param(
    [Parameter(Mandatory = $true)]
    [string]$Release,

    [Parameter(Mandatory = $true)]
    [string]$Dist,

    [string]$Environment = 'prod',

    [string]$DartSymbolsDirectory = 'build\shorebird-symbols\prod\base',

    [string]$ObfuscationMapPath = 'build\shorebird\obfuscation_map.json',

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$EngineSymbolsDirectory,

    [string]$Flavor = 'prod',

    [string]$ShorebirdPatchNumber = 'base'
)

$ErrorActionPreference = 'Stop'

$requiredEnvironment = @(
    'SENTRY_AUTH_TOKEN',
    'SENTRY_ORG',
    'SENTRY_PROJECT'
)
foreach ($name in $requiredEnvironment) {
    $value = [System.Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Missing required Sentry environment value: $name"
    }

    # Normalize accidental surrounding whitespace from copied secrets and variables.
    [System.Environment]::SetEnvironmentVariable($name, $value.Trim())
}
if ($env:SENTRY_ORG -ne 'owntend') {
    throw 'SENTRY_ORG must be owntend.'
}
if ($env:SENTRY_PROJECT -ne 'owntend-mobile') {
    throw 'SENTRY_PROJECT must be owntend-mobile.'
}
if ([string]::IsNullOrWhiteSpace($Release) -or
    $Release -notmatch '^app\.owntend\.mobile@\d+\.\d+\.\d+\+\d+$') {
    throw "Unexpected Sentry release identifier: $Release"
}
if ([string]::IsNullOrWhiteSpace($Dist) -or $Dist -notmatch '^\d+$') {
    throw "Unexpected Sentry dist: $Dist"
}

$pubspecVersion = Select-String -LiteralPath (Join-Path $PSScriptRoot '..\pubspec.yaml') -Pattern '^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$'
if ($null -eq $pubspecVersion -or $pubspecVersion.Matches.Count -ne 1) {
    throw 'pubspec.yaml must contain one canonical semantic version and build number.'
}
$expectedRelease = "app.owntend.mobile@$($pubspecVersion.Matches[0].Groups[1].Value)+$($pubspecVersion.Matches[0].Groups[2].Value)"
$expectedDist = $pubspecVersion.Matches[0].Groups[2].Value
if ($Release -ne $expectedRelease -or $Dist -ne $expectedDist) {
    throw 'Sentry release or dist does not match the canonical pubspec build identity.'
}
if ($Flavor -ne 'prod') {
    throw 'The protected Owntend Sentry publication accepts only the prod flavor.'
}
if ($Environment -ne 'prod') {
    throw 'The protected Owntend Sentry publication accepts only the prod environment.'
}
if ($ShorebirdPatchNumber -ne 'base' -and $ShorebirdPatchNumber -notmatch '^[1-9]\d*$') {
    throw 'The Shorebird patch identity must be base or a positive integer.'
}

$env:SENTRY_RELEASE = $Release
$env:SENTRY_DIST = $Dist

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = (& $FilePath @Arguments 2>&1 | Out-String)
    $exitCode = $LASTEXITCODE
    if (-not [string]::IsNullOrWhiteSpace($output)) {
        Write-Host $output.TrimEnd()
    }

    if ($exitCode -ne 0) {
        if ($output -match '(?i)(Invalid token|http status:\s*401|Unauthorized)') {
            throw [System.UnauthorizedAccessException]::new(
                'Sentry authentication failed. Replace the GitHub production environment secret SENTRY_AUTH_TOKEN with a valid token for organization owntend and project owntend-mobile. The token must support sentry-cli release management and include org:read plus project:releases (or org:ci).'
            )
        }

        throw "$FilePath $($Arguments -join ' ') failed with exit code $exitCode."
    }
}

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Operation
    )

    for ($attempt = 1; $attempt -le 2; $attempt++) {
        try {
            & $Operation
            return
        }
        catch [System.UnauthorizedAccessException] {
            # Authentication failures are permanent until the protected secret is rotated.
            throw
        }
        catch {
            if ($attempt -eq 2) {
                throw
            }
            Write-Warning "$Label failed on attempt $attempt. Retrying once."
            Start-Sleep -Seconds 5
        }
    }
}

