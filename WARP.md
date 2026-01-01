# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project overview

This repository contains **macOS System Monitor**, a Swift/AppKit menu bar application that shows real‑time system metrics (CPU, GPU, memory, disk, temperature, network, and app performance) in the status bar and a detailed dropdown menu.

The app is implemented both as an Xcode project (`SystemMonitor.xcodeproj`) and a Swift Package (`Package.swift`) with an executable target `SystemMonitor` so it can be built and tested via Xcode or Swift Package Manager (SPM).

Key design goals (from the specs and implementation):
- Clear separation between data collection, UI, and user settings.
- Modular monitor implementations per subsystem (CPU, memory, GPU, disk, temperature, network).
- Low overhead via async data collection, adaptive polling frequency, and intelligent caching.
- Robustness: graceful degradation when system APIs/permissions are unavailable, plus crash auto‑restart.

## Build, run, and test

### Environment

From `README.md` and `Package.swift`:
- macOS 13.0+
- Xcode 15.0+
- Swift 5.9+

### Using Xcode

- Open the project:
  - `SystemMonitor.xcodeproj`
- Run the app:
  - Select the `SystemMonitor` scheme and press **⌘R**.
- Run tests:
  - Select the `SystemMonitor` scheme and press **⌘U**.

### Using Swift Package Manager (SPM)

All SPM commands should be run at the repository root (`/Users/mac/Projects/xiaoke-state`).

- Build the executable:
  - `swift build`
- Run the app (default executable target `SystemMonitor`):
  - `swift run`
- Run the full test suite (XCTest + SwiftCheck):
  - `swift test`
- Run a single test or test case (example):
  - `swift test --filter SystemMonitorTests/testMemoryMonitorDataCollection`
  - `swift test --filter SystemMonitorTests`

## High‑level architecture

### Entry point and application lifecycle

- `SystemMonitor/Core/AppDelegate.swift`
  - Declares `@main` and manually runs `NSApplication`.
  - Owns the top‑level objects:
    - `StatusBarManager` – manages the menu bar item and menus.
    - `SystemMonitor` – orchestrates all low‑level monitors and data aggregation.
    - `PreferencesManager` – manages user settings, preferences window, launch‑at‑login, and language override.
    - `MenuBuilder` – builds the detailed dropdown and right‑click menus.
    - `CrashHandler` – sets up signal and exception handlers for auto‑restart.
  - Wiring:
    - Creates `PreferencesManager`, then `MenuBuilder` with its `DisplayOptions`.
    - Creates `StatusBarManager` with `MenuBuilder`, `WarningThresholds`, and `DisplayOptions` from preferences.
    - Creates `SystemMonitor` and sets callbacks:
      - `systemMonitor.onDataUpdate` → updates the status bar via `StatusBarManager`.
      - `systemMonitor.onError` → forwards `MonitorError` instances to UI‑level error handling.
    - Registers for system events via `NSWorkspace` and (on newer macOS) power state notifications:
      - Sleep, wake, power‑off, screen sleep/wake, and low‑power/thermal changes.
    - On launch: completes setup, starts monitoring, registers event listeners, configures crash handling, and refreshes localized UI.
    - On terminate: stops monitoring, unregisters from events, cleans up crash handlers, and records normal termination to avoid false “crash” restarts.

### Monitoring pipeline and monitor abstraction

#### Core orchestrator: `SystemMonitor`

Location: `SystemMonitor/Core/SystemMonitor.swift`.

Responsibilities:
- Owns all monitors:
  - `CPUMonitor`
  - `MemoryMonitor`
  - `GPUMonitor`
  - `TemperatureMonitor`
  - `NetworkMonitor`
  - `DiskMonitor`
  - `PerformanceMonitor` (for the app’s own resource usage)
- Manages:
  - Sampling timer (`Timer` on the main run loop, `.common` mode so it keeps firing while menus are open).
  - Current update interval (user‑controlled base interval + adaptive adjustments).
  - `SystemData` cache of the latest snapshot.
  - Error counting per error type to throttle user‑visible alerts.
  - `AdaptiveFrequencyManager` and `IntelligentCache` utilities.
