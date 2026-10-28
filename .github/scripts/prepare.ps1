#requires -Version 7.0
<#
  打包发布工作流 · 准备阶段。

  从草稿 Release（当上传区用）取回 DLL，按文件名映射到包目录，校验包内容，
  算出本次 Release 的 tag，并写出打包矩阵与 plan.json。

  输入全部来自环境变量（workflow_dispatch 的 inputs）：
    INPUT_PROJECTS              auto | all | "目录名,目录名"
    INPUT_MAPPING               "dll文件名=包目录名" 每行一条
    INPUT_SOURCE_RELEASE        源 Release 的 tag；留空取最新草稿
    INPUT_DRY_RUN/INPUT_OVERWRITE/INPUT_PUBLISH/INPUT_SKIP_DEPENDENCY_CHECK
#>

. (Join-Path $PSScriptRoot 'common.ps1')

# ---------------------------------------------------------------- 输入
$repo = $env:GITHUB_REPOSITORY
if (-not $repo) { Fail '缺少环境变量 GITHUB_REPOSITORY。' }
if (-not $env:GH_TOKEN) { Fail '缺少环境变量 GH_TOKEN（工作流里应为 secrets.GITHUB_TOKEN）。' }

$workRoot = if ($env:WORK_ROOT) { $env:WORK_ROOT } else { '.publish' }
$stagingDir = Join-Path $workRoot 'staging'
$incomingDir = Join-Path $stagingDir 'incoming'

$projectsInput = if ($env:INPUT_PROJECTS) { ([string]$env:INPUT_PROJECTS).Trim() } else { 'auto' }
if (-not $projectsInput) { $projectsInput = 'auto' }
$mappingInput = [string]$env:INPUT_MAPPING
$sourceInput = ([string]$env:INPUT_SOURCE_RELEASE).Trim()
$dryRun = $env:INPUT_DRY_RUN -eq 'true'
$overwrite = $env:INPUT_OVERWRITE -eq 'true'
$publish = $env:INPUT_PUBLISH -eq 'true'
$skipDependencyCheck = $env:INPUT_SKIP_DEPENDENCY_CHECK -eq 'true'

$mode = if ($dryRun) { '演练（只打包，不写 Release）' }
elseif (-not $publish) { '打包并保留草稿（待网页手动发布）' }
else { '打包并发布' }

$warnings = [System.Collections.Generic.List[string]]::new()
$headers = @{
    Authorization          = "Bearer $($env:GH_TOKEN)"
    Accept                 = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
}

# ---------------------------------------------------------------- 包目录
$root = (Get-Location).Path
$projectDirs = @(Get-ChildItem -LiteralPath $root -Directory | Where-Object {
        $_.Name -notlike '.*' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'manifest.json'))
    } | Sort-Object -Property Name)

if ($projectDirs.Count -eq 0) {
    Fail "仓库根目录下没有找到任何带 manifest.json 的包目录：$root" @(
        '确认 checkout 的是 main 分支，且工作目录是仓库根目录。'
    )
}

$projects = @(foreach ($dir in $projectDirs) {
        $manifestPath = Join-Path $dir.FullName 'manifest.json'
        try {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
        }
        catch {
            Fail "无法解析 $($dir.Name)/manifest.json：$($_.Exception.Message)"
        }

        $missingKeys = @(foreach ($key in 'name', 'version_number', 'description', 'website_url', 'dependencies') {
                if ($manifest.PSObject.Properties.Name -notcontains $key) { $key }
            })
        if ($missingKeys.Count -gt 0) {
            Fail "$($dir.Name)/manifest.json 缺少字段：$($missingKeys -join '、')"
        }

        $manifestName = [string]$manifest.name
        $version = [string]$manifest.version_number
        if ($manifestName -notmatch '^[A-Za-z0-9_]+$') {
            Fail "$($dir.Name)/manifest.json 的 name「$manifestName」不是 Thunderstore 合法格式（只允许英文字母、数字、下划线）。"
        }
        if ($version -notmatch '^\d+\.\d+\.\d+$') {
            Fail "$($dir.Name)/manifest.json 的 version_number「$version」不是 x.y.z 格式。"
        }

        $short = ($manifestName -replace '^DSPEasy_', '') -replace '_', '-'
        [pscustomobject]@{
            DirName      = $dir.Name
            FullName     = $dir.FullName
            Manifest     = $manifest
            Name         = $manifestName
            Version      = $version
            Short        = $short
        }
    })

