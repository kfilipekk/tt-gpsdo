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

On a fast die (cold, high supply, fast process) 44 taps can be shorter than
a clock period, about 88 ns at the ff corner. When the calibration pulse
fills the line the chip launches it on the falling edge instead, measures
half a cycle and doubles it, and goes back to full cycles once one fits with
a few taps spare. That assumes the clock is close to 50% duty, an error there
only scales the loop gain. A GPS pulse in the first ~12 ns after an edge then reads
as a full line, 44, so the loop is blind to motion inside that sliver but
still sees every whole cycle.

The taps are sampled once and the result is used on the next clock, so a
sample that goes metastable has most of a 100 ns period to settle. There is
no second synchroniser stage, there is no room for 44 more flip-flops.

### Loop

Each second gives the error in taps: whole cycles times taps per cycle, plus
the change in fine code. An integrator adds it up and sets a 16 bit word. A
proportional term only added counter noise in simulation, so there isn't one.
The integrator is kept in three copies of hand placed flip-flops and voted
every clock, so a bit flipped by a particle hit is outvoted and rewritten on
the next clock. Only the integrator is tripled, a flip in the counters or the
sigma-delta is a one second glitch rather than a lost lock. `GAIN` sets the
scale from integrator to word.

The integrator sums the phase moves, so it holds the oscillator on GPS in
frequency and keeps `PPS_OUT` at a fixed offset from the GPS edge, set by
where it locked and how far off the oscillator sits on its own. It does not
pull `PPS_OUT` onto the edge, the 10 MHz is the product. Telemetry shows the
offset.

The word drives a first order sigma-delta on `EFC`, and an RC outside turns
that into the tuning voltage. The top 8 bits are also on the uio pins.
Before lock the counter is jammed to the GPS pulse so it pulls in from any
phase, and from up to 63 clocks a second either way, about 6 ppm, which
covers any OCXO or VCTCXO. The phase is kept as the offset from the nearest
wrap of the counter, since a second is not a whole number of 256 clocks.
Further off than that it does not update, and past about 19 ppm the phase
aliases, so start the oscillator near 10 MHz. `LOCKED` needs 15 seconds in a row within 24
taps and drops after 3 bad ones in a row, so GPS jitter does not flap it.
After two seconds with no pulse `HOLDOVER` goes high, `LOCKED` drops,
the word freezes and `PPS_OUT` keeps going from the oscillator. When GPS
comes back the counter is jammed to it again and the loop carries on from
the frozen word.

`HOLD`, `CAL` and `GAIN` each go through two flip-flops before they are
used, so they can change at any time. A second that `CAL` or `GAIN` changes
in can still give one odd update, so change them with `HOLD` high if that
matters. `CAL` stops
GPS being timed, so after two seconds of it the chip is in holdover.

`ena` is not used, the Tiny Tapeout mux only connects the selected design to
the pads, so `uio_oe` is driven all the time.

### Ring oscillator

31 inverters and a divider. `RING_MON` is the ring over 1024, which is a
direct reading of how fast this die is. In `CAL` mode the TDC times the
ring over 64 instead of GPS. Its edges are not related to the clock, so they
land on every tap, and a histogram of the codes shows how wide each tap is.

### Telemetry

One line per pulse on `UART_TX`, 115200 8n1:

```text
DD CC PP WWWW S
```

`DD` is whole cycles short of nominal over the last second (signed), `CC` the
fine code, `PP` taps per cycle, `WWWW` the word, and `S` the status bits
have, cal, holdover, locked. In `CAL` mode each line is just `CC`, for
whichever edge comes in while the UART is free.

The delay line and ring are false paths in `src/gpsdo.sdc`, since they are
sampled asynchronously on purpose, and are kept from being resized. The ring
divider is a ripple counter clocked by the ring, so it is its own clock
domain. Only its divide by 64 reaches the logic, through the delay line, and
its divide by 1024 goes straight to a pin.

## How to test

Hold `rst_n` low for a few clocks. The TDC only starts once it has seen the
line low, so a PPS that is high at reset is not taken as an edge. Then, with
just a clock:

1. Pulse `PPS` once. `PPS_SEEN` toggles, `PPS_OUT` restarts high and a line
   comes out of `UART_TX`.
2. Pulse it once a second and each second prints a line. `PP` should be
   about 29 at room temperature, and `CC` moves as the pulse moves inside a
   clock cycle.
3. Set `CAL`. The line now times ring edges and prints a code each time
   the UART is free, a few thousand a second.
4. Set `RING_ON` and measure `RING_MON`, times 1024 is the ring frequency.

In a real GPSDO the GPS PPS goes to `PPS`, the oscillator to `clk`, `EFC`
through the RC to the tuning pin and `UART_TX` to a USB serial adapter.
`LOCKED` goes high after 15 seconds in a row within 24 taps. Start with `GAIN`
at 0, 2 and 3 are slower for a better oscillator.

| Input   | Use                                                 |
| ------- | --------------------------------------------------- |
| PPS     | GPS pulse per second, rising edge timed             |
| HOLD    | freeze the control word                             |
| CAL     | time ring edges instead of PPS                      |
| RING_ON | run the ring oscillator                             |
| GAIN    | 0 1:1, 1 x2, 2 /2, 3 /4 from integrator to DAC word |

| Output   | Use                                               |
| -------- | ------------------------------------------------- |
| UART_TX  | telemetry, 115200 8n1                             |
| EFC      | sigma-delta of the DAC word, RC it to the tuning pin |
| PPS_OUT  | high for the first 125 ms of each second          |
| LOCKED   | 15 good seconds in a row, drops after 3 bad ones  |
| HOLDOVER | no GPS pulse for two seconds                      |
| RING_MON | ring oscillator over 1024                         |
| PPS_SEEN | toggles on every GPS pulse                        |
| LINE_IN  | what goes into the delay line, for a scope        |
| DAC8-15  | top 8 bits of the DAC word, on the uio pins       |

## External hardware

- GPS receiver with a PPS output, e.g. a u-blox NEO-M8N. The pulse has to
  be low again before half a second, when the calibration pulse goes in, the
  usual 100 ms is fine
- 10 MHz voltage controlled oscillator (OCXO or VCTCXO) as the clock
- RC low pass from `EFC` to the tuning pin, e.g. 10 kΩ and 10 µF, scaled to
  the oscillator's tuning range
- USB to UART adapter on `UART_TX`
