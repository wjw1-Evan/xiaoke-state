import Cocoa
import Foundation
import ServiceManagement
import os.log

class PreferencesManager {
    // MARK: - Properties
    private let userDefaults: UserDefaults
    private var preferencesWindow: NSWindow?
    private let logger = Logger(subsystem: "com.systemmonitor", category: "Preferences")

    // MARK: - Settings Keys
    private enum Keys {
        static let updateInterval = "updateInterval"
        static let showCPU = "showCPU"
        static let showGPU = "showGPU"
        static let showMemory = "showMemory"
        static let showDisk = "showDisk"
        static let showTemperature = "showTemperature"
        static let showFan = "showFan"
        static let showNetwork = "showNetwork"
        static let menuBarFormat = "menuBarFormat"
        static let cpuWarningThreshold = "cpuWarningThreshold"
        static let memoryWarningThreshold = "memoryWarningThreshold"
        static let temperatureWarningThreshold = "temperatureWarningThreshold"
        static let autoRestartEnabled = "autoRestartEnabled"
        static let launchAtLogin = "launchAtLogin"
        static let languageOverride = "languageOverride"  // "auto" | "en" | "ja" | "zh-Hans"
    }

    // MARK: - Callbacks
    var onSettingsChanged: (() -> Void)?

    // MARK: - Initialization
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        registerDefaults()
        migrateDisplayOptionsIfNeeded()
    }

    // MARK: - Public Properties

    /// 固定为 1 秒刷新间隔，不再暴露给偏好设置界面
    var updateInterval: TimeInterval {
        get { 1.0 }
        set { /* ignore external changes */ }
    }

    var displayOptions: DisplayOptions {
        get {
            return DisplayOptions(
                showCPU: userDefaults.bool(forKey: Keys.showCPU),
                showGPU: userDefaults.bool(forKey: Keys.showGPU),
                showMemory: userDefaults.bool(forKey: Keys.showMemory),
                showDisk: userDefaults.bool(forKey: Keys.showDisk),
                showTemperature: userDefaults.bool(forKey: Keys.showTemperature),
                showFan: userDefaults.bool(forKey: Keys.showFan),
                showNetwork: userDefaults.bool(forKey: Keys.showNetwork),
                menuBarFormat: MenuBarFormat(
                    rawValue: userDefaults.string(forKey: Keys.menuBarFormat) ?? "") ?? .twoLine
            )
        }
        set {
            userDefaults.set(newValue.showCPU, forKey: Keys.showCPU)
            userDefaults.set(newValue.showGPU, forKey: Keys.showGPU)
            userDefaults.set(newValue.showMemory, forKey: Keys.showMemory)
            userDefaults.set(newValue.showDisk, forKey: Keys.showDisk)
            userDefaults.set(newValue.showTemperature, forKey: Keys.showTemperature)
            userDefaults.set(newValue.showFan, forKey: Keys.showFan)
            userDefaults.set(newValue.showNetwork, forKey: Keys.showNetwork)
            userDefaults.set(newValue.menuBarFormat.rawValue, forKey: Keys.menuBarFormat)
            notifySettingsChanged()
        }
    }

    var warningThresholds: WarningThresholds {
        get {
            return WarningThresholds(
                cpuUsage: userDefaults.double(forKey: Keys.cpuWarningThreshold),
                memoryUsage: userDefaults.double(forKey: Keys.memoryWarningThreshold),
                temperature: userDefaults.double(forKey: Keys.temperatureWarningThreshold)
            )
        }
        set {
            userDefaults.set(newValue.cpuUsage, forKey: Keys.cpuWarningThreshold)
            userDefaults.set(newValue.memoryUsage, forKey: Keys.memoryWarningThreshold)
            userDefaults.set(newValue.temperature, forKey: Keys.temperatureWarningThreshold)
            notifySettingsChanged()
        }
    }

    var isAutoRestartEnabled: Bool {
        get {
            return userDefaults.bool(forKey: Keys.autoRestartEnabled)
        }
        set {
            userDefaults.set(newValue, forKey: Keys.autoRestartEnabled)
            notifySettingsChanged()
        }
    }

    var isLaunchAtLoginEnabled: Bool {
        get { return userDefaults.bool(forKey: Keys.launchAtLogin) }
        set {
            userDefaults.set(newValue, forKey: Keys.launchAtLogin)
            updateLoginItem(enabled: newValue)
            notifySettingsChanged()
        }
    }

    /// Language selection: "auto" (follow system) or a BCP-47 code like "en", "ja", "zh-Hans"
    var languageOverride: String {
        get {
            return userDefaults.string(forKey: Keys.languageOverride) ?? "auto"
        }
        set {
            let allowed = ["auto", "en", "ja", "zh-Hans"]
            let value = allowed.contains(newValue) ? newValue : "auto"
            userDefaults.set(value, forKey: Keys.languageOverride)
            // Refresh localization bundle immediately so UI reflects change without restart
            Localization.shared.refreshBundle()
            notifySettingsChanged()
        }
    }

    // MARK: - Public Methods

    func showPreferencesWindow() {
        if preferencesWindow == nil {
            createPreferencesWindow()
        }

        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func saveSettings() {
        userDefaults.synchronize()
        notifySettingsChanged()
    }

    func loadSettings() {
        // Settings are loaded automatically through computed properties
        // Force reload from UserDefaults
        userDefaults.synchronize()
        notifySettingsChanged()
    }

    func resetToDefaults() {
        let keys = [
            Keys.updateInterval,
            Keys.showCPU,
            Keys.showGPU,
            Keys.showMemory,
            Keys.showDisk,
            Keys.showTemperature,
            Keys.showFan,
            Keys.showNetwork,
            Keys.menuBarFormat,
            Keys.cpuWarningThreshold,
            Keys.memoryWarningThreshold,
            Keys.temperatureWarningThreshold,
            Keys.autoRestartEnabled,
            Keys.launchAtLogin,
        ]

        for key in keys {
            userDefaults.removeObject(forKey: key)
        }

        registerDefaults()
        notifySettingsChanged()
    }

    // MARK: - Private Methods

    private func registerDefaults() {
        let defaults: [String: Any] = [
            Keys.updateInterval: 1.0,
            Keys.showCPU: true,
            Keys.showGPU: true,
            Keys.showMemory: true,
            Keys.showDisk: true,
            Keys.showTemperature: true,
            Keys.showFan: true,
            Keys.showNetwork: true,
            Keys.menuBarFormat: MenuBarFormat.twoLine.rawValue,
            Keys.cpuWarningThreshold: 80.0,
            Keys.memoryWarningThreshold: 80.0,
            Keys.temperatureWarningThreshold: 80.0,
            Keys.autoRestartEnabled: false,
            Keys.launchAtLogin: false,
            Keys.languageOverride: "auto",
        ]

        userDefaults.register(defaults: defaults)
    }

    /// 迁移早期版本中可能误配置的显示选项，避免所有可选监控项被永久隐藏。
    ///
    /// 场景：如果用户偏好中 CPU/内存可见，但 GPU/磁盘/温度/网络全部为 false，
    /// 很可能是旧版本或错误配置导致的，我们在此自动恢复这些可选项为可见。
    private func migrateDisplayOptionsIfNeeded() {
        let showCPU = userDefaults.bool(forKey: Keys.showCPU)
        let showMemory = userDefaults.bool(forKey: Keys.showMemory)
        let showGPU = userDefaults.bool(forKey: Keys.showGPU)
        let showDisk = userDefaults.bool(forKey: Keys.showDisk)
        let showTemperature = userDefaults.bool(forKey: Keys.showTemperature)
        let showNetwork = userDefaults.bool(forKey: Keys.showNetwork)

        // 如果核心指标可见，但所有可选指标都被关掉，则认为是异常配置，自动恢复。
        if (showCPU || showMemory) && !showGPU && !showDisk && !showTemperature && !showNetwork {
            userDefaults.set(true, forKey: Keys.showGPU)
            userDefaults.set(true, forKey: Keys.showDisk)
            userDefaults.set(true, forKey: Keys.showTemperature)
            userDefaults.set(true, forKey: Keys.showNetwork)
            logger.debug("Migrated display options: re-enabled GPU/Disk/Temperature/Network visibility")
        }
    }

    private func notifySettingsChanged() {
        DispatchQueue.main.async {
            self.onSettingsChanged?()
        }
    }

    private func updateLoginItem(enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            logger.error("Launch at login requires macOS 13+")
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
                logger.debug("Enabled launch at login")
            } else {
                try SMAppService.mainApp.unregister()
                logger.debug("Disabled launch at login")
            }
        } catch {
            logger.error(
                "Failed to update launch at login: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func createPreferencesWindow() {
        let windowRect = NSRect(x: 0, y: 0, width: 500, height: 450)
        preferencesWindow = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        preferencesWindow?.title = NSLocalizedString("prefs.title", comment: "")
        preferencesWindow?.center()
        preferencesWindow?.isReleasedWhenClosed = false

        // Create the preferences view controller
        let preferencesViewController = PreferencesViewController(preferencesManager: self)
        preferencesWindow?.contentViewController = preferencesViewController
    }
}

