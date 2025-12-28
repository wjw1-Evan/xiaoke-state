import Cocoa
import Darwin

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    // MARK: - Properties
    var statusBarManager: StatusBarManager?
    var systemMonitor: SystemMonitor?
    var preferencesManager: PreferencesManager?
    var menuBuilder: MenuBuilder?

    // Auto-restart functionality
    private var crashHandler: CrashHandler?
    private var isTerminatingNormally = false

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("System Monitor: Application did finish launching")
        setupApplication()
        startMonitoring()

        // Register for system sleep/wake notifications
        registerForSystemEvents()

        // Setup crash handling and auto-restart if enabled
        setupCrashHandling()

        NSLog("System Monitor: Setup complete, status bar should be visible")

        // Ensure localized texts are applied after setup
        statusBarManager?.refreshLocalizedTexts()

        // Localization diagnostics
        let diag = Localization.shared.diagnostics()
        NSLog(
            "Localization: active=\(diag.activeLanguage), available=\(diag.available), preferred=\(diag.preferred), path=\(diag.bundlePath ?? "nil")"
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminatingNormally = true
        stopMonitoring()
        unregisterFromSystemEvents()

        // Clean up crash handler
        crashHandler?.cleanup()

        NSLog("System Monitor terminated normally")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
        -> Bool
    {
        // Show preferences when dock icon is clicked (if visible)
        preferencesManager?.showPreferencesWindow()
        return true
    }

    // MARK: - Setup Methods

    private func setupApplication() {
        // Initialize preferences manager
        preferencesManager = PreferencesManager()

        // Initialize menu builder
        menuBuilder = MenuBuilder(
            displayOptions: preferencesManager?.displayOptions ?? DisplayOptions(),
            preferencesManager: preferencesManager
        )

        // Initialize status bar manager
        guard let menuBuilder = menuBuilder else {
            fatalError("Failed to initialize menu builder")
        }

        statusBarManager = StatusBarManager(
            menuBuilder: menuBuilder,
            warningThresholds: preferencesManager?.warningThresholds ?? WarningThresholds(),
            displayOptions: preferencesManager?.displayOptions ?? DisplayOptions()
        )

        // Initialize system monitor
        systemMonitor = SystemMonitor()

        // Setup status bar
        statusBarManager?.setupStatusItem()

        // Setup callbacks
        setupCallbacks()
    }

    private func setupCallbacks() {
        // System monitor data updates
        systemMonitor?.onDataUpdate = { [weak self] data in
            self?.statusBarManager?.updateStatusDisplay(with: data)
        }

        // System monitor errors
        systemMonitor?.onError = { [weak self] error in
            self?.handleMonitorError(error)
        }

        // Preferences changes
        preferencesManager?.onSettingsChanged = { [weak self] in
            self?.handleSettingsChanged()
        }
    }

    private func startMonitoring() {
        systemMonitor?.startAllMonitors()
    }

    private func stopMonitoring() {
        systemMonitor?.stopAllMonitors()
    }

    // MARK: - Event Handling

    private func handleMonitorError(_ error: MonitorError) {
        // Log all errors to system log
        NSLog("Monitor error: \(error.localizedDescription)")

        // Show user-friendly error if needed
        switch error {
        case .permissionDenied:
            showPermissionAlert()
        case .systemCallFailed(let call):
            NSLog("System call failed: \(call)")
        // Don't show user alert for system call failures
        case .dataUnavailable:
            NSLog("System data unavailable - monitoring will continue")
        // Don't show user alert for temporary data unavailability
        case .invalidData(let reason):
            NSLog("Invalid data: \(reason)")
        case .networkUnavailable:
            NSLog("Network monitoring unavailable")
        // Could show a subtle indicator in the menu
        case .diskAccessFailed(let reason):
            NSLog("Disk access failed: \(reason)")
        case .temperatureSensorUnavailable:
            NSLog("Temperature sensors unavailable on this system")
        case .gpuUnavailable:
            NSLog("GPU monitoring unavailable on this system")
        case .timeout(let operation):
            NSLog("Operation timeout: \(operation)")
        }
    }

    private func handleSettingsChanged() {
        guard let preferencesManager = preferencesManager else { return }

        // Update system monitor interval
        systemMonitor?.setUpdateInterval(preferencesManager.updateInterval)

        // Update menu builder display options
        menuBuilder?.updateDisplayOptions(preferencesManager.displayOptions)

        // Update status bar options and thresholds
        statusBarManager?.updateDisplayOptions(preferencesManager.displayOptions)
        statusBarManager?.updateWarningThresholds(preferencesManager.warningThresholds)

        // Refresh localized texts to reflect potential language changes
        statusBarManager?.refreshLocalizedTexts()
    }

    private func showPermissionAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("alert.permission.title", comment: "")
            alert.informativeText = NSLocalizedString("alert.permission.message", comment: "")
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    // MARK: - System Events

    private func registerForSystemEvents() {
        let notificationCenter = NSWorkspace.shared.notificationCenter

        notificationCenter.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )

        notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        // Additional system events
        notificationCenter.addObserver(
            self,
            selector: #selector(systemWillPowerOff),
            name: NSWorkspace.willPowerOffNotification,
            object: nil
        )

        notificationCenter.addObserver(
            self,
            selector: #selector(screenDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )

        notificationCenter.addObserver(
            self,
            selector: #selector(screenDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )

        // Register for low power mode notifications (if available)
        if #available(macOS 12.0, *) {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(lowPowerModeChanged),
                name: .NSProcessInfoPowerStateDidChange,
                object: nil
            )
        }
    }

    private func unregisterFromSystemEvents() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func systemWillSleep() {
        NSLog("System will sleep notification received")
        systemMonitor?.handleSystemSleep()
    }

    @objc private func systemDidWake() {
        NSLog("System did wake notification received")
        systemMonitor?.handleSystemWake()
    }

    @objc private func systemWillPowerOff() {
        NSLog("System will power off notification received")
        systemMonitor?.handleSystemShutdown()
    }

    @objc private func screenDidSleep() {
        NSLog("Screen did sleep notification received")
        // Optionally reduce monitoring frequency when screen is off
    }

    @objc private func screenDidWake() {
        NSLog("Screen did wake notification received")
        // Resume normal monitoring frequency
    }

    @objc private func lowPowerModeChanged() {
        if #available(macOS 12.0, *) {
            // Note: isLowPowerModeEnabled is iOS only, on macOS we can check thermal state
            let thermalState = Foundation.ProcessInfo.processInfo.thermalState
            let isLowPowerMode = thermalState == .serious || thermalState == .critical
            NSLog(
                "Thermal state changed: \(thermalState), treating as low power: \(isLowPowerMode)")
            systemMonitor?.handleLowPowerMode(isLowPowerMode)
        }
    }

    // MARK: - Crash Handling and Auto-Restart

    private func setupCrashHandling() {
        // Only setup crash handling if auto-restart is enabled in preferences
        guard let preferencesManager = preferencesManager,
            preferencesManager.isAutoRestartEnabled
        else {
            return
        }

        crashHandler = CrashHandler()
        crashHandler?.setupCrashHandling { [weak self] in
            self?.handleApplicationCrash()
        }
    }

    private func handleApplicationCrash() {
        guard !isTerminatingNormally else { return }

        NSLog("System Monitor crashed - attempting auto-restart")

        // Create a script to restart the application
        let appPath = Bundle.main.bundlePath
        let restartScript = """
            #!/bin/bash
            sleep 2
            open "\(appPath)"
            """

        // Write script to temporary file
        let tempDir = NSTemporaryDirectory()
        let scriptPath = tempDir + "restart_system_monitor.sh"

        do {
            try restartScript.write(toFile: scriptPath, atomically: true, encoding: .utf8)

            // Make script executable
            let fileManager = FileManager.default
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

            // Execute restart script
            let process = Process()
            process.launchPath = "/bin/bash"
            process.arguments = [scriptPath]
            process.launch()

            NSLog("Auto-restart script launched")
        } catch {
            NSLog("Failed to create restart script: \(error)")
        }
    }

    // MARK: - Internal method for crash handlers
    internal func triggerAutoRestart() {
        handleApplicationCrash()
    }
}