# Match the sentry-cli version embedded by sentry_dart_plugin 3.4.0 so release
# management and debug-file upload use the same protocol implementation.
$sentryCli = @('--yes', '@sentry/cli@2.58.6')

function Get-DebugFileIdentity {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedArch,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $checkOutput = (& npx @sentryCli debug-files check --json $Path 2>$null | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read debug identifiers for $Label."
    }
    try {
        $check = $checkOutput | ConvertFrom-Json
    }
    catch {
        throw "Sentry CLI returned invalid debug-identifier JSON for $Label."
    }
    $variants = @($check.variants)
    if ($check.is_usable -ne $true -or $variants.Count -ne 1 -or
        [string]$variants[0].arch -ne $ExpectedArch -or
        [string]$variants[0].debug_id -notmatch '^[0-9a-f-]{36}$' -or
        [string]$variants[0].code_id -notmatch '^[0-9a-f]+$') {
        throw "Debug identifiers are invalid for $Label."
    }
    return [ordered]@{
        arch = [string]$variants[0].arch
        debug_id = [string]$variants[0].debug_id
        code_id = [string]$variants[0].code_id
    }
}

$resolvedDartSymbols = [System.IO.Path]::GetFullPath($DartSymbolsDirectory)
$resolvedObfuscationMap = [System.IO.Path]::GetFullPath($ObfuscationMapPath)
if (-not (Test-Path -LiteralPath $resolvedDartSymbols -PathType Container)) {
    throw "Shorebird Dart symbols were not found: $resolvedDartSymbols"
}
if (-not (Test-Path -LiteralPath $resolvedObfuscationMap -PathType Leaf)) {
    throw "Shorebird obfuscation map was not found: $resolvedObfuscationMap"
}
$expectedDartSymbols = [ordered]@{
    'app.android-arm.symbols' = 'arm'
    'app.android-arm64.symbols' = 'arm64'
    'app.android-x64.symbols' = 'x86_64'
}
$expectedDartSymbolFiles = @($expectedDartSymbols.Keys)
$actualDartSymbols = @(Get-ChildItem -LiteralPath $resolvedDartSymbols -File -Filter '*.symbols' | ForEach-Object { $_.Name } | Sort-Object)
$symbolDifference = @(Compare-Object -ReferenceObject $expectedDartSymbolFiles -DifferenceObject $actualDartSymbols)
if ($symbolDifference.Count -ne 0 -or $actualDartSymbols.Count -ne 3) {
    throw 'Exactly the three canonical Android ABI Dart symbol files are required.'
}
try {
    Get-Content -LiteralPath $resolvedObfuscationMap -Raw | ConvertFrom-Json | Out-Null
}
catch {
    throw 'The Shorebird obfuscation map is not valid JSON.'
}
$dartDebugFiles = @()
$dartDebugFilesByName = @{}
foreach ($symbolName in $expectedDartSymbolFiles) {
    $identity = Get-DebugFileIdentity `
        -Path (Join-Path $resolvedDartSymbols $symbolName) `
        -ExpectedArch ([string]$expectedDartSymbols[$symbolName]) `
        -Label $symbolName
    $debugFile = [ordered]@{
        file = $symbolName
        arch = [string]$identity.arch
        debug_id = [string]$identity.debug_id
        code_id = [string]$identity.code_id
    }
    $dartDebugFiles += $debugFile
    $dartDebugFilesByName[$symbolName] = $debugFile
}
$sentryDartSymbols = [System.IO.Path]::GetFullPath((Join-Path $PWD 'build\sentry-debug\dart'))
if (Test-Path -LiteralPath $sentryDartSymbols) {
    Remove-Item -LiteralPath $sentryDartSymbols -Recurse -Force
}
New-Item -ItemType Directory -Path $sentryDartSymbols -Force | Out-Null
Copy-Item -Path (Join-Path $resolvedDartSymbols '*') -Destination $sentryDartSymbols -Force
Copy-Item -LiteralPath $resolvedObfuscationMap -Destination (Join-Path $sentryDartSymbols 'mapping.json') -Force

$proguardMappingPath = Join-Path $PWD 'build\app\outputs\mapping\prodRelease\mapping.txt'
if (-not (Test-Path -LiteralPath $proguardMappingPath -PathType Leaf)) {
    throw "Android R8 mapping file was not found for Sentry upload: $proguardMappingPath"
}
$sourceSha = (& git -C (Join-Path $PSScriptRoot '..') rev-parse HEAD 2>$null | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $sourceSha -notmatch '^[0-9a-f]{40}$') {
    throw 'Unable to bind Sentry evidence to the current source revision.'
}
$evidenceDirectory = Join-Path $PWD 'build\sentry-release-evidence'
New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
$dartSymbolHashes = @{}
$artifactEvidence = @(
    $expectedDartSymbolFiles | ForEach-Object {
        $path = Join-Path $resolvedDartSymbols $_
        $sha1 = (Get-FileHash -LiteralPath $path -Algorithm SHA1).Hash.ToLowerInvariant()
        $dartSymbolHashes[$_] = $sha1
        $debugFile = $dartDebugFilesByName[$_]
        [ordered]@{
            file = $_
            sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            sha1 = $sha1
            arch = [string]$debugFile.arch
            debug_id = [string]$debugFile.debug_id
            code_id = [string]$debugFile.code_id
        }
    }
)
$artifactEvidence += [ordered]@{
    file = 'mapping.json'
    sha256 = (Get-FileHash -LiteralPath $resolvedObfuscationMap -Algorithm SHA256).Hash.ToLowerInvariant()
}
$artifactEvidence += [ordered]@{
    file = 'mapping.txt'
    sha256 = (Get-FileHash -LiteralPath $proguardMappingPath -Algorithm SHA256).Hash.ToLowerInvariant()
    sha1 = (Get-FileHash -LiteralPath $proguardMappingPath -Algorithm SHA1).Hash.ToLowerInvariant()
}
$resolvedEngineSymbols = [System.IO.Path]::GetFullPath($EngineSymbolsDirectory)
$manifestPath = Join-Path $resolvedEngineSymbols 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Shorebird engine-symbol manifest is missing: $manifestPath"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$canonical = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\config\toolchain.json') -Raw | ConvertFrom-Json
if ([int]$manifest.schema_version -ne 1 -or
    [string]$manifest.engine_revision -ne [string]$canonical.canonicalToolchain.tools.shorebirdCli.releaseEngineRevision) {
    throw 'Shorebird engine-symbol manifest differs from the canonical release engine.'
}
$expectedEngineArtifacts = [ordered]@{
    'android-arm-release' = [ordered]@{ file = 'android-arm-release-symbols.zip'; arch = 'arm' }
    'android-arm64-release' = [ordered]@{ file = 'android-arm64-release-symbols.zip'; arch = 'arm64' }
    'android-x64-release' = [ordered]@{ file = 'android-x64-release-symbols.zip'; arch = 'x86_64' }
}
if (@($manifest.artifacts).Count -ne 3) {
    throw 'Exactly three Shorebird Android engine-symbol archives are required.'
}
$engineArchives = @()
$engineDebugFiles = @()
$engineInspectionRoot = Join-Path $PWD 'build\sentry-debug\engine-inspect'
if (Test-Path -LiteralPath $engineInspectionRoot) {
    Remove-Item -LiteralPath $engineInspectionRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $engineInspectionRoot -Force | Out-Null
foreach ($manifestArtifact in @($manifest.artifacts)) {
    $architecture = [string]$manifestArtifact.architecture
    if (-not $expectedEngineArtifacts.Contains($architecture)) {
        throw "Unexpected engine symbol architecture: $architecture"
    }
    $expectedEngineArtifact = $expectedEngineArtifacts[$architecture]
    $fileName = [string]$manifestArtifact.file
    if ($fileName -ne [string]$expectedEngineArtifact.file -or
        [System.IO.Path]::GetFileName($fileName) -ne $fileName) {
        throw "Unexpected engine symbol archive name for $architecture."
    }
    $archive = Join-Path $resolvedEngineSymbols $fileName
    if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
        throw "Engine symbol archive is missing: $archive"
    }
    $hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne [string]$manifestArtifact.sha256) {
        throw "Engine symbol archive hash mismatch: $archive"
    }

    $inspectionDirectory = Join-Path $engineInspectionRoot $architecture
    New-Item -ItemType Directory -Path $inspectionDirectory -Force | Out-Null
    Expand-Archive -LiteralPath $archive -DestinationPath $inspectionDirectory -Force
    $flutterBinary = Join-Path $inspectionDirectory 'libflutter.so'
    if (-not (Test-Path -LiteralPath $flutterBinary -PathType Leaf)) {
        throw "Engine symbol archive does not contain libflutter.so: $archive"
    }
    $identity = Get-DebugFileIdentity `
        -Path $flutterBinary `
        -ExpectedArch ([string]$expectedEngineArtifact.arch) `
        -Label $architecture

    $engineArchives += $archive
    $engineDebugFiles += [ordered]@{
        architecture = $architecture
        arch = [string]$identity.arch
        debug_id = [string]$identity.debug_id
        code_id = [string]$identity.code_id
    }
    $artifactEvidence += [ordered]@{ file = $fileName; sha256 = $hash }
}
$evidence = [ordered]@{
    schema_version = 1
    release = $Release
    dist = $Dist
    environment = $Environment
    flavor = $Flavor
    shorebird_patch_number = $ShorebirdPatchNumber
    source_sha = $sourceSha
    engine_revision = [string]$manifest.engine_revision
    dart_debug_files = $dartDebugFiles
    engine_debug_files = $engineDebugFiles
    artifacts = $artifactEvidence
}
$evidence | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $evidenceDirectory 'manifest.json') -Encoding utf8NoBOM
Remove-Item -LiteralPath $engineInspectionRoot -Recurse -Force

