# check-gateway-running.ps1 - outputs "RUNNING" if a hermes gateway process is
# alive, otherwise outputs nothing. Used by start_gateway.bat's redundant-instance
# guard (avoids fragile inline PowerShell quoting inside cmd for /f backticks).
#
# v2: read lifecycle.json first (fast, <1ms), fallback to CIM query (slow on low-RAM).
$ErrorActionPreference = 'SilentlyContinue'

# --- Fast path: lifecycle.json ---
$lifecyclePath = Join-Path $env:HERMES_HOME 'state\gateway.lifecycle.json'
if (Test-Path $lifecyclePath) {
    try {
        $lc = Get-Content -Raw $lifecyclePath | ConvertFrom-Json
        if ($lc.phase -eq 'running' -and $lc.pid) {
            # Verify the PID is actually alive (file could be stale)
            $proc = Get-Process -Id $lc.pid -ErrorAction SilentlyContinue
            if ($proc) {
                Write-Output 'RUNNING'
                exit 0
            }
        }
    } catch { }
}

# --- Slow path: CIM query (fallback if lifecycle.json missing/stale) ---
try {
    $c = @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='hermes.exe'" |
        Where-Object { $_.CommandLine -match 'hermes' -and $_.CommandLine -match 'gateway' })
    if ($c.Count -gt 0) { Write-Output 'RUNNING' }
} catch { }
