import Cocoa

class MenuBuilder {
    // Localization helper
    private func localized(_ key: String, comment: String = "") -> String {
        return NSLocalizedString(key, comment: comment)
    }
    // MARK: - Properties
    private var displayOptions: DisplayOptions
    private weak var preferencesManager: PreferencesManager?

    // MARK: - Initialization
    init(
        displayOptions: DisplayOptions = DisplayOptions(),
        preferencesManager: PreferencesManager? = nil
    ) {
        self.displayOptions = displayOptions
        self.preferencesManager = preferencesManager
    }

    // MARK: - Public Methods

    func buildMenu(with data: SystemData? = nil) -> NSMenu {
        let menu = NSMenu()

        if let systemData = data {
            addSystemInfoItems(to: menu, with: systemData)
            menu.addItem(NSMenuItem.separator())
        }

        addControlItems(to: menu)

        return menu
    }

    func buildRightClickMenu() -> NSMenu {
        let menu = NSMenu()

        // Quick actions for right-click
        let preferencesItem = NSMenuItem(
            title: localized("app.preferences"),
            action: #selector(showPreferences),
            keyEquivalent: ","
        )
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(
            title: localized("app.about"),
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(
            title: localized("app.quit"),
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    func updateDisplayOptions(_ options: DisplayOptions) {
        displayOptions = options
    }

    // MARK: - Private Methods

    private func addSystemInfoItems(to menu: NSMenu, with data: SystemData) {
        // Add header with timestamp
        let appName = appDisplayName(localized("app.name"))
        let headerItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        let headerFont = NSFont.boldSystemFont(ofSize: 12)
        headerItem.attributedTitle = NSAttributedString(
            string: appName,
            attributes: [.font: headerFont, .foregroundColor: NSColor.controlTextColor]
        )
        menu.addItem(headerItem)

        let updatedText = String(
            format: localized("statusbar.updated"), formatTimestamp(data.timestamp))
        let timestampItem = NSMenuItem(
            title: "  \(updatedText)",
            action: nil,
            keyEquivalent: ""
        )
        timestampItem.isEnabled = false
        let timestampFont = NSFont.systemFont(ofSize: 10)
        timestampItem.attributedTitle = NSAttributedString(
            string: "  \(updatedText)",
            attributes: [.font: timestampFont, .foregroundColor: NSColor.secondaryLabelColor]
        )
        menu.addItem(timestampItem)

        menu.addItem(NSMenuItem.separator())

        // CPU Information
        if displayOptions.showCPU {
            addCPUSection(to: menu, with: data.cpu)
        }

        // Memory Information
        if displayOptions.showMemory {
            addMemorySection(to: menu, with: data.memory)
        }

        // GPU Information (if available)
        if displayOptions.showGPU, let gpu = data.gpu {
            addGPUSection(to: menu, with: gpu)
        }

        // Temperature / fan Information
        if displayOptions.showTemperature || displayOptions.showFan {
            addTemperatureSection(to: menu, with: data.temperature)
        }

        // Network Information (if available)
        if displayOptions.showNetwork, let network = data.network {
            addNetworkSection(to: menu, with: network)
        }

        // Disk Information (if available)
        if displayOptions.showDisk && !data.disk.isEmpty {
            addDiskSection(to: menu, with: data.disk)
        }

        // Performance Information (if available)
        if let performance = data.performance {
            addPerformanceSection(to: menu, with: performance)
        }
    }

    private func addCPUSection(to menu: NSMenu, with cpu: CPUData) {
        let cpuItem = createSectionHeader(localized("menu.cpu"))
        menu.addItem(cpuItem)

        let usageColor = getUsageColor(cpu.usage)
        let cpuUsageText = String(format: localized("cpu.usage"), cpu.usage)
        let cpuUsageItem = createInfoItem(cpuUsageText, color: usageColor)
        menu.addItem(cpuUsageItem)

        let cpuCoresText = String(format: localized("cpu.cores"), cpu.coreCount)
        let cpuCoresItem = createInfoItem(cpuCoresText)
        menu.addItem(cpuCoresItem)

        let cpuFreqText = String(format: localized("cpu.frequency"), cpu.frequency)
        let cpuFreqItem = createInfoItem(cpuFreqText)
        menu.addItem(cpuFreqItem)

        menu.addItem(NSMenuItem.separator())
    }

    private func addMemorySection(to menu: NSMenu, with memory: MemoryData) {
        let memoryItem = createSectionHeader(localized("menu.memory"))
        menu.addItem(memoryItem)

        let usedGB = Double(memory.used) / (1024 * 1024 * 1024)
        let totalGB = Double(memory.total) / (1024 * 1024 * 1024)

        let usageColor = getUsageColor(memory.usagePercentage)
        let memoryUsageText = String(
            format: localized("memory.usage"), usedGB, totalGB, memory.usagePercentage)
        let memoryUsageItem = createInfoItem(memoryUsageText, color: usageColor)
        menu.addItem(memoryUsageItem)

        let pressureColor = getPressureColor(memory.pressure)
        let pressureText = localized("pressure.\(memory.pressure.rawValue.lowercased())")
        let memoryPressureText = String(format: localized("memory.pressure"), pressureText)
        let memoryPressureItem = createInfoItem(memoryPressureText, color: pressureColor)
        menu.addItem(memoryPressureItem)

        if memory.swapUsed > 0 {
            let swapGB = Double(memory.swapUsed) / (1024 * 1024 * 1024)
            let swapText = String(format: localized("memory.swap"), swapGB)
            let swapItem = createInfoItem(swapText)
            menu.addItem(swapItem)
        }

        menu.addItem(NSMenuItem.separator())
    }

    private func addGPUSection(to menu: NSMenu, with gpu: GPUData) {
        let gpuItem = createSectionHeader(localized("menu.gpu"))
        menu.addItem(gpuItem)

        let gpuNameText = String(format: localized("gpu.name"), gpu.name)
        let gpuNameItem = createInfoItem(gpuNameText)
        menu.addItem(gpuNameItem)

        let usageColor = getUsageColor(gpu.usage)
        let gpuUsageText = String(format: localized("gpu.usage"), gpu.usage)
        let gpuUsageItem = createInfoItem(gpuUsageText, color: usageColor)
        menu.addItem(gpuUsageItem)

        let gpuMemoryUsedGB = Double(gpu.memoryUsed) / (1024 * 1024 * 1024)
        let gpuMemoryTotalGB = Double(gpu.memoryTotal) / (1024 * 1024 * 1024)
        let gpuMemoryText = String(
            format: localized("gpu.memory"), gpuMemoryUsedGB, gpuMemoryTotalGB)
        let gpuMemoryItem = createInfoItem(gpuMemoryText)
        menu.addItem(gpuMemoryItem)

        menu.addItem(NSMenuItem.separator())
    }

    private func addTemperatureSection(to menu: NSMenu, with temperature: TemperatureData?) {
        let tempItem = createSectionHeader(localized("menu.temperature"))
        menu.addItem(tempItem)

        var hasContent = false

        if displayOptions.showTemperature, let cpuTemp = temperature?.cpuTemperature {
            let tempColor = getTemperatureColor(cpuTemp)
            let cpuTempText = String(format: localized("temp.cpu"), cpuTemp)
            let cpuTempItem = createInfoItem(cpuTempText, color: tempColor)
            menu.addItem(cpuTempItem)
            hasContent = true
        }

        if displayOptions.showTemperature, let gpuTemp = temperature?.gpuTemperature {
            let tempColor = getTemperatureColor(gpuTemp)
            let gpuTempText = String(format: localized("temp.gpu"), gpuTemp)
            let gpuTempItem = createInfoItem(gpuTempText, color: tempColor)
            menu.addItem(gpuTempItem)
            hasContent = true
        }

        if displayOptions.showFan {
            if let fanSpeed = temperature?.fanSpeed {
                let fanText = String(format: localized("temp.fan"), fanSpeed)
                let fanItem = createInfoItem(fanText)
                menu.addItem(fanItem)
                hasContent = true
            } else {
                // Show placeholder to make fan entry visible even when RPM is unavailable
                let fanPlaceholder = "\(localized("short.fan")): -- RPM"
                let fanItem = createInfoItem(fanPlaceholder)
                menu.addItem(fanItem)
            }
        }

        if !hasContent {
            let naItem = createInfoItem(localized("na"))
            menu.addItem(naItem)
        }

        menu.addItem(NSMenuItem.separator())
    }

    private func addNetworkSection(to menu: NSMenu, with network: NetworkData) {
        let networkItem = createSectionHeader(localized("menu.network"))
        menu.addItem(networkItem)

        let uploadMBps = Double(network.uploadSpeed) / (1024 * 1024)
        let downloadMBps = Double(network.downloadSpeed) / (1024 * 1024)

        let speedText = String(format: localized("network.speed"), uploadMBps, downloadMBps)
        let speedItem = createInfoItem(speedText)
        menu.addItem(speedItem)

        let totalUploadGB = Double(network.totalUploaded) / (1024 * 1024 * 1024)
        let totalDownloadGB = Double(network.totalDownloaded) / (1024 * 1024 * 1024)

        if totalUploadGB > 0.1 || totalDownloadGB > 0.1 {
            let totalText = String(
                format: localized("network.total"), totalUploadGB, totalDownloadGB)
            let totalItem = createInfoItem(totalText)
            menu.addItem(totalItem)
        }

        menu.addItem(NSMenuItem.separator())
    }

    private func addDiskSection(to menu: NSMenu, with disks: [DiskData]) {
        let diskItem = createSectionHeader(localized("menu.disk"))
        menu.addItem(diskItem)

        for disk in disks {
            let usedGB = Double(disk.used) / (1024 * 1024 * 1024)
            let totalGB = Double(disk.total) / (1024 * 1024 * 1024)

            let usageColor = getUsageColor(disk.usagePercentage)
            let diskInfoText = String(
                format: localized("disk.info"), disk.name, usedGB, totalGB, disk.usagePercentage)
            let diskInfoItem = createInfoItem(diskInfoText, color: usageColor)
            menu.addItem(diskInfoItem)

            if disk.readSpeed > 0 || disk.writeSpeed > 0 {
                let readMBps = Double(disk.readSpeed) / (1024 * 1024)
                let writeMBps = Double(disk.writeSpeed) / (1024 * 1024)
                let speedText = String(format: localized("disk.io"), readMBps, writeMBps)
                let speedItem = createInfoItem(speedText)
                menu.addItem(speedItem)
            }
        }

        menu.addItem(NSMenuItem.separator())
    }

    private func addPerformanceSection(to menu: NSMenu, with performance: PerformanceData) {
        let perfItem = createSectionHeader(localized("menu.performance"))
        menu.addItem(perfItem)

        let cpuColor = getUsageColor(performance.cpuUsagePercent)
        let appCpuText = String(format: localized("perf.cpu"), performance.cpuUsagePercent)
        let appCpuItem = createInfoItem(appCpuText, color: cpuColor)
        menu.addItem(appCpuItem)

        let appMemoryText = String(format: localized("perf.memory"), performance.memoryUsageMB)
        let appMemoryItem = createInfoItem(appMemoryText)
        menu.addItem(appMemoryItem)

        let threadsText = String(format: localized("perf.threads"), performance.threadCount)
        let threadsItem = createInfoItem(threadsText)
        menu.addItem(threadsItem)

        menu.addItem(NSMenuItem.separator())
    }

    // MARK: - Helper Methods for Menu Styling

    private func createSectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        let font = NSFont.boldSystemFont(ofSize: 11)
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: font, .foregroundColor: NSColor.controlTextColor]
        )
        return item
    }

