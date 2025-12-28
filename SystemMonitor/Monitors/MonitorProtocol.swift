import Foundation

// MARK: - Monitor Protocol
protocol MonitorProtocol {
    associatedtype DataType

    /// Collect current system data
    func collect() -> DataType

    /// Check if monitoring is available on this system
    func isAvailable() -> Bool

    /// Start monitoring (if needed for continuous monitoring)
    func startMonitoring()

    /// Stop monitoring and cleanup resources
    func stopMonitoring()

    /// Handle system sleep event
    func handleSystemSleep()

    /// Handle system wake event
    func handleSystemWake()
    
    /// Handle system shutdown event
    func handleSystemShutdown()
}

// MARK: - Monitor Error Types
enum MonitorError: Error, LocalizedError {
    case permissionDenied
    case systemCallFailed(String)
    case dataUnavailable
    case invalidData(String)
    case networkUnavailable
    case diskAccessFailed(String)
    case temperatureSensorUnavailable
    case gpuUnavailable
    case timeout(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Permission denied to access system information"
        case .systemCallFailed(let call):
            return "System call failed: \(call)"
        case .dataUnavailable:
            return "System data is currently unavailable"
        case .invalidData(let reason):
            return "Invalid data received: \(reason)"
        case .networkUnavailable:
            return "Network monitoring is unavailable"
        case .diskAccessFailed(let reason):
            return "Disk access failed: \(reason)"
        case .temperatureSensorUnavailable:
            return "Temperature sensors are not available on this system"
        case .gpuUnavailable:
            return "GPU monitoring is not available on this system"
        case .timeout(let operation):
            return "Operation timed out: \(operation)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            return
                "Please grant the necessary permissions in System Preferences > Security & Privacy > Privacy."
        case .systemCallFailed:
            return "This may be a temporary issue. Try restarting the application."
        case .dataUnavailable:
            return
                "System data may be temporarily unavailable. Monitoring will resume automatically."
        case .invalidData:
            return "This may indicate a system compatibility issue."
        case .networkUnavailable:
            return "Network monitoring requires an active network connection."
        case .diskAccessFailed:
            return "Check disk permissions and available space."
        case .temperatureSensorUnavailable:
            return "Temperature monitoring is not supported on this hardware."
        case .gpuUnavailable:
            return "GPU monitoring may not be available on this system configuration."
        case .timeout:
            return "The operation took too long. This may indicate system performance issues."
        }
    }

    var shouldShowToUser: Bool {
        switch self {
        case .permissionDenied:
            return true
        case .systemCallFailed:
            return false  // Log only
        case .dataUnavailable:
            return false  // Handle gracefully
        case .invalidData:
            return false  // Log only
        case .networkUnavailable:
            return false  // Handle gracefully
        case .diskAccessFailed:
            return false  // Handle gracefully
        case .temperatureSensorUnavailable:
            return false  // Handle gracefully
        case .gpuUnavailable:
            return false  // Handle gracefully
        case .timeout:
            return false  // Log only
        }
    }
}

// MARK: - Monitor State
enum MonitorState {
    case stopped
    case starting
    case running
    case error(MonitorError)
}

// MARK: - Base Monitor Class
class BaseMonitor {
    private(set) var state: MonitorState = .stopped
    private var monitoringQueue: DispatchQueue

    init(queueLabel: String) {
        self.monitoringQueue = DispatchQueue(label: queueLabel, qos: .utility)
    }

    func setState(_ newState: MonitorState) {
        DispatchQueue.main.async {
            self.state = newState
        }
    }

    func performAsync<T>(
        _ operation: @escaping () throws -> T,
        completion: @escaping (Result<T, MonitorError>) -> Void
    ) {
        monitoringQueue.async {
            do {
                let result = try operation()
                DispatchQueue.main.async {
                    completion(.success(result))
                }
            } catch let error as MonitorError {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.systemCallFailed(error.localizedDescription)))
                }
            }
        }
    }

    func performAsyncWithTimeout<T>(
        _ operation: @escaping () throws -> T, timeout: TimeInterval = 3.0
    ) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<T, MonitorError>?

        monitoringQueue.async {
            do {
                let value = try operation()
                result = .success(value)
            } catch let error as MonitorError {
                result = .failure(error)
            } catch {
                result = .failure(.systemCallFailed(error.localizedDescription))
            }
            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + timeout)

        guard waitResult == .success, let finalResult = result else {
            throw MonitorError.systemCallFailed("Operation timeout after \(timeout) seconds")
        }

        switch finalResult {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }

    // MARK: - System Event Handling

    func handleSystemSleep() {
        NSLog("\(String(describing: type(of: self))) handling system sleep")
        // Default implementation - subclasses can override
    }

    func handleSystemWake() {
        NSLog("\(String(describing: type(of: self))) handling system wake")
        // Default implementation - subclasses can override
    }
    
    func handleSystemShutdown() {
        NSLog("\(String(describing: type(of: self))) handling system shutdown")
        // Default implementation - subclasses can override
    }
}

// MARK: - Monitor Manager Protocol
protocol MonitorManagerProtocol {
    func startAllMonitors()
    func stopAllMonitors()
    func getCurrentData() -> SystemData
    func isMonitoringActive() -> Bool
}
