//
//  ProcessUsage.h
//  OnlySwitch
//
//  Swift-friendly wrapper for libproc's incorrectly typed rusage buffer.
//

#pragma once

#import <libproc.h>
#import <sys/resource.h>

/// Reads version-2 process resource usage into the supplied struct.
///
/// libproc declares its output argument as `rusage_info_t *`, although
/// `rusage_info_t` is itself `void *`. The Darwin ABI expects the address of
/// the concrete output struct; centralizing its required C cast here prevents
/// Swift from accidentally passing the address of a pointer-sized variable.
static inline int OnlySwitchProcessRusageV2(pid_t pid, struct rusage_info_v2 *usage) {
    return proc_pid_rusage(pid, RUSAGE_INFO_V2, (rusage_info_t *)usage);
}
