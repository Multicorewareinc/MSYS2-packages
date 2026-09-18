# MinGit prototype #1 — a natively-built POSIX layer for ARM64 Git for Windows

**Date:** 2026-09-19
**Machine:** Snapdragon X Elite, Windows 11 ARM64
**Result:** working prototype at `~/mingit-proto1`, assembled by `crossarm64/50-mingit-proto1.sh`

---

## What this is

Git for Windows already ships `MinGit-*-arm64.zip` with a native ARM64 `git.exe`,
but the POSIX layer it shells out to is still x86-64 and runs under emulation.
Of the 84 files in its `usr/bin`, **82 are x86-64 and none are ARM64**.

This prototype replaces that layer with our `aarch64-pc-cygwin` build, so that
every process in a git operation is native.

---

## Why git needs two runtimes

Git for Windows is two halves that talk by **spawning processes, not by linking**:

| half | toolchain | links against |
|---|---|---|
| `clangarm64/bin/git.exe` | MinGW (Clang) | `KERNEL32`, `ucrtbase`, `libcurl`, `libssl` |
| `usr/bin/*` — sh, coreutils | MSYS2 | `msys-2.0.dll` |

`git.exe` imports `msys-2.0.dll` **zero** times; its only coupling to the other
half is a literal `sh.exe` string. So `git.exe` is not rebuilt here and cannot
be made to "use" our runtime — the work is entirely in `usr/bin`.

Git needs the shell because much of it is still shell scripts: `rebase -i`,
`bisect`, hooks, `git-sh-setup`, credential helpers.

---

## How the prototype is built

`crossarm64/50-mingit-proto1.sh [outdir]`

1. Download and cache the official `MinGit-2.55.0.5-arm64.zip`.
2. **Leave `clangarm64/` untouched.** It is already native and owns git's whole
   transport stack — `libcurl-4`, `libssl-3`, `libcrypto-3`, `git-remote-https`.
   HTTPS clone and push therefore need nothing from `usr/bin`.
3. Swap in every ARM64 binary we build, from `/c/upstream-root/usr/bin`.
4. **Prune the ssh/kerberos cluster** (16 files: `ssh`, `ssh-add`, `ssh-agent`
   and 13 krb5/heimdal/fido2 DLLs).
5. Report the final architecture split.

### Why pruning rather than leaving them

An x86-64 `.exe` **cannot load an ARM64 DLL**. Once `msys-2.0.dll` is ARM64,
any x86-64 binary left in `usr/bin` fails to start — it does not fall back to
emulation. Deleting them gives a clean absence instead of a confusing load
error. SSH transport is out of scope for prototype #1; HTTPS is unaffected.

---

## The one package we had to add: findutils

`find` and `xargs` were the only genuine gap for core git operations.
`findutils/PKGBUILD` was made arch-aware following the same pattern as the
other seven userland recipes:

- `aarch64` added to `arch=`, `pkgrel` bumped
- guarded cross arm in `build()`, pointing `-I`/`-L` at `/usr/aarch64-pc-cygwin/usr`
- `check()` skipped for cross — target binaries cannot run on the x64 host
- `gl_cv_func_strtod_works=yes`, `gl_cv_func_working_mktime=yes` — gnulib probes
  these with `AC_RUN_IFELSE`, which cannot run a target binary when cross-compiling

### A GCC-17 AArch64 bug blocked it

`gl/lib/mountlist.c` hung `cc1` indefinitely — no diagnostic, no progress:

```
-O2                  HUNG   (>120s, killed)
-O0                  HUNG   (>120s, killed)
-no-integrated-cpp   COMPILED
```

Hanging at `-O0` as well rules out the optimizer, so the fault is in the front
end. `-no-integrated-cpp` runs `cpp` as a separate pass instead of interleaving
it with parsing, which avoids it.

**This is the same bug `msys2-runtime-aarch64` already works around** for
`libc/minires-os-if.o`, whose comment reads: *"clean with a SEPARATE cpp pass,
so the bug is in cc1's lex-while-parse path, NOT the optimizer (crashes at -O0
too)"*. Same defect, different file.

It is applied package-wide here rather than per-object, because findutils has
no per-file rule hook like the winsup Makefile does. The cost is one extra
process per translation unit.

**Worth reporting upstream** — with the `disk_file.cc` IPA-inline ICE, that is
two characterised GCC-17 AArch64 bugs. The reproducer is one command.

---

## Result

```
usr/bin : 68 files   (84 original, 16 ssh/kerberos pruned)
  ARM64 : 51
  x86-64: 15
```

### Verified working

```
git clone --depth 1 https://github.com/git-for-windows/build-extra
  -> 52 entries, clean working tree, log reads f3c914b

pre-commit hook:
  HOOK: uname=aarch64  find=/usr/bin/find  xargs=/usr/bin/xargs
```

Also exercised: `init`, `add`, `commit`, `rebase -i`, `bisect`, `stash`,
`status`, `log`. Every process in those operations is native ARM64.

### Still x86-64 (15)

```
chattr  cygwin-console-helper  dash  gencat  getfacl  getopt  gmondump
lsattr  newgrp  profiler  rebase  rebaseall
msys-gcc_s-seh-1.dll  msys-mpfr-6.dll  msys-pcre-1.dll  msys-sqlite3-0.dll
```

None is needed for the operations above — MSYS2 maintenance tools plus four
DLLs. They matter for prototype #2 *(full native)*, alongside restoring SSH.

---

## Reproducing

```bash
# prerequisites: the ARM64 userland staged at /c/upstream-root
#                (crossarm64 build chain, then mkroot.sh)
bash crossarm64/50-mingit-proto1.sh ~/mingit-proto1

~/mingit-proto1/cmd/git.exe --version
~/mingit-proto1/cmd/git.exe clone --depth 1 https://github.com/git-for-windows/build-extra /tmp/t
```

Run it from an **MSYS2** shell, not Git Bash. Git Bash is a separate Cygwin
installation and its `usr/bin` comes first on `PATH`, so MSYS2 binaries load
Git Bash's `msys-2.0.dll` and fail with:

```
cc1.exe: error while loading shared libraries: ?: cannot open shared object file
```

That symptom looks like a broken toolchain and is not one.

---

## Next: prototype #2 (full native)

1. Port the 15 remaining files — mostly `dash`, `pcre`, `sqlite3`, `mpfr` and
   small MSYS2 tools from the winsup tree.
2. Restore SSH: `openssh` + `heimdal` + `libfido2` + `libcbor` + `libxcrypt`,
   about 13 DLLs. The largest item, and the fiddliest to cross-build.
3. Benchmark against the stock emulated MinGit — that is the number that makes
   the case.
