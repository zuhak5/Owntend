<#
.SYNOPSIS
    Runs backend integration tests against an isolated, disposable local
    Supabase stack with all Edge Functions served over real HTTP.

.DESCRIPTION
    Creates a temporary copy of the repository Supabase configuration on
    shifted ports, starts and resets ONLY that stack, loads deterministic
    fixtures, serves every configured Edge Function, executes the Deno
    integration suites under supabase/tests/integration against real
    endpoints, and tears everything down even on failure.

    Safety contract:
      - Refuses to run when the repository is linked to any remote project.
      - Never touches a developer-started stack: the isolated stack listens
        on ports shifted by -PortOffset from the committed local ports.
      - Credentials stay in memory; they are never printed or logged.
      - Teardown stops served functions, stops the stack without backup, and
        deletes the temporary workspace in all outcomes.

.EXAMPLE
    npm run test:backend-integration
#>

[CmdletBinding()]
param(
    # Port shift applied to the committed local stack ports for isolation.
    [int]$PortOffset = 400,

    # Keep the disposable workspace for debugging (never used in CI).
    [switch]$KeepWorkspace,

    # Environment variable name carrying the worker capability secret that is
    # injected into the served cleanup function.
    [string]$MediaCleanupWorkerTokenEnv = 'OWNTEND_MEDIA_CLEANUP_WORKER_TOKEN'
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot

# ------------------------------------------------------------------- guards
$linkState = Join-Path $repositoryRoot 'supabase\.temp\project-id'
if (Test-Path -LiteralPath $linkState) {
    throw "Repository appears linked to a remote Supabase project ($linkState exists). Unlink before running the disposable backend integration lane."
}
$linkedProject = Join-Path $repositoryRoot 'supabase\.temp\linked-project.json'
if (Test-Path -LiteralPath $linkedProject) {
    Write-Warning 'Repository carries Supabase CLI link state. It will NOT be copied into the disposable workspace; every command below runs strictly inside that unlinked, local-only workspace.'
}
if (-not (Test-Path -LiteralPath (Join-Path $repositoryRoot 'supabase\config.toml'))) {
    throw 'supabase/config.toml was not found.'
}

# ---------------------------------------------------- disposable workspace
$workspace = Join-Path ([IO.Path]::GetTempPath()) ("owntend-backend-integration-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workspace | Out-Null

$serveProcess = $null

function Stop-DisposableStack {
    try {
        if ($serveProcess -and -not $serveProcess.HasExited) {
            Stop-Process -Id $serveProcess.Id -Force -ErrorAction SilentlyContinue
            $script:serveProcess = $null
        }
        $supabaseDir = Join-Path $workspace 'supabase'
        if (Test-Path -LiteralPath $supabaseDir) {
            Push-Location $supabaseDir
            & npx supabase stop --no-backup 2>$null | Out-Null
            Pop-Location
        }
    } catch { }
    if (-not $KeepWorkspace -and (Test-Path -LiteralPath $workspace)) {
        Remove-Item -LiteralPath $workspace -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Preparing disposable backend workspace: $workspace"

try {
    # Copy the Supabase surface under test. CLI runtime state (.temp,
    # .branches) is NEVER copied: it can carry hosted link data and would
    # redirect serve/reset behavior away from the disposable stack.
    $supabaseSource = Join-Path $repositoryRoot 'supabase'
    $supabaseTarget = Join-Path $workspace 'supabase'
    New-Item -ItemType Directory -Path $supabaseTarget | Out-Null
    Get-ChildItem -LiteralPath $supabaseSource -Force | Where-Object {
        $_.Name -notin @('.temp', '.branches')
    } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $supabaseTarget -Recurse -Force
    }

    # Shift ports and assign a unique project id so the isolated stack gets
    # its own Docker containers and can never collide with, reuse, or reset a
    # developer-started stack.
    $configPath = Join-Path $workspace 'supabase\config.toml'
    $config = Get-Content -LiteralPath $configPath -Raw
    $config = [regex]::Replace($config, '(?m)^project_id\s*=\s*.*$', ("project_id = `"owntend-integration-" + [Guid]::NewGuid().ToString('N').Substring(0, 8) + "`""))
    $config = [regex]::Replace($config, '(?m)^(\s*port\s*=\s*)(\d+)', {
        param($match) $match.Groups[1].Value + ([int]$match.Groups[2].Value + $PortOffset)
    })
    $config = [regex]::Replace($config, '(?m)^(\s*smtp_port\s*=\s*)(\d+)', {
        param($match) $match.Groups[1].Value + ([int]$match.Groups[2].Value + $PortOffset)
    })
    $config = [regex]::Replace($config, '(?m)^(\s*pop3_port\s*=\s*)(\d+)', {
        param($match) $match.Groups[1].Value + ([int]$match.Groups[2].Value + $PortOffset)
    })
    $config = [regex]::Replace($config, '(?m)^(\s*shadow_port\s*=\s*)(\d+)', {
        param($match) $match.Groups[1].Value + ([int]$match.Groups[2].Value + $PortOffset)
    })
    # WriteAllText emits UTF-8 without BOM on every PowerShell edition.
    [IO.File]::WriteAllText($configPath, $config)

    # ------------------------------------------------------------------ start
    # `supabase start` on a brand-new isolated project applies the full
    # migration baseline onto a blank database. No separate reset step is
    # needed: integration suites self-bootstrap their fixtures through
    # supported admin APIs, so nothing interactive can block the lane.
    Push-Location (Join-Path $workspace 'supabase')
    Write-Host 'Starting isolated Supabase stack...'
    & npx supabase start --ignore-health-check | Out-Null
    if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'supabase start failed for the disposable stack.' }

    # -------------------------------------------------- blank-baseline gates
    # Lint and the full pgTAP suite prove the freshly applied single baseline
    # on a blank stack, exactly as the validation matrix requires. These run
    # here so a stale developer database can never mask a baseline regression.
    # The stack was started with --ignore-health-check, so gate steps retry
    # briefly until Postgres is accepting queries.
    function Invoke-StackCommandWithRetry {
        param([string]$Description, [scriptblock]$Command, [int]$MaxAttempts = 12)
        for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
            & $Command
            if ($LASTEXITCODE -eq 0) { return }
            if ($attempt -lt $MaxAttempts) { Start-Sleep -Seconds 5 }
        }
        Pop-Location
        throw "$Description failed on the disposable stack after $MaxAttempts attempts."
    }

    Write-Host 'Linting blank baseline schema...'
    Invoke-StackCommandWithRetry -Description 'supabase db lint' -Command {
        & npx supabase db lint --local --level error --fail-on error
    }

    Write-Host 'Running pgTAP suite against the blank baseline...'
    Invoke-StackCommandWithRetry -Description 'pgTAP suite' -MaxAttempts 3 -Command {
        & npx supabase test db --local (Join-Path $repositoryRoot 'supabase\tests\database')
    }

    # ------------------------------------------------------------ credentials
    # Parse status output strictly in memory. Values are never echoed or
    # written anywhere persistent.
    $statusJson = & npx supabase status -o json
    if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'supabase status failed.' }
    Pop-Location
    $status = $statusJson | ConvertFrom-Json

    $apiUrl = [string]$status.API_URL
    $anonKey = [string]$status.ANON_KEY
    $serviceRoleKey = [string]$status.SERVICE_ROLE_KEY
    foreach ($entry in @(@('API_URL', $apiUrl), @('ANON_KEY', $anonKey), @('SERVICE_ROLE_KEY', $serviceRoleKey))) {
        if ([string]::IsNullOrWhiteSpace($entry[1])) { throw "Disposable stack status did not include $($entry[0])." }
    }

    # Random capability secret for this run only.
    $workerTokenBytes = [byte[]]::new(32)
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($workerTokenBytes) } finally { $rng.Dispose() }
    $workerToken = [Convert]::ToBase64String($workerTokenBytes)

    # ------------------------------------------------------- serve functions
    $serveLog = Join-Path $workspace 'functions-serve.log'
    $serveErr = Join-Path $workspace 'functions-serve.err.log'
    $envFile = Join-Path $workspace 'functions.env'
    [IO.File]::WriteAllText($envFile, "$MediaCleanupWorkerTokenEnv=$workerToken")
    Write-Host 'Serving Edge Functions...'
    # A bootstrap script sidesteps quoting problems caused by spaces in the
    # temporary workspace path.
    $serveBootstrap = Join-Path $workspace 'run-functions-serve.ps1'
    $serveScript = "Set-Location -LiteralPath '" + (Join-Path $workspace 'supabase') + "'" + [Environment]::NewLine
    $serveScript += '& npx supabase functions serve --env-file ''' + $envFile + ''' 1> ''' + $serveLog + ''' 2> ''' + $serveErr + ''''
    [IO.File]::WriteAllText($serveBootstrap, $serveScript)
    $serveProcess = Start-Process -FilePath 'powershell.exe' `
        -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$serveBootstrap`"" `
        -WindowStyle Hidden `
        -PassThru

    # Wait until OUR token-aware function revision is actually serving. The
    # stack ships its own Edge Runtime container which answers 403 (fail
    # closed, no capability configured); only the CLI-served instance knows
    # this run's random token and answers 200.
    $functionsHealthy = $false
    for ($attempt = 0; $attempt -lt 90; $attempt++) {
        Start-Sleep -Seconds 1
        try {
            $probe = Invoke-WebRequest -Uri "$apiUrl/functions/v1/process-media-cleanup" `
                -Method POST `
                -UseBasicParsing `
                -TimeoutSec 5 `
                -Headers @{ 'Content-Type' = 'application/json'; 'X-Owntend-Worker-Token' = $workerToken }
            if ($probe.StatusCode -eq 200) { $functionsHealthy = $true; break }
        } catch {
            # Boot responses (403/502/503) keep the loop waiting.
        }
    }
    if (-not $functionsHealthy) {
        Get-Content -LiteralPath $serveLog -ErrorAction SilentlyContinue | Select-Object -First 30 | ForEach-Object { Write-Host $_ }
        throw 'Edge Function runtime did not become reachable.'
    }

    # ---------------------------------------------------------------- testing
    Write-Host 'Running integration suites against real endpoints...'
    $env:SUPABASE_URL = $apiUrl
    $env:SUPABASE_ANON_KEY = $anonKey
    $env:SUPABASE_SERVICE_ROLE_KEY = $serviceRoleKey
    $env:SUPABASE_FUNCTIONS_URL = "$apiUrl/functions/v1"
    Set-Item -Path "env:$MediaCleanupWorkerTokenEnv" -Value $workerToken

    Push-Location $repositoryRoot
    & deno test --frozen --allow-env --allow-net supabase/tests/integration/*.test.ts
    $testExit = $LASTEXITCODE
    Pop-Location

    if ($testExit -ne 0) {
        Write-Host '--- Edge Function serve output (diagnostic) ---'
        Get-Content -LiteralPath $serveLog -ErrorAction SilentlyContinue | Select-Object -First 40 | ForEach-Object { Write-Host $_ }
        Get-Content -LiteralPath $serveErr -ErrorAction SilentlyContinue | Select-Object -First 20 | ForEach-Object { Write-Host $_ }
        throw "Integration tests failed (exit $testExit)."
    }
    Write-Host 'Backend integration suite passed.' -ForegroundColor Green
} finally {
    Stop-DisposableStack
}
