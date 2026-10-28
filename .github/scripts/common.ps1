#requires -Version 7.0
<#
  打包发布工作流 · 公共函数。

  被 prepare.ps1 / package.ps1 / publish.ps1 点源加载；同时兼容本地手动执行
  （GITHUB_STEP_SUMMARY / GITHUB_OUTPUT 不存在时静默跳过）。
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

<#
.SYNOPSIS
  打印可操作的错误信息，写入 Step Summary，并以退出码 1 结束当前脚本。
#>
function Fail {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string[]]$Details = @()
    )

    Write-Host "::error::$Message"
    $lines = @('## ❌ 打包发布失败', '', $Message)
    foreach ($detail in $Details) {
        if ([string]::IsNullOrWhiteSpace($detail)) { continue }
        Write-Host "  $detail"
        $lines += ''
        $lines += $detail
    }

    if ($env:GITHUB_STEP_SUMMARY) {
        Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value ($lines -join "`n") -Encoding utf8
    }

    exit 1
}

<#
.SYNOPSIS
  向 Step Summary 追加一段 markdown。
#>
function Add-Summary {
    param([string[]]$Lines = @())

    if (-not $env:GITHUB_STEP_SUMMARY) { return }
    Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value ($Lines -join "`n") -Encoding utf8
}

<#
.SYNOPSIS
  写一条 job 输出（$GITHUB_OUTPUT）。
#>
function Set-Output {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowEmptyString()][string]$Value = ''
    )

    if (-not $env:GITHUB_OUTPUT) { return }
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "$Name=$Value" -Encoding utf8
}

<#
.SYNOPSIS
  读取 prepare 阶段产出的 plan.json。
#>
function Get-Plan {
    param([string]$WorkRoot = '.publish')

    $path = Join-Path (Join-Path $WorkRoot 'staging') 'plan.json'
    if (-not (Test-Path -LiteralPath $path)) {
        Fail "找不到计划文件 $path，prepare 阶段没有正常完成。" @(
            '重新运行工作流；若仍失败，看 prepare 阶段日志里的报错。'
        )
    }

    return Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json
}

<#
.SYNOPSIS
  比较两个 x.y.z 版本号：返回正数表示 A > B，0 表示相等。
#>
function Compare-SemVer {
    param(
        [Parameter(Mandatory = $true)][string]$A,
        [Parameter(Mandatory = $true)][string]$B
    )

    $left = $A.Split('.') | ForEach-Object { [int]$_ }
    $right = $B.Split('.') | ForEach-Object { [int]$_ }
    for ($i = 0; $i -lt 3; $i++) {
        if ($left[$i] -ne $right[$i]) { return ($left[$i] - $right[$i]) }
    }

    return 0
}

<#
.SYNOPSIS
  用 GitHub API 判断 git tag 是否已存在。
#>
function Test-TagExists {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$Tag
    )

    $encoded = [uri]::EscapeDataString($Tag)
    & gh api "repos/$Repo/git/ref/tags/$encoded" *> $null
    return ($LASTEXITCODE -eq 0)
}

<#
.SYNOPSIS
  分页调用 `gh api`，把每个元素压成一行 JSON 返回（避免 pretty-print 破坏逐行解析）。
#>
function Get-GhJsonLines {
    param([Parameter(Mandatory = $true)][string]$Path)

    $lines = & gh api $Path --paginate --jq '.[] | @json'
    if ($LASTEXITCODE -ne 0) {
        Fail "调用 GitHub API 失败：$Path" @(
            '确认 GITHUB_TOKEN 有 contents: write 权限，且源 Release 的 tag 拼写正确。'
        )
    }

    return @($lines | Where-Object { $_ -and $_.Trim().Length -gt 0 })
}
