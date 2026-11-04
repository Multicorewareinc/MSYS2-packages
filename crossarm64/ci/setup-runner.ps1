# Prepare a Windows-ARM64 machine for .github/workflows/arm64-selfhosted.yml.
#
#   powershell -ExecutionPolicy Bypass -File crossarm64\ci\setup-runner.ps1 `
#       -Token <registration token> [-GitBuildFrom <built Git for Windows tree>]
#
# The token comes from the repository's Settings > Actions > Runners > New
# self-hosted runner page (or POST /repos/{owner}/{repo}/actions/runners/
# registration-token); it is valid for an hour.  Safe to re-run: every step
# skips what already exists.
#
#   $Msys    the CI's own x86_64 MSYS2 (kept apart from any MSYS2 used for
#            development: the CI reinstalls the toolchain and wipes the sysroot)
#   $State   what persists between runs (crossarm64/ci/common.sh)
#   $Runner  the runner, started at logon as the current user, so the tests
#            run with a real user profile (sshd, HOME) rather than a service
#            account
param(
  [string]$Token,
  [string]$Repo = 'aswin-mcw/MSYS2-packages',
  [string]$Msys = 'C:\ci-msys64',
  [string]$State = 'C:\ci-state',
  [string]$Runner = 'C:\actions-runner-msys2',
  [string]$Label = 'msys2-arm64',
  [string]$GitBuildFrom = '',
  [string]$GitVersion = '2.55.0.windows.5'
)
$ErrorActionPreference = 'Stop'
function Step($m) { Write-Host "=== $m" }

# --- MSYS2 ------------------------------------------------------------------
if (-not (Test-Path "$Msys\usr\bin\bash.exe")) {
  Step "Installing MSYS2 in $Msys"
  $tmp = Join-Path $env:TEMP 'ci-msys2'
  New-Item -ItemType Directory -Force $tmp | Out-Null
  $sfx = Join-Path $tmp 'msys2-base.sfx.exe'
  Invoke-WebRequest -UseBasicParsing 'https://repo.msys2.org/distrib/msys2-x86_64-latest.sfx.exe' -OutFile $sfx
  & $sfx -y "-o$tmp" | Out-Null
  Move-Item (Join-Path $tmp 'msys64') $Msys
}
$bash = "$Msys\usr\bin\bash.exe"
$env:MSYSTEM = 'MSYS'; $env:CHERE_INVOKING = '1'
Step 'First start and full update'
& $bash --login -c 'true'
& $bash --login -c 'pacman -Syuu --noconfirm --noprogressbar'
& $bash --login -c 'pacman -Syuu --noconfirm --noprogressbar'
# a few packages the stage scripts use besides crossarm64/00-host-prereqs.sh
& $bash --login -c 'pacman -S --needed --noconfirm --noprogressbar file libarchive make'

# --- persistent state -------------------------------------------------------
foreach ($d in 'srcdest', 'cache', 'run') { New-Item -ItemType Directory -Force (Join-Path $State $d) | Out-Null }

# The git test suite needs a Git for Windows build tree of the same version as
# the MinGit zip (test-tool, t/).  Copy one and point its recorded paths at
# the new place (crossarm64/test/run-git-tests-mingit.ps1).
$gb = Join-Path $State 'gitbuild'
if ($GitBuildFrom -and -not (Test-Path "$gb\GIT-BUILD-OPTIONS")) {
  Step "Copying the Git build tree to $gb"
  & robocopy $GitBuildFrom $gb /E /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)" }
  $from = (& "$Msys\usr\bin\cygpath.exe" -u $GitBuildFrom).TrimEnd('/') -replace '^/cygdrive', ''
  $to = (& "$Msys\usr\bin\cygpath.exe" -u $gb).TrimEnd('/') -replace '^/cygdrive', ''
  & $bash --login -c "cd '$to' && sed -i 's#$from#$to#g' GIT-BUILD-OPTIONS bin-wrappers/*"
}
if (-not (Test-Path "$gb\t\helper\test-tool.exe")) {
  Write-Warning "no Git build tree in ${gb}: pass -GitBuildFrom <built git-$GitVersion tree> (the git test stage needs it)"
}

# --- runner -----------------------------------------------------------------
if (-not (Test-Path "$Runner\.runner")) {
  if (-not $Token) { throw "pass -Token <registration token> to register the runner" }
  Step "Installing the runner in $Runner"
  New-Item -ItemType Directory -Force $Runner | Out-Null
  $rel = Invoke-RestMethod -UseBasicParsing 'https://api.github.com/repos/actions/runner/releases/latest'
  $asset = $rel.assets | Where-Object name -match '^actions-runner-win-arm64-.*\.zip$' | Select-Object -First 1
  $zip = Join-Path $Runner $asset.name
  Invoke-WebRequest -UseBasicParsing $asset.browser_download_url -OutFile $zip
  Expand-Archive -Force $zip $Runner
  Remove-Item $zip
  Push-Location $Runner
  & .\config.cmd --unattended --url "https://github.com/$Repo" --token $Token `
      --name "$env:COMPUTERNAME-$Label" --labels $Label --work _work --replace
  if ($LASTEXITCODE) { throw "runner configuration failed" }
  Pop-Location
}

# Start at logon, as this user, and right now
$task = 'GitHub runner msys2-arm64'
if (-not (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue)) {
  Step "Registering scheduled task '$task'"
  $action = New-ScheduledTaskAction -Execute "$Runner\run.cmd" -WorkingDirectory $Runner
  $trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
  $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 `
      -RestartInterval (New-TimeSpan -Minutes 5) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
  Register-ScheduledTask -TaskName $task -Action $action -Trigger $trigger -Settings $settings | Out-Null
}
if (-not (Get-Process Runner.Listener -ErrorAction SilentlyContinue | Where-Object Path -like "$Runner\*")) {
  Start-ScheduledTask -TaskName $task
}
Step "Done. Runner '$env:COMPUTERNAME-$Label' for $Repo, label $Label"
