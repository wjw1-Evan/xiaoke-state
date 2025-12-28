import Cocoa

/// 自定义的两行菜单项视图：第一行显示标题，第二行显示数据
class TwoLineMenuItemView: NSView {
    private let titleLabel: NSTextField
    private let valueLabel: NSTextField
    private let stackView: NSStackView

    init(title: String, value: String, valueColor: NSColor = NSColor.controlTextColor) {
        // 预设一个合适的初始大小，实际高度由内容决定
        self.titleLabel = NSTextField(labelWithString: title)
        self.valueLabel = NSTextField(labelWithString: value)
        self.stackView = NSStackView()
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 36))

        setupLabels(valueColor: valueColor)
        setupLayout()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private func setupLabels(valueColor: NSColor) {
        // 标题样式
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = NSColor.controlTextColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.alignment = .left
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // 数据样式
        valueLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        valueLabel.textColor = valueColor
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.alignment = .left
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupLayout() {
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 2
        stackView.translatesAutoresizingMaskIntoConstraints = false

        // 左侧缩进以与现有单行项的"  "对齐
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stackView)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(valueLabel)

        addSubview(container)

        // 约束：左右留边，顶部对齐，底部 >= stack
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            container.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),

            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: container.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    override var intrinsicContentSize: NSSize {
        // 提供一个合理的内在尺寸，菜单会根据 view 高度调整行高
        return NSSize(width: 280, height: 36)
    }
}
