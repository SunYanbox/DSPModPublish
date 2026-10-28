#requires -Version 7.0
<#
  打包发布工作流 · 发布阶段。

  把各包目录产出的 zip 上传到源 Release（草稿 Release 就是上传区），改写 tag 与
  标题，然后按 publish 决定是保留草稿还是正式发布。dry_run 时只汇报、不写。

  环境变量：
    GITHUB_REPOSITORY / GH_TOKEN
    WORK_ROOT（可选，默认 .publish）
#>

. (Join-Path $PSScriptRoot 'common.ps1')

$repo = $env:GITHUB_REPOSITORY
if (-not $repo) { Fail '缺少环境变量 GITHUB_REPOSITORY。' }
if (-not $env:GH_TOKEN) { Fail '缺少环境变量 GH_TOKEN（工作流里应为 secrets.GITHUB_TOKEN）。' }

$workRoot = if ($env:WORK_ROOT) { $env:WORK_ROOT } else { '.publish' }
$plan = Get-Plan -WorkRoot $workRoot
$distDir = Join-Path $workRoot 'dist'

$headers = @{
    Authorization          = "Bearer $($env:GH_TOKEN)"
    Accept                 = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
}
$apiBase = "https://api.github.com/repos/$repo"
$uploadBase = "https://uploads.github.com/repos/$repo"

# ---------------------------------------------------------------- 收集压缩包
$metaFiles = @(Get-ChildItem -LiteralPath $distDir -Filter '*.meta.json' -File)
if ($metaFiles.Count -eq 0) {
    Fail "在 $distDir 里没有找到任何 *.meta.json，无法确认要上传哪些压缩包。" @('这是工作流产出的临时目录，重新运行整个工作流。')
}

$metas = @($metaFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8 | ConvertFrom-Json })

$orderedMetas = @()
foreach ($package in $plan.packages) {
    $meta = @($metas | Where-Object { $_.project -eq $package.project }) | Select-Object -First 1
    if (-not $meta) { Fail "缺少 $($package.project) 的打包结果（*.meta.json）。" }
    $orderedMetas += $meta
}

if ($orderedMetas.Count -ne @($plan.packages).Count) {
    Fail "压缩包数量和计划不一致：计划 $(@($plan.packages).Count) 个，实际 $($orderedMetas.Count) 个。"
}

$missingZip = @($orderedMetas | Where-Object { -not (Test-Path -LiteralPath (Join-Path $distDir $_.zip)) })
if ($missingZip.Count -gt 0) {
    Fail "以下压缩包不见了：$($missingZip.zip -join '、')"
}

foreach ($meta in $orderedMetas) {
    $zipPath = Join-Path $distDir $meta.zip
    $actualSha = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $actualSize = (Get-Item -LiteralPath $zipPath).Length
    if ($actualSha -ne $meta.sha256) { Fail "$($meta.zip) 的 SHA256 与打包阶段不一致。" @("期望 $($meta.sha256)", "实际 $actualSha") }
    if ($actualSize -ne [int64]$meta.size) { Fail "$($meta.zip) 的大小与打包阶段不一致。" }
}

# ---------------------------------------------------------------- 冲突与 tag 检查
$assetLines = Get-GhJsonLines "repos/$repo/releases/$($plan.sourceReleaseId)/assets?per_page=100"
$existingAssets = @($assetLines | ForEach-Object { $_ | ConvertFrom-Json })

$conflicts = @(foreach ($meta in $orderedMetas) {
        $existing = @($existingAssets | Where-Object { $_.name -ieq $meta.zip }) | Select-Object -First 1
        if ($existing) { [pscustomobject]@{ name = $meta.zip; id = $existing.id; size = $existing.size } }
    })

$tagExists = Test-TagExists -Repo $repo -Tag $plan.tag
$blocking = @()
if ($tagExists -and -not $plan.overwrite) {
    $blocking += "tag 已存在：$($plan.tag)（发版必须升 version_number；修复场景才用 overwrite）"
}
if ($conflicts.Count -gt 0 -and -not $plan.overwrite) {
    $blocking += "Release 里已有同名压缩包：$($conflicts.name -join '、')（修复场景才用 overwrite）"
}

