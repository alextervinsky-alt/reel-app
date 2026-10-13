#if os(macOS)
import SwiftUI
import ReelCore

/// Back from the player in Cinema mode: "Did you finish it?", then "How was it?", large enough
/// for the TV. The arrow keys pick the answer and the stars (left and right set them), Return
/// chooses, Esc puts it off. The same shared stars as everywhere in Reel.
struct CinemaHowWasIt: View {
    @Environment(AppModel.self) private var model
    let prompt: RatingPrompt
    @State private var finished = false
    @State private var stars: Int?
    /// Where the keys are: the stars (row 0) or the buttons (row 1), and which one.
    @State private var row = 1
    @State private var index = 0

    private var asking: Bool { prompt.askFinished && !finished }

    var body: some View {
        let film = model.film(id: prompt.filmID)
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 30) {
                FocusedBackdrop(path: film?.tmdb?.backdropPath)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                VStack(alignment: .leading, spacing: 8) {
                    Text(asking ? "Did you finish it?" : "How was it?")
                        .font(.system(size: Cinema.title, weight: .bold))
                    Text(film?.displayTitle ?? "")
                        .font(.system(size: Cinema.body))
                        .foregroundStyle(.secondary)
                }
                if !asking { starRow }
                HStack(spacing: 16) {
                    ForEach(Array(buttons.enumerated()), id: \.offset) { offset, button in
                        Button(button.title, action: button.action)
                            .buttonStyle(CinemaButtonStyle(primary: offset == 0, focused: row == 1 && index == offset))
                    }
                }
            }
            .padding(44)
            .frame(width: 940, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Theme.background))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Theme.hairline))
        }
        .onAppear {
            stars = film.map { model.record(for: $0).rating } ?? nil
            // On the stars only when there are some: Return never saves stars nobody chose.
            row = prompt.askFinished || stars == nil ? 1 : 0
            index = row == 1 ? 0 : max((stars ?? 1) - 1, 0)
        }
        .onReelKey(key)
    }

    private var starRow: some View {
        HStack(spacing: 14) {
            ForEach(1...5, id: \.self) { i in
                Button {
                    stars = stars == i ? nil : i
                    row = 0
                    index = i - 1
                } label: {
                    Image(systemName: (stars ?? 0) >= i ? "star.fill" : "star")
                        .font(.system(size: 58))
                        .foregroundStyle((stars ?? 0) >= i ? Color.yellow : Color.white.opacity(0.4))
                        .frame(width: 92, height: 92)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .cinemaFocus(row == 0 && index == i - 1, circle: true)
            }
        }
    }

    private struct Answer {
        let title: String
        let action: () -> Void
    }

    /// The first is the main answer.
    private var buttons: [Answer] {
        if asking {
            return [
                Answer(title: "Yes, Finished") {
                    model.markFinished(prompt)
                    withAnimation(.easeOut(duration: 0.2)) { finished = true }
                    row = 0
                    index = max((stars ?? 3) - 1, 0)
                },
                // Still to finish: kept on tonight's shortlist.
                Answer(title: "Not Yet") {
                    model.addToTonight(prompt.id)
                    model.ratingPrompt = nil
                },
                Answer(title: "Didn't Watch") { model.ratingPrompt = nil },
            ]
        }
        return [
            Answer(title: "Save") { model.rate(prompt, stars: stars, line: "") },
            Answer(title: "Not Now") { model.ratingPrompt = nil },
        ]
    }

    /// Left and right move along a row (on the stars they set them), up and down between the
    /// stars and the buttons, Return chooses, Esc puts it off.
    private func key(_ key: ReelKey) -> Bool {
        let count = row == 0 ? 5 : buttons.count
        switch key {
        case .left, .right:
            index = key == .left ? max(index - 1, 0) : min(index + 1, count - 1)
            // On the stars, left and right set them.
            if row == 0 { stars = index + 1 }
        case .up where !asking:
            row = 0
            index = max((stars ?? 3) - 1, 0)
        case .down where !asking:
            row = 1
            index = 0
        case .up, .down: break
        case .enter, .space:
            if row == 1, buttons.indices.contains(index) {
                buttons[index].action()
            } else if row == 0, let stars {
                // Return on the stars keeps them (once some are chosen).
                model.rate(prompt, stars: stars, line: "")
            }
        case .escape:
            model.ratingPrompt = nil
        case .tonight, .fullScreen: break
        }
        return true
    }
}
#endif
