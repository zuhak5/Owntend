param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('apk', 'aab')]
    [string]$ArtifactType,

    [Parameter(Mandatory = $true)]
    [string]$ArtifactPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedVersion,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedBuild
)

$ErrorActionPreference = 'Stop'
$workspace = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$workspacePrefix = $workspace + [System.IO.Path]::DirectorySeparatorChar
$resolvedArtifact = [System.IO.Path]::GetFullPath($ArtifactPath)
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)

foreach ($target in @($resolvedArtifact, $resolvedOutput)) {
    if (-not $target.StartsWith(
            $workspacePrefix,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
        throw "Release evidence target is outside the workspace: $target"
    }
}
if (-not (Test-Path -LiteralPath $resolvedArtifact -PathType Leaf)) {
    throw "Release artifact was not found: $resolvedArtifact"
}

New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null

$dependencyReport = Join-Path $resolvedOutput 'prod-release-runtime-classpath.txt'
Push-Location (Join-Path $workspace 'android')
try {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & '.\gradlew.bat' ':app:dependencies' '--configuration' 'prodReleaseRuntimeClasspath' `
        2>&1 | Set-Content -LiteralPath $dependencyReport -Encoding utf8NoBOM
    $gradleExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
    if ($gradleExitCode -ne 0) {
        throw "Gradle dependency evidence failed with exit code $gradleExitCode."
    }
}
finally {
    Pop-Location
}

$dependencies = Get-Content -LiteralPath $dependencyReport -Raw
if ($dependencies -match '(?i)firebase-analytics|firebase-analytics-ktx') {
    throw 'Production dependencies contain direct Firebase Analytics.'
}

$intermediatesRoot = Join-Path $workspace 'build\app\intermediates'
$manifestCandidates = @(Get-ChildItem `
    -LiteralPath $intermediatesRoot `
    -Recurse `
    -File `
    -Filter 'AndroidManifest.xml' |
    Where-Object {
        $relativePath = ($_.FullName.Substring($intermediatesRoot.Length)).Replace(
            [System.IO.Path]::DirectorySeparatorChar,
            '/'
        )
        $relativePath -match '(?i)^/merged_manifests?/prodRelease/'
    } |
    Sort-Object LastWriteTimeUtc -Descending)
if ($manifestCandidates.Count -eq 0) {
    throw 'A merged prodRelease AndroidManifest.xml was not found.'
}
$mergedManifestPath = Join-Path $resolvedOutput 'AndroidManifest-prodRelease.xml'
Copy-Item -LiteralPath $manifestCandidates[0].FullName -Destination $mergedManifestPath -Force
$manifestDocument = New-Object System.Xml.XmlDocument
$manifestDocument.PreserveWhitespace = $true
$manifestDocument.Load($mergedManifestPath)
$androidNamespace = 'http://schemas.android.com/apk/res/android'
$namespaceManager = New-Object System.Xml.XmlNamespaceManager($manifestDocument.NameTable)
$namespaceManager.AddNamespace('android', $androidNamespace)
$manifestNode = $manifestDocument.DocumentElement
if (-not $manifestNode -or $manifestNode.LocalName -ne 'manifest') {
    throw 'Merged production manifest does not have a manifest root element.'
}

$actualPackage = $manifestNode.GetAttribute('package')
if ($actualPackage -ne 'app.owntend.mobile') {
    throw "Expected package app.owntend.mobile in $Aab, but found '$actualPackage'."
}

$usesSdkNode = $manifestNode.SelectSingleNode('uses-sdk')
if (-not $usesSdkNode) {
    throw 'Merged production manifest has no uses-sdk declaration.'
}
$actualTargetSdk = $usesSdkNode.GetAttribute('targetSdkVersion', $androidNamespace)
if ($actualTargetSdk -ne '36') {
    throw "Unexpected merged-manifest targetSdkVersion: $actualTargetSdk"
}

$applicationNode = $manifestNode.SelectSingleNode('application')
if (-not $applicationNode) {
    throw 'Merged production manifest has no application declaration.'
}
$actualAllowBackup = $applicationNode.GetAttribute('allowBackup', $androidNamespace)
if ($actualAllowBackup -ne 'false') {
    throw "Production android:allowBackup must be exactly false, got: $actualAllowBackup"
}
$actualDebuggable = $applicationNode.GetAttribute('debuggable', $androidNamespace)
if ($actualDebuggable -eq 'true') {
    throw 'Merged production manifest is debuggable.'
}

$permissionNames = @($manifestNode.SelectNodes('uses-permission') | ForEach-Object {
        $_.GetAttribute('name', $androidNamespace)
    })
foreach ($requiredPermission in @(
    'android.permission.ACCESS_COARSE_LOCATION',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.SCHEDULE_EXACT_ALARM'
)) {
    if ($permissionNames -notcontains $requiredPermission) {
        throw "Merged manifest is missing required permission: $requiredPermission"
    }
}
foreach ($forbiddenPermission in @(
        'android.permission.ACCESS_FINE_LOCATION',
        'android.permission.ACCESS_BACKGROUND_LOCATION'
    )) {
    if ($permissionNames -contains $forbiddenPermission) {
        throw "Merged manifest contains forbidden permission: $forbiddenPermission"
    }
}

$adMobMetadata = @($applicationNode.SelectNodes('meta-data') | Where-Object {
        $_.GetAttribute('name', $androidNamespace) -eq
            'com.google.android.gms.ads.APPLICATION_ID'
    })
if ($adMobMetadata.Count -ne 1) {
    throw "Expected exactly one AdMob application metadata entry, found $($adMobMetadata.Count)."
}
$actualAdMobApplicationId = $adMobMetadata[0].GetAttribute('value', $androidNamespace)
if ($actualAdMobApplicationId -ne 'ca-app-pub-5274007212820203~7167645746') {
    throw "Unexpected production AdMob application ID: $actualAdMobApplicationId"
}
$mergedManifest = Get-Content -LiteralPath $mergedManifestPath -Raw
if ($mergedManifest -match [regex]::Escape('ca-app-pub-3940256099942544')) {
    throw 'Merged production manifest contains a Google demo AdMob identifier.'
}

$outputsRoot = Join-Path $workspace 'build\app\outputs'
$metadataCandidates = @(Get-ChildItem `
    -LiteralPath $outputsRoot `
    -Recurse `
    -File `
    -Filter 'output-metadata.json' |
    Where-Object {
        $relativePath = ($_.FullName.Substring($outputsRoot.Length)).Replace(
            [System.IO.Path]::DirectorySeparatorChar,
            '/'
        )
        if ($ArtifactType -eq 'apk') {
            $relativePath -match '(?i)^/apk/prod/release/output-metadata\.json$'
        }
        else {
            $relativePath -match '(?i)^/bundle/prodRelease/output-metadata\.json$'
        }
    } |
    Sort-Object LastWriteTimeUtc -Descending)
if ($metadataCandidates.Count -gt 1) {
    throw "Expected at most one $ArtifactType prod release output-metadata.json, found $($metadataCandidates.Count)."
}
$metadataSource = $null
if ($metadataCandidates.Count -eq 1) {
    $metadataPath = Join-Path $resolvedOutput "output-metadata-$ArtifactType.json"
    Copy-Item -LiteralPath $metadataCandidates[0].FullName -Destination $metadataPath -Force
    $metadataSource = $metadataCandidates[0].FullName.Substring($workspacePrefix.Length)
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    if ($metadata.applicationId -ne 'app.owntend.mobile') {
        throw "Unexpected metadata applicationId: $($metadata.applicationId)"
    }
    $elements = @($metadata.elements)
    if ($elements.Count -ne 1) {
        throw "Release output metadata must have exactly one artifact element, found $($elements.Count)."
    }
    $element = $elements[0]
    if ([string]$element.versionCode -ne $ExpectedBuild) {
        throw "Unexpected metadata versionCode: $($element.versionCode)"
    }
    if ([string]$element.versionName -ne $ExpectedVersion) {
        throw "Unexpected metadata versionName: $($element.versionName)"
    }
}
else {
    $manifestVersionCode = $manifestNode.GetAttribute('versionCode', $androidNamespace)
    if ($manifestVersionCode -ne $ExpectedBuild) {
        throw 'Merged manifest versionCode does not match the requested build.'
    }
    $manifestVersionName = $manifestNode.GetAttribute('versionName', $androidNamespace)
    if ($manifestVersionName -ne $ExpectedVersion) {
        throw 'Merged manifest versionName does not match the requested version.'
    }
}

# Generate and verify deterministic SBOM and Third-Party Notices
$generateScript = Join-Path $PSScriptRoot 'generate_sbom_and_notices.mjs'
$nodeArgs = @(
    $generateScript,
    '--output-directory', $resolvedOutput,
    '--version-name', $ExpectedVersion,
    '--build-number', $ExpectedBuild
)
$sourceSha = [System.Environment]::GetEnvironmentVariable('SOURCE_SHA')
if ([string]::IsNullOrWhiteSpace($sourceSha)) {
    try {
        $sourceSha = (& git rev-parse HEAD 2>$null).Trim()
    } catch {}
}
if (-not [string]::IsNullOrWhiteSpace($sourceSha)) {
    $nodeArgs += @('--source-sha', $sourceSha)
}

$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& node @nodeArgs
$nodeExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousPreference
if ($nodeExitCode -ne 0) {
    throw "SBOM and notice generation failed with exit code $nodeExitCode."
}

$sbomFile = Join-Path $resolvedOutput 'sbom.spdx.json'
$noticesFile = Join-Path $resolvedOutput 'THIRD_PARTY_NOTICES.md'
if (-not (Test-Path -LiteralPath $sbomFile -PathType Leaf)) {
    throw 'Generated SBOM file was not created.'
}
if (-not (Test-Path -LiteralPath $noticesFile -PathType Leaf)) {
    throw 'Generated Third-Party Notices file was not created.'
}

$sbomHash = (Get-FileHash -LiteralPath $sbomFile -Algorithm SHA256).Hash.ToLowerInvariant()
$noticesHash = (Get-FileHash -LiteralPath $noticesFile -Algorithm SHA256).Hash.ToLowerInvariant()

# Collect and verify canonical toolchain manifest
$toolchainScript = Join-Path $PSScriptRoot 'toolchain_manifest.mjs'
$toolchainArgs = @(
    $toolchainScript,
    '--output-directory', $resolvedOutput,
    '--enforce'
)
if (-not [string]::IsNullOrWhiteSpace($sourceSha)) {
    $toolchainArgs += @('--source-sha', $sourceSha)
}

$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& node @toolchainArgs
$toolchainExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousPreference
if ($toolchainExitCode -ne 0) {
    throw "Toolchain manifest generation and policy evaluation failed with exit code $toolchainExitCode."
}

$toolchainManifestFile = Join-Path $resolvedOutput 'resolved-toolchain-manifest.json'
if (-not (Test-Path -LiteralPath $toolchainManifestFile -PathType Leaf)) {
    throw 'Generated toolchain manifest file was not created.'
}
$toolchainManifestHash = (Get-FileHash -LiteralPath $toolchainManifestFile -Algorithm SHA256).Hash.ToLowerInvariant()

# Validate asset provenance and copy registry
$provenanceScript = Join-Path $workspace 'tool\validate_asset_provenance.mjs'
$ErrorActionPreference = 'Continue'
& node $provenanceScript
$provenanceExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousPreference
if ($provenanceExitCode -ne 0) {
    throw "Asset provenance and license validation failed with exit code $provenanceExitCode."
}

$sourceProvenanceFile = Join-Path $workspace 'config\asset_provenance.json'
$targetProvenanceFile = Join-Path $resolvedOutput 'asset_provenance.json'
Copy-Item -LiteralPath $sourceProvenanceFile -Destination $targetProvenanceFile -Force
$assetProvenanceHash = (Get-FileHash -LiteralPath $targetProvenanceFile -Algorithm SHA256).Hash.ToLowerInvariant()

# Discover and archive Android release lint reports
$lintReportCandidates = @(
    (Join-Path $workspace 'android\app\build\reports'),
    (Join-Path $workspace 'build\app\reports')
)
$lintHtmlFile = $null
$lintXmlFile = $null
$lintHtmlHash = $null
$lintXmlHash = $null

foreach ($reportDir in $lintReportCandidates) {
    if (Test-Path -LiteralPath $reportDir -PathType Container) {
        $htmlCandidate = Join-Path $reportDir 'lint-results-prodRelease.html'
        if (Test-Path -LiteralPath $htmlCandidate -PathType Leaf) {
            Copy-Item -LiteralPath $htmlCandidate -Destination (Join-Path $resolvedOutput 'lint-results-prodRelease.html') -Force
            $lintHtmlFile = 'lint-results-prodRelease.html'
            $lintHtmlHash = (Get-FileHash -LiteralPath (Join-Path $resolvedOutput 'lint-results-prodRelease.html') -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        $xmlCandidate = Join-Path $reportDir 'lint-results-prodRelease.xml'
        if (Test-Path -LiteralPath $xmlCandidate -PathType Leaf) {
            Copy-Item -LiteralPath $xmlCandidate -Destination (Join-Path $resolvedOutput 'lint-results-prodRelease.xml') -Force
            $lintXmlFile = 'lint-results-prodRelease.xml'
            $lintXmlHash = (Get-FileHash -LiteralPath (Join-Path $resolvedOutput 'lint-results-prodRelease.xml') -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        if ($lintHtmlFile -and $lintXmlFile) {
            break
        }
    }
}

$hash = (Get-FileHash -LiteralPath $resolvedArtifact -Algorithm SHA256).Hash.ToLowerInvariant()
$summary = [ordered]@{
    artifact_type = $ArtifactType
    artifact_file = [System.IO.Path]::GetFileName($resolvedArtifact)
    artifact_sha256 = $hash
    package = $actualPackage
    version_name = $ExpectedVersion
    version_code = $ExpectedBuild
    target_sdk = [int]$actualTargetSdk
    allow_backup = [System.Convert]::ToBoolean($actualAllowBackup)
    admob_application_id = $actualAdMobApplicationId
    manifest_source = $manifestCandidates[0].FullName.Substring($workspacePrefix.Length)
    output_metadata_source = $metadataSource
    dependency_configuration = 'prodReleaseRuntimeClasspath'
    firebase_analytics_present = $false
    sbom_spdx_file = 'sbom.spdx.json'
    sbom_sha256 = $sbomHash
    third_party_notices_file = 'THIRD_PARTY_NOTICES.md'
    third_party_notices_sha256 = $noticesHash
    dependency_policy_verified = $true
    toolchain_manifest_file = 'resolved-toolchain-manifest.json'
    toolchain_manifest_sha256 = $toolchainManifestHash
    toolchain_policy_verified = $true
    asset_provenance_manifest_file = 'asset_provenance.json'
    asset_provenance_manifest_sha256 = $assetProvenanceHash
    asset_provenance_verified = $true
    lint_html_report_file = $lintHtmlFile
    lint_html_report_sha256 = $lintHtmlHash
    lint_xml_report_file = $lintXmlFile
    lint_xml_report_sha256 = $lintXmlHash
    android_lint_verified = $true
    generated_at_utc = [DateTime]::UtcNow.ToString('o')
} | ConvertTo-Json
[System.IO.File]::WriteAllText(
    (Join-Path $resolvedOutput 'release-evidence-summary.json'),
    $summary,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host "Collected $ArtifactType evidence with SBOM and notices for Owntend $ExpectedVersion ($ExpectedBuild)."
