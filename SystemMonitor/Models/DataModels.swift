import Foundation

// MARK: - Performance Data (from PerformanceMonitor)
/// Performance data for the application itself
struct PerformanceData {
    let cpuUsagePercent: Double  // 0.0 - 100.0
    let memoryUsageBytes: UInt64  // bytes
    let threadCount: Int  // number of threads
    let timestamp: Date

    /// Memory usage in megabytes for easier reading
    var memoryUsageMB: Double {
        return Double(memoryUsageBytes) / (1024 * 1024)
    }
}

// MARK: - System Data Container
struct SystemData {
    let cpu: CPUData
    let gpu: GPUData?
    let memory: MemoryData
    let disk: [DiskData]
    let temperature: TemperatureData?
    let network: NetworkData?
    let performance: PerformanceData?
    let timestamp: Date

    init(
        cpu: CPUData,
        gpu: GPUData? = nil,
        memory: MemoryData,
        disk: [DiskData] = [],
        temperature: TemperatureData? = nil,
        network: NetworkData? = nil,
        performance: PerformanceData? = nil
    ) {
        self.cpu = cpu
        self.gpu = gpu
        self.memory = memory
        self.disk = disk
        self.temperature = temperature
        self.network = network
        self.performance = performance
        self.timestamp = Date()
    }
}

// MARK: - CPU Data
struct CPUData {
    let usage: Double  // 0.0 - 100.0
    let coreCount: Int
    let frequency: Double  // GHz
    let processes: [ProcessInfo]

    init(usage: Double, coreCount: Int, frequency: Double, processes: [ProcessInfo] = []) {
        self.usage = max(0.0, min(100.0, usage))
        self.coreCount = max(1, coreCount)
        self.frequency = max(0.0, frequency)
        self.processes = processes
    }
}

struct ProcessInfo {
    let pid: Int32
    let name: String
    let cpuUsage: Double
}

// MARK: - GPU Data
struct GPUData {
    let usage: Double  // 0.0 - 100.0
    let memoryUsed: UInt64  // bytes
    let memoryTotal: UInt64  // bytes
    let name: String

    init(usage: Double, memoryUsed: UInt64, memoryTotal: UInt64, name: String) {
        self.usage = max(0.0, min(100.0, usage))
        self.memoryUsed = memoryUsed
        self.memoryTotal = max(memoryUsed, memoryTotal)
        self.name = name
    }
}

// MARK: - Memory Data
struct MemoryData {
    let used: UInt64  // bytes
    let total: UInt64  // bytes
    let pressure: MemoryPressure
    let swapUsed: UInt64  // bytes

    init(used: UInt64, total: UInt64, pressure: MemoryPressure, swapUsed: UInt64 = 0) {
        self.used = used
        self.total = max(used, total)
        self.pressure = pressure
        self.swapUsed = swapUsed
    }

    var usagePercentage: Double {
        guard total > 0 else { return 0.0 }
        return Double(used) / Double(total) * 100.0
    }
}

enum MemoryPressure: String, CaseIterable {
    case normal = "Normal"
    case warning = "Warning"
    case critical = "Critical"
}

// MARK: - Disk Data
struct DiskData {
    let name: String
    let mountPoint: String
    let used: UInt64  // bytes
    let total: UInt64  // bytes
    let readSpeed: UInt64  // bytes/sec
    let writeSpeed: UInt64  // bytes/sec

    init(
        name: String, mountPoint: String, used: UInt64, total: UInt64, readSpeed: UInt64 = 0,
        writeSpeed: UInt64 = 0
    ) {
        self.name = name
        self.mountPoint = mountPoint
        self.used = used
        self.total = max(used, total)
        self.readSpeed = readSpeed
        self.writeSpeed = writeSpeed
    }

    var usagePercentage: Double {
        guard total > 0 else { return 0.0 }
        return Double(used) / Double(total) * 100.0
    }
}

// MARK: - Temperature Data
struct TemperatureData {
    let cpuTemperature: Double?  // Celsius
    let gpuTemperature: Double?  // Celsius
    let fanSpeed: Int?  // RPM

