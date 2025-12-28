import Darwin
import Foundation
import IOKit

class GPUMonitor: BaseMonitor, MonitorProtocol {
    typealias DataType = GPUData

    private var powermetricsProcess: Process?
    private var isAppleSilicon: Bool

    init() {
        // Detect if running on Apple Silicon
        var size = MemoryLayout<Int>.size
        var result: Int = 0
        let status = sysctlbyname("hw.optional.arm64", &result, &size, nil, 0)
        self.isAppleSilicon = (status == 0 && result == 1)

        super.init(queueLabel: "com.systemmonitor.gpu")
    }

    deinit {
        stopMonitoring()
        // Ensure process is properly cleaned up
        cleanupProcess()
    }

    private func cleanupProcess() {
        if let process = powermetricsProcess {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
            powermetricsProcess = nil
        }
    }

    func collect() -> GPUData {
        do {
            let usage = try getGPUUsage()
            let (memoryUsed, memoryTotal) = try getGPUMemory()
            let name = try getGPUName()

            return GPUData(
                usage: usage, memoryUsed: memoryUsed, memoryTotal: memoryTotal, name: name)
        } catch {
            // Return default data on error
            return GPUData(usage: 0.0, memoryUsed: 0, memoryTotal: 1, name: "Unknown GPU")
        }
    }

