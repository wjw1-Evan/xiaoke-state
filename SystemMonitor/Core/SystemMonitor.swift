import Foundation
import os.log

class SystemMonitor: MonitorManagerProtocol {
    // MARK: - Properties
    private let cpuMonitor: CPUMonitor
    private let memoryMonitor: MemoryMonitor
    private let gpuMonitor: GPUMonitor
    private let temperatureMonitor: TemperatureMonitor
    private let networkMonitor: NetworkMonitor
    private let diskMonitor: DiskMonitor
    private let performanceMonitor: PerformanceMonitor

    private var updateTimer: Timer?
    private var updateInterval: TimeInterval = 1.0
    private var isActive: Bool = false

    private var currentSystemData: SystemData?

    // Error handling and logging
    private let logger = Logger(subsystem: "com.systemmonitor", category: "SystemMonitor")
    private var errorCounts: [String: Int] = [:]
    private let maxErrorsPerType = 10

    // Adaptive frequency and caching
    private let adaptiveFrequencyManager: AdaptiveFrequencyManager
    private let intelligentCache: IntelligentCache

    // MARK: - Callbacks
    var onDataUpdate: ((SystemData) -> Void)?
    var onError: ((MonitorError) -> Void)?

    // MARK: - Initialization
    init() {
        self.cpuMonitor = CPUMonitor()
        self.memoryMonitor = MemoryMonitor()
        self.gpuMonitor = GPUMonitor()
        self.temperatureMonitor = TemperatureMonitor()
        self.networkMonitor = NetworkMonitor()
        self.diskMonitor = DiskMonitor()
        self.performanceMonitor = PerformanceMonitor()
        self.adaptiveFrequencyManager = AdaptiveFrequencyManager()
        self.intelligentCache = IntelligentCache()

        // Ensure base interval starts from 1 second so first timer uses 1s
        adaptiveFrequencyManager.setBaseUpdateInterval(updateInterval)

        setupAdaptiveFrequency()
    }

    deinit {
        stopAllMonitors()
    }

    // MARK: - MonitorManagerProtocol

    func startAllMonitors() {
        guard !isActive else { return }

        isActive = true

        // Start individual monitors
        cpuMonitor.startMonitoring()
        memoryMonitor.startMonitoring()
        performanceMonitor.startMonitoring()

        // Start extended monitors if available
        if gpuMonitor.isAvailable() {
            gpuMonitor.startMonitoring()
        }

        if temperatureMonitor.isAvailable() {
            temperatureMonitor.startMonitoring()
        }

        if networkMonitor.isAvailable() {
            networkMonitor.startMonitoring()
        }

        if diskMonitor.isAvailable() {
            diskMonitor.startMonitoring()
        }

        // Start update timer
        startUpdateTimer()

        // Collect initial data
        collectAndUpdateData()
    }

    func stopAllMonitors() {
        guard isActive else { return }

        isActive = false

        // Stop timer
        stopUpdateTimer()

        // Stop individual monitors
        cpuMonitor.stopMonitoring()
        memoryMonitor.stopMonitoring()
        performanceMonitor.stopMonitoring()
        gpuMonitor.stopMonitoring()
        temperatureMonitor.stopMonitoring()
        networkMonitor.stopMonitoring()
        diskMonitor.stopMonitoring()
    }

    func getCurrentData() -> SystemData {
        if let data = currentSystemData {
            return data
        }

        // Return default data if no data is available
        return createDefaultSystemData()
    }

    func isMonitoringActive() -> Bool {
        return isActive
    }

    // MARK: - Configuration

    func setUpdateInterval(_ interval: TimeInterval) {
        guard interval >= 1.0 && interval <= 10.0 else { return }

        updateInterval = interval
        adaptiveFrequencyManager.setBaseUpdateInterval(interval)

        if isActive {
            stopUpdateTimer()
            startUpdateTimer()
        }
    }

    func getUpdateInterval() -> TimeInterval {
        return updateInterval
    }

    // MARK: - Private Methods

    private func startUpdateTimer() {
        let currentInterval = adaptiveFrequencyManager.getCurrentUpdateInterval()
        let timer = Timer(timeInterval: currentInterval, repeats: true) { [weak self] _ in
            self?.collectAndUpdateData()
        }
        updateTimer = timer
        // 使用 Common 模式，确保在菜单跟踪等 UI 模式下仍继续触发
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func collectAndUpdateData() {
        // Ensure we don't block the main thread and monitoring is active
        guard isActive else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self, self.isActive else { return }

            do {
                let systemData = try self.collectSystemDataAsync()

                // Update adaptive frequency based on system load
                self.updateAdaptiveFrequency(with: systemData)

                DispatchQueue.main.async {
                    self.currentSystemData = systemData
                    self.onDataUpdate?(systemData)
                }
            } catch {
                DispatchQueue.main.async {
                    let monitorError =
                        error as? MonitorError ?? .systemCallFailed(error.localizedDescription)
                    self.handleError(monitorError, context: "Data collection")

                    // Try to provide fallback data if possible
                    if let fallbackData = self.createFallbackDataIfPossible() {
                        self.currentSystemData = fallbackData
                        self.onDataUpdate?(fallbackData)
                    }
                }
            }
        }
    }