$frameworkProject = @($projects | Where-Object { $_.Name -eq 'DSPEasy_Framework' }) | Select-Object -First 1
$frameworkVersion = if ($frameworkProject) { $frameworkProject.Version } else { $null }

# ---------------------------------------------------------------- 源 Release
$releaseLines = Get-GhJsonLines "repos/$repo/releases?per_page=100"
$releases = @($releaseLines | ForEach-Object { $_ | ConvertFrom-Json })

$source = $null
if ($sourceInput) {
    $source = @($releases | Where-Object { $_.tag_name -eq $sourceInput }) | Select-Object -First 1
    if (-not $source) {
        $available = @($releases | Select-Object -First 10 -ExpandProperty tag_name) -join '、'
        Fail "找不到 tag 为「$sourceInput」的 Release。" @(
            "最近可用的 Release：$available",
            'source_release 要填 Release 的 tag（不是 Release 标题）。留空则自动使用最新的草稿 Release。'
        )
    }
}
else {
    $drafts = @($releases | Where-Object { $_.draft } | Sort-Object -Property { [datetime]$_.created_at } -Descending)
    if ($drafts.Count -eq 0) {
        Fail '没有找到任何草稿 Release，也没有填 source_release。' @(
            '先在这个仓库的 Releases 页面新建一个草稿 Release，把这次的 DLL 拖进它的 assets，然后重新运行工作流。',
            "草稿 Release 地址：https://github.com/$repo/releases"
        )
    }
    $source = $drafts[0]
    if ($drafts.Count -gt 1) {
        $warnings.Add("有 $($drafts.Count) 个草稿 Release，已选用最新创建的「$($source.tag_name)」；要指定别的请填 source_release。")
    }
}

$sourceIsDraft = [bool]$source.draft
$sourceUrl = if ($sourceIsDraft) { "https://github.com/$repo/releases/edit/$([uri]::EscapeDataString($source.tag_name))" } else { [string]$source.html_url }

# ---------------------------------------------------------------- DLL 资产
$assetLines = Get-GhJsonLines "repos/$repo/releases/$($source.id)/assets?per_page=100"
$assets = @($assetLines | ForEach-Object { $_ | ConvertFrom-Json })
$dllAssets = @($assets | Where-Object { $_.name -match '(?i)\.dll$' } | Sort-Object -Property name)

if ($dllAssets.Count -eq 0) {
    Fail "源 Release「$($source.tag_name)」里没有 .dll 资产。" @(
        "打开 $sourceUrl ，把这次的 DLL 拖进 assets 后重新运行工作流。",
        '（GitHub Actions 的 workflow_dispatch 表单不能选文件，所以 DLL 统一放在草稿 Release 里传。）'
    )
}

$ignoredAssets = @($assets | Where-Object { $_.name -notmatch '(?i)\.dll$' })
if ($ignoredAssets.Count -gt 0) {
    $warnings.Add("源 Release 里的非 DLL 资产已忽略：$($ignoredAssets.name -join '、')")
}

if (Test-Path -LiteralPath $incomingDir) { Remove-Item -LiteralPath $incomingDir -Recurse -Force }
New-Item -ItemType Directory -Path $incomingDir -Force | Out-Null