- Public API (via `MonitorManagerProtocol` and extensions):
  - `startAllMonitors()`, `stopAllMonitors()`, `isMonitoringActive()`.
  - `getCurrentData()` – returns the last `SystemData` (or a default stub if none yet).
  - `setUpdateInterval(_:)`, `getUpdateInterval()` – user‑driven base interval.
  - System event hooks used by `AppDelegate`:
    - `handleSystemSleep()`, `handleSystemWake()`, `handleSystemShutdown()`, `handleLowPowerMode(_:)`.
  - Performance and diagnostic accessors:
    - `checkPerformanceLimits()`, `getPerformanceStatistics()`, `getCurrentPerformanceData()`.
    - `getFrequencyStatistics()`, `getCacheStatistics()`, `clearCache()`.
    - `getErrorStatistics()`, `resetErrorCounts()`.

Data collection model:
- `startAllMonitors()` starts required monitors (CPU, memory, performance) unconditionally and optional monitors (GPU, temperature, network, disk) only when `isAvailable()` returns true.
- A repeating timer triggers `collectAndUpdateData()`:
  - Runs on a global background queue to avoid blocking the main thread.
  - Uses `collectSystemDataAsync()` with a `DispatchGroup` and a dedicated concurrent queue to gather metrics from each monitor in parallel.
  - Per‑monitor errors are accumulated into `MonitorError` values but do not abort the entire sampling pass; at least CPU and memory are required, otherwise a `dataUnavailable` error is raised.
  - On success:
    - Updates `AdaptiveFrequencyManager` with CPU and memory usage.
    - Updates the cached `SystemData` and calls the `onDataUpdate` callback on the main queue.
  - On error:
    - Wraps unknown errors in `MonitorError.systemCallFailed`.
    - Passes error to `handleError`, which logs, updates per‑type error counts, and conditionally notifies `onError` for user‑visible issues (e.g. permission problems) up to a configurable threshold.
    - Attempts to construct a partial fallback snapshot using whichever metrics can still be collected (e.g., CPU and/or memory only).

Adaptive frequency & caching:
- `AdaptiveFrequencyManager` (see below) tracks recent CPU/memory load and low‑power state to adjust `currentUpdateInterval` within a bounded range.
- `IntelligentCache` stores slowly changing or expensive‑to‑derive values with per‑key lifetimes (e.g., GPU name, disk mount info) and exposes stats for debugging.
- `SystemMonitor` hooks `onFrequencyChanged` to restart the sampling timer with the new interval.

System events:
- On sleep: stops the update timer and informs all monitors (CPU, memory, GPU, temperature, network, disk, performance) via their `handleSystemSleep()` hooks.
- On wake: resets adaptive frequency, notifies all monitors of wake, then restarts the timer and triggers an immediate sample after a short delay so the system can stabilize.
- On shutdown: calls `stopAllMonitors()` to cleanly tear down resources.
- On low‑power/thermal changes: updates adaptive frequency using the latest `SystemData`.

#### Monitor abstraction: `MonitorProtocol` and `BaseMonitor`

Location: `SystemMonitor/Monitors/MonitorProtocol.swift`.

- `MonitorProtocol` defines the common contract implemented by all monitors:
  - `associatedtype DataType`
  - `collect() -> DataType`
  - `isAvailable() -> Bool`
  - `startMonitoring()`, `stopMonitoring()`
  - `handleSystemSleep()`, `handleSystemWake()`, `handleSystemShutdown()`
- `MonitorError` (an `Error & LocalizedError`) centralizes domain‑specific failure cases:
  - Permission issues, system call failures, data unavailability, invalid data, network/disk failures, temperature/GPU unavailability, and timeouts.
  - Each case provides a human‑readable description, an optional recovery suggestion, and a `shouldShowToUser` flag so `SystemMonitor` can decide which errors should result in user alerts vs. log‑only behavior.
- `MonitorState` and `BaseMonitor` provide shared machinery:
  - A per‑monitor serial `DispatchQueue` for work.
  - Helpers to run operations asynchronously with typed result callbacks or blocking with timeouts.
  - Default implementations for system event handlers that derived monitors can override.

