import Foundation
import IOKit
import IOKit.storage

class DiskMonitor: BaseMonitor, MonitorProtocol {
    typealias DataType = [DiskData]
    
    private var previousIOStats: [String: DiskIOStats] = [:]
    private var lastUpdateTime: Date?
    
    private struct DiskIOStats {
        let readBytes: UInt64
        let writeBytes: UInt64
        let timestamp: Date
    }
    
    init() {
        super.init(queueLabel: "com.systemmonitor.disk")
    }
    
    deinit {
        stopMonitoring()
    }
    
    func collect() -> [DiskData] {
        do {
            let diskSpaceInfo = try getDiskSpaceInfo()
            let ioSpeeds = try getDiskIOSpeeds()
            
            var diskDataArray: [DiskData] = []
            
            for spaceInfo in diskSpaceInfo {
                let readSpeed = ioSpeeds[spaceInfo.name]?.readSpeed ?? 0
                let writeSpeed = ioSpeeds[spaceInfo.name]?.writeSpeed ?? 0
                
                let diskData = DiskData(
                    name: spaceInfo.name,
                    mountPoint: spaceInfo.mountPoint,
                    used: spaceInfo.used,
                    total: spaceInfo.total,
                    readSpeed: readSpeed,
                    writeSpeed: writeSpeed
                )
                
                diskDataArray.append(diskData)
            }
            
            return diskDataArray
        } catch {
            // Return empty array on error
            return []
        }
    }
    
