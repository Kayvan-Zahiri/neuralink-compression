#!/usr/bin/env bash
# Verifies losslessness and reports the compression ratio.
set -u
fsize() { if stat -c%s "$1" >/dev/null 2>&1; then stat -c%s "$1"; else stat -f%z "$1"; fi; }
total_raw=0; total_comp=0; n=0; fail=0
for file in data/*.wav; do
  ./encode "$file" /tmp/nl.bw
  ./decode /tmp/nl.bw /tmp/nl.dec.wav
  if ! cmp -s "$file" /tmp/nl.dec.wav; then echo "ERROR: $file did not round-trip"; fail=1; break; fi
  total_raw=$((total_raw + $(fsize "$file")))
  total_comp=$((total_comp + $(fsize /tmp/nl.bw)))
  n=$((n+1))
done
[ $fail -eq 0 ] && echo "All $n recordings losslessly compressed."
echo "Original size (bytes):   $total_raw"
echo "Compressed size (bytes): $total_comp"
echo "Compression ratio: $(echo "scale=3; $total_raw/$total_comp" | bc)"
