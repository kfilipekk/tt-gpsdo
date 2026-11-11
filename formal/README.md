# Formal

SymbiYosys proofs, run from this directory with the oss-cad-suite tools:

```sh
sby -f tdc.sby
sby -f loop.sby
sby -f top.sby
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

- **top.sby** (k-induction, the real 10 MHz second): the counter stays
  inside a second, the top half flag matches the count, the phase is the low
  byte of the offset from the nearest wrap and moves by exactly one a clock
  across the wrap, a jam puts the counter at 8, holdover counts at most two
  empty seconds, and the `DD` telemetry only changes when a pulse comes in.
  The ring is a free stand-in here (`ring_f.v`), a closed inverter loop has
  no formal meaning.

Each proof was checked against deliberate bugs, a tap short in the TDC count,
a broken voter, no saturation, a wrong clamp, a copy that is never reloaded,
and for the top level the two real bugs found in review (the phase aliasing
at the wrap and the stuck `DD`), a flag set a clock early, a wrong jam count
and a holdover that overcounts. None of them proves. The fault model is an
upset in one copy, not a stuck or metastable cell, and the loop proofs use
the default widths.
