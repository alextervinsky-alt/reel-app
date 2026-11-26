#if os(macOS)
import SwiftUI
import ReelCore

// MARK: - New Releases

/// What's new, wherever it's showing (1.11.2, Alex's decision of 26 Nov: its own tab rather than
/// low on Explore): in cinemas now, coming to cinemas, recently in cinemas and now out online,
/// and new on Blu-ray. Films you've seen are left out, as in Explore.
struct NewReleasesView: View {
    @Environment(AppModel.self) private var model
    @State private var preview: PreviewFilm?

    static let lists: [DiscoverList] = [.inCinemas, .comingSoon, .newAtHome, .newOnBluRay]

    var body: some View {
        ScrollView {
            // Lazy: a row is made as it comes into view.
            LazyVStack(alignment: .leading, spacing: 38) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("New Releases").font(.system(size: 30, weight: .bold))
                    Text("In cinemas now and soon, and just out to watch at home: online and on Blu-ray.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                ForEach(Self.lists, id: \.self) { list in
                    DiscoverRow(list: list) { preview = $0 }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .tracksScrolling("New Releases")
        .background(Theme.background)
        .navigationTitle("New Releases")
        .filmPreviewSheet($preview)
        .task {
            await withTaskGroup(of: Void.self) { group in
                for list in Self.lists {
                    group.addTask { await model.loadDiscover(list) }
                }
            }
        }
    }
}
#endif
