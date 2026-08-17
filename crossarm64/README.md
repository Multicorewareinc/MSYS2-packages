# Building the aarch64-pc-msys package chain

Rebuilds bash, git and everything between them for `aarch64-pc-msys`, from
MSYS2-packages' own sources and patches, as installable `cross-msysarm64-*`
packages.

Run these from an **MSYS2 shell** (`msys2_shell.cmd -msys`), not Git Bash - Git
Bash has its own root and cannot see `/usr/aarch64-pc-msys`.

## Prerequisite: the cross toolchain

These scripts do **not** build the toolchain. Install it first:

    cross-msysarm64-binutils   cross-msysarm64-gcc
    cross-msysarm64-runtime    cross-msysarm64-runtime-devel
    cross-msysarm64-newlib     cross-msysarm64-w32api-headers
    cross-msysarm64-w32api-runtime

Stage 0 checks for all seven and stops with a list if any are missing.

## Running it

    cd crossarm64
    ./build-all.sh                 # or ./build-all.sh /c/my-root

Roughly two hours on a warm machine, most of it in openssl, pacman and git.
Each package logs to `${PKGDEST}/logs/<name>.log`; on failure the last 25 lines
are printed and the log path is given.

Stages can also be run individually:

| stage | script | what it does |
|---|---|---|
| 0 | `00-prereqs.sh` | installs host build tools, verifies the toolchain, clears known sysroot problems |
| 1 | `10-packages.sh` | builds and installs the 23 packages in dependency order |
| 2 | `20-testroot.sh` | assembles a runnable Windows-ARM64 root |
| 3 | `30-test.sh` | runs every executable, then 30-odd functional checks |

`10-packages.sh` accepts package names to build just those:

    ./10-packages.sh cross-msysarm64-curl cross-msysarm64-git

Already-installed packages are skipped; `SKIP_BUILT=0` forces a rebuild.
`PKGDEST` controls where packages land (default `../aarch64-pkgs`).

## Things that are not obvious

**Why a separate root is needed to test.** An ARM64 process takes its idea of
`/` from where `msys-2.0.dll` sits. Run from the staging sysroot inside the
x86_64 installation, it resolves `/` to the *host* root, so the only `/bin/sh`
it finds is x86_64 - and msys's fork emulation cannot clone an ARM64 parent's
cygheap into an x86_64 child. Anything that spawns a helper (`git clone`, a
shell alias) dies with `child_copy: cygheap read copy failed`. In a root whose
`usr/bin` holds the ARM64 `msys-2.0.dll`, `/bin` maps to `/usr/bin` and it all
works. This is not a bug in the packages.

**Shadowing headers.** `cross-msysarm64-runtime-devel` ships newlib's
`iconv.h`, `unctrl.h` and `stdatomic.h` at several paths under the sysroot,
where they take precedence over the real packages. Left alone, everything built
afterwards silently links the runtime's iconv instead of libiconv, and curl
fails to compile outright. Stage 0 removes them - see MSYS2-packages#26; when
that is fixed this becomes a no-op.

**Unowned files in the sysroot.** Anything there that no package owns can shadow
a packaged file. A stale `msys-z.dll` left by an older hand build once
overwrote the packaged zlib in a test root, and bsdtar quietly started reporting
the older version. Stage 0 lists any it finds; stage 2 copies only
`msys-2.0.dll` out of `${SYSROOT}/bin` for the same reason.

**gnupg.org returns 403** to curl from some networks, and libgpg-error,
libassuan and gpgme take their sources from there. Stage 1 pre-fetches them from
a mirror; the checksums in the PKGBUILDs are what verify them either way. Set
`GNUPG_MIRROR` to use a different one.

**`--skippgpcheck`** is passed because the upstream signing keys are not
imported on a fresh machine. The `sha256sums` in each PKGBUILD still apply.

## What does not work yet

`socket()` segfaults in the AArch64 runtime
([msys2-runtime#5](https://github.com/Multicorewareinc/msys2-runtime/issues/5)),
so nothing can use the network: no `git clone https://`, no `pacman -Sy`, no
curl transfer beyond `file://`. Everything local works. Stage 3 does not test
network operations for this reason.

There is also no `ca-certificates` package for the target yet, so HTTPS will not
verify certificates even once sockets are fixed
([#35](https://github.com/Multicorewareinc/MSYS2-packages/issues/35)).
