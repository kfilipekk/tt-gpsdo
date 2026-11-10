# Formal

SymbiYosys proofs, run from this directory with the oss-cad-suite tools:

```sh
sby -f tdc.sby
sby -f loop.sby
```

The checkers are instantiated inside `tdc` and `loop` under `ifdef FORMAL`,
so synthesis never sees them. `cells.v` stands in for the gf180 cells, each
`dlyd` is a free bit every clock, so the TDC sees any thermometer code,
bubbles included.

- **tdc.sby prove** (k-induction): start and hit never coincide, every start
  gives exactly one hit 43 clocks later with no new start in between, and the
  code never goes over 44. A few helper assertions tie the checker's count to
  the TDC's own so it closes by induction. A cover run shows both ends are
  reachable.
- **loop.sby prove** (k-induction): the vote is the bitwise majority, with two
  copies equal any flip in the third leaves the voted word and the DAC word
  alone, and the next clock rewrites it. The next integrator value is the
  saturated sum, and the DAC word is the gain shifted integrator clamped to
  the rails, not wrapped.
- **loop.sby fault** (k-induction): three real `tmr_reg` copies, one built from
  a flip-flop with a free fault input. The flip never reaches the vote and is
  gone a clock later.

Each proof was checked against deliberate bugs, a tap short in the TDC count,
a broken voter, no saturation, a wrong clamp and a copy that is never
reloaded, and fails on every one. The fault model is an upset in one copy,
not a stuck or metastable cell, and the loop proofs use the default widths.
