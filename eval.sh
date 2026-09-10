#!/usr/bin/env bash
# Verifies losslessness and reports the compression ratio.
# Exits non-zero if ANY file fails to round-trip, and prints no ratio in that case.
set -u
fsize() { if stat -c%s "$1" >/dev/null 2>&1; then stat -c%s "$1"; else stat -f%z "$1"; fi; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
total_raw=0; total_comp=0; n=0
for file in data/*.wav; do
  if ! ./encode "$file" "$tmp/c.bw"; then echo "ERROR: encode failed on $file" >&2; exit 1; fi
  if ! ./decode "$tmp/c.bw" "$tmp/d.wav"; then echo "ERROR: decode failed on $file" >&2; exit 1; fi
  if ! cmp -s "$file" "$tmp/d.wav"; then echo "ERROR: $file did not round-trip" >&2; exit 1; fi
  total_raw=$((total_raw + $(fsize "$file")))
  total_comp=$((total_comp + $(fsize "$tmp/c.bw")))
  n=$((n+1))
done
if [ "$n" -eq 0 ]; then echo "ERROR: no files matched data/*.wav" >&2; exit 1; fi
echo "All $n recordings losslessly compressed."
echo "Original size (bytes):   $total_raw"
echo "Compressed size (bytes): $total_comp"
if command -v bc >/dev/null 2>&1; then
  echo "Compression ratio: $(echo "scale=3; $total_raw/$total_comp" | bc)"
else
  echo "Compression ratio: $(awk -v a="$total_raw" -v b="$total_comp" 'BEGIN{printf "%.3f", a/b}')"
fi
