import Foundation
import QuartzCore
import os.log

/// Monitor for tracking the application's own performance metrics
class PerformanceMonitor: MonitorProtocol {
    typealias DataType = PerformanceData

    // MARK: - Properties
    private let logger = Logger(subsystem: "com.systemmonitor", category: "PerformanceMonitor")
    private var isMonitoring = false

    // Performance tracking
    private var lastCPUTime: Double = 0
    private var lastTimestamp: TimeInterval = 0
    private var performanceHistory: [PerformanceData] = []
    private let maxHistorySize = 60  // Keep 1 minute of history at 1-second intervals

    // Performance limits (from requirements 4.1, 4.2)
    private let maxCPUUsagePercent: Double = 1.0  // 1% CPU usage limit
    private let maxMemoryUsageMB: Double = 50.0  // 50MB memory limit

    // MARK: - MonitorProtocol

    func collect() -> PerformanceData {
        let currentData = collectCurrentPerformanceData()

        // Add to history
        performanceHistory.append(currentData)
        if performanceHistory.count > maxHistorySize {
            performanceHistory.removeFirst()
        }

        return currentData
    }

    func isAvailable() -> Bool {
        return true  // Performance monitoring is always available
    }

    func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true
        lastTimestamp = CACurrentMediaTime()
        lastCPUTime = getCurrentCPUTime()

        logger.info("Performance monitoring started")
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        isMonitoring = false
        logger.info("Performance monitoring stopped")
    }

    func handleSystemSleep() {
        logger.debug("Performance monitoring paused for system sleep")
    }

    func handleSystemWake() {
        // Reset baseline measurements after wake
        lastTimestamp = CACurrentMediaTime()
        lastCPUTime = getCurrentCPUTime()
        logger.debug("Performance monitoring resumed after system wake")
    }
    
    func handleSystemShutdown() {
        stopMonitoring()
    }

    // MARK: - Performance Limit Checking

    /// Check if the application is within performance limits
    func checkPerformanceLimits() -> PerformanceLimitStatus {
        let currentData = collect()

        var violations: [PerformanceLimitViolation] = []

        // Check CPU usage limit
        if currentData.cpuUsagePercent > maxCPUUsagePercent {
            violations.append(
                .cpuUsageExceeded(
                    current: currentData.cpuUsagePercent,
                    limit: maxCPUUsagePercent
                ))
        }

        // Check memory usage limit
        let memoryUsageMB = Double(currentData.memoryUsageBytes) / (1024 * 1024)
        if memoryUsageMB > maxMemoryUsageMB {
            violations.append(
                .memoryUsageExceeded(
                    current: memoryUsageMB,
                    limit: maxMemoryUsageMB
                ))
        }

        return PerformanceLimitStatus(
            isWithinLimits: violations.isEmpty,
            violations: violations,
            currentData: currentData
        )
    }

    /// Get performance statistics over time
    func getPerformanceStatistics() -> PerformanceStatistics {
        guard !performanceHistory.isEmpty else {
            let currentData = collect()
            return PerformanceStatistics(
                averageCPUUsage: currentData.cpuUsagePercent,
                peakCPUUsage: currentData.cpuUsagePercent,
                averageMemoryUsage: currentData.memoryUsageBytes,
                peakMemoryUsage: currentData.memoryUsageBytes,
                sampleCount: 1,
                timeSpan: 0
            )
        }

        let cpuUsages = performanceHistory.map { $0.cpuUsagePercent }
        let memoryUsages = performanceHistory.map { $0.memoryUsageBytes }

        return PerformanceStatistics(
            averageCPUUsage: cpuUsages.reduce(0, +) / Double(cpuUsages.count),
            peakCPUUsage: cpuUsages.max() ?? 0,
            averageMemoryUsage: UInt64(memoryUsages.reduce(0, +) / UInt64(memoryUsages.count)),
            peakMemoryUsage: memoryUsages.max() ?? 0,
            sampleCount: performanceHistory.count,
            timeSpan: TimeInterval(performanceHistory.count)
        )
    }

    // MARK: - Private Methods

    private func collectCurrentPerformanceData() -> PerformanceData {
        let currentTime = CACurrentMediaTime()
        let currentCPUTime = getCurrentCPUTime()

        // Calculate CPU usage percentage
        let cpuUsagePercent: Double
        if lastTimestamp > 0 && currentTime > lastTimestamp {
            let timeDelta = currentTime - lastTimestamp
            let cpuDelta = currentCPUTime - lastCPUTime
            cpuUsagePercent = min(100.0, max(0.0, (cpuDelta / timeDelta) * 100.0))
        } else {
            cpuUsagePercent = 0.0
        }

        // Update for next calculation
        lastTimestamp = currentTime
        lastCPUTime = currentCPUTime

        // Get memory usage
        let memoryUsage = getCurrentMemoryUsage()

        // Get thread count
        let threadCount = getCurrentThreadCount()

        return PerformanceData(
            cpuUsagePercent: cpuUsagePercent,
            memoryUsageBytes: memoryUsage,
            threadCount: threadCount,
            timestamp: Date()
        )
    }

    private func getCurrentCPUTime() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            logger.error("Failed to get CPU time: \(result)")
            return 0.0
        }

        return Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1_000_000.0
            + Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1_000_000.0
    }

    private func getCurrentMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            logger.error("Failed to get memory usage: \(result)")
            return 0
        }

        return UInt64(info.resident_size)
    }

    private func getCurrentThreadCount() -> Int {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0

        let result = task_threads(mach_task_self_, &threadList, &threadCount)

        if result == KERN_SUCCESS {
            // Clean up the thread list
            if let list = threadList {
                vm_deallocate(
                    mach_task_self_, vm_address_t(bitPattern: list),
                    vm_size_t(threadCount * UInt32(MemoryLayout<thread_t>.size)))
            }
            return Int(threadCount)
        } else {
            logger.error("Failed to get thread count: \(result)")
            return 0
        }
    }
}

