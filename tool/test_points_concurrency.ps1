param(
    [string]$Workdir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'
$supabase = (Get-Command supabase -ErrorAction Stop).Source
$userId = [guid]::NewGuid().ToString()
$operationIds = @([guid]::NewGuid().ToString(), [guid]::NewGuid().ToString())
$suffix = $userId.Replace('-', '').Substring(0, 12)
$areaId = "points-concurrency-area-$suffix"
$roomId = "points-concurrency-room-$suffix"
$assetId = "points-concurrency-asset-$suffix"
$taskIds = @(
    "points-concurrency-task-a-$suffix",
    "points-concurrency-task-b-$suffix"
)
$email = "points-concurrency-$suffix@example.test"

function Invoke-LocalQuery {
    param([Parameter(Mandatory)][string]$Sql)

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & $supabase db query --local $Sql 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
    if ($exitCode -ne 0) {
        throw "Local Supabase query failed: $output"
    }
    return $output
}

$setup = @"
do language plpgsql `$fixture`$
declare
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at
  ) values (
    '00000000-0000-0000-0000-000000000000', '$userId',
    'authenticated', 'authenticated', '$email', '', now(), now(), now()
  );


  insert into public.areas (
    user_id, id, name, kind, sort_order, created_at, updated_at
  ) values (
    '$userId', '$areaId', 'Concurrency area', 'indoor', 0, now(), now()
  );
  insert into public.rooms (
    user_id, id, area_id, name, room_type, sort_order, created_at, updated_at
  ) values (
    '$userId', '$roomId', '$areaId', 'Concurrency room', 'other', 0,
    now(), now()
  );
  insert into public.assets (
    user_id, id, name, asset_type, room_id,
    created_at, updated_at
  ) values (
    '$userId', '$assetId', 'Concurrency item', 'general', '$roomId', now(), now()
  );
  insert into public.point_transactions (
    user_id, amount, balance_before, balance_after, transaction_type,
    reference_id, idempotency_key
  ) values (
    '$userId', -6, 7, 1, 'admin_adjustment', 'concurrency-fixture',
    'concurrency-fixture:$userId'
  );
  update public.point_wallets set balance = 1, updated_at = now()
  where user_id = '$userId';
end
`$fixture`$;
"@

try {
    Invoke-LocalQuery -Sql $setup | Out-Null

    $queries = for ($index = 0; $index -lt 2; $index++) {
        $operationId = $operationIds[$index]
        $taskId = $taskIds[$index]
        $title = "Concurrent task $index"
        @"
with auth_context as (
  select
    set_config('request.jwt.claim.sub', '$userId', true),
    set_config('request.jwt.claim.role', 'authenticated', true)
)
select public.create_task_with_point_debit(
  jsonb_build_object(
    'operation_id', '$operationId',
    'plan', jsonb_build_object(
      'id', '$taskId',
      'asset_id', '$assetId',
      'title', '$title',
      'recurrence_interval', 1,
      'recurrence_unit', 'months',
      'priority', 'medium',
      'next_due_date', now() + interval '1 day',
      'reminder_days_before', 0,
      'health_group', 'other'
    )
  )
) as result
from auth_context;
"@
    }

    $jobs = foreach ($query in $queries) {
        Start-Job -ScriptBlock {
            param($Supabase, $Query, $Directory)
            Set-Location -LiteralPath $Directory
            $result = & $Supabase db query --local $Query 2>&1 | Out-String
            [pscustomobject]@{
                ExitCode = $LASTEXITCODE
                Output = $result
            }
        } -ArgumentList $supabase, $query, $Workdir
    }
    $results = $jobs | Wait-Job | Receive-Job
    $jobs | Remove-Job -Force

    $successes = @($results | Where-Object ExitCode -eq 0)
    $insufficient = @(
        $results | Where-Object {
            $_.ExitCode -ne 0 -and $_.Output -match 'INSUFFICIENT_POINTS'
        }
    )
    if ($successes.Count -ne 1 -or $insufficient.Count -ne 1) {
        throw "Expected one debit and one insufficient-points rejection."
    }

    $verificationSql = @"
select jsonb_build_object(
  'balance', (select balance from public.point_wallets where user_id = '$userId'),
  'task_count', (select count(*) from public.maintenance_plans
                 where user_id = '$userId' and id in ('$($taskIds[0])', '$($taskIds[1])')),
  'task_debits', (select count(*) from public.point_transactions
                  where user_id = '$userId' and transaction_type = 'task_creation'
                    and reference_id in ('$($taskIds[0])', '$($taskIds[1])'))
) as verification;
"@
    $verificationOutput = Invoke-LocalQuery -Sql $verificationSql
    $jsonStart = $verificationOutput.IndexOf('{')
    $jsonEnd = $verificationOutput.LastIndexOf('}')
    if ($jsonStart -lt 0 -or $jsonEnd -lt $jsonStart) {
        throw 'Supabase verification query did not return JSON.'
    }
    $response = $verificationOutput.Substring(
        $jsonStart,
        $jsonEnd - $jsonStart + 1
    ) | ConvertFrom-Json
    $verification = $response.rows[0].verification
    if (
        $verification.balance -ne 0 -or
        $verification.task_count -ne 1 -or
        $verification.task_debits -ne 1
    ) {
        throw "Concurrent debit invariant failed: $($verification | ConvertTo-Json -Compress)"
    }

    [pscustomobject]@{
        Result = 'PASS'
        SuccessfulDebits = $successes.Count
        InsufficientPointRejections = $insufficient.Count
        FinalBalance = $verification.balance
        CreatedTasks = $verification.task_count
        LedgerDebits = $verification.task_debits
    }
}
finally {
    Invoke-LocalQuery -Sql "delete from auth.users where id = '$userId'" | Out-Null
}
