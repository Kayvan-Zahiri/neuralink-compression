# brainwire — lossless codec for N1 electrode recordings

**2.791x lossless** across all 743 files (146,800,526 -> 52,588,672 bytes), verified
byte-exact by `eval.sh`. Single-core throughput 12.7M samples/s encode, 13.2M decode.
Model state is 49 KB total.

```
make && ./eval.sh
```

## Result in context

Measured per file, which is what the challenge scores and what an implant can
actually do (no cross-recording dictionary):

| codec | ratio | encode | model state |
|---|---|---|---|
| zip | 2.279x | — | — |
| gzip -9 | 2.286x | — | — |
| xz -9e | 2.756x | 2.78M samples/s | 64 MiB dictionary |
| **brainwire** | **2.794x** | **12.7M samples/s** | **49 KB** |

So it beats `xz -9e` on ratio while encoding 4.6x faster in roughly 1/1300th the
memory. Against the posted `zip` baseline it is a 22.5% improvement.

(The 2.791 headline is over all 743 files; the table is the 200-file subset used
for the head-to-head, hence 2.794.)

## What the data actually looks like

Measured over **all 743 files**, 73,383,917 samples, 19,531 Hz mono, 16-bit container:

1. **The samples sit on a 64-step lattice.** 67.8% of first differences are exact
   multiples of 64, and 99.27% are `64k`, `64k+1` or `64k-1`. Per file, `round(x/64)`
   takes 52 to 1009 distinct values, mean 186. That is the 10-bit ADC showing through
   a 16-bit file.
2. **Because of the lattice, a = 1.0 is the optimal first-order coefficient.** A grid
   search over one- and two-tap coefficients put plain first difference first at
   5.539 bits/sample. The cheapest alternative coefficient costs +2.4 bits and the
   worst +4.6. Fractional and LPC predictors break lattice alignment, which is why
   the usual FLAC/Shorten playbook underperforms here.
3. **The residual is near-memoryless in magnitude.** Conditioning first-difference
   entropy on one, two or three previous magnitude buckets moves it from 5.540 to
   5.529 bits, so classical activity context modeling buys essentially nothing.

## Design

First difference, then split each residual on the lattice:

```
d = x[n] - x[n-1]
m = round(d / 64)      # which comb tooth
r = d - 64*m           # jitter, |r| <= 32, almost always in {-1,0,1}
```

`m` and `r` are coded with an adaptive binary range coder: zigzag, adaptive unary
bit-length, then mantissa bits with a context per (length, bit position). `m`'s
model is selected by the magnitude classes of the two previous teeth (25 contexts)
and `r`'s by the current `|m|` crossed with the previous jitter (35 contexts).

Coding `d` directly through the same binarizer gives only 1.72x, because the comb
structure puts real entropy in bits a length-plus-mantissa code has to spend in
full. Splitting the tooth from the jitter is what takes it to 2.75x. Rice coding
does worse still (1.48x) since the residual distribution is a comb rather than
geometric.

## Where the remaining headroom is, and is not

Measured conditional entropies, using the exact context definitions the codec ships
with, put this decomposition's floor at **2.868x**: over 200 files and 19.7M samples,
`H(m | prev, prev2)` is 4.584 bits and `H(r | m, prev r)` is 0.995, for 5.578
bits/sample. The coder reaches 2.791x against that, about **97%** of its own model's
ceiling. The remaining headroom is in the model class, not in tuning.

Things that were tried and did not help, with numbers, so nobody repeats them:

- **Coding `q = round(x/64)` and the offset separately** rather than differencing
  first: 2.25x. The sample offset costs 2.52 bits where the *difference* jitter
  costs 1.23.
- **Lattice phase as a context.** The decoder knows `x[n-1] mod 64` for free, but on
  a common 20-file sample `H(r | phase, m)` measured 0.971 against 0.969 for the
  context already in use, so it is a wash.
- **Higher-order predictors on the decimated signal**: order 2 costs 5.21 bits
  against 4.59 for order 1, and it gets worse from there.
- **Model priming from corpus statistics.** Encoding the same file four times in a
  row shows the cold-start penalty is only 1.0%, so there is nothing to recover.

Getting to the ~3.5x the best published attempts reach needs context mixing, which
means several models, logistic mixing and SSE. That buys ratio at 10-100x the time
and memory, which is the wrong trade for something meant to run at under 10 mW.

## On the 200x target

The brief asks for >200x. That is not reachable losslessly on this data and no
amount of engineering changes it: first-difference entropy is ~5.5 bits/sample, so
the information-theoretic ceiling for any lossless coder in this family is about
2.9x, and the best published attempts at this challenge sit near 3.5x. 200x means
roughly 0.08 bits/sample, which is below the entropy of the recording noise itself.

Getting to 200x requires throwing data away — spike detection and timestamping, or
band-limited lossy coding — which is a product decision about what the downstream
decoder needs, not a compression problem. What is here is the lossless floor,
measured, with the cost structure an implant would care about.

## Correctness and limits

`./test.sh` covers the cases an audit of this codec turned up. Three real bugs were
found and fixed, and the tests exist so they stay fixed:

- **An odd-sized data chunk silently lost its last byte**, and the decoder wrote
  uninitialised heap in its place, with exit status 0. Whole samples are now coded
  and any trailing odd byte rides along in the verbatim tail. No file in the
  challenge corpus has an odd data chunk, so the 2.791x result was never affected,
  but the unqualified "lossless" claim was wrong until this was fixed.
- **A hostile chunk size field spun `find_data_chunk` forever.** `8 + sz + (sz&1)`
  was evaluated in 32-bit, so `sz = 0xFFFFFFF8` advanced the cursor by zero. The
  walk is 64-bit and bounds-checked now.
- **`eval.sh` exited 0 after a round-trip failure** and still printed a ratio, so a
  broken build looked like a passing one. It now exits non-zero and prints nothing.

Also fixed after a second audit pass:

- **The decoder's size bound was dead code.** It tested `dl > 64 GiB`, but `dl` is a
  `uint32_t` and can never reach that, so a 16-byte crafted header still committed the
  process to a ~400 MB allocation and a multi-billion-iteration loop. `dl` is now bounded
  against the bitstream actually present in the file.
- **A truncated `.bw` decoded to a full-size wrong WAV and exited 0**, because `fgetc`
  returning EOF was folded into the bit decoder as data. EOF is now counted and the
  decode aborts.
- **The model arrays were leaked on every encode and decode** (about 50 KB per run).
- Signed overflow in the decoder's sample accumulator on corrupt input is now defined
  unsigned wraparound.

Every allocation is checked and short writes are detected rather than silently
truncating output.

Still true and worth stating plainly: the `.bw` format carries **no checksum**, so a
bit-flipped stream that survives the size bounds will decode to wrong samples without
complaint. For a submission measured by `eval.sh` that is not a defect, but it is not
an archival format.

**Endianness.** Samples are read native-endian and the `.bw` header stores its
length fields as native-endian `uint32`. That is fine on any little-endian host,
which is what WAV itself assumes. On a big-endian host the codec stays lossless but
the ratio collapses, since the first difference would be taken over byte-swapped
samples, and `.bw` files do not move between hosts of differing endianness.

## Files

- `brainwire.c` — codec, ~190 lines, no dependencies beyond libc
- `encode` / `decode` — the interface `eval.sh` expects
- `eval.sh` — losslessness check and ratio, portable to Linux and macOS
- `test.sh` — regression tests for the audit findings
