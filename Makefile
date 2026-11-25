OS = LINUX
CMP = bsc

DIR ?= 
NAME ?= Testbench
TOP_FILE=$(NAME).bsv
MOD_NAME := mk$(NAME)
EXE = $(MOD_NAME)_sim
EXE_V = $(MOD_NAME)_simv

BUILD_DIR =build
SIM_DIR =sim

VERILOG_DIR =verilog
BUILD_DIR_V = $(BUILD_DIR)/verilog
SIM_DIR_V = $(SIM_DIR)/verilog

PEAKRDL ?= peakrdl
RDL_FILES ?= $(wildcard $(SIM_DIR)/*.rdl)
CHEADER_DIR ?= cheader

VSIM = iverilog
CLEAR =
ARGS ?= -u -show-schedule -Xc++ -Wno-format-truncation -Xc++ -Wno-dangling-else
ARGSC ?= -u -show-schedule
#-no-warn-action-shadowing
ARGSCV ?= -show-schedule -remove-dollar

BLUEAXI_DIR=
BLUEIMPORT=$(BLUEAXI_DIR):+
SOURCE_DIRS := . $(foreach dir,$(BLUEAXI_DIR),$(if $(strip $(dir)),$(dir)))
BSV_SRCS := $(sort $(TOP_FILE) $(foreach dir,$(SOURCE_DIRS),$(wildcard $(dir)/*.bsv)))

all: $(EXE)

allV: $(EXE_V)

$(BUILD_DIR)/$(MOD_NAME).ba: $(BSV_SRCS) Makefile
	@mkdir -p $(BUILD_DIR)
	$(CMP) -p $(BLUEIMPORT) -bdir $(BUILD_DIR) -sim -g $(MOD_NAME) $(ARGSC) -u $(TOP_FILE)

clean:
	rm -f $(EXE) $(EXE_V) *.so *.sched
	rm -rf $(BUILD_DIR) $(SIM_DIR) $(VERILOG_DIR) $(CHEADER_DIR)

# generate C headers from exported SystemRDL, run the simulation first to export
cheader:
	@mkdir -p $(CHEADER_DIR)
	$(foreach rdl,$(RDL_FILES),$(PEAKRDL) c-header $(rdl) -o $(CHEADER_DIR)/$(basename $(notdir $(rdl))).h;)

.PHONY: cheader

$(EXE): $(BUILD_DIR)/$(MOD_NAME).ba
	@mkdir -p $(SIM_DIR)
	$(CMP) -p $(BLUEIMPORT) -bdir $(BUILD_DIR) -simdir $(SIM_DIR) -sim -e $(MOD_NAME) $(ARGS) -o $@

sim: $(EXE)
	@echo Starting Bluesim simulation...
	./$<

simV: $(EXE_V)
	@echo Starting Bluesim simulation...
	./$<

vcd: $(EXE)
	@echo Starting Bluesim simulation with vcd output...
	./$< -V dump.vcd

compileV: $(TOP_FILE)
	@echo Compiling $(MOD_NAME) to Verilog
	@mkdir -p $(VERILOG_DIR)
	@mkdir -p $(BUILD_DIR_V)
	$(CMP) -p $(BLUEIMPORT) -bdir $(BUILD_DIR_V) -u -verilog -vdir $(VERILOG_DIR) -g $(MOD_NAME) $(ARGSCV) $<

$(EXE_V): compileV
	@mkdir -p $(SIM_DIR_V)
	$(CMP) -p $(BLUEIMPORT) -bdir $(BUILD_DIR_V) -simdir $(SIM_DIR_V) -vsim $(VSIM) -e $(MOD_NAME) $(ARGS) -verilog -o $@ -vdir $(VERILOG_DIR) $(VERILOG_DIR)/$(MOD_NAME).v

SOC_BLUEFABRIC_SRC ?= dep/bluefabric/src
SOC_BSV_PATH = +:src:examples:$(SOC_BLUEFABRIC_SRC)/common:$(SOC_BLUEFABRIC_SRC)/soc:$(SOC_BLUEFABRIC_SRC)/ahb:$(SOC_BLUEFABRIC_SRC)/apb
SOC_SOURCE_DIRS = src examples $(addprefix $(SOC_BLUEFABRIC_SRC)/,common soc ahb apb)
SOC_BUILD_DIR = $(BUILD_DIR)/soc-docs
SOC_HTML_DIR ?= sim/BlueCSRSoCExample-html

.PHONY: soc-docs soc-html
soc-docs:
	@mkdir -p sim
	$(MAKE) sim NAME=BlueCSRSoCExample TOP_FILE=examples/BlueCSRSoCExample.bsv \
	    BLUEIMPORT="$(SOC_BSV_PATH)" SOURCE_DIRS="$(SOC_SOURCE_DIRS)" BUILD_DIR="$(SOC_BUILD_DIR)" \
	    SIM_DIR="$(SOC_BUILD_DIR)" EXE="$(SOC_BUILD_DIR)/soc_sim"

soc-html: soc-docs
	$(PEAKRDL) html sim/BlueCSRSoCExample.rdl -o "$(SOC_HTML_DIR)"
