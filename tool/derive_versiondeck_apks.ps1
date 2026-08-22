param(
    [Parameter(Mandatory = $true)][string]$AppBundle,
    [Parameter(Mandatory = $true)][string]$ExpectedVersion,
    [Parameter(Mandatory = $true)][string]$ExpectedBuild,
    [Parameter(Mandatory = $true)][string]$KeystorePath,
    [Parameter(Mandatory = $true)][string]$KeyAlias,
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
$workspace = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
if ($ExpectedVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'ExpectedVersion must use x.y.z.' }
if ($ExpectedBuild -notmatch '^[1-9]\d*$') { throw 'ExpectedBuild must be a positive integer.' }
foreach ($name in @('ANDROID_APK_KEYSTORE_PASSWORD', 'ANDROID_APK_KEY_PASSWORD')) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) { throw "Missing signing secret: $name" }
}
$resolvedAab = [System.IO.Path]::GetFullPath($AppBundle)
$resolvedKeystore = [System.IO.Path]::GetFullPath($KeystorePath)
if (-not (Test-Path -LiteralPath $resolvedAab -PathType Leaf)) { throw "AAB is missing: $resolvedAab" }
if (-not (Test-Path -LiteralPath $resolvedKeystore -PathType Leaf)) { throw "Keystore is missing: $resolvedKeystore" }
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $workspace 'release\shorebird-apk-evidence' }
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
$releaseRoot = [System.IO.Path]::GetFullPath((Join-Path $workspace 'release'))
if (-not $resolvedOutput.StartsWith($releaseRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputDirectory must remain inside the repository release directory.'
}
if (Test-Path -LiteralPath $resolvedOutput) { Remove-Item -LiteralPath $resolvedOutput -Recurse -Force }
$artifactRoot = Join-Path $resolvedOutput 'artifacts'
$metadataRoot = Join-Path $resolvedOutput 'metadata'
$symbolsRoot = Join-Path $resolvedOutput 'symbols'
New-Item -ItemType Directory -Path $artifactRoot, $metadataRoot, $symbolsRoot -Force | Out-Null

$toolchain = Get-Content -LiteralPath (Join-Path $workspace 'config\toolchain.json') -Raw | ConvertFrom-Json
$buildToolsVersion = [string]$toolchain.canonicalToolchain.android.buildToolsVersion
$sdkRoot = if (-not [string]::IsNullOrWhiteSpace($env:ANDROID_HOME)) { $env:ANDROID_HOME } else { $env:ANDROID_SDK_ROOT }
if ([string]::IsNullOrWhiteSpace($sdkRoot)) { throw 'ANDROID_HOME or ANDROID_SDK_ROOT is required.' }
$buildTools = Join-Path $sdkRoot "build-tools\$buildToolsVersion"
$apksigner = Join-Path $buildTools 'apksigner.bat'
$zipalign = Join-Path $buildTools 'zipalign.exe'
$aapt2 = Join-Path $buildTools 'aapt2.exe'
foreach ($tool in @($apksigner, $zipalign, $aapt2)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Required Android tool is missing: $tool" }
}
$bundletool = (& (Join-Path $PSScriptRoot 'download_bundletool.ps1') | Select-Object -Last 1)
if (-not (Test-Path -LiteralPath $bundletool -PathType Leaf)) { throw 'Pinned bundletool download failed.' }

$temporaryRoot = Join-Path $workspace 'build\versiondeck-apk-derivation'
if (Test-Path -LiteralPath $temporaryRoot) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
$apksArchive = Join-Path $temporaryRoot 'universal.apks'
& java -jar $bundletool build-apks `
    "--bundle=$resolvedAab" `
    "--output=$apksArchive" `
    --mode=universal `
    "--ks=$resolvedKeystore" `
    "--ks-key-alias=$KeyAlias" `
    --ks-pass=env:ANDROID_APK_KEYSTORE_PASSWORD `
    --key-pass=env:ANDROID_APK_KEY_PASSWORD `
    --overwrite
if ($LASTEXITCODE -ne 0) { throw "Pinned bundletool failed with exit code $LASTEXITCODE." }

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$extracted = Join-Path $temporaryRoot 'apks'
[System.IO.Compression.ZipFile]::ExtractToDirectory($apksArchive, $extracted)
$generatedUniversal = Join-Path $extracted 'universal.apk'
if (-not (Test-Path -LiteralPath $generatedUniversal -PathType Leaf)) { throw 'Bundletool did not produce universal.apk.' }

$expectedPackage = 'app.owntend.mobile'
$expectedSigner = '3e980eb5bb68a51990e77056d4e10995b2e04fb388a73442b79a46c853361e51'
$expectedAbis = @('arm64-v8a', 'armeabi-v7a', 'x86_64')
$symbolFileByAbi = @{
    'arm64-v8a' = 'app.android-arm64.symbols'
    'armeabi-v7a' = 'app.android-arm.symbols'
    'x86_64' = 'app.android-x64.symbols'
}

function Write-Utf8([string]$Path, [string]$Content) {
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}
function Get-ApkAbis([string]$Path) {
    $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        return @($archive.Entries | ForEach-Object {
            if ($_.FullName -match '^lib/([^/]+)/') { $Matches[1] }
        } | Sort-Object -Unique)
    }
    finally { $archive.Dispose() }
}
function Remove-OtherAbis([string]$Path, [string]$KeepAbi) {
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    try {
        $archive = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Update, $false)
        try {
            foreach ($entry in @($archive.Entries)) {
                if ($entry.FullName -match '^lib/([^/]+)/' -and $Matches[1] -ne $KeepAbi) { $entry.Delete() }
            }
        }
        finally { $archive.Dispose() }
    }
    finally { $stream.Dispose() }
}
function Inspect-Apk([string]$Path, [string]$Label) {
    $signature = (& $apksigner verify --verbose --print-certs $Path 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) { throw "APK signature verification failed for $Label.`n$signature" }
    if ($signature -notmatch '(?:Signer #\d+|V\d+(?:\.\d+)? Signer:)\s+certificate SHA-256 digest:\s*([0-9A-Fa-f:]+)') { throw "Signer was not found for $Label." }
    $signer = ($Matches[1] -replace '[^0-9A-Fa-f]', '').ToLowerInvariant()
    if ($signer -ne $expectedSigner) { throw "Unexpected signer for ${Label}: $signer" }
    $badging = (& $aapt2 dump badging $Path 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0 -or $badging -notmatch "package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'") { throw "Package metadata was not found for $Label." }
    if ($Matches[1] -ne $expectedPackage -or $Matches[2] -ne $ExpectedBuild -or $Matches[3] -ne $ExpectedVersion) { throw "Package/version mismatch for $Label." }
    if ($badging -match '(?m)^application-debuggable') { throw "Production APK is debuggable: $Label" }
    return [ordered]@{ signature = $signature; badging = $badging; signer = $signer }
}