// MARK: - Data Models

/// Performance statistics over time
struct PerformanceStatistics {
    let averageCPUUsage: Double
    let peakCPUUsage: Double
    let averageMemoryUsage: UInt64
    let peakMemoryUsage: UInt64
    let sampleCount: Int
    let timeSpan: TimeInterval  // seconds

    /// Average memory usage in megabytes
    var averageMemoryUsageMB: Double {
        return Double(averageMemoryUsage) / (1024 * 1024)
    }

    /// Peak memory usage in megabytes
    var peakMemoryUsageMB: Double {
        return Double(peakMemoryUsage) / (1024 * 1024)
    }
}

/// Performance limit violation types
enum PerformanceLimitViolation {
    case cpuUsageExceeded(current: Double, limit: Double)
    case memoryUsageExceeded(current: Double, limit: Double)

    var description: String {
        switch self {
        case .cpuUsageExceeded(let current, let limit):
            return
                "CPU usage exceeded: \(String(format: "%.2f", current))% > \(String(format: "%.1f", limit))%"
        case .memoryUsageExceeded(let current, let limit):
            return
                "Memory usage exceeded: \(String(format: "%.1f", current))MB > \(String(format: "%.1f", limit))MB"
        }
    }
}

/// Status of performance limit checking
struct PerformanceLimitStatus {
    let isWithinLimits: Bool
    let violations: [PerformanceLimitViolation]
    let currentData: PerformanceData

    /// Human-readable description of the status
    var description: String {
        if isWithinLimits {
            return
                "Performance within limits: CPU \(String(format: "%.2f", currentData.cpuUsagePercent))%, Memory \(String(format: "%.1f", currentData.memoryUsageMB))MB"
        } else {
            let violationDescriptions = violations.map { $0.description }.joined(separator: "; ")
            return "Performance limit violations: \(violationDescriptions)"
        }
    }
}
