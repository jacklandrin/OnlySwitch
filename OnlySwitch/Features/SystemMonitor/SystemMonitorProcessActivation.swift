import AppKit
import Darwin
import SystemMonitor

@MainActor
enum SystemMonitorProcessActivation {
    private static let responsibleForPID: (@convention(c) (pid_t) -> pid_t)? = {
        guard let symbol = dlsym(
            UnsafeMutableRawPointer(bitPattern: -2),
            "responsibility_get_pid_responsible_for_pid"
        ) else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()

    static func enrich(
        _ snapshot: SystemMonitorSnapshot,
        sampledIdentities: [Int32: SystemMonitorProcessIdentity]
    ) -> SystemMonitorSnapshot {
        let resolver = resolver()
        let processes = snapshot.processes.map { process in
            guard let identity = sampledIdentities[process.pid] else { return process }
            return SystemMonitorProcess(
                pid: process.pid,
                name: process.name,
                cpuUsage: process.cpuUsage,
                memoryBytes: process.memoryBytes,
                downloadBytesPerSecond: process.downloadBytesPerSecond,
                uploadBytesPerSecond: process.uploadBytesPerSecond,
                activationTarget: resolver.activationTarget(for: identity)
            )
        }
        return SystemMonitorSnapshot(
            timestamp: snapshot.timestamp,
            cpuUsage: snapshot.cpuUsage,
            cpuTemperatureCelsius: snapshot.cpuTemperatureCelsius,
            gpuUsage: snapshot.gpuUsage,
            gpuTemperatureCelsius: snapshot.gpuTemperatureCelsius,
            hardware: snapshot.hardware,
            memory: snapshot.memory,
            disks: snapshot.disks,
            network: snapshot.network,
            processes: processes
        )
    }

    static func activate(_ target: SystemMonitorProcessActivationTarget) -> SystemMonitorProcessActivationOutcome {
        guard let application = NSRunningApplication(
            processIdentifier: target.owningApplication.pid
        ) else { return .unavailable }
        return resolver().activate(target) { pid in
            guard application.processIdentifier == pid else { return false }
            NSApp.yieldActivation(to: application)
            return application.activate(options: [])
        }
    }

    nonisolated static func processIdentity(pid: pid_t) -> SystemMonitorProcessIdentity? {
        var info = proc_bsdinfo()
        let count = proc_pidinfo(
            pid,
            PROC_PIDTBSDINFO,
            0,
            &info,
            Int32(MemoryLayout<proc_bsdinfo>.size)
        )
        guard count == MemoryLayout<proc_bsdinfo>.size,
              let startTime = SystemMonitorProcessOwnershipResolver.startTimeMicroseconds(
                seconds: Int64(info.pbi_start_tvsec),
                microseconds: Int32(info.pbi_start_tvusec)
              ) else { return nil }
        return .init(pid: pid, startTimeMicroseconds: startTime)
    }

    private static func resolver() -> SystemMonitorProcessOwnershipResolver {
        SystemMonitorProcessOwnershipResolver(
            processIdentity: { processIdentity(pid: $0) },
            regularApplicationIdentity: { pid in
                guard let application = NSRunningApplication(processIdentifier: pid),
                      application.activationPolicy == .regular else { return nil }
                return processIdentity(pid: pid)
            },
            responsiblePID: { pid in
                guard let resolve = responsibleForPID else { return nil }
                let responsible = resolve(pid)
                return responsible > 0 ? responsible : nil
            },
            parentPID: { pid in
                var info = kinfo_proc()
                var size = MemoryLayout<kinfo_proc>.stride
                var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
                guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
                let parent = info.kp_eproc.e_ppid
                return parent > 0 ? parent : nil
            }
        )
    }
}
