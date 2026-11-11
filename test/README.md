# Tests

cocotb tests in [test.py](test.py), run with iverilog.

```sh
make -B
```

RTL runs with `SIM_SHORT`, which gives a second of 1664 clocks and 4 clocks
per UART bit, and with [cells.v](cells.v), which models the delay and ring
cells with real delays. 1664 leaves the same remainder mod 256 as 10 MHz, so
the counter wrap the phase arithmetic has to handle is the real one. The
tests cover:

- the sub-cycle code and self calibration
- lock from 50 clocks a second slow and fast, 5 ppm at 10 MHz, and from 10
- holdover, and relock after it with the pulse in a fast die's blind spot
- a PPS held high through reset not being taken as an edge
- a flipped integrator bit being outvoted
- the cal mode code stream

Gate level runs the real 10 MHz design on the hardened netlist. The PDK cell
models have no delay, so the line reads full. It checks the first pulse,
and reads the netlist to make sure every integrator bit is still three
separate flip-flops on separate nets, so the voting survived synthesis and
layout. Copy the netlist from
`runs/wokwi/final/pnl/tt_um_kfilipekk_gpsdo.pnl.v` to `gate_level_netlist.v`,
then:

```sh
make -B GATES=yes
```

To view the waveform:

```sh
gtkwave tb.fst tb.gtkw
```

## Timing simulation

`TIMING=yes` with `GATES=yes` annotates the hardened netlist with the SDF
from layout, so the real `dlyd` delays drive the TDC:

```sh
make -B GATES=yes TIMING=yes CORNER=nom_tt_025C_3v30
```

`CORNER` picks the SDF under `runs/wokwi/final/sdf`, and `TT_BUILD` points at
another run. Icarus drives a cell output to `x` under `-gspecify` when a
submodule drives it, which is every cell in the PDK library, so
[timing_cells.py](timing_cells.py) drops the `dlyd` wrapper from a copy of
the library and [timing_dly.v](timing_dly.v) puts a buffer with a specify
path in its place. The 44 delay line cells also get flat names, because the
SDF parser in Icarus splits escaped instance names at dots. Every other cell
stays functional, only the delay line carries SDF delays.

The test sends one pps at 10, 30, 50, 70 and 90 ns after a clock edge, after
a 60 clock reset, and takes the code from the first UART line. Codes and the
`dlyd` tap step in the SDF:

| corner | 10 ns | 30 ns | 50 ns | 70 ns | 90 ns | tap     |
| ------ | ----- | ----- | ----- | ----- | ----- | ------- |
| tt     | 24    | 18    | 13    | 8     | 2     | 3.73 ns |
| ff     | 44    | 34    | 24    | 15    | 5     | 2.03 ns |
| ss     | 11    | 9     | 6     | 4     | 1     | 7.76 ns |

The ns per tap from the code against the offset is 3.64, 2.07 and 8.0, within
a tap or two of the SDF. At ff the 44 taps cover 89 ns, less than the 100 ns
clock period, so a pulse more than 89 ns before the clock edge fills the
line: the code reads 44 and smaller offsets cannot be told apart. The RTL
tests cover that case with `make -B TAP_NS=2`, a fast die, where the
calibration falls back to half cycles and the loop still locks with the
pulse in the blind spot.