$mode = if ($plan.dryRun) { '演练（不写 Release）' } elseif (-not $plan.publish) { '保留草稿' } else { '正式发布' }

if ($plan.dryRun) {
    $zipList = (@($orderedMetas | ForEach-Object { "``$($_.zip)``" }) -join '、')
    $dryLines = @(
        '## 🧪 演练结果（没有写 Release）'
        ''
        "- 目标 tag：``$($plan.tag)``"
        "- 要上传的压缩包：$zipList"
        ''
    )
    if ($blocking.Count -gt 0) {
        $dryLines += '真跑会被拦下：'
        $dryLines += ''
        foreach ($item in $blocking) { $dryLines += "- $item" }
    }
    else {
        $dryLines += '✅ 真跑不会被拦下。'
    }
    $dryLines += ''
    $dryLines += '各包的详情与 Artifacts 见上面的 job 汇总。'
    Add-Summary -Lines $dryLines

    Write-Host "演练模式：目标 tag = $($plan.tag)"
    foreach ($item in $blocking) { Write-Host "::warning::$item" }
    foreach ($meta in $orderedMetas) { Write-Host "将上传 $($meta.zip)（$($meta.size) 字节）" }
    exit 0
}

if ($blocking.Count -gt 0) {
    Fail $blocking[0] @($blocking | Select-Object -Skip 1)
}

# ---------------------------------------------------------------- 上传
foreach ($meta in $orderedMetas) {
    $zipPath = Join-Path $distDir $meta.zip
    $existing = @($existingAssets | Where-Object { $_.name -ieq $meta.zip }) | Select-Object -First 1

    if ($existing) {
        Write-Host "删除旧资产 $($meta.zip)（id $($existing.id)）"
        Invoke-RestMethod -Method Delete -Uri "$apiBase/releases/assets/$($existing.id)" -Headers $headers | Out-Null
    }

    $encodedName = [uri]::EscapeDataString($meta.zip)
    Write-Host "上传 $($meta.zip)（$($meta.size) 字节）"
    try {
        $asset = Invoke-RestMethod -Method Post `
            -Uri "$uploadBase/releases/$($plan.sourceReleaseId)/assets?name=$encodedName" `
            -Headers $headers -ContentType 'application/zip' -InFile $zipPath -TimeoutSec 300
    }
    catch {
        Fail "上传 $($meta.zip) 失败。" @($_.Exception.Message, '若提示 404/403，检查工作流的 permissions 是否为 contents: write。')
    }

    if (-not $asset -or $asset.name -ne $meta.zip) {
        Fail "上传 $($meta.zip) 后返回的信息不对。"
    }
    if ([int64]$asset.size -ne [int64]$meta.size) {
        Fail "上传后的 $($meta.zip) 大小不对：期望 $($meta.size)，实际 $($asset.size)。"
    }
}

# ---------------------------------------------------------------- 改写 Release
$bodyLines = @(
    '## 压缩包'
    ''
    '| 项目 | manifest name | 版本 | 压缩包 | SHA256 |'
    '| --- | --- | --- | --- | --- |'
)
foreach ($meta in $orderedMetas) {
    $bodyLines += "| $($meta.project) | ``$($meta.manifestName)`` | $($meta.version) | ``$($meta.zip)`` | ``$($meta.sha256.Substring(0, 12))…`` |"
}
$bodyLines += ''
$bodyLines += '上面的 `.dll` 是各插件的本体，`.zip` 是直接上传 Thunderstore 的压缩包，两者内容一致。'
$bodyLines += ''
if ($plan.prevTag) {
    $bodyLines += "**Full Changelog**：https://github.com/$repo/compare/$([uri]::EscapeDataString($plan.prevTag))...$([uri]::EscapeDataString($plan.tag))"
    $bodyLines += ''
}
$bodyLines += "由「打包并发布 Release」工作流生成 · [运行记录]($($plan.runUrl))"
$bodyText = $bodyLines -join "`n"

