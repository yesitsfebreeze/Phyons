package phyons

import "core:fmt"
import "core:os/os2"

set_exe_cwd :: proc() -> bool {
	exe_dir, err := os2.get_executable_directory(context.temp_allocator)
	if err == nil {
		os2.set_working_directory(exe_dir)
		return true
	} else {
		fmt.printf("Failed to set working directory: %v\n", err)
	}
	return false
}