$dlls = @(foreach ($asset in $dllAssets) {
        $dest = Join-Path $incomingDir $asset.name
        Write-Host "下载资产 $($asset.name) ……"

        # 资产直链要 Accept: application/octet-stream，否则 API 返回的是 JSON 元数据；
        # 公开仓库再用 browser_download_url 兜底一次。
        $candidates = @(
            @{
                Label   = 'assets API（application/octet-stream）'
                Uri     = "https://api.github.com/repos/$repo/releases/assets/$($asset.id)"
                Headers = @{
                    Authorization          = "Bearer $($env:GH_TOKEN)"
                    Accept                 = 'application/octet-stream'
                    'X-GitHub-Api-Version' = '2022-11-28'
                }
            }
            @{
                Label   = 'browser_download_url'
                Uri     = [string]$asset.browser_download_url
                Headers = @{}
            }
        )

        $downloaded = $false
        $lastError = ''
        foreach ($candidate in $candidates) {
            if (-not $candidate.Uri) { continue }
            try {
                Invoke-WebRequest -Uri $candidate.Uri -Headers $candidate.Headers -OutFile $dest `
                    -MaximumRetryCount 2 -RetryIntervalSec 3 -TimeoutSec 180
            }
            catch {
                $lastError = "$($candidate.Label)：$($_.Exception.Message)"
                continue
            }

            $gotSize = (Get-Item -LiteralPath $dest).Length
            if ($gotSize -gt 0 -and (-not $asset.size -or $gotSize -eq [int64]$asset.size)) {
                $downloaded = $true
                break
            }
            $lastError = "$($candidate.Label) 返回 $gotSize 字节，Release 里记录的是 $($asset.size) 字节"
        }

        if (-not $downloaded) {
            Fail "下载 DLL 失败：$($asset.name)" @($lastError, "资产地址：$sourceUrl")
        }

        [pscustomobject]@{
            Name       = [string]$asset.name
            Path       = $dest
            Size       = (Get-Item -LiteralPath $dest).Length
            Sha256     = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLowerInvariant()
            AssignedTo = ''
        }
    })

if ($dlls.Count -lt 1) { Fail '没有取到任何 DLL。' }

# ---------------------------------------------------------------- 映射
function ConvertTo-MatchKey {
    param([Parameter(Mandatory = $true)][string]$Value)

    $key = $Value -replace '(?i)\.dll$', ''
    $key = $key -replace '[._\-]+', '.'
    return $key.Trim('.').ToLowerInvariant()
}

$byProject = @{}
foreach ($project in $projects) { $byProject[$project.DirName] = [System.Collections.Generic.List[object]]::new() }

function Get-ProjectByKey {
    param([Parameter(Mandatory = $true)][string]$Key)

    return @($projects | Where-Object { $_.DirName -ieq $Key -or $_.Name -ieq $Key }) | Select-Object -First 1
}

$mappingLines = @()
if (-not [string]::IsNullOrWhiteSpace($mappingInput)) {
    $mappingLines = @($mappingInput -split "\r?\n" |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith('#') })
}

foreach ($line in $mappingLines) {
    $separator = $line.IndexOf('=')
    if ($separator -lt 1) {
        Fail "mapping 的这一行格式不对：「$line」" @('每行应为 `DSPEasy.Buildings.dll=DSPEasy.Buildings`：等号左边是上传的 DLL 文件名，右边是包目录名或 manifest 里的 name。')
    }

    $dllKey = $line.Substring(0, $separator).Trim()
    $projectKey = $line.Substring($separator + 1).Trim()

    $dll = @($dlls | Where-Object { $_.Name -ieq $dllKey }) | Select-Object -First 1
    if (-not $dll) {
        $normalized = ConvertTo-MatchKey $dllKey
        $dll = @($dlls | Where-Object { (ConvertTo-MatchKey $_.Name) -eq $normalized }) | Select-Object -First 1
    }
    if (-not $dll) {
        Fail "mapping 里写的 DLL「$dllKey」不在源 Release 中。" @("源 Release 里的 DLL：$($dlls.Name -join '、')")
    }

    $project = Get-ProjectByKey $projectKey
    if (-not $project) {
        Fail "mapping 里写的项目「$projectKey」没有对应的包目录。" @("可用的包目录：$($projects.DirName -join '、')")
    }

    if ($dll.AssignedTo) {
        if ($dll.AssignedTo -ne $project.DirName) {
            Fail "mapping 把 $($dll.Name) 指到了两个项目：$($dll.AssignedTo) 和 $($project.DirName)。"
        }
        continue
    }

    $dll.AssignedTo = $project.DirName
    $byProject[$project.DirName].Add($dll)
    Write-Host "手动映射：$($dll.Name) → $($project.DirName)"
}

# 自动映射：DLL 文件名（去扩展名、把 . _ - 归一成 .）对上包目录名或 manifest name
foreach ($dll in $dlls) {
    if ($dll.AssignedTo) { continue }

    $key = ConvertTo-MatchKey $dll.Name
    $candidates = @($projects | Where-Object {
            (ConvertTo-MatchKey $_.DirName) -eq $key -or (ConvertTo-MatchKey $_.Name) -eq $key
        })

    if ($candidates.Count -gt 1) {
        Fail "DLL 名字 $($dll.Name) 同时匹配多个包目录：$($candidates.DirName -join '、')" @('在 mapping 输入里显式指定它属于哪个项目。')
    }
    if ($candidates.Count -eq 0) { continue }

    $dll.AssignedTo = $candidates[0].DirName
    $byProject[$candidates[0].DirName].Add($dll)
    Write-Host "自动映射：$($dll.Name) → $($candidates[0].DirName)"
}

$unmapped = @($dlls | Where-Object { -not $_.AssignedTo })
if ($unmapped.Count -gt 0) {
    $warnings.Add("这些 DLL 没有对上任何包目录，已忽略：$($unmapped.Name -join '、')（需要时用 mapping 输入指定）")
}

# ---------------------------------------------------------------- 选中项目
$selected = @()
if ($projectsInput -ieq 'auto') {
    $selected = @($projects | Where-Object { $byProject[$_.DirName].Count -gt 0 })
    if ($selected.Count -eq 0) {
        Fail '这些 DLL 没有一个能对上包目录，auto 模式下没有可打包的项目。' @(
            "源 Release 里的 DLL：$($dlls.Name -join '、')",
            "仓库里的包目录：$($projects.DirName -join '、')",
            '如果文件名和包目录确实对不上，用 mapping 输入手动指定，或把 projects 填成具体项目名。'
        )
    }
}
elseif ($projectsInput -ieq 'all') {
    $selected = @($projects)
}
else {
    $requested = @($projectsInput -split '[,，\s]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($item in $requested) {
        $match = Get-ProjectByKey $item
        if (-not $match) {
            Fail "projects 里写的「$item」没有对应的包目录。" @("可用的包目录：$($projects.DirName -join '、')")
        }
        $selected += $match
    }
}

$seenDirs = @{}
$selected = @($selected | Where-Object {
        if ($seenDirs.ContainsKey($_.DirName)) { return $false }
        $seenDirs[$_.DirName] = $true
        return $true
    })

# 规范顺序：Framework 先发，其余按目录名；这样 tag 里玩法包总在 Framework 之后
$priority = @{ 'DSPEasy.Framework' = 0 }
$selected = @($selected | Sort-Object -Property `
        @{ Expression = { if ($priority.ContainsKey($_.DirName)) { [int]$priority[$_.DirName] } else { 10 } } }, `
        @{ Expression = { $_.DirName } })

$missingDll = @($selected | Where-Object { $byProject[$_.DirName].Count -eq 0 })
if ($missingDll.Count -gt 0) {
    Fail "以下项目被选中，但没有对应的 DLL：$($missingDll.DirName -join '、')" @(
        "源 Release 里已上传的 DLL：$($dlls.Name -join '、')",
        '把缺的 DLL 传进同一个 Release 后重新运行；或从 projects 里去掉这些项目。'
    )
}

# ---------------------------------------------------------------- 校验包内容
function Assert-IconPng {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ProjectName
    )

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 24) { Fail "$ProjectName/icon.png 是损坏的 PNG（文件太短）。" }

    $signature = @(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
    for ($i = 0; $i -lt $signature.Count; $i++) {
        if ($bytes[$i] -ne $signature[$i]) { Fail "$ProjectName/icon.png 不是 PNG 文件（文件头不对）。" }
    }

    $width = [int64]$bytes[16] * 16777216 + [int64]$bytes[17] * 65536 + [int64]$bytes[18] * 256 + [int64]$bytes[19]
    $height = [int64]$bytes[20] * 16777216 + [int64]$bytes[21] * 65536 + [int64]$bytes[22] * 256 + [int64]$bytes[23]
    if ($width -ne 256 -or $height -ne 256) {
        Fail "$ProjectName/icon.png 是 ${width}×${height}，Thunderstore 要求 256×256。"
    }
}

foreach ($project in $selected) {
    foreach ($required in 'icon.png', 'README.md', 'CHANGELOG.md') {
        $path = Join-Path $project.FullName $required
        if (-not (Test-Path -LiteralPath $path)) { Fail "$($project.DirName) 缺少 $required。" }
        if ((Get-Item -LiteralPath $path).Length -eq 0) { Fail "$($project.DirName)/$required 是空文件。" }
    }
    Assert-IconPng -Path (Join-Path $project.FullName 'icon.png') -ProjectName $project.DirName

    $frameworkDeps = @($project.Manifest.dependencies | Where-Object { $_ -match '^Suntion-DSPEasy_Framework-' })
    if ($project.Name -eq 'DSPEasy_Framework') {
        if ($frameworkDeps.Count -gt 0) {
            Fail 'Framework 包不应该依赖自己（manifest 里出现了 Suntion-DSPEasy_Framework-* 依赖）。'
        }
        continue
    }

    if (-not $skipDependencyCheck -and $frameworkVersion) {
        if ($frameworkDeps.Count -eq 0) {
            $expectedDependency = "Suntion-DSPEasy_Framework-$frameworkVersion"
            Fail "$($project.DirName)/manifest.json 没有把 Framework 写成依赖。" @(
                "当前仓库里 Framework 的版本是 $frameworkVersion，dependencies 里应包含 `"$expectedDependency`"。"
            )
        }
        $declaredVersion = [string]($frameworkDeps[0] -replace '^Suntion-DSPEasy_Framework-', '')
        if ($declaredVersion -ne $frameworkVersion) {
            Fail "$($project.DirName) 依赖的 Framework 版本是 $declaredVersion，但仓库里的 Framework 是 $frameworkVersion。" @(
                '按 AGENTS.md：Framework 升版时必须同步两个玩法包的 manifest 依赖，三个包一起发（先 Framework）。',
                '确实只是先发玩法包、暂不升 Framework 时，可以勾选 skip_dependency_check。'
            )
        }
    }
}

