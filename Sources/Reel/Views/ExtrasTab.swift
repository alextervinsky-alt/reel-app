#if os(macOS)
import AppKit
import QuickLook
import SwiftUI
import ReelCore

extension ExtraKind {
    var symbol: String {
        switch self {
        case .trailer: "film"
        case .interview: "quote.bubble"
        case .behindTheScenes: "video"
        case .deletedScene: "scissors"
        case .festival: "laurel.leading"
        case .short: "film.stack"
        case .commentary: "mic"
        case .gallery: "photo.on.rectangle"
        case .bonus: "sparkles"
        case .part: "square.stack"
        case .sample: "play.rectangle"
        case .subtitle: "captions.bubble"
        case .document: "doc.text"
        case .image: "photo"
        case .audio: "music.note"
        }
    }
}

/// Everything found with the film: bonus videos to play, subtitles and other files to look at.
/// Nothing here is changed on the drive; files open in their usual app or in Quick Look.
struct ExtrasTab: View {
    @Environment(AppModel.self) private var model
    let film: FilmEntry
    @State private var lookingAt: URL?

    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 18, alignment: .top)]

    var body: some View {
        if let copy = model.extrasSource(for: film) {
            let catalog = ExtrasCatalog(copy.extras)
            let online = model.fileURL(copy) != nil
            let titles = [film.displayTitle, film.parsed.title, film.tmdb?.originalTitle].compactMap { $0 }
            let art = film.checkedStills ?? film.tmdb?.stillPaths ?? []
            let people = creditPeople
            let previewable = online ? (catalog.subtitles + catalog.otherFiles)
                .filter { Self.quickLooks($0) }
                .compactMap { model.url(of: $0, in: copy) } : []

            VStack(alignment: .leading, spacing: 36) {
                if !online {
                    Label("Connect \(model.drive(copy.driveID)?.name ?? "the drive") to play these.", systemImage: "externaldrive")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                if !catalog.videos.isEmpty {
                    section("Bonus Material", count: catalog.videos.count) {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                            ForEach(Array(catalog.videos.enumerated()), id: \.element.id) { index, video in
                                let title = video.file.title(removing: titles)
                                let person = ExtraPeople.person(in: title, among: people)
                                ExtraCard(
                                    video: video, title: title,
                                    subtitle: person.map { "\($0.name) · \($0.role)" } ?? video.file.kind.label,
                                    art: art.isEmpty ? film.tmdb?.backdropPath : art[(index * 3 + 1) % art.count],
                                    online: online
                                ) {
                                    model.open(video.file, in: copy)
                                }
                                .contextMenu { menu(video.file, copy: copy, online: online) }
                            }
                        }
                    }
                }
                if !catalog.subtitles.isEmpty {
                    section("Subtitles", count: catalog.subtitles.count) {
                        fileList(catalog.subtitles, copy: copy, online: online, titles: titles)
                    }
                }
                if !catalog.otherFiles.isEmpty {
                    section("Other Files", count: catalog.otherFiles.count) {
                        fileList(catalog.otherFiles, copy: copy, online: online, titles: titles)
                    }
                }
            }
            .quickLookPreview($lookingAt, in: previewable)
        }
    }

    /// Who the film's people are, so "Chris Doyle.mkv" can say "Christopher Doyle · Director of Photography".
    private var creditPeople: [(name: String, role: String)] {
        guard let credits = film.tmdb?.credits else { return [] }
        let crew = credits.crew.map { (name: $0.name, role: $0.job ?? "Crew") }
        let cast = credits.cast.map { member in (name: member.name, role: member.character.map { "as \($0)" } ?? "Cast") }
        return crew + cast
    }

    /// Text and pictures open in Quick Look; videos and audio in their player.
    static func quickLooks(_ extra: FilmExtra) -> Bool {
        extra.kind == .subtitle || extra.kind == .document || extra.kind == .image
    }

    private func section<Content: View>(_ title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Theme.sectionTitle(title)
                Text("\(count)").font(.system(size: 13)).foregroundStyle(.tertiary)
            }
            content()
        }
    }

    private func fileList(_ files: [FilmExtra], copy: FilmEntry, online: Bool, titles: [String]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                if index > 0 { Divider().overlay(Theme.hairline).padding(.leading, 48) }
                ExtraFileRow(file: file, name: name(of: file, titles: titles), online: online) {
                    if Self.quickLooks(file) {
                        lookingAt = model.url(of: file, in: copy)
                    } else {
                        model.open(file, in: copy)
                    }
                }
                .contextMenu { menu(file, copy: copy, online: online) }
            }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panel))
        .frame(maxWidth: 760)
    }

    private func name(of file: FilmExtra, titles: [String]) -> String {
        switch file.kind {
        case .subtitle:
            return [file.language ?? "Subtitles", file.subtitleFlag].compactMap { $0 }.joined(separator: " · ")
        case .document, .image:
            return file.fileName
        case .sample:
            return "Sample"
        default:
            return file.title(removing: titles)
        }
    }

    @ViewBuilder
    private func menu(_ file: FilmExtra, copy: FilmEntry, online: Bool) -> some View {
        Button(file.kind.isVideo || file.kind == .audio ? "Play" : "Open") { model.open(file, in: copy) }
            .disabled(!online)
        if Self.quickLooks(file) {
            Button("Quick Look") { lookingAt = model.url(of: file, in: copy) }
                .disabled(!online)
        }
        Button("Show in Finder") { model.showInFinder(file, in: copy) }
            .disabled(!online)
        if file.kind.isVideo {
            Divider()
            Button("This Is a Film") { model.makeFilm(file) }
                .help("List it in the library as a film of its own. Nothing on the drive changes.")
            if model.isRegrouped(file.relativePath) {
                Button("Undo Regrouping") { model.resetGrouping(file.relativePath) }
            }
        }
    }
}

/// A bonus video: a frame from the film as its picture, what it is, and a play button on hover.
struct ExtraCard: View {
    let video: ExtrasCatalog.Video
    let title: String
    let subtitle: String
    let art: String?
    let online: Bool
    let play: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: 10) {
                Color(white: 0.1)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .overlay {
                        CachedImage(path: art, kind: .still) { Theme.brandGradient.opacity(0.25) }
                    }
                    .overlay {
                        LinearGradient(colors: [Color.black.opacity(0.1), Color.black.opacity(0.55)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .overlay(alignment: .topLeading) {
                        Label(video.file.kind.label, systemImage: video.file.kind.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(10)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if !video.subtitles.isEmpty {
                            Text("CC")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white.opacity(0.8)))
                                .padding(10)
                                .help("Has subtitles")
                        }
                    }
                    .overlay {
                        if hovering && online {
                            Image(systemName: "play.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Color.black)
                                .frame(width: 48, height: 48)
                                .background(Circle().fill(Color.white))
                                .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .opacity(online ? 1 : 0.55)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!online)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(video.file.fileName)
    }
}

struct ExtraFileRow: View {
    let file: FilmExtra
    let name: String
    let online: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: file.kind.symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 13.5, weight: .medium))
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 12)
                Text(Format.bytes(file.size))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(hovering && online ? Color.white.opacity(0.04) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!online)
        .onHover { hovering = $0 }
    }

    private var detail: String {
        switch file.kind {
        case .subtitle: "\(file.subtitleFormat) · \(file.fileName)"
        case .document, .image: file.kind.label
        default: "\(file.kind.label) · \(file.fileName)"
        }
    }
}
#endif
