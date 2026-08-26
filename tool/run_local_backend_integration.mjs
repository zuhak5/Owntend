import { spawnSync } from 'node:child_process';
import process from 'node:process';

// The disposable backend integration lane is a PowerShell script that must run
// on every canonical surface: GitHub ubuntu runners ship only PowerShell 7
// (`pwsh`), while Windows runners and local developer machines may only expose
// Windows PowerShell (`powershell`). Node is the repository's universal
// runtime, so it resolves the correct host per platform.
const script = 'tool/run_local_backend_integration.ps1';
const shell = process.platform === 'win32' ? 'powershell.exe' : 'pwsh';

const result = spawnSync(
  shell,
  ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script],
  { stdio: 'inherit' },
);

process.exitCode = result.status ?? 1;