# ---------------------------------------------------------------- tag 与重复检查
$tag = ($selected | ForEach-Object { "$($_.Short)-$($_.Version)" }) -join '+'

if (-not $overwrite -and (Test-TagExists -Repo $repo -Tag $tag)) {
    Fail "tag 已存在：$tag" @(
        '同一个版本号不能重复发布：先把 manifest.json 的 version_number 升上去，再运行工作流。',
        '如果确实是要修同名旧资产（例如上次压缩包漏文件），勾选 overwrite 重跑。'
    )
}

if (-not $sourceIsDraft) {
    if ($tag -ne $source.tag_name) {
        Fail "源 Release 已经发布了（tag 是 $($source.tag_name)），但按 manifest 算出来的 tag 是 $tag。" @(
            '已发布的 Release 只能原地改名后再覆盖资产：把 source_release 指向草稿 Release，或把 tag 改成一致。'
        )
    }
    if (-not $overwrite) {
        Fail "源 Release 已经发布了：$($source.tag_name)" @(
            '要往已发布的 Release 上补资产/换资产，请勾选 overwrite；正常发版应该用草稿 Release 当上传区。'
        )
    }
}

$prevRelease = @($releases | Where-Object { -not $_.draft -and $_.published_at } |
        Sort-Object -Property { [datetime]$_.published_at } -Descending) | Select-Object -First 1

