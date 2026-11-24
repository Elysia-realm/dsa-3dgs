# Invoke from the directory containing smoke_netlist.v and smoke.vcd.
# ENV_SMOKE_LIB must point at the project's original Nangate45 TT Liberty.
# No accelerator RTL or memory black box is part of this installation test.
if {[catch {
    if {![info exists ::env(ENV_SMOKE_LIB)] || ![file isfile $::env(ENV_SMOKE_LIB)]} {
        error "ENV_SMOKE_LIB must name an existing Nangate45 TT Liberty"
    }
    read_liberty $::env(ENV_SMOKE_LIB)
    read_verilog smoke_netlist.v
    link_design env_smoke
    create_clock -name clk -period 5.0 [get_ports clk_i]
    set_clock_uncertainty 0.25 [get_clocks clk]
    set_input_delay -clock clk -max 0.5 [get_ports d_i]
    set_input_delay -clock clk -min 0.0 [get_ports d_i]
    set_output_delay -clock clk -max 0.5 [get_ports q_o]
    set_output_delay -clock clk -min 0.0 [get_ports q_o]
    set_driving_cell -lib_cell BUF_X1 [get_ports d_i]
    # Nangate45 TT capacitive_load_unit is 1 fF; verify report_units below.
    set_load 3.899 [get_ports q_o]
    report_units
    check_setup -verbose
    report_checks -path_delay max -group_path_count 5
    report_checks -path_delay min -group_path_count 5
    report_worst_slack -max
    report_worst_slack -min
    report_tns
    # This is only a VCD reader/power-command smoke, not a power acceptance run.
    read_vcd -scope tb/dut smoke.vcd
    report_power
    puts "ENV_STA_COMMANDS_COMPLETED_NOT_PROJECT_SIGNOFF"
} reason]} {
    puts stderr "ENV_STA_FAILED: $reason"
    exit 1
}
exit 0
