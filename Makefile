
BASE := $(shell pwd)

# Set your project folder either as a relative location from the repository root,
# or as an absolute path. Project name is the Vivado project name.
PRJ_FOLDER := ../zedboard_jtag_01
PRJ_NAME := zed_board_01

# If you change the part, you need to change the constraints to match that part/board.
FPGA_PART := xc7z020clg484-2

# Setting Source and Constraint files
include $(BASE)/rtl/include_src.mk 
include $(BASE)/constraints/include_constraints.mk

run:
	@echo ""
	@echo "Usage: make [OPTIONS]"
	@echo "Make sure to set your Vivado project folder location in the Makefile"
	@echo "  run                         - Help message."
	@echo "  help                        - Help message."
	@echo "  project                     - Build the Vivado project if it does not exist."
	@echo "  clean                       - Clean Vivado tool log and jou files (not vivado project or run logs)."
	@echo "  delete_project              - Delete's Vivado project."

help: run

project:
	env PRJ_FOLDER="$(PRJ_FOLDER)" PRJ_NAME="$(PRJ_NAME)" FPGA_PART="$(FPGA_PART)" BASE="$(BASE)" SRC_FILES="$(SRC_FILES)" CONSTRAINT_FILES="$(CONSTRAINT_FILES)" vivado -mode batch -source scripts/create_project.tcl

clean:
	@rm -f vivado*.log
	@rm -f vivado*.jou

delete_project:
	@rm -rf $(PRJ_FOLDER)/$(PRJ_NAME)