import XCTest
@testable import ReelCore

final class CameraSourcesTests: XCTestCase {
    func testCitedLinksArePickedForTheCraft() {
        let links = [
            "https://www.boxofficemojo.com/release/rl123/",
            "https://variety.com/2016/film/news/arrival-box-office-1201912345/",
            "https://www.indiewire.com/2016/11/arrival-bradford-young-cinematography-interview-1201746011/",
            "https://theasc.com/article/arrival-cinematography-bradford-young/",
            "https://theasc.com/article/arrival-cinematography-bradford-young/",
            "https://www.kodak.com/en/motion/blog-post/arrival",
            "https://www.indiewire.com/tag/arrival/",
            "https://www.nytimes.com/2016/11/10/movies/arrival-review.html",
        ]
        let picked = CameraSources.pick(links, cinematographers: ["Bradford Young"])
        XCTAssertEqual(picked.map(\.site), ["American Cinematographer", "Kodak", "IndieWire"],
                       "craft sites naming the cinematographer first; box office, reviews and tag pages left out; each once")
        XCTAssertEqual(picked.first?.url.absoluteString, "https://theasc.com/article/arrival-cinematography-bradford-young/")
    }

    func testAnASCResultMustBeAboutTheFilm() {
        XCTAssertTrue(CameraSources.isAbout(title: "Arrival", articleTitle: "Universal Translator: <em>Arrival</em>",
                                            url: "https://theasc.com/article/arrival-cinematography-bradford-young/"))
        XCTAssertFalse(CameraSources.isAbout(title: "Arrival", articleTitle: "Meet the Nominees",
                                             url: "https://theasc.com/article/nominees-arrival-of-spring/"))
        XCTAssertTrue(CameraSources.isAbout(title: "Blade Runner 2049", articleTitle: "Future Noir",
                                            url: "https://theasc.com/article/blade-runner-2049-deakins/"))
        XCTAssertFalse(CameraSources.isAbout(title: "Parasite", articleTitle: "Caught: A Lost Noir Classic",
                                             url: "https://theasc.com/article/caught-a-lost-noir-classic/"))
    }

    func testAPageIsReadAsParagraphs() {
        let html = """
        <html><head><title>Lighting the Dark | American Cinematographer</title>
        <meta property="og:title" content="Lighting the Dark: Arrival &amp; the Fog" />
        <script>var p = "<p>not this</p>";</script></head>
        <body><nav><p>Home About Subscribe to our newsletter today</p></nav>
        <p>Young shot <em>Arrival</em> on the ARRI Alexa XT with Zeiss Ultra Primes, and he &#8220;wanted the light to feel like fog.&#8221;</p>
        <p>Short.</p>
        <p>The production used a single 18K HMI through a big diffusion frame&nbsp;outside the windows of the hall.</p>
        <footer><p>All rights reserved. Copyright 2026 American Society of Cinematographers.</p></footer>
        </body></html>
        """
        XCTAssertEqual(HTMLText.title(html), "Lighting the Dark: Arrival & the Fog")
        XCTAssertEqual(HTMLText.paragraphs(html), [
            "Young shot Arrival on the ARRI Alexa XT with Zeiss Ultra Primes, and he “wanted the light to feel like fog.”",
            "The production used a single 18K HMI through a big diffusion frame outside the windows of the hall.",
        ])
    }

    func testSpoilersStayOutOfWhatIsReadUntilWatched() {
        let reading = CameraReading(sources: [
            CameraReading.Source(title: "T", site: "Kodak", url: URL(string: "https://kodak.com/a")!, paragraphs: [
                "We shot the whole film on Kodak Vision3 500T.",
                "For the final scene, where she dies, we went handheld.",
            ]),
        ], more: [], cinematographer: nil)
        XCTAssertEqual(reading.texts(hiding: true).first?.sections.first?.paragraphs, ["We shot the whole film on Kodak Vision3 500T."])
        XCTAssertEqual(reading.texts(hiding: false).first?.sections.first?.paragraphs.count, 2)
    }
}
