param(
    [Parameter(Mandatory = $true)]
    [string]$Release,

    [Parameter(Mandatory = $true)]
    [string]$Dist,

    [string]$Environment = 'prod',

    [string]$DartSymbolsDirectory = 'build\shorebird-symbols\prod\base',

    [string]$ObfuscationMapPath = 'build\shorebird\obfuscation_map.json',

    [string]$EngineSymbolsDirectory = ''
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

# Authenticate before mutating release state so invalid credentials fail clearly.
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

$resolvedDartSymbols = [System.IO.Path]::GetFullPath($DartSymbolsDirectory)
$resolvedObfuscationMap = [System.IO.Path]::GetFullPath($ObfuscationMapPath)
if (-not (Test-Path -LiteralPath $resolvedDartSymbols -PathType Container)) {
    throw "Shorebird Dart symbols were not found: $resolvedDartSymbols"
}
if (-not (Test-Path -LiteralPath $resolvedObfuscationMap -PathType Leaf)) {
    throw "Shorebird obfuscation map was not found: $resolvedObfuscationMap"
}
$sentryDartSymbols = [System.IO.Path]::GetFullPath((Join-Path $PWD 'build\sentry-debug\dart'))
if (Test-Path -LiteralPath $sentryDartSymbols) {
    Remove-Item -LiteralPath $sentryDartSymbols -Recurse -Force
}
New-Item -ItemType Directory -Path $sentryDartSymbols -Force | Out-Null
Copy-Item -Path (Join-Path $resolvedDartSymbols '*') -Destination $sentryDartSymbols -Force
Copy-Item -LiteralPath $resolvedObfuscationMap -Destination (Join-Path $sentryDartSymbols 'mapping.json') -Force

Invoke-WithRetry -Label 'Sentry Shorebird Dart debug symbol upload' -Operation {
    Invoke-NativeCommand -FilePath 'dart' -Arguments @(
        'run',
        'sentry_dart_plugin'
    )
}

$proguardMappingPath = Join-Path $PWD 'build\app\outputs\mapping\prodRelease\mapping.txt'
if (-not (Test-Path -LiteralPath $proguardMappingPath -PathType Leaf)) {
    throw "Android R8 mapping file was not found for Sentry upload: $proguardMappingPath"
}
Invoke-WithRetry -Label 'Sentry Android mapping upload' -Operation {
    Invoke-NativeCommand -FilePath 'npx' -Arguments (
        $sentryCli + @('upload-proguard', $proguardMappingPath)
    )
}

if (-not [string]::IsNullOrWhiteSpace($EngineSymbolsDirectory)) {
    $resolvedEngineSymbols = [System.IO.Path]::GetFullPath($EngineSymbolsDirectory)
    $manifestPath = Join-Path $resolvedEngineSymbols 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Shorebird engine-symbol manifest is missing: $manifestPath"
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $canonical = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\config\toolchain.json') -Raw | ConvertFrom-Json
    if ([string]$manifest.engine_revision -ne [string]$canonical.canonicalToolchain.tools.shorebirdCli.releaseEngineRevision) {
        throw 'Shorebird engine-symbol revision differs from the canonical release engine.'
    }
    $engineArchives = @($manifest.artifacts | ForEach-Object {
        $archive = Join-Path $resolvedEngineSymbols ([string]$_.file)
        if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) { throw "Engine symbol archive is missing: $archive" }
        $hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -ne [string]$_.sha256) { throw "Engine symbol archive hash mismatch: $archive" }
        $archive
    })
    if ($engineArchives.Count -ne 3) { throw 'Exactly three Shorebird Android engine-symbol archives are required.' }
    foreach ($archive in $engineArchives) {
        Invoke-WithRetry -Label "Sentry Shorebird engine symbol upload" -Operation {
            Invoke-NativeCommand -FilePath 'npx' -Arguments ($sentryCli + @('debug-files', 'upload', $archive))
        }
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
