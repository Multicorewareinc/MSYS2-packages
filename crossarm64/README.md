# aarch64-pc-cygwin: toolchain, userland, test root, MinGit

Run everything from an **MSYS2 shell** (`MSYSTEM=MSYS`), not Git Bash: Git
Bash has its own root and its own `SHELL`, both of which leak into the tests.

## Quickstart: bare Windows ARM64 to every suite

Needs a Windows 11 ARM64 machine and about 60 GB free. It also needs HTTPS access to:
- repo.msys2.org and its mirrors;
- github.com, including release downloads (MinGit);
- sourceware.org;
- gcc.gnu.org (both gcc recipes);
- gitlab.inria.fr (mpfr);
- the usual upstream tarball hosts (ftp.gnu.org, openssl, openssh and so on).

Use a local account, or check the user-name trap below.

1. **Install MSYS2** (the x86_64 build, which runs emulated) at `C:\msys64`. Use the official `msys2-base-x86_64-*.tar.xz`: check its sha256 and unpack it with `tar`. Start it once, then run `pacman -Syuu` twice.
2. **Clone** this repo into the MSYS2 home and check out the branch that carries these scripts (`aarch64-e2e-build-test`):

       git clone https://github.com/Multicorewareinc/MSYS2-packages ~/MSYS2-packages
       git -C ~/MSYS2-packages checkout aarch64-e2e-build-test

3. **Build everything**, in PowerShell:

       $env:MSYSTEM='MSYS'; C:\msys64\usr\bin\bash.exe -lc 'bash ~/MSYS2-packages/crossarm64/e2e.sh'

   The steps run in order: prereqs, toolchain, winsup, userland, root, stage, mingit.
   - After a failure, rerun with `FROM=<step>`.
   - Packages go to `~/aarch64-pkgs`, logs to `~/aarch64-pkgs/logs`, and the winsup output to `logs/winsup.log`.
   - The toolchain step refuses to run over an already installed cross toolchain or sysroot. `CLEAN=1` removes them first.
   - The userland is split the way the self-hosted CI does it. The PR 6922 recipes use the PR's makepkg config. The test-root tools (mpfr … hexdump, dash, util-linux, rebase) use `makepkg-harness.conf`, which runs configure natively.
4. **Git test tree** (only for the git suite):

       $env:MSYSTEM='CLANGARM64'; C:\msys64\usr\bin\bash.exe -lc 'bash ~/MSYS2-packages/crossarm64/test/build-git-testtree.sh /c/gitbuild'

