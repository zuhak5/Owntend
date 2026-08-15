param(
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $workspace 'config\prod.json'

if (-not (Test-Path -LiteralPath $configPath)) {
    throw 'Missing config\prod.json. Create it from environment variables or template before building.'
}

$config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
if ($config.APP_ENV -ne 'prod') {
    throw 'config\prod.json must set APP_ENV=prod.'
}
if ([string]::IsNullOrWhiteSpace($config.SUPABASE_URL) -or
    [string]::IsNullOrWhiteSpace($config.SUPABASE_PUBLISHABLE_KEY) -or
    [string]::IsNullOrWhiteSpace($config.GOOGLE_WEB_CLIENT_ID)) {
    throw 'config\prod.json must contain Supabase settings and GOOGLE_WEB_CLIENT_ID.'
}
if ($config.SENTRY_ENABLED -ne $true) {
    throw 'config\prod.json must set SENTRY_ENABLED=true for production.'
}
if ([string]::IsNullOrWhiteSpace([string]$config.SENTRY_DSN)) {
    throw 'config\prod.json must contain SENTRY_DSN for production.'
}

try {
    $sentryUri = [System.Uri]([string]$config.SENTRY_DSN)
}
catch {
    throw 'SENTRY_DSN must be a valid absolute URL.'
}
if ($sentryUri.Scheme -ne 'https' -or
    [string]::IsNullOrWhiteSpace($sentryUri.UserInfo) -or
    $sentryUri.Host -notmatch '(?i)(^|\.)ingest(?:\.[a-z0-9-]+)?\.sentry\.io$') {
    throw 'SENTRY_DSN must be an HTTPS Sentry ingest URL with a public key.'
}

try {
    $traceSampleRate = [double]::Parse(
        [string]$config.SENTRY_TRACES_SAMPLE_RATE,
        [System.Globalization.CultureInfo]::InvariantCulture
    )
}
catch {
    throw 'SENTRY_TRACES_SAMPLE_RATE must be a number between 0.0 and 1.0.'
}
if ($traceSampleRate -lt 0.0 -or $traceSampleRate -gt 1.0) {
    throw 'SENTRY_TRACES_SAMPLE_RATE must be between 0.0 and 1.0.'
}

$productionDefines = @(
    "--dart-define-from-file=$configPath"
)
$sentryDebugRoot = Join-Path $workspace 'build\sentry-debug'
$dartSymbolsDir = Join-Path $sentryDebugRoot 'dart'
$dartSymbolMapPath = Join-Path $dartSymbolsDir 'mapping.json'

function Invoke-Flutter {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $exitCode = 0
    try {
        $ErrorActionPreference = 'Continue'
        & flutter @Arguments
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($exitCode -ne 0) {
        throw "flutter $($Arguments -join ' ') failed with exit code $exitCode."
    }
}

function Invoke-Dart {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $exitCode = 0
    try {
        $ErrorActionPreference = 'Continue'
        & dart @Arguments
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($exitCode -ne 0) {
        throw "dart $($Arguments -join ' ') failed with exit code $exitCode."
    }
}

function Assert-NoIntegrationTestRegistrant {
    $workspacePrefix = [System.IO.Path]::GetFullPath($workspace) +
        [System.IO.Path]::DirectorySeparatorChar
    $searchRoots = @(
        (Join-Path $workspace 'android'),
        (Join-Path $workspace 'build')
    )
    $registrants = foreach ($searchRoot in $searchRoots) {
        if (Test-Path -LiteralPath $searchRoot) {
            Get-ChildItem `
                -LiteralPath $searchRoot `
                -Recurse `
                -File `
                -Filter 'GeneratedPluginRegistrant.*'
        }
    }

    foreach ($registrant in $registrants) {
        $registrantPath = [System.IO.Path]::GetFullPath($registrant.FullName)
        $relativePath = if ($registrantPath.StartsWith(
                $workspacePrefix,
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
            $registrantPath.Substring($workspacePrefix.Length)
        }
        else {
            $registrantPath
        }
        if ($relativePath -match '(?i)(^|[\\/])(debug|profile)([\\/]|$)') {
            continue
        }

        if (Select-String `
                -LiteralPath $registrant.FullName `
                -SimpleMatch `
                -Quiet `
                -Pattern 'IntegrationTestPlugin') {
            throw "Release plugin registrant contains integration_test: $($registrant.FullName)"
        }
    }
}

function Remove-GeneratedAndroidRegistrants {
    $workspacePrefix = [System.IO.Path]::GetFullPath($workspace) +
        [System.IO.Path]::DirectorySeparatorChar
    $registrantPaths = @(
        'android\app\src\main\java\io\flutter\plugins\GeneratedPluginRegistrant.java'
    )

    foreach ($relativeRegistrantPath in $registrantPaths) {
        $registrantPath = [System.IO.Path]::GetFullPath(
            (Join-Path $workspace $relativeRegistrantPath)
        )
        if (-not $registrantPath.StartsWith(
                $workspacePrefix,
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
            throw "Refusing to remove a generated registrant outside the workspace: $registrantPath"
        }

        if (Test-Path -LiteralPath $registrantPath) {
            Remove-Item -LiteralPath $registrantPath -Force
        }
    }
}

function Initialize-BuildWorkspace {
    Invoke-Flutter -Arguments @('clean')
    Invoke-Flutter -Arguments @('pub', 'get', '--enforce-lockfile')
    Invoke-Flutter -Arguments @('gen-l10n')
    Invoke-Dart -Arguments @('run', 'build_runner', 'build')
    $LockChanges = (& git status --porcelain pubspec.lock 2>&1 | Out-String).Trim()
    if (-not [string]::IsNullOrWhiteSpace($LockChanges)) {
        throw "pubspec.lock was modified during workspace initialization. Commit the updated lockfile and verify the change is intentional before releasing.`n$LockChanges"
    }
}

Push-Location $workspace
try {
    Initialize-BuildWorkspace
    Invoke-Flutter -Arguments @('analyze', '--no-pub')
    if (-not $SkipTests) {
        Invoke-Flutter -Arguments @(
            'test',
            '--no-pub',
            '--concurrency=1',
            '--timeout',
            '2m',
            '--exclude-tags',
            'production-config'
        )
        Invoke-Flutter -Arguments (@(
            'test',
            '--no-pub',
            'test/prod_build_config_test.dart'
        ) + $productionDefines + @('--dart-define=VERIFY_PRODUCTION_CONFIG=true'))
    }

    Remove-GeneratedAndroidRegistrants
    Assert-NoIntegrationTestRegistrant
    if (Test-Path -LiteralPath $sentryDebugRoot) {
        Remove-Item -LiteralPath $sentryDebugRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $dartSymbolsDir -Force | Out-Null
    $dartBuildFlags = @(
        '--obfuscate',
        "--split-debug-info=$dartSymbolsDir",
        "--extra-gen-snapshot-options=--save-obfuscation-map=$dartSymbolMapPath"
    )
    Invoke-Flutter -Arguments (
        @('build', 'appbundle', '--flavor', 'prod', '--release') +
        $productionDefines +
        $dartBuildFlags
    )
    Assert-NoIntegrationTestRegistrant
    if (-not (Test-Path -LiteralPath $dartSymbolMapPath -PathType Leaf)) {
        throw "Flutter obfuscation map was not generated: $dartSymbolMapPath"
    }
    $dartSymbolFiles = @(Get-ChildItem -LiteralPath $dartSymbolsDir -Filter '*.symbols' -File)
    if ($dartSymbolFiles.Count -eq 0) {
        throw "Flutter debug symbol files were not generated in $dartSymbolsDir."
    }
    $proguardMappingPath = Join-Path $workspace 'build\app\outputs\mapping\prodRelease\mapping.txt'
    if (-not (Test-Path -LiteralPath $proguardMappingPath -PathType Leaf)) {
        throw "Android R8 mapping file was not generated: $proguardMappingPath"
    }
    $bundleDirectory = Join-Path $workspace 'build\app\outputs\bundle\prodRelease'
    $bundles = @(Get-ChildItem -LiteralPath $bundleDirectory -File -Filter '*.aab')
    if ($bundles.Count -ne 1) {
        throw "Expected exactly one prodRelease AAB, found $($bundles.Count)."
    }
    Write-Host "Created production AAB: $($bundles[0].FullName)"
}
finally {
    Pop-Location
}
