#build the inputs for the sdf timing run. icarus x's a cell whose output a
#submodule drives once a specify path is on it, so the dlyd wrapper is left
#to timing_dly.v, and its sdf parser splits escaped instance names at dots,
#so the 44 delay line cells get flat names in the netlist and the sdf.
#everything else passes through as built.

import re
import sys

lib_in, net_in, sdf_in, lib_out, net_out, sdf_out = sys.argv[1:7]

lib = open(lib_in).read()
lib = re.sub(r"`ifndef GF180MCU_FD_SC_MCU7T5V0__DLYD_1_V\b.*?"
             r"`endif // GF180MCU_FD_SC_MCU7T5V0__DLYD_1_V\n",
             "", lib, flags=re.S)
open(lib_out, "w").write(lib)

net, n = re.subn(r"gf180mcu_fd_sc_mcu7t5v0__dlyd_1\s+"
                 r"\\u_tdc\.g\[(\d+)\]\.u_dly\s+\(",
                 r"gf180mcu_fd_sc_mcu7t5v0__dlyd_1 u_dly_\1 (",
                 open(net_in).read())
assert n == 44, n
open(net_out, "w").write(net)

sdf = open(sdf_in).read()
head = sdf[:sdf.index(" (CELL\n")]
cells = []
for c in re.findall(r" \(CELL\n.*?\n \)\n", sdf, re.S):
    m = re.search(r'\(CELLTYPE "gf180mcu_fd_sc_mcu7t5v0__dlyd_1"\)\s*'
                  r'\(INSTANCE u_tdc\\\.g\\\[(\d+)\\\]\\\.u_dly\)', c)
    p = re.search(r"\(IOPATH I Z [^\n]+\)", c)
    if m and p:
        cells.append(" (CELL\n"
                     '  (CELLTYPE "gf180mcu_fd_sc_mcu7t5v0__dlyd_1")\n'
                     f"  (INSTANCE u_dly_{m.group(1)})\n"
                     "  (DELAY\n"
                     "   (ABSOLUTE\n"
                     f"    {p.group(0)}\n"
                     "   )\n"
                     "  )\n"
                     " )\n")
assert len(cells) == 44, len(cells)
open(sdf_out, "w").write(head + "".join(cells) + ")\n")
