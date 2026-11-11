# SPDX-FileCopyrightText: © 2026 Krystian Filipek
# SPDX-License-Identifier: Apache-2.0

#rtl runs with SIM_SHORT: a second of 1664 clocks, the same remainder mod
#256 as 10 mhz so the wrap is exercised, and 4 clocks a uart bit.
#gate level runs the real 10 mhz design on zero delay cells, so the delay
#line reads full. it checks the first pulse, and that the netlist kept the
#three integrator copies apart

import os
import re

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer

GL = os.environ.get("GATES") == "yes"
TIMING = os.environ.get("TIMING") == "yes"
SDF = os.environ.get("TIMING_SDF", "")
T_NS = 100
NOM = 1664
BIT = 4 if not GL else 87
TAP_NS = float(os.environ.get("TAP_NS", "3.4"))  #dlyd stand-in in cells.v
N = 44
LINE = re.compile(r"^([0-9A-F]{2}) ([0-9A-F]{2}) ([0-9A-F]{2}) ([0-9A-F]{4}) ([0-9A-F])$")

CAL, RING, HOLD = 0x04, 0x08, 0x02


def tap_ns():
    #mean rise delay of a dlyd cell in the sdf, the tap step
    with open(SDF) as f:
        text = f.read()
    d = re.findall(r'__dlyd_1"\)\s*\(INSTANCE [^)]*\)\s*\(DELAY\s*\(ABSOLUTE\s*'
                   r'\(IOPATH I Z \(([0-9.]+):', text)
    return sum(map(float, d)) / len(d)


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


async def setup(dut, ui=0, watch=True):
    cocotb.start_soon(Clock(dut.clk, T_NS, unit="ns").start())
    dut.ena.value = 1
    dut.ui_in.value = ui
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 60)  #long enough to clear the tdc snap
    dut.rst_n.value = 1
    lines = []
    if watch:
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
    #a fast die calibrates on half cycles, so a tap either way more
    assert abs(taps - T_NS / TAP_NS) <= (1 if T_NS / TAP_NS < N else 2), lines


@cocotb.test(skip=not TIMING)
async def real_delays_move_the_code(dut):
    #one pulse after each reset, offset after a clock edge, and the first
    #uart line carries its code. a line takes 13 ms, so no second pulse
    lines = await setup(dut, watch=False)
    tap = tap_ns()
    corner = os.environ.get("CORNER", "?")
    codes = []
    for off in (10.0, 30.0, 50.0, 70.0, 90.0):
        dut.rst_n.value = 0
        await ClockCycles(dut.clk, 60)
        dut.rst_n.value = 1
        lines.clear()
        dec = cocotb.start_soon(uart_lines(dut, lines))
        await RisingEdge(dut.clk)
        await Timer(off, unit="ns")
        cocotb.start_soon(pulse(dut))
        for _ in range(400):
            await ClockCycles(dut.clk, 100)
            if lines:
                break
        dec.cancel()
        assert lines and LINE.match(lines[0]), (off, lines[:3])
        code = int(LINE.match(lines[0]).group(2), 16)
        want = min(N, (T_NS - off) / tap)
        cocotb.log.info(f"timing {corner}: offset {off:.0f} ns code {code} "
                        f"want {want:.1f}")
        assert abs(code - want) <= 2, (off, code, want, tap)
        codes.append(code)
    #the code falls as the pulse moves into the cycle, unless the line is full
    for a, b in zip(codes, codes[1:]):
        assert b <= a, codes
    cocotb.log.info(f"timing {corner}: tap {tap:.2f} ns codes {codes}")


@cocotb.test(skip=GL)
async def telemetry_shows_a_step_when_locked(dut):
    #once locked the pulse jumps a couple of clocks, and dd has to say so
    lines = await setup(dut)
    await gps(dut, 25)
    assert bit(dut.uo_out, 3) == 1
    n = len(lines)
    await gps(dut, 3, offset_ns=130.0)
    await ClockCycles(dut.clk, 200)
    dd = [int(LINE.match(l).group(1), 16) for l in lines[n:]]
    assert dd[0] != 0 and dd[1:] == [0, 0], lines[n:]


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
        want = min(N, (T_NS - off) / TAP_NS)
        assert abs(code - want) <= 1, (off, code, want)