$current = Invoke-RestMethod -Method Get -Uri "$apiBase/releases/$($plan.sourceReleaseId)" -Headers $headers
$existingBody = [string]$current.body
$keepExistingBody = ($existingBody.Trim().Length -gt 0) -and ($existingBody -notmatch '由「打包并发布 Release」工作流生成')

$patchBody = [ordered]@{
    tag_name = $plan.tag
    name     = $plan.tag
    draft    = -not $plan.publish
}
if (-not $keepExistingBody) { $patchBody.body = $bodyText }
if ($plan.sourceIsDraft -and $plan.headSha) { $patchBody.target_commitish = $plan.headSha }

if ($keepExistingBody) {
    Write-Host '检测到 Release 里已有手写正文，保留原正文不改写。'
}

$release = Invoke-RestMethod -Method Patch -Uri "$apiBase/releases/$($plan.sourceReleaseId)" `
    -Headers $headers -Body ($patchBody | ConvertTo-Json -Depth 5) -ContentType 'application/json'

if ($release.tag_name -ne $plan.tag) {
    Fail "改写 tag 失败：期望 $($plan.tag)，实际 $($release.tag_name)。"
}
if ([bool]$release.draft -ne (-not $plan.publish)) {
    Fail "发布状态不对：期望 draft=$(-not $plan.publish)，实际 draft=$($release.draft)。"
}

# ---------------------------------------------------------------- 回读确认
$verifyLines = Get-GhJsonLines "repos/$repo/releases/$($plan.sourceReleaseId)/assets?per_page=100"
$verifyAssets = @($verifyLines | ForEach-Object { $_ | ConvertFrom-Json })
$missingAssets = @(foreach ($meta in $orderedMetas) {
        $found = @($verifyAssets | Where-Object { $_.name -ieq $meta.zip -and [int64]$_.size -eq [int64]$meta.size })
        if ($found.Count -eq 0) { $meta.zip }
    })
if ($missingAssets.Count -gt 0) {
    Fail "上传后回读不到这些资产：$($missingAssets -join '、')"
}

# ---------------------------------------------------------------- 汇总
$releaseUrl = if ($plan.publish) { [string]$release.html_url } else { "https://github.com/$repo/releases/edit/$([uri]::EscapeDataString($plan.tag))" }
Add-Summary -Lines @(
    "## 🚀 $mode"
    ''
    "- Release：[$($plan.tag)]($releaseUrl)"
    "- 状态：$(if ($plan.publish) { '已发布' } else { '草稿（等你在网页点 Publish release）' })"
    "- 正文：$(if ($keepExistingBody) { '保留原有手写内容' } else { '已用工作流生成的内容更新' })"
    ''
    '| 项目 | 版本 | 压缩包 | 大小 |'
    '| --- | --- | --- | --- |'
) 

$assetRows = @(foreach ($meta in $orderedMetas) {
        "| $($meta.project) | $($meta.version) | ``$($meta.zip)`` | $([math]::Round([int64]$meta.size / 1KB, 1)) KB |"
    })
Add-Summary -Lines $assetRows

Add-Summary -Lines @(
    ''
    $(if ($plan.thunderstore -and $plan.thunderstore.enabled) {
            '> 下一步：紧随其后的「上传 Thunderstore」job 会把这些 zip 传上去，完成后确认依赖能正确解析。'
        }
        else {
            '> 下一步：把同名的 `.zip` 传到 [Thunderstore](https://thunderstore.io/c/dyson-sphere-program/)，确认依赖能解析。'
        })
)

Write-Host ''
Write-Host "Release：$($plan.tag) → $releaseUrl"
Write-Host "状态    ：$(if ($plan.publish) { '已发布' } else { '草稿' })"
Write-Host "资产    ：$(@($orderedMetas.zip) -join '、')"
