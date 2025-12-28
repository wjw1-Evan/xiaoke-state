import Cocoa

class StatusBarManager {
    // MARK: - Properties
    private var statusItem: NSStatusItem?
    private var menuBuilder: MenuBuilder
    private var warningThresholds: WarningThresholds
    private var displayOptions: DisplayOptions

    // MARK: - Initialization
    init(
        menuBuilder: MenuBuilder,
        warningThresholds: WarningThresholds = WarningThresholds(),
        displayOptions: DisplayOptions = DisplayOptions()
    ) {
        self.menuBuilder = menuBuilder
        self.warningThresholds = warningThresholds
        self.displayOptions = displayOptions
    }

    // MARK: - Public Methods

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let statusItem = statusItem else { return }

        // Configure button appearance
        if let button = statusItem.button {
            // Configure initial appearance based on display options
            applyMenuBarFormat(to: button)
            // Initial content
            if displayOptions.menuBarFormat == .twoLine {
                button.title = ""
                button.imagePosition = .imageOnly
                button.image = createTwoLinePlaceholderImage()
            } else {
                button.title = "--"
                button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            }

            button.toolTip = NSLocalizedString("statusbar.tooltip", comment: "")

            // Add right-click support
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
            button.action = #selector(statusItemClicked(_:))
        }

        // Set up menu
        statusItem.menu = menuBuilder.buildMenu()
    }

    private func createStatusBarIcon() -> NSImage {
        // Create a simple icon using SF Symbols or a custom image
        if #available(macOS 11.0, *) {
            // Use SF Symbols for modern macOS
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            if let sfSymbol = NSImage(
                systemSymbolName: "chart.bar.fill", accessibilityDescription: "System Monitor")
            {
                return sfSymbol.withSymbolConfiguration(config) ?? createFallbackIcon()
            }
        }
        // Fallback: create a simple custom icon
        return createFallbackIcon()
    }

    private func createFallbackIcon() -> NSImage {
        // Create a simple custom icon (16x16 pixels for menu bar)
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)

        image.lockFocus()

        // Draw a simple chart/bar icon
        let context = NSGraphicsContext.current?.cgContext
        // Use system blue color for compatibility
        let fillColor = NSColor.systemBlue
        context?.setFillColor(fillColor.cgColor)
        context?.setStrokeColor(fillColor.cgColor)
        context?.setLineWidth(1.5)

        // Draw bars representing a chart
        let barWidth: CGFloat = 3
        let spacing: CGFloat = 2
        let startX: CGFloat = 2
        let startY: CGFloat = 2

        // Bar 1 (short)
        context?.fill(CGRect(x: startX, y: startY, width: barWidth, height: 4))

        // Bar 2 (medium)
        context?.fill(CGRect(x: startX + barWidth + spacing, y: startY, width: barWidth, height: 7))

        // Bar 3 (tall)
        context?.fill(
            CGRect(x: startX + (barWidth + spacing) * 2, y: startY, width: barWidth, height: 10))

        // Bar 4 (medium)
        context?.fill(
            CGRect(x: startX + (barWidth + spacing) * 3, y: startY, width: barWidth, height: 6))

        image.unlockFocus()
        image.isTemplate = true  // Allow system to tint the icon

        return image
    }

    func updateStatusDisplay(with data: SystemData) {
        guard let statusItem = statusItem else { return }

        DispatchQueue.main.async {
            // Update status bar content according to display options
            if let button = statusItem.button {
                // Apply icon/text format
                self.applyMenuBarFormat(to: button)
                if self.displayOptions.menuBarFormat == .twoLine {
                    let parts = self.buildTwoLineStatusParts(from: data)
                    button.image = self.createTwoLineStatusImage(
                        parts: parts.parts, color: parts.color)
                    button.title = ""
                    button.imagePosition = .imageOnly
                } else {
                    // Build composite text from selected components
                    button.title = self.buildStatusBarText(from: data)
                }
            }

            // Update color based on warning thresholds
            if self.displayOptions.menuBarFormat != .twoLine {
                self.updateStatusColor(for: data.cpu.usage)
            }

            // Update menu with latest data
            statusItem.menu = self.menuBuilder.buildMenu(with: data)
        }
    }

    func updateWarningThresholds(_ thresholds: WarningThresholds) {
        warningThresholds = thresholds
    }

    func updateDisplayOptions(_ options: DisplayOptions) {
        displayOptions = options
        // Apply format immediately if status item exists
        if let button = statusItem?.button {
            applyMenuBarFormat(to: button)
            if displayOptions.menuBarFormat == .twoLine {
                // Ensure there is at least a placeholder image when switching modes before data arrives
                button.image = createTwoLinePlaceholderImage()
                button.title = ""
                button.imagePosition = .imageOnly
            }
        }
    }

    func hideStatusItem() {
        statusItem = nil
    }

    // MARK: - Right-click Menu Support

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            // Show right-click context menu
            showRightClickMenu()
        } else {
            // Show normal menu (left click)
            showNormalMenu()
        }
    }

    private func showRightClickMenu() {
        guard let statusItem = statusItem else { return }

        let contextMenu = menuBuilder.buildRightClickMenu()
        statusItem.menu = contextMenu
        statusItem.button?.performClick(nil)

        // Restore normal menu after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            statusItem.menu = self.menuBuilder.buildMenu()
        }
    }

    private func showNormalMenu() {
        guard let statusItem = statusItem else { return }
        // 直接展示当前菜单（保持最新数据），避免在点击时重建菜单导致数据空白/暂停
        statusItem.button?.performClick(nil)
    }

    // MARK: - Private Methods

    private func updateStatusColor(for cpuUsage: Double) {
        guard let button = statusItem?.button else { return }

        if cpuUsage >= warningThresholds.cpuUsage {
            // High usage - red color
            button.attributedTitle = NSAttributedString(
                string: button.title,
                attributes: [
                    .foregroundColor: NSColor.systemRed,
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
                ]
            )
        } else if cpuUsage >= warningThresholds.cpuUsage * 0.75 {
            // Medium usage - orange color
            button.attributedTitle = NSAttributedString(
                string: button.title,
                attributes: [
                    .foregroundColor: NSColor.systemOrange,
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular),
                ]
            )
        } else {
            // Normal usage - default color
            button.attributedTitle = NSAttributedString(
                string: button.title,
                attributes: [
                    .foregroundColor: NSColor.controlTextColor,
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular),
                ]
            )
        }
    }

    // Refresh localized texts (tooltip and menu) after language changes
    func refreshLocalizedTexts() {
        guard let statusItem = statusItem else { return }
        if let button = statusItem.button {
            button.toolTip = NSLocalizedString("statusbar.tooltip", comment: "")
        }
        statusItem.menu = menuBuilder.buildMenu()
    }

    // MARK: - Status bar content helpers

    private func applyMenuBarFormat(to button: NSStatusBarButton) {
        // Only twoLine is supported; ensure placeholder image exists
        button.imagePosition = .imageOnly
        button.title = ""
        if button.image == nil {
            button.image = createTwoLinePlaceholderImage()
        }
    }

    private func buildStatusBarText(from data: SystemData) -> String {
        var parts: [String] = []
        if displayOptions.showCPU {
            parts.append(String(format: "\(localizedShort("short.cpu")) %.0f%%", data.cpu.usage))
        }
        if displayOptions.showMemory {
            parts.append(
                String(format: "\(localizedShort("short.mem")) %.0f%%", data.memory.usagePercentage)
            )
        }
        if displayOptions.showGPU, let gpu = data.gpu {
            parts.append(String(format: "\(localizedShort("short.gpu")) %.0f%%", gpu.usage))
        }
        if displayOptions.showTemperature {
            if let t = data.temperature?.cpuTemperature {
                let tempLabel = localizedShort("short.cpu")
                parts.append(String(format: "\(tempLabel) %.0f℃", t))
            }
        }
        if displayOptions.showFan {
            let fanLabel = localizedShort("short.fan")
            if let rpm = data.temperature?.fanSpeed {
                parts.append("\(fanLabel) \(rpm)RPM")
            } else {
                parts.append("\(fanLabel) --")
            }
        }
        if displayOptions.showNetwork, let net = data.network {
            let up = formatBytes(net.uploadSpeed)
            let down = formatBytes(net.downloadSpeed)
            parts.append("↑" + up + " ↓" + down)
        }
        if displayOptions.showDisk, !data.disk.isEmpty {
            let totalUsed = data.disk.reduce(0) { $0 + $1.used }
            let totalSpace = data.disk.reduce(0) { $0 + $1.total }
            let percentage = totalSpace > 0 ? Double(totalUsed) / Double(totalSpace) * 100.0 : 0.0
            parts.append(String(format: "\(localizedShort("short.disk")) %.0f%%", percentage))
        }

        if parts.isEmpty {
            return "--"
        }
        return parts.joined(separator: " • ")
    }

    // MARK: - Two-line status image rendering

    private struct StatusPart {
        let label: String
        let value: String
        let severity: Int
    }

    private func buildTwoLineStatusParts(from data: SystemData) -> (
        parts: [StatusPart], color: NSColor
    ) {
        // Collect all enabled metrics, then render them into aligned columns.
        var parts: [StatusPart] = []

        func severity(for color: NSColor) -> Int {
            // 0: normal, 1: yellow, 2: orange, 3: red
            switch color {
            case NSColor.systemRed: return 3
            case NSColor.systemOrange: return 2
            case NSColor.systemYellow: return 1
            default: return 0
            }
        }

        if displayOptions.showCPU {
            let label = localizedShort("short.cpu")
            let value = String(format: "%.0f%%", data.cpu.usage)
            let color = getUsageColor(data.cpu.usage)
            parts.append(StatusPart(label: label, value: value, severity: severity(for: color)))
        }

        if displayOptions.showMemory {
            let label = localizedShort("short.mem")
            let value = String(format: "%.0f%%", data.memory.usagePercentage)
            let color = getUsageColor(data.memory.usagePercentage)
            parts.append(StatusPart(label: label, value: value, severity: severity(for: color)))
        }

        if displayOptions.showGPU, let gpu = data.gpu {
            let label = localizedShort("short.gpu")
            let value = String(format: "%.0f%%", gpu.usage)
            let color = getUsageColor(gpu.usage)
            parts.append(StatusPart(label: label, value: value, severity: severity(for: color)))
        }

        if displayOptions.showTemperature, let t = data.temperature?.cpuTemperature {
            let label = localizedShort("short.cpu")
            let value = String(format: "%.0f℃", t)
            let color = getTemperatureColor(t)
            parts.append(StatusPart(label: label, value: value, severity: severity(for: color)))
        }

        if displayOptions.showFan {
            let label = localizedShort("short.fan")
            if let rpm = data.temperature?.fanSpeed {
                let value = "\(rpm)RPM"
                parts.append(StatusPart(label: label, value: value, severity: 0))
            } else {
                parts.append(StatusPart(label: label, value: "--", severity: 0))
            }
        }

        if displayOptions.showNetwork, let net = data.network {
            let label = localizedShort("short.net")
            let value = "↑" + formatBytes(net.uploadSpeed) + " ↓" + formatBytes(net.downloadSpeed)
            parts.append(StatusPart(label: label, value: value, severity: 0))
        }

        if displayOptions.showDisk, !data.disk.isEmpty {
            let label = localizedShort("short.disk")
            let totalUsed = data.disk.reduce(0) { $0 + $1.used }
            let totalSpace = data.disk.reduce(0) { $0 + $1.total }
            let percentage = totalSpace > 0 ? Double(totalUsed) / Double(totalSpace) * 100.0 : 0.0
            let value = String(format: "%.0f%%", percentage)
            let color = getUsageColor(percentage)
            parts.append(StatusPart(label: label, value: value, severity: severity(for: color)))
        }

        if parts.isEmpty {
            return (
                [StatusPart(label: localizedShort("short.cpu"), value: "--", severity: 0)],
                NSColor.controlTextColor
            )
        }

        // Choose the highest severity color among parts
        let maxSeverity = parts.map { $0.severity }.max() ?? 0
        let color: NSColor
        switch maxSeverity {
        case 3: color = NSColor.systemRed
        case 2: color = NSColor.systemOrange
        case 1: color = NSColor.systemYellow
        default: color = NSColor.controlTextColor
        }

        return (parts, color)
    }

    private func createTwoLinePlaceholderImage() -> NSImage {
        let placeholderPart = StatusPart(
            label: localizedShort("short.cpu"), value: "--", severity: 0)
        return createTwoLineStatusImage(parts: [placeholderPart], color: NSColor.controlTextColor)
    }

    private func createTwoLineStatusImage(parts: [StatusPart], color: NSColor) -> NSImage {
        // Compute status bar height
        let height = NSStatusBar.system.thickness
        // Fonts: compact top label, clearer bottom value
        let topFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
        let bottomFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

        let topAttrs: [NSAttributedString.Key: Any] = [
            .font: topFont,
            .foregroundColor: NSColor.controlTextColor,
        ]
        let bottomAttrs: [NSAttributedString.Key: Any] = [
            .font: bottomFont,
            .foregroundColor: color,
        ]

        let paddingX: CGFloat = 4
        let columnSpacing: CGFloat = 6

        // Measure per-column widths (align labels and values to same start x per column)
        var columnWidths: [CGFloat] = []
        for part in parts {
            let labelWidth = (part.label as NSString).size(withAttributes: topAttrs).width
            let valueWidth = (part.value as NSString).size(withAttributes: bottomAttrs).width
            columnWidths.append(max(labelWidth, valueWidth))
        }

        let totalWidth =
            columnWidths.reduce(0, +)
            + columnSpacing * CGFloat(max(0, columnWidths.count - 1))
            + paddingX * 2

        let imageSize = NSSize(width: ceil(totalWidth), height: ceil(height))
        let image = NSImage(size: imageSize)

        image.lockFocus()
        defer { image.unlockFocus() }

        // Baseline positions: split the available height into two lines
        let ctx = NSGraphicsContext.current?.cgContext
        ctx?.saveGState()
        defer { ctx?.restoreGState() }

        let topY = height * 0.58  // slightly above center
        let bottomY = height * 0.18  // lower baseline

        var currentX = paddingX
        for (index, part) in parts.enumerated() {
            let labelSize = (part.label as NSString).size(withAttributes: topAttrs)
            let valueSize = (part.value as NSString).size(withAttributes: bottomAttrs)

            (part.label as NSString).draw(
                at: NSPoint(x: currentX, y: topY - labelSize.height / 2), withAttributes: topAttrs)
            (part.value as NSString).draw(
                at: NSPoint(x: currentX, y: bottomY - valueSize.height / 2),
                withAttributes: bottomAttrs)

            currentX += columnWidths[index] + columnSpacing
        }

        // Template image allows system tint if needed; but we use explicit colors for value
        image.isTemplate = false
        return image
    }

    private func getUsageColor(_ usage: Double) -> NSColor {
        if usage >= 90.0 {
            return NSColor.systemRed
        } else if usage >= 75.0 {
            return NSColor.systemOrange
        } else if usage >= 50.0 {
            return NSColor.systemYellow
        } else {
            return NSColor.controlTextColor
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
            return NSColor.controlTextColor
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func localizedShort(_ key: String) -> String {
        return NSLocalizedString(key, comment: "")
    }
}
