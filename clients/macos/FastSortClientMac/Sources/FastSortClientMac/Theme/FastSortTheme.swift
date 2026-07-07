import AppKit
import SwiftUI

enum FastSortTheme {
    static let background = Color(hex: 0xf5f5f7)
    static let groupedBackground = Color(hex: 0xf5f5f7)
    static let surface = Color(hex: 0xffffff)
    static let sidebar = Color(hex: 0xf9f9fb)
    static let border = Color(hex: 0xd2d2d7, opacity: 0.72)
    static let text = Color(hex: 0x1d1d1f)
    static let muted = Color(hex: 0x6e6e73)
    static let accent = Color(hex: 0x007aff)
    static let accentDark = Color(hex: 0x0066d6)
    static let accentSoft = Color(hex: 0xe8f2ff)
    static let danger = Color(hex: 0xff3b30)
    static let success = Color(hex: 0x34c759)

    static let sidebarWidth: CGFloat = 224
    static let contentPadding: CGFloat = 24
    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 10
    static let smallRadius: CGFloat = 8
    static let shadowColor = Color.black.opacity(0.024)
    static let accentShadow = Color(hex: 0x007aff, opacity: 0.16)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xff) / 255
        let green = Double((hex >> 8) & 0xff) / 255
        let blue = Double(hex & 0xff) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

extension View {
    func nativeCard(cornerRadius: CGFloat = FastSortTheme.cardRadius) -> some View {
        self
            .background(FastSortTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(FastSortTheme.border, lineWidth: 0.7)
            }
            .shadow(color: FastSortTheme.shadowColor, radius: 5, x: 0, y: 2)
    }

    func webCard(cornerRadius: CGFloat = FastSortTheme.cardRadius) -> some View {
        self
            .nativeCard(cornerRadius: cornerRadius)
    }

    func webPanel(cornerRadius: CGFloat = FastSortTheme.controlRadius) -> some View {
        self
            .background(FastSortTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func webTextInput(width: CGFloat? = nil) -> some View {
        self
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(width: width)
            .background(Color(hex: 0xfafafa))
            .clipShape(RoundedRectangle(cornerRadius: FastSortTheme.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FastSortTheme.controlRadius, style: .continuous)
                    .stroke(FastSortTheme.border, lineWidth: 1)
            }
    }

    func macPagePadding() -> some View {
        self
            .padding(.horizontal, FastSortTheme.contentPadding)
            .padding(.bottom, FastSortTheme.contentPadding)
    }
}

struct MacSidebarButtonStyle: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: active ? .semibold : .medium))
            .foregroundStyle(active ? FastSortTheme.accent : FastSortTheme.text.opacity(0.84))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(active ? FastSortTheme.accentSoft : Color.white.opacity(0.001))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct AdaptiveHorizontalTable<Content: View>: View {
    let minimumWidth: CGFloat
    let minHeight: CGFloat
    @ViewBuilder let content: (CGFloat) -> Content

    var body: some View {
        GeometryReader { proxy in
            let tableWidth = max(proxy.size.width, minimumWidth)
            ScrollView(.horizontal, showsIndicators: tableWidth > proxy.size.width + 1) {
                content(tableWidth)
                    .frame(width: tableWidth, alignment: .leading)
            }
        }
        .frame(minHeight: minHeight)
    }
}

struct MacFilterBar<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            content
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MacChoiceOption<Value: Hashable>: Identifiable {
    let label: String
    let value: Value

    var id: String {
        "\(label)-\(value.hashValue)"
    }
}

