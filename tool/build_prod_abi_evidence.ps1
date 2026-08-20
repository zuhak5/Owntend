param(
    [Parameter(Mandatory = $true)]
    [string]$ExpectedVersion,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedBuild
)

$ErrorActionPreference = 'Stop'
$workspace = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$configPath = Join-Path $workspace 'config\prod.json'
$universalApk = Join-Path $workspace 'build\app\outputs\flutter-apk\app-release.apk'
$splitOutputDirectory = Join-Path $workspace 'build\app\outputs\flutter-apk'
$splitDebugRoot = Join-Path $workspace 'build\sentry-debug\abi-apk'
$splitObfuscationMap = Join-Path $splitDebugRoot 'mapping.json'
$evidenceRoot = Join-Path $workspace 'release\abi-apk-evidence'
$artifactRoot = Join-Path $evidenceRoot 'artifacts'
$metadataRoot = Join-Path $evidenceRoot 'metadata'
$symbolsRoot = Join-Path $evidenceRoot 'symbols'

$expectedPackage = 'app.owntend.mobile'
$expectedSigner = '3E:98:0E:B5:BB:68:A5:19:90:E7:70:56:D4:E1:09:95:B2:E0:4F:B3:88:A7:34:42:B7:9A:46:C8:53:36:1E:51'
$expectedSignerNormalized = ($expectedSigner -replace '[^0-9A-Fa-f]', '').ToLowerInvariant()
$expectedAbis = @('arm64-v8a', 'armeabi-v7a', 'x86_64')
$symbolFileByAbi = @{
    'arm64-v8a' = 'app.android-arm64.symbols'
    'armeabi-v7a' = 'app.android-arm.symbols'
    'x86_64' = 'app.android-x64.symbols'
}