#### Concrete monitors (summary)

All concrete monitors live under `SystemMonitor/Monitors` and follow the same pattern: implement `MonitorProtocol`, rely on macOS system APIs or tools, handle errors via `MonitorError`, and expose a value type from `DataModels.swift`.

- `CPUMonitor`:
  - Uses `host_processor_info` for per‑core tick counts and tracks a previous snapshot to compute deltas.
  - Uses `sysctl` (`hw.ncpu`, `hw.cpufrequency_max`) to determine core count and nominal frequency, with conservative fallbacks.
  - Returns `CPUData` with usage, core count, frequency, and (future) top processes.
- `MemoryMonitor`:
  - Uses `sysctl` (`hw.memsize`) and `host_statistics64` to derive total, active, and wired memory in pages, constructs bytes, and computes usage.
  - Uses `xsw_usage` via `sysctl` (`vm.swapusage`) for swap usage.
  - Encodes coarse memory pressure as `MemoryPressure` (`normal`, `warning`, `critical`) based on usage thresholds.
- `NetworkMonitor`:
  - Uses `getifaddrs` to iterate network interfaces and `if_data` statistics (`ifi_ibytes`, `ifi_obytes`).
  - Filters out loopback and interfaces that are not up/running.
  - Maintains a previous sample and timestamp to derive upload/download speeds (bytes/sec).
  - Uses `SCNetworkReachability` for basic reachability checks.
- `DiskMonitor`:
  - Uses `FileManager.mountedVolumeURLs` with resource keys to fetch volume name, total capacity, available capacity, and whether a volume is local.
  - Skips small/system volumes and aggregates `DiskData` for significant disks.
  - Uses IOKit (`IOBlockStorageDriver` statistics) to measure cumulative read/write bytes and derive per‑disk throughput over time; falls back to parsing `iostat` output when needed.
- `TemperatureMonitor`:
  - Distinguishes Apple Silicon vs Intel via `sysctl("hw.optional.arm64")`.
  - On Apple Silicon: primarily parses plist output from `powermetrics --samplers smc --format plist` to find CPU/GPU temperature keys and fans.
  - On Intel: uses SMC/IOKit and `powermetrics`/`pmset thermlog` parsing, with multiple fallbacks (SMC keys, text regexes) and IORegistry fan speed probing.
  - Returns `TemperatureData` with optional CPU/GPU temps and fan RPM.
- `GPUMonitor`:
  - Uses `powermetrics` and system APIs (IOKit/sysctl) to gather GPU usage, memory usage, and name.
  - Manages a long‑lived `powermetrics` process and ensures it is terminated and cleaned up when monitoring stops or the monitor is deallocated.

### Data modeling

Location: `SystemMonitor/Models/DataModels.swift`.

- `SystemData` is the central snapshot object:
  - Aggregates per‑subsystem data: `CPUData`, `GPUData?`, `MemoryData`, `[DiskData]`, `TemperatureData?`, `NetworkData?`, `PerformanceData?` and a timestamp.
  - Created by `SystemMonitor` each sampling interval and passed to the UI via `onDataUpdate`.
- Per‑subsystem models:
  - `CPUData`: usage (clamped 0–100), core count (≥1), frequency (GHz), optional `ProcessInfo` list.
  - `GPUData`: usage, used/total VRAM (bytes, with total ≥ used), GPU name.
  - `MemoryData`: used/total bytes (total ≥ used), `MemoryPressure`, optional swap usage and computed `usagePercentage`.
  - `DiskData`: name, mount point, used/total bytes (total ≥ used), read/write speeds (bytes/sec) with a derived `usagePercentage`.
  - `TemperatureData`: optional CPU/GPU temps and fan RPM.
  - `NetworkData`: upload/download throughput and cumulative traffic.
  - `PerformanceData`: app’s own CPU usage, memory usage and thread count, plus convenience `memoryUsageMB`.
