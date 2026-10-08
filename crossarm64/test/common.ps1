# Shared helpers for the MinGit / ssh tests.  Dot-source it after setting
# $MinGit, $Root and $Work (Windows paths), e.g.
#   . "$PSScriptRoot\common.ps1"
#
#   $MinGit  assembled MinGit (crossarm64/50-mingit-proto1.sh output)
#   $Root    ARM64 test root (crossarm64/30-mkroot.sh output); its sshd is the server
#   $Work    scratch directory for keys, repos and logs

function ConvertTo-MsysPath([string]$p) {
  $p = $p -replace '\\', '/'
  if ($p -match '^([A-Za-z]):/(.*)$') { return '/' + $matches[1].ToLower() + '/' + $matches[2] }
  return $p
}

$script:W   = ConvertTo-MsysPath $Work
$script:MG  = ConvertTo-MsysPath $MinGit
$script:RootBash = Join-Path $Root 'usr\bin\bash.exe'
$script:Sh  = Join-Path $MinGit 'usr\bin\sh.exe'
$script:Up  = "$MG/cmd/git.exe upload-pack"     # server side: cmd\git.exe sets up git's own PATH
$script:Rp  = "$MG/cmd/git.exe receive-pack"

# Client environment: only MinGit on PATH, a throwaway HOME, nothing inherited
# from the launching shell (a foreign SHELL makes ssh run ProxyCommand with
# the wrong bash).
$env:PATH = "$MinGit\cmd;$MinGit\usr\bin;$env:SystemRoot\system32;$env:SystemRoot"
$env:SHELL = $null; $env:MSYSTEM = $null
$env:HOME = Join-Path $Work 'home'

function Invoke-RootBash([string]$cmd) {
  $env:MSYS2_ARG_CONV_EXCL = '*'
  & $script:RootBash --login -c $cmd
  $env:MSYS2_ARG_CONV_EXCL = $null
}

function Initialize-Work {
  New-Item -ItemType Directory -Force $Work, (Join-Path $Work 'home\.ssh') | Out-Null
  if (-not (Test-Path (Join-Path $Work 'ssh\hostkey'))) {
    Invoke-RootBash "bash $(ConvertTo-MsysPath "$PSScriptRoot\ssh-test-setup.sh") $W" | Out-Host
  }
  $bare = Join-Path $Work 'bare.git'
  if (-not (Test-Path $bare)) {
    git init -q --bare -b main $bare
    $seed = Join-Path $Work 'seed'
    git init -q -b main $seed
    Set-Content (Join-Path $seed 'a.txt') 'seed'
    git -C $seed add a.txt; git -C $seed -c user.name=t -c user.email=t@t commit -qm seed
    git -C $seed push -q $bare main
    Remove-Item -Recurse -Force $seed
  }
}

function Test-Listening([int]$Port) { [bool](Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) }

# Start the ROOT's ARM64 sshd on $Port with optional extra config lines.
# Detached on purpose: a daemonized sshd would hold a captured stdout pipe
# open forever.
function Start-Sshd([int]$Port, [string[]]$Extra = @()) {
  $cfg = Join-Path $Work "ssh\sshd_$Port"
  $base = Get-Content (Join-Path $Work 'ssh\sshd_config')
  ($base + "Port $Port" + "PidFile $W/ssh/sshd_$Port.pid" + $Extra) | Set-Content -Encoding ascii $cfg
  $env:MSYS2_ARG_CONV_EXCL = '*'
  Start-Process -FilePath $script:RootBash -WindowStyle Hidden -ArgumentList '--login', '-c',
    "`"export SHELL=/usr/bin/bash; /usr/bin/sshd -f $W/ssh/sshd_$Port -E $W/ssh/sshd_$Port.log`"" | Out-Null
  $env:MSYS2_ARG_CONV_EXCL = $null
  for ($i = 0; $i -lt 40 -and -not (Test-Listening $Port); $i++) { Start-Sleep -Milliseconds 250 }
  if (-not (Test-Listening $Port)) { throw "sshd did not start on $Port (see $Work\ssh\sshd_$Port.log)" }
}

function Stop-Sshd([int]$Port) {
  Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*sshd_$Port*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

# Start-Process wrapper that keeps ExitCode readable (PS 5.1 loses it for
# -NoNewWindow processes unless the handle is taken immediately).
function Start-Tracked([string]$File, [string[]]$ArgList, [string]$Out, [string]$Err) {
  $p = Start-Process -FilePath $File -ArgumentList $ArgList -NoNewWindow -PassThru `
         -RedirectStandardOutput $Out -RedirectStandardError $Err
  $null = $p.Handle
  return $p
}
