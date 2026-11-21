#!/bin/bash
# List every PE file under $1 with its machine type: <machine> <relative path>
cd "$1" || exit 1
find . -type f \( -iname '*.exe' -o -iname '*.dll' -o -iname '*.pyd' -o -iname '*.so' \) -print0 |
while IFS= read -r -d '' f; do
  m=$(od -An -tx1 -j60 -N4 "$f" 2>/dev/null | awk '{print $1$2$3$4}')
  off=$((16#${m:6:2}${m:4:2}${m:2:2}${m:0:2})) 2>/dev/null || { echo "notpe ${f#./}"; continue; }
  sig=$(od -An -tx1 -j$off -N6 "$f" 2>/dev/null | tr -d ' \n')
  case ${sig:0:8}${sig:10:2}${sig:8:2} in
    50450000aa64) echo "arm64 ${f#./}";;
    500450000864) echo "x64 ${f#./}";;
    500450000014c) echo "x86 ${f#./}";;
    *) case "${sig:8:4}" in 64aa) echo "arm64 ${f#./}";; 6486) echo "x64 ${f#./}";; 4c01) echo "x86 ${f#./}";; 64a6) echo "arm64ec ${f#./}";; *) echo "other(${sig}) ${f#./}";; esac;;
  esac
done
