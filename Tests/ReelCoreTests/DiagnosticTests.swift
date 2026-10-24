import XCTest
@testable import ReelCore

/// TEMPORARY (diag branch only): the structure of three public pages, for the 1.9.8 design.
final class DiagnosticTests: XCTestCase {
    private var lines: [String] = []
    private func say(_ s: String) { lines.append(s.replacingOccurrences(of: "\n", with: " ")) }
    private func flush(_ tag: String) {
        // Annotations: a few long notices (GitHub keeps ten a step).
        let joined = lines.joined(separator: " ¦ ")
        var start = joined.startIndex
        var part = 0
        while start < joined.endIndex, part < 3 {
            let end = joined.index(start, offsetBy: 3500, limitedBy: joined.endIndex) ?? joined.endIndex
            FileHandle.standardOutput.write(Data(("::notice::DIAG \(tag) \(part): " + joined[start..<end] + "\n").utf8))
            start = end
            part += 1
        }
        lines = []
    }

    func testStructure() async throws {
        let client = CameraSourcesClient()
        // 1. IndieWire's Cannes 2024 gallery: the paragraphs around Megalopolis.
        let iw = await client.page(URL(string: "https://www.indiewire.com/gallery/cannes-2024-cameras-arri-furiosa/megalopolis-mihai-malaimare-jr-dp/")!,
                                   site: "IndieWire", title: nil)
        if let paras = iw.source?.paragraphs {
            say("IW paragraphs \(paras.count)")
            let hits = paras.indices.filter { paras[$0].localizedCaseInsensitiveContains("megalopolis") || paras[$0].contains("laimare") }
            say("IW naming indices \(hits)")
            for h in hits.prefix(3) {
                for i in max(0, h - 3)...min(paras.count - 1, h + 8) {
                    let p = paras[i]
                    say("IW [\(i)] len=\(p.count) sheet=\(TechSpecs.isSpecList(p)) names=\(p.localizedCaseInsensitiveContains("megalopolis") || p.contains("laimare")) :: \(String(p.prefix(110)))")
                }
            }
        } else { say("IW failed \(String(describing: iw.failure))") }
        flush("IW")
        // 2. American Cinematographer on Megalopolis: around the F900 sentence.
        let ac = await client.page(URL(string: "https://theasc.com/article/material-ecology-megalopolis/")!, site: "American Cinematographer", title: nil)
        if let paras = ac.source?.paragraphs {
            for (i, p) in paras.enumerated() where p.contains("F900") || p.contains("Alexa") {
                let s = Digest.sentences(in: p)
                for (j, x) in s.enumerated() where x.contains("F900") || x.contains("Alexa") {
                    say("AC [\(i).\(j)] prev=\(j > 0 ? String(s[j - 1].prefix(160)) : "-") :: \(String(x.prefix(160)))")
                }
            }
        } else { say("AC failed \(String(describing: ac.failure))") }
        flush("AC")
        // 3. Kodak on Oppenheimer: every sentence naming IMAX.
        let kodak = await client.page(URL(string: "https://www.kodak.com/en/motion/blog-post/oppenheimer/")!, site: "Kodak", title: nil)
        if let paras = kodak.source?.paragraphs {
            for p in paras { for x in Digest.sentences(in: p) where x.contains("IMAX") { say("KODAK :: \(String(x.prefix(200)))") } }
        } else { say("KODAK failed \(String(describing: kodak.failure))") }
        flush("KODAK")
    }
}
