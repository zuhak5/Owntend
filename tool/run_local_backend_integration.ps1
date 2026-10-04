<#
.SYNOPSIS
    Runs backend integration tests against an isolated, disposable local
    Supabase stack with all Edge Functions served over real HTTP.

.DESCRIPTION
    Creates a temporary copy of the repository Supabase configuration on
    shifted ports, starts ONLY that stack, loads deterministic
    fixtures, serves every configured Edge Function, executes the Deno
    integration suites under supabase/tests/integration against real
    endpoints, and tears everything down even on failure.

    Safety contract:
      - Refuses to run when the repository is linked to any remote project.
      - Never touches a developer-started stack: the isolated stack listens
        on ports shifted by -PortOffset from the committed local ports.
      - Credentials are never printed or logged. Per-run credential files
        exist only in the disposable workspace and are removed at teardown.
      - Teardown stops served functions, stops the stack without backup, and
        deletes the temporary workspace in all outcomes.

.EXAMPLE
    npm run test:backend-integration

.EXAMPLE
    npm run test:backend-integration -- -IncludeApplicationIntegration
#>

[CmdletBinding()]
param(
    # Port shift applied to the committed local stack ports for isolation.
    [int]$PortOffset = 400,

    # Keep the disposable workspace for debugging (never used in CI).
    [switch]$KeepWorkspace,

    # Also run the real Flutter Auth/RLS/sync/Storage scenarios on this stack.
    [switch]$IncludeApplicationIntegration,

    # Environment variable name carrying the worker capability secret that is
    # injected into the served cleanup function.
    [string]$MediaCleanupWorkerTokenEnv = 'OWNTEND_MEDIA_CLEANUP_WORKER_TOKEN'
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$supabaseCliRelativePath = 'node_modules\.bin\supabase.cmd'
if ($PSVersionTable.PSEdition -ne 'Desktop' -and $env:OS -ne 'Windows_NT') {
    $supabaseCliRelativePath = 'node_modules/.bin/supabase'
}
$supabaseCli = Join-Path $repositoryRoot $supabaseCliRelativePath
if (-not (Test-Path -LiteralPath $supabaseCli -PathType Leaf)) {
    throw "Pinned Supabase CLI launcher was not found at $supabaseCli. Run npm ci first."
}
$expectedSupabaseCliVersion = [string](
    Get-Content -LiteralPath (Join-Path $repositoryRoot 'config\toolchain.json') -Raw |
        ConvertFrom-Json
).canonicalToolchain.tools.supabaseCli
$resolvedSupabaseCliVersion = (& $supabaseCli --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $resolvedSupabaseCliVersion -ne $expectedSupabaseCliVersion) {
    throw "Supabase CLI mismatch: expected $expectedSupabaseCliVersion, got $resolvedSupabaseCliVersion."
}

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
$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
$workspace = Join-Path $temporaryRoot ("owntend-backend-integration-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workspace | Out-Null

$serveProcess = $null

function Stop-DisposableStack {
    $cleanupFailed = $false
    try {
        if ($serveProcess -and -not $serveProcess.HasExited) {
            if ($env:OS -eq 'Windows_NT') {
                # Stopping only PowerShell leaves cmd/Supabase children holding
                # the log files and working directory open on Windows.
                $processes = @(Get-CimInstance Win32_Process)
                $ownedIds = [Collections.Generic.List[int]]::new()
                $ownedIds.Add($serveProcess.Id)
                for ($index = 0; $index -lt $ownedIds.Count; $index++) {
                    foreach ($child in $processes | Where-Object { $_.ParentProcessId -eq $ownedIds[$index] }) {
                        $ownedIds.Add([int]$child.ProcessId)
                    }
                }
                for ($index = $ownedIds.Count - 1; $index -ge 0; $index--) {
                    Stop-Process -Id $ownedIds[$index] -Force -ErrorAction SilentlyContinue
                }
            } else {
                $serveProcess.Kill($true)
            }
            $serveProcess.WaitForExit()
            $script:serveProcess = $null
        }
    } catch {
        $cleanupFailed = $true
        Write-Warning 'The disposable Edge Functions process did not stop cleanly.'
    }
    try {
        $supabaseDir = Join-Path $workspace 'supabase'
        if (Test-Path -LiteralPath $supabaseDir) {
            Push-Location $supabaseDir
            try {
                # Windows PowerShell wraps native stderr as errors. CLI progress
                # on stderr must not skip Pop-Location or workspace deletion.
                $previousErrorPreference = $ErrorActionPreference
                $ErrorActionPreference = 'Continue'
                & $supabaseCli stop --no-backup 2>$null | Out-Null
                $stopExit = $LASTEXITCODE
                if ($stopExit -ne 0) { $cleanupFailed = $true }
            } finally {
                $ErrorActionPreference = $previousErrorPreference
                Pop-Location
            }
        }
    } catch {
        $cleanupFailed = $true
        Write-Warning 'The disposable Supabase stack did not stop cleanly.'
    }
    if (-not $KeepWorkspace -and (Test-Path -LiteralPath $workspace)) {
        $resolvedWorkspace = (Resolve-Path -LiteralPath $workspace).ProviderPath
        if ([IO.Path]::GetDirectoryName($resolvedWorkspace) -ne $temporaryRoot -or
            [IO.Path]::GetFileName($resolvedWorkspace) -notmatch '^owntend-backend-integration-[a-f0-9]{32}$' -or
            (Get-Item -LiteralPath $resolvedWorkspace).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Refusing to remove an unexpected disposable workspace target.'
        }
        for ($attempt = 0; $attempt -lt 5; $attempt++) {
            try {
                Remove-Item -LiteralPath $resolvedWorkspace -Recurse -Force -ErrorAction Stop
                break
            } catch {
                if ($attempt -eq 4) { throw 'Could not remove the disposable backend workspace; cleanup requires attention.' }
                Start-Sleep -Milliseconds 500
            }
        }
        if (Test-Path -LiteralPath $resolvedWorkspace) {
            throw 'Disposable backend workspace still exists after teardown.'
        }
    }
    if ($cleanupFailed) { throw 'Disposable backend teardown failed; inspect the local stack and process state.' }
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
    # ordered migration chain onto a blank database. No separate reset step is
    # needed: integration suites self-bootstrap their fixtures through
    # supported admin APIs, so nothing interactive can block the lane.
    Push-Location (Join-Path $workspace 'supabase')
    Write-Host 'Starting isolated Supabase stack...'
    & $supabaseCli start --ignore-health-check | Out-Null
    if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'supabase start failed for the disposable stack.' }

    # -------------------------------------------------- blank-baseline gates
    # Lint and the full pgTAP suite prove the freshly applied migration chain
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
        & $supabaseCli db lint --local --level error --fail-on error
    }

    Write-Host 'Running pgTAP suite against the blank baseline...'
    Invoke-StackCommandWithRetry -Description 'pgTAP suite' -MaxAttempts 3 -Command {
        & $supabaseCli test db --local (Join-Path $repositoryRoot 'supabase\tests\database')
    }

    # ------------------------------------------------------------ credentials
    # Parse status output strictly in memory. Values are never echoed; any
    # necessary per-run credential file belongs to the disposable workspace.
    $statusJson = & $supabaseCli status -o json
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
    # A bootstrap script sidesteps process-argument quoting for workspace paths.
    # Escape every quote delimiter PowerShell accepts, including curly quotes.
    # The bootstrap is launched by the same
    # PowerShell host executing this lane (Windows PowerShell or pwsh), which
    # keeps the served-function environment identical across platforms.
    $hostExecutable = (Get-Process -Id $PID).Path
    $serveBootstrap = Join-Path $workspace 'run-functions-serve.ps1'
    function ConvertTo-ServePathLiteral([string]$Value) {
        return "'" + [regex]::Replace($Value, '[\u0027\u2018\u2019\u201a\u201b]', '$0$0') + "'"
    }
    $serveScript = 'Set-Location -LiteralPath ' + (ConvertTo-ServePathLiteral (Join-Path $workspace 'supabase')) + [Environment]::NewLine
    $serveScript += '& ' + (ConvertTo-ServePathLiteral $supabaseCli) + ' functions serve --env-file ' + (ConvertTo-ServePathLiteral $envFile) + ' 1> ' + (ConvertTo-ServePathLiteral $serveLog) + ' 2> ' + (ConvertTo-ServePathLiteral $serveErr)
    # Windows PowerShell 5.1 otherwise reads non-ASCII UTF-8 source as ANSI.
    [IO.File]::WriteAllText($serveBootstrap, $serveScript, [Text.UTF8Encoding]::new($true))
    $serveWindowOptions = @{}
    if ($env:OS -eq 'Windows_NT') { $serveWindowOptions.WindowStyle = 'Hidden' }
    $serveProcess = Start-Process @serveWindowOptions -FilePath $hostExecutable `
        -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$serveBootstrap`"" `
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
    if ($IncludeApplicationIntegration) {
        # These credentials belong only to the disposable loopback stack. Keep
        # them out of command lines and logs and remove them with the workspace.
        $applicationDefinesPath = Join-Path $workspace 'application-test-defines.json'
        $applicationDefines = @{
            OWNTEND_TEST_SUPABASE_URL = $apiUrl
            OWNTEND_TEST_SUPABASE_ANON_KEY = $anonKey
            OWNTEND_TEST_SUPABASE_SERVICE_ROLE_KEY = $serviceRoleKey
        } | ConvertTo-Json
        [IO.File]::WriteAllText($applicationDefinesPath, $applicationDefines)
        Push-Location $repositoryRoot
        try {
            & flutter test --no-pub --concurrency=1 --timeout 3m `
                test/backend_integration/local_backend_sync_test.dart `
                "--dart-define-from-file=$applicationDefinesPath"
            if ($LASTEXITCODE -ne 0) {
                throw "Application/backend integration failed (exit $LASTEXITCODE)."
            }
        } finally { Pop-Location }
    }
    Write-Host 'Backend integration suite passed.' -ForegroundColor Green
} finally {
    Stop-DisposableStack
}
