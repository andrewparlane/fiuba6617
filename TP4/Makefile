# ----------------------------------------------------------------------------------
# Requirements:
#	QuestaSim - We use vcom and vsim.
#	Each test bench must contain an instantiation called dut.
#	Each test bench must call std.env.stop when it's finished testing.
# ----------------------------------------------------------------------------------

ifndef WLF
# set the default target to be all. Otherwise it's the first target it finds
.DEFAULT_GOAL := all
else
.DEFAULT_GOAL := view
endif

# Directories
SIM_DIR			= sim
WAVES_DIR		= $(SIM_DIR)/waves
SRC_DIR			= src
PKG_SRC_DIR		= $(SRC_DIR)/pkg
TB_SRC_DIR		= $(SRC_DIR)/tb
COMMON_DIR		= ../common
QUARTUS_DIR		= C:\\altera/13.0sp1/quartus

# Common Lib name
# Add the following to your .vhd files that need
# to use something from the common/ directory
# 	library common;
#	use common.all;
COMMON_LIB		= common

CORDIC_GEN_PATH = c/cordic_test_generator

# src files
SRCS	= $(wildcard $(SRC_DIR)/*.vhd) \
		  $(wildcard $(SRC_DIR)/synth_test/*.vhd) \
# tb files
TB_SRCS	= $(wildcard $(TB_SRC_DIR)/*.vhd) \
		  $(wildcard $(TB_SRC_DIR)/*.sv)

# Extra arguments beyond the defaults in helper.mk
VCOM_FLAGS		=
VSIM_FLAGS		=

ifndef NUM_CORDIC_TESTS
NUM_CORDIC_TESTS = 100000
endif

# Now include our helper.mk which has all the rules we need
# to create our library, compile and simulate our test benches
include ../herramientas/helper.mk

common:
	@# Build all the sources, but not the testbenches
	@make -C $(COMMON_DIR) all
	@# Add the common lib to our modelsim.ini
	@$(call MAP_VLIB_CMD, $(COMMON_DIR), $(COMMON_LIB))

cordic_test_gen:
	@make -C $(CORDIC_GEN_PATH)

# default rule is to create the library, and compile all the components
all: common altera_mf srcs tb_srcs cordic_test_gen

.PHONY: common all

$(SIM_DIR)/altera_mf_work:
	vlib $(SIM_DIR)/altera_mf_work
	vmap $(MODELSIM_FLAG) altera_mf $(SIM_DIR)/altera_mf_work

$(SIM_DIR)/altera_mf_work/flag: $(SIM_DIR)/altera_mf_work
	vcom $(MODELSIM_FLAG) -work altera_mf -2002 -explicit $(QUARTUS_DIR)/eda/sim_lib/altera_mf_components.vhd
	vcom $(MODELSIM_FLAG) -work altera_mf -2002 -explicit $(QUARTUS_DIR)/eda/sim_lib/altera_mf.vhd
	touch $(SIM_DIR)/altera_mf_work/flag

altera_mf: $(SIM_DIR)/altera_mf_work/flag

.PHONY: altera_mf

sram: all
	@$(call VSIM_CMD, sram_tb)

video_ram: all
	@$(call VSIM_CMD, video_ram_tb)

video_subsystem: all
	@$(call VSIM_CMD, video_subsystem_tb)

.PHONY: sram video_ram video_subsystem

cordic_no_delay: all cordic_test_gen
	$(CORDIC_GEN_PATH)/cordicTestGen -n $(NUM_CORDIC_TESTS) -o $(CORDIC_GEN_PATH)/out.txt
	@$(call VSIM_CMD, cordic_rotation_tb, -gTEST_FILE=c/cordic_test_generator/out.txt -gDELAY_BETWEEN_ENTRIES=0)

cordic_delay: all cordic_test_gen
	$(CORDIC_GEN_PATH)/cordicTestGen -n $(NUM_CORDIC_TESTS) -o $(CORDIC_GEN_PATH)/out.txt
	@$(call VSIM_CMD, cordic_rotation_tb, -gTEST_FILE=c/cordic_test_generator/out.txt -gDELAY_BETWEEN_ENTRIES=2)

cordic_3d_no_delay: all cordic_test_gen
	$(CORDIC_GEN_PATH)/cordicTestGen -3 -n $(NUM_CORDIC_TESTS) -o $(CORDIC_GEN_PATH)/out.txt
	@$(call VSIM_CMD, cordic_rotation_3d_tb, -gTEST_FILE=c/cordic_test_generator/out.txt -gDELAY_BETWEEN_ENTRIES=0)

cordic_3d_delay: all cordic_test_gen
	$(CORDIC_GEN_PATH)/cordicTestGen -3 -n $(NUM_CORDIC_TESTS) -o $(CORDIC_GEN_PATH)/out.txt
	@$(call VSIM_CMD, cordic_rotation_3d_tb, -gTEST_FILE=c/cordic_test_generator/out.txt -gDELAY_BETWEEN_ENTRIES=2)

.PHONY: cordic_no_delay cordic_delay cordic_3d_no_delay cordic_3d_delay

transform: all cordic_test_gen
	$(CORDIC_GEN_PATH)/cordicTestGen -p -n $(NUM_CORDIC_TESTS) -o $(CORDIC_GEN_PATH)/out.txt
	@$(call VSIM_CMD, transform_tb, -gTEST_FILE=c/cordic_test_generator/out.txt)

.PHONY: transform

uart_rx: all
	@$(call VSIM_CMD, uart_rx_tb)

control: all
	@$(call VSIM_CMD, control_tb)

buttons: all
	@$(call VSIM_CMD, buttons_tb)

.PHONY: uart_rx control buttons

# delete the library and all compiled files
clean: helper_clean
	$(call DEL_VLIB_CMD, $(COMMON_LIB))

distclean: clean
	make -C $(COMMON_DIR) clean

.PHONY: clean distclean