- Display configuration and thresholds:
  - `DisplayOptions`: feature flags for which components to show (CPU/GPU/memory/disk/temp/fan/network) plus a single `MenuBarFormat` (`twoLine` currently).
  - `WarningThresholds`: numeric thresholds for CPU, memory, and temperature warnings, clamped to safe ranges.
  - `SystemComponent` enum identifies logical slices of data (cpu/memory/gpu/temperature/network/disk/performance).
- UI‑oriented helpers:
  - `SystemData.displayString(for:)` produces human‑friendly strings for each `SystemComponent` (percentages, degrees Celsius, network arrows with formatted bytes/sec, etc.) and falls back to `"N/A"` when data is unavailable.

### Status bar UI and menus

#### Status bar manager

Location: `SystemMonitor/UI/StatusBarManager.swift`.

Responsibilities:
- Creates and owns the `NSStatusItem`.
- Applies the current `DisplayOptions.menuBarFormat` to the status bar button.
- Receives `SystemData` updates and renders them into the menu bar and dropdown menu.
- Manages left‑click (normal menu) vs right‑click (quick‑actions context menu) behavior.

Key behavior:
- `setupStatusItem()`:
  - Creates a variable‑length status item.
  - Configures the button to use image‑only display for the two‑line format, including a placeholder image before data arrives.
  - Sets a localized tooltip (`statusbar.tooltip`).
  - Binds `statusItemClicked(_:)` to handle both left and right clicks.
  - Initializes the menu with `menuBuilder.buildMenu()` and sets `NSMenuDelegate` to track open/close state.
- `updateStatusDisplay(with:)`:
  - Always executed on the main thread.
  - For two‑line mode, relies on helper functions (within `StatusBarManager`) to build a compact visual representation of key metrics and renders it as an image; the button’s title is kept empty in this mode.
  - Rebuilds the entire menu with fresh data (`menuBuilder.buildMenu(with:)`) so the dropdown always reflects the latest `SystemData`.
  - Applies warning colors when not in two‑line mode based on `WarningThresholds` and CPU usage.
- Right‑click:
  - Builds a dedicated quick‑actions menu via `menuBuilder.buildRightClickMenu()` (Preferences, About, Quit) and temporarily assigns it to the status item.
  - After a short delay restores the normal dynamic menu.
- Localization refresh:
  - `refreshLocalizedTexts()` updates the tooltip and rebuilds the menu when language settings change.

#### Menu construction

Location: `SystemMonitor/UI/MenuBuilder.swift`.

Responsibilities:
- Encapsulates menu construction and section layout.
- Uses `DisplayOptions` to decide which sections to include.
- Uses the global `NSLocalizedString` override (backed by `Localization`) to obtain localized strings for all titles, labels, and values.

Core operations:
- `buildMenu(with: SystemData?)`:
  - Creates a new `NSMenu` each time.
  - If `SystemData` is provided, adds a header section with the localized app name and a localized “last updated” timestamp, then detailed sections for each enabled subsystem:
    - CPU: usage, core count, frequency.
    - Memory: used/total in GB, usage percentage, pressure state, optional swap usage.
    - GPU: name, usage, memory used/total, or `N/A` if unavailable.
    - Temperature/fan: CPU and GPU temperatures (with color coding), fan speed or a placeholder, or `N/A` when no readings.
    - Network: upload/download speeds using localized formats.
    - Disk: per‑disk space and throughput.
    - Performance: app‑level performance metrics when available.
  - Inserts separators between logical sections.
  - Appends control items (Preferences…, About, Quit) at the end.
- `buildRightClickMenu()`:
  - Returns a small menu focused on quick access to Preferences, About, and Quit, with expected keyboard shortcuts.

Custom view support:
- `TwoLineMenuItemView` provides a reusable two‑line view (title + value) for more compact, readable entries in the dropdown menu.

### Preferences, localization, and app management

#### Preferences management

Location: `SystemMonitor/Utilities/PreferencesManager.swift`.

