
BASE := $(shell cd ../; pwd)

# Set your project folder either as a relative location from the repository root,
# or as an absolute path.
PRJ_FOLDER := ../zedboard_jtag_01

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

help: run

project:
	env PRJ_FOLDER="$(PRJ_FOLDER)" BASE="$(BASE)" SRC_FILES="$(SRC_FILES)" CONSTRAINT_FILES="$(CONSTRAINT_FILES)" vivado -mode batch -source create_project.tcl