    private func collectSystemDataAsync() throws -> SystemData {
        // Use concurrent queue for parallel data collection
        let concurrentQueue = DispatchQueue(
            label: "com.systemmonitor.datacollection", attributes: .concurrent)
        let group = DispatchGroup()

        var cpuData: CPUData?
        var memoryData: MemoryData?
        var performanceData: PerformanceData?
        var gpuData: GPUData?
        var temperatureData: TemperatureData?
        var networkData: NetworkData?
        var diskData: [DiskData] = []

        // Collect CPU data
        group.enter()
        concurrentQueue.async {
            defer { group.leave() }
            cpuData = self.cpuMonitor.collect()
        }

        // Collect Memory data
        group.enter()
        concurrentQueue.async {
            defer { group.leave() }
            memoryData = self.memoryMonitor.collect()
        }

        // Collect Performance data
        group.enter()
        concurrentQueue.async {
            defer { group.leave() }
            performanceData = self.performanceMonitor.collect()
        }

        // Collect GPU data if available
        if gpuMonitor.isAvailable() {
            group.enter()
            concurrentQueue.async {
                defer { group.leave() }
                gpuData = self.gpuMonitor.collect()
            }
        }

        // Collect Temperature data if available
        if temperatureMonitor.isAvailable() {
            group.enter()
            concurrentQueue.async {
                defer { group.leave() }
                temperatureData = self.temperatureMonitor.collect()
            }
        }

        // Collect Network data if available
        if networkMonitor.isAvailable() {
            group.enter()
            concurrentQueue.async {
                defer { group.leave() }
                networkData = self.networkMonitor.collect()
            }
        }

        // Collect Disk data if available
        if diskMonitor.isAvailable() {
            group.enter()
            concurrentQueue.async {
                defer { group.leave() }
                diskData = self.diskMonitor.collect()
            }
        }

        // Wait for all data collection to complete with timeout
        let result = group.wait(timeout: .now() + 5.0)  // 5 second timeout

        guard result == .success else {
            throw MonitorError.systemCallFailed("Data collection timeout")
        }

        // Ensure we have at least CPU and Memory data (required)
        guard let cpu = cpuData, let memory = memoryData else {
            throw MonitorError.dataUnavailable
        }

        return SystemData(
            cpu: cpu,
            gpu: gpuData,
            memory: memory,
            disk: diskData,
            temperature: temperatureData,
            network: networkData,
            performance: performanceData
        )
    }

    // MARK: - Adaptive Frequency and Caching Methods

    private func updateAdaptiveFrequency(with systemData: SystemData) {
        // Update frequency manager with current system load
        let cpuUsage = systemData.cpu.usage
        let memoryUsage = systemData.memory.usagePercentage

        // Check if system is in low power mode (simplified check)
        let isLowPower = systemData.performance?.cpuUsagePercent ?? 0 > 0.5  // App using more than 0.5% CPU

        adaptiveFrequencyManager.updateSystemState(
            cpuUsage: cpuUsage,
            memoryUsage: memoryUsage,
            isLowPower: isLowPower
        )
    }

    private func createDefaultSystemData() -> SystemData {
        let defaultCPU = CPUData(usage: 0.0, coreCount: 1, frequency: 0.0)
        let defaultMemory = MemoryData(used: 0, total: 1, pressure: .normal)

        return SystemData(
            cpu: defaultCPU,
            gpu: nil,
            memory: defaultMemory,
            disk: [],
            temperature: nil,
            network: nil,
            performance: nil
        )
    }

    private func createFallbackDataIfPossible() -> SystemData? {
        // Try to collect at least basic CPU and memory data
        let cpuData: CPUData? = cpuMonitor.collect()
        let memoryData: MemoryData? = memoryMonitor.collect()

        // If we have at least one type of data, create fallback
        if cpuData != nil || memoryData != nil {
            return createFallbackData(from: (cpu: cpuData, memory: memoryData))
        }

        return nil
    }
}

// MARK: - System Event Handling
extension SystemMonitor {
    func handleSystemSleep() {
        NSLog("System going to sleep - pausing monitoring")
        if isActive {
            stopUpdateTimer()
            // Notify all monitors about sleep event
            cpuMonitor.handleSystemSleep()
            memoryMonitor.handleSystemSleep()
            performanceMonitor.handleSystemSleep()
            gpuMonitor.handleSystemSleep()
            temperatureMonitor.handleSystemSleep()
            networkMonitor.handleSystemSleep()
            diskMonitor.handleSystemSleep()
        }
    }

