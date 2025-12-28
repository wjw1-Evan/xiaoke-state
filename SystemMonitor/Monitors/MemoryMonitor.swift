import Darwin
import Foundation

class MemoryMonitor: BaseMonitor, MonitorProtocol {
    typealias DataType = MemoryData

    init() {
        super.init(queueLabel: "com.systemmonitor.memory")
    }

    func collect() -> MemoryData {
        do {
            let (used, total) = try getMemoryUsage()
            let pressure = try getMemoryPressure()
            let swapUsed = try getSwapUsage()

            setState(.running)
            return MemoryData(used: used, total: total, pressure: pressure, swapUsed: swapUsed)
        } catch let error as MonitorError {
            setState(.error(error))
            NSLog("Memory Monitor error: \(error.localizedDescription)")
            // Return safe default values
            return MemoryData(used: 0, total: 1, pressure: .normal, swapUsed: 0)
        } catch {
            let monitorError = MonitorError.systemCallFailed(
                "Memory data collection: \(error.localizedDescription)")
            setState(.error(monitorError))
            NSLog("Memory Monitor unexpected error: \(error.localizedDescription)")
            // Return safe default values
            return MemoryData(used: 0, total: 1, pressure: .normal, swapUsed: 0)
        }
    }

    func isAvailable() -> Bool {
        var size = MemoryLayout<UInt64>.size
        var memSize: UInt64 = 0
        let result = sysctlbyname("hw.memsize", &memSize, &size, nil, 0)
        return result == 0 && memSize > 0
    }

    func startMonitoring() {
        setState(.starting)
        setState(.running)
    }

    func stopMonitoring() {
        setState(.stopped)
    }

    // MARK: - Private Methods

    private func getMemoryUsage() throws -> (used: UInt64, total: UInt64) {
        // Get total physical memory
        var size = MemoryLayout<UInt64>.size
        var totalMemory: UInt64 = 0
        var result = sysctlbyname("hw.memsize", &totalMemory, &size, nil, 0)

        guard result == 0 else {
            throw MonitorError.systemCallFailed("sysctlbyname hw.memsize")
        }

        // Get VM statistics
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            throw MonitorError.systemCallFailed("host_statistics64")
        }

        let pageSize = UInt64(vm_page_size)
        let _ = UInt64(vmStats.free_count) * pageSize
        let _ = UInt64(vmStats.inactive_count) * pageSize
        let wireMemory = UInt64(vmStats.wire_count) * pageSize
        let activeMemory = UInt64(vmStats.active_count) * pageSize

        let usedMemory = wireMemory + activeMemory

        return (used: usedMemory, total: totalMemory)
    }

    private func getMemoryPressure() throws -> MemoryPressure {
        // Fallback: calculate pressure based on usage
        let (used, total) = try getMemoryUsage()
        let usagePercentage = Double(used) / Double(total) * 100.0

        if usagePercentage > 90.0 {
            return .critical
        } else if usagePercentage > 75.0 {
            return .warning
        } else {
            return .normal
        }
    }

    private func getSwapUsage() throws -> UInt64 {
        var swapUsage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let result = sysctlbyname("vm.swapusage", &swapUsage, &size, nil, 0)

        guard result == 0 else {
            return 0  // Return 0 if swap info is not available
        }

        return swapUsage.xsu_used
    }
}
