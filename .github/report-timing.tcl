package require ::quartus::project
project_open NeoGeo
create_timing_netlist -model slow
read_sdc
update_timing_netlist
report_timing -setup -npaths 20 -detail full_path -file output_files/NeoGeo.setup-paths.rpt
# See both board and accelerator paths even when one transfer dominates the overall report.
foreach {counter rate} {0 96 1 48} {
    set domain [get_clocks [format {emu|pll|*counter?%d?.output_counter|divclk} $counter]]
    if {[get_collection_size $domain] == 1} {
        report_timing -setup -to_clock $domain -npaths 12 -detail full_path -file output_files/NeoGeo.setup-${rate}MHz.rpt
    }
}
delete_timing_netlist
project_close
