# Run a command in the ARM64 root's own login shell, with nothing from the
# runner's environment that could pull in another runtime: only the root's
# usr\bin and Windows on PATH, and no SHELL, HOME or MSYS2 variables (bash
# test helpers and ssh's ProxyCommand would otherwise start the wrong shell).
#
#   powershell -File crossarm64\ci\run-in-root.ps1 -Root C:\ci-state\run\root -Command '...'
param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Command)

$bash = Join-Path $Root 'usr\bin\bash.exe'
if (-not (Test-Path $bash)) { throw "no bash in $Root\usr\bin" }
$env:PATH = "$Root\usr\bin;$env:SystemRoot\system32;$env:SystemRoot"
foreach ($v in 'SHELL', 'HOME', 'MSYSTEM', 'MSYS', 'CHERE_INVOKING', 'MSYS2_PATH_TYPE', 'MSYS2_ARG_CONV_EXCL',
               'MSYS2_ENV_CONV_EXCL', 'TMPDIR', 'TEMP_MSYS', 'BASH_ENV', 'ENV') {
  Remove-Item "Env:$v" -ErrorAction SilentlyContinue
}
& $bash --login -c $Command
exit $LASTEXITCODE
