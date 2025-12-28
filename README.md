# macOS System Monitor

一款 macOS 菜单栏系统监控应用，实时展示 CPU、GPU、内存、磁盘、温度和网络等系统性能信息。

感谢：<https://github.com/exelban/stats>

## 项目结构

```
SystemMonitor/
├── SystemMonitor.xcodeproj/          # Xcode 工程文件
├── SystemMonitor/                    # 主应用源码
│   ├── Core/                        # 核心应用组件
│   │   ├── AppDelegate.swift        # 应用入口委托
│   │   └── SystemMonitor.swift      # 系统监控协调器
│   ├── Models/                      # 数据模型
│   │   └── DataModels.swift         # 系统数据结构
│   ├── Monitors/                    # 系统监控模块
│   │   ├── MonitorProtocol.swift    # 监控接口定义
│   │   ├── CPUMonitor.swift         # CPU 监控实现
│   │   └── MemoryMonitor.swift      # 内存监控实现
│   ├── UI/                          # 用户界面组件
│   │   ├── StatusBarManager.swift   # 菜单栏状态项管理
│   │   └── MenuBuilder.swift        # 下拉菜单构建
│   ├── Utilities/                   # 工具类
│   │   └── PreferencesManager.swift # 设置管理
│   ├── Info.plist                   # 应用配置
│   └── SystemMonitor.entitlements   # 安全权限
├── SystemMonitorTests/              # 测试套件
│   └── SystemMonitorTests.swift     # 单元与集成测试
├── Package.swift                    # Swift Package Manager 配置
└── README.md                        # 本文件
```

## 功能

### 当前实现（任务 1）

- ✅ 项目结构与核心接口
- ✅ 系统信息的数据模型
- ✅ 监控协议与基础实现
- ✅ CPU 与内存监控
- ✅ 菜单栏状态项管理
- ✅ 基础偏好设置系统
- ✅ 测试框架配置（XCTest + SwiftCheck）
- ✅ 仅菜单栏应用配置（LSUIElement = true）

### 计划功能

- GPU 监控与显示
- 温度监控
- 网络速度监控
- 磁盘使用与 I/O 监控
- 偏好设置窗口 UI
- 性能优化
- 错误处理与日志
- 系统睡眠/唤醒处理

## 环境要求

- macOS 13.0 或更高版本
- Xcode 15.0 或更高版本
- Swift 5.9 或更高版本

## 构建

1. 在 Xcode 中打开 `SystemMonitor.xcodeproj`
2. 选择 SystemMonitor 目标
3. 构建并运行（⌘+R）

或者使用 Swift Package Manager：

```bash
swift build
swift run
```

## 测试

在 Xcode 或命令行运行测试：

```bash
swift test
```

项目包含基于 SwiftCheck 的单元测试与性质测试，以确保全面验证。

## 架构

应用采用模块化架构，职责清晰分离：

- **Core**：应用生命周期与协调
- **Models**：数据结构与校验
- **Monitors**：系统数据采集模块
- **UI**：菜单栏与界面组件
- **Utilities**：设置与辅助函数

每个监控模块都实现 `MonitorProtocol`，以保持数据采集与错误处理的一致性。

## 本地化

应用已支持多语言本地化：

- 英语（`en.lproj`）
- 日语（`ja.lproj`）
- 简体中文（`zh-Hans.lproj`）

若多语言未能正常显示：

- 请确保系统的“首选语言”包含以上语言之一。
- 对于中文，系统通常使用 `zh-Hans`（简体）或 `zh-Hant`（繁体）脚本标识。应用会优先解析完整语言脚本（如 `zh-Hans`）。
- 如果仍显示为英文，尝试重新启动应用或将目标语言移动到系统语言列表的顶部。

开发者与用户提示：

- 资源位于 `SystemMonitor/Resources/*/Localizable.strings`。
- 运行时会优先从 SwiftPM 资源包（`Bundle.module`）解析本地化，再回退至主 Bundle（`Bundle.main`）。
- 本地化解析逻辑见 `Utilities/Localization.swift`。

### 在偏好设置中选择语言

- 打开偏好设置，在“语言”部分选择：自动（跟随系统）、英语、日语、中文（简体）。
- 默认值为“自动（跟随系统）”。
- 更改语言后，菜单与提示会立即刷新，无需重启应用。

### 更新间隔（刷新率）

- 默认刷新率：1 秒（可在偏好设置的“更新间隔”中调整，范围 1–10 秒）。

## 许可证

本项目是系统监控应用的规范与实现的一部分。
