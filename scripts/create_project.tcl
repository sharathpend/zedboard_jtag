set project_location $::env(PRJ_FOLDER)
set prj_name $::env(PRJ_NAME)
set fpga_part $::env(FPGA_PART)
set base_location $::env(BASE)
set src_files $::env(SRC_FILES)
set constraint_files $::env(CONSTRAINT_FILES)
#set ip_files $::env(IP_FILES)


if {[file exists $project_location/$prj_name/$prj_name.xpr]} {
    puts "Project already exists at $project_location/$prj_name/$prj_name.xpr"
} else {
    create_project $prj_name $project_location -part $fpga_part
    foreach constraint_file $constraint_files {
        add_files -fileset constrs_1 -norecurse $constraint_file
    }
    foreach src_file $src_files {
        add_files -scan_for_includes $src_file
    }
    update_compile_order -fileset sources_1
    exit
}