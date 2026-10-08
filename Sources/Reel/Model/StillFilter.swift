#if os(macOS)
import CoreGraphics
import Vision

/// TMDB doesn't separate frames from the film from promotional art and behind-the-scenes photos.
/// This looks at each image on the Mac and keeps the ones that look like frames:
/// - no text (posters, title cards),
/// - no film gear in view (behind-the-scenes photos),
/// - not a collage of faces at different sizes (key art),
/// - no large empty side left for a title (textless poster art).
enum StillFilter {
    static let crewGear: Set<String> = [
        "camera", "tripod", "microphone", "camera_lens", "studio", "film_camera", "video_camera", "boom_microphone",
    ]
    /// Image types that are designed rather than filmed.
    static let artwork: Set<String> = [
        "poster", "collage", "illustrations", "cartoon", "comics", "graphic_design", "screenshot", "document",
        "text", "logo", "drawing", "painting",
    ]

    static func looksLikeFrame(_ image: CGImage) -> Bool {
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .fast
        text.usesLanguageCorrection = false
        let classify = VNClassifyImageRequest()
        let faces = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([text, classify, faces])
        } catch {
            return true
        }
        let letters = (text.results ?? [])
            .compactMap { $0.topCandidates(1).first }
            .filter { $0.confidence > 0.5 }
            .reduce(0) { $0 + $1.string.filter { $0.isLetter }.count }
        if letters >= 8 { return false }

        let labels = (classify.results ?? []).filter { $0.confidence > 0.3 }.map { $0.identifier }
        if labels.contains(where: { crewGear.contains($0) || artwork.contains($0) }) { return false }

        // Key art stacks several characters at very different sizes; a frame rarely does.
        let heights = (faces.results ?? []).map { $0.boundingBox.height }.filter { $0 > 0.03 }
        if heights.count >= 4 { return false }
        if heights.count >= 3, let big = heights.max(), let small = heights.min(), big / small > 2.5 { return false }

        return !hasEmptySide(image)
    }

    /// Textless poster art keeps one side nearly empty (flat colour) for the title while the
    /// other side is busy. Real frames that are dark all over, or have letterbox bars, pass.
    static func hasEmptySide(_ image: CGImage) -> Bool {
        let columns = 48, rows = 27
        guard let context = CGContext(data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: columns,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let data = context.data else { return false }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        let pixels = data.bindMemory(to: UInt8.self, capacity: columns * rows)

        func spread(_ columnRange: Range<Int>) -> Double {
            var values: [Double] = []
            for y in 0..<rows {
                for x in columnRange { values.append(Double(pixels[y * columns + x])) }
            }
            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
            return variance.squareRoot()
        }
        let third = columns / 3
        let left = spread(0..<third)
        let right = spread((columns - third)..<columns)
        let flat = min(left, right), busy = max(left, right)
        return flat < 6 && busy > 30
    }
}
#endif
