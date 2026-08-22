param([string]$OutputDirectory = '')

$ErrorActionPreference = 'Stop'
$workspace = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$toolchain = Get-Content -LiteralPath (Join-Path $workspace 'config\toolchain.json') -Raw | ConvertFrom-Json
$revision = [string]$toolchain.canonicalToolchain.tools.shorebirdCli.releaseEngineRevision
if ($revision -notmatch '^[0-9a-f]{40}$') { throw 'Canonical Shorebird engine revision is invalid.' }
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $workspace "build\shorebird-engine-symbols\$revision"
}
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null
$records = @()
foreach ($architecture in @('android-arm-release', 'android-arm64-release', 'android-x64-release')) {
    # Use Shorebird's official artifact proxy. Shorebird engine revisions are
    # resolved through the revision manifest and may be served from Shorebird's
    # bucket instead of Flutter's upstream bucket.
    $url = "https://download.shorebird.dev/flutter_infra_release/flutter/$revision/$architecture/symbols.zip"
    $destination = Join-Path $resolvedOutput "$architecture-symbols.zip"
    if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
        Invoke-WebRequest -Uri $url -OutFile $destination -UseBasicParsing
    }
    $records += [ordered]@{
        architecture = $architecture
        url = $url
        file = [System.IO.Path]::GetFileName($destination)
        sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
        bytes = (Get-Item -LiteralPath $destination).Length
    }
}
$manifest = [ordered]@{ schema_version = 1; engine_revision = $revision; artifacts = $records }
[System.IO.File]::WriteAllText((Join-Path $resolvedOutput 'manifest.json'), (($manifest | ConvertTo-Json -Depth 5) + "`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Output $resolvedOutput
