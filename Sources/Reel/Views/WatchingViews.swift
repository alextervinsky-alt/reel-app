#if os(macOS)
import AppKit
import SwiftUI
import ReelCore

extension Format {
    /// "English and Estonian subtitles · 4K · HDR": what matters on the sofa, from the files.
    /// Posters leave the quality out (`quality: false`): it matters on the film page, not at a glance.
    static func sofaLine(_ film: FilmEntry, quality: Bool = true) -> String? {
        var parts: [String] = []
        let languages = film.subtitleLanguages
        if !languages.isEmpty {
            parts.append(ListFormatter.localizedString(byJoining: languages) + " subtitles")
        } else if film.hasSubtitles {
            parts.append("Subtitles")
        }
        if quality, let label = film.qualityLabel { parts.append(label) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Badges

/// "Palme d'Or · 1994", "Sight & Sound greatest films · #54": the two most notable lists a film is
/// on. The rest are counted ("+2") and named on hover.
struct BadgeRow: View {
    let badges: [ListBadge]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(badges.prefix(2)) { badge in
                NavigationLink(value: ListRoute(kind: badge.kind)) {
                    HStack(spacing: 5) {
                        Image(systemName: badge.symbol).font(.system(size: 10.5, weight: .semibold))
                        Text(badge.text).lineLimit(1)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .foregroundStyle(badge.isWin ? Color(red: 1, green: 0.84, blue: 0.5) : Color.white.opacity(0.8))
                    .background(Capsule().fill(Color.black.opacity(0.35)))
                    .overlay(Capsule().strokeBorder(badge.isWin ? Color(red: 1, green: 0.84, blue: 0.5).opacity(0.45) : Theme.hairline))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("See the list")
            }
            if badges.count > 2 {
                Text("+\(badges.count - 2)")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .foregroundStyle(Color.white.opacity(0.8))
                    .background(Capsule().fill(Color.black.opacity(0.35)))
                    .help(badges.dropFirst(2).map(\.text).joined(separator: "\n"))
            }
        }
    }
}

// MARK: - Playing

/// "Play With" › IINA, VLC, Default App (only the installed ones), and each version.
struct PlayWithMenu: View {
    @Environment(AppModel.self) private var model
    let film: FilmEntry

    var body: some View {
        let versions = model.versions(of: film)
        Menu("Play With") {
            ForEach(PlayerChoice.installed) { player in
                if versions.count > 1 {
                    Menu(player.title) {
                        ForEach(versions) { copy in
                            Button(model.versionTitle(copy)) { model.play(film, version: copy, with: player) }
                        }
                    }
                } else {
                    Button(player.title) { model.play(film, with: player) }
                }
            }
        }
        .disabled(versions.isEmpty)
    }
}

// MARK: - Tonight

/// Tonight's shortlist, side by side: how long, when it would end, what kind of film, what
/// critics thought, subtitles and quality. Clears itself at 6 in the morning.
struct TonightView: View {
    @Environment(AppModel.self) private var model
    @State private var chosen: String?
    @State private var width: CGFloat = 1000

    var body: some View {
        let items = model.tonightItems
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tonight").font(.system(size: 30, weight: .bold))
                        Text("Your shortlist for this evening, side by side. It starts empty again tomorrow.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if items.count > 1 {
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { chosen = items.randomElement()?.id }
                        } label: {
                            Label("Decide for Us", systemImage: "dice")
                        }
                        .buttonStyle(PrimaryCapsuleStyle())
                    }
                    if !items.isEmpty {
                        Button("Clear") {
                            chosen = nil
                            model.clearTonight()
                        }
                        .buttonStyle(SecondaryCapsuleStyle())
                    }
                }
                if items.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing on tonight's shortlist", systemImage: "moon.stars")
                    } description: {
                        Text("Add films with the moon button on a film's page, on Recommended, or by right-clicking a poster.")
                    }
                    .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    let picked = TonightPick.current(chosen, in: items)
                    let slots = TonightSlots(items, model: model)
                    let columnWidth = TonightSlots.width(for: items.count, in: width, large: false)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(items) { item in
                                TonightCompareColumn(item: item, slots: slots, width: columnWidth, chosen: picked == item.id,
                                                     dimmed: picked != nil && picked != item.id, large: false) {
                                    model.filmToOpen = item.main.id
                                }
                            }
                        }
                        .padding(.bottom, 6)
                    }
                    .scrollClipDisabled()
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 22)
            .onGeometryChange(for: CGFloat.self) { $0.size.width - 64 } action: { width = $0 }
        }
        .background(Theme.background)
        .navigationTitle("Tonight")
        .onAppear { model.startNewEveningIfNeeded() }
    }
}

// MARK: - How was it?

/// Asked once after marking a film watched: your shared stars and a line for the notes.
struct HowWasItSheet: View {
    @Environment(AppModel.self) private var model
    let prompt: RatingPrompt
    /// Back from the player: first "Did you finish it?", then the stars.
    @State private var finished = false
    @State private var stars: Int?
    @State private var line = ""

    var body: some View {
        let film = model.film(id: prompt.filmID)
        let asking = prompt.askFinished && !finished
        VStack(alignment: .leading, spacing: 18) {
            FocusedBackdrop(path: film?.tmdb?.backdropPath)
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(asking ? "Did you finish it?" : "How was it?").font(.system(size: 22, weight: .bold))
                Text(film?.displayTitle ?? "").font(.system(size: 14)).foregroundStyle(.secondary)
            }
            if asking {
                finishButtons
            } else {
                rating
            }
        }
        .padding(22)
        .frame(width: 440)
        .onAppear { stars = film.map { model.record(for: $0).rating } ?? nil }
    }

    /// Big buttons: this sheet is often answered from the sofa.
    private var finishButtons: some View {
        HStack(spacing: 10) {
            Button("Not Yet") {
                // Still to finish: kept on tonight's shortlist.
                model.addToTonight(prompt.id)
                model.ratingPrompt = nil
            }
            .buttonStyle(SecondaryCapsuleStyle())
            Button("Didn't Watch") { model.ratingPrompt = nil }
                .buttonStyle(SecondaryCapsuleStyle())
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("Yes, Finished") {
                model.markFinished(prompt)
                withAnimation(.easeOut(duration: 0.2)) { finished = true }
            }
            .buttonStyle(PrimaryCapsuleStyle())
            .keyboardShortcut(.defaultAction)
        }
    }

    private var rating: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { i in
                    Button {
                        stars = stars == i ? nil : i
                    } label: {
                        Image(systemName: (stars ?? 0) >= i ? "star.fill" : "star")
                            .font(.system(size: 30))
                            .foregroundStyle((stars ?? 0) >= i ? Color.yellow : Color.white.opacity(0.4))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            TextField("One line to remember it by (optional)", text: $line)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack {
                Button("Not Now") { model.ratingPrompt = nil }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(stars == nil && line.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func save() {
        model.rate(prompt, stars: stars, line: line)
    }
}
#endif
