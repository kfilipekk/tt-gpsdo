# SPDX-FileCopyrightText: © 2026 Krystian Filipek
# SPDX-License-Identifier: Apache-2.0

#rtl runs with SIM_SHORT: a second of 2000 clocks and 4 clocks a uart bit.
#gate level runs the real 10 mhz design on zero delay cells, so the delay
#line reads full and only the first pulse is checked there

import os
import re

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer

GL = os.environ.get("GATES") == "yes"
T_NS = 100
NOM = 2000
BIT = 4 if not GL else 87
TAP_NS = 3.4            #dlyd stand-in in cells.v
N = 44
LINE = re.compile(r"^([0-9A-F]{2}) ([0-9A-F]{2}) ([0-9A-F]{2}) ([0-9A-F]{4}) ([0-9A-F])$")

CAL, RING, HOLD = 0x04, 0x08, 0x02


def bit(sig, i):
    v = sig.value
    return (int(v) >> i) & 1 if v.is_resolvable else 1


async def uart_lines(dut, out):
    buf = ""
    while True:
        await RisingEdge(dut.clk)
        if bit(dut.uo_out, 0):
            continue
        await ClockCycles(dut.clk, BIT // 2)
        byte = 0
        for i in range(8):
            await ClockCycles(dut.clk, BIT)
            byte |= bit(dut.uo_out, 0) << i
        await ClockCycles(dut.clk, BIT)
        if byte == 0x0A:
            out.append(buf)
            buf = ""
        else:
            buf += chr(byte)


async def setup(dut, ui=0):
    cocotb.start_soon(Clock(dut.clk, T_NS, unit="ns").start())
    dut.ena.value = 1
    dut.ui_in.value = ui
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    lines = []
    cocotb.start_soon(uart_lines(dut, lines))
    return lines


async def pulse(dut, width_ns=20_000):
    dut.ui_in.value = int(dut.ui_in.value) | 1
    await Timer(width_ns, unit="ns")
    dut.ui_in.value = int(dut.ui_in.value) & ~1


async def gps(dut, seconds, offset_ns=30.0, y=lambda: 0.0):
    #pps edges offset_ns after a clock edge, a second of 2000 clocks scaled
    #by 1 + y, y being how fast clk runs against gps
    await RisingEdge(dut.clk)
    await Timer(offset_ns, unit="ns")
    for _ in range(seconds):
        cocotb.start_soon(pulse(dut))
        await Timer(round(NOM * T_NS * (1 + y()) * 1000), unit="ps")


@cocotb.test()
async def first_pulse_gives_a_line(dut):
    lines = await setup(dut)
    assert int(dut.uio_out.value) == 0x80
    assert int(dut.uio_oe.value) == 0xFF
    seen = bit(dut.uo_out, 6)
    cocotb.start_soon(pulse(dut))
    await ClockCycles(dut.clk, 100)
    assert bit(dut.uo_out, 6) != seen
    assert bit(dut.uo_out, 2) == 1  #pps out restarted on the pulse
    await ClockCycles(dut.clk, 20 * 10 * BIT)
    assert len(lines) == 1, lines
    assert LINE.match(lines[0]), repr(lines[0])


@cocotb.test(skip=GL)
async def telemetry_line_per_pps(dut):
    lines = await setup(dut)
    await gps(dut, 4)
    await ClockCycles(dut.clk, 1000)
    assert len(lines) >= 3, lines
    for l in lines:
        assert LINE.match(l), repr(l)
    #a steady second is zero cycles short, and the code and calibration
    #match the stand-in delays
    dc, code, taps = (int(x, 16) for x in LINE.match(lines[-1]).groups()[:3])
    assert dc == 0, lines
    assert abs(code - (T_NS - 30) / TAP_NS) <= 1, lines
    assert abs(taps - T_NS / TAP_NS) <= 1, lines


@cocotb.test(skip=GL)
async def code_tracks_sub_cycle_phase(dut):
    lines = await setup(dut)
    for off in (10.0, 50.0, 90.0):
        dut.rst_n.value = 0
        await ClockCycles(dut.clk, 5)
        dut.rst_n.value = 1
        lines.clear()
        await gps(dut, 2, offset_ns=off)
        await ClockCycles(dut.clk, 1000)
        code = int(LINE.match(lines[-1]).group(2), 16)
        want = (T_NS - off) / TAP_NS
        assert abs(code - want) <= 1, (off, code, want)
