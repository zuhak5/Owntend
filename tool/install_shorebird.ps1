param(
    [string]$InstallDirectory = '',
    [switch]$SkipBootstrap
)

$ErrorActionPreference = 'Stop'
$workspace = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$toolchainPath = Join-Path $workspace 'config\toolchain.json'
$toolchain = Get-Content -LiteralPath $toolchainPath -Raw | ConvertFrom-Json
$pin = $toolchain.canonicalToolchain.tools.shorebirdCli

if ([string]::IsNullOrWhiteSpace($InstallDirectory)) {
    $InstallDirectory = Join-Path $workspace 'build\shorebird'
}
$resolvedInstall = [System.IO.Path]::GetFullPath($InstallDirectory)
New-Item -ItemType Directory -Path (Split-Path -Parent $resolvedInstall) -Force | Out-Null

function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

if (-not (Test-Path -LiteralPath $resolvedInstall -PathType Container)) {
    New-Item -ItemType Directory -Path $resolvedInstall | Out-Null
    Invoke-Git -Arguments @('-C', $resolvedInstall, 'init', '--quiet')
    Invoke-Git -Arguments @(
        '-C', $resolvedInstall, 'remote', 'add', 'origin', [string]$pin.repository
    )
}

if (-not (Test-Path -LiteralPath (Join-Path $resolvedInstall '.git') -PathType Container)) {
    throw "Shorebird install directory is not a Git checkout: $resolvedInstall"
}

$origin = (& git -C $resolvedInstall remote get-url origin 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $origin -ne [string]$pin.repository) {
    throw "Unexpected Shorebird origin '$origin'. Expected $($pin.repository)."
}

Invoke-Git -Arguments @(
    '-C', $resolvedInstall, 'fetch', '--quiet', '--depth', '1', 'origin', [string]$pin.commit
)
Invoke-Git -Arguments @(
    '-C', $resolvedInstall, 'fetch', '--quiet', 'origin', 'stable:refs/remotes/origin/stable'
)
Invoke-Git -Arguments @(
    '-C', $resolvedInstall, 'checkout', '--quiet', '-B', 'owntend-pinned', [string]$pin.commit
)
Invoke-Git -Arguments @(
    '-C', $resolvedInstall, 'branch', '--set-upstream-to=origin/stable', 'owntend-pinned'
)

$resolvedCommit = (& git -C $resolvedInstall rev-parse HEAD 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $resolvedCommit -ne [string]$pin.commit) {
    throw "Shorebird checkout mismatch. Expected $($pin.commit), got $resolvedCommit."
}

$flutterRevisionPath = Join-Path $resolvedInstall 'bin\internal\flutter.version'
$flutterRevision = (Get-Content -LiteralPath $flutterRevisionPath -Raw).Trim()
if ($flutterRevision -ne [string]$pin.bundledFlutterRevision) {
    throw "Shorebird bundled Flutter revision mismatch. Expected $($pin.bundledFlutterRevision), got $flutterRevision."
}

$shorebirdExecutable = Join-Path $resolvedInstall 'bin\shorebird.bat'
if (-not $SkipBootstrap) {
    $previousGitConfigCount = $env:GIT_CONFIG_COUNT
    $previousGitConfigKey = $env:GIT_CONFIG_KEY_0
    $previousGitConfigValue = $env:GIT_CONFIG_VALUE_0
    try {
        # Shorebird's pinned Flutter checkout contains valid paths longer than
        # legacy Win32 MAX_PATH. This process-local override also reaches child Git.
        $env:GIT_CONFIG_COUNT = '1'
        $env:GIT_CONFIG_KEY_0 = 'core.longpaths'
        $env:GIT_CONFIG_VALUE_0 = 'true'
        $versionOutput = (& $shorebirdExecutable --version 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) {
            throw "Shorebird bootstrap failed with exit code $LASTEXITCODE.`n$versionOutput"
        }
    }
    finally {
        $env:GIT_CONFIG_COUNT = $previousGitConfigCount
        $env:GIT_CONFIG_KEY_0 = $previousGitConfigKey
        $env:GIT_CONFIG_VALUE_0 = $previousGitConfigValue
    }
    if ($versionOutput -notmatch "(?m)^Shorebird\s+$([regex]::Escape([string]$pin.version))\b") {
        throw "Unexpected Shorebird version output. Expected $($pin.version).`n$versionOutput"
    }
    $flutterCheckout = Join-Path $resolvedInstall "bin\cache\flutter\$($pin.bundledFlutterRevision)"
    $flutterCommit = (& git -c core.longpaths=true -C $flutterCheckout rev-parse HEAD 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $flutterCommit -ne [string]$pin.bundledFlutterRevision) {
        throw "Bootstrapped Shorebird Flutter revision mismatch: $flutterCommit"
    }
    $flutterChanges = (& git -c core.longpaths=true -C $flutterCheckout status --porcelain 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or -not [string]::IsNullOrWhiteSpace($flutterChanges)) {
        throw "Bootstrapped Shorebird Flutter checkout is incomplete or dirty.`n$flutterChanges"
    }
    $engineRevision = (Get-Content -LiteralPath (Join-Path $flutterCheckout 'bin\internal\engine.version') -Raw).Trim()
    if ($engineRevision -ne [string]$pin.bundledEngineRevision) {
        throw "Bootstrapped Shorebird engine revision mismatch. Expected $($pin.bundledEngineRevision), got $engineRevision."
    }
    Write-Host $versionOutput
}

$shorebirdBin = Join-Path $resolvedInstall 'bin'
$env:SHOREBIRD_HOME = $resolvedInstall
$env:PATH = "$shorebirdBin$([System.IO.Path]::PathSeparator)$env:PATH"
if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_PATH)) {
    $shorebirdBin >> $env:GITHUB_PATH
}
if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_ENV)) {
    "SHOREBIRD_HOME=$resolvedInstall" >> $env:GITHUB_ENV
}

Write-Output $shorebirdBin