# Authenticate only after every local release artifact has passed validation.
Invoke-NativeCommand -FilePath 'npx' -Arguments ($sentryCli + @('info'))

# A previous failed workflow attempt may already have created the release.
& npx @sentryCli releases info $Release *> $null
if ($LASTEXITCODE -ne 0) {
    Invoke-WithRetry -Label 'Sentry release creation' -Operation {
        Invoke-NativeCommand -FilePath 'npx' -Arguments (
            $sentryCli + @('releases', 'new', $Release)
        )
    }
}

Invoke-WithRetry -Label 'Sentry commit association' -Operation {
    Invoke-NativeCommand -FilePath 'npx' -Arguments (
        $sentryCli + @(
            'releases',
            'set-commits',
            $Release,
            '--auto',
            '--ignore-missing'
        )
    )
}

Invoke-WithRetry -Label 'Sentry Shorebird Dart debug symbol upload' -Operation {
    Invoke-NativeCommand -FilePath 'dart' -Arguments @(
        'run',
        'sentry_dart_plugin'
    )
}

Invoke-WithRetry -Label 'Sentry Android mapping upload' -Operation {
    Invoke-NativeCommand -FilePath 'npx' -Arguments (
        $sentryCli + @('upload-proguard', $proguardMappingPath)
    )
}

