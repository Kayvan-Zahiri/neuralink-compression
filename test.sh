#!/usr/bin/env bash
# Regression tests for bugs found in audit. Exits non-zero on any failure.
set -u
fail=0
t() { if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1 (got $2, want $3)"; fail=1; fi; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

python3 - "$tmp" <<'PY'
import struct,sys,os
d=sys.argv[1]
def wav(path, data):
    fmt=struct.pack('<HHIIHH',1,1,19531,39062,2,16)
    body=b'WAVE'+b'fmt '+struct.pack('<I',16)+fmt+b'data'+struct.pack('<I',len(data))+data
    open(path,'wb').write(b'RIFF'+struct.pack('<I',len(body))+body)
wav(f'{d}/odd.wav', b'\x41')                       # odd data chunk: 1 byte
wav(f'{d}/empty.wav', b'')                         # empty data chunk
wav(f'{d}/one.wav', struct.pack('<h',-32768))      # single sample
wav(f'{d}/ext.wav', struct.pack('<hh',-32768,32767))
# hostile chunk size that used to spin find_data_chunk forever
body=b'WAVE'+b'junk'+struct.pack('<I',0xFFFFFFF8)+b'\x00'*8+b'data'+struct.pack('<I',2)+b'\x01\x02'
open(f'{d}/hang.wav','wb').write(b'RIFF'+struct.pack('<I',len(body))+body)
PY

for f in odd empty one ext; do
  ./brainwire "$tmp/$f.wav" "$tmp/$f.bw" >/dev/null 2>&1
  ./brainwire "$tmp/$f.bw" "$tmp/$f.dec.wav" >/dev/null 2>&1
  if cmp -s "$tmp/$f.wav" "$tmp/$f.dec.wav"; then t "round-trip $f" ok ok; else t "round-trip $f" bad ok; fi
done

timeout 5 ./brainwire "$tmp/hang.wav" "$tmp/hang.bw" >/dev/null 2>&1
t "hostile chunk size terminates" "$([ $? -eq 124 ] && echo hang || echo ok)" ok

printf 'BW1\0\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff' > "$tmp/huge.bw"
timeout 10 ./brainwire "$tmp/huge.bw" "$tmp/huge.out" >/dev/null 2>&1
t "bogus length fields rejected" "$([ $? -ne 0 ] && echo ok || echo accepted)" ok

printf '' > "$tmp/z.bw"; ./brainwire "$tmp/z.bw" "$tmp/z.out" >/dev/null 2>&1
t "empty .bw rejected" "$([ $? -ne 0 ] && echo ok || echo accepted)" ok

[ $fail -eq 0 ] && echo "all regression tests passed" || echo "REGRESSIONS PRESENT"
exit $fail
