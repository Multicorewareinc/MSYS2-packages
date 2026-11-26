# Run every suite against an ARM64 root (30-mkroot.sh + 60-stage-test-root.sh)
# and, with -MinGit, the MinGit ssh/git suites and git's own testsuite.
#
#   powershell -ExecutionPolicy Bypass -File crossarm64\test\run-root-tests.ps1 `
#       -Root C:\upstream-root -Out C:\results\run1 `
#       [-MinGit C:\msys64\home\<you>\mingit] [-GitBuild C:\gitbuild] [-Skip bash,ssh,stress,mingit,git]
#
# Order: bash testsuite -> OpenSSH regress (unit + t-exec) -> sshd stress ->
# MinGit ssh features / concurrent ssh / concurrent git -> git testsuite.
# Leftover root processes are killed (by path) between suites, because hung
# bash groups keep files in the root locked.  winsup is NOT here: it runs from
# the MSYS2 shell right after the runtime build (40-winsup-test.sh).
# status.txt puts each result next to its baseline; failures to compare by
# name are listed in crossarm64/ci/expected/{bash,ssh,git}.txt.
param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Out,
      [string]$MinGit = '', [string]$GitBuild = '', [string[]]$Skip = @())
$Skip = @($Skip | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$Root = (Resolve-Path $Root).Path
New-Item -ItemType Directory -Force $Out | Out-Null
$Out = (Resolve-Path $Out).Path
$ps = Join-Path $PSHOME 'powershell.exe'
$S = Join-Path $Out 'status.txt'
function St($m) { "$(Get-Date -Format HH:mm:ss) $m" | Tee-Object -FilePath $S -Append }
function Stop-Root { Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -like "$Root\*" } |
                       ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } }
$saved = $env:PATH
foreach ($v in 'SHELL', 'MSYSTEM', 'CHERE_INVOKING', 'MSYS', 'HOME', 'TMPDIR', 'BASH_ENV') { Remove-Item "Env:$v" -ErrorAction SilentlyContinue }
$env:PATH = "$Root\usr\bin;$env:SystemRoot\system32;$env:SystemRoot"
$bash = "$Root\usr\bin\bash.exe"
foreach ($f in 'run-bash-tests.sh', 'run-ssh-tests.sh') {
  if (-not (Test-Path "$Root\tmp\$f")) { throw "$Root\tmp\$f missing: run crossarm64/60-stage-test-root.sh first" }
}

if ($Skip -notcontains 'bash') {
  St "bash testsuite ($(& $bash -c 'echo $BASH_VERSION'))   [baseline: 63-64 pass / 22-23 fail; x86_64 63/23; run-jobs flaky]"
  & $bash --login -c "sh /tmp/run-bash-tests.sh /usr/share/bash/tests /tmp/bash-results 300" *> (Join-Path $Out 'bash.log')
  St "  $(Get-Content "$Root\tmp\bash-results\summary.txt" -Tail 1)"
  Copy-Item -Recurse -Force "$Root\tmp\bash-results" (Join-Path $Out 'bash-results')
  Stop-Root
}
if ($Skip -notcontains 'ssh') {
  if (-not (Test-Path "$Root\build\openssh\regress")) { throw "no $Root\build\openssh: run 60-stage-test-root.sh" }
  St "openssh regress   [baseline: unit 12/1 (utf8), t-exec 80 pass / 1 fail (sftp-perm) / 16 skip = x86_64]"
  & $bash --login -c "bash /tmp/run-ssh-tests.sh /build/openssh /tmp/ssh-results all 600" *> (Join-Path $Out 'ssh.log')
  St "  $(Get-Content "$Root\tmp\ssh-results\unit-summary.txt" -Tail 1)"
  St "  $(Get-Content "$Root\tmp\ssh-results\t-exec-summary.txt" -Tail 1)"
  Copy-Item -Recurse -Force "$Root\tmp\ssh-results" (Join-Path $Out 'ssh-results')
  Stop-Root
}
$env:PATH = $saved
if ($Skip -notcontains 'stress') {
  St "sshd session stress   [baseline: 300/300]"
  & $ps -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\sshd-stress.ps1" -Root $Root -Work (Join-Path $Out 'sshtest') |
    ForEach-Object { St "  $_" }
}
if ($MinGit -and $Skip -notcontains 'mingit') {
  $MinGit = (Resolve-Path $MinGit).Path
  $w = Join-Path $Out 'mingit-ssh'
  St "MinGit ssh features   [baseline 19/19]"
  & $ps -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\mingit-ssh-features.ps1" -MinGit $MinGit -Root $Root -Work $w | ForEach-Object { St "  $_" }
  St "simultaneous ssh sessions   [baseline all ok]"
  & $ps -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\ssh-concurrent.ps1" -MinGit $MinGit -Root $Root -Work $w -N 30 -Rounds 5 | ForEach-Object { St "  $_" }
  St "simultaneous git clone/push   [baseline 20/20, fsck clean]"
  & $ps -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\mingit-git-concurrent.ps1" -MinGit $MinGit -Root $Root -Work $w -N 20 | ForEach-Object { St "  $_" }
  Stop-Root
}
if ($Skip -notcontains 'git' -and $MinGit -and $GitBuild) {
  St "git testsuite on MinGit   [snapshot ci/expected/git.txt: 697 pass / 196 fail / 158 skip - compare failures by name]"
  & $ps -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\run-git-tests-mingit.ps1" `
      -MinGit $MinGit -GitBuild $GitBuild -Out (Join-Path $Out 'git') -Jobs 10 | ForEach-Object { St "  $_" }
  $exp = Get-Content (Join-Path $PSScriptRoot '..\ci\expected\git.txt') | ForEach-Object { ($_ -replace '#.*', '').Trim() } | Where-Object { $_ }
  $new = Get-Content (Join-Path $Out 'git\summary.txt') | Where-Object { $_ -match '^(FAIL|TIMEOUT)' } |
           ForEach-Object { ($_ -split '\s+')[1] } | Where-Object { $exp -notcontains $_ }
  St "  failing and NOT in ci/expected/git.txt: $(@($new).Count) $(@($new) -join ' ')"
} elseif ($Skip -notcontains 'git') {
  St "git testsuite skipped: pass -MinGit and -GitBuild (crossarm64/test/build-git-testtree.sh makes the build tree)"
}
St "ALL DONE - results in $Out"
