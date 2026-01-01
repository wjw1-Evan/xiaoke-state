import Foundation
import os.log

/// Manages adaptive data collection frequency based on system load and performance
class AdaptiveFrequencyManager {

    // MARK: - Properties
    private let logger = Logger(
        subsystem: "com.systemmonitor", category: "AdaptiveFrequencyManager")

    // Frequency settings
    private var baseUpdateInterval: TimeInterval = 2.0
    private var currentUpdateInterval: TimeInterval = 2.0
    private let minUpdateInterval: TimeInterval = 1.0
    private let maxUpdateInterval: TimeInterval = 10.0

    // Adaptive thresholds
    private let highLoadCPUThreshold: Double = 70.0
    private let highLoadMemoryThreshold: Double = 80.0
    private let lowPowerModeMultiplier: Double = 2.0
    private let highLoadMultiplier: Double = 0.5  // Increase frequency when system is busy

    // System state tracking
    private var isLowPowerMode: Bool = false
    private var isHighSystemLoad: Bool = false
    private var consecutiveHighLoadSamples: Int = 0
    private var consecutiveLowLoadSamples: Int = 0
    private let loadSampleThreshold: Int = 3  // Require 3 consecutive samples to change frequency

    // Callbacks
    var onFrequencyChanged: ((TimeInterval) -> Void)?

    // MARK: - Public Methods

    /// Set the base update interval (user preference)
    func setBaseUpdateInterval(_ interval: TimeInterval) {
        baseUpdateInterval = max(minUpdateInterval, min(maxUpdateInterval, interval))
        recalculateUpdateInterval()
    }

    /// Get the current adaptive update interval
    func getCurrentUpdateInterval() -> TimeInterval {
        return currentUpdateInterval
    }

    /// Update system state and potentially adjust frequency
    func updateSystemState(cpuUsage: Double, memoryUsage: Double, isLowPower: Bool = false) {
        // Track previous states so we can detect transitions
        let wasHighLoad = isHighSystemLoad
        let wasLowPower = isLowPowerMode

        isLowPowerMode = isLowPower

        // Determine if system is under high load
        isHighSystemLoad = cpuUsage > highLoadCPUThreshold || memoryUsage > highLoadMemoryThreshold

        // Track consecutive samples to avoid frequent changes
        if isHighSystemLoad {
            consecutiveHighLoadSamples += 1
            consecutiveLowLoadSamples = 0
        } else {
            consecutiveLowLoadSamples += 1
            consecutiveHighLoadSamples = 0
        }

        // Only change frequency after consistent samples or power mode changes
        let shouldRecalculate =
            (consecutiveHighLoadSamples >= loadSampleThreshold && !wasHighLoad)
            || (consecutiveLowLoadSamples >= loadSampleThreshold && wasHighLoad)
            || (wasLowPower != isLowPowerMode)  // Power mode changed

        if shouldRecalculate {
            recalculateUpdateInterval()
        }

        logger.debug(
            "System state: CPU=\(cpuUsage, privacy: .public)%, Memory=\(memoryUsage, privacy: .public)%, HighLoad=\(self.isHighSystemLoad), LowPower=\(self.isLowPowerMode), Interval=\(self.currentUpdateInterval, privacy: .public)s"
        )
    }

    /// Force recalculation of update interval
    func recalculateUpdateInterval() {
        let previousInterval = currentUpdateInterval

        var newInterval = baseUpdateInterval

        // Apply low power mode multiplier
        if isLowPowerMode {
            newInterval *= lowPowerModeMultiplier
        }

        // Apply high load adjustment (increase frequency when system is busy)
        if isHighSystemLoad {
            newInterval *= highLoadMultiplier
        }

        // Clamp to valid range
        newInterval = max(minUpdateInterval, min(maxUpdateInterval, newInterval))

        // Only update if there's a meaningful change (avoid micro-adjustments)
        if abs(newInterval - currentUpdateInterval) > 0.1 {
            currentUpdateInterval = newInterval

            logger.info(
                "Update interval changed from \(previousInterval, privacy: .public)s to \(self.currentUpdateInterval, privacy: .public)s (base: \(self.baseUpdateInterval, privacy: .public)s, highLoad: \(self.isHighSystemLoad), lowPower: \(self.isLowPowerMode))"
            )

            onFrequencyChanged?(currentUpdateInterval)
        }
    }

    /// Reset to base frequency (useful after system events)
    func resetToBaseFrequency() {
        consecutiveHighLoadSamples = 0
        consecutiveLowLoadSamples = 0
        isHighSystemLoad = false
        recalculateUpdateInterval()

        logger.info(
            "Frequency reset to base interval: \(self.currentUpdateInterval, privacy: .public)s")
    }

    /// Get frequency adjustment statistics
    func getFrequencyStatistics() -> FrequencyStatistics {
        return FrequencyStatistics(
            baseInterval: baseUpdateInterval,
            currentInterval: currentUpdateInterval,
            isAdaptive: currentUpdateInterval != baseUpdateInterval,
            isHighLoad: isHighSystemLoad,
            isLowPowerMode: isLowPowerMode,
            adjustmentReason: getAdjustmentReason()
        )
    }

    // MARK: - Private Methods

