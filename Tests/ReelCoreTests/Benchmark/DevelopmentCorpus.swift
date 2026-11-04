import Foundation
@testable import ReelCore

/// The development benchmark: 150 synthetic films built from templates, each with a mix of the
/// situations research meets (an article about the film, a cinematographer's membership news with a
/// credits list and another production's gear, an interview covering several productions, a page
/// with an ambiguous title, a VFX company's pages, hedged statements, a provider that doesn't
/// answer, films with almost nothing written about them). The rules were developed against these;
/// the holdout (`HoldoutCorpus`) was written separately, blind to the rules.
enum DevelopmentCorpus {
    static let adjectives = ["Amber", "Silent", "Northern", "Hollow", "Glass", "Iron", "Paper", "Velvet", "Burning", "Distant",
                             "Copper", "Winter", "Salt", "Crimson", "Restless"]
    static let nouns = ["Meridian", "Harbour", "Orchard", "Signal", "Lantern", "Tide", "Archive", "Garden", "Engine", "Frontier",
                        "Choir", "Quarry"]
    static let shorts = ["Moth", "Kiln", "Vow", "Ember", "Rook", "Lull"]
    static let firsts = ["Ana", "Bruno", "Clara", "Dmitri", "Elif", "Farid", "Greta", "Hugo", "Ines", "Jonas", "Kaia", "Luis",
                         "Mira", "Noor", "Otto", "Priya", "Quentin", "Rosa", "Soren", "Tilde"]
    static let lasts = ["Abernathy", "Bellweather", "Castellan", "Dunmore", "Everly", "Fairbank", "Galloway", "Hartigan", "Ivanov",
                        "Jessop", "Kincade", "Lindqvist", "Marchetti", "Northcott", "Okonkwo", "Pembridge", "Quarles", "Rasmussen",
                        "Sorensen", "Thackeray", "Underhill", "Vandermeer", "Whitlock", "Yardley"]
    static let cameras = ["ARRI Alexa Mini", "Sony Venice", "RED Monstro", "ARRI Alexa 65", "Panavision Millennium DXL"]
    static let lenses = ["Cooke S4", "Panavision Primo", "Zeiss Supreme Prime", "Leica Summilux-C"]
    static let lights = ["SkyPanels", "Kino Flos", "Astera tubes", "Creamsource Vortex8"]

    static func title(_ i: Int) -> String {
        if i % 25 == 7 { return shorts[(i / 25) % shorts.count] }
        return "The " + adjectives[i % adjectives.count] + " " + nouns[(i / adjectives.count) % nouns.count]
    }

    static func name(_ i: Int, _ role: Int) -> String {
        firsts[(i * 7 + role * 3) % firsts.count] + " " + lasts[(i * 5 + role * 11) % lasts.count]
    }

    /// Another production's title, never one of the corpus films (so a leak is always detectable).
    static func other(_ i: Int, _ k: Int) -> String {
        ["Glass Rivers", "Low Country", "The Ninth Gate Road", "Saltmarsh", "Paper Kingdoms", "Night Ferry", "The Last Orchard Road"][(i + k) % 7]
    }

