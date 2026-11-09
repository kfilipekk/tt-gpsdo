# Formal

SymbiYosys proofs, run from this directory with the oss-cad-suite tools:

```sh
sby -f tdc.sby
sby -f loop.sby
```

`cells.v` stands in for the gf180 cells. Each `dlyd` is a free bit every
clock, so the TDC sees any thermometer code, bubbles included. Nothing in
`src/` changes.

- **tdc.sby** (bounded, 120 clocks): start and hit never coincide, every
  start gives exactly one hit 43 clocks later with no new start in between,
  and the code never goes over 44. A cover run shows both are reachable.
- **loop.sby prove** (k-induction): the vote is the bitwise majority. With
  two copies equal, any flip in the third leaves the voted integrator and the
  DAC word alone, and the next clock rewrites it. The integrator saturates
  instead of wrapping, and the DAC stays in 0 to 65535.
- **loop.sby fault** (k-induction): three real `tmr_reg` copies, one built
  from a flip-flop with a free fault input. The flip never reaches the vote
  and is gone a clock later.

The fault model is an upset in one copy, not a stuck or metastable cell, and
the loop proofs use the default widths.
