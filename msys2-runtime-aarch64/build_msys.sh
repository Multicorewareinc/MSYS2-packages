# #!/bin/bash
set -e  # stop if any command fails

ROOT_DIR=$(pwd)

echo "===== STEP 1: Building NEWLIB ====="
cd "$ROOT_DIR/newlib_pkgbuild"


rm -rf src pkg
makepkg -o


cd src/msys2-runtime/newlib

find . -name "Makefile.in" -delete
find . -name "Makefile" -delete

autoreconf -fvi

cd ../../..
cp -rf  src/msys2-runtime/newlib/libc/include/getopt.h .
cp -rf src/msys2-runtime/winsup/cygwin/include/* src/msys2-runtime/newlib/libc/include/ 
cp -rf ./getopt.h src/msys2-runtime/newlib/libc/include/
makepkg -e

echo "===== NEWLIB BUILD DONE ====="


cat > /usr/lib/gcc/aarch64-pc-msys/15/include/c++/bits/c++config.h << 'CXXCONFIG'
#ifndef _GLIBCXX_CXX_CONFIG_H
#define _GLIBCXX_CXX_CONFIG_H 1


#define __GLIBCXX__ 1


// Exception / ABI macros
#define _GLIBCXX_NOTHROW noexcept
#define _GLIBCXX_USE_NOEXCEPT noexcept
#define _GLIBCXX_THROW(...) noexcept
#define _GLIBCXX_TXN_SAFE
#define _GLIBCXX_TXN_SAFE_DYN
#define _GLIBCXX_NODISCARD [[nodiscard]]


// Visibility
#define _GLIBCXX_VISIBILITY(V) __attribute__((__visibility__(#V)))
#define _GLIBCXX_BEGIN_NAMESPACE_VERSION
#define _GLIBCXX_END_NAMESPACE_VERSION


// Feature flags
#define _GLIBCXX_USE_C99_STDLIB 1
#define _GLIBCXX_USE_C99_MATH 1
#define _GLIBCXX_USE_WCHAR_T 1
#define _GLIBCXX_HAS_GTHREADS 1



namespace std {
typedef __SIZE_TYPE__ size_t;
typedef __PTRDIFF_TYPE__ ptrdiff_t;
}
#endif
CXXCONFIG


echo "===== STEP 2: Building WINSUP (msys2-runtime) ====="
cd "$ROOT_DIR"

# Clean + build
cp -rf newlib_pkgbuild/msys2-runtime/ .
cp -rf newlib_pkgbuild/pkg/ .
cp -rf newlib_pkgbuild/src/ .

rm -rf src/runtime-build
cp -rf newlib_pkgbuild/src/runtime-build/aarch64-pc-msys/newlib  src/.

makepkg -e

echo "===== ALL BUILDS COMPLETED SUCCESSFULLY ====="