// SwiftUI conveniences that arrived in macOS 13 or 14, for a macOS 12 deployment target. Each uses the system's own
// where it exists and falls back to a plainer version where it doesn't.

import SwiftUI

/// `LabeledContent` (macOS 13). Declared here so the call sites keep their spelling; the system's is used when present.
struct LabeledContent<Label: View, Content: View>: View {
    private let label: Label
    private let content: Content

    init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.content = content()
        self.label = label()
    }

    var body: some View {
        if #available(macOS 13, *) {
            SwiftUI.LabeledContent {
                content
            } label: {
                label
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) { label }
                Spacer(minLength: 8)
                content
            }
        }
    }
}

extension LabeledContent where Label == Text {
    init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        self.init(content: content, label: { Text(title) })
    }
}

extension LabeledContent where Label == Text, Content == Text {
    init<S: StringProtocol, V: StringProtocol>(_ title: S, value: V) {
        self.init(content: { Text(value) }, label: { Text(title) })
    }
}

extension View {
    /// `.formStyle(.grouped)` (macOS 13): the grouped look where it exists, the plain form before.
    @ViewBuilder func compatGroupedForm() -> some View {
        if #available(macOS 13, *) { self.formStyle(.grouped) } else { self }
    }

    /// `.scrollDisabled(_:)` (macOS 13): before it, the view just keeps its scrolling.
    @ViewBuilder func compatScrollDisabled(_ disabled: Bool) -> some View {
        if #available(macOS 13, *) { self.scrollDisabled(disabled) } else { self }
    }

    /// `.onChange(of:) { … }` without the new value (macOS 14's form); the one-parameter form before.
    @ViewBuilder func compatOnChange<V: Equatable>(of value: V, _ action: @escaping () -> Void) -> some View {
        if #available(macOS 14, *) {
            self.onChange(of: value) { action() }
        } else {
            self.onChange(of: value) { _ in action() }
        }
    }
}

/// A label/value table: the system's `Grid` on macOS 13 and later, two aligned columns before.
struct FactsGrid: View {
    let rows: [(label: String, value: String)]

    var body: some View {
        if #available(macOS 13, *) {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
                ForEach(rows.indices, id: \.self) { index in
                    GridRow {
                        Text(rows[index].label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        Text(rows[index].value).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .trailing, spacing: 3) {
                    ForEach(rows.indices, id: \.self) { Text(rows[$0].label).foregroundStyle(.secondary) }
                }
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(rows.indices, id: \.self) { Text(rows[$0].value).monospacedDigit() }
                }
            }
        }
    }
}