    private func createInfoItem(_ title: String, color: NSColor = NSColor.controlTextColor)
        -> NSMenuItem
    {
        // 单行显示，若能拆分标题/数据则为数据部分着色
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = false

        let (label, value) = splitLabelAndValue(from: title)
        let font = NSFont.systemFont(ofSize: 10, weight: .regular)

        if let label = label, let value = value {
            let combined = "  \(label): \(value)"
            let attributed = NSMutableAttributedString(string: combined)

            let fullRange = NSRange(location: 0, length: (combined as NSString).length)
            attributed.addAttributes([
                .font: font,
                .foregroundColor: NSColor.controlTextColor,
            ], range: fullRange)

            let valueRange = (combined as NSString).range(of: value)
            if valueRange.location != NSNotFound {
                attributed.addAttributes([
                    .font: font,
                    .foregroundColor: color,
                ], range: valueRange)
            }

            item.attributedTitle = attributed
        } else {
            let combined = "  \(title)"
            item.attributedTitle = NSAttributedString(
                string: combined,
                attributes: [.font: font, .foregroundColor: color]
            )
        }

        return item
    }

    /// 将形如 "标题: 数据" 或 "标题：数据" 的文本拆分为 (标题, 数据)
    private func splitLabelAndValue(from text: String) -> (String?, String?) {
        // 去除前导缩进（MenuBuilder 里统一添加了两个空格缩进）
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 支持半角与全角冒号
        let separators: [Character] = [":", "："]
        if let idx = trimmed.firstIndex(where: { separators.contains($0) }) {
            let label = String(trimmed[..<idx]).trimmingCharacters(in: .whitespaces)
            // 跳过冒号本身
            let valueStart = trimmed.index(after: idx)
            let value = String(trimmed[valueStart...]).trimmingCharacters(in: .whitespaces)
            if !label.isEmpty && !value.isEmpty {
                return (label, value)
            }
        }
        return (nil, nil)
    }

    private func getUsageColor(_ usage: Double) -> NSColor {
        if usage >= 90.0 {
            return NSColor.systemRed
        } else if usage >= 75.0 {
            return NSColor.systemOrange
        } else if usage >= 50.0 {
            return NSColor.systemYellow
        } else {
            return NSColor.systemGreen
        }
    }

    private func getPressureColor(_ pressure: MemoryPressure) -> NSColor {
        switch pressure {
        case .critical:
            return NSColor.systemRed
        case .warning:
            return NSColor.systemOrange
        case .normal:
            return NSColor.systemGreen
        }
    }

    private func getTemperatureColor(_ temperature: Double) -> NSColor {
        if temperature >= 85.0 {
            return NSColor.systemRed
        } else if temperature >= 70.0 {
            return NSColor.systemOrange
        } else if temperature >= 60.0 {
            return NSColor.systemYellow
        } else {
            return NSColor.systemGreen
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func addControlItems(to menu: NSMenu) {
        // Preferences
        let preferencesItem = NSMenuItem(
            title: localized("app.preferences"),
            action: #selector(showPreferences),
            keyEquivalent: ","
        )
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        menu.addItem(NSMenuItem.separator())

        // About
        let aboutItem = NSMenuItem(
            title: localized("app.about"),
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        // Quit
        let quitItem = NSMenuItem(
            title: localized("app.quit"),
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Menu Actions

    @objc private func showPreferences() {
        preferencesManager?.showPreferencesWindow()
    }

    @objc private func showAbout() {
        // Create custom about window with more detailed information
        let aboutWindow = createAboutWindow()
        aboutWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApplication() {
        // Perform clean shutdown
        NSLog("System Monitor is shutting down...")

        // Save any pending settings
        preferencesManager?.saveSettings()

        // Graceful termination
        NSApplication.shared.terminate(nil)
    }

    // MARK: - About Window

    private func createAboutWindow() -> NSWindow {
        let windowRect = NSRect(x: 0, y: 0, width: 400, height: 300)
        let aboutWindow = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        aboutWindow.title = appDisplayName(localized("app.about"))
        aboutWindow.center()
        aboutWindow.isReleasedWhenClosed = false

        // Create content view
        let contentView = NSView(frame: windowRect)
        aboutWindow.contentView = contentView

        var yPosition: CGFloat = 250
        let margin: CGFloat = 20

        // App icon (if available)
        if let appIcon = NSApp.applicationIconImage {
            let iconView = NSImageView(
                frame: NSRect(x: 175, y: yPosition - 64, width: 64, height: 64))
            iconView.image = appIcon
            contentView.addSubview(iconView)
            yPosition -= 80
        }

        // App name
        let appNameLabel = NSTextField(labelWithString: localized("app.name"))
        appNameLabel.font = NSFont.boldSystemFont(ofSize: 18)
        appNameLabel.alignment = .center
        appNameLabel.frame = NSRect(x: margin, y: yPosition, width: 360, height: 25)
        contentView.addSubview(appNameLabel)
        yPosition -= 35

        // Version
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let versionLabel = NSTextField(labelWithString: "Version \(version) (Build \(build))")
        versionLabel.font = NSFont.systemFont(ofSize: 12)
        versionLabel.alignment = .center
        versionLabel.frame = NSRect(x: margin, y: yPosition, width: 360, height: 20)
        contentView.addSubview(versionLabel)
        yPosition -= 30

        // Description
        let descriptionText =
            "A lightweight macOS menu bar application for monitoring system performance including CPU, memory, GPU, temperature, network, and disk usage."
        let descriptionLabel = NSTextField(wrappingLabelWithString: descriptionText)
        descriptionLabel.font = NSFont.systemFont(ofSize: 11)
        descriptionLabel.alignment = .center
        descriptionLabel.frame = NSRect(x: margin, y: yPosition - 40, width: 360, height: 40)
        contentView.addSubview(descriptionLabel)
        yPosition -= 60

        // System info
        let systemInfo = getSystemInfo()
        let systemLabel = NSTextField(labelWithString: systemInfo)
        systemLabel.font = NSFont.systemFont(ofSize: 10)
        systemLabel.alignment = .center
        systemLabel.textColor = NSColor.secondaryLabelColor
        systemLabel.frame = NSRect(x: margin, y: yPosition, width: 360, height: 20)
        contentView.addSubview(systemLabel)
        yPosition -= 40

        // Close button
        let closeButton = NSButton(frame: NSRect(x: 160, y: 20, width: 80, height: 30))
        closeButton.title = localized("prefs.close")
        closeButton.bezelStyle = .rounded
        closeButton.target = aboutWindow
        closeButton.action = #selector(NSWindow.close)
        contentView.addSubview(closeButton)

        return aboutWindow
    }

    private func getSystemInfo() -> String {
        let processInfo = Foundation.ProcessInfo.processInfo
        let osVersion = processInfo.operatingSystemVersionString
        let hostName = processInfo.hostName

        return "Running on \(hostName) • \(osVersion)"
    }

    private func appDisplayName(_ localizedName: String) -> String {
        // If localization failed and returned key, fallback to bundle display name
        if localizedName == "app.name" || localizedName == "app.about" {
            let displayName =
                Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? localized("app.name")
            return displayName
        }
        return localizedName
    }
}