Responsibilities:
- Centralizes all user‑configurable settings, backed by `UserDefaults`.
- Exposes high‑level properties that the rest of the app consumes:
  - `updateInterval` (1–10 seconds),
  - `displayOptions` (what to show in the menu bar and dropdown),
  - `warningThresholds` (CPU/memory/temperature warning thresholds),
  - `isAutoRestartEnabled` (controls crash auto‑restart behavior),
  - `isLaunchAtLoginEnabled` (macOS login item),
  - `languageOverride` ("auto", "en", "ja", "zh-Hans").
- Provides a `onSettingsChanged` callback used by `AppDelegate` to:
  - Update `SystemMonitor`’s update interval.
  - Update `MenuBuilder` and `StatusBarManager` display options and thresholds.
  - Refresh localization via `Localization.shared.refreshBundle()`.

Preferences UI:
- Lazily creates a dedicated preferences `NSWindow` with a `PreferencesViewController` that owns the UI controls (sliders, checkboxes, etc.).
- The view controller binds UI state back into `PreferencesManager` properties; changes immediately propagate through `onSettingsChanged` and the app updates live.

Launch at login:
- Uses `SMAppService.mainApp` (macOS 13+) to register/unregister the app as a login item when `isLaunchAtLoginEnabled` changes, with error logging on failure.

#### Localization

Location: `SystemMonitor/Utilities/Localization.swift` and `SystemMonitor/Resources/*/Localizable.strings`.

Behavior:
- `Localization` is a singleton (`Localization.shared`) that wraps bundle resolution and localization logic for the whole app.
- It looks up the active language as follows:
  - Optional override from preferences (`languageOverride` via `UserDefaults`): `"auto"` = follow system, otherwise a BCP‑47 tag like `"en"`, `"ja"`, `"zh-Hans"`.
  - System preferred languages (`Locale.preferredLanguages`), with logic to:
    - Try exact match.
    - Try language–script pairs (e.g., `zh-Hans`, `zh-Hant`).
    - Infer script based on region for Chinese varieties.
    - Fall back to plain language codes.
  - If no localized bundle is found, falls back to `Base.lproj` if available, else to the main bundle and finally English.
- Supports both Xcode and SwiftPM resource bundles (uses `.module` when built as a package).
- Overrides the global `NSLocalizedString(_:,comment:)` to route all lookups through `Localization.shared`.
- Provides diagnostics via `diagnostics()` used by `AppDelegate` for logging:
  - active language code,
  - bundle path,
  - available localizations,
  - preferred languages.

User‑visible behavior:
- Localized strings are loaded from `SystemMonitor/Resources/<lang>.lproj/Localizable.strings` (currently `en`, `ja`, `zh-Hans`, plus additional Chinese variants under `zh.lproj`).
- Language selection in preferences updates `languageOverride`, triggers `Localization.refreshBundle()`, and calls `onSettingsChanged`, which causes `StatusBarManager` and menus to re‑localize immediately without app restart.

#### Crash handling and auto‑restart

Location: `AppDelegate` and `CrashHandler` (nested in `AppDelegate.swift`).

Behavior:
- When `PreferencesManager.isAutoRestartEnabled` is true, `AppDelegate` initializes a `CrashHandler`.
- `CrashHandler`:
  - Installs signal handlers for common crash signals (SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGPIPE).
  - Sets an `NSSetUncaughtExceptionHandler` callback.
  - On crash/exception, logs the event and calls `AppDelegate.triggerAutoRestart()`.
- Auto‑restart flow:
  - Writes a small shell script into the temporary directory that sleeps briefly then re‑opens the app’s bundle.
  - Marks the script executable and launches it as a detached `Process`.
  - On normal termination, `AppDelegate` sets a flag and calls `crashHandler.cleanup()` to avoid misinterpreting a normal quit as a crash.

### Performance, adaptive frequency, and caching

Location: `SystemMonitor/Utilities/AdaptiveFrequencyManager.swift` (also defines `IntelligentCache` and `FrequencyStatistics`).

Adaptive frequency:
- Maintains:
  - `baseUpdateInterval` (from preferences),
  - `currentUpdateInterval`,
  - min/max bounds, and thresholds for “high load” CPU/memory usage.
