#requires -Version 7.0
<#
  打包发布工作流 · Thunderstore 上传阶段。

  按 plan.json 的顺序（Framework 在前）逐个把 dist 里的 zip 传到 Thunderstore：

    1. POST /usermedia/initiate-upload/   用文件名和大小换预签名分片地址
    2. 逐片 PUT（带 Content-MD5），从响应头取 ETag
    3. POST /usermedia/{uuid}/finish-upload/
    4. POST /submission/submit/           提交包（社区与分类来自仓库根的 thunderstore.json）

  每个包上传失败就立刻停下（前面的包可能已经进了 Thunderstore，无法撤回，
  只能升版本号重发），所以顺序是先 Framework 后玩法包。

  环境变量：
    THUNDERSTORE_TOKEN   Service Account token（tss_...），来自仓库 Secret
    WORK_ROOT            可选，默认 .publish
#>

. (Join-Path $PSScriptRoot 'common.ps1')

$workRoot = if ($env:WORK_ROOT) { $env:WORK_ROOT } else { '.publish' }
$plan = Get-Plan -WorkRoot $workRoot
$distDir = Join-Path $workRoot 'dist'

$config = $plan.thunderstore
if (-not $config -or -not $config.enabled) {
    Write-Host '本次没有启用 Thunderstore 上传，跳过。'
    exit 0
}
if ($plan.dryRun) {
    Write-Host '演练模式，不上传 Thunderstore。'
    exit 0
}
if (-not $plan.publish) {
    Write-Host 'Release 保持草稿，不上传 Thunderstore。'
    exit 0
}

$token = [string]$env:THUNDERSTORE_TOKEN
if (-not $token) {
    Fail '缺少环境变量 THUNDERSTORE_TOKEN。' @(
        '在仓库 Settings → Secrets and variables → Actions 里新建 secret「THUNDERSTORE_TOKEN」，值填团队 Service Account 的 tss_... token。',
        '没有 token 的话：thunderstore.io → 右上角头像 → Settings → Teams → 你的团队 → Service accounts → Create service account（明文只显示一次）。'
    )
}

$community = [string]$config.community
$authorName = [string]$config.authorName
$hasNsfw = [bool]$config.hasNsfwContent
$apiBase = 'https://thunderstore.io/api/experimental'

$authHeaders = @{
    Authorization = "Bearer $token"
    Accept        = 'application/json'
}

$http = [System.Net.Http.HttpClient]::new()
$http.Timeout = [TimeSpan]::FromMinutes(10)

function Send-Api {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('GET', 'POST')][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        $Body
    )

    $params = @{
        Method             = $Method
        Uri                = "$apiBase$Path"
        Headers            = $authHeaders
        SkipHttpErrorCheck = $true
        StatusCodeVariable = 'statusCode'
        TimeoutSec         = 120
    }
    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
        $params.Body = ($Body | ConvertTo-Json -Depth 8 -Compress)
        $params.ContentType = 'application/json'
    }

    try {
        $data = Invoke-RestMethod @params
    }
    catch {
        # 连不上（DNS/TLS/超时）也算失败，交给调用方统一报错
        return [pscustomobject]@{ Status = 0; Ok = $false; Data = $null; Raw = "网络错误：$($_.Exception.Message)" }
    }

    $code = [int]$statusCode
    return [pscustomobject]@{
        Status = $code
        Ok     = ($code -ge 200 -and $code -lt 300)
        Data   = $data
        Raw    = if ($data -is [string]) { $data } else { $data | ConvertTo-Json -Depth 8 -Compress }
    }
}

function Format-ApiError {
    param([Parameter(Mandatory = $true)]$Response)

    if ([int]$Response.Status -le 0) { return [string]$Response.Raw }
    return "HTTP $($Response.Status) $($Response.Raw)"
}

function Send-UserMedia {
    <#
      把文件分片传上去，返回 usermedia 的 uuid。失败时先 abort 再抛错。
    #>
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$FileName
    )

    $bytes = [System.IO.File]::ReadAllBytes($ZipPath)
    if ($bytes.Length -eq 0) { throw "$FileName 是空文件。" }

    $init = Send-Api -Method POST -Path '/usermedia/initiate-upload/' -Body ([ordered]@{
            filename        = $FileName
            file_size_bytes = $bytes.Length
        })
    if (-not $init.Ok) {
        throw "initiate-upload 失败：$(Format-ApiError $init)"
    }

    $uuid = [string]$init.Data.user_media.uuid
    $urls = @($init.Data.upload_urls)
    if (-not $uuid -or $urls.Count -eq 0) { throw "initiate-upload 返回的内容不完整：$($init.Raw)" }

    $parts = [System.Collections.Generic.List[object]]::new()
    try {
        foreach ($url in $urls) {
            $offset = [int64]$url.offset
            $length = [int64]$url.length
            if ($offset -lt 0 -or $length -le 0 -or ($offset + $length) -gt $bytes.Length) {
                throw "分片范围越界（offset=$offset, length=$length, 文件 $($bytes.Length) 字节）。"
            }

            $slice = if ($offset -eq 0 -and $length -eq $bytes.Length) {
                $bytes
            }
            else {
                $buffer = [byte[]]::new($length)
                [System.Array]::Copy($bytes, $offset, $buffer, 0, $length)
                $buffer
            }

            # S3 预签名 PUT 要求 Content-MD5；不要额外带 Content-Type，避免签名不匹配。
            $content = [System.Net.Http.ByteArrayContent]::new($slice)
            $content.Headers.Add('Content-MD5', [Convert]::ToBase64String([System.Security.Cryptography.MD5]::HashData($slice)))

            $response = $http.PutAsync([string]$url.url, $content).GetAwaiter().GetResult()
            if (-not $response.IsSuccessStatusCode) {
                $bodyText = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                throw "分片 $($url.part_number) 上传失败：HTTP $([int]$response.StatusCode) $bodyText"
            }

            $etag = $response.Headers.ETag
            if (-not $etag) { throw "分片 $($url.part_number) 上传后没有返回 ETag。" }
            $parts.Add([ordered]@{ ETag = $etag.Tag; PartNumber = [int]$url.part_number })
        }

        $finish = Send-Api -Method POST -Path "/usermedia/$uuid/finish-upload/" -Body ([ordered]@{ parts = @($parts) })
        if (-not $finish.Ok) { throw "finish-upload 失败：$(Format-ApiError $finish)" }
    }
    catch {
        $message = $_.Exception.Message
        try { $null = Send-Api -Method POST -Path "/usermedia/$uuid/abort-upload/" } catch { }
        throw $message
    }

    return $uuid
}

