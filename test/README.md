# Tests

cocotb tests in [test.py](test.py), run with iverilog.

```sh
make -B
```

RTL runs with `SIM_SHORT`, which gives a second of 2000 clocks and 4 clocks
per UART bit, and with [cells.v](cells.v), which models the delay and ring
cells with real delays. The tests cover:

- the sub-cycle code and self calibration
- lock of a 250 ppm slow oscillator
- holdover
- a flipped integrator bit being outvoted
- the cal mode code stream

Gate level runs the real 10 MHz design on the hardened netlist. The PDK cell
models have no delay, so the line reads full, and only the first pulse is
checked there. Copy the netlist from
`runs/wokwi/final/pnl/tt_um_kfilipekk_gpsdo.pnl.v` to `gate_level_netlist.v`,
then:

```sh
make -B GATES=yes
```

To view the waveform:

```sh
gtkwave tb.fst tb.gtkw
```