foreach ($archive in $engineArchives) {
    Invoke-WithRetry -Label "Sentry Shorebird engine symbol upload" -Operation {
        Invoke-NativeCommand -FilePath 'npx' -Arguments ($sentryCli + @('debug-files', 'upload', '--wait', $archive))
    }
}

function Assert-SentryDebugFileAvailable {
    param(
        [string]$Query = '',

        [string]$ExpectedSha1 = '',

        [string]$DebugId = '',

        [string]$CodeId = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($DebugId)) {
        $uri = "https://sentry.io/api/0/projects/$env:SENTRY_ORG/$env:SENTRY_PROJECT/files/dsyms/?debug_id=$([System.Uri]::EscapeDataString($DebugId))"
    }
    else {
        $uri = "https://sentry.io/api/0/projects/$env:SENTRY_ORG/$env:SENTRY_PROJECT/files/dsyms/?query=$([System.Uri]::EscapeDataString($Query))"
    }
    $headers = @{ Authorization = "Bearer $env:SENTRY_AUTH_TOKEN" }
    $response = @(Invoke-RestMethod -Method Get -Uri $uri -Headers $headers)
    $matches = @($response | Where-Object {
        ([string]::IsNullOrWhiteSpace($ExpectedSha1) -or [string]$_.sha1 -eq $ExpectedSha1) -and
        ([string]::IsNullOrWhiteSpace($DebugId) -or [string]$_.debugId -eq $DebugId) -and
        ([string]::IsNullOrWhiteSpace($CodeId) -or [string]$_.codeId -eq $CodeId)
    })
    if ($matches.Count -eq 0) {
        $identity = if (-not [string]::IsNullOrWhiteSpace($DebugId)) { $DebugId } else { $Query }
        throw "Sentry did not report the exact processed debug-information file for $identity."
    }
}

