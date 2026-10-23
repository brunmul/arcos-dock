//
//  SettingsKit.swift
//  Docky
//
//  The pieces every Settings pane is built from, so they all read the same
//  way: titled groups of options on soft cards, each switch, menu or
//  slider with its symbol and a line saying what it changes, and choices
//  shown as a drawing of their result where one can be drawn.
//

import AppKit
import SwiftUI

/// A pane's page: its groups in a column, scrolling.
struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                content()
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Rows on one card; put a `SettingsDivider` between them.
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .settingsCard()
    }
}

/// The hairline between two rows of a card, starting under their text.
struct SettingsDivider: View {
    var body: some View {
        Divider().padding(.leading, 56)
    }
}

/// A menu of choices with a symbol, its name and what it does.
struct PickerRow<Value: Hashable, Options: View>: View {
    let symbol: String
    let title: String
    let note: String
    @Binding var selection: Value
    var isSegmented = false
    @ViewBuilder let options: () -> Options

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingsSymbol(symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if isSegmented {
                Picker(title, selection: $selection, content: options)
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
            } else {
                Picker(title, selection: $selection, content: options)
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// A slider with a symbol, its name, its value and what it does.
struct SliderRow: View {
    let symbol: String
    let title: String
    let note: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.05
    var format: (Double) -> String = { String(format: "%.2f s", $0) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SettingsSymbol(symbol: symbol)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                    Spacer()
                    Text(format(value))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $value, in: range, step: step)
                    .labelsHidden()
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Pieces

/// A titled block of options, with a line saying what it is about.
struct SettingsGroup<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let note {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
    }
}

extension View {
    func settingsCard() -> some View {
        background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

/// One choice among a few, shown as a drawing of its result with its name
/// under it; the chosen one is ringed in the accent color.
struct ChoiceCard<Preview: View>: View {
    let title: String
    let isSelected: Bool
    @ViewBuilder let preview: () -> Preview
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                preview()
                    .frame(height: 74)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.primary.opacity(isHovered ? 0.25 : 0.12),
                                lineWidth: isSelected ? 2.5 : 1
                            )
                    )
                HStack(spacing: 4) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(title)
                        .font(.callout.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// A switch with a symbol, its name and what it does.
struct ToggleRow: View {
    let symbol: String
    let title: String
    let note: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingsSymbol(symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// Like `ToggleRow`, with a button in place of the switch.
struct ButtonRow: View {
    let symbol: String
    let title: String
    let note: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingsSymbol(symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button(buttonTitle, action: action)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// A tile that is on or off, for a set of things to keep: its symbol and
/// name, ticked when on.
struct CheckTile: View {
    let symbol: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .frame(width: 18)
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOn ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isOn ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// An option's symbol, in outline on a soft square, the way the sidebar
/// draws its folders.
struct SettingsSymbol: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
    }
}

