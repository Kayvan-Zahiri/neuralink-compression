# brainwire — lossless codec for N1 electrode recordings

**2.750x lossless** across all 743 files (146,800,526 -> 53,364,086 bytes), verified
byte-exact by `eval.sh`. Single-core throughput 13.4M samples/s encode, 12.3M decode.
Model state is 6.7 KB total.

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
| **brainwire** | **2.753x** | **13.4M samples/s** | **6.7 KB** |

So it ties `xz -9e` on ratio while encoding 4.8x faster in about 1/10,000th the
memory. Against the posted `zip` baseline of 2.2 it is a 21% improvement.

(The 2.750 headline is over all 743 files; the table is the 200-file subset used
for the head-to-head, hence 2.753.)

## What the data actually looks like

Measured over 743 files, ~73M samples, 19,531 Hz mono, 16-bit container:

1. **The samples sit on a 64-step lattice.** 72.8% of first differences are exact
   multiples of 64, and 99.98% are `64k`, `64k+1` or `64k-1`. `round(x/64)` takes
   only 256 distinct values. That is the 10-bit ADC showing through a 16-bit file.
2. **Because of the lattice, a = 1.0 is the optimal first-order coefficient.** A
   grid search over fractional one- and two-tap predictors put plain first
   difference first at 5.50 bits/sample; the next best fractional coefficient cost
   7.89 bits. Fractional and LPC predictors break lattice alignment and *lose*
   3 to 5 bits per sample. This is why the usual FLAC/Shorten playbook underperforms
   here.
3. **The residual is near-memoryless in magnitude.** Conditioning first-difference
   entropy on one, two or three previous magnitude buckets moved it from 5.504 to
   5.482 bits, so classical activity context modeling buys essentially nothing.

## Design

First difference, then split each residual on the lattice:

```
d = x[n] - x[n-1]
m = round(d / 64)      # which comb tooth
r = d - 64*m           # jitter, |r| <= 32, almost always in {-1,0,1}
```

`m` and `r` are coded with an adaptive binary range coder: zigzag, adaptive unary
bit-length, then mantissa bits with a context per (length, bit position). `m`'s
model is selected by the previous sample's magnitude class and `r`'s by the current
`|m|`, four classes each.

Coding `d` directly through the same binarizer gives only 1.72x, because the comb
structure puts real entropy in bits a length-plus-mantissa code has to spend in
full. Splitting the tooth from the jitter is what takes it to 2.75x. Rice coding
does worse still (1.48x) since the residual distribution is a comb rather than
geometric.

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

## Files

- `brainwire.c` — codec, ~180 lines, no dependencies beyond libc
- `encode` / `decode` — the interface `eval.sh` expects
- `eval.sh` — losslessness check and ratio, portable to Linux and macOS