// MARK: - Crash Handler

class CrashHandler {
    private var crashCallback: (() -> Void)?

    func setupCrashHandling(onCrash: @escaping () -> Void) {
        crashCallback = onCrash

        // Setup signal handlers for common crash signals
        signal(SIGABRT, crashSignalHandler)
        signal(SIGILL, crashSignalHandler)
        signal(SIGSEGV, crashSignalHandler)
        signal(SIGFPE, crashSignalHandler)
        signal(SIGBUS, crashSignalHandler)
        signal(SIGPIPE, crashSignalHandler)

        // Setup NSException handler
        NSSetUncaughtExceptionHandler(uncaughtExceptionHandler)
    }

    func cleanup() {
        // Reset signal handlers
        signal(SIGABRT, SIG_DFL)
        signal(SIGILL, SIG_DFL)
        signal(SIGSEGV, SIG_DFL)
        signal(SIGFPE, SIG_DFL)
        signal(SIGBUS, SIG_DFL)
        signal(SIGPIPE, SIG_DFL)

        NSSetUncaughtExceptionHandler(nil)
        crashCallback = nil
    }
}

// Global crash handlers
private func crashSignalHandler(signal: Int32) {
    NSLog("System Monitor received fatal signal: \(signal)")

    // Try to get the app delegate and trigger restart
    if let appDelegate = NSApp.delegate as? AppDelegate {
        appDelegate.triggerAutoRestart()
    }

    exit(signal)
}

private func uncaughtExceptionHandler(exception: NSException) {
    NSLog("System Monitor uncaught exception: \(exception)")

    // Try to get the app delegate and trigger restart
    if let appDelegate = NSApp.delegate as? AppDelegate {
        appDelegate.triggerAutoRestart()
    }

    exit(1)
}