5. **Run the suites**, from Windows PowerShell (not from an MSYS shell), in the repo directory:

       cd C:\msys64\home\<you>\MSYS2-packages
       powershell -ExecutionPolicy Bypass -File crossarm64\test\run-root-tests.ps1 `
           -Root C:\upstream-root -Out C:\results\e2e -MinGit C:\msys64\home\<you>\mingit -GitBuild C:\gitbuild

   It runs these suites in order: bash, OpenSSH regress (unit and t-exec), sshd stress, the MinGit ssh/git suites, then git's testsuite. `-Skip bash,ssh,...` leaves suites out.

   `status.txt` shows each result next to its baseline. For git, it also lists failing scripts that are not in `ci/expected/git.txt`.

   **Current baselines** (26 Nov 2026):

   | suite | baseline |
   |---|---|
   | winsup | 266 pass / 3 fail (link04, cancel11, systemcall), plus the XPASSes listed in `ci/expected/winsup.txt` |
   | bash | 63-64 pass / 22-23 fail |
   | OpenSSH unit | 12 / 1 |
   | OpenSSH t-exec | 80 / 1 / 16 |
   | sshd stress | 300 / 300 |
   | git on MinGit | the 196 known failures in `ci/expected/git.txt` |

   The table further down is the older 8 Oct snapshot.

**To verify CI-built packages instead of building**, for example a PR's artifacts:
- Run `crossarm64/test/verify-ci-packages.sh <artifacts-dir>` after `00-host-prereqs.sh`.
- It installs the CI toolchain, prestages the sysroot (`15-prestage-sysroot.sh`), rebuilds only the stage-2 runtime (winsup needs its build tree), and runs winsup.
- It then unpacks the CI userland, builds the test tools the PR set lacks plus openssh's build tree, and stages the root.
- Then run step 5.

**Git for Windows tree** (Tiers 1-5, the native GfW install test): see `test/gfw-native/README.md`.

**Traps:**
- **Never run `makepkg -o` or `--nobuild` on `msys2-runtime-aarch64`.** Its prepare() writes stub `crt0.o` and `libcygwin.a` into the live sysroot, and every binary linked afterwards hangs at startup. To check that the patches apply, use `git apply --check`.
- **Microsoft Defender** can block `cc1.exe` on certain command lines (ML detection `Trojan:Win32/Commando.A!ml`, "spawn: Permission denied"). Add an exclusion for the MSYS2 tree.
- **A crash can exit with status 0** and print nothing. Check outputs, not only exit codes.
- **Don't run other heavy work during a build or test run.** Timeouts then show up as false failures.
- **User name:**
  - `sshd-stress.ps1` logs in as the root's `id -un`.
  - The MinGit ssh scripts use `%USERNAME%`.
  - On a domain or AzureAD account, Cygwin's name can be `DOMAIN+user`, and those sessions fail to authenticate. Use a local account.
- **Rebuilding the stage-2 runtime:** `40-winsup-test.sh` stops the cygserver it started. If it was interrupted, kill `cygserver.exe` before you run `makepkg -C`.

**x86_64 comparison:** a result counts as a port bug only when it fails on aarch64 alone.
- The recorded x86_64 numbers are in the Baseline table below and in `ci/expected/*.txt`.
- To regenerate them, run the same runners on x86_64 MSYS2 the way the Test section describes.

## Build

| step | script | what it does |
|---|---|---|
| 0 | `00-host-prereqs.sh` | x86_64 host packages (incl. `cocom`, `ncurses-devel`, `mingw-w64-cross-mingwarm64-*`) |
| 1 | `10-build-toolchain.sh` | the 9-step bootstrap: w32api-headers, runtime-devel, binutils, default-manifest, w32api-runtime, gcc-stage1, runtime stage 1, gcc, runtime stage 2 |
| 2 | `40-winsup-test.sh` | Cygwin's own testsuite against the freshly built runtime -- run after **every** runtime rebuild |
| 3 | `20-build-userland.sh` | bash chain (libiconv … bash, coreutils, sed, grep, …, hexdump), then ssh chain (zlib, openssl, … heimdal, openssh) |
| 4 | `30-mkroot.sh` | runnable ARM64 root at `/c/upstream-root` |
| 5 | `50-mingit-proto1.sh` | MinGit with our ARM64 POSIX layer swapped in |

Packages and per-recipe logs go to `../aarch64-pkgs` (`PKGDEST` overrides).
Both build scripts take recipe names to (re)build just those.

## Test

Always compare against **x86_64 MSYS2 running the same suite the same way**:
only what fails on aarch64 alone is a port problem.

**bash** -- inside the root (`run-bash-tests.sh` is copied there by hand):

    THIS_SH=/usr/bin/bash sh run-bash-tests.sh /usr/share/bash/tests <results> 300

x86_64: build `recho`/`zecho`/`printenv`/`xcase` from `bash/src/bash-*/support`
with the host gcc next to a copy of `tests/`, run the same command with the
host bash.  A group fails on any output other than its own `warning:` lines.

**OpenSSH regress** -- cross-build the helpers in the openssh build tree
(`make regress-binaries regress-unit-binaries`), copy the tree into the root,
then inside it:

    bash test/run-ssh-tests.sh /build/openssh <results> all 600

x86_64: `makepkg` the same `openssh` recipe natively in a copy of the recipe
directory and run the same runner on that tree.  Rename
`regress/misc/sk-dummy/sk-dummy.so` on both sides (see below).

**MinGit / ssh** -- from Windows PowerShell; they generate their own keys,
sshd config and bare repo in `-Work`, and use the root's sshd as the server:

    test\mingit-ssh-features.ps1   -MinGit <mingit> -Root C:\upstream-root -Work C:\sshtest
    test\ssh-concurrent.ps1        ... -N 30 -Rounds 5
    test\mingit-git-concurrent.ps1 ... -N 20

## Baseline (2026-10-08, runtime with woarm64-0110..0115)

| suite | x86_64 MSYS2 | aarch64 |
|---|---|---|
| winsup | -- | 267 pass / 1 fail (`link04`) |
| bash 5.3.15 (86 groups) | 63 / 23 | 63-64 / 22-23; `run-jobs` flaky (~2/10) |
| OpenSSH unit | 12 / 1 | 12 / 1 |
| OpenSSH t-exec | 80 / 1 / 16 skip | 80 / 1 / 16 skip -- identical test by test |
| MinGit ssh features | -- | 19 / 19 |
| simultaneous ssh sessions | -- | 350 / 350 (10x5, 30x5, 50x3) |
| simultaneous git clone / push | -- | 20 / 20 each, server fsck clean |

Failing on both, i.e. MSYS2 behaviour: OpenSSH `sftp-perm` (`noacl` mount:
`chmod 0400` gives 444) and `unit/utf8` (`utf8_badarg`).

## Things that are not obvious

- **Two runtimes in one process tree crash.** bash's test helpers load
  `msys-2.0.dll` from their own directory, so `usr/share/bash/tests` holds a
  *hardlink* of `usr/bin/msys-2.0.dll`; `30-mkroot.sh` recreates it every run.
  A stale copy makes `recho` segfault in ~28 groups.
- **The root needs `/etc/fstab`** (`none / cygdrive …`), or `/c/…` paths do
  not exist inside it, and a real `HOME` (`/home/<user>`), or OpenSSH's
  `percent` test fails on `%d`.
- **`SHELL` must be the root's bash.** ssh runs ProxyCommand/LocalCommand via
  `$SHELL`; one inherited from Git Bash runs an x86_64 bash with a different `/`.
- **`git://` may be blocked** (port 9418); `00-host-prereqs.sh` rewrites
  sourceware URLs to HTTPS.  Port 22 to github.com may be too: use
  `ssh.github.com:443`.
- **Rebuild with `makepkg -C`.**  Re-applying the woarm64 series over a
  reused `src/` fails on files the previous run's patches created.
- **Known open runtime bug:** an ARM64 DLL that reads a *data* symbol from
  `msys-2.0.dll` without `dllimport` (`environ`, `__stack_chk_guard`) gets the
  import-slot address instead of the value.  It is why OpenSSH's sk-dummy
  provider crashes `ssh-sk-helper`, so the sk tests are disabled.