function Invoke-Flutter {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & flutter @Arguments
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    if ($exitCode -ne 0) {
        throw "flutter $($Arguments -join ' ') failed with exit code $exitCode."
    }
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    [System.IO.File]::WriteAllText(
        $Path,
        $Content,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

if ($ExpectedVersion -notmatch '^\d+\.\d+\.\d+$') {
    throw "ExpectedVersion must use x.y.z, got: $ExpectedVersion"
}
if ($ExpectedBuild -notmatch '^\d+$') {
    throw "ExpectedBuild must be numeric, got: $ExpectedBuild"
}
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw 'Missing config\prod.json. ABI evidence must run inside the protected production APK job.'
}
if (-not (Test-Path -LiteralPath $universalApk -PathType Leaf)) {
    throw 'The canonical universal production APK must be built before ABI evidence is generated.'
}

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
if ($config.APP_ENV -ne 'prod' -or
    [string]::IsNullOrWhiteSpace([string]$config.SUPABASE_URL) -or
    [string]::IsNullOrWhiteSpace([string]$config.SUPABASE_PUBLISHABLE_KEY) -or
    [string]::IsNullOrWhiteSpace([string]$config.GOOGLE_WEB_CLIENT_ID) -or
    $config.SENTRY_ENABLED -ne $true -or
    [string]::IsNullOrWhiteSpace([string]$config.SENTRY_DSN)) {
    throw 'config\prod.json does not satisfy the production configuration contract.'
}

$headSha = (& git rev-parse HEAD 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($headSha)) {
    throw 'Could not resolve the current source SHA.'
}
$sourceSha = if ([string]::IsNullOrWhiteSpace($env:GITHUB_SHA)) { $headSha } else { $env:GITHUB_SHA }
if ($sourceSha -ne $headSha) {
    throw "ABI evidence source $headSha differs from GITHUB_SHA $sourceSha."
}

$buildTools = Get-ChildItem (Join-Path $env:ANDROID_HOME 'build-tools') -Directory |
    Sort-Object { [version]$_.Name } -Descending |
    Select-Object -First 1
if (-not $buildTools) {
    throw 'Android build tools were not found.'
}
$apkSigner = Join-Path $buildTools.FullName 'apksigner.bat'
$aapt2 = Join-Path $buildTools.FullName 'aapt2.exe'
if (-not (Test-Path -LiteralPath $apkSigner -PathType Leaf) -or
    -not (Test-Path -LiteralPath $aapt2 -PathType Leaf)) {
    throw "apksigner or aapt2 was not found in $($buildTools.FullName)."
}

if (Test-Path -LiteralPath $splitDebugRoot) {
    Remove-Item -LiteralPath $splitDebugRoot -Recurse -Force
}
if (Test-Path -LiteralPath $evidenceRoot) {
    Remove-Item -LiteralPath $evidenceRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $splitDebugRoot -Force | Out-Null
New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
New-Item -ItemType Directory -Path $metadataRoot -Force | Out-Null
New-Item -ItemType Directory -Path $symbolsRoot -Force | Out-Null

$productionDefines = @("--dart-define-from-file=$configPath")
$dartBuildFlags = @(
    '--obfuscate',
    "--split-debug-info=$splitDebugRoot",
    "--extra-gen-snapshot-options=--save-obfuscation-map=$splitObfuscationMap"
)

Push-Location $workspace
try {
    Invoke-Flutter -Arguments (
        @(
            'build', 'apk',
            '--flavor', 'prod',
            '--release',
            '--split-per-abi',
            '-P', 'force-version-code-ignoring-abi=true'
        ) + $productionDefines + $dartBuildFlags
    )
}
finally {
    Pop-Location
}

if (-not (Test-Path -LiteralPath $splitObfuscationMap -PathType Leaf)) {
    throw "Split APK obfuscation map was not generated: $splitObfuscationMap"
}

$splitApks = @(Get-ChildItem -LiteralPath $splitOutputDirectory -File |
    Where-Object { $_.Name -match '^app-(arm64-v8a|armeabi-v7a|x86_64)-prod-release\.apk$' })
if ($splitApks.Count -ne $expectedAbis.Count) {
    throw "Expected exactly $($expectedAbis.Count) production ABI APKs, found $($splitApks.Count)."
}

$r8MappingPath = Join-Path $workspace 'build\app\outputs\mapping\prodRelease\mapping.txt'
if (-not (Test-Path -LiteralPath $r8MappingPath -PathType Leaf)) {
    throw "Android R8 mapping file was not generated for ABI evidence: $r8MappingPath"
}
Copy-Item -LiteralPath $r8MappingPath -Destination (Join-Path $symbolsRoot 'mapping.txt') -Force
Copy-Item -LiteralPath $splitObfuscationMap -Destination (Join-Path $symbolsRoot 'obfuscation-map.json') -Force

$outputMetadataSource = Join-Path $workspace 'build\app\outputs\apk\prod\release\output-metadata.json'
if (Test-Path -LiteralPath $outputMetadataSource -PathType Leaf) {
    Copy-Item -LiteralPath $outputMetadataSource -Destination (Join-Path $metadataRoot 'output-metadata-apk.json') -Force
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$artifactRecords = @()

foreach ($abi in $expectedAbis) {
    $sourceApk = Join-Path $splitOutputDirectory "app-$abi-prod-release.apk"
    if (-not (Test-Path -LiteralPath $sourceApk -PathType Leaf)) {
        throw "Missing expected ABI APK: $sourceApk"
    }

    $releaseName = "Owntend-$ExpectedVersion-build-$ExpectedBuild-$abi.apk"
    $releaseApk = Join-Path $artifactRoot $releaseName
    Copy-Item -LiteralPath $sourceApk -Destination $releaseApk -Force

    $hash = (Get-FileHash -LiteralPath $releaseApk -Algorithm SHA256).Hash.ToLowerInvariant()
    $checksumName = "$releaseName.sha256"
    $checksumPath = Join-Path $artifactRoot $checksumName
    Write-Utf8NoBom -Path $checksumPath -Content "$hash  $releaseName`n"

    $signatureOutput = (& $apkSigner verify --verbose --print-certs $releaseApk 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "APK signature verification failed for $abi.`n$signatureOutput"
    }
    if ($signatureOutput -notmatch '(?:Signer #\d+|V\d+(?:\.\d+)? Signer:)\s+certificate SHA-256 digest:\s*([0-9A-Fa-f:]+)') {
        throw "The signer SHA-256 could not be extracted for $abi.`n$signatureOutput"
    }
    $actualSignerNormalized = ($Matches[1] -replace '[^0-9A-Fa-f]', '').ToLowerInvariant()
    if ($actualSignerNormalized -ne $expectedSignerNormalized) {
        throw "Unexpected production signer for $abi. Expected $expectedSigner, got $($Matches[1])."
    }
    $signatureFile = "apk-signature-$abi.txt"
    Write-Utf8NoBom -Path (Join-Path $metadataRoot $signatureFile) -Content $signatureOutput

    $badging = (& $aapt2 dump badging $releaseApk 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "APK metadata inspection failed for $abi.`n$badging"
    }
    if ($badging -notmatch "package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'") {
        throw "Package metadata could not be parsed for $abi.`n$badging"
    }
    $actualPackage = $Matches[1]
    $actualBuild = $Matches[2]
    $actualVersion = $Matches[3]
    if ($actualPackage -ne $expectedPackage) {
        throw "Unexpected package for $abi: $actualPackage"
    }
    if ($actualVersion -ne $ExpectedVersion) {
        throw "Unexpected versionName for $abi: $actualVersion"
    }
    if ($actualBuild -ne $ExpectedBuild) {
        throw "Unexpected versionCode for $abi: $actualBuild. Split APKs must preserve the pubspec build number."
    }
    if ($badging -match '(?m)^application-debuggable') {
        throw "Production ABI APK is debuggable: $abi"
    }
    $badgingFile = "apk-badging-$abi.txt"
    Write-Utf8NoBom -Path (Join-Path $metadataRoot $badgingFile) -Content $badging

    $archive = [System.IO.Compression.ZipFile]::OpenRead($releaseApk)
    try {
        $libAbis = @($archive.Entries |
            ForEach-Object {
                if ($_.FullName -match '^lib/([^/]+)/') { $Matches[1] }
            } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique)
    }
    finally {
        $archive.Dispose()
    }
    if ($libAbis.Count -ne 1 -or $libAbis[0] -ne $abi) {
        throw "ABI APK $abi contains unexpected native directories: $($libAbis -join ', ')."
    }

    $symbolFile = $symbolFileByAbi[$abi]
    $symbolSource = Join-Path $splitDebugRoot $symbolFile
    if (-not (Test-Path -LiteralPath $symbolSource -PathType Leaf)) {
        throw "Missing Dart symbols for $abi: $symbolSource"
    }
    Copy-Item -LiteralPath $symbolSource -Destination (Join-Path $symbolsRoot $symbolFile) -Force

    $sizeReportFile = "apk-size-report-$abi.json"
    $sizeReportPath = Join-Path $metadataRoot $sizeReportFile
    & node (Join-Path $PSScriptRoot 'android_apk_size_report.mjs') `
        --apk $releaseApk `
        --source-sha $sourceSha `
        --version-name $ExpectedVersion `
        --version-code $ExpectedBuild `
        --abi $abi `
        --output $sizeReportPath
    if ($LASTEXITCODE -ne 0) {
        throw "APK size reporting failed for $abi."
    }

    $sizeReport = Get-Content -LiteralPath $sizeReportPath -Raw | ConvertFrom-Json
    $actualLength = (Get-Item -LiteralPath $releaseApk).Length
    if ([string]$sizeReport.artifactSha256 -ne $hash) {
        throw "APK size report hash mismatch for $abi."
    }
    if ([int64]$sizeReport.totalBytes -ne [int64]$actualLength) {
        throw "APK size report length mismatch for $abi."
    }
    $reportedLibAbis = @($sizeReport.components.lib.byAbi.PSObject.Properties.Name)
    if ($reportedLibAbis.Count -ne 1 -or $reportedLibAbis[0] -ne $abi) {
        throw "APK size report ABI mismatch for $abi: $($reportedLibAbis -join ', ')."
    }

    $artifactRecords += [ordered]@{
        abi = $abi
        file = "artifacts/$releaseName"
        checksum_file = "artifacts/$checksumName"
        sha256 = $hash
        total_bytes = [int64]$actualLength
        package = $actualPackage
        version_name = $actualVersion
        version_code = [int]$actualBuild
        signer_sha256 = $expectedSignerNormalized
        native_abis = @($libAbis)
        badging_file = "metadata/$badgingFile"
        signature_file = "metadata/$signatureFile"
        size_report_file = "metadata/$sizeReportFile"
        dart_symbols_file = "symbols/$symbolFile"
    }
}

$recordAbis = @($artifactRecords | ForEach-Object { $_.abi } | Sort-Object)
$expectedSorted = @($expectedAbis | Sort-Object)
if (($recordAbis -join ',') -ne ($expectedSorted -join ',')) {
    throw 'ABI evidence artifact set is incomplete or contains unexpected architectures.'
}

$index = [ordered]@{
    schema_version = 1
    evidence_mode = 'protected-abi-apk-evidence'
    source_sha = $sourceSha
    version_name = $ExpectedVersion
    version_code = [int]$ExpectedBuild
    package = $expectedPackage
    expected_signer_sha256 = $expectedSignerNormalized
    expected_abis = $expectedAbis
    universal_apk_remains_authoritative = $true
    public_distribution_authorized = $false
    versiondeck_publication_authorized = $false
    artifacts = $artifactRecords
    r8_mapping_file = 'symbols/mapping.txt'
    dart_obfuscation_map_file = 'symbols/obfuscation-map.json'
    output_metadata_file = if (Test-Path -LiteralPath (Join-Path $metadataRoot 'output-metadata-apk.json')) {
        'metadata/output-metadata-apk.json'
    }
    else {
        $null
    }
    generated_at_utc = [DateTime]::UtcNow.ToString('o')
}
Write-Utf8NoBom -Path (Join-Path $evidenceRoot 'abi-evidence-index.json') -Content (($index | ConvertTo-Json -Depth 8) + "`n")

Write-Host "Generated protected ABI APK evidence for $($expectedAbis -join ', ') at exact versionCode $ExpectedBuild."
Write-Host 'The universal APK remains authoritative; this evidence does not authorize VersionDeck publication.'