    private func getAdjustmentReason() -> String {
        if currentUpdateInterval == baseUpdateInterval {
            return "No adjustment"
        }

        var reasons: [String] = []

        if isLowPowerMode {
            reasons.append("Low power mode")
        }

        if isHighSystemLoad {
            reasons.append("High system load")
        }

        return reasons.isEmpty ? "Unknown" : reasons.joined(separator: ", ")
    }
}

// MARK: - Data Models

/// Statistics about frequency adjustments
struct FrequencyStatistics {
    let baseInterval: TimeInterval
    let currentInterval: TimeInterval
    let isAdaptive: Bool
    let isHighLoad: Bool
    let isLowPowerMode: Bool
    let adjustmentReason: String

    /// Frequency adjustment ratio (current/base)
    var adjustmentRatio: Double {
        return baseInterval > 0 ? currentInterval / baseInterval : 1.0
    }

    /// Human-readable description
    var description: String {
        if isAdaptive {
            return
                "Adaptive: \(String(format: "%.1f", currentInterval))s (base: \(String(format: "%.1f", baseInterval))s) - \(adjustmentReason)"
        } else {
            return "Fixed: \(String(format: "%.1f", currentInterval))s"
        }
    }
}

/// Intelligent caching system for system data
class IntelligentCache {

    // MARK: - Properties
    private let logger = Logger(subsystem: "com.systemmonitor", category: "IntelligentCache")

    // Cache storage
    private var cachedData: [String: CachedItem] = [:]
    private let cacheQueue = DispatchQueue(
        label: "com.systemmonitor.cache", attributes: .concurrent)

    // Cache configuration
    private let defaultCacheDuration: TimeInterval = 5.0  // 5 seconds default
    private let maxCacheSize: Int = 100

    // Cache durations for different data types
    private let cacheDurations: [String: TimeInterval] = [
        "cpu_frequency": 30.0,  // CPU frequency changes slowly
        "cpu_cores": 300.0,  // Core count never changes
        "memory_total": 300.0,  // Total memory never changes
        "gpu_name": 300.0,  // GPU name never changes
        "disk_info": 60.0,  // Disk info changes slowly
        "network_interfaces": 30.0,  // Network interfaces change slowly
        "temperature_sensors": 10.0,  // Temperature sensor availability changes slowly
    ]

    // MARK: - Public Methods

    /// Get cached data if available and not expired
    func getCachedData<T>(key: String, type: T.Type) -> T? {
        return cacheQueue.sync {
            guard let item = cachedData[key],
                !item.isExpired,
                let data = item.data as? T
            else {
                return nil
            }

            logger.debug("Cache hit for key: \(key, privacy: .public)")
            return data
        }
    }

    /// Store data in cache with appropriate expiration
    func setCachedData<T>(key: String, data: T) {
        let duration = cacheDurations[key] ?? defaultCacheDuration
        let item = CachedItem(data: data, expirationTime: Date().addingTimeInterval(duration))

        cacheQueue.async(flags: .barrier) {
            self.cachedData[key] = item

            // Clean up expired items if cache is getting large
            if self.cachedData.count > self.maxCacheSize {
                self.cleanupExpiredItems()
            }

            self.logger.debug(
                "Cached data for key: \(key, privacy: .public) (expires in \(duration, privacy: .public)s)"
            )
        }
    }

    /// Check if data is cached and valid
    func isCached(key: String) -> Bool {
        return cacheQueue.sync {
            guard let item = cachedData[key] else { return false }
            return !item.isExpired
        }
    }

    /// Clear all cached data
    func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.cachedData.removeAll()
            self.logger.info("Cache cleared")
        }
    }

    /// Clear expired items from cache
    func cleanupExpiredItems() {
        cacheQueue.async(flags: .barrier) {
            let initialCount = self.cachedData.count
            self.cachedData = self.cachedData.filter { !$0.value.isExpired }
            let removedCount = initialCount - self.cachedData.count

            if removedCount > 0 {
                self.logger.debug("Cleaned up \(removedCount) expired cache items")
            }
        }
    }

    /// Get cache statistics
    func getCacheStatistics() -> CacheStatistics {
        return cacheQueue.sync {
            let totalItems = cachedData.count
            let expiredItems = cachedData.values.filter { $0.isExpired }.count
            let validItems = totalItems - expiredItems

            return CacheStatistics(
                totalItems: totalItems,
                validItems: validItems,
                expiredItems: expiredItems,
                hitRate: 0.0  // Would need to track hits/misses for accurate rate
            )
        }
    }

    // MARK: - Private Methods
}

// MARK: - Cache Data Models

/// Cached item with expiration
private struct CachedItem {
    let data: Any
    let expirationTime: Date

    var isExpired: Bool {
        return Date() > expirationTime
    }
}

/// Cache performance statistics
struct CacheStatistics {
    let totalItems: Int
    let validItems: Int
    let expiredItems: Int
    let hitRate: Double

    /// Cache efficiency percentage
    var efficiency: Double {
        return totalItems > 0 ? Double(validItems) / Double(totalItems) * 100.0 : 0.0
    }

    /// Human-readable description
    var description: String {
        return
            "Cache: \(validItems)/\(totalItems) items valid (\(String(format: "%.1f", efficiency))% efficiency)"
    }
}
