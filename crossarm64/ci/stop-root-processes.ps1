# Stop every process running from the ARM64 root (left over from a test that
# hung or a job that was cancelled), so the root's files can be replaced.
#
#   powershell -File crossarm64\ci\stop-root-processes.ps1 -Root C:\ci-state\run\root
param([Parameter(Mandatory)][string]$Root)

$prefix = (Resolve-Path -LiteralPath $Root -ErrorAction SilentlyContinue).Path
if (-not $prefix) { exit 0 }
$prefix = $prefix.TrimEnd('\') + '\'
$left = Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($prefix, 'OrdinalIgnoreCase') }
foreach ($p in $left) {
  Write-Host "stopping leftover $($p.Name) $($p.ProcessId): $($p.CommandLine)"
  Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
}
exit 0
