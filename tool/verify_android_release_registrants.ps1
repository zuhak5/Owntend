param([switch]$RemoveGeneratedMain)

$ErrorActionPreference = 'Stop'
$workspace = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$workspacePrefix = $workspace + [System.IO.Path]::DirectorySeparatorChar
$mainRegistrant = [System.IO.Path]::GetFullPath((Join-Path $workspace 'android\app\src\main\java\io\flutter\plugins\GeneratedPluginRegistrant.java'))
if (-not $mainRegistrant.StartsWith($workspacePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Generated registrant target escaped the workspace.'
}
if ($RemoveGeneratedMain -and (Test-Path -LiteralPath $mainRegistrant -PathType Leaf)) {
    Remove-Item -LiteralPath $mainRegistrant -Force
}

$registrants = foreach ($root in @((Join-Path $workspace 'android'), (Join-Path $workspace 'build'))) {
    if (Test-Path -LiteralPath $root -PathType Container) {
        Get-ChildItem -LiteralPath $root -Recurse -File -Filter 'GeneratedPluginRegistrant.*'
    }
}
foreach ($registrant in $registrants) {
    $registrantPath = [System.IO.Path]::GetFullPath($registrant.FullName)
    $relativePath = if ($registrantPath.StartsWith($workspacePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        $registrantPath.Substring($workspacePrefix.Length)
    }
    else { $registrantPath }
    # Flutter/Gradle variant directories are commonly named devDebug,
    # stagingProfile, and similar rather than only debug/profile.
    if ($relativePath -match '(?i)(^|[\\/])[^\\/]*(?:debug|profile)[^\\/]*(?:[\\/]|$)') { continue }
    if (Select-String -LiteralPath $registrantPath -SimpleMatch -Quiet -Pattern 'IntegrationTestPlugin') {
        throw "Release plugin registrant contains integration_test: $relativePath"
    }
}
Write-Host 'Release plugin registrants contain no IntegrationTestPlugin.'