- Tracks consecutive high/low load samples to avoid flapping.
- Adjusts frequency when:
  - System enters/leaves high‑load state.
  - Low‑power mode toggles.
- New intervals are clamped and only applied when the change is meaningful; updates are logged and surfaced via `onFrequencyChanged`, which `SystemMonitor` uses to reconfigure its timer.

Intelligent caching:
- Thread‑safe, concurrent dictionary keyed by string.
- Per‑key expiration durations tuned to data volatility (e.g., GPU name and core count cached for 5 minutes, disk info for 60 seconds).
- Exposes helpers:
  - `getCachedData(key:type:)`, `setCachedData(key:data:)`, `isCached(key:)`, `clearCache()`, `cleanupExpiredItems()`.
- `SystemMonitor` uses this to avoid recomputing expensive or rarely changing information (e.g., GPU name, disk identity), and exposes `getCacheStatistics()` for diagnostics.

### Requirements mapping and test strategy

#### Requirements coverage

The `.kiro/specs/macos-system-monitor` folder contains:
- `requirements.md` – user stories and acceptance criteria for:
  - Menu bar status item behavior and refresh rate.
  - Detailed dropdown contents across all metric types.
  - Customizable display options, update interval, warning thresholds.
  - Performance constraints (low CPU/memory overhead, proper sleep/wake handling).
  - Error handling, logging, and auto‑restart semantics.
- `design.md` – the conceptual architecture and data flow diagrams that match the implemented structure (AppDelegate → StatusBarManager/MenuBuilder/SystemMonitor/PreferencesManager and Monitor → OS APIs/powermetrics/IOKit, etc.).
- `tasks.md` – an incremental implementation plan tracking which features and properties are complete, with explicit links from tasks to requirements and associated tests.

Future work (per `tasks.md`) includes:
- Additional property‑based tests for CPU monitoring, performance limits, and full integration flows.
- More coverage for extended monitors (GPU, disk, temperature, network) and long‑running stability.

#### Tests and property‑based testing

Location: `SystemMonitorTests/SystemMonitorTests.swift`.

- Uses `SwiftCheck` in combination with `XCTest` for property‑based tests.
- Current focus areas:
  - Memory monitor:
    - Boundary conditions and safe defaults when system calls fail.
    - Usage percentage, pressure categorization, swap usage, and consistency over multiple samples.
  - Preferences and menu behavior:
    - Menu builder always includes control items (Preferences, About, Quit).
    - Right‑click quick‑actions menu structure.
    - `PreferencesManager` default values, mutation behavior, reset‑to‑defaults, and warning thresholds.

When extending the system, keep new behavior aligned with the existing property‑based testing style and requirements in `.kiro/specs`.

## Extending the system

These patterns are already established in the codebase and should be followed when adding new functionality:

- **Adding a new monitor type** (e.g., battery or thermal throttling):
  - Define a new data model in `DataModels.swift` and, if it should appear in high‑level display helpers, extend `SystemComponent` and `SystemData.displayString(for:)`.
  - Implement a monitor under `SystemMonitor/Monitors` that conforms to `MonitorProtocol` and uses `BaseMonitor` for queueing and error propagation.
  - Wire it into `SystemMonitor` (construction, `isAvailable()` checks, participation in async collection and system event handlers).
  - Integrate it into `MenuBuilder` and `StatusBarManager` using a new section or by extending existing ones.

- **Extending preferences or display behavior**:
  - Add new fields to `DisplayOptions`/`WarningThresholds` as needed.
  - Update `PreferencesManager` keys, defaults, and computed properties, plus the preferences UI controller.
  - Propagate through `AppDelegate.handleSettingsChanged()` to `SystemMonitor`, `MenuBuilder`, and `StatusBarManager`.

- **Localization of new strings**:
  - Add keys to all `Localizable.strings` files under `SystemMonitor/Resources/*/`.
  - Use the global `NSLocalizedString` wrapper so that `Localization` can resolve the correct bundle.

By following these existing extension points, future changes will integrate cleanly with the monitoring pipeline, adaptive frequency management, localization, and preferences flows already present in the codebase.
