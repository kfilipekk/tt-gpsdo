# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
SIM ?= icarus
FST ?= -fst # Use more efficient FST format
TOPLEVEL_LANG ?= verilog
.DEFAULT_GOAL := sim
SRC_DIR = $(PWD)/../src
PROJECT_SOURCES = project.v tdc.v ring.v loop.v tmr_reg.v uart_tx.v

#timing mode reads the hardened netlist and an sdf corner from a local
#harden, TT_BUILD points at another run
TT_BUILD ?= $(PWD)/../runs/wokwi/final
CORNER ?= nom_tt_025C_3v30
TIMING_NETLIST ?= $(TT_BUILD)/pnl/tt_um_kfilipekk_gpsdo.pnl.v
TIMING_SDF ?= $(TT_BUILD)/sdf/$(CORNER)/tt_um_kfilipekk_gpsdo__$(CORNER).sdf
GF180_LIB ?= $(PDK_ROOT)/gf180mcuD/libs.ref

ifneq ($(GATES),yes)

# RTL simulation:
SIM_BUILD				= sim_build/rtl
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))
#delayed stand-ins for the hand placed cells, and a 2000 clock second.
#TAP_NS=2 runs a fast die
TAP_NS ?= 3.4
export TAP_NS
VERILOG_SOURCES += $(PWD)/cells.v
COMPILE_ARGS    += -DSIM_SHORT -DTAP_NS=$(TAP_NS)

else

ifeq ($(TIMING),yes)

# Gate level with real delays:
SIM_BUILD				= sim_build/timing
TIMING_WORK				= $(SIM_BUILD)/prep
TIMING_LIB				= $(TIMING_WORK)/cells.v
TIMING_NET				= $(TIMING_WORK)/netlist.v
TIMING_ANNOTATE_SDF		= $(TIMING_WORK)/timing.sdf
export TIMING CORNER TIMING_SDF
COMPILE_ARGS    += -DGL_TEST
COMPILE_ARGS    += -DTIMING
COMPILE_ARGS    += -DTIMING_SDF=\"$(TIMING_ANNOTATE_SDF)\"
COMPILE_ARGS    += -DUSE_POWER_PINS
COMPILE_ARGS    += -DSIM
#icarus x's a pdk cell whose output a submodule drives once a specify path
#is on it, so only the delay line keeps specify blocks, and the sdf picked
#by CORNER sets its 44 tap delays
COMPILE_ARGS    += -DFUNCTIONAL
COMPILE_ARGS    += -gspecify
VERILOG_SOURCES += $(GF180_LIB)/gf180mcu_fd_sc_mcu7t5v0/verilog/primitives.v
VERILOG_SOURCES += $(TIMING_LIB)
VERILOG_SOURCES += $(PWD)/timing_dly.v
VERILOG_SOURCES += $(TIMING_NET)

$(TIMING_WORK)/.prep: $(TIMING_NETLIST) $(TIMING_SDF) \
                       $(GF180_LIB)/gf180mcu_fd_sc_mcu7t5v0/verilog/gf180mcu_fd_sc_mcu7t5v0.v \
                       $(PWD)/timing_cells.py
	@mkdir -p $(TIMING_WORK)
	python3 $(PWD)/timing_cells.py \
	    $(GF180_LIB)/gf180mcu_fd_sc_mcu7t5v0/verilog/gf180mcu_fd_sc_mcu7t5v0.v \
	    $(TIMING_NETLIST) $(TIMING_SDF) \
	    $(TIMING_LIB) $(TIMING_NET) $(TIMING_ANNOTATE_SDF)
	@touch $@

$(SIM_BUILD)/sim.vvp: $(TIMING_WORK)/.prep

else

# Gate level simulation:
SIM_BUILD				= sim_build/gl
COMPILE_ARGS    += -DGL_TEST
COMPILE_ARGS    += -DFUNCTIONAL
COMPILE_ARGS    += -DUSE_POWER_PINS
COMPILE_ARGS    += -DSIM
COMPILE_ARGS    += -DUNIT_DELAY=\#1
VERILOG_SOURCES += $(PDK_ROOT)/gf180mcuD/libs.ref/gf180mcu_fd_sc_mcu7t5v0/verilog/primitives.v
VERILOG_SOURCES += $(PDK_ROOT)/gf180mcuD/libs.ref/gf180mcu_fd_sc_mcu7t5v0/verilog/gf180mcu_fd_sc_mcu7t5v0.v

# this gets copied in by the GDS action workflow
VERILOG_SOURCES += $(PWD)/gate_level_netlist.v

endif

endif

# Allow sharing configuration between design and testbench via `include`:
COMPILE_ARGS 		+= -I$(SRC_DIR)

# Include the testbench sources:
VERILOG_SOURCES += $(PWD)/tb.v
TOPLEVEL = tb

# List test modules to run, separated by commas and without the .py suffix:
COCOTB_TEST_MODULES = test

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim
