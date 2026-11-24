# Tool-neutral baseline constraints for gs_accel_system_top.
# These values are early design targets, not signoff constraints or measured PPA.

set GS_CLK_PORT clk_i
set GS_RESET_PORT rst_ni

# Replace these parameters with package/interconnect and signoff budgets.
set GS_CLK_PERIOD_NS 5.000
set GS_CLK_UNCERTAINTY_NS 0.250
set GS_INPUT_DELAY_NS 0.500
set GS_OUTPUT_DELAY_NS 0.500

create_clock -name gs_core_clk -period $GS_CLK_PERIOD_NS [get_ports $GS_CLK_PORT]
set_clock_uncertainty $GS_CLK_UNCERTAINTY_NS [get_clocks gs_core_clk]

# rst_ni is an asynchronous assertion path. Recovery/removal and reset release
# strategy must be checked with the selected library and reset architecture.
set_false_path -from [get_ports $GS_RESET_PORT]

set GS_DATA_INPUTS [remove_from_collection [all_inputs] [get_ports [list $GS_CLK_PORT $GS_RESET_PORT]]]
set_input_delay $GS_INPUT_DELAY_NS -clock gs_core_clk $GS_DATA_INPUTS
set_output_delay $GS_OUTPUT_DELAY_NS -clock gs_core_clk [all_outputs]

# Library-dependent set_driving_cell, set_load, max transition/capacitance,
# clock-gating, generated-clock, multicycle, and false-path constraints are
# intentionally absent. Add them only from verified integration requirements.
