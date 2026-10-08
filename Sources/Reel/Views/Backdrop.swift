#if os(macOS)
import SwiftUI
import Vision
import ReelCore

/// A backdrop that fills its frame without cutting off heads. Wide frames only show a band of
/// the image; instead of the middle band, Reel finds the people in it (on the Mac, once per
/// image) and shows the band from just above the highest head. Without people it keeps more of
/// the top than the bottom, where titles and horizons usually sit.
struct FocusedBackdrop: View {
    let path: String?
    @State private var shown: (path: String, image: DecodedImage, peopleTop: CGFloat?)?

    var body: some View {
        GeometryReader { geometry in
            if let shown = current {
                let width = CGFloat(shown.image.cgImage.width)
                let height = CGFloat(shown.image.cgImage.height)
                let scale = max(geometry.size.width / width, geometry.size.height / height)
                let drawnWidth = width * scale
                let drawnHeight = height * scale
                let top = Self.topFraction(people: shown.peopleTop, visible: geometry.size.height / drawnHeight)
                Image(decorative: shown.image.cgImage, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .frame(width: drawnWidth, height: drawnHeight)
                    .offset(x: (geometry.size.width - drawnWidth) / 2, y: -top * drawnHeight)
                    .transition(.opacity)
            } else {
                Color(white: 0.07)
            }
        }
        .clipped()
        .task(id: path) {
            guard let path, shown?.path != path else { return }
            // What `current` drew before any waiting: in memory, framing known.
            let drawnFromMemory = ImageStore.shared.cached(path, .backdrop)
            let knownTop = BackdropFocus.known(path)
            guard let image = await ImageStore.shared.image(path, .backdrop) else { return }
            let top = await BackdropFocus.peopleTop(path: path, image: image)
            // Already on screen from memory with the same framing: nothing to animate.
            if drawnFromMemory === image, knownTop == .some(top) {
                shown = (path, image, top)
            } else {
                withAnimation(.easeOut(duration: 0.3)) { shown = (path, image, top) }
            }
        }
    }

    /// What to draw: the loaded image, or one already in memory (no fade-in, and drawable when
    /// a screen is rendered to an image).
    private var current: (path: String, image: DecodedImage, peopleTop: CGFloat?)? {
        if let shown, shown.path == path { return shown }
        guard let path, let image = ImageStore.shared.cached(path, .backdrop) else { return nil }
        return (path, image, BackdropFocus.known(path) ?? nil)
    }

    /// Where the visible band starts, as a fraction of the image height from the top.
    static func topFraction(people: CGFloat?, visible: CGFloat) -> CGFloat {
        let lowest = max(0, 1 - visible)
        guard let people else { return lowest * 0.2 }
        // A little headroom above the highest head.
        return min(max(0, people - 0.08), lowest)
    }
}

/// Finds the top of the highest head in an image, remembered per image for the session.
@MainActor
enum BackdropFocus {
    private static var known: [String: CGFloat] = [:]
    private static var nobody: Set<String> = []

    /// The framing found earlier this session: .some(nil) when the image has no people,
    /// nil when it hasn't been looked at yet.
    static func known(_ path: String) -> CGFloat?? {
        if let top = known[path] { return .some(top) }
        return nobody.contains(path) ? .some(nil) : nil
    }

    static func peopleTop(path: String, image: DecodedImage) async -> CGFloat? {
        if let top = known[path] { return top }
        if nobody.contains(path) { return nil }
        let cgImage = image.cgImage
        let top = await Task.detached(priority: .userInitiated) { detect(in: cgImage) }.value
        if let top { known[path] = top } else { nobody.insert(path) }
        return top
    }

    nonisolated static func detect(in image: CGImage) -> CGFloat? {
        let faces = VNDetectFaceRectanglesRequest()
        let bodies = VNDetectHumanRectanglesRequest()
        bodies.upperBodyOnly = false
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([faces, bodies])
        var tops: [CGFloat] = []
        // Vision measures from the bottom; the face box starts at the brow, so hair is added above it.
        for face in faces.results ?? [] where face.boundingBox.height > 0.05 {
            tops.append(1 - face.boundingBox.maxY - face.boundingBox.height * 0.35)
        }
        for body in bodies.results ?? [] where body.confidence > 0.6 && body.boundingBox.height > 0.3 {
            tops.append(1 - body.boundingBox.maxY)
        }
        return tops.min().map { max(0, $0) }
    }
}
#endif