    func isAvailable() -> Bool {
        // Check if we can access file system information
        let fileManager = FileManager.default
        let mountedVolumes = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [])
        return mountedVolumes != nil && !mountedVolumes!.isEmpty
    }
    
    func startMonitoring() {
        setState(.starting)
        
        // Initialize IO stats for speed calculations
        if let initialStats = try? getCurrentIOStats() {
            previousIOStats = initialStats
            lastUpdateTime = Date()
        }
        
        setState(.running)
    }
    
    func stopMonitoring() {
        setState(.stopped)
        previousIOStats.removeAll()
        lastUpdateTime = nil
    }
    
    // MARK: - Private Methods
    
    private struct DiskSpaceInfo {
        let name: String
        let mountPoint: String
        let used: UInt64
        let total: UInt64
    }
    
    private func getDiskSpaceInfo() throws -> [DiskSpaceInfo] {
        let fileManager = FileManager.default
        var diskInfoArray: [DiskSpaceInfo] = []
        
        guard let mountedVolumes = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: [
                .volumeNameKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
                .volumeIsLocalKey,
                .volumeIsInternalKey
            ],
            options: [.skipHiddenVolumes]
        ) else {
            throw MonitorError.systemCallFailed("mountedVolumeURLs")
        }
        
        for volumeURL in mountedVolumes {
            do {
                let resourceValues = try volumeURL.resourceValues(forKeys: [
                    .volumeNameKey,
                    .volumeTotalCapacityKey,
                    .volumeAvailableCapacityKey,
                    .volumeIsLocalKey,
                    .volumeIsInternalKey
                ])
                
                // Skip non-local or network volumes
                guard let isLocal = resourceValues.volumeIsLocal, isLocal else {
                    continue
                }
                
                let volumeName = resourceValues.volumeName ?? "Unknown"
                let totalCapacity = UInt64(resourceValues.volumeTotalCapacity ?? 0)
                let availableCapacity = UInt64(resourceValues.volumeAvailableCapacity ?? 0)
                let usedCapacity = totalCapacity > availableCapacity ? totalCapacity - availableCapacity : 0
                
                // Skip very small volumes (likely system volumes)
                guard totalCapacity > 1_000_000_000 else { // 1GB minimum
                    continue
                }
                
                let diskInfo = DiskSpaceInfo(
                    name: volumeName,
                    mountPoint: volumeURL.path,
                    used: usedCapacity,
                    total: totalCapacity
                )
                
                diskInfoArray.append(diskInfo)
            } catch {
                // Skip volumes that can't be read
                continue
            }
        }
        
        return diskInfoArray
    }
    
    private func getDiskIOSpeeds() throws -> [String: (readSpeed: UInt64, writeSpeed: UInt64)] {
        let currentStats = try getCurrentIOStats()
        var speeds: [String: (readSpeed: UInt64, writeSpeed: UInt64)] = [:]
        
        guard !previousIOStats.isEmpty,
              let lastTime = lastUpdateTime else {
            // First measurement, store current stats and return 0 speeds
            previousIOStats = currentStats
            lastUpdateTime = Date()
            return [:]
        }
        
        let timeDelta = Date().timeIntervalSince(lastTime)
        
        // Avoid division by zero
        guard timeDelta > 0.1 else {
            return [:]
        }
        
        for (diskName, currentStat) in currentStats {
            if let previousStat = previousIOStats[diskName] {
                let readBytesDelta = currentStat.readBytes >= previousStat.readBytes ?
                    currentStat.readBytes - previousStat.readBytes : 0
                let writeBytesDelta = currentStat.writeBytes >= previousStat.writeBytes ?
                    currentStat.writeBytes - previousStat.writeBytes : 0
                
                let readSpeed = UInt64(Double(readBytesDelta) / timeDelta)
                let writeSpeed = UInt64(Double(writeBytesDelta) / timeDelta)
                
                speeds[diskName] = (readSpeed: readSpeed, writeSpeed: writeSpeed)
            }
        }
        
        // Update previous stats for next calculation
        previousIOStats = currentStats
        lastUpdateTime = Date()
        
        return speeds
    }
    
    private func getCurrentIOStats() throws -> [String: DiskIOStats] {
        var stats: [String: DiskIOStats] = [:]
        
        // Get IOKit registry iterator for storage devices
        let matchingDict = IOServiceMatching("IOBlockStorageDriver")
        var iterator: io_iterator_t = 0
        
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        guard result == KERN_SUCCESS else {
            throw MonitorError.systemCallFailed("IOServiceGetMatchingServices")
        }
        
        defer {
            IOObjectRelease(iterator)
        }
        
        var service: io_registry_entry_t = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            
            // Get the device name
            var deviceName: io_name_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
            let nameResult = IORegistryEntryGetName(service, &deviceName)
            guard nameResult == KERN_SUCCESS else { continue }
            let name = withUnsafePointer(to: &deviceName) {
                $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<io_name_t>.size) {
                    String(cString: $0)
                }
            }
            
            // Get IO statistics
            var properties: Unmanaged<CFMutableDictionary>?
            let propertiesResult = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
            
            guard propertiesResult == KERN_SUCCESS,
                  let propertiesDict = properties?.takeRetainedValue() as? [String: Any] else {
                continue
            }
            
            // Look for statistics in the properties
            if let statistics = propertiesDict["Statistics"] as? [String: Any] {
                let readBytes = statistics["Bytes read"] as? UInt64 ?? 0
                let writeBytes = statistics["Bytes written"] as? UInt64 ?? 0
                
                let ioStats = DiskIOStats(
                    readBytes: readBytes,
                    writeBytes: writeBytes,
                    timestamp: Date()
                )
                
                stats[name] = ioStats
            }
        }
        
        // If IOKit method doesn't work, try alternative approach using iostat
        if stats.isEmpty {
            return try getIOStatsFromCommand()
        }
        
        return stats
    }
    
    private func getIOStatsFromCommand() throws -> [String: DiskIOStats] {
        // Fallback: use iostat command if available
        let process = Process()
        process.launchPath = "/usr/sbin/iostat"
        process.arguments = ["-d", "-c", "1"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            
            guard process.terminationStatus == 0 else {
                return [:]
            }
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            return parseIOStatOutput(output)
        } catch {
            return [:]
        }
    }
    
    private func parseIOStatOutput(_ output: String) -> [String: DiskIOStats] {
        var stats: [String: DiskIOStats] = [:]
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            let components = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
            
            // Look for disk device lines (typically start with "disk")
            if components.count >= 3 && components[0].hasPrefix("disk") {
                let deviceName = components[0]
                
                // Parse read and write bytes (this is a simplified parser)
                // In a production app, you'd want more robust parsing
                let readBytes: UInt64 = 0  // iostat output format varies
                let writeBytes: UInt64 = 0
                
                let ioStats = DiskIOStats(
                    readBytes: readBytes,
                    writeBytes: writeBytes,
                    timestamp: Date()
                )
                
                stats[deviceName] = ioStats
            }
        }
        
        return stats
    }
    
    override func handleSystemShutdown() {
        stopMonitoring()
    }
}