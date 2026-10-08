#if os(macOS)
import AppKit
import SwiftUI
import ReelCore

/// A director, cinematographer, composer or actor: photo, bio, films you own, full filmography.
struct PersonPage: View {
    @Environment(AppModel.self) private var model
    let route: PersonRoute

    @State private var person: TMDBPerson?
    @State private var films: [FilmographyEntry] = []
    @State private var loadFailed = false
    @State private var department: String?
    @State private var showFullBio = false
    @State private var preview: PreviewFilm?
    /// Their films as a director or cinematographer, to collect.
    @State private var filmSet: FilmSet?
    @State private var onlyMissing = false

    private let columns = [GridItem(.adaptive(minimum: 128, maximum: 160), spacing: 20, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                header
                if let filmSet {
                    SetProgressHeader(title: filmSet.kind == .director ? "Films directed by \(route.name)"
                                                                       : "Films shot by \(route.name)",
                                      set: filmSet)
                }
                if person != nil {
                    let owned = films.filter { model.itemsByTMDB[$0.id] != nil }
                    if !owned.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Theme.sectionTitle("In Your Library")
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                                ForEach(owned) { entry in filmCell(entry) }
                            }
                        }
                    }
                    filmography
                } else if loadFailed {
                    Text("Couldn't load this page. Check the internet connection and try again.")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 28)
            .frame(maxWidth: 1180, alignment: .leading)
        }
        .background(Theme.background)
        .navigationTitle(route.name)
        .filmPreviewSheet($preview)
        .task(id: route.id) {
            loadFailed = false
            if let loaded = await model.person(id: route.id) {
                person = loaded
                films = await Task.detached(priority: .userInitiated) { Filmography.build(loaded) }.value
                filmSet = Self.set(for: loaded, owned: model.ownedIDs)
            } else {
                loadFailed = true
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 26) {
            Color(white: 0.14)
                .frame(width: 132, height: 132)
                .overlay {
                    CachedImage(path: person?.profilePath, kind: .profile) {
                        Image(systemName: "person.fill").font(.system(size: 44)).foregroundStyle(.tertiary)
                    }
                }
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.hairline))
            VStack(alignment: .leading, spacing: 8) {
                Text(route.name)
                    .font(.system(size: 34, weight: .bold))
                if let line = factLine {
                    Text(line)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.secondaryText)
                }
                if let bio = person?.biography, !bio.isEmpty {
                    Text(bio)
                        .font(.system(size: 14))
                        .lineSpacing(4)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(showFullBio ? nil : 4)
                        .frame(maxWidth: 720, alignment: .leading)
                        .textSelection(.enabled)
                    if bio.count > 320 {
                        Button(showFullBio ? "Less" : "More") {
                            withAnimation(.easeOut(duration: 0.2)) { showFullBio.toggle() }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.brand)
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    /// "Camera · Born 1949 in Torquay, England · 84 films"
    private var factLine: String? {
        guard let person else { return nil }
        var parts: [String] = []
        if let department = person.knownForDepartment { parts.append(department) }
        if let born = person.birthday?.prefix(4), !born.isEmpty {
            var text = "Born \(born)"
            if let place = person.placeOfBirth, !place.isEmpty { text += " in \(place)" }
            parts.append(text)
        }
        if let died = person.deathday?.prefix(4), !died.isEmpty { parts.append("Died \(died)") }
        if !films.isEmpty { parts.append("\(films.count) films") }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    /// Directors are collected by the films they directed, cinematographers by the films they shot.
    static func set(for person: TMDBPerson, owned: Set<Int>) -> FilmSet? {
        let order: [FilmSet.Kind] = person.knownForDepartment == "Camera" ? [.cinematographer, .director] : [.director, .cinematographer]
        return order.lazy.map { FilmSets.person(person, kind: $0) }.first { $0.films(owned: owned).count >= 2 }
    }

    // MARK: Filmography

    private var filmography: some View {
        let departments = Filmography.departments(in: films)
        let missing = Set((filmSet?.films(owned: model.ownedIDs) ?? []).map { $0.id }.filter { model.itemsByTMDB[$0] == nil })
        let shown = onlyMissing ? films.filter { missing.contains($0.id) }
            : department.map { d in films.filter { $0.departments.contains(d) } } ?? films
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                Theme.sectionTitle("Filmography")
                if departments.count > 1 || !missing.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(title: "All", isOn: department == nil && !onlyMissing) {
                                department = nil
                                onlyMissing = false
                            }
                            if !missing.isEmpty {
                                FilterChip(title: "Missing from Your Set", isOn: onlyMissing) {
                                    onlyMissing.toggle()
                                    department = nil
                                }
                            }
                            if departments.count > 1 {
                                ForEach(departments, id: \.self) { d in
                                    FilterChip(title: d, isOn: department == d && !onlyMissing) {
                                        department = department == d ? nil : d
                                        onlyMissing = false
                                    }
                                }
                            }
                        }
                    }
                }
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(shown) { entry in filmCell(entry) }
            }
        }
    }

    @ViewBuilder
    private func filmCell(_ entry: FilmographyEntry) -> some View {
        if let item = model.itemsByTMDB[entry.id] {
            NavigationLink(value: FilmRoute(id: item.main.id)) {
                cellBody(entry, owned: true)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                preview = PreviewFilm(entry)
            } label: {
                cellBody(entry, owned: false)
            }
            .buttonStyle(.plain)
        }
    }

    private func cellBody(_ entry: FilmographyEntry, owned: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Poster(path: entry.posterPath, title: entry.title, cornerRadius: 8)
                .opacity(owned ? 1 : 0.8)
                .overlay(alignment: .topTrailing) {
                    if owned {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.white, Theme.brand)
                            .padding(6)
                            .help("In your library")
                    }
                }
            Text(entry.title)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
            Text([entry.year.map { String($0) }, entry.roles.first].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}
#endif
