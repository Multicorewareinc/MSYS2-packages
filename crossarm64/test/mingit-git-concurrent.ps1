# MinGit: N simultaneous git clones, then N simultaneous pushes (one branch
# each) over ssh to the ARM64 sshd; verify every branch landed and the server
# repository is intact.
#
#   powershell -ExecutionPolicy Bypass -File crossarm64\test\mingit-git-concurrent.ps1 `
#       -MinGit C:\msys64\home\me\mingit -Root C:\upstream-root -Work C:\sshtest -N 20
param([string]$MinGit = "$env:USERPROFILE\mingit", [string]$Root = 'C:\upstream-root',
      [string]$Work = 'C:\sshtest', [int]$N = 20, [int]$Port = 4333)
. "$PSScriptRoot\common.ps1"
Initialize-Work
Stop-Sshd $Port; Start-Sshd $Port @('MaxStartups 500')
$env:GIT_SSH_COMMAND = "ssh -i $W/ssh/id_ed25519 -p $Port -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
$url = "ssh://$env:USERNAME@127.0.0.1$W/bare.git"
$bare = Join-Path $Work 'bare.git'; $cg = Join-Path $Work 'cg'
Remove-Item $cg -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory $cg | Out-Null
# start from a clean slate: drop branches left by an earlier run
git --git-dir=$bare for-each-ref --format='%(refname)' 'refs/heads/par*' | ForEach-Object { git --git-dir=$bare update-ref -d $_ }

function Run-All($label, [scriptblock]$mk) {
  $ps = @(); for ($i = 1; $i -le $N; $i++) { $ps += & $mk $i }
  $sw = [Diagnostics.Stopwatch]::StartNew(); $ok = 0; $hung = 0; $fail = 0
  foreach ($p in $ps) {
    if (-not $p.WaitForExit([math]::Max(0, 120000 - [int]$sw.ElapsedMilliseconds))) { $hung++ } elseif ($p.ExitCode -eq 0) { $ok++ } else { $fail++ }
  }
  # Write-Host, not output: the function's only output must be the count
  Write-Host ("{0,-26} ok={1} fail={2} hung={3}  ({4}s)  listener={5}" -f $label, $ok, $fail, $hung, [math]::Round($sw.Elapsed.TotalSeconds, 1), $(if (Test-Listening $Port) { 'up' } else { 'DEAD' }))
  return ($fail + $hung)
}
$git = Join-Path $MinGit 'cmd\git.exe'
$bad = Run-All "$N simultaneous clones" { param($i) Start-Tracked $git @('clone', '-q', '-u', "`"$Up`"", '-b', 'main', $url, "$cg\c$i") "$cg\clone$i.out" "$cg\clone$i.err" }
for ($i = 1; $i -le $N; $i++) {
  $c = "$cg\c$i"
  git -C $c config user.name t; git -C $c config user.email t@t; git -C $c config remote.origin.receivepack $Rp
  Set-Content "$c\par$i.txt" "parallel $i"; git -C $c add "par$i.txt"; git -C $c commit -qm "parallel $i"
}
$bad += Run-All "$N simultaneous pushes" { param($i) Start-Tracked $git @('-C', "$cg\c$i", 'push', '-q', 'origin', "HEAD:refs/heads/par$i") "$cg\push$i.out" "$cg\push$i.err" }
$landed = @(git --git-dir=$bare for-each-ref --format='%(refname)' 'refs/heads/par*').Count
"branches landed on server: $landed / $N"
git --git-dir=$bare fsck --no-dangling --no-progress 2>&1 | Select-Object -First 3
$fsck = $LASTEXITCODE
"server repo fsck rc=$fsck"
Stop-Sshd $Port
exit [int](($bad -ne 0) -or ($landed -ne $N) -or ($fsck -ne 0))
