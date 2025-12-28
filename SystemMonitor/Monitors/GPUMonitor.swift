import Foundation
import Darwin
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
                    if let usage = cluster["idle_ratio"] as? Double {
                        totalUsage += (1.0 - usage) * 100.0
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
                let gpuPower = firstSample["gpu_power"] as? [String: Any],
                let usage = gpuPower["gpu_usage"] as? Double
            {
                return usage
            }

            return 0.0
        } catch {
            // Return 0 on error instead of throwing
            return 0.0
        }
    }

    private func getGPUMemory() throws -> (used: UInt64, total: UInt64) {
        if isAppleSilicon {
            return try getAppleSiliconGPUMemory()
        } else {
            return try getIntelGPUMemory()
        }
    }

    private func getAppleSiliconGPUMemory() throws -> (used: UInt64, total: UInt64) {
        // Apple Silicon GPUs share system memory
        // We'll estimate based on system memory
        var size = MemoryLayout<UInt64>.size
        var totalMemory: UInt64 = 0
        let result = sysctlbyname("hw.memsize", &totalMemory, &size, nil, 0)

        guard result == 0 else {
            throw MonitorError.systemCallFailed("sysctlbyname hw.memsize")
        }

        // Estimate GPU memory as a portion of system memory
        let estimatedGPUMemory = totalMemory / 4  // Rough estimate
        let estimatedUsed = estimatedGPUMemory / 10  // Very rough usage estimate

        return (used: estimatedUsed, total: estimatedGPUMemory)
    }

    private func getIntelGPUMemory() throws -> (used: UInt64, total: UInt64) {
        // For Intel integrated GPUs, they also typically share system memory
        // This is a simplified implementation
        var size = MemoryLayout<UInt64>.size
        var totalMemory: UInt64 = 0
        let result = sysctlbyname("hw.memsize", &totalMemory, &size, nil, 0)

        guard result == 0 else {
            throw MonitorError.systemCallFailed("sysctlbyname hw.memsize")
        }

        // Estimate GPU memory for Intel integrated graphics
        let estimatedGPUMemory = totalMemory / 8  // Conservative estimate
        let estimatedUsed = estimatedGPUMemory / 20  // Very rough usage estimate

        return (used: estimatedUsed, total: estimatedGPUMemory)
    }

    private func getGPUName() throws -> String {
        // Try to get GPU name using system_profiler
        let process = Process()
        process.launchPath = "/usr/sbin/system_profiler"
        process.arguments = ["SPDisplaysDataType", "-xml"]

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
                return isAppleSilicon ? "Apple GPU" : "Intel GPU"
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            pipe.fileHandleForReading.closeFile()

            if let plist = try PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [[String: Any]],
                let displays = plist.first?["_items"] as? [[String: Any]],
                let firstDisplay = displays.first,
                let chipsetModel = firstDisplay["sppci_model"] as? String
            {
                return chipsetModel
            }

            return isAppleSilicon ? "Apple GPU" : "Intel GPU"
        } catch {
            return isAppleSilicon ? "Apple GPU" : "Intel GPU"
        }
    }
}
