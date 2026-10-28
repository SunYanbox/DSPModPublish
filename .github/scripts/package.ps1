#requires -Version 7.0
<#
  打包发布工作流 · 打包阶段。

  对单个包目录：把 manifest.json / icon.png / README.md / CHANGELOG.md 和分配到的
  DLL 复制到暂存目录，打成 zip（全部在 zip 根目录），校验条目，并写出 *.meta.json
  供发布阶段使用。

  参数：
    -Project  包目录名，例如 DSPEasy.Buildings
    -WorkRoot 工作目录，默认 .publish
#>

param(
    [Parameter(Mandatory = $true)][string]$Project,
    [string]$WorkRoot = '.publish'
)

. (Join-Path $PSScriptRoot 'common.ps1')

$plan = Get-Plan -WorkRoot $WorkRoot
$package = @($plan.packages | Where-Object { $_.project -eq $Project }) | Select-Object -First 1
if (-not $package) {
    Fail "计划里没有项目 $Project。" @("计划里的项目：$(@($plan.packages.project) -join '、')")
}

$root = (Get-Location).Path
$projectDir = Join-Path $root $Project
if (-not (Test-Path -LiteralPath (Join-Path $projectDir 'manifest.json'))) {
    Fail "找不到包目录 $projectDir（或里面的 manifest.json）。"
}

$stagingDir = Join-Path $WorkRoot 'staging'
$incomingDir = Join-Path $stagingDir 'incoming'
$outDir = Join-Path (Join-Path $WorkRoot 'out') $Project
$distDir = Join-Path $WorkRoot 'dist'
$zipPath = Join-Path $distDir "$Project.zip"

# ---------------------------------------------------------------- 组装暂存目录
if (Test-Path -LiteralPath $outDir) { Remove-Item -LiteralPath $outDir -Recurse -Force }
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

# 固定顺序；用完即弃的暂存目录里只有这些文件，避免把上一版 zip 打进包里
$files = [System.Collections.Generic.List[string]]::new()
foreach ($name in 'manifest.json', 'icon.png', 'README.md', 'CHANGELOG.md') {
    $source = Join-Path $projectDir $name
    if (-not (Test-Path -LiteralPath $source)) { Fail "$Project 缺少 $name。" }
    if ((Get-Item -LiteralPath $source).Length -eq 0) { Fail "$Project/$name 是空文件。" }
    Copy-Item -LiteralPath $source -Destination (Join-Path $outDir $name)
    $files.Add($name)
}

foreach ($dll in $package.dlls) {
    $source = Join-Path $incomingDir $dll.name
    if (-not (Test-Path -LiteralPath $source)) {
        Fail "找不到 DLL 文件 $($dll.name)（应在 $incomingDir）。" @('prepare 阶段没有把它写进 Artifacts，重新运行整个工作流。')
    }

    $actualSha = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualSha -ne $dll.sha256) {
        Fail "DLL $($dll.name) 的 SHA256 和 prepare 阶段不一致，文件在传递过程中被改动了。" @("期望 $($dll.sha256)", "实际 $actualSha")
    }

    Copy-Item -LiteralPath $source -Destination (Join-Path $outDir $dll.name)
    $files.Add($dll.name)
}

if ($files.Count -ne (4 + @($package.dlls).Count)) {
    Fail "暂存目录里的文件数不对：期望 $(4 + @($package.dlls).Count)，实际 $($files.Count)。"
}

# ---------------------------------------------------------------- 打包
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

New-Item -ItemType Directory -Path $distDir -Force | Out-Null
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

$stream = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite)
try {
    $archive = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in $files) {
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive,
                (Join-Path $outDir $name),
                $name,
                [System.IO.Compression.CompressionLevel]::Optimal)
        }
    }
    finally { $archive.Dispose() }
}
finally { $stream.Dispose() }

# ---------------------------------------------------------------- 校验
$readStream = [System.IO.File]::OpenRead($zipPath)
try {
    $verifyArchive = [System.IO.Compression.ZipArchive]::new($readStream, [System.IO.Compression.ZipArchiveMode]::Read)
    try {
        $entries = @($verifyArchive.Entries)
        $entryNames = @($entries | ForEach-Object { $_.FullName })
        $emptyEntries = @($entries | Where-Object { $_.Length -eq 0 })
    }
    finally { $verifyArchive.Dispose() }
}
finally { $readStream.Dispose() }

$nested = @($entryNames | Where-Object { $_ -match '[\\/]' })
if ($nested.Count -gt 0) {
    Fail "压缩包里有子目录条目：$($nested -join '、')" @('Thunderstore 要求 manifest.json 等直接放在 zip 根目录，不能套一层文件夹。')
}

$strayZip = @($entryNames | Where-Object { $_ -match '(?i)\.(zip|7z)$' })
if ($strayZip.Count -gt 0) {
    Fail "压缩包把旧的压缩包也打进去了：$($strayZip -join '、')"
}

$expectedNames = @($files | Sort-Object)
$actualNames = @($entryNames | Sort-Object)
if (($expectedNames -join '|') -ne ($actualNames -join '|')) {
    Fail "$Project.zip 的条目和预期不一致。" @(
        "预期：$($expectedNames -join '、')",
        "实际：$($actualNames -join '、')"
    )
}

if ($emptyEntries.Count -gt 0) {
    Fail "$Project.zip 里有空文件：$($emptyEntries.FullName -join '、')"
}

# ---------------------------------------------------------------- 元数据
$zipSize = (Get-Item -LiteralPath $zipPath).Length
$zipSha = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()

if ($zipSize -eq 0) { Fail "$Project.zip 是空文件。" }
if ($zipSize -ge 100MB) { Fail "$Project.zip 有 $([math]::Round($zipSize / 1MB, 1)) MB，超过 Thunderstore 的 100 MB 上限。" }

$meta = [ordered]@{
    project      = $Project
    manifestName = $package.manifestName
    short        = $package.short
    version      = $package.version
    tag          = $plan.tag
    zip          = "$Project.zip"
    size         = $zipSize
    sha256       = $zipSha
    files        = @($files)
    dlls         = @($package.dlls)
}
$metaPath = Join-Path $distDir "$Project.meta.json"
$meta | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $metaPath -Encoding utf8

# ---------------------------------------------------------------- 汇总
$rows = @(foreach ($name in $files) {
        $item = Get-Item -LiteralPath (Join-Path $outDir $name)
        [pscustomobject]@{ '文件' = $item.Name; '字节' = $item.Length }
    })
$table = $rows | Format-Table -AutoSize | Out-String
Write-Host $table

Add-Summary -Lines (@(
        "### 📦 $Project"
        ''
        "- 压缩包：``$Project.zip``（$([math]::Round($zipSize / 1KB, 1)) KB）"
        "- SHA256：``$zipSha``"
        ''
        '| 文件 | 字节 |'
        '| --- | --- |'
    ) + @(foreach ($name in $files) {
            $item = Get-Item -LiteralPath (Join-Path $outDir $name)
            "| $($item.Name) | $($item.Length) |"
        }))
