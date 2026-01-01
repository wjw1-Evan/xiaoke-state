import Foundation
import IOKit

class TemperatureMonitor: BaseMonitor, MonitorProtocol {
    typealias DataType = TemperatureData

    private var isAppleSilicon: Bool
    private var smcConnection: io_connect_t = 0

    init() {
        var size = MemoryLayout<Int>.size
        var result: Int = 0
        let status = sysctlbyname("hw.optional.arm64", &result, &size, nil, 0)
        self.isAppleSilicon = (status == 0 && result == 1)
        super.init(queueLabel: "com.systemmonitor.temperature")
    }

    deinit {
        stopMonitoring()
    }

    func collect() -> TemperatureData {
        do {
            let cpuTemp = try getCPUTemperature()
            let gpuTemp = try getGPUTemperature()
            let fanSpeed = try getFanSpeed()
            return TemperatureData(
                cpuTemperature: cpuTemp, gpuTemperature: gpuTemp, fanSpeed: fanSpeed)
        } catch {
            return TemperatureData()
        }
    }

    /// Temperature and fan information is considered logically available on all supported macOS
    /// systems. The monitor will internally degrade gracefully (returning nil / default values)
    /// when powermetrics or pmset are not usable.
    func isAvailable() -> Bool {
        return true
    }

    func startMonitoring() {
        setState(.starting)
        if !isAppleSilicon {
            _ = connectToSMC()
        }
        setState(.running)
    }

    func stopMonitoring() {
        setState(.stopped)
        if smcConnection != 0 {
            IOServiceClose(smcConnection)
            smcConnection = 0
        }
    }

    // MARK: - Private Helpers

    private func getCPUTemperature() throws -> Double? {
        if isAppleSilicon {
            return try getAppleSiliconCPUTemperature()
        } else {
            return try getIntelCPUTemperature()
        }
    }

    private func getGPUTemperature() throws -> Double? {
        if isAppleSilicon {
            return try getAppleSiliconGPUTemperature()
        } else {
            return try getIntelGPUTemperature()
        }
    }

    private func getFanSpeed() throws -> Int? {
        if let rpm = getFanSpeedFromIORegistry() {
            return rpm
        }

        if let pmsetOutput = runPmsetThermlog(), let rpm = parseFanSpeed(from: pmsetOutput) {
            return rpm
        }

        if let sample = readPowermetricsSample() {
            if let fans = sample["fans"] as? [[String: Any]] {
                for fan in fans {
                    if let rpm = fan["actual"] as? Double { return Int(rpm) }
                    if let rpm = fan["speed"] as? Double { return Int(rpm) }
                }
            }

            if let smc = sample["smc"] as? [String: Any] {
                let fanKeys = ["F0Ac", "F1Ac", "F0Tg", "F1Tg"]
                for key in fanKeys {
                    if let speed = smc[key] as? Double { return Int(speed) }
                }
                for (key, value) in smc where key.hasPrefix("F") && key.contains("Ac") {
                    if let speed = value as? Double { return Int(speed) }
                }
            }
        }

        return nil
    }

    // MARK: - Apple Silicon

    private func getAppleSiliconCPUTemperature() throws -> Double? {
        if let sample = readPowermetricsSample(), let smc = sample["smc"] as? [String: Any] {
            for (key, value) in smc {
                if key.contains("CPU") && key.contains("temp") || key.hasPrefix("TC") {
                    if let temp = value as? Double { return temp }
                }
            }
            for (key, value) in smc {
                if key.lowercased().contains("temp"), let temp = value as? Double,
                    temp > 0 && temp < 150
                {
                    return temp
                }
            }
        }

        if let pmsetOutput = runPmsetThermlog(), let temp = parseCPUTemperature(from: pmsetOutput) {
            return temp
        }

        return nil
    }

    private func getAppleSiliconGPUTemperature() throws -> Double? {
        if let sample = readPowermetricsSample(), let smc = sample["smc"] as? [String: Any] {
            for (key, value) in smc {
                if key.contains("GPU") && key.contains("temp") || key.hasPrefix("TG") {
                    if let temp = value as? Double { return temp }
                }
            }
        }

        if let pmsetOutput = runPmsetThermlog(), let temp = parseGPUTemperature(from: pmsetOutput) {
            return temp
        }

        return nil
    }

    // MARK: - Intel

