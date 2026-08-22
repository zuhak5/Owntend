param(
    [Parameter(Mandatory = $true)][ValidateSet('dev', 'staging', 'prod')][string]$Flavor,
    [Parameter(Mandatory = $true)][string]$ReleaseVersion,
    [Parameter(Mandatory = $true)][string]$ReleaseBaseSha,
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$workspace = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
if ($ReleaseVersion -notmatch '^\d+\.\d+\.\d+\+[1-9]\d*$') { throw 'ReleaseVersion must use x.y.z+N.' }
if ($ReleaseBaseSha -notmatch '^[0-9a-f]{40}$') { throw 'ReleaseBaseSha must be a lowercase full commit SHA.' }
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

function Get-ReleasePatches {
    $jsonText = (& shorebird patches list --release-version $ReleaseVersion --app-id $appId --json 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Could not list Shorebird patches.`n$jsonText" }
    try { $envelope = $jsonText | ConvertFrom-Json } catch { throw "Shorebird patch-list JSON was invalid.`n$jsonText" }
    if ($envelope.status -ne 'success') { throw 'Shorebird patch-list request did not report success.' }
    return @($envelope.data.patches)
}

$patchesBefore = if ($DryRun) { @() } else { @(Get-ReleasePatches) }

$symbols = Join-Path $workspace "build\shorebird-symbols\$Flavor\patch-$($ReleaseVersion.Replace('+', '-'))"
New-Item -ItemType Directory -Path $symbols -Force | Out-Null
$arguments = @(
    'patch', 'android',
    "--flavor=$Flavor",
    "--release-version=$ReleaseVersion",
    '--track=staging',
    '--target=lib/main.dart',
    "--dart-define-from-file=$resolvedConfig",
    '--obfuscate',
    "--split-debug-info=$symbols",
    '--public-key-cmd=bash tool/shorebird_kms_public_key.sh',
    '--sign-cmd=bash tool/shorebird_kms_sign.sh'
)
if ($DryRun) { $arguments += '--dry-run' }
$arguments += @('--', '--no-pub')

Push-Location $workspace
try {
    & shorebird @arguments
    if ($LASTEXITCODE -ne 0) { throw "shorebird patch android failed with exit code $LASTEXITCODE." }
}
finally { Pop-Location }

if ([string]::IsNullOrWhiteSpace($env:SHOREBIRD_HOME)) { throw 'SHOREBIRD_HOME is required.' }
$releaseFlutterCheckout = Join-Path $env:SHOREBIRD_HOME "bin\cache\flutter\$($shorebirdPin.releaseFlutterRevision)"
if (-not (Test-Path -LiteralPath $releaseFlutterCheckout -PathType Container)) {
    throw "The patch did not resolve its base release to canonical Flutter $($shorebirdPin.releaseFlutterVersion)."
}
$resolvedReleaseFlutter = (& git -c core.longpaths=true -C $releaseFlutterCheckout rev-parse HEAD 2>&1 | Out-String).Trim()
$resolvedReleaseEngine = (Get-Content -LiteralPath (Join-Path $releaseFlutterCheckout 'bin\internal\engine.version') -Raw).Trim()
if ($LASTEXITCODE -ne 0 -or $resolvedReleaseFlutter -ne [string]$shorebirdPin.releaseFlutterRevision -or $resolvedReleaseEngine -ne [string]$shorebirdPin.releaseEngineRevision) {
    throw 'The Shorebird patch build did not use its canonical base Flutter/engine revisions.'
}

$mode = if ($DryRun) { 'dry-run' } else { 'published-to-staging' }
$patchNumber = $null
if (-not $DryRun) {
    $existingNumbers = @($patchesBefore | ForEach-Object { [int]$_.number })
    $newPatches = @(Get-ReleasePatches | Where-Object { [int]$_.number -notin $existingNumbers })
    if ($newPatches.Count -ne 1) { throw "Expected exactly one newly published patch, found $($newPatches.Count)." }
    if ([string]$newPatches[0].channel -ne 'staging' -or [bool]$newPatches[0].is_rolled_back) {
        throw 'The newly published patch is not an active staging-track patch.'
    }
    $patchNumber = [int]$newPatches[0].number
}
$sourceSha = (& git -C $workspace rev-parse HEAD).Trim()
$evidence = [ordered]@{
    schema_version = 1
    operation = 'shorebird-patch'
    mode = $mode
    flavor = $Flavor
    app_id = $appId
    release_version = $ReleaseVersion
    release_base_sha = $ReleaseBaseSha
    patch_number = $patchNumber
    track = 'staging'
    source_sha = $sourceSha
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
$evidencePath = Join-Path $workspace "build\shorebird-patch-$Flavor-$mode.json"
[System.IO.File]::WriteAllText($evidencePath, (($evidence | ConvertTo-Json -Depth 5) + "`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Output $evidencePath