    func isAvailable() -> Bool {
        // Check if powermetrics is available
        let process = Process()
        process.launchPath = "/usr/bin/which"
        process.arguments = ["powermetrics"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        defer {
            // Ensure process is cleaned up
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    func startMonitoring() {
        setState(.starting)
        setState(.running)
    }

    func stopMonitoring() {
        setState(.stopped)
        cleanupProcess()
    }

    // MARK: - Private Methods

    private func getGPUUsage() throws -> Double {
        // 优先使用 IORegistry 的 PerformanceStatistics，不依赖 powermetrics
        if let usage = getGPUUsageFromIORegistry() {
            return usage
        }

        // 回退到 powermetrics
        if isAppleSilicon {
            return try getAppleSiliconGPUUsage()
        } else {
            return try getIntelGPUUsage()
        }
    }

    private func getAppleSiliconGPUUsage() throws -> Double {
        let process = Process()
        process.launchPath = "/usr/bin/powermetrics"
        process.arguments = [
            "-n", "1", "-i", "1000", "--samplers", "gpu_power", "--format", "plist",
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        defer {
            // Ensure process is cleaned up
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw MonitorError.systemCallFailed(
                    "powermetrics failed with status \(process.terminationStatus)")
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            pipe.fileHandleForReading.closeFile()

            if let plist = try PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any],
                let samples = plist["samples"] as? [[String: Any]],
                let firstSample = samples.first,
                let gpuPower = firstSample["gpu_power"] as? [String: Any],
                let clusters = gpuPower["clusters"] as? [[String: Any]]
            {

                var totalUsage: Double = 0.0
                var clusterCount = 0

                for cluster in clusters {
                    // idle_ratio: 0.0~1.0，取(1-idle_ratio)*100 作为使用率百分比
                    if let idle = cluster["idle_ratio"] as? Double {
                        totalUsage += max(0.0, min(100.0, (1.0 - idle) * 100.0))
                        clusterCount += 1
                    } else if let active = cluster["active_ratio"] as? Double {
                        totalUsage += max(0.0, min(100.0, active * 100.0))
                        clusterCount += 1
                    }
                }

                return clusterCount > 0 ? totalUsage / Double(clusterCount) : 0.0
            }

            return 0.0
        } catch {
            throw MonitorError.systemCallFailed(
                "powermetrics execution failed: \(error.localizedDescription)")
        }
    }

    private func getIntelGPUUsage() throws -> Double {
        // For Intel GPUs, we'll use a simplified approach
        // In a production app, you might want to use IOKit to access GPU performance counters
        let process = Process()
        process.launchPath = "/usr/bin/powermetrics"
        process.arguments = [
            "-n", "1", "-i", "1000", "--samplers", "gpu_power", "--format", "plist",
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        defer {
            // Ensure process is cleaned up
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                // If powermetrics fails, return 0 instead of throwing
                return 0.0
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            pipe.fileHandleForReading.closeFile()

            if let plist = try PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any],
                let samples = plist["samples"] as? [[String: Any]],
                let firstSample = samples.first,
                let gpuPower = firstSample["gpu_power"] as? [String: Any]
            {
                if let usage = gpuPower["gpu_usage"] as? Double {
                    return max(0.0, min(100.0, usage))
                }
                // 某些机型可能提供 clusters 的 idle_ratio，与 Apple Silicon 类似
                if let clusters = gpuPower["clusters"] as? [[String: Any]] {
                    var total: Double = 0.0
                    var cnt = 0
                    for cluster in clusters {
                        if let idle = cluster["idle_ratio"] as? Double {
                            total += max(0.0, min(100.0, (1.0 - idle) * 100.0))
                            cnt += 1
                        }
                    }
                    if cnt > 0 { return total / Double(cnt) }
                }
            }

            return 0.0
        } catch {
            // Return 0 on error instead of throwing
            return 0.0
        }
    }

    /// 使用 IORegistry 读取 GPU 使用率（优先），读取 IOAccelerator* 的 PerformanceStatistics
    private func getGPUUsageFromIORegistry() -> Double? {
        let classes = [
            "IOAccelerator", "IOAcceleratorBSDClient", "AGXAccelerator", "AMDRadeonAccelerator",
        ]

        for cls in classes {
            var iterator: io_iterator_t = 0
            let result = IOServiceGetMatchingServices(
                kIOMainPortDefault, IOServiceMatching(cls), &iterator)
            guard result == KERN_SUCCESS else { continue }

            defer { IOObjectRelease(iterator) }

            var service = IOIteratorNext(iterator)
            while service != 0 {
                defer { IOObjectRelease(service) }
                if let dict = IORegistryEntryCreateCFProperty(
                    service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any]
                {
                    // 常见键名："Device Utilization %"、"GPU Busy"（0~1）
                    if let percent = dict["Device Utilization %"] as? Double {
                        return max(0.0, min(100.0, percent))
                    }
                    if let busy = dict["GPU Busy"] as? Double {
                        return max(0.0, min(100.0, busy * 100.0))
                    }
                    if let renderer = dict["Renderer Utilization %"] as? Double {
                        return max(0.0, min(100.0, renderer))
                    }
                    if let tiler = dict["Tiler Utilization %"] as? Double {
                        // 若仅有 Tiler，则也返回该值
                        return max(0.0, min(100.0, tiler))
                    }
                }
                service = IOIteratorNext(iterator)
            }
        }

        return nil
    }

    private func getGPUMemory() throws -> (used: UInt64, total: UInt64) {
        if isAppleSilicon {
            return try getAppleSiliconGPUMemory()
        } else {
            return try getIntelGPUMemory()
        }
    }

    private func getAppleSiliconGPUMemory() throws -> (used: UInt64, total: UInt64) {
        // Apple Silicon GPU 与系统共享内存，没有公开 API 给出实时显存使用。
        // 尝试从 IORegistry 读取 VRAM/显存信息，如缺失则回退为系统内存的一部分作为总量估计，已用估计为 0。
        if let vramMB = getVRAMTotalMBFromIORegistry() {
            let total = UInt64(vramMB) * 1024 * 1024
            return (used: 0, total: total)
        }

        var size = MemoryLayout<UInt64>.size
        var totalMemory: UInt64 = 0
        let result = sysctlbyname("hw.memsize", &totalMemory, &size, nil, 0)
        guard result == 0 else { throw MonitorError.systemCallFailed("sysctlbyname hw.memsize") }

        // Conservative estimate: 1/8 of system memory
        let estimatedTotal = totalMemory / 8
        return (used: 0, total: estimatedTotal)
    }

    private func getIntelGPUMemory() throws -> (used: UInt64, total: UInt64) {
        // 先尝试通过 IORegistry/system_profiler 获取离散显卡 VRAM；若为集显则保守估计为系统内存的一部分。
        if let vramMB = getVRAMTotalMBFromIORegistry() {
            let total = UInt64(vramMB) * 1024 * 1024
            return (used: 0, total: total)
        }
        if let vramMB = getVRAMTotalMBFromSystemProfiler() {
            let total = UInt64(vramMB) * 1024 * 1024
            return (used: 0, total: total)
        }

        var size = MemoryLayout<UInt64>.size
        var totalMemory: UInt64 = 0
        let result = sysctlbyname("hw.memsize", &totalMemory, &size, nil, 0)
        guard result == 0 else { throw MonitorError.systemCallFailed("sysctlbyname hw.memsize") }

        let estimatedTotal = totalMemory / 8
        return (used: 0, total: estimatedTotal)
    }

    private func getGPUName() throws -> String {
        // 优先从 IORegistry 读取 GPU 型号
        if let name = getGPUNameFromIORegistry() { return name }

        // 回退到 system_profiler
        let process = Process()
        process.launchPath = "/usr/sbin/system_profiler"
        process.arguments = ["SPDisplaysDataType", "-xml"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return isAppleSilicon ? "Apple GPU" : "Intel/AMD GPU"
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            pipe.fileHandleForReading.closeFile()

            if let plist = try PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [[String: Any]],
                let displays = plist.first?["_items"] as? [[String: Any]],
                let firstDisplay = displays.first
            {
                if let model = firstDisplay["sppci_model"] as? String {
                    return model
                }
                if let vendor = firstDisplay["_name"] as? String {
                    return vendor
                }
            }

            return isAppleSilicon ? "Apple GPU" : "Intel/AMD GPU"
        } catch {
            return isAppleSilicon ? "Apple GPU" : "Intel/AMD GPU"
        }
    }

    // MARK: - IORegistry helpers

    private func getGPUNameFromIORegistry() -> String? {
        let classes = [
            "IOAccelerator", "IOAcceleratorBSDClient", "AGXAccelerator", "AMDRadeonAccelerator",
            "IOPCIDevice",
        ]
        for cls in classes {
            var iterator: io_iterator_t = 0
            let result = IOServiceGetMatchingServices(
                kIOMainPortDefault, IOServiceMatching(cls), &iterator)
            guard result == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }

            var service = IOIteratorNext(iterator)
            while service != 0 {
                defer { IOObjectRelease(service) }
                // 尝试读取 model 属性（可能为 CFData 或 CFString）
                if let cfString = IORegistryEntryCreateCFProperty(
                    service, "model" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
                {
                    if CFGetTypeID(cfString) == CFStringGetTypeID() {
                        return cfString as? String
                    } else if CFGetTypeID(cfString) == CFDataGetTypeID(),
                        let data = cfString as? Data, let str = String(data: data, encoding: .utf8)
                    {
                        return str
                    }
                }
                // 备用：IOName 或 Vendor/Device strings
                if let name = IORegistryEntryCreateCFProperty(
                    service, "IOName" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
                    as? String
                {
                    return name
                }
                service = IOIteratorNext(iterator)
            }
        }
        return nil
    }

    private func getVRAMTotalMBFromIORegistry() -> Int? {
        let classes = [
            "IOAccelerator", "IOAcceleratorBSDClient", "AMDRadeonAccelerator", "IOPCIDevice",
        ]
        for cls in classes {
            var iterator: io_iterator_t = 0
            let result = IOServiceGetMatchingServices(
                kIOMainPortDefault, IOServiceMatching(cls), &iterator)
            guard result == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }

            var service = IOIteratorNext(iterator)
            while service != 0 {
                defer { IOObjectRelease(service) }
                // 常见属性名：VRAM,totalMB 或 VRAM,Total
                if let totalMB = IORegistryEntryCreateCFProperty(
                    service, "VRAM,totalMB" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? Int
                {
                    return totalMB
                }
                if let totalMB = IORegistryEntryCreateCFProperty(
                    service, "VRAM,Total" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
                    as? Int
                {
                    return totalMB
                }
                service = IOIteratorNext(iterator)
            }
        }
        return nil
    }

    private func getVRAMTotalMBFromSystemProfiler() -> Int? {
        let process = Process()
        process.launchPath = "/usr/sbin/system_profiler"
        process.arguments = ["SPDisplaysDataType", "-xml"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            pipe.fileHandleForReading.closeFile()
            if let plist = try PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [[String: Any]],
                let displays = plist.first?["_items"] as? [[String: Any]],
                let first = displays.first
            {
                // sppci_vram 形如 "4 GB"，解析数字和单位
                if let vramStr = first["sppci_vram"] as? String {
                    return parseMB(fromVramString: vramStr)
                }
            }
        } catch { return nil }
        return nil
    }

    private func parseMB(fromVramString s: String) -> Int? {
        // 支持 "4096 MB" 或 "4 GB"
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let parts = trimmed.split(separator: " ")
        guard parts.count >= 2, let value = Double(parts[0]) else { return nil }
        let unit = parts[1]
        if unit.hasPrefix("GB") { return Int(value * 1024.0) }
        if unit.hasPrefix("MB") { return Int(value) }
        return nil
    }
}
