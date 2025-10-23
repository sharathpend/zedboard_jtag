set project_location $::env(PRJ_FOLDER)
set base_location $::env(BASE)
set src_files $::env(SRC_FILES)
set constraint_files $::env(CONSTRAINT_FILES)
#set ip_files $::env(IP_FILES)

# Check if project already exists
if {[file exists $project_location/zed_board_01/zed_board_01.xpr]} {
    puts "Project already exists at $project_location/zed_board_01/zed_board_01.xpr"
} else {
    create_project zed_board_01 $project_location -part xc7z020clg484-2
    foreach constraint_file $constraint_files {
        add_files -fileset constrs_1 -norecurse $constraint_file
    }
    foreach src_file $src_files {
        add_files -scan_for_includes $src_file
    }
}