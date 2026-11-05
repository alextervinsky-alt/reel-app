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
            let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
            let title = parts[0], sentence = parts[1]
            let frame = ComparisonFrame(sentence, title: title, otherTitles: [], people: ["Jane Doe", "Carl Example"])
            say("== [\(title)] \(sentence)")
            say("   spans: \(frame.spans.map { String(sentence[$0]) })")
            for rule in TechSpecs.rules {
                for (name, at) in rule.found(in: sentence) {
                    say("   \(rule.kind) \(name): reason=\(String(describing: ClaimFrame.reason(sentence, at: at, kind: rule.kind, name: name))) "
                        + "setAside=\(String(describing: TechSpecs.setAside(sentence, at: at, title: title, people: ["Jane Doe", "Carl Example"])))")
                }
            }
            let specs = TechSpecs.read(texts: [TechSpecs.Text(source: nil, sections: [FilmArticle.Section(id: 0, title: "", paragraphs: [sentence])], isInterview: false)],
                                       cinematographers: ["Jane Doe"], directors: ["Carl Example"], title: title)
            say("   → accepted \(specs.specs.map(\.name)) mentioned \(specs.mentioned.map(\.name)) judged \(specs.judged.map { "\($0.name):\($0.reason)" })")
        }
    }
}
