#if os(macOS)
import AppKit
import SwiftUI
import ReelCore

// MARK: - Filters

/// "Mood" button: a checklist with live counts. Ticking several shows films that have all of them.
struct MoodFilterButton: View {
    @Binding var selected: Set<Mood>
    /// Films before the mood filter.
    let base: [LibraryItem]
    let available: [Mood]
    @State private var open = false

    var body: some View {
        Button {
            open.toggle()
        } label: {
            FilterPill(icon: "theatermasks", text: label, active: !selected.isEmpty)
        }
        .buttonStyle(.plain)
        .disabled(available.isEmpty)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            MoodChecklist(selected: $selected, base: base, available: available)
        }
    }

    private var label: String {
        switch selected.count {
        case 0: "Mood"
        case 1: selected.first?.title ?? "Mood"
        default: "\(selected.count) moods"
        }
    }
}

struct MoodChecklist: View {
    @Binding var selected: Set<Mood>
    let base: [LibraryItem]
    let available: [Mood]

    var body: some View {
        let current = selected.isEmpty ? base : base.filter { selected.isSubset(of: $0.moods) }
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Mood").font(.system(size: 14, weight: .semibold))
                Text("\(current.count) films").font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                if !selected.isEmpty {
                    Button("Clear") { selected = [] }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.brand)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
            ForEach(available) { mood in
                let isOn = selected.contains(mood)
                let count = isOn ? current.count : current.filter { $0.moods.contains(mood) }.count
                Button {
                    if isOn { selected.remove(mood) } else { selected.insert(mood) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isOn ? "checkmark.square.fill" : "square")
                            .foregroundStyle(isOn ? Theme.brand : Color.secondary)
                        Image(systemName: mood.symbol)
                            .frame(width: 18)
                            .foregroundStyle(.secondary)
                        Text(mood.title)
                        Spacer()
                        Text("\(count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 13))
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(count == 0 && !isOn)
                .opacity(count == 0 && !isOn ? 0.4 : 1)
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}

/// Length menu with how many films fall into each band.
struct LengthFilterMenu: View {
    @Binding var length: LengthBand
    /// Films before the length filter.
    let base: [LibraryItem]

    var body: some View {
        Menu {
            Picker("Length", selection: $length) {
                ForEach(LengthBand.allCases) { band in
                    let count = band == .any ? base.count : base.filter { band.contains($0.runtime) }.count
                    Text("\(band.title)  (\(count))").tag(band)
                }
            }
            .pickerStyle(.inline)
        } label: {
            FilterPill(icon: "clock", text: length == .any ? "Length" : length.title, active: length != .any)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct LanguageFilterMenu: View {
    @Binding var language: String?
    /// Films before the language filter.
    let base: [LibraryItem]
    let languages: [String]

    var body: some View {
        Menu {
            Button("Any Language  (\(base.count))") { language = nil }
            Divider()
            ForEach(languages, id: \.self) { code in
                let count = base.filter { $0.language == code }.count
                if count > 0 {
                    Button("\(FilmLanguage.name(code))  (\(count))") { language = code }
                }
            }
        } label: {
            FilterPill(icon: "globe", text: language.map(FilmLanguage.name) ?? "Language", active: language != nil)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// What the films were shot on (film, digital, anamorphic, IMAX, black and white), as read about
/// them in the background; only what's in the library is offered.

struct SortMenu: View {
    @Binding var sort: LibrarySort

    var body: some View {
        Menu {
            Picker("Sort By", selection: $sort) {
                ForEach(LibrarySort.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 5) {
                Text(sort.title)
                Image(systemName: "chevron.down").font(.system(size: 8.5, weight: .bold)).opacity(0.7)
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.8))
            .padding(.horizontal, 8)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct FilterPill: View {
    let icon: String
    let text: String
    let active: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(text)
            Image(systemName: "chevron.down").font(.system(size: 8.5, weight: .bold)).opacity(0.6)
        }
        .font(.system(size: 12.5, weight: .medium))
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Capsule().fill(active ? Theme.brand.opacity(0.14) : Theme.field))
        .overlay(Capsule().strokeBorder(active ? Theme.brand.opacity(0.5) : Color.white.opacity(0.07)))
        .foregroundStyle(active ? Theme.brand : Color.white.opacity(0.85))
        .contentShape(Capsule())
    }
}

/// The posters' size: small to large, as in Photos.
struct PosterSizeSlider: View {
    @Binding var size: Double

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.portrait").font(.system(size: 8, weight: .semibold))
            Slider(value: $size, in: 130...240)
                .controlSize(.mini)
                .frame(width: 84)
            Image(systemName: "rectangle.portrait").font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(.secondary)
        .tint(Theme.brand)
        .help("Poster size")
    }
}

/// Posters or a list.
struct ViewModeToggle: View {
    @Binding var asList: Bool

    var body: some View {
        HStack(spacing: 2) {
            option("square.grid.2x2", list: false, help: "Posters")
            option("list.bullet", list: true, help: "List")
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.field))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.07)))
    }

    private func option(_ symbol: String, list: Bool, help: String) -> some View {
        Button {
            asList = list
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(asList == list ? Color.white : Color.secondary)
                .frame(width: 28, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(asList == list ? Color.white.opacity(0.12) : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

struct RemovableChip: View {
    let title: String
    let remove: () -> Void

    var body: some View {
        Button(action: remove) {
            HStack(spacing: 5) {
                Text(title)
                Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold))
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().strokeBorder(Theme.hairline).background(Capsule().fill(Theme.panel)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Search the library: a slim field beside the title (titles, people, places, moods, years).
struct LibrarySearchField: View {
    @Binding var text: String
    @Binding var focusRequested: Bool
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search films, people, craft", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onExitCommand { focused = false }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 260, height: 32)
        .background(Capsule().fill(Color.white.opacity(focused ? 0.11 : 0.07)))
        .overlay(Capsule().strokeBorder(focused ? Theme.brand.opacity(0.6) : Theme.hairline))
        .animation(.easeOut(duration: 0.15), value: focused)
        // ⌘F (RootView), also when it brought All Films up for it.
        .onAppear(perform: takeFocus)
        .onChange(of: focusRequested) { takeFocus() }
    }

    private func takeFocus() {
        guard focusRequested else { return }
        focusRequested = false
        Task { @MainActor in focused = true }
    }
}
#endif
