# Native Git for Windows install test (aarch64)

These scripts check that a Git for Windows ARM64 release works when its
MSYS side (usr/) is replaced with our aarch64-pc-cygwin builds. They are
the scripts behind the 2.55.0.windows.5 results from 21 November 2026.

## Install test

The working folder is fixed at `C:\gfw-native`. Unpack
`Git-<ver>-arm64.tar.bz2` twice: once into `official/` (left as it is) and
once into `native/` (gets our files). Then run these in order from the
MSYS2 shell:

| Script | What it does |
|---|---|
| `pescan.sh <dir>` | Lists every PE file with its machine type (arm64/x64/x86/arm64ec). Run it on `official/` to get `scan-official.txt`. |
| `swap.sh` | Replaces each x64 file under `native/usr` with the ARM64 file at the same path in the sysroot. |
| `swap2.sh` | Copies in the runtime utilities from the sysroot's `bin/` (checking the machine type, because that folder also holds the x86 cross binutils), `getprocaddrarm64.exe`, and the new runtime DLLs. Removes `lesskey.exe` (dropped in less 710). |
| `overlay.sh` | For each package in `etc/package-versions.txt`, copies our whole aarch64 package over the files the official tree has, so each Perl `.pm` file matches its XS `.dll`. |
| `deps.sh` | Rescans and lists `msys-*`/`cyg*` imports that don't resolve inside `usr/bin`. |
| `smoke.sh` | 29 end-to-end checks. Run it from the tree's own `git-bash.exe` login shell. |

After that, run the Git test suite with `../run-git-tests-mingit.ps1`, using
`GIT_TEST_INSTALLED` pointed at each tree and a git build of the same version.
Run it on `official/` too, so that only differences between the two trees count.

The DLLs that `swap2.sh` doesn't cover were swapped by hand for 2.55:

- added `msys-pcre2-posix-3.dll`;
- removed `msys-cbor-0.11.dll` and `msys-gcc_s-seh-1.dll`, because our builds
  import `msys-cbor-0.14.dll` and `cyggcc_s-seh-1.dll` (issue 54).

## Component tests (run natively on ARM64)

| Script | Covers |
|---|---|
| `test-t4.sh`, `test-perl.sh`, `test-perl-modules.sh`, `test-send-email.sh` | Tier 4: perl, the XS modules, git send-email |
| `run-perl-core-tests.sh` | The perl core test suite from the build tree |
| `test-t5.sh`, `test-svn.sh` | Tier 5: file/libmagic, svn/svnadmin/svnserve, SVN:: Perl bindings, git svn clone/dcommit/rebase |

Paths such as `/c/msys64/home/<user>/gfw-tests` (override: `GFW_TESTS`, `REPO`, `PKGDEST`) and `C:\gfw-native` are the ones used
on the build machine. Change them to match yours.
