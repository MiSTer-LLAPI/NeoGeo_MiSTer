package require ::quartus::project
project_open NeoGeo
create_timing_netlist -model slow
read_sdc
update_timing_netlist
report_timing -setup -npaths 20 -detail full_path -file output_files/NeoGeo.setup-paths.rpt
delete_timing_netlist
project_close