$prevVersions = @{}
if ($prevRelease) {
    foreach ($part in ([string]$prevRelease.tag_name -split '\+')) {
        if ($part -match '^(.+?)-(\d+\.\d+\.\d+)$') {
            $prevVersions[$Matches[1].ToLowerInvariant()] = $Matches[2]
        }
    }

    foreach ($project in $selected) {
        $shortKey = $project.Short.ToLowerInvariant()
        if (-not $prevVersions.ContainsKey($shortKey)) { continue }

        $comparison = Compare-SemVer -A $project.Version -B $prevVersions[$shortKey]
        if ($comparison -gt 0) { continue }

        if ($overwrite) {
            $warnings.Add("$($project.DirName) 的版本 $($project.Version) 不高于已发布的 $($prevVersions[$shortKey])，按 overwrite 继续。")
            continue
        }

        Fail "$($project.DirName) 的版本 $($project.Version) 不高于已发布的 $($prevVersions[$shortKey])。" @(
            "已发布的最新 Release 是 $($prevRelease.tag_name)。",
            '发版必须升 version_number：改 manifest.json 后重新打包，再运行工作流。',
            '（只是重新压缩同一个版本、不打算改版本号时，勾选 overwrite。）'
        )
    }
}

# ---------------------------------------------------------------- 计划
$packages = @(foreach ($project in $selected) {
        [pscustomobject]@{
            project      = $project.DirName
            manifestName = $project.Name
            short        = $project.Short
            version      = $project.Version
            dir          = $project.DirName
            dlls         = @(foreach ($dll in $byProject[$project.DirName]) {
                    [pscustomobject]@{ name = $dll.Name; size = $dll.Size; sha256 = $dll.Sha256 }
                })
        }
    })