// MARK: - PreferencesViewController

class PreferencesViewController: NSViewController {
    // MARK: - Properties
    private weak var preferencesManager: PreferencesManager?

    // UI Controls
    private var showCPUCheckbox: NSButton!
    private var showGPUCheckbox: NSButton!
    private var showMemoryCheckbox: NSButton!
    private var showDiskCheckbox: NSButton!
    private var showTemperatureCheckbox: NSButton!
    private var showFanCheckbox: NSButton!
    private var showNetworkCheckbox: NSButton!
    private var displayOptionsTitleLabel: NSTextField!

    private var menuBarFormatPopup: NSPopUpButton!
    private var menuBarFormatTitleLabel: NSTextField!

    private var cpuThresholdSlider: NSSlider!
    private var cpuThresholdLabel: NSTextField!
    private var memoryThresholdSlider: NSSlider!
    private var memoryThresholdLabel: NSTextField!
    private var temperatureThresholdSlider: NSSlider!
    private var temperatureThresholdLabel: NSTextField!
    private var warningThresholdsTitleLabel: NSTextField!
    private var cpuThresholdTitleLabel: NSTextField!
    private var memoryThresholdTitleLabel: NSTextField!
    private var temperatureThresholdTitleLabel: NSTextField!
    private var launchAtLoginCheckbox: NSButton!