    func handleSystemWake() {
        NSLog("System waking up - resuming monitoring")
        if isActive {
            // Reset adaptive frequency after wake
            adaptiveFrequencyManager.resetToBaseFrequency()

            // Notify all monitors about wake event
            cpuMonitor.handleSystemWake()
            memoryMonitor.handleSystemWake()
            performanceMonitor.handleSystemWake()
            gpuMonitor.handleSystemWake()
            temperatureMonitor.handleSystemWake()
            networkMonitor.handleSystemWake()
            diskMonitor.handleSystemWake()

            // Resume monitoring with a slight delay to allow system to stabilize
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.startUpdateTimer()
                self?.collectAndUpdateData()
            }
        }
    }

    func handleSystemShutdown() {
        NSLog("System shutting down - stopping all monitoring")
        stopAllMonitors()
    }

    func handleLowPowerMode(_ enabled: Bool) {
        NSLog("Low power mode \(enabled ? "enabled" : "disabled")")

        // Update adaptive frequency manager
        if let currentData = currentSystemData {
            adaptiveFrequencyManager.updateSystemState(
                cpuUsage: currentData.cpu.usage,
                memoryUsage: currentData.memory.usagePercentage,
                isLowPower: enabled
            )
        }
    }
}

// MARK: - Error Handling
extension SystemMonitor {
    private func handleError(_ error: MonitorError, context: String = "") {
        let errorKey = "\(error)"
        let currentCount = errorCounts[errorKey, default: 0]

        // Increment error count
        errorCounts[errorKey] = currentCount + 1

        // Log error with context
        let contextInfo = context.isEmpty ? "" : " (\(context))"
        logger.error("Monitor error\(contextInfo): \(error.localizedDescription)")

        // Log recovery suggestion if available
        if let suggestion = error.recoverySuggestion {
            logger.info("Recovery suggestion: \(suggestion)")
        }

        // Only show user alerts for critical errors and if we haven't shown too many
        if error.shouldShowToUser && currentCount < maxErrorsPerType {
            DispatchQueue.main.async { [weak self] in
                self?.onError?(error)
            }
        }

        // Reset error counts periodically to allow recovery
        if currentCount >= maxErrorsPerType {
            DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in  // 5 minutes
                self?.errorCounts[errorKey] = 0
            }
        }
    }

    private func createFallbackData(from partialData: (cpu: CPUData?, memory: MemoryData?))
        -> SystemData
    {
        let safeCPU = partialData.cpu ?? CPUData(usage: 0.0, coreCount: 1, frequency: 0.0)
        let safeMemory = partialData.memory ?? MemoryData(used: 0, total: 1, pressure: .normal)

        logger.info("Creating fallback system data due to collection errors")

        return SystemData(
            cpu: safeCPU,
            gpu: nil,
            memory: safeMemory,
            disk: [],
            temperature: nil,
            network: nil,
            performance: nil
        )
    }

    func getErrorStatistics() -> [String: Int] {
        return errorCounts
    }

    func resetErrorCounts() {
        errorCounts.removeAll()
        logger.info("Error counts reset")
    }

    // MARK: - Performance Monitoring

    /// Check if the application is within performance limits
    func checkPerformanceLimits() -> PerformanceLimitStatus {
        return performanceMonitor.checkPerformanceLimits()
    }

    /// Get performance statistics over time
    func getPerformanceStatistics() -> PerformanceStatistics {
        return performanceMonitor.getPerformanceStatistics()
    }

    /// Get current performance data
    func getCurrentPerformanceData() -> PerformanceData? {
        return currentSystemData?.performance
    }

    // MARK: - Adaptive Frequency Management

    private func setupAdaptiveFrequency() {
        adaptiveFrequencyManager.onFrequencyChanged = { [weak self] newInterval in
            DispatchQueue.main.async {
                self?.handleFrequencyChange(newInterval)
            }
        }
    }

    private func handleFrequencyChange(_ newInterval: TimeInterval) {
        guard isActive else { return }

        logger.info("Adapting update frequency to \(newInterval, privacy: .public) seconds")

        // Restart timer with new interval
        stopUpdateTimer()
        let timer = Timer(timeInterval: newInterval, repeats: true) { [weak self] _ in
            self?.collectAndUpdateData()
        }
        updateTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Get frequency management statistics
    func getFrequencyStatistics() -> FrequencyStatistics {
        return adaptiveFrequencyManager.getFrequencyStatistics()
    }

    /// Get cache statistics
    func getCacheStatistics() -> CacheStatistics {
        return intelligentCache.getCacheStatistics()
    }

    /// Clear intelligent cache
    func clearCache() {
        intelligentCache.clearCache()
    }
}
