# MinGit ssh client features against the ARM64 sshd, from plain Windows.
#
#   powershell -ExecutionPolicy Bypass -File crossarm64\test\mingit-ssh-features.ps1 `
#       -MinGit C:\msys64\home\me\mingit -Root C:\upstream-root -Work C:\sshtest
#
# Each test (mingit-ssh-features.txt: "name|||sh command") runs in MinGit's
# own sh.exe with a 30 s watchdog; a hang is retried once and reported.  The
# last line shows which ssh.exe git actually ran (captured via LocalCommand).
param([string]$MinGit = "$env:USERPROFILE\mingit", [string]$Root = 'C:\upstream-root',
      [string]$Work = 'C:\sshtest', [int]$Port = 4300)
. "$PSScriptRoot\common.ps1"
Initialize-Work
Stop-Sshd $Port; Start-Sshd $Port
"sshd listening on $Port"

$pre = "K=$W/ssh; W=$W; WWIN='$($Work -replace '\\','/')'; P=$Port; KH=`$HOME/.ssh/known_hosts; H=`$USERNAME@127.0.0.1; " +
       "O=`"-p $Port -o UserKnownHostsFile=`$KH -o BatchMode=yes -o LogLevel=ERROR`"; UP='$Up'; RP='$Rp'; cd $W; "
$t = Join-Path $Work 't.sh'; $tm = (ConvertTo-MsysPath $t)
$hangs = 0; $fails = 0; $deaths = @()
Remove-Item (Join-Path $Work 'which-ssh.txt') -ErrorAction SilentlyContinue
foreach ($line in Get-Content "$PSScriptRoot\mingit-ssh-features.txt") {
  if (-not $line.Trim()) { continue }
  $name, $cmd = $line -split '\|\|\|', 2
  $outcome = $null
  foreach ($try in 1, 2) {
    [IO.File]::WriteAllText($t, $pre + $cmd + "`n")
    $p = Start-Tracked $Sh @($tm) (Join-Path $Work 't.out') (Join-Path $Work 't.err')
    if (-not $p.WaitForExit(30000)) {
      $hangs++
      Get-CimInstance Win32_Process | Where-Object { $_.Name -in 'ssh.exe', 'ssh-agent.exe', 'sh.exe', 'git.exe' -and $_.ExecutablePath -like "$MinGit*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
      $outcome = 'HANG'; continue
    }
    $outcome = if ($p.ExitCode -eq 0) { if ($try -eq 2) { 'PASS (after a hang)' } else { 'PASS' } } else { "FAIL rc=$($p.ExitCode)" }
    break
  }
  if ($outcome -notlike 'PASS') { $fails++ }
  "{0,-22} {1}" -f $outcome, $name
  if ($outcome -notlike 'PASS*') { Get-Content (Join-Path $Work 't.err') -Tail 3 -ErrorAction SilentlyContinue | ForEach-Object { "                       | $_" } }
  if (-not (Test-Listening $Port)) { $deaths += $name; "                       | !! sshd listener died; restarting"; Start-Sshd $Port }
}
"--- ssh.exe git ran: $(Get-Content (Join-Path $Work 'which-ssh.txt') -ErrorAction SilentlyContinue)"
"--- not clean: $fails   hangs: $hangs   listener deaths: $($deaths.Count)"
Stop-Sshd $Port
exit [int]($fails -ne 0)
