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
model is selected by the magnitude classes of the two previous teeth (25 contexts)
and `r`'s by the current `|m|` crossed with the previous jitter (35 contexts).

Coding `d` directly through the same binarizer gives only 1.72x, because the comb
structure puts real entropy in bits a length-plus-mantissa code has to spend in
full. Splitting the tooth from the jitter is what takes it to 2.75x. Rice coding
does worse still (1.48x) since the residual distribution is a comb rather than
geometric.

## Where the remaining headroom is, and is not

Measured conditional entropies over the corpus put this decomposition's floor at
about **2.98x**: `H(m | prev, prev2)` is 4.562 bits and `H(r | m, prev r)` is 0.808.
The coder reaches 2.79 against that, so roughly 94% of its own model's ceiling.

Things that were tried and did not help, with numbers, so nobody repeats them:

- **Coding `q = round(x/64)` and the offset separately** rather than differencing
  first: 2.25x. The sample offset costs 2.52 bits where the *difference* jitter
  costs 1.23.
- **Lattice phase as a context.** The decoder knows `x[n-1] mod 64` for free, but
  `H(r | phase, m)` is 0.971 against 0.969 for the context already in use.
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

## Files

- `brainwire.c` — codec, ~180 lines, no dependencies beyond libc
- `encode` / `decode` — the interface `eval.sh` expects
- `eval.sh` — losslessness check and ratio, portable to Linux and macOS
