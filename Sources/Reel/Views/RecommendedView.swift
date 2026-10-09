#if os(macOS)
import AppKit
import SwiftUI
import ReelCore

/// Five films from the library, picked fresh at every launch: a short, varied choice instead of
/// a wall of posters, with what critics and audiences thought of each.
struct RecommendedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recommended").font(.system(size: 30, weight: .bold))
                        Text("Five films from your library, picked fresh each time Reel opens. Choose a mood, or just choose.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !model.recommended.isEmpty {
                        Button {
                            withAnimation(.easeOut(duration: 0.25)) { model.reshuffleRecommended() }
                        } label: {
                            Label("New Picks", systemImage: "shuffle")
                        }
                        .buttonStyle(SecondaryCapsuleStyle())
                        .help(model.recommendedChoice == .any ? "Five other films" : "Five other \(model.recommendedChoice.title.lowercased()) films")
                    }
                }
                if model.recommendedChoices.count > 1 {
                    MoodChips(choices: model.recommendedChoices, selected: model.recommendedChoice) { choice in
                        withAnimation(.easeOut(duration: 0.25)) { model.chooseRecommended(choice) }
                    }
                }
                if model.recommended.isEmpty {
                    ContentUnavailableView("Nothing to recommend yet", systemImage: "wand.and.stars",
                                           description: Text("Films you haven't watched show up here once Reel has found their info."))
                        .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    ForEach(Array(model.recommended.enumerated()), id: \.element.id) { index, item in
                        RecommendationCard(number: index + 1, item: item)
                            .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 22)
            .frame(maxWidth: 1120, alignment: .leading)
        }
        .background(Theme.background)
        .navigationTitle("Recommended")
        // Play is right here: VLC gets a head start.
        .onAppear { model.warmPlayer() }
    }
}

/// Any · Feel-good · Dark · … · Short, each with how many films it has. Moods with fewer than
/// three unwatched films aren't offered.
struct MoodChips: View {
    let choices: [MoodChoiceCount]
    let selected: MoodChoice
    /// How many films each has, after its name (not in Explore, where nothing is counted).
    var counted = true
    let choose: (MoodChoice) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(choices) { entry in
                    let isOn = entry.choice == selected
                    Button {
                        choose(entry.choice)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: entry.choice.symbol).font(.system(size: 11, weight: .semibold))
                            Text(entry.choice.title)
                            if counted {
                                Text("\(entry.count)")
                                    .monospacedDigit()
                                    .foregroundStyle(isOn ? Color.black.opacity(0.5) : Color.white.opacity(0.45))
                            }
                        }
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 13)
                        .frame(height: 30)
                        .background(Capsule().fill(isOn ? Color.white : Color.white.opacity(0.08)))
                        .foregroundStyle(isOn ? Color.black : Color.white.opacity(0.88))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollClipDisabled()
    }
}

struct RecommendationCard: View {
    @Environment(AppModel.self) private var model
    let number: Int
    let item: LibraryItem
    @State private var hovering = false

    var body: some View {
        let film = item.main
        let record = model.record(forKey: item.id)
        HStack(alignment: .top, spacing: 24) {
            NavigationLink(value: FilmRoute(id: film.id)) {
                FocusedBackdrop(path: film.tmdb?.backdropPath)
                    .frame(width: 360, height: 203)
                    .overlay(alignment: .bottomLeading) {
                        Text("\(number)")
                            .font(.system(size: 54, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.92))
                            .shadow(color: Color.black.opacity(0.6), radius: 8)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 2)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline))
                    .scaleEffect(hovering ? 1.02 : 1)
                    .animation(.spring(response: 0.28, dampingFraction: 0.82), value: hovering)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }

            VStack(alignment: .leading, spacing: 9) {
                // Why it's here (the one orange line), then the same order as everywhere else.
                if let reason = model.recommendedReasons[item.id] {
                    Text(reason.long.uppercased())
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.9)
                        .foregroundStyle(Theme.brand)
                        .lineLimit(1)
                }
                Text(film.displayTitle)
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(2)
                Text(([Format.glanceLine(year: film.displayYear, runtime: item.runtime)] + item.moods.prefix(3).map(\.title))
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                RatingStrip(film: film)
                    .font(.system(size: 12.5))
                if let verdict = ReceptionVerdict.sentence(ratings: film.ratings, tmdbVote: film.tmdb?.voteAverage,
                                                           reception: film.reception, cinemaScore: film.funFacts?.cinemaScore) {
                    Text(verdict)
                        .font(.system(size: 13.5, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let overview = film.tmdb?.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    if model.onlineCopy(of: film) != nil {
                        Button {
                            model.play(film)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                        .buttonStyle(PrimaryCapsuleStyle())
                    }
                    NavigationLink(value: FilmRoute(id: film.id)) {
                        Label("Details", systemImage: "info.circle")
                    }
                    .buttonStyle(SecondaryCapsuleStyle())
                    RoundToggle(symbol: "moon", onSymbol: "moon.fill", isOn: model.isTonight(item.id),
                                help: model.isTonight(item.id) ? "On tonight's shortlist" : "Add to Tonight") {
                        model.toggleTonight(item.id)
                    }
                    moreMenu(film: film, record: record)
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.hairline))
    }

    /// Watchlist, Watched and Not Tonight, out of the way of the decision.
    private func moreMenu(film: FilmEntry, record: PersonalRecord) -> some View {
        Menu {
            Button(record.watchlist ? "Remove from Watchlist" : "Add to Watchlist") { model.toggle(\.watchlist, for: film) }
            Button(record.watched ? "Mark as Unwatched" : "Mark as Watched") { model.toggle(\.watched, for: film) }
            Divider()
            Button("Not Tonight (hide for \(AppModel.notTonightDays) days)") {
                withAnimation(.easeOut(duration: 0.25)) { model.notTonight(item.id) }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.white.opacity(0.14)))
                .foregroundStyle(Color.white)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
    }
}
#endif
