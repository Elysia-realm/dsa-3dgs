# Current-profile register-storage first feedback, not final SRAM/PPA signoff.
# Inputs are set by run_t01_wsl_sta.py; all values are in the loaded Liberty units.
if {[catch {
    foreach key {T01_LIBERTY T01_NETLIST T01_DRIVER_CELL T01_LOAD T01_OUT_SDC} {
        if {![info exists ::env($key)]} { error "Missing environment value $key" }
    }
    read_liberty $::env(T01_LIBERTY)
    read_verilog $::env(T01_NETLIST)
    set top gs_accel_system_top
    if {[info exists ::env(T01_TOP)]} { set top $::env(T01_TOP) }
    link_design $top
    puts "T01_LINKED_TOP=$top"
    create_clock -name gs_core_clk -period 5.0 [get_ports clk_i]
    set_clock_uncertainty 0.25 [get_clocks gs_core_clk]
    # Engineering source-slew budget, not an extracted clock tree.
    set_clock_transition 0.05 [get_clocks gs_core_clk]
    set data_inputs {}
    foreach p [all_inputs] {
        if {[get_full_name $p] ne "clk_i"} { lappend data_inputs $p }
    }
    # Includes reset deassertion; no blanket false path on reset.
    set_input_delay -clock gs_core_clk -max 0.5 $data_inputs
    set_input_delay -clock gs_core_clk -min 0.0 $data_inputs
    set_driving_cell -lib_cell $::env(T01_DRIVER_CELL) -input_transition_rise 0.05 -input_transition_fall 0.05 $data_inputs
    set_output_delay -clock gs_core_clk -max 0.5 [all_outputs]
    set_output_delay -clock gs_core_clk -min 0.0 [all_outputs]
    set_load $::env(T01_LOAD) [all_outputs]
    write_sdc $::env(T01_OUT_SDC)
    puts "T01_BEGIN_UNITS"
    report_units
    puts "T01_BEGIN_COVERAGE"
    set coverage_ok [check_setup -verbose]
    puts "T01_COVERAGE_OK=$coverage_ok"
    puts "T01_BEGIN_SETUP"
    report_checks -path_delay max -group_path_count 10 -format full_clock_expanded
    puts "T01_BEGIN_HOLD"
    report_checks -path_delay min -group_path_count 10 -format full_clock_expanded
    puts "T01_BEGIN_SUMMARY"
    report_worst_slack -max
    report_worst_slack -min
    report_tns -max
    report_tns -min
    puts "T01_BEGIN_ASYNC_RESET_CHECKS"
    report_check_types -recovery -removal -max_count 20
    puts "T01_BEGIN_ELECTRICAL"
    report_check_types -max_slew -max_capacitance -max_fanout -violators -max_count 40
    puts "T01_STA_REPORT_END_REQUIRES_AUDIT"
} reason]} {
    puts stderr "T01_STA_FAILED: $reason"
    exit 1
}
exit 0
