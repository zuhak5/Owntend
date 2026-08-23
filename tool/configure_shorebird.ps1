param(
    [string]$DevAppId = $env:SHOREBIRD_DEV_APP_ID,
    [string]$StagingAppId = $env:SHOREBIRD_STAGING_APP_ID,
    [string]$ProdAppId = $env:SHOREBIRD_PROD_APP_ID,
    [switch]$EnsurePubspecAsset
)

$ErrorActionPreference = 'Stop'
$workspace = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$templatePath = Join-Path $workspace 'shorebird.yaml.template'
$outputPath = Join-Path $workspace 'shorebird.yaml'
$pubspecPath = Join-Path $workspace 'pubspec.yaml'
$uuidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'

$ids = [ordered]@{
    SHOREBIRD_DEV_APP_ID = $DevAppId
    SHOREBIRD_STAGING_APP_ID = $StagingAppId
    SHOREBIRD_PROD_APP_ID = $ProdAppId
}
foreach ($key in @($ids.Keys)) {
    $value = [string]$ids[$key]
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Missing Shorebird app ID: $key. App IDs are GitHub Variables, not secrets."
    }
    $value = $value.Trim().ToLowerInvariant()
    if ($value -notmatch $uuidPattern) {
        throw "$key is not a canonical UUID: $value"
    }
    $ids[$key] = $value
}
if ((@($ids.Values | Sort-Object -Unique)).Count -ne 3) {
    throw 'The dev, staging, and prod Shorebird app IDs must be distinct.'
}

$content = Get-Content -LiteralPath $templatePath -Raw
foreach ($entry in $ids.GetEnumerator()) {
    $content = $content.Replace('${' + $entry.Key + '}', [string]$entry.Value)
}
if ($content -match '\$\{SHOREBIRD_[A-Z_]+\}') {
    throw 'shorebird.yaml contains an unresolved app-ID placeholder.'
}
[System.IO.File]::WriteAllText(
    $outputPath,
    $content,
    (New-Object System.Text.UTF8Encoding($false))
)

# Shorebird CLI automatically handles bundling shorebird.yaml into assets
# during release and patch builds. Do not inject raw shorebird.yaml into pubspec.yaml.

$hash = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "Generated ignored shorebird.yaml for dev, staging, and prod (SHA-256 $hash)."