async def lock(dut, lines, slip, secs, off=30.0):
    #clk slip clocks a second off nominal, positive slow, and a dac step of
    #one moves it half the error a second would
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 60)
    dut.rst_n.value = 1
    dac = lambda: int(dut.user_project.u_loop.dac.value)
    g = 0.5 / (NOM * T_NS / TAP_NS)
    y = lambda: -slip / NOM + g * (dac() - 32768)
    await gps(dut, secs, offset_ns=off, y=y)
    assert bit(dut.uo_out, 3) == 1, (slip, lines[-3:])
    assert abs(y() * NOM) < 0.2, (slip, y() * NOM, lines[-3:])
    return y


@cocotb.test(skip=GL)
async def loop_locks_either_side(dut):
    #50 clocks a second is 5 ppm at 10 mhz, either side of the wrap
    lines = await setup(dut)
    for slip in (50, -50, 10, -10):
        await lock(dut, lines, slip, 60)


@cocotb.test(skip=GL)
async def too_far_off_never_claims_lock(dut):
    #100 clocks a second is outside the window, it must not lock onto an alias
    lines = await setup(dut)
    dac = lambda: int(dut.user_project.u_loop.dac.value)
    g = 0.5 / (NOM * T_NS / TAP_NS)
    await gps(dut, 40, y=lambda: -100 / NOM + g * (dac() - 32768))
    assert bit(dut.uo_out, 3) == 0, lines[-3:]


@cocotb.test(skip=GL)
async def relocks_after_holdover(dut):
    #the pulse lands 5 ns after an edge, which a fast die's line cannot reach
    lines = await setup(dut)
    y = await lock(dut, lines, 30, 60, off=5.0)
    await ClockCycles(dut.clk, 3 * NOM)
    assert bit(dut.uo_out, 4) == 1 and bit(dut.uo_out, 3) == 0
    await gps(dut, 30, offset_ns=5.0, y=y)
    assert bit(dut.uo_out, 3) == 1
    assert abs(y() * NOM) < 0.2


@cocotb.test(skip=GL)
async def pps_high_through_reset_is_not_an_edge(dut):
    lines = await setup(dut, ui=1)
    seen = bit(dut.uo_out, 6)
    await ClockCycles(dut.clk, 200)
    assert bit(dut.uo_out, 6) == seen and not lines
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 100)
    cocotb.start_soon(pulse(dut))
    await ClockCycles(dut.clk, 100)
    assert bit(dut.uo_out, 6) != seen


@cocotb.test(skip=GL)
async def holdover_when_pps_stops(dut):
    lines = await setup(dut)
    await gps(dut, 3)
    word = int(dut.uio_out.value)
    assert bit(dut.uo_out, 4) == 0
    await ClockCycles(dut.clk, 3 * NOM)
    assert bit(dut.uo_out, 4) == 1
    assert int(dut.uio_out.value) == word
    #pps out keeps going from the oscillator
    highs = 0
    for _ in range(NOM):
        await RisingEdge(dut.clk)
        highs += bit(dut.uo_out, 2)
    assert highs == NOM // 8, highs


@cocotb.test(skip=GL)
async def one_flipped_bit_is_outvoted(dut):
    lines = await setup(dut)
    await gps(dut, 3, y=lambda: -2e-4)
    loop = dut.user_project.u_loop
    before = int(loop.dac.value)
    ff = loop.u_r1.b[12].u_ff
    ff.Q.value = 1 - int(ff.Q.value)
    await ClockCycles(dut.clk, 2)
    assert int(loop.dac.value) == before
    assert int(ff.Q.value) == int(loop.u_r0.b[12].u_ff.Q.value)


@cocotb.test(skip=not GL or TIMING)
async def tmr_copies_survive_layout(dut):
    #the hardened netlist still has three separate flip-flops for every
    #integrator bit, each driving its own net into the vote
    net = open(os.path.join(os.path.dirname(__file__), "gate_level_netlist.v")).read()
    ffs = re.findall(r"dffq_1\s+\\u_loop\.u_r(\d)\.b\[(\d+)\]\.u_ff\s*\((.*?)\);", net, re.S)
    q = {}
    for copy, b, pins in ffs:
        q.setdefault(int(b), set()).add(re.search(r"\.Q\(([^)]*)\)", pins).group(1).strip())
    assert sorted(q) == list(range(19)), sorted(q)
    assert all(len(v) == 3 for v in q.values()), q
    assert len(ffs) == 57


@cocotb.test(skip=GL)
async def cal_mode_streams_ring_codes(dut):
    lines = await setup(dut, ui=CAL)
    await ClockCycles(dut.clk, 3000)
    codes = [int(l, 16) for l in lines if re.fullmatch(r"[0-9A-F]{2}", l)]
    assert len(codes) >= 5, lines
    assert all(c <= N for c in codes), codes
    assert len(set(codes)) > 1, codes