    private var autoRestartCheckbox: NSButton!
    private var autoRestartTitleLabel: NSTextField!

    private var languagePopup: NSPopUpButton!

    // MARK: - Initialization
    init(preferencesManager: PreferencesManager) {
        self.preferencesManager = preferencesManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View Lifecycle
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 450))
        setupUI()
        loadCurrentSettings()
    }

    // MARK: - UI Setup
    private func setupUI() {
        let scrollView = NSScrollView(frame: view.bounds)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.autoresizingMask = [.width, .height]

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 600))
        scrollView.documentView = contentView

        var yPosition: CGFloat = 560
        let margin: CGFloat = 20
        let controlHeight: CGFloat = 20
        let spacing: CGFloat = 10
        // Language Section
        let languageTitle = NSTextField(
            labelWithString: NSLocalizedString("prefs.language", comment: ""))
        languageTitle.font = NSFont.boldSystemFont(ofSize: 13)
        languageTitle.frame = NSRect(x: margin, y: yPosition, width: 200, height: controlHeight)
        contentView.addSubview(languageTitle)
        yPosition -= controlHeight + spacing

        languagePopup = NSPopUpButton(
            frame: NSRect(x: margin, y: yPosition, width: 220, height: controlHeight + 5))
        languagePopup.addItem(withTitle: NSLocalizedString("prefs.language.auto", comment: ""))
        languagePopup.lastItem?.representedObject = "auto"
        languagePopup.addItem(withTitle: NSLocalizedString("prefs.language.english", comment: ""))
        languagePopup.lastItem?.representedObject = "en"
        languagePopup.addItem(withTitle: NSLocalizedString("prefs.language.japanese", comment: ""))
        languagePopup.lastItem?.representedObject = "ja"
        languagePopup.addItem(
            withTitle: NSLocalizedString("prefs.language.chinese.simplified", comment: ""))
        languagePopup.lastItem?.representedObject = "zh-Hans"
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)
        contentView.addSubview(languagePopup)
        yPosition -= controlHeight + spacing * 2

        // Display Options Section
        displayOptionsTitleLabel = NSTextField(
            labelWithString: NSLocalizedString("prefs.displayOptions", comment: ""))
        displayOptionsTitleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        displayOptionsTitleLabel.frame = NSRect(
            x: margin, y: yPosition, width: 200, height: controlHeight)
        contentView.addSubview(displayOptionsTitleLabel)
        yPosition -= controlHeight + spacing

        // Checkboxes for display options
        showCPUCheckbox = createCheckbox(
            title: NSLocalizedString("prefs.showCPU", comment: ""), y: yPosition,
            contentView: contentView)
        yPosition -= controlHeight + spacing

        showGPUCheckbox = createCheckbox(
            title: NSLocalizedString("prefs.showGPU", comment: ""), y: yPosition,
            contentView: contentView)
        yPosition -= controlHeight + spacing

        showMemoryCheckbox = createCheckbox(
            title: NSLocalizedString("prefs.showMemory", comment: ""), y: yPosition,
            contentView: contentView)
        yPosition -= controlHeight + spacing

        showDiskCheckbox = createCheckbox(
            title: NSLocalizedString("prefs.showDisk", comment: ""), y: yPosition,
            contentView: contentView)
        yPosition -= controlHeight + spacing

        showTemperatureCheckbox = createCheckbox(
            title: NSLocalizedString("prefs.showTemperature", comment: ""), y: yPosition,
            contentView: contentView)
        yPosition -= controlHeight + spacing

        showFanCheckbox = createCheckbox(
            title: NSLocalizedString("prefs.showFan", comment: ""), y: yPosition,
            contentView: contentView)
        yPosition -= controlHeight + spacing

        showNetworkCheckbox = createCheckbox(
            title: NSLocalizedString("prefs.showNetwork", comment: ""), y: yPosition,
            contentView: contentView)
        yPosition -= controlHeight + spacing * 2

        // Menu Bar Format Section
        menuBarFormatTitleLabel = NSTextField(
            labelWithString: NSLocalizedString("prefs.menuBarFormat", comment: ""))
        menuBarFormatTitleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        menuBarFormatTitleLabel.frame = NSRect(
            x: margin, y: yPosition, width: 200, height: controlHeight)
        contentView.addSubview(menuBarFormatTitleLabel)
        yPosition -= controlHeight + spacing

        menuBarFormatPopup = NSPopUpButton(
            frame: NSRect(x: margin, y: yPosition, width: 200, height: controlHeight + 5))
        menuBarFormatPopup.removeAllItems()
        menuBarFormatPopup.addItem(withTitle: MenuBarFormat.twoLine.rawValue)
        menuBarFormatPopup.target = self
        menuBarFormatPopup.action = #selector(menuBarFormatChanged)
        contentView.addSubview(menuBarFormatPopup)
        yPosition -= controlHeight + spacing * 2

        // Warning Thresholds Section
        warningThresholdsTitleLabel = NSTextField(
            labelWithString: NSLocalizedString("prefs.warningThresholds", comment: ""))
        warningThresholdsTitleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        warningThresholdsTitleLabel.frame = NSRect(
            x: margin, y: yPosition, width: 200, height: controlHeight)
        contentView.addSubview(warningThresholdsTitleLabel)
        yPosition -= controlHeight + spacing

        // CPU Threshold
        cpuThresholdTitleLabel = NSTextField(
            labelWithString: NSLocalizedString("prefs.cpuWarning", comment: ""))
        cpuThresholdTitleLabel.frame = NSRect(
            x: margin, y: yPosition, width: 150, height: controlHeight)
        contentView.addSubview(cpuThresholdTitleLabel)

        cpuThresholdSlider = NSSlider(
            frame: NSRect(x: margin + 160, y: yPosition, width: 200, height: controlHeight))
        cpuThresholdSlider.minValue = 50.0
        cpuThresholdSlider.maxValue = 95.0
        cpuThresholdSlider.target = self
        cpuThresholdSlider.action = #selector(cpuThresholdChanged)
        contentView.addSubview(cpuThresholdSlider)

        cpuThresholdLabel = NSTextField(labelWithString: "80%")
        cpuThresholdLabel.frame = NSRect(
            x: margin + 370, y: yPosition, width: 50, height: controlHeight)
        contentView.addSubview(cpuThresholdLabel)
        yPosition -= controlHeight + spacing

        // Memory Threshold
        memoryThresholdTitleLabel = NSTextField(
            labelWithString: NSLocalizedString("prefs.memoryWarning", comment: ""))
        memoryThresholdTitleLabel.frame = NSRect(
            x: margin, y: yPosition, width: 150, height: controlHeight)
        contentView.addSubview(memoryThresholdTitleLabel)

        memoryThresholdSlider = NSSlider(
            frame: NSRect(x: margin + 160, y: yPosition, width: 200, height: controlHeight))
        memoryThresholdSlider.minValue = 50.0
        memoryThresholdSlider.maxValue = 95.0
        memoryThresholdSlider.target = self
        memoryThresholdSlider.action = #selector(memoryThresholdChanged)
        contentView.addSubview(memoryThresholdSlider)

        memoryThresholdLabel = NSTextField(labelWithString: "80%")
        memoryThresholdLabel.frame = NSRect(
            x: margin + 370, y: yPosition, width: 50, height: controlHeight)
        contentView.addSubview(memoryThresholdLabel)
        yPosition -= controlHeight + spacing

        // Temperature Threshold
        temperatureThresholdTitleLabel = NSTextField(
            labelWithString: NSLocalizedString("prefs.tempWarning", comment: ""))
        temperatureThresholdTitleLabel.frame = NSRect(
            x: margin, y: yPosition, width: 150, height: controlHeight)
        contentView.addSubview(temperatureThresholdTitleLabel)

        temperatureThresholdSlider = NSSlider(
            frame: NSRect(x: margin + 160, y: yPosition, width: 200, height: controlHeight))
        temperatureThresholdSlider.minValue = 60.0
        temperatureThresholdSlider.maxValue = 100.0
        temperatureThresholdSlider.target = self
        temperatureThresholdSlider.action = #selector(temperatureThresholdChanged)
        contentView.addSubview(temperatureThresholdSlider)

        temperatureThresholdLabel = NSTextField(labelWithString: "80°C")
        temperatureThresholdLabel.frame = NSRect(
            x: margin + 370, y: yPosition, width: 60, height: controlHeight)
        contentView.addSubview(temperatureThresholdLabel)
        yPosition -= controlHeight + spacing * 2

        // Auto-restart Section
        autoRestartTitleLabel = NSTextField(
            labelWithString: NSLocalizedString("prefs.appManagement", comment: ""))
        autoRestartTitleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        autoRestartTitleLabel.frame = NSRect(
            x: margin, y: yPosition, width: 200, height: controlHeight)
        contentView.addSubview(autoRestartTitleLabel)
        yPosition -= controlHeight + spacing

        autoRestartCheckbox = createCheckbox(
            title: NSLocalizedString("prefs.autoRestart", comment: ""), y: yPosition,
            contentView: contentView)
        autoRestartCheckbox.target = self
        autoRestartCheckbox.action = #selector(autoRestartChanged)
        yPosition -= controlHeight + spacing * 2

        // Launch at login
        launchAtLoginCheckbox = createCheckbox(
            title: NSLocalizedString("prefs.launchAtLogin", comment: ""), y: yPosition,
            contentView: contentView)
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginChanged)
        yPosition -= controlHeight + spacing

        // View logs button
        let logsButton = NSButton(
            frame: NSRect(x: margin, y: yPosition, width: 140, height: 28))
        logsButton.title = NSLocalizedString("prefs.viewLogs", comment: "")
        logsButton.bezelStyle = .rounded
        logsButton.target = self
        logsButton.action = #selector(openLogsFolder)
        contentView.addSubview(logsButton)
        yPosition -= 28 + spacing * 2

        // Adjust document view height to fit all subviews to enable scrolling for overflowing content
        let maxY = contentView.subviews.map { $0.frame.maxY }.max() ?? contentView.frame.height
        let requiredHeight = max(maxY + 40, scrollView.bounds.height)
        contentView.setFrameSize(NSSize(width: contentView.frame.width, height: requiredHeight))

        view.addSubview(scrollView)
    }

    private func createCheckbox(title: String, y: CGFloat, contentView: NSView) -> NSButton {
        let checkbox = NSButton(frame: NSRect(x: 20, y: y, width: 300, height: 20))
        checkbox.setButtonType(.switch)
        checkbox.title = title
        checkbox.target = self
        checkbox.action = #selector(displayOptionChanged)
        contentView.addSubview(checkbox)
        return checkbox
    }

    // MARK: - Settings Management
    private func loadCurrentSettings() {
        guard let preferencesManager = preferencesManager else { return }

        // Display options
        let displayOptions = preferencesManager.displayOptions
        showCPUCheckbox.state = displayOptions.showCPU ? .on : .off
        showGPUCheckbox.state = displayOptions.showGPU ? .on : .off
        showMemoryCheckbox.state = displayOptions.showMemory ? .on : .off
        showDiskCheckbox.state = displayOptions.showDisk ? .on : .off
        showTemperatureCheckbox.state = displayOptions.showTemperature ? .on : .off
        showFanCheckbox.state = displayOptions.showFan ? .on : .off
        showNetworkCheckbox.state = displayOptions.showNetwork ? .on : .off

        // Menu bar format
        menuBarFormatPopup.selectItem(withTitle: displayOptions.menuBarFormat.rawValue)

        // Warning thresholds
        let thresholds = preferencesManager.warningThresholds
        cpuThresholdSlider.doubleValue = thresholds.cpuUsage
        cpuThresholdLabel.stringValue = String(format: "%.0f%%", thresholds.cpuUsage)

        memoryThresholdSlider.doubleValue = thresholds.memoryUsage
        memoryThresholdLabel.stringValue = String(format: "%.0f%%", thresholds.memoryUsage)

        temperatureThresholdSlider.doubleValue = thresholds.temperature
        temperatureThresholdLabel.stringValue = String(format: "%.0f°C", thresholds.temperature)

        // Auto-restart setting
        autoRestartCheckbox.state = preferencesManager.isAutoRestartEnabled ? .on : .off
        launchAtLoginCheckbox.state = preferencesManager.isLaunchAtLoginEnabled ? .on : .off

        // Language selection
        let currentLang = preferencesManager.languageOverride
        for item in languagePopup.itemArray {
            if let code = item.representedObject as? String, code == currentLang {
                languagePopup.select(item)
                break
            }
        }
    }

    // MARK: - Actions
    @objc private func displayOptionChanged() {
        guard let preferencesManager = preferencesManager else { return }

        var displayOptions = preferencesManager.displayOptions
        displayOptions.showCPU = showCPUCheckbox.state == .on
        displayOptions.showGPU = showGPUCheckbox.state == .on
        displayOptions.showMemory = showMemoryCheckbox.state == .on
        displayOptions.showDisk = showDiskCheckbox.state == .on
        displayOptions.showTemperature = showTemperatureCheckbox.state == .on
        displayOptions.showFan = showFanCheckbox.state == .on
        displayOptions.showNetwork = showNetworkCheckbox.state == .on

        preferencesManager.displayOptions = displayOptions
    }

    @objc private func menuBarFormatChanged() {
        guard let preferencesManager = preferencesManager,
            let selectedTitle = menuBarFormatPopup.selectedItem?.title,
            let format = MenuBarFormat(rawValue: selectedTitle)
        else { return }

        var displayOptions = preferencesManager.displayOptions
        displayOptions.menuBarFormat = format
        preferencesManager.displayOptions = displayOptions
    }

    @objc private func languageChanged() {
        guard let preferencesManager = preferencesManager,
            let item = languagePopup.selectedItem,
            let code = item.representedObject as? String
        else { return }
        preferencesManager.languageOverride = code
        // Optionally refresh current window titles using localization
        // Reload UI text to reflect updated language immediately
        refreshLocalizedTexts()
        loadCurrentSettings()
    }

    private func refreshLocalizedTexts() {
        // Section titles
        displayOptionsTitleLabel.stringValue = NSLocalizedString(
            "prefs.displayOptions", comment: "")
        menuBarFormatTitleLabel.stringValue = NSLocalizedString("prefs.menuBarFormat", comment: "")
        warningThresholdsTitleLabel.stringValue = NSLocalizedString(
            "prefs.warningThresholds", comment: "")
        autoRestartTitleLabel.stringValue = NSLocalizedString("prefs.appManagement", comment: "")
        // Checkbox titles
        showCPUCheckbox.title = NSLocalizedString("prefs.showCPU", comment: "")
        showGPUCheckbox.title = NSLocalizedString("prefs.showGPU", comment: "")
        showMemoryCheckbox.title = NSLocalizedString("prefs.showMemory", comment: "")
        showDiskCheckbox.title = NSLocalizedString("prefs.showDisk", comment: "")
        showTemperatureCheckbox.title = NSLocalizedString("prefs.showTemperature", comment: "")
        showFanCheckbox.title = NSLocalizedString("prefs.showFan", comment: "")
        showNetworkCheckbox.title = NSLocalizedString("prefs.showNetwork", comment: "")
        // Threshold titles
        cpuThresholdTitleLabel.stringValue = NSLocalizedString("prefs.cpuWarning", comment: "")
        memoryThresholdTitleLabel.stringValue = NSLocalizedString(
            "prefs.memoryWarning", comment: "")
        temperatureThresholdTitleLabel.stringValue = NSLocalizedString(
            "prefs.tempWarning", comment: "")
        // Buttons (bottom)
        if let window = view.window { window.title = NSLocalizedString("prefs.title", comment: "") }
    }

    @objc private func cpuThresholdChanged() {
        let threshold = cpuThresholdSlider.doubleValue
        var thresholds = preferencesManager?.warningThresholds ?? WarningThresholds()
        thresholds.cpuUsage = threshold
        preferencesManager?.warningThresholds = thresholds
        cpuThresholdLabel.stringValue = String(format: "%.0f%%", threshold)
    }

    @objc private func memoryThresholdChanged() {
        let threshold = memoryThresholdSlider.doubleValue
        var thresholds = preferencesManager?.warningThresholds ?? WarningThresholds()
        thresholds.memoryUsage = threshold
        preferencesManager?.warningThresholds = thresholds
        memoryThresholdLabel.stringValue = String(format: "%.0f%%", threshold)
    }

    @objc private func temperatureThresholdChanged() {
        let threshold = temperatureThresholdSlider.doubleValue
        var thresholds = preferencesManager?.warningThresholds ?? WarningThresholds()
        thresholds.temperature = threshold
        preferencesManager?.warningThresholds = thresholds
        temperatureThresholdLabel.stringValue = String(format: "%.0f°C", threshold)
    }

    @objc private func autoRestartChanged() {
        preferencesManager?.isAutoRestartEnabled = autoRestartCheckbox.state == .on
    }

    @objc private func launchAtLoginChanged() {
        preferencesManager?.isLaunchAtLoginEnabled = launchAtLoginCheckbox.state == .on
    }

    @objc private func openLogsFolder() {
        let fm = FileManager.default
        let logsURL = fm.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("SystemMonitor", isDirectory: true)
        do {
            try fm.createDirectory(at: logsURL, withIntermediateDirectories: true)
            NSWorkspace.shared.open(logsURL)
        } catch {
            NSLog("Failed to open logs folder: \(error.localizedDescription)")
        }
    }

    @objc private func resetToDefaults() {
        preferencesManager?.resetToDefaults()
        loadCurrentSettings()
    }

    @objc private func closeWindow() {
        view.window?.close()
    }
}