# ---------------------------------------------------------------- 逐个上传
$metaFiles = @(Get-ChildItem -LiteralPath $distDir -Filter '*.meta.json' -File)
if ($metaFiles.Count -eq 0) {
    Fail "在 $distDir 里没有找到任何 *.meta.json，无法确定要上传哪些压缩包。" @('重新运行整个工作流。')
}
$metas = @($metaFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8 | ConvertFrom-Json })

$results = [System.Collections.Generic.List[object]]::new()

foreach ($package in @($plan.packages)) {
    $meta = @($metas | Where-Object { $_.project -eq $package.project }) | Select-Object -First 1
    if (-not $meta) { Fail "缺少 $($package.project) 的打包结果（*.meta.json）。" }

    $zipPath = Join-Path $distDir $meta.zip
    if (-not (Test-Path -LiteralPath $zipPath)) { Fail "找不到压缩包 $($meta.zip)。" }

    $categories = @($package.categories | Where-Object { $_ })
    Write-Host ''
    Write-Host "上传 $($meta.zip)（$($meta.size) 字节，分类：$(if ($categories.Count -gt 0) { $categories -join '、' } else { '无' })）……"

    try {
        $uuid = Send-UserMedia -ZipPath $zipPath -FileName $meta.zip
    }
    catch {
        Fail "上传 $($meta.zip) 到 Thunderstore 失败。" @(
            $_.Exception.Message,
            '若提示 401，检查 THUNDERSTORE_TOKEN 是否是有效的 tss_ 开头 token；若提示 403，检查 token 是否属于目标团队。'
        )
    }

    $submitBody = [ordered]@{
        author_name      = $authorName
        communities      = @($community)
        has_nsfw_content = $hasNsfw
        upload_uuid      = $uuid
    }
    if ($categories.Count -gt 0) {
        $categoryMap = [ordered]@{}
        $categoryMap[$community] = @($categories)
        $submitBody.community_categories = $categoryMap
    }

    $submit = Send-Api -Method POST -Path '/submission/submit/' -Body $submitBody
    if (-not $submit.Ok) {
        Fail "提交 $($meta.zip) 到 Thunderstore 失败。" @(
            "响应：$(Format-ApiError $submit)",
            '常见原因：这个版本号已经发布过（必须升 version_number）、token 不属于目标团队、分类 slug 在该社区不存在。'
        )
    }

    $packageUrl = ''
    $available = @($submit.Data.available_communities)
    if ($available.Count -gt 0) { $packageUrl = [string]$available[0].url }

    Write-Host "✅ $($meta.zip) 已提交$(if ($packageUrl) { "：$packageUrl" })"

    $results.Add([pscustomobject]@{
            project    = $package.project
            version    = $package.version
            zip        = $meta.zip
            categories = $categories
            url        = $packageUrl
        })
}

# ---------------------------------------------------------------- 汇总
$summary = @(
    '## 🚀 Thunderstore 上传完成'
    ''
    "- 社区：``$community``（作者：``$authorName``）"
    ''
    '| 项目 | 版本 | 压缩包 | 分类 | 页面 |'
    '| --- | --- | --- | --- | --- |'
)
foreach ($row in $results) {
    $catCell = if ($row.categories.Count -gt 0) { $row.categories -join '、' } else { '—' }
    $urlCell = if ($row.url) { "[打开]($($row.url))" } else { '—' }
    $summary += "| $($row.project) | $($row.version) | ``$($row.zip)`` | $catCell | $urlCell |"
}
$summary += ''
$summary += '> Thunderstore 上的包可能需要几分钟才能在社区页面看到；确认依赖能正确解析，再通知玩家更新。'
Add-Summary -Lines $summary

Write-Host ''
Write-Host "已上传 $($results.Count) 个包到 Thunderstore（$community）。"
foreach ($row in $results) { Write-Host "  $($row.project) $($row.version) → $($row.zip)" }
