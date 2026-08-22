param(
    [Parameter(Mandatory = $true)][ValidateSet('dev', 'staging', 'prod')][string]$Flavor,
    [Parameter(Mandatory = $true)][string]$BuildName,
    [Parameter(Mandatory = $true)][string]$BuildNumber,
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$workspace = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
if ($BuildName -notmatch '^\d+\.\d+\.\d+$') { throw 'BuildName must use x.y.z.' }
if ($BuildNumber -notmatch '^[1-9]\d*$') { throw 'BuildNumber must be a positive integer.' }
$resolvedConfig = [System.IO.Path]::GetFullPath($ConfigPath)
if (-not (Test-Path -LiteralPath $resolvedConfig -PathType Leaf)) { throw "Runtime config is missing: $resolvedConfig" }
if ([string]::IsNullOrWhiteSpace($env:SHOREBIRD_TOKEN)) { throw 'SHOREBIRD_TOKEN is required.' }
if (-not (Test-Path -LiteralPath (Join-Path $workspace 'shorebird.yaml') -PathType Leaf)) {
    throw 'Generate ignored shorebird.yaml with tool/configure_shorebird.ps1 first.'
}
$shorebirdConfig = Get-Content -LiteralPath (Join-Path $workspace 'shorebird.yaml') -Raw
$appIdMatch = [regex]::Match(
    $shorebirdConfig,
    "(?m)^\s{2}$([regex]::Escape($Flavor)):\s+([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})\s*$",
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
)
if (-not $appIdMatch.Success) { throw "shorebird.yaml has no canonical app ID for flavor $Flavor." }
$appId = $appIdMatch.Groups[1].Value.ToLowerInvariant()
$canonical = Get-Content -LiteralPath (Join-Path $workspace 'config\toolchain.json') -Raw | ConvertFrom-Json
$shorebirdPin = $canonical.canonicalToolchain.tools.shorebirdCli

$symbols = Join-Path $workspace "build\shorebird-symbols\$Flavor\base"
New-Item -ItemType Directory -Path $symbols -Force | Out-Null
$arguments = @(
    'release', 'android',
    "--flavor=$Flavor",
    '--artifact=aab',
    '--target=lib/main.dart',
    "--build-name=$BuildName",
    "--build-number=$BuildNumber",
    "--flutter-version=$($shorebirdPin.releaseFlutterVersion)",
    "--dart-define-from-file=$resolvedConfig",
    '--obfuscate',
    "--split-debug-info=$symbols",
    '--public-key-cmd=bash tool/shorebird_kms_public_key.sh',
    '--',
    '--no-pub'
)
if ($DryRun) { $arguments += '--dry-run' }

Push-Location $workspace
try {
    & shorebird @arguments
    if ($LASTEXITCODE -ne 0) { throw "shorebird release android failed with exit code $LASTEXITCODE." }
}
finally { Pop-Location }

if ([string]::IsNullOrWhiteSpace($env:SHOREBIRD_HOME)) { throw 'SHOREBIRD_HOME is required.' }
$releaseFlutterCheckout = Join-Path $env:SHOREBIRD_HOME "bin\cache\flutter\$($shorebirdPin.releaseFlutterRevision)"
if (-not (Test-Path -LiteralPath $releaseFlutterCheckout -PathType Container)) {
    throw "Shorebird did not resolve canonical Flutter $($shorebirdPin.releaseFlutterVersion) at revision $($shorebirdPin.releaseFlutterRevision)."
}
$resolvedReleaseFlutter = (& git -c core.longpaths=true -C $releaseFlutterCheckout rev-parse HEAD 2>&1 | Out-String).Trim()
$resolvedReleaseEngine = (Get-Content -LiteralPath (Join-Path $releaseFlutterCheckout 'bin\internal\engine.version') -Raw).Trim()
if ($LASTEXITCODE -ne 0 -or $resolvedReleaseFlutter -ne [string]$shorebirdPin.releaseFlutterRevision -or $resolvedReleaseEngine -ne [string]$shorebirdPin.releaseEngineRevision) {
    throw 'The Shorebird release build did not use the canonical Owntend Flutter/engine revisions.'
}

$aab = Join-Path $workspace "build\app\outputs\bundle\${Flavor}Release\app-$Flavor-release.aab"
if (-not (Test-Path -LiteralPath $aab -PathType Leaf)) { throw "Shorebird did not produce the expected AAB: $aab" }
$mode = if ($DryRun) { 'dry-run' } else { 'published' }
$evidence = [ordered]@{
    schema_version = 1
    operation = 'shorebird-release'
    mode = $mode
    flavor = $Flavor
    app_id = $appId
    release_version = "$BuildName+$BuildNumber"
    app_bundle = $aab.Substring($workspace.Length + 1).Replace('\\', '/')
    app_bundle_sha256 = (Get-FileHash -LiteralPath $aab -Algorithm SHA256).Hash.ToLowerInvariant()
    source_sha = (& git -C $workspace rev-parse HEAD).Trim()
    shorebird_cli_version = [string]$shorebirdPin.version
    shorebird_cli_commit = [string]$shorebirdPin.commit
    flutter_version = [string]$shorebirdPin.releaseFlutterVersion
    flutter_revision = [string]$shorebirdPin.releaseFlutterRevision
    engine_revision = [string]$shorebirdPin.releaseEngineRevision
    shorebird_bundled_flutter_revision = [string]$shorebirdPin.bundledFlutterRevision
    shorebird_bundled_engine_revision = [string]$shorebirdPin.bundledEngineRevision
    ci_repository = [string]$env:GITHUB_REPOSITORY
    ci_ref = [string]$env:GITHUB_REF
    ci_run_id = [string]$env:GITHUB_RUN_ID
    ci_run_attempt = [string]$env:GITHUB_RUN_ATTEMPT
    native_diff_bypass = $false
    asset_diff_bypass = $false
    generated_at_utc = [DateTime]::UtcNow.ToString('o')
}
$evidencePath = Join-Path $workspace "build\shorebird-release-$Flavor-$mode.json"
[System.IO.File]::WriteAllText($evidencePath, (($evidence | ConvertTo-Json -Depth 5) + "`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Output $aab
