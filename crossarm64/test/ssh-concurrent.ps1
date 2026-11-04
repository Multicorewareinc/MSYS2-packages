# Simultaneous ssh sessions against the ARM64 sshd (issue #50/#51 regression test).
#
#   powershell -ExecutionPolicy Bypass -File crossarm64\test\ssh-concurrent.ps1 `
#       -MinGit C:\msys64\home\me\mingit -Root C:\upstream-root -Work C:\sshtest -N 30 -Rounds 5
#
# Each round starts N ssh sessions at once; each runs real work that forks
# (sleep, a pipeline) and echoes a token that is checked.  Per round: ok /
# failed / hung, whether the listener survived, and leftover sshd-session
# processes.  MaxStartups is raised so sshd's own connection throttling is not
# what gets measured; pass -DefaultMaxStartups to test with sshd's defaults.
param([string]$MinGit = "$env:USERPROFILE\mingit", [string]$Root = 'C:\upstream-root',
      [string]$Work = 'C:\sshtest', [int]$N = 20, [int]$Rounds = 5, [int]$Port = 4330,
      [switch]$DefaultMaxStartups)
. "$PSScriptRoot\common.ps1"
Initialize-Work
$extra = if ($DefaultMaxStartups) { @() } else { @('MaxStartups 500') }
Stop-Sshd $Port; Start-Sshd $Port $extra
"sshd on $Port ($(if ($extra) { $extra } else { 'default MaxStartups' })): $N simultaneous sessions x $Rounds rounds"
$base = @('-i', "$W/ssh/id_ed25519", '-p', "$Port", '-o', 'UserKnownHostsFile=/dev/null', '-o', 'StrictHostKeyChecking=no',
          '-o', 'BatchMode=yes', '-o', 'LogLevel=ERROR', "$env:USERNAME@127.0.0.1")
$ssh = Join-Path $MinGit 'usr\bin\ssh.exe'
$tot = @{ ok = 0; fail = 0; hung = 0 }
for ($r = 1; $r -le $Rounds; $r++) {
  $ps = @()
  for ($i = 1; $i -le $N; $i++) {
    $ps += Start-Tracked $ssh ($base + "sleep 1; seq 1 2000 | wc -l; echo tok-$r-$i") (Join-Path $Work "c_$i.out") (Join-Path $Work "c_$i.err")
  }
  $sw = [Diagnostics.Stopwatch]::StartNew(); $ok = 0; $fail = 0; $hung = 0
  for ($i = 0; $i -lt $N; $i++) {
    if (-not $ps[$i].WaitForExit([math]::Max(0, 60000 - [int]$sw.ElapsedMilliseconds))) { $hung++; continue }
    $o = Get-Content (Join-Path $Work "c_$($i + 1).out") -Raw -ErrorAction SilentlyContinue
    if ($ps[$i].ExitCode -eq 0 -and $o -match '2000' -and $o -match "tok-$r-$($i + 1)\b") { $ok++ } else { $fail++ }
  }
  $secs = [math]::Round($sw.Elapsed.TotalSeconds, 1)
  Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'ssh.exe' -and $_.ExecutablePath -like "$MinGit*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Start-Sleep 2
  $left = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'sshd-session.exe' -and $_.CommandLine -like "*sshd_$Port*" }).Count
  "round {0}: ok={1,3} fail={2} hung={3}  ({4}s)  listener={5}  leftover sshd-session={6}" -f $r, $ok, $fail, $hung, $secs, $(if (Test-Listening $Port) { 'up' } else { 'DEAD' }), $left
  $tot.ok += $ok; $tot.fail += $fail; $tot.hung += $hung
  if (-not (Test-Listening $Port)) { break }
}
"TOTAL: ok=$($tot.ok) fail=$($tot.fail) hung=$($tot.hung) of $($N * $Rounds)"
Stop-Sshd $Port
exit [int](($tot.fail + $tot.hung) -ne 0)
