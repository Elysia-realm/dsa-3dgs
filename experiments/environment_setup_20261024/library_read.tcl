if {[catch {
    read_liberty $::env(GS_LIB_AUDIT_PATH)
    set count [llength [get_lib_cells */*]]
    if {$count == 0} { error "No library cells loaded" }
    report_units
    puts "LIBRARY_READ_PASS cells=$count"
} reason]} {
    puts stderr "LIBRARY_READ_FAILED: $reason"
    exit 1
}
exit 0
