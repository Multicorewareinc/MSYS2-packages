#!/usr/bin/env bash
# Native ARM64 tests for zstd, lz4, gzip, tar (run with the ARM64 bash from the sysroot).
# usage: test-t4.sh <zstd|lz4|gzip|tar>
D=/c/msys64/home/HCKTest/gfw-tests/t4
cd "$D"; rm -rf out-$1; mkdir out-$1; O=out-$1
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "PASS: $*"; }
bad() { fail=$((fail+1)); echo "FAIL: $*"; }
arm64() { local f=$(command -v $1) off=$(od -An -tu4 -j60 -N4 "$(command -v $1)"); [ "$(od -An -tx1 -j$((off+4)) -N2 "$f" | tr -d ' ')" = "64aa" ]; }
arm64 $1 && ok "$1.exe is an ARM64 binary" || bad "$1.exe is not ARM64"
case $1 in
zstd)
  echo "version: $(zstd --version)"
  zstd -dc text.x64.zst | cmp -s - text.txt && ok "decompress x86_64 .zst" || bad "decompress x86_64 .zst"
  for l in -1 -9 -19 --ultra\ -22; do zstd -q $l -c random.bin > $O/r.zst && zstd -dc $O/r.zst | cmp -s - random.bin && ok "round trip $l" || bad "round trip $l"; done
  zstd -q -T4 -c text.txt > $O/t.zst && zstd -dc $O/t.zst | cmp -s - text.txt && ok "round trip -T4" || bad "round trip -T4"
  zstd -q --long=27 -c random.bin > $O/l.zst && zstd -dc --long=27 $O/l.zst | cmp -s - random.bin && ok "long mode" || bad "long mode"
  zstd -q -c text.txt > $O/a.zst && unzstd -c $O/a.zst | cmp -s - text.txt && zstdcat $O/a.zst | cmp -s - text.txt && ok "unzstd / zstdcat" || bad "unzstd / zstdcat"
  zstd -q -t $O/a.zst && ok "integrity test (good)" || bad "integrity test (good)"
  cp $O/a.zst $O/c.zst; printf '\xff\xff\xff\xff' | dd of=$O/c.zst bs=1 seek=100 conv=notrunc 2>/dev/null
  zstd -q -t $O/c.zst 2>/dev/null && bad "corruption NOT detected" || ok "corruption detected"
  zstd -q -9 -c text.txt > $O/text.arm64.zst ;;
lz4)
  echo "version: $(lz4 --version 2>&1 | head -1)"
  lz4 -dc text.x64.lz4 | cmp -s - text.txt && ok "decompress x86_64 .lz4" || bad "decompress x86_64 .lz4"
  for l in -1 -9 -12; do lz4 -q $l -c random.bin > $O/r.lz4 && lz4 -dc $O/r.lz4 | cmp -s - random.bin && ok "round trip $l" || bad "round trip $l"; done
  lz4 -q -c text.txt > $O/a.lz4 && unlz4 -c $O/a.lz4 | cmp -s - text.txt && lz4cat $O/a.lz4 | cmp -s - text.txt && ok "unlz4 / lz4cat" || bad "unlz4 / lz4cat"
  lz4 -q -t $O/a.lz4 && ok "integrity test (good)" || bad "integrity test (good)"
  lz4 -q --content-size -c text.txt > $O/cs.lz4 && cp $O/cs.lz4 $O/c.lz4; printf '\xff\xff\xff\xff' | dd of=$O/c.lz4 bs=1 seek=60 conv=notrunc 2>/dev/null
  lz4 -q -t $O/c.lz4 2>/dev/null && bad "corruption NOT detected" || ok "corruption detected"
  lz4 -q -9 -c text.txt > $O/text.arm64.lz4 ;;
gzip)
  echo "version: $(gzip --version | head -1)"
  gzip -dc text.x64.gz | cmp -s - text.txt && ok "decompress x86_64 .gz" || bad "decompress x86_64 .gz"
  for l in -1 -6 -9; do gzip $l -c random.bin > $O/r.gz && gzip -dc $O/r.gz | cmp -s - random.bin && ok "round trip $l" || bad "round trip $l"; done
  cp text.txt $O/k.txt && gzip $O/k.txt && gunzip $O/k.txt.gz && cmp -s $O/k.txt text.txt && ok "gzip / gunzip in place" || bad "gzip / gunzip in place"
  gzip -c text.txt > $O/a.gz && zcat $O/a.gz | cmp -s - text.txt && ok "zcat" || bad "zcat"
  gzip -t $O/a.gz && ok "integrity test (good)" || bad "integrity test (good)"
  cp $O/a.gz $O/c.gz; printf '\xff\xff\xff\xff' | dd of=$O/c.gz bs=1 seek=200 conv=notrunc 2>/dev/null
  gzip -t $O/c.gz 2>/dev/null && bad "corruption NOT detected" || ok "corruption detected"
  gzip -9 -c text.txt > $O/text.arm64.gz ;;
tar)
  echo "version: $(tar --version | head -1)"
  mkdir $O/x1 && tar -xzf tree.x64.tar.gz -C $O/x1 && diff -r tree $O/x1/tree >/dev/null && ok "extract x86_64 .tar.gz (gzip)" || bad "extract x86_64 .tar.gz"
  mkdir $O/x2 && tar -xJf tree.x64.tar.xz -C $O/x2 && diff -r tree $O/x2/tree >/dev/null && ok "extract x86_64 .tar.xz (xz)" || bad "extract x86_64 .tar.xz"
  for z in -z -j -J --zstd "-I lz4"; do
    n=${z//[- ]/}; f=$O/t-$n.tar
    mkdir -p $O/y-$n && tar -c $z -f $f tree && tar -x $z -f $f -C $O/y-$n && diff -r tree $O/y-$n/tree >/dev/null && ok "create+extract with $z" || bad "create+extract $z"
  done
  tar -tf tree.x64.tar.gz | sort | head -20 > $O/list && grep -q 'tree/sub/deep/c.txt' $O/list && ok "list archive (-t)" || bad "list archive"
  [ -L $O/x1/tree/link.txt ] || [ -f $O/x1/tree/link.txt ] && ok "symlink entry restored" || bad "symlink entry"
  tar -czf $O/tree.arm64.tar.gz tree ;;
esac
echo "== $1: $pass passed, $fail failed"