struct MacChoiceGroup<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [MacChoiceOption<Value>]
    var minItemWidth: CGFloat = 64

    init(_ title: String, selection: Binding<Value>, options: [MacChoiceOption<Value>], minItemWidth: CGFloat = 64) {
        self.title = title
        self._selection = selection
        self.options = options
        self.minItemWidth = minItemWidth
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                if !title.isEmpty {
                    titleLabel
                }
                choiceStrip
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                if !title.isEmpty {
                    titleLabel
                }
                compactChoices
            }
        }
    }

    private var titleLabel: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(FastSortTheme.muted)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var choiceStrip: some View {
        MacNativeSegmentedControl(selection: $selection, options: options, minItemWidth: minItemWidth)
        .frame(minWidth: choiceStripMinimumWidth)
        .frame(maxWidth: .infinity)
        .frame(height: 32)
    }

    private var compactChoices: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minItemWidth), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(options) { option in
                choiceButton(option, compact: true)
            }
        }
    }

    private func choiceButton(_ option: MacChoiceOption<Value>, compact: Bool) -> some View {
        Button {
            selection = option.value
        } label: {
            choiceVisual(option, compact: compact)
                .frame(maxWidth: compact ? .infinity : .infinity)
        }
        .background(Color.white.opacity(0.001))
        .contentShape(Rectangle())
        .buttonStyle(.plain)
    }

    private var choiceStripMinimumWidth: CGFloat {
        CGFloat(options.count) * minItemWidth + CGFloat(max(0, options.count - 1)) * 2
    }

    private func choiceVisual(_ option: MacChoiceOption<Value>, compact: Bool) -> some View {
        let isSelected = selection == option.value
        return Text(option.label)
            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? FastSortTheme.accent : FastSortTheme.text.opacity(0.76))
            .lineLimit(1)
            .minimumScaleFactor(0.86)
            .padding(.horizontal, compact ? 8 : 12)
            .frame(minWidth: minItemWidth)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(isSelected ? FastSortTheme.surface : (compact ? Color(hex: 0xf1f2f5) : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isSelected ? FastSortTheme.accent.opacity(0.26) : (compact ? FastSortTheme.border.opacity(0.45) : Color.clear), lineWidth: 0.8)
            }
            .shadow(color: isSelected ? FastSortTheme.shadowColor : Color.clear, radius: 5, x: 0, y: 2)
    }
}

private struct MacNativeSegmentedControl<Value: Hashable>: NSViewRepresentable {
    @Binding var selection: Value
    let options: [MacChoiceOption<Value>]
    let minItemWidth: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: options.map(\.label), trackingMode: .selectOne, target: context.coordinator, action: #selector(Coordinator.selectionChanged(_:)))
        control.segmentStyle = .rounded
        control.controlSize = .small
        control.focusRingType = .none
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        updateControl(control)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        if control.segmentCount != options.count {
            control.segmentCount = options.count
        }
        updateControl(control)
    }

    private func updateControl(_ control: NSSegmentedControl) {
        for index in options.indices {
            control.setLabel(options[index].label, forSegment: index)
            control.setWidth(minItemWidth, forSegment: index)
            control.setEnabled(true, forSegment: index)
        }
        if let selectedIndex = options.firstIndex(where: { $0.value == selection }) {
            control.selectedSegment = selectedIndex
        } else {
            control.selectedSegment = -1
        }
    }

    final class Coordinator: NSObject {
        var parent: MacNativeSegmentedControl

        init(parent: MacNativeSegmentedControl) {
            self.parent = parent
        }

        @MainActor @objc func selectionChanged(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            guard parent.options.indices.contains(index) else { return }
            parent.selection = parent.options[index].value
        }
    }
}

struct MacSelectOption<Value: Hashable>: Identifiable {
    let label: String
    let value: Value

    var id: String {
        "\(label)-\(value.hashValue)"
    }
}

struct MacSelect<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [MacSelectOption<Value>]
    var width: CGFloat?

    init(_ title: String = "", selection: Binding<Value>, options: [MacSelectOption<Value>], width: CGFloat? = nil) {
        self.title = title
        self._selection = selection
        self.options = options
        self.width = width
    }

    private var selectedLabel: String {
        options.first { $0.value == selection }?.label ?? options.first?.label ?? "-"
    }

    var body: some View {
        HStack(spacing: 8) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FastSortTheme.muted)
                    .fixedSize(horizontal: true, vertical: false)
            }
            MacNativePopUpButton(selection: $selection, options: options)
                .frame(maxWidth: .infinity)
        }
        .frame(width: width)
        .frame(height: 32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title.isEmpty ? selectedLabel : "\(title) \(selectedLabel)")
    }
}

private struct MacNativePopUpButton<Value: Hashable>: NSViewRepresentable {
    @Binding var selection: Value
    let options: [MacSelectOption<Value>]

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        button.focusRingType = .none
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        updateButton(button)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        updateButton(button)
    }

    private func updateButton(_ button: NSPopUpButton) {
        if button.numberOfItems != options.count || button.itemTitles != options.map(\.label) {
            button.removeAllItems()
            button.addItems(withTitles: options.map(\.label))
        }
        let selectedIndex = options.firstIndex { $0.value == selection } ?? 0
        if button.indexOfSelectedItem != selectedIndex {
            button.selectItem(at: selectedIndex)
        }
    }

    final class Coordinator: NSObject {
        var parent: MacNativePopUpButton

        init(parent: MacNativePopUpButton) {
            self.parent = parent
        }

        @MainActor @objc func selectionChanged(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            guard parent.options.indices.contains(index) else { return }
            parent.selection = parent.options[index].value
        }
    }
}
