package phyons

import "base:runtime"
import "core:os/os2"

set_exe_cwd :: proc() -> bool {
	exe_dir, err := os2.get_executable_directory(context.temp_allocator)
	if err == nil {
		os2.set_working_directory(exe_dir)
		return true
	} else {
		logf_err("Failed to set working directory: %v\n", err)
	}
	return false
}


absolute_path :: proc(current: string, alloc: runtime.Allocator) -> string {
	abs_path, err := os2.get_absolute_path(current, alloc)
	if err != nil {
		logf_err("Failed to get absolute path: %v\n", err)
		return ""
	}
	return abs_path
}

relative_path :: proc(current: string, base: string, alloc: runtime.Allocator) -> string {
	abs_base := absolute_path(base, alloc)
	rel_path, err := os2.get_relative_path(abs_base, current, alloc)
	if err != nil {
		logf_debug("Failed to get relative path: %v\n", err)
		return current
	}
	return rel_path
}

join_path :: proc(parts: []string, alloc: runtime.Allocator) -> string {
	if len(parts) == 0 {
		return ""
	}
	result, err := os2.join_path(parts, alloc)
	if err != nil {
		logf_err("Failed to join path: %v\n", err)
		return ""
	}
	return result
}
