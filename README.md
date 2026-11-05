![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg)

# GPS disciplined oscillator on GF180

This is a GPSDO controller that fits in one Tiny Tapeout tile on
GlobalFoundries 180 nm. It:

- times each GPS pulse to a fraction of a clock cycle with an on-chip delay
  line
- calibrates that line against the clock every second
- steers a 10 MHz oscillator through a sigma-delta DAC

It also has holdover, a triplicated loop integrator, a ring oscillator
process monitor and UART telemetry.

It fills 94% of the 1x1 tile, with no setup or hold violations at any
corner, and LVS, DRC and antenna clean.

It is the ASIC version of [fpga_gps_clock](https://github.com/kfilipekk/fpga_gps_clock),
a GPSDO with a carry chain TDC on a Tang Nano 9K. That board held an OCXO to
0.05 ppb at 4096 s against GPS, measured in loop. Here the FPGA carry chain
becomes a chain of `dlyd` cells, and the same self calibration makes the
measurement independent of process corner.

- [Datasheet: how it works, how to test, hardware](docs/info.md)
- [Testbench](test/README.md)

## Layout

| Block | What |
| --- | --- |
| `src/tdc.v` | 44 tap delay line, sampled every clock, bubbles counted not decoded |
| `src/loop.v` | integral loop: saturating, TMR integrator, gain select |
| `src/tmr_reg.v` | kept flip-flops for the voted integrator |
| `src/ring.v` | 31 stage ring oscillator and ripple divider |
| `src/uart_tx.v` | telemetry at 115200 baud |
| `src/project.v` | phase counter, self calibration, sigma-delta, telemetry |
| `src/gpsdo.sdc` | false paths through the delay line and the ring |
