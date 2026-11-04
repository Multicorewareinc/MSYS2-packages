# aarch64-pc-cygwin: toolchain, userland, test root, MinGit

Run everything from an **MSYS2 shell** (`MSYSTEM=MSYS`), not Git Bash: Git
Bash has its own root and its own `SHELL`, both of which leak into the tests.

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