    static func corpus() -> BenchCorpus {
        var films: [BenchFilm] = []
        var pages: [String: BenchPage] = [:]
        var searches: [BenchSearch] = []
        for i in 0..<150 {
            let film = title(i)
            let slug = film.lowercased().replacingOccurrences(of: " ", with: "-")
            let year = 1970 + (i * 3) % 55
            let dp = name(i, 1), steadicam = name(i, 2), gaffer = name(i, 3), vfxSup = name(i, 4)
            let vfx = i % 5 == 0
            var crew: [(job: String, name: String)] = [("Director of Photography", dp), ("Gaffer", gaffer)]
            if i % 2 == 0 { crew.append(("Steadicam Operator", steadicam)) }
            if vfx { crew.append(("Visual Effects Supervisor", vfxSup)) }
            if i % 11 == 3 { crew.append(("Second Unit Director of Photography", name(i, 5))) }
            let camera = cameras[i % cameras.count], lens = lenses[i % lenses.count], light = lights[i % lights.count]
            let otherCamera = cameras[(i + 2) % cameras.count], otherLens = lenses[(i + 1) % lenses.count]
            let otherLight = lights[(i + 2) % lights.count]
            var firstPass: [String] = []
            var article: [String] = [], articleClaims: [BenchClaim] = []

            // Its Wikipedia article: a little on the shoot for most.
            if i % 6 != 5 {
                let s = "Principal photography on \(film) began in the spring of \(year), with \(dp) as cinematographer."
                article = ["\(film) is a \(year) drama directed by \(name(i, 0)).", s]
            }
            // A magazine article about the film (most films).
            if i % 5 != 4 {
                let url = "https://theasc.com/article/\(slug)-\(i)/"
                let capture = "\(film) was shot on the \(camera) with \(lens) lenses."
                let lit = "For the night exteriors, \(gaffer) rigged \(light) along the street."
                let reason = "\(dp) wanted the city to feel lived in rather than staged."
                var paragraphs = ["\(dp) photographed \(film) over eleven weeks.", capture + " " + lit, reason]
                var claims = [BenchClaim(text: capture, film: film, gear: [camera, lens]), BenchClaim(text: lit, film: film, gear: [light]),
                              BenchClaim(text: reason, film: film)]
                if i % 7 == 0 {
                    let estimate = "The practicals in the bar were probably around 300 watts, hidden behind the shelves."
                    paragraphs.append(estimate)
                    claims.append(BenchClaim(text: estimate, film: film))
                }
                if i % 9 == 0 {
                    let guess = "Some viewers think they may have used a Black Satin filter on the close-ups."
                    paragraphs.append(guess)
                    claims.append(BenchClaim(text: guess, film: film))
                }
                // Another production compared, in quotes as the magazine prints it.
                let compare = "Unlike on “\(other(i, 1))”, which \(dp) shot on the \(otherCamera), this film needed a lighter camera."
                paragraphs.append(compare)
                claims.append(BenchClaim(text: compare, film: other(i, 1)))
                pages[url] = BenchPage(title: "Lived-In Light: \(film)", url: url, site: "American Cinematographer",
                                       paragraphs: paragraphs, claims: claims)
                firstPass.append(url)
            } else if i % 10 == 9 {
                // An article whose title doesn't name the film, about it throughout.
                let url = "https://www.cineworkshop.example/a-conversation-about-night-\(i)/"
                let a = "\(film) opens on a long night drive, and \(dp) knew early on how it had to look."
                let b = "On \(film), \(dp) chose the \(camera) and a set of \(lens) lenses."
                let c = "In \(film), most of the light came from \(light) taped inside the cars."
                pages[url] = BenchPage(title: "A Conversation About Night", url: url, site: "The Film Stage",
                                       paragraphs: [a, b, c, "The shoot ran for nine weeks."],
                                       claims: [BenchClaim(text: a, film: film), BenchClaim(text: b, film: film, gear: [camera, lens]),
                                                BenchClaim(text: c, film: film, gear: [light])])
                firstPass.append(url)
            }

            // The cinematographer's membership news: a credits list and another production's gear.
            var dpHits: [(title: String, url: String)] = []
            if i % 3 == 0 {
                let url = "https://theasc.com/news/\(dp.lowercased().replacingOccurrences(of: " ", with: "-"))-joins-\(i)/"
                let welcome = "The Society has welcomed \(dp) into its active membership."
                let credits = "\(dp)'s credits include \(other(i, 2)), \(film), \(other(i, 3)) and \(other(i, 4))."
                let gear = "On \(other(i, 2)), \(dp) shot with the \(otherCamera) and \(otherLens) lenses."
                let career = "\(dp) began as a Steadicam operator on commercials."
                pages[url] = BenchPage(title: "\(dp) Joins the Society", url: url, site: "American Cinematographer",
                                       paragraphs: [welcome, credits + " " + gear, career],
                                       claims: [BenchClaim(text: welcome, film: ""), BenchClaim(text: credits, film: ""),
                                                BenchClaim(text: gear, film: other(i, 2)), BenchClaim(text: career, film: "")])
                dpHits.append(("\(dp) Joins the Society", url))
            }
            // An interview about several productions, with a paragraph about this one.
            if i % 4 == 1 {
                let url = "https://theasc.com/article/\(dp.lowercased().replacingOccurrences(of: " ", with: "-"))-light-and-movement-\(i)/"
                let a = "For “\(other(i, 5))”, we built everything around a Technocrane."
                let a2 = "It gave the whole film a floating feeling."
                let b = "On \(film), we lit the interiors with \(otherLight) and kept the camera on a dolly."
                let b2 = "We wanted the rooms to breathe."
                let c = "“\(other(i, 6))” was a different story: we shot it handheld on the \(otherCamera)."
                pages[url] = BenchPage(title: "\(dp) on Light and Movement", url: url, site: "American Cinematographer",
                                       paragraphs: ["\(dp) has shot features on three continents.", a + " " + a2, b + " " + b2, c],
                                       claims: [BenchClaim(text: a, film: other(i, 5)), BenchClaim(text: a2, film: other(i, 5)),
                                                BenchClaim(text: b, film: film, gear: [otherLight, "Dolly"]), BenchClaim(text: b2, film: film),
                                                BenchClaim(text: c, film: other(i, 6))])
                dpHits.append(("\(dp) on Light and Movement", url))
            }
            if !dpHits.isEmpty { searches.append(BenchSearch(provider: "American Cinematographer", query: dp, hits: dpHits)) }
            // The Steadicam operator, in their own words, on this film (some), or a provider that's down.
            if i % 2 == 0 {
                if i % 8 == 6 {
                    searches.append(BenchSearch(provider: "American Cinematographer", query: steadicam, hits: [], failure: "didn't answer: timed out (read again later)"))
                } else if i % 8 == 2 {
                    let url = "https://theasc.com/article/steadicam-\(slug)-\(i)/"
                    let quote = "“We ran the whole market scene in one take on the Steadicam,” \(steadicam.split(separator: " ").last!) says of \(film)."
                    pages[url] = BenchPage(title: "Running With \(film)", url: url, site: "American Cinematographer",
                                           paragraphs: ["\(steadicam) was the Steadicam operator on \(film).", quote, "The market took two nights."],
                                           claims: [BenchClaim(text: quote, film: film, gear: ["Steadicam"])])
                    searches.append(BenchSearch(provider: "American Cinematographer", query: steadicam, hits: [("Running With \(film)", url)]))
                }
            }
            // A VFX company's page about the film, and its year in review listing it among others.
            if vfx {
                let url = "https://cinesite.com/\(slug)-\(i)/"
                let witness = "Witness cameras recorded every take from the side so the tracking team could rebuild the set."
                let plates = "The background plates for \(film) were shot from a camera array on a truck."
                let review = "https://cinesite.com/our-year-\(i)/"
                let list = "This year we delivered shots for \(other(i, 1)), \(film), \(other(i, 2)) and \(other(i, 3))."
                let leak = "On \(other(i, 1)), every plate was shot with a motion-control rig."
                pages[url] = BenchPage(title: "\(film)", url: url, site: "Cinesite", paragraphs: ["\(film) needed crowds of thousands.", witness, plates],
                                       claims: [BenchClaim(text: witness, film: film), BenchClaim(text: plates, film: film)])
                pages[review] = BenchPage(title: "Our Year: \(film) and More", url: review, site: "Cinesite", paragraphs: [list, leak, "We opened a studio in Berlin."],
                                          claims: [BenchClaim(text: list, film: ""), BenchClaim(text: leak, film: other(i, 1))])
                searches.append(BenchSearch(provider: "Cinesite", query: film, hits: [(film, url), ("Our Year: \(film) and More", review)]))
            }
            films.append(BenchFilm(id: 800_000 + i, title: film, year: year, director: name(i, 0), crew: crew, article: article,
                                   articleClaims: articleClaims, firstPass: firstPass))
        }
        return BenchCorpus(name: "development", films: films, pages: pages, searches: searches)
    }
}
