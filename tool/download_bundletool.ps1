param([string]$OutputPath = '')

$ErrorActionPreference = 'Stop'
$workspace = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$toolchain = Get-Content -LiteralPath (Join-Path $workspace 'config\toolchain.json') -Raw | ConvertFrom-Json
$pin = $toolchain.canonicalToolchain.tools.bundletool
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $workspace "build\tools\bundletool-$($pin.version).jar"
}
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
New-Item -ItemType Directory -Path (Split-Path -Parent $resolvedOutput) -Force | Out-Null

if (Test-Path -LiteralPath $resolvedOutput -PathType Leaf) {
    $existingHash = (Get-FileHash -LiteralPath $resolvedOutput -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($existingHash -eq [string]$pin.sha256) {
        Write-Output $resolvedOutput
        exit 0
    }
    throw "Existing bundletool has an unexpected SHA-256: $resolvedOutput"
}

$temporaryPath = "$resolvedOutput.download"
try {
    Invoke-WebRequest -Uri ([string]$pin.url) -OutFile $temporaryPath -UseBasicParsing
    $actualHash = (Get-FileHash -LiteralPath $temporaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne [string]$pin.sha256) {
        throw "Bundletool SHA-256 mismatch. Expected $($pin.sha256), got $actualHash."
    }
    Move-Item -LiteralPath $temporaryPath -Destination $resolvedOutput -Force
}
finally {
    if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
        Remove-Item -LiteralPath $temporaryPath -Force
    }
}
Write-Output $resolvedOutput