    private func getIntelCPUTemperature() throws -> Double? {
        if let sample = readPowermetricsSample(), let smc = sample["smc"] as? [String: Any] {
            let cpuTempKeys = ["TC0P", "TC0H", "TC0D", "TCAD", "TCAH"]
            for key in cpuTempKeys {
                if let temp = smc[key] as? Double { return temp }
            }
        }

        if smcConnection != 0 {
            if let temp = getSMCTemperature(key: "TC0P") {
                return temp
            }
        }

        if let pmsetOutput = runPmsetThermlog(), let temp = parseCPUTemperature(from: pmsetOutput) {
            return temp
        }

        return nil
    }

    private func getIntelGPUTemperature() throws -> Double? {
        if let sample = readPowermetricsSample(), let smc = sample["smc"] as? [String: Any] {
            let gpuTempKeys = ["TGDD", "TG0P", "TG0D", "TG1D"]
            for key in gpuTempKeys {
                if let temp = smc[key] as? Double { return temp }
            }
        }

        if let pmsetOutput = runPmsetThermlog(), let temp = parseGPUTemperature(from: pmsetOutput) {
            return temp
        }

        return nil
    }

    // MARK: - powermetrics shared

    private func readPowermetricsSample() -> [String: Any]? {
        let process = Process()
        process.launchPath = "/usr/bin/powermetrics"
        process.arguments = ["-n", "1", "-i", "1000", "--samplers", "smc", "--format", "plist"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let plist = try PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any],
                let samples = plist["samples"] as? [[String: Any]],
                let firstSample = samples.first
            {
                return firstSample
            }
        } catch {
            return nil
        }

        return nil
    }

    // MARK: - IORegistry fan lookup

    private func getFanSpeedFromIORegistry() -> Int? {
        let classes = ["AppleSMCFan", "AppleFan", "IOPlatformFan"]

        for cls in classes {
            var iterator: io_iterator_t = 0
            let result = IOServiceGetMatchingServices(
                kIOMainPortDefault, IOServiceMatching(cls), &iterator)
            guard result == KERN_SUCCESS else { continue }

            defer { IOObjectRelease(iterator) }

            var service = IOIteratorNext(iterator)
            while service != 0 {
                defer { IOObjectRelease(service) }

                if let rpm = IORegistryEntryCreateCFProperty(
                    service, "current-speed" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? Int
                {
                    return rpm
                }

                if let rpm = IORegistryEntryCreateCFProperty(
                    service, "actual-speed" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? Int
                {
                    return rpm
                }

                service = IOIteratorNext(iterator)
            }
        }

        return nil
    }

    // MARK: - pmset thermlog fallback

    private func runPmsetThermlog() -> String? {
        let process = Process()
        process.launchPath = "/bin/sh"
        process.arguments = ["-c", "/usr/bin/pmset -g thermlog | head -n 12"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func parseCPUTemperature(from text: String) -> Double? {
        if let match = text.range(
            of: "CPU die temperature=([0-9]+\\.?[0-9]*)C", options: .regularExpression)
        {
            let value = text[match]
            if let numberRange = value.range(of: "[0-9]+\\.?[0-9]*", options: .regularExpression) {
                return Double(value[numberRange])
            }
        }
        return nil
    }

    private func parseGPUTemperature(from text: String) -> Double? {
        if let match = text.range(
            of: "GPU die temperature=([0-9]+\\.?[0-9]*)C", options: .regularExpression)
        {
            let value = text[match]
            if let numberRange = value.range(of: "[0-9]+\\.?[0-9]*", options: .regularExpression) {
                return Double(value[numberRange])
            }
        }
        return nil
    }

    private func parseFanSpeed(from text: String) -> Int? {
        if let match = text.range(of: "Fan: ([0-9]+) rpm", options: .regularExpression) {
            let value = text[match]
            if let numberRange = value.range(of: "[0-9]+", options: .regularExpression) {
                return Int(value[numberRange])
            }
        }
        return nil
    }

    // MARK: - SMC (Intel)

    private func connectToSMC() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }

        let result = IOServiceOpen(service, mach_task_self_, 0, &smcConnection)
        IOObjectRelease(service)

        return result == kIOReturnSuccess
    }

    private func getSMCTemperature(key: String) -> Double? {
        // Stubbed SMC call placeholder
        return nil
    }

    override func handleSystemShutdown() {
        stopMonitoring()
    }
}
