import Foundation
import SystemConfiguration

class NetworkMonitor: BaseMonitor, MonitorProtocol {
    typealias DataType = NetworkData

    private var previousStats: NetworkStats?
    private var lastUpdateTime: Date?
    private var networkReachability: SCNetworkReachability?

    private struct NetworkStats {
        let bytesReceived: UInt64
        let bytesSent: UInt64
        let timestamp: Date
    }

    init() {
        super.init(queueLabel: "com.systemmonitor.network")
    }

    deinit {
        stopMonitoring()
    }

    func collect() -> NetworkData {
        do {
            let currentStats = try getCurrentNetworkStats()
            let (uploadSpeed, downloadSpeed) = calculateSpeeds(current: currentStats)

            return NetworkData(
                uploadSpeed: uploadSpeed,
                downloadSpeed: downloadSpeed,
                totalUploaded: currentStats.bytesSent,
                totalDownloaded: currentStats.bytesReceived
            )
        } catch {
            // Return default data on error
            return NetworkData(
                uploadSpeed: 0, downloadSpeed: 0, totalUploaded: 0, totalDownloaded: 0)
        }
    }

    func isAvailable() -> Bool {
        // Check if we can access network interface information
        var ifaddrs: UnsafeMutablePointer<ifaddrs>?
        let result = getifaddrs(&ifaddrs)

        if result == 0 {
            freeifaddrs(ifaddrs)
            return true
        }

        return false
    }

    func startMonitoring() {
        setState(.starting)

        // Initialize network reachability monitoring
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        zeroAddress.sin_family = sa_family_t(AF_INET)

        networkReachability = withUnsafePointer(to: &zeroAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                SCNetworkReachabilityCreateWithAddress(nil, $0)
            }
        }

        // Get initial stats
        if let initialStats = try? getCurrentNetworkStats() {
            previousStats = initialStats
            lastUpdateTime = Date()
        }

        setState(.running)
    }

    func stopMonitoring() {
        setState(.stopped)
        networkReachability = nil
        previousStats = nil
        lastUpdateTime = nil
    }

    // MARK: - Private Methods

    private func getCurrentNetworkStats() throws -> NetworkStats {
        var ifaddrs: UnsafeMutablePointer<ifaddrs>?
        let result = getifaddrs(&ifaddrs)

        guard result == 0, let firstAddr = ifaddrs else {
            throw MonitorError.systemCallFailed("getifaddrs")
        }

        defer {
            freeifaddrs(ifaddrs)
        }

        var totalBytesReceived: UInt64 = 0
        var totalBytesSent: UInt64 = 0

        var currentAddr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while currentAddr != nil {
            let addr = currentAddr!
            defer { currentAddr = addr.pointee.ifa_next }

            guard let name = addr.pointee.ifa_name,
                let data = addr.pointee.ifa_data
            else {
                continue
            }

            let interfaceName = String(cString: name)

            // Skip loopback and inactive interfaces
            guard !interfaceName.hasPrefix("lo"),
                addr.pointee.ifa_flags & UInt32(IFF_UP) != 0,
                addr.pointee.ifa_flags & UInt32(IFF_RUNNING) != 0
            else {
                continue
            }

            // Only process AF_LINK (data link layer) addresses for statistics
            guard addr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK) else {
                continue
            }

            let networkData = data.assumingMemoryBound(to: if_data.self)

            totalBytesReceived += UInt64(networkData.pointee.ifi_ibytes)
            totalBytesSent += UInt64(networkData.pointee.ifi_obytes)
        }

        return NetworkStats(
            bytesReceived: totalBytesReceived,
            bytesSent: totalBytesSent,
            timestamp: Date()
        )
    }

    private func calculateSpeeds(current: NetworkStats) -> (
        uploadSpeed: UInt64, downloadSpeed: UInt64
    ) {
        guard let previous = previousStats,
            lastUpdateTime != nil
        else {
            // First measurement, store current stats and return 0 speeds
            previousStats = current
            lastUpdateTime = current.timestamp
            return (uploadSpeed: 0, downloadSpeed: 0)
        }

        let timeDelta = current.timestamp.timeIntervalSince(previous.timestamp)

        // Avoid division by zero and ensure reasonable time delta
        guard timeDelta > 0.1 else {
            return (uploadSpeed: 0, downloadSpeed: 0)
        }

        let bytesSentDelta =
            current.bytesSent >= previous.bytesSent ? current.bytesSent - previous.bytesSent : 0
        let bytesReceivedDelta =
            current.bytesReceived >= previous.bytesReceived
            ? current.bytesReceived - previous.bytesReceived : 0

        let uploadSpeed = UInt64(Double(bytesSentDelta) / timeDelta)
        let downloadSpeed = UInt64(Double(bytesReceivedDelta) / timeDelta)

        // Update previous stats for next calculation
        previousStats = current
        lastUpdateTime = current.timestamp

        return (uploadSpeed: uploadSpeed, downloadSpeed: downloadSpeed)
    }

    // MARK: - Network Reachability Helper

    private func isNetworkReachable() -> Bool {
        guard let reachability = networkReachability else { return false }

        var flags: SCNetworkReachabilityFlags = []
        let success = SCNetworkReachabilityGetFlags(reachability, &flags)

        guard success else { return false }

        let isReachable = flags.contains(.reachable)
        let needsConnection = flags.contains(.connectionRequired)

        return isReachable && !needsConnection
    }

    // MARK: - Interface Information Helper

    private func getActiveNetworkInterfaces() -> [String] {
        var interfaces: [String] = []
        var ifaddrs: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddrs) == 0, let firstAddr = ifaddrs else {
            return interfaces
        }

        defer {
            freeifaddrs(ifaddrs)
        }

        var currentAddr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while currentAddr != nil {
            let addr = currentAddr!
            defer { currentAddr = addr.pointee.ifa_next }

            guard let name = addr.pointee.ifa_name else {
                continue
            }

            let interfaceName = String(cString: name)

            // Check if interface is up and running
            if addr.pointee.ifa_flags & UInt32(IFF_UP) != 0
                && addr.pointee.ifa_flags & UInt32(IFF_RUNNING) != 0
                && !interfaceName.hasPrefix("lo")
            {

                if !interfaces.contains(interfaceName) {
                    interfaces.append(interfaceName)
                }
            }
        }

        return interfaces
    }
    
    override func handleSystemShutdown() {
        stopMonitoring()
    }
}
