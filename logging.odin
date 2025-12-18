package phyons

import "core:log"
import "core:mem"

// Force mem import to be used even when USE_TRACKING_ALLOCATOR is false
_ :: mem

USE_TRACKING_ALLOCATOR :: #config(USE_TRACKING_ALLOCATOR, ODIN_DEBUG)

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

init_logging :: proc() {
	context.logger = log.create_console_logger()

	when USE_TRACKING_ALLOCATOR {
		default_allocator := context.allocator
		mem.tracking_allocator_init(&tracking_allocator, default_allocator)
		context.allocator = mem.tracking_allocator(&tracking_allocator)
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
		mem.tracking_allocator_destroy(&tracking_allocator)
	}

	log.destroy_console_logger(context.logger)
}