foreach ($dartDebugFile in $dartDebugFiles) {
    Invoke-WithRetry -Label "Sentry Dart symbol verification for $($dartDebugFile.file)" -Operation {
        Assert-SentryDebugFileAvailable `
            -DebugId $dartDebugFile.debug_id `
            -CodeId $dartDebugFile.code_id
    }
}
Invoke-WithRetry -Label 'Sentry R8 mapping verification' -Operation {
    $mappingSha1 = (Get-FileHash -LiteralPath $proguardMappingPath -Algorithm SHA1).Hash.ToLowerInvariant()
    Assert-SentryDebugFileAvailable -Query 'proguard-mapping' -ExpectedSha1 $mappingSha1
}
foreach ($engineDebugFile in $engineDebugFiles) {
    Invoke-WithRetry -Label "Sentry engine DIF verification for $($engineDebugFile.architecture)" -Operation {
        Assert-SentryDebugFileAvailable -DebugId $engineDebugFile.debug_id -CodeId $engineDebugFile.code_id
    }
}

Invoke-WithRetry -Label 'Sentry release finalization' -Operation {
    Invoke-NativeCommand -FilePath 'npx' -Arguments (
        $sentryCli + @('releases', 'finalize', $Release)
    )
}

$deployName = if ([string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID)) {
    "manual-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
}
else {
    $runAttempt = if ([string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ATTEMPT)) {
        '1'
    }
    else {
        $env:GITHUB_RUN_ATTEMPT
    }
    "github-actions-$env:GITHUB_RUN_ID-attempt-$runAttempt"
}
Invoke-WithRetry -Label 'Sentry deploy marker' -Operation {
    Invoke-NativeCommand -FilePath 'npx' -Arguments (
        $sentryCli + @(
            'releases',
            'deploys',
            $Release,
            'new',
            '-e',
            $Environment,
            '-n',
            $deployName
        )
    )
}

Invoke-NativeCommand -FilePath 'npx' -Arguments (
    $sentryCli + @('releases', 'info', $Release)
)
Write-Host "Verified Sentry release $Release with dist $Dist in $Environment."
