# DEPRECATED: Production patches in Owntend now publish directly to track 'stable' via
# tool/invoke_shorebird_patch.ps1. This script is retained only as a manual/emergency
# fallback and is NOT part of the canonical automated production patch pipeline.

param(
    [Parameter(Mandatory = $true)][string]$AppId,
    [Parameter(Mandatory = $true)][string]$ReleaseVersion,
    [Parameter(Mandatory = $true)][int]$PatchNumber,
    [Parameter(Mandatory = $true)][string]$PreviewConfirmation,
    [string]$EvidencePath = 'release\shorebird-promotion-evidence.json'
)

$ErrorActionPreference = 'Stop'
if ($AppId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$') { throw 'AppId must be a canonical UUID.' }
if ($ReleaseVersion -notmatch '^\d+\.\d+\.\d+\+[1-9]\d*$') { throw 'ReleaseVersion must use x.y.z+N.' }
if ($PatchNumber -lt 1) { throw 'PatchNumber must be positive.' }
$expectedConfirmation = "PREVIEWED PATCH $ReleaseVersion#$PatchNumber"
if ($PreviewConfirmation -cne $expectedConfirmation) { throw "Preview confirmation must be exactly: $expectedConfirmation" }
if ([string]::IsNullOrWhiteSpace($env:SHOREBIRD_TOKEN)) { throw 'SHOREBIRD_TOKEN is required.' }

$jsonText = (& shorebird patches list --release-version $ReleaseVersion --app-id $AppId --json 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw "Could not list Shorebird patches.`n$jsonText" }
try { $envelope = $jsonText | ConvertFrom-Json } catch { throw "Shorebird patch-list JSON was invalid.`n$jsonText" }
if ($envelope.status -ne 'success') { throw 'Shorebird patch-list request did not report success.' }
$patch = @($envelope.data.patches | Where-Object { [int]$_.number -eq $PatchNumber })
if ($patch.Count -ne 1) { throw "Expected exactly one Shorebird patch $PatchNumber, found $($patch.Count)." }
if ([bool]$patch[0].is_rolled_back) { throw 'A rolled-back patch cannot be promoted.' }
if ([string]$patch[0].channel -ne 'staging') { throw "Patch must be on staging before promotion; current track is '$($patch[0].channel)'." }

$promotionJson = (& shorebird patches set-track --release $ReleaseVersion --patch $PatchNumber --track stable --app-id $AppId --json 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw "Shorebird promotion failed.`n$promotionJson" }
$promotion = $promotionJson | ConvertFrom-Json
if ($promotion.status -ne 'success' -or $promotion.data.track -ne 'stable' -or [int]$promotion.data.patch_number -ne $PatchNumber) {
    throw 'Shorebird promotion response did not match the requested patch and stable track.'
}
$workspace = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$resolvedEvidence = [System.IO.Path]::GetFullPath((Join-Path $workspace $EvidencePath))
$releaseRoot = [System.IO.Path]::GetFullPath((Join-Path $workspace 'release')) + [System.IO.Path]::DirectorySeparatorChar
if (-not $resolvedEvidence.StartsWith($releaseRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Promotion evidence must remain inside the repository release directory.'
}
New-Item -ItemType Directory -Path (Split-Path -Parent $resolvedEvidence) -Force | Out-Null
$evidence = [ordered]@{
    schema_version = 1
    operation = 'shorebird-patch-promotion'
    app_id = $AppId.ToLowerInvariant()
    release_version = $ReleaseVersion
    patch_number = $PatchNumber
    from_track = 'staging'
    to_track = 'stable'
    device_preview_confirmation = $PreviewConfirmation
    source_sha = (& git -C $workspace rev-parse HEAD).Trim()
    ci_repository = [string]$env:GITHUB_REPOSITORY
    ci_ref = [string]$env:GITHUB_REF
    ci_run_id = [string]$env:GITHUB_RUN_ID
    ci_run_attempt = [string]$env:GITHUB_RUN_ATTEMPT
    generated_at_utc = [DateTime]::UtcNow.ToString('o')
}
[System.IO.File]::WriteAllText($resolvedEvidence, (($evidence | ConvertTo-Json -Depth 5) + "`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Output $resolvedEvidence