    init(cpuTemperature: Double? = nil, gpuTemperature: Double? = nil, fanSpeed: Int? = nil) {
        self.cpuTemperature = cpuTemperature
        self.gpuTemperature = gpuTemperature
        self.fanSpeed = fanSpeed
    }
}

// MARK: - Network Data
struct NetworkData {
    let uploadSpeed: UInt64  // bytes/sec
    let downloadSpeed: UInt64  // bytes/sec
    let totalUploaded: UInt64  // bytes
    let totalDownloaded: UInt64  // bytes

    init(uploadSpeed: UInt64, downloadSpeed: UInt64, totalUploaded: UInt64, totalDownloaded: UInt64)
    {
        self.uploadSpeed = uploadSpeed
        self.downloadSpeed = downloadSpeed
        self.totalUploaded = totalUploaded
        self.totalDownloaded = totalDownloaded
    }
}

// MARK: - Configuration Data Models
struct DisplayOptions {
    var showCPU: Bool
    var showGPU: Bool
    var showMemory: Bool
    var showDisk: Bool
    var showTemperature: Bool
    var showFan: Bool
    var showNetwork: Bool
    var menuBarFormat: MenuBarFormat

    init(
        showCPU: Bool = true,
        showGPU: Bool = true,
        showMemory: Bool = true,
        showDisk: Bool = true,
        showTemperature: Bool = true,
        showFan: Bool = true,
        showNetwork: Bool = true,
        menuBarFormat: MenuBarFormat = .twoLine
    ) {
        self.showCPU = showCPU
        self.showGPU = showGPU
        self.showMemory = showMemory
        self.showDisk = showDisk
        self.showTemperature = showTemperature
        self.showFan = showFan
        self.showNetwork = showNetwork
        self.menuBarFormat = menuBarFormat
    }
}

struct WarningThresholds {
    var cpuUsage: Double
    var memoryUsage: Double
    var temperature: Double

    init(cpuUsage: Double = 80.0, memoryUsage: Double = 80.0, temperature: Double = 80.0) {
        self.cpuUsage = max(0.0, min(100.0, cpuUsage))
        self.memoryUsage = max(0.0, min(100.0, memoryUsage))
        self.temperature = max(0.0, temperature)
    }
}

enum MenuBarFormat: String, CaseIterable {
    case twoLine = "Two-Line"
}

enum SystemComponent {
    case cpu, memory, gpu, temperature, network, disk, performance
}

// MARK: - Display Utilities
extension SystemData {
    /// Returns a user-friendly display string for system data, showing "N/A" for unavailable data
    func displayString(for component: SystemComponent) -> String {
        switch component {
        case .cpu:
            return cpu.usage > 0 ? String(format: "%.1f%%", cpu.usage) : "N/A"
        case .memory:
            return memory.total > 1 ? String(format: "%.1f%%", memory.usagePercentage) : "N/A"
        case .gpu:
            if let gpu = gpu, gpu.usage > 0 {
                return String(format: "%.1f%%", gpu.usage)
            }
            return "N/A"
        case .temperature:
            if let temp = temperature?.cpuTemperature, temp > 0 {
                return String(format: "%.1f°C", temp)
            }
            return "N/A"
        case .network:
            if let net = network {
                return "↑\(formatBytes(net.uploadSpeed))/s ↓\(formatBytes(net.downloadSpeed))/s"
            }
            return "N/A"
        case .disk:
            if !disk.isEmpty {
                let totalUsed = disk.reduce(0) { $0 + $1.used }
                let totalSpace = disk.reduce(0) { $0 + $1.total }
                let percentage =
                    totalSpace > 0 ? Double(totalUsed) / Double(totalSpace) * 100.0 : 0.0
                return String(format: "%.1f%%", percentage)
            }
            return "N/A"
        case .performance:
            if let perf = performance {
                return
                    "CPU: \(String(format: "%.2f", perf.cpuUsagePercent))%, Mem: \(String(format: "%.1f", perf.memoryUsageMB))MB"
            }
            return "N/A"
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
