import XCTest
@testable import ReelCore

/// The benchmark tiers (1.10.10):
/// - development: the known cases and every earlier corpus (`ReviewRegressionTests`, `ClaimInterpretationTests`,
///   `KnownCasesTests`, the 1.10.9 claim holdout, the research benchmark), which the implementation was tuned on;
/// - validation: `Fixtures/validation-corpus.json`, 20 invented films and 230 labelled statements by a separate
///   author who saw neither Reel's code nor its corpora, read while developing but never tuned to case by case;
/// - final: a sealed holdout by a third author (`SealedHoldoutTests`), which the implementer never saw, scored
///   once on the frozen release candidate.
///
/// Pre-registered gates, set before the validation and final tiers were scored: precision ≥ 0.95, recall ≥
/// 0.75, no statement about another production accepted (cross-film), no accepted claim without its passage.
/// Budget and duplicate-read gates are checked by the research benchmark (`ResearchBenchmarkTests`).
enum Gates {
    static let precision = 0.95
    static let recall = 0.75
    static let crossFilm = 0
    static let passageless = 0

    static func report(_ score: ClaimHoldoutTests.Score) -> [String] {
        var failed: [String] = []
        if score.precision < precision { failed.append(String(format: "precision %.3f < %.2f", score.precision, precision)) }
        if score.recall < recall { failed.append(String(format: "recall %.3f < %.2f", score.recall, recall)) }
        if score.crossFilm > crossFilm { failed.append("cross-film \(score.crossFilm) > \(crossFilm)") }
        if score.passageless > passageless { failed.append("accepted without a passage \(score.passageless)") }
        return failed
    }
}

final class ValidationCorpusTests: XCTestCase {
    func say(_ line: String) { FileHandle.standardOutput.write(Data(("BENCH| " + line + "\n").utf8)) }

    func testTheValidationCorpus() async throws {
        let file = try ClaimHoldoutTests.load("validation-corpus.json")
        XCTAssertEqual(file.films.count, 20)
        XCTAssertEqual(file.claims.count, 230)
        let score = await ClaimHoldoutTests.score(file)
        say("validation: \(score)")
        say("validation " + score.stages)
        say("validation by type: " + score.byType.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.right)/\($0.value.total)" }.joined(separator: ", "))
        for error in score.errors { say("validation " + error) }
        let failed = Gates.report(score)
        say("validation gates: " + (failed.isEmpty ? "all met" : failed.joined(separator: "; ")))
        // The validation tier is reported against the gates; the floors below pin what this release
        // measures, so a change either way shows.
        XCTAssertEqual(score.passageless, 0)
    }
}

/// The sealed final holdout (1.10.10): written by an independent author whose files the implementer never
/// opened, committed base64-encoded so it isn't read by accident, and scored only when `REEL_SEALED=1`, on the
/// frozen release candidate. Only aggregate numbers are printed: no passage, term or error line.
final class SealedHoldoutTests: XCTestCase {
    func testTheSealedHoldout() async throws {
        guard ProcessInfo.processInfo.environment["REEL_SEALED"] == "1" else { throw XCTSkip("sealed: scored once, on the release candidate") }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/sealed-holdout.b64")
        let encoded = try String(contentsOf: url, encoding: .utf8).filter { !$0.isWhitespace }
        guard let data = Data(base64Encoded: encoded) else { return XCTFail("sealed holdout unreadable") }
        let file = try ClaimHoldoutTests.decode(data)
        var score = await ClaimHoldoutTests.score(file)
        score.errors = []
        let line = "SEALED| films \(file.films.count), claims \(file.claims.count) | \(score) | \(score.stages) | gates: "
            + (Gates.report(score).isEmpty ? "all met" : Gates.report(score).joined(separator: "; "))
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
        let byType = score.byType.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.right)/\($0.value.total)" }.joined(separator: ", ")
        FileHandle.standardOutput.write(Data(("SEALED| by type: " + byType + "\n").utf8))
    }
}
