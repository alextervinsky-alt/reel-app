import XCTest
@testable import ReelCore

/// A development aid, not a check (1.10.9): with `REEL_EXPLAIN=1`, prints for each sentence in
/// `REEL_EXPLAIN_FILE` (one per line, "title|sentence") every gear name found, the comparison parts
/// set aside and the claim reason, then what the reader accepted. Skipped otherwise.
final class ClaimExplainTests: XCTestCase {
    func testExplain() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["REEL_EXPLAIN"] == "1", let path = env["REEL_EXPLAIN_FILE"],
              let lines = try? String(contentsOfFile: path, encoding: .utf8) else { throw XCTSkip("development aid") }
        func say(_ line: String) { FileHandle.standardOutput.write(Data(("EXPLAIN| " + line + "\n").utf8)) }
        for line in lines.split(separator: "\n") where line.contains("|") {
            let parts = line.split(separator: "|", maxSplits: 2).map(String.init)
            let title = parts[0], sentence = parts.count == 3 ? parts[2] : parts[1]
            let others = parts.count == 3 ? parts[1].split(separator: ",").map(String.init) : []
            let frame = ComparisonFrame(sentence, title: title, otherTitles: others, people: ["Jane Doe", "Carl Example"])
            say("   main: [\(frame.main)]")
            say("== [\(title)] \(sentence)")
            say("   spans: \(frame.spans.map { String(sentence[$0]) })")
            for rule in TechSpecs.rules {
                for (name, at) in rule.found(in: sentence) {
                    let main = frame.main
                    let at2 = main.index(main.startIndex, offsetBy: sentence.distance(from: sentence.startIndex, to: at.lowerBound))
                        ..< main.index(main.startIndex, offsetBy: sentence.distance(from: sentence.startIndex, to: at.upperBound))
                    let whole = TechSpecs.segmentRange(of: main, around: at2)
                    let part = String(main[whole])
                    say("   main-reading \(TechSpecs.reading(main, at: at2, title: title, otherTitles: others, people: ["Jane Doe", "Carl Example"], kind: rule.kind)) "
                        + "namesAnother=\(TechSpecs.namesAnotherFilm(part, title: title, otherTitles: others, people: ["Jane Doe", "Carl Example"])) "
                        + "anotherPart=\(TechSpecs.namesAnotherPart(TechSpecs.scope(of: main, around: at2), title: title, otherTitles: others)) "
                        + "saidOfAnother=\(TechSpecs.saidOfAnotherTitle(String(main[whole.lowerBound..<at2.upperBound]), title: title)) "
                        + "hedges=\(TechSpecs.hedges(main, around: at2, within: whole)) part=[\(part.trimmingCharacters(in: .whitespaces))]")
                    say("   \(rule.kind) \(name): reason=\(String(describing: ClaimFrame.reason(sentence, at: at, kind: rule.kind, name: name))) "
                        + "setAside=\(String(describing: TechSpecs.setAside(sentence, at: at, title: title, people: ["Jane Doe", "Carl Example"])))")
                }
            }
            let specs = TechSpecs.read(texts: [TechSpecs.Text(source: nil, sections: [FilmArticle.Section(id: 0, title: "", paragraphs: [sentence])], isInterview: false)],
                                       cinematographers: ["Jane Doe"], directors: ["Carl Example"], title: title, otherTitles: others)
            say("   → accepted \(specs.specs.map(\.name)) mentioned \(specs.mentioned.map(\.name)) judged \(specs.judged.map { "\($0.name):\($0.reason)" })")
        }
    }
}