$releasePrefix = "Owntend-$ExpectedVersion-build-$ExpectedBuild"
$universalName = "$releasePrefix-universal.apk"
$universalPath = Join-Path $artifactRoot $universalName
Copy-Item -LiteralPath $generatedUniversal -Destination $universalPath -Force
$universalInspection = Inspect-Apk $universalPath 'universal'
Write-Utf8 (Join-Path $metadataRoot 'apk-signature-universal.txt') $universalInspection.signature
Write-Utf8 (Join-Path $metadataRoot 'apk-badging-universal.txt') $universalInspection.badging
$universalHash = (Get-FileHash -LiteralPath $universalPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Utf8 (Join-Path $artifactRoot "$universalName.sha256") "$universalHash  $universalName`n"

$sourceSha = (& git -C $workspace rev-parse HEAD).Trim()
$records = @()
foreach ($abi in $expectedAbis) {
    $working = Join-Path $temporaryRoot "$abi-mutated.apk"
    Copy-Item -LiteralPath $generatedUniversal -Destination $working -Force
    Remove-OtherAbis $working $abi
    $aligned = Join-Path $temporaryRoot "$abi-aligned.apk"
    & $zipalign -f -p 4 $working $aligned
    if ($LASTEXITCODE -ne 0) { throw "zipalign failed for $abi." }
    $name = "$releasePrefix-$abi.apk"
    $destination = Join-Path $artifactRoot $name
    & $apksigner sign `
        --ks $resolvedKeystore `
        --ks-key-alias $KeyAlias `
        --ks-pass env:ANDROID_APK_KEYSTORE_PASSWORD `
        --key-pass env:ANDROID_APK_KEY_PASSWORD `
        --out $destination `
        $aligned
    if ($LASTEXITCODE -ne 0) { throw "apksigner failed for $abi." }
    $abis = @(Get-ApkAbis $destination)
    if ($abis.Count -ne 1 -or $abis[0] -ne $abi) { throw "Derived APK $abi has unexpected native directories: $($abis -join ', ')." }
    $inspection = Inspect-Apk $destination $abi
    $hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Utf8 (Join-Path $artifactRoot "$name.sha256") "$hash  $name`n"
    Write-Utf8 (Join-Path $metadataRoot "apk-signature-$abi.txt") $inspection.signature
    Write-Utf8 (Join-Path $metadataRoot "apk-badging-$abi.txt") $inspection.badging
    $sizeReportName = "apk-size-report-$abi.json"
    & node (Join-Path $PSScriptRoot 'android_apk_size_report.mjs') --apk $destination --source-sha $sourceSha --version-name $ExpectedVersion --version-code $ExpectedBuild --abi $abi --output (Join-Path $metadataRoot $sizeReportName)
    if ($LASTEXITCODE -ne 0) { throw "APK size reporting failed for $abi." }
    $symbolName = $symbolFileByAbi[$abi]
    $symbolSource = Join-Path $workspace "build\shorebird-symbols\prod\base\$symbolName"
    if (-not (Test-Path -LiteralPath $symbolSource -PathType Leaf)) { throw "Shorebird Dart symbols are missing: $symbolSource" }
    Copy-Item -LiteralPath $symbolSource -Destination (Join-Path $symbolsRoot $symbolName) -Force
    $records += [ordered]@{
        abi = $abi; file = "artifacts/$name"; checksum_file = "artifacts/$name.sha256"
        sha256 = $hash; total_bytes = (Get-Item -LiteralPath $destination).Length
        package = $expectedPackage; version_name = $ExpectedVersion; version_code = [int]$ExpectedBuild
        signer_sha256 = $expectedSigner; native_abis = @($abis)
        badging_file = "metadata/apk-badging-$abi.txt"; signature_file = "metadata/apk-signature-$abi.txt"
        size_report_file = "metadata/$sizeReportName"; dart_symbols_file = "symbols/$symbolName"
    }
}

$r8Source = Join-Path $workspace 'build\app\outputs\mapping\prodRelease\mapping.txt'
if (-not (Test-Path -LiteralPath $r8Source -PathType Leaf)) { throw 'R8 mapping from the canonical AAB build is missing.' }
Copy-Item -LiteralPath $r8Source -Destination (Join-Path $symbolsRoot 'mapping.txt') -Force
$aabHash = (Get-FileHash -LiteralPath $resolvedAab -Algorithm SHA256).Hash.ToLowerInvariant()
$index = [ordered]@{
    schema_version = 2
    evidence_mode = 'protected-shorebird-aab-derived-apk-evidence'
    derivation_mode = 'pinned-bundletool-universal-pruned-per-abi'
    source_sha = $sourceSha; version_name = $ExpectedVersion; version_code = [int]$ExpectedBuild
    package = $expectedPackage; expected_signer_sha256 = $expectedSigner; expected_abis = $expectedAbis
    canonical_aab_sha256 = $aabHash
    bundletool_version = [string]$toolchain.canonicalToolchain.tools.bundletool.version
    bundletool_sha256 = (Get-FileHash -LiteralPath $bundletool -Algorithm SHA256).Hash.ToLowerInvariant()
    universal_apk_file = "artifacts/$universalName"; universal_apk_sha256 = $universalHash
    universal_apk_remains_authoritative = $true; public_distribution_authorized = $false; versiondeck_publication_authorized = $false
    artifacts = $records; r8_mapping_file = 'symbols/mapping.txt'; generated_at_utc = [DateTime]::UtcNow.ToString('o')
}
Write-Utf8 (Join-Path $resolvedOutput 'abi-evidence-index.json') (($index | ConvertTo-Json -Depth 8) + "`n")
Write-Host "Derived one universal and three single-ABI APKs from canonical AAB SHA-256 $aabHash."
Write-Output $resolvedOutput
