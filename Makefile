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

VSIM = iverilog
CLEAR =
ARGS ?= -u -show-schedule -Xc++ -Wno-format-truncation -Xc++ -Wno-dangling-else
ARGSC ?= -u -show-schedule
#-no-warn-action-shadowing
ARGSCV ?= -show-schedule -remove-dollar

BLUEAXI_DIR=
BLUEIMPORT=$(BLUEAXI_DIR):+
SOURCE_DIRS := . $(foreach dir,$(BLUEAXI_DIR),$(if $(strip $(dir)),$(dir)))
BSV_SRCS := $(sort $(foreach dir,$(SOURCE_DIRS),$(wildcard $(dir)/*.bsv)))

all: $(EXE)

allV: $(EXE_V)

$(BUILD_DIR)/$(MOD_NAME).ba: $(BSV_SRCS) Makefile
	@mkdir -p $(BUILD_DIR)
	$(CMP) -p $(BLUEIMPORT) -bdir $(BUILD_DIR) -sim -g $(MOD_NAME) $(ARGSC) -u $(TOP_FILE)

clean:
	rm -f $(EXE) $(EXE_V) *.so *.sched
	rm -rf $(BUILD_DIR) $(SIM_DIR) $(VERILOG_DIR)

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

	