#!/bin/bash
# set -e  # stop if any command fails

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