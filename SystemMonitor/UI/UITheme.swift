import Cocoa

/// Centralized UI theme helpers for colors and formatting
enum UITheme {
    // MARK: - Usage Colors

    /// Color for general "usage" style values (CPU, memory, disk, etc.)
    static func usageColor(_ value: Double) -> NSColor {
        switch value {
        case 90...:
            return .systemRed
        case 75..<90:
            return .systemOrange
        case 50..<75:
            return .systemYellow
        default:
            return .systemGreen
        }
    }

    // MARK: - Temperature Colors

    /// Color for temperature values in °C
    static func temperatureColor(_ temperature: Double) -> NSColor {
        switch temperature {
        case 85...:
            return .systemRed
        case 70..<85:
            return .systemOrange
        case 60..<70:
            return .systemYellow
        default:
            return .systemGreen
        }
    }

    // MARK: - Memory Pressure Colors

    static func pressureColor(_ pressure: MemoryPressure) -> NSColor {
        switch pressure {
        case .critical:
            return .systemRed
        case .warning:
            return .systemOrange
        case .normal:
            return .systemGreen
        }
    }
}
