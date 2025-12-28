import Darwin
import Foundation

class CPUMonitor: BaseMonitor, MonitorProtocol {
    typealias DataType = CPUData

    private var previousCPUInfo: [integer_t] = []

    init() {
        super.init(queueLabel: "com.systemmonitor.cpu")
    }

    deinit {
        // Cleanup is handled automatically with Array
    }

    func collect() -> CPUData {
        do {
            let usage = try getCPUUsage()
            let coreCount = try getCoreCount()
            let frequency = try getCPUFrequency()
            let processes = getTopProcesses()

            setState(.running)
            return CPUData(
                usage: usage, coreCount: coreCount, frequency: frequency, processes: processes)
        } catch let error as MonitorError {
            setState(.error(error))
            NSLog("CPU Monitor error: \(error.localizedDescription)")
            // Return safe default values
            return CPUData(usage: 0.0, coreCount: 1, frequency: 0.0, processes: [])
        } catch {
            let monitorError = MonitorError.systemCallFailed(
                "CPU data collection: \(error.localizedDescription)")
            setState(.error(monitorError))
            NSLog("CPU Monitor unexpected error: \(error.localizedDescription)")
            // Return safe default values
            return CPUData(usage: 0.0, coreCount: 1, frequency: 0.0, processes: [])
        }
    }

    func isAvailable() -> Bool {
        var size = MemoryLayout<Int>.size
        var coreCount: Int = 0
        let result = sysctlbyname("hw.ncpu", &coreCount, &size, nil, 0)
        return result == 0 && coreCount > 0
    }

    func startMonitoring() {
        setState(.starting)
        // Initialize CPU info for delta calculations
        _ = try? getCPUUsage()
        setState(.running)
    }

    func stopMonitoring() {
        setState(.stopped)
        previousCPUInfo.removeAll()
    }

    // MARK: - Private Methods

    private func getCPUUsage() throws -> Double {
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0

        let result = host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfo, &cpuInfoCount)

        guard result == KERN_SUCCESS, let info = cpuInfo else {
            throw MonitorError.systemCallFailed("host_processor_info")
        }

        defer {
            vm_deallocate(
                mach_task_self_, vm_address_t(bitPattern: info),
                vm_size_t(Int(cpuInfoCount) * MemoryLayout<integer_t>.size))
        }

        var totalUsage: Double = 0.0

        if !previousCPUInfo.isEmpty && previousCPUInfo.count == Int(cpuInfoCount) {
            // Calculate usage based on delta
            for i in 0..<Int(numCPUs) {
                let currentUser = info[i * Int(CPU_STATE_MAX) + Int(CPU_STATE_USER)]
                let currentSystem = info[i * Int(CPU_STATE_MAX) + Int(CPU_STATE_SYSTEM)]
                let currentIdle = info[i * Int(CPU_STATE_MAX) + Int(CPU_STATE_IDLE)]
                let currentNice = info[i * Int(CPU_STATE_MAX) + Int(CPU_STATE_NICE)]

                let prevUser = previousCPUInfo[i * Int(CPU_STATE_MAX) + Int(CPU_STATE_USER)]
                let prevSystem = previousCPUInfo[i * Int(CPU_STATE_MAX) + Int(CPU_STATE_SYSTEM)]
                let prevIdle = previousCPUInfo[i * Int(CPU_STATE_MAX) + Int(CPU_STATE_IDLE)]
                let prevNice = previousCPUInfo[i * Int(CPU_STATE_MAX) + Int(CPU_STATE_NICE)]

                let totalTicks =
                    (currentUser - prevUser) + (currentSystem - prevSystem)
                    + (currentIdle - prevIdle) + (currentNice - prevNice)
                let usedTicks =
                    (currentUser - prevUser) + (currentSystem - prevSystem)
                    + (currentNice - prevNice)

                if totalTicks > 0 {
                    totalUsage += Double(usedTicks) / Double(totalTicks) * 100.0
                }
            }

            totalUsage /= Double(numCPUs)
        }

        // Store current info for next calculation
        previousCPUInfo = Array(UnsafeBufferPointer(start: info, count: Int(cpuInfoCount)))

        return max(0.0, min(100.0, totalUsage))
    }

    private func getCoreCount() throws -> Int {
        var size = MemoryLayout<Int>.size
        var coreCount: Int = 0
        let result = sysctlbyname("hw.ncpu", &coreCount, &size, nil, 0)

        guard result == 0 else {
            throw MonitorError.systemCallFailed("sysctlbyname hw.ncpu")
        }

        return max(1, coreCount)
    }

    private func getCPUFrequency() throws -> Double {
        var size = MemoryLayout<UInt64>.size
        var frequency: UInt64 = 0
        let result = sysctlbyname("hw.cpufrequency_max", &frequency, &size, nil, 0)

        if result == 0 && frequency > 0 {
            return Double(frequency) / 1_000_000_000.0  // Convert Hz to GHz
        }

        // Fallback: try alternative method or return estimated frequency
        return 2.0  // Default estimate for modern CPUs
    }

    private func getTopProcesses() -> [ProcessInfo] {
        // This is a simplified implementation
        // In a full implementation, you would use proc_listpids() and proc_pidinfo()
        return []
    }
}
