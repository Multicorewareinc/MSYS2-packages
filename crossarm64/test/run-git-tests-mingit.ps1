# Run git's testsuite against a MinGit *package*, exactly as released: the
# package's own git.exe (clangarm64/bin) and its own usr/bin, nothing else on
# PATH.  Compare our ARM64 MinGit with the unmodified official zip -- they
# differ only in usr/bin.
#
#   powershell -ExecutionPolicy Bypass -File crossarm64\test\run-git-tests-mingit.ps1 `
#       -MinGit C:\path\to\mingit -GitBuild C:\path\to\git-2.55.0.windows.5 -Out C:\results\mingit-arm64
#
# -GitBuild is a built Git for Windows tree of the SAME version as the
# package: MinGit ships no test helpers, so t/ and t/helper/test-tool come from
# there, while GIT_TEST_INSTALLED makes the tests run the package's git.exe.
# Every DLL the helpers need is in MinGit's clangarm64/bin.
# The build tree's GIT-BUILD-OPTIONS and bin-wrappers must hold /c/... paths
# (see git-testsuite report), since /home differs between roots.
param([Parameter(Mandatory)][string]$MinGit, [Parameter(Mandatory)][string]$GitBuild,
      [Parameter(Mandatory)][string]$Out, [int]$Jobs = 10, [int]$Timeout = 1800, [string]$Tests = '')   # -Tests "t0000-basic.sh,t0001-init.sh"

function ConvertTo-MsysPath([string]$p) {
  $p = $p -replace '\\', '/'
  if ($p -match '^([A-Za-z]):/(.*)$') { return '/' + $matches[1].ToLower() + '/' + $matches[2] }
  $p
}
$MinGit = (Resolve-Path $MinGit).Path; $GitBuild = (Resolve-Path $GitBuild).Path
$tdir = Join-Path $GitBuild 't'
New-Item -ItemType Directory -Force (Join-Path $Out 'logs'), (Join-Path $Out 'trash') | Out-Null
$sh = Join-Path $MinGit 'usr\bin\sh.exe'

# The release environment: the package's directories only, as cmd\git.exe sets
# them up, plus Windows.  Nothing inherited from the launching shell.
$env:PATH = "$MinGit\usr\bin;$MinGit\clangarm64\bin;$env:SystemRoot\system32;$env:SystemRoot"
foreach ($v in 'SHELL', 'MSYS2_ARG_CONV_EXCL', 'MSYS2_ENV_CONV_EXCL', 'GIT_DIR', 'GIT_WORK_TREE', 'GIT_EXEC_PATH',
               'GIT_TEMPLATE_DIR', 'GIT_CONFIG', 'HOME', 'TERM') { Remove-Item "Env:$v" -ErrorAction SilentlyContinue }
$env:MSYSTEM = 'MINGW64'                     # what MinGit's git.exe sets for its sh; uname -s -> MINGW64_NT
$env:GIT_TEST_INSTALLED = ConvertTo-MsysPath "$MinGit\clangarm64\bin"   # run the PACKAGE's git.exe
$env:GIT_TEST_CHAIN_LINT = '0'               # the linter is perl; MinGit has none
$env:LANG = 'C'; $env:LC_ALL = 'C'

$list = if ($Tests) { $Tests -split ',\s*' } else { Get-ChildItem $tdir -Filter 't*.sh' | Where-Object Name -match '^t\d{4}-.*\.sh$' | Sort-Object Name | ForEach-Object Name }
"{0} scripts, {1} in parallel, {2}s each; sh = {3}" -f $list.Count, $Jobs, $Timeout, $sh
$queue = [Collections.Generic.Queue[string]]::new(); $list | ForEach-Object { $queue.Enqueue($_) }
$running = @{}; $rcs = @{}; $start = Get-Date

function Stop-Tree([int]$id) { & taskkill.exe /T /F /PID $id 2>&1 | Out-Null }
while ($queue.Count -or $running.Count) {
  while ($queue.Count -and $running.Count -lt $Jobs) {
    $t = $queue.Dequeue(); $n = $t -replace '\.sh$', ''
    $trash = ConvertTo-MsysPath (Join-Path $Out "trash\$n")
    $p = Start-Process -FilePath $sh -ArgumentList "./$t", "--root=$trash" -WorkingDirectory $tdir -NoNewWindow -PassThru `
           -RedirectStandardOutput (Join-Path $Out "logs\$n.out") -RedirectStandardError (Join-Path $Out "logs\$n.err")
    $null = $p.Handle
    $running[$n] = @{ P = $p; T0 = Get-Date }
  }
  Start-Sleep -Milliseconds 300
  foreach ($n in @($running.Keys)) {
    $r = $running[$n]
    if ($r.P.HasExited) { $rcs[$n] = $r.P.ExitCode }
    elseif (((Get-Date) - $r.T0).TotalSeconds -gt $Timeout) { Stop-Tree $r.P.Id; $rcs[$n] = 124 }
    else { continue }
    $running.Remove($n)
    Remove-Item -Recurse -Force (Join-Path $Out "trash\$n") -ErrorAction SilentlyContinue
    if ($rcs.Count % 50 -eq 0) { "  {0}/{1} done ({2:N0} min)" -f $rcs.Count, $list.Count, ((Get-Date) - $start).TotalMinutes }
  }
}

# Same classification as run-git-tests.sh: one line per script
$lines = foreach ($n in ($rcs.Keys | Sort-Object)) {
  $log = Join-Path $Out "logs\$n.out"; $c = if (Test-Path $log) { Get-Content $log } else { @() }
  $ok = @($c | Where-Object { $_ -match '^ok ' }).Count; $nok = @($c | Where-Object { $_ -match '^not ok ' }).Count
  $sk = @($c | Where-Object { $_ -match '^ok .* # skip' }).Count; $brk = @($c | Where-Object { $_ -match '^not ok .* # TODO' }).Count
  $fail = $nok - $brk; $rc = $rcs[$n]
  $s = if ($rc -eq 124) { 'TIMEOUT' } elseif ($c | Where-Object { $_ -match '^1\.\.0 # SKIP' }) { 'SKIP' } elseif ($rc -eq 0 -and $fail -eq 0) { 'PASS' } else { 'FAIL' }
  '{0,-7} {1,-52} ok={2} fail={3} skip={4} known_broken={5} rc={6}' -f $s, $n, ($ok - $sk), $fail, $sk, $brk, $rc
}
$lines | Set-Content -Encoding ascii (Join-Path $Out 'summary.txt')
"elapsed {0:N0} min" -f ((Get-Date) - $start).TotalMinutes
$lines | ForEach-Object { ($_ -split '\s+')[0] } | Group-Object | Sort-Object Name | ForEach-Object { '{0,6} {1}' -f $_.Count, $_.Name }
