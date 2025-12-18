package phyons

import "core:log"
import "core:mem"
import "core:os"

// Force mem import to be used even when USE_TRACKING_ALLOCATOR is false
_ :: mem

USE_TRACKING_ALLOCATOR :: #config(USE_TRACKING_ALLOCATOR, ODIN_DEBUG)
LOG_FILE_PATH :: #config(LOG_FILE_PATH, "phyons.log")

log_debug :: proc(args: ..any, location := #caller_location) {
	when ODIN_DEBUG {
		log.debug(args = args, location = location)
	}
}

log_info :: proc(args: ..any, location := #caller_location) {
	log.info(args = args, location = location)
}

log_warn :: proc(args: ..any, location := #caller_location) {
	log.warn(args = args, location = location)
}

log_err :: proc(args: ..any, location := #caller_location) {
	log.error(args = args, location = location)
}

log_fatal :: proc(args: ..any, location := #caller_location) {
	log.fatal(args = args, location = location)
}

// Formatted logging (printf-style)
logf_debug :: proc(fmt_str: string, args: ..any, location := #caller_location) {
	when ODIN_DEBUG {
		log.debugf(fmt_str, ..args, location = location)
	}
}

logf_info :: proc(fmt_str: string, args: ..any, location := #caller_location) {
	log.infof(fmt_str, ..args, location = location)
}

logf_warn :: proc(fmt_str: string, args: ..any, location := #caller_location) {
	log.warnf(fmt_str, ..args, location = location)
}

logf_err :: proc(fmt_str: string, args: ..any, location := #caller_location) {
	log.errorf(fmt_str, ..args, location = location)
}

logf_fatal :: proc(fmt_str: string, args: ..any, location := #caller_location) {
	log.fatalf(fmt_str, ..args, location = location)
}


@(private = "file")
tracking_allocator: mem.Tracking_Allocator

@(private = "file")
console_logger: log.Logger

@(private = "file")
file_logger: log.Logger

@(private = "file")
multi_logger: log.Logger

@(private = "file")
log_file_handle: os.Handle = os.INVALID_HANDLE

init_logging :: proc() -> log.Logger {
	// Create console logger
	console_logger = log.create_console_logger()

	// Create file logger
	log_file_handle, _ = os.open(LOG_FILE_PATH, os.O_WRONLY | os.O_CREATE | os.O_TRUNC, 0o644)
	if log_file_handle != os.INVALID_HANDLE {
		file_logger = log.create_file_logger(log_file_handle)
		// Create multi-logger combining both
		multi_logger = log.create_multi_logger(console_logger, file_logger)
		return multi_logger
	} else {
		// Fall back to console only if file creation fails
		return console_logger
	}
}

init_tracking_allocator :: proc() -> mem.Allocator {
	when USE_TRACKING_ALLOCATOR {
		default_allocator := context.allocator
		mem.tracking_allocator_init(&tracking_allocator, default_allocator)
		return mem.tracking_allocator(&tracking_allocator)
	} else {
		return context.allocator
	}
}

cleanup_logging :: proc() {
	when USE_TRACKING_ALLOCATOR {
		if len(tracking_allocator.allocation_map) > 0 {
			logf_err("=== %v allocations not freed: ===", len(tracking_allocator.allocation_map))
			for _, entry in tracking_allocator.allocation_map {
				logf_err("- %v bytes @ %v", entry.size, entry.location)
			}
		}
		if len(tracking_allocator.bad_free_array) > 0 {
			logf_err("=== %v bad frees: ===", len(tracking_allocator.bad_free_array))
			for entry in tracking_allocator.bad_free_array {
				logf_err("- %p @ %v", entry.memory, entry.location)
			}
		}
		// Get the backing allocator before destroying
		backing := tracking_allocator.backing
		mem.tracking_allocator_destroy(&tracking_allocator)
		// Restore default allocator for logger cleanup
		context.allocator = backing
	}

	// Destroy multi-logger if file was opened
	if log_file_handle != os.INVALID_HANDLE {
		log.destroy_multi_logger(multi_logger)
		log.destroy_file_logger(file_logger)
		log.destroy_console_logger(console_logger)
	} else {
		log.destroy_console_logger(console_logger)
	}
}
