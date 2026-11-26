# sshd session stress against an ARM64 root's own sshd and ssh (the #50/#51
# regression test: lost SIGCHLD -> exit-status never sent -> session hangs).
#
#   powershell -ExecutionPolicy Bypass -File crossarm64\test\sshd-stress.ps1 `
#       -Root C:\upstream-root [-Work C:\sshtest] [-Port 4321] [-Seq 200] [-Conc 10] [-Rounds 10]
#
# Starts the root's sshd, then (1) $Seq sequential "echo hi" sessions and
# (2) $Rounds rounds of $Conc simultaneous sessions, all with the root's own
# ssh.exe.  A session that does not finish in 15 s counts as hung.
# Baseline (25 Nov 2026, v11 packages): 200/200 sequential, 100/100 concurrent.
# Exit code 0 only when every session was ok.
param([Parameter(Mandatory)][string]$Root, [string]$Work = 'C:\sshtest', [int]$Port = 4321,
      [int]$Seq = 200, [int]$Conc = 10, [int]$Rounds = 10)
$ErrorActionPreference = 'Continue'
function ConvertTo-MsysPath([string]$p) {
  $p = $p -replace '\\', '/'
  if ($p -match '^([A-Za-z]):/(.*)$') { return '/' + $matches[1].ToLower() + '/' + $matches[2] }
  $p
}
$Root = (Resolve-Path $Root).Path
$bin = "$Root\usr\bin"; $ssh = "$bin\ssh.exe"; $W = ConvertTo-MsysPath $Work
$env:PATH = "$bin;$env:SystemRoot\system32;$env:SystemRoot"
foreach ($v in 'SHELL', 'MSYSTEM', 'CHERE_INVOKING', 'MSYS', 'BASH_ENV') { Remove-Item "Env:$v" -ErrorAction SilentlyContinue }
$env:HOME = Join-Path $Work 'home'
New-Item -ItemType Directory -Force $Work, (Join-Path $Work 'home\.ssh') | Out-Null

function Invoke-RootBash([string]$cmd) {
  $env:MSYS2_ARG_CONV_EXCL = '*'; & "$bin\bash.exe" --login -c $cmd; $env:MSYS2_ARG_CONV_EXCL = $null
}
# keys + base sshd_config, made with the root's own ssh-keygen
if (-not (Test-Path (Join-Path $Work 'ssh\hostkey'))) {
  Invoke-RootBash "bash $(ConvertTo-MsysPath "$PSScriptRoot\ssh-test-setup.sh") $W" | Out-Host
}
$cfg = Join-Path $Work "ssh\sshd_stress_$Port"
(Get-Content (Join-Path $Work 'ssh\sshd_config')) + "Port $Port" + "PidFile $W/ssh/stress_$Port.pid" + 'MaxStartups 100' |
  Set-Content -Encoding ascii $cfg

function Up { [bool](Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) }
function Stop-Root { Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -like "$Root\*" } |
                       ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } }
Stop-Root
$env:MSYS2_ARG_CONV_EXCL = '*'
Start-Process -FilePath "$bin\bash.exe" -WindowStyle Hidden -ArgumentList '--login', '-c',
  "`"export SHELL=/usr/bin/bash; /usr/bin/sshd -f $W/ssh/sshd_stress_$Port -E $W/ssh/stress_$Port.log`"" | Out-Null
$env:MSYS2_ARG_CONV_EXCL = $null
for ($i = 0; $i -lt 40 -and -not (Up); $i++) { Start-Sleep -Milliseconds 500 }
if (-not (Up)) { "FATAL: sshd did not start on $Port (see $Work\ssh\stress_$Port.log)"; exit 2 }

# the login name as the root's runtime sees it (a domain/AzureAD account can be DOMAIN+user)
$user = (& (Join-Path $bin 'id.exe') -un).Trim()
$sshArgs = @('-i', "$W/ssh/id_ed25519", '-p', "$Port", '-o', 'StrictHostKeyChecking=no', '-o', 'UserKnownHostsFile=/dev/null',
             '-o', 'BatchMode=yes', '-o', 'LogLevel=ERROR', "$user@127.0.0.1", 'echo', 'hi')
$tmp = Join-Path $Work "stress_$Port"; New-Item -ItemType Directory -Force $tmp | Out-Null

$ok = 0; $hung = 0; $bad = 0
for ($n = 1; $n -le $Seq; $n++) {
  $p = Start-Process -FilePath $ssh -ArgumentList $sshArgs -NoNewWindow -PassThru -RedirectStandardOutput "$tmp\o.txt" -RedirectStandardError "$tmp\e.txt"
  $null = $p.Handle
  if (-not $p.WaitForExit(15000)) { $hung++; Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; continue }
  if ($p.ExitCode -eq 0 -and (Get-Content "$tmp\o.txt" -Raw) -match '^hi') { $ok++ } else { $bad++ }
}
"sequential: $Seq sessions  ok=$ok hung=$hung bad=$bad  listener=$(if (Up) {'up'} else {'DEAD'})"

$tok = 0; $thung = 0; $tbad = 0
for ($r = 1; $r -le $Rounds; $r++) {
  $ps = @(); for ($i = 0; $i -lt $Conc; $i++) {
    $p = Start-Process -FilePath $ssh -ArgumentList $sshArgs -NoNewWindow -PassThru -RedirectStandardOutput "$tmp\c$i.txt" -RedirectStandardError "$tmp\ce$i.txt"
    $null = $p.Handle; $ps += $p }
  $deadline = (Get-Date).AddSeconds(30)
  for ($i = 0; $i -lt $Conc; $i++) {
    $left = [int][Math]::Max(0, ($deadline - (Get-Date)).TotalMilliseconds)
    if (-not $ps[$i].WaitForExit($left)) { $thung++; Stop-Process -Id $ps[$i].Id -Force -ErrorAction SilentlyContinue }
    elseif ($ps[$i].ExitCode -eq 0 -and (Get-Content "$tmp\c$i.txt" -Raw) -match '^hi') { $tok++ } else { $tbad++ }
  }
}
Start-Sleep -Seconds 2
$leftover = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'sshd-session.exe' -and $_.ExecutablePath -like "$Root\*" }).Count
"concurrent: $Rounds x $Conc sessions  ok=$tok hung=$thung bad=$tbad  listener=$(if (Up) {'up'} else {'DEAD'})  leftover sshd-session=$leftover"
"TOTAL: ok=$($ok + $tok) of $($Seq + $Rounds * $Conc)"
Stop-Root
exit [int](($hung + $bad + $thung + $tbad) -ne 0)