$plan = [ordered]@{
    generatedAt          = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    headSha              = [string]$env:GITHUB_SHA
    runUrl               = if ($env:GITHUB_SERVER_URL -and $env:GITHUB_RUN_ID) { "$($env:GITHUB_SERVER_URL)/$repo/actions/runs/$($env:GITHUB_RUN_ID)" } else { '' }
    tag                  = $tag
    prevTag              = if ($prevRelease) { [string]$prevRelease.tag_name } else { '' }
    mode                 = $mode
    publish              = $publish
    dryRun               = $dryRun
    overwrite            = $overwrite
    sourceReleaseId      = $source.id
    sourceTag            = [string]$source.tag_name
    sourceIsDraft        = $sourceIsDraft
    sourceUrl            = $sourceUrl
    projectsInput        = $projectsInput
    warnings             = @($warnings)
    packages             = $packages
}

New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
$plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $stagingDir 'plan.json') -Encoding utf8

$matrix = @(foreach ($package in $packages) {
        [pscustomobject]@{ project = $package.project; manifestName = $package.manifestName; version = $package.version }
    })
Set-Output -Name 'matrix' -Value ($matrix | ConvertTo-Json -Compress -Depth 5 -AsArray)
Set-Output -Name 'tag' -Value $tag
Set-Output -Name 'prevTag' -Value ([string]$plan.prevTag)
Set-Output -Name 'packageCount' -Value ([string]$packages.Count)
Set-Output -Name 'dryRun' -Value ([string]$dryRun)
Set-Output -Name 'sourceIsDraft' -Value ([string]$sourceIsDraft)

# ---------------------------------------------------------------- 汇总
$summary = @(
    '## 📦 发布计划'
    ''
    "- 源 Release：``$($plan.sourceTag)``（$(if ($sourceIsDraft) { '草稿' } else { '已发布' })）— $sourceUrl"
    "- 目标 tag：``$tag``"
    "- 模式：$mode"
    "- 覆盖已有资产：$(if ($overwrite) { '是' } else { '否' })"
    ''
    '| 项目 | manifest name | 版本 | DLL |'
    '| --- | --- | --- | --- |'
)
foreach ($package in $packages) {
    $dllCell = (@($package.dlls | ForEach-Object { "``$($_.name)``" }) -join '<br>')
    $summary += "| $($package.project) | ``$($package.manifestName)`` | $($package.version) | $dllCell |"
}

if ($warnings.Count -gt 0) {
    $summary += ''
    $summary += '### 提示'
    $summary += ''
    foreach ($warning in $warnings) { $summary += "- $warning" }
}

Add-Summary -Lines $summary

Write-Host ''
Write-Host "源 Release：$($plan.sourceTag)（$sourceUrl）"
Write-Host "目标 tag  ：$tag"
Write-Host "模式      ：$mode"
Write-Host "打包项目  ：$($packages.project -join '、')"
