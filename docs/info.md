## How it works

This is the controller half of a GPS disciplined oscillator. The chip clock
is a 10 MHz oscillator with a tuning pin (an OCXO or VCTCXO), and a GPS
receiver gives a pulse every second that is good to a few tens of ns. The
chip measures where each pulse lands against its own clock and tunes the
oscillator until the two agree, so over hours the oscillator ends up as
accurate as GPS. If GPS drops out it keeps counting on its own.

### Timing the pulse

A counter wraps every 10,000,000 clocks. That gives the whole cycles between
pulses, and it is also the PPS output. 100 ns is too coarse to steer a good
oscillator, so the pulse also goes down a chain of 44 `dlyd` delay cells,
about 3.4 ns each. Every clock samples all 44 taps, and the first sample with
the edge in it says how long before that clock edge the pulse came in. The
taps are shifted out and counted, so a bubble in the code costs one tap
rather than a wrong answer.

### Calibration

Delay cells change with process, voltage and temperature, so half way through
every second the chip sends a one clock pulse of its own down the same line.
However many taps it covers by the next edge is one clock period, about 29
taps, and that scales everything else. No trimming per chip.

### Loop

Each second gives the error in taps: whole cycles times taps per cycle, plus
the change in fine code. An integrator adds it up and sets a 16 bit word. A
proportional term only added counter noise in simulation, so there isn't one.
The integrator is kept in three copies of hand placed flip-flops and voted
every clock, so a bit flipped by a particle hit is outvoted and rewritten on
the next clock. `GAIN` sets the scale from integrator to word.

The word drives a first order sigma-delta on `EFC`, and an RC outside turns
that into the tuning voltage. The top 8 bits are also on the uio pins.
Before lock the counter is jammed to the GPS pulse so it pulls in from any
phase. After two seconds with no pulse `HOLDOVER` goes high, the word freezes
and `PPS_OUT` keeps going from the oscillator.

### Ring oscillator

31 inverters and a divider. `RING_MON` is the ring over 16384, which is a
direct reading of how fast this die is. In `CAL` mode the TDC times ring
edges instead of GPS, which sweeps every tap, and a histogram of the codes
shows how wide each tap is.

### Telemetry

One line per pulse on `UART_TX`, 115200 8n1:

```text
DD CC PP WWWW S
```

`DD` is whole cycles short of nominal over the last second (signed), `CC` the
fine code, `PP` taps per cycle, `WWWW` the word, and `S` the status bits
have, cal, holdover, locked. In `CAL` mode each line is just `CC`.

The delay line and ring are false paths in `src/gpsdo.sdc`, since they are
sampled asynchronously on purpose, and are kept from being resized.

## How to test

Hold `rst_n` low for at least 50 clocks so the TDC sample register clears.
Then, with just a clock:

1. Pulse `PPS` once. `PPS_SEEN` toggles, `PPS_OUT` restarts high and a line
   comes out of `UART_TX`.
2. Pulse it once a second and each second prints a line. `PP` should be
   about 29 at room temperature, and `CC` moves as the pulse moves inside a
   clock cycle.
3. Set `CAL`. The line now times ring edges and prints one code per edge.
4. Set `RING_ON` and measure `RING_MON`, times 16384 is the ring frequency.

In a real GPSDO the GPS PPS goes to `PPS`, the oscillator to `clk`, `EFC`
through the RC to the tuning pin and `UART_TX` to a USB serial adapter.
`LOCKED` goes high after 15 seconds in a row within 8 taps. Start with `GAIN`
at 0, 2 and 3 are slower for a better oscillator.

| Input   | Use                                                 |
| ------- | --------------------------------------------------- |
| PPS     | GPS pulse per second, rising edge timed             |
| HOLD    | freeze the control word                             |
| CAL     | time ring edges instead of PPS                      |
| RING_ON | run the ring oscillator                             |
| GAIN    | 0 1:1, 1 x2, 2 /2, 3 /4 from integrator to DAC word |

## External hardware

- GPS receiver with a PPS output, e.g. a u-blox NEO-M8N
- 10 MHz voltage controlled oscillator (OCXO or VCTCXO) as the clock
- RC low pass from `EFC` to the tuning pin, e.g. 10 kΩ and 10 µF, scaled to
  the oscillator's tuning range
- USB to UART adapter on `UART_TX`
