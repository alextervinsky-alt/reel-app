@testable import ReelCore
import Foundation

// The research benchmark's blind holdout: 24 invented films, the pages a reading of them may meet,
// and the searches that lead there. Nothing here is real except the gear names, which are real
// products so the reader recognises them. Every sentence that says something about a production's
// cinematography is labelled with the production it concerns; paragraphs are assembled from the
// same segments as the labels, so each claim's text is a verbatim substring of its paragraph.
enum HoldoutCorpus {
    static func corpus() -> BenchCorpus {
        var b = Builder()
        addHollowBayAndCopperRain(&b)
        addGorseAndKiln(&b)
        addCartographyAndHarbour(&b)
        addOssaAndAntlers(&b)
        addTides(&b)
        addNineBellsAndNinthLock(&b)
        addGlassRepublicAndWolves(&b)
        addCalderStreet(&b)
        addMarrowLineAndOrchardist(&b)
        addSaints(&b)
        addWeatherglass(&b)
        addGlovemakerAndBallad(&b)
        addJuniperPass(&b)
        addQuietLedgerAndUndertow(&b)
        addLowlightPsalms(&b)
        return BenchCorpus(name: "holdout", films: b.films.sorted { $0.id < $1.id },
                           pages: b.pages, searches: b.searches())
    }

    // MARK: - Titles

    private static let hollowBay = "The Lantern Keepers of Hollow Bay"
    private static let copperRain = "Copper Rain Season"
    private static let gorse = "Gorse"
    private static let cartography = "A Cartography of Small Fires"
    private static let ossa = "Ossa"
    private static let tides = "The Unhurried Arithmetic of Tides"
    private static let kiln = "Kiln"
    private static let nineBells = "Nine Bells for the Drowned Orchard"
    private static let glassRepublic = "Halfway to the Glass Republic"
    private static let calder = "Every Window on Calder Street"
    private static let marrow = "The Marrow Line"
    private static let saints = "Saints of the Low Meridian"
    private static let weatherglass = "A Season Under Weatherglass"
    private static let glovemaker = "The Glovemaker's Last Winter"
    private static let juniper = "Static Over Juniper Pass"
    private static let wolves = "Wolves in the Choir Loft"
    private static let ninthLock = "Daughters of the Ninth Lock"
    private static let quietLedger = "The Quiet Ledger"
    private static let ballad = "Ballad of the Furnace Children"
    private static let psalms = "Lowlight Psalms"
    private static let harbour = "Harbour of the Patient Machines"
    private static let antlers = "Antlers Above the Salt Road"
    private static let orchardist = "The Orchardist's Second Wife"
    private static let undertow = "Undertow Hymnal"

    // MARK: - Gear (real names, written exactly)

    private static let mini = "ARRI Alexa Mini"
    private static let alexa65 = "ARRI Alexa 65"
    private static let venice = "Sony Venice"
    private static let monstro = "RED Monstro"
    private static let dxl = "Panavision Millennium DXL"
    private static let arricam = "Arricam LT"
    private static let cooke = "Cooke S4"
    private static let primo = "Panavision Primo"
    private static let supreme = "Zeiss Supreme Prime"
    private static let summilux = "Leica Summilux-C"
    private static let skyPanels = "SkyPanels"
    private static let kinoFlos = "Kino Flos"
    private static let astera = "Astera tubes"
    private static let vortex = "Creamsource Vortex8"
    private static let steadicam = "Steadicam"
    private static let technocrane = "Technocrane"
    private static let dolly = "dolly"
    private static let vision3 = "Kodak Vision3 500T"

    // MARK: - Sites

    private static let ac = "American Cinematographer"
    private static let cinesite = "Cinesite"
    private static let lensAndLight = "Lens & Light Review"
    private static let workshop = "Cine Workshop"
    private static let frameNotes = "Frame Notes Quarterly"

    // MARK: - Building blocks

    /// A piece of a paragraph: filler, or a labelled statement.
    private enum Seg {
        case text(String)
        case claim(BenchClaim)
    }

    private static func t(_ s: String) -> Seg { .text(s) }

    private static func c(_ s: String, _ film: String, _ gear: String...) -> Seg {
        .claim(BenchClaim(text: s, film: film, gear: gear))
    }

    private static func assemble(_ paragraphs: [[Seg]]) -> (paragraphs: [String], claims: [BenchClaim]) {
        var texts: [String] = []
        var claims: [BenchClaim] = []
        for paragraph in paragraphs {
            var parts: [String] = []
            for seg in paragraph {
                switch seg {
                case .text(let s):
                    parts.append(s)
                case .claim(let claim):
                    parts.append(claim.text)
                    claims.append(claim)
                }
            }
            texts.append(parts.joined(separator: " "))
        }
        return (texts, claims)
    }

    private struct Builder {
        var films: [BenchFilm] = []
        var pages: [String: BenchPage] = [:]
        var queries: [(provider: String, query: String, urls: [String], failure: String?)] = []

        mutating func page(_ title: String, _ url: String, _ site: String, _ paragraphs: [[Seg]],
                           failure: SourceFailure? = nil) {
            let built = HoldoutCorpus.assemble(paragraphs)
            precondition(pages[url] == nil, "duplicate page \(url)")
            pages[url] = BenchPage(title: title, url: url, site: site, paragraphs: built.paragraphs,
                                   claims: built.claims, failure: failure)
        }

        mutating func film(_ id: Int, _ title: String, _ year: Int, director: String,
                           crew: [(job: String, name: String)], article: [[Seg]] = [],
                           firstPass: [String] = []) {
            let built = HoldoutCorpus.assemble(article)
            films.append(BenchFilm(id: id, title: title, year: year, director: director, crew: crew,
                                   article: built.paragraphs, articleClaims: built.claims,
                                   firstPass: firstPass))
        }

        /// An American Cinematographer search by a crew member's name.
        mutating func ac(_ name: String, _ urls: String...) {
            queries.append((HoldoutCorpus.ac, name, urls, nil))
        }

        /// A Cinesite search by the film's title.
        mutating func cinesite(_ title: String, _ urls: String..., failure: String? = nil) {
            queries.append((HoldoutCorpus.cinesite, title, urls, failure))
        }

        func searches() -> [BenchSearch] {
            queries.map { q in
                let hits: [(title: String, url: String)] = q.urls.map { url in
                    (title: pages[url]?.title ?? url, url: url)
                }
                return BenchSearch(provider: q.provider, query: q.query, hits: hits, failure: q.failure)
            }
        }
    }

    // MARK: - 910001 The Lantern Keepers of Hollow Bay, 910002 Copper Rain Season

    private static func addHollowBayAndCopperRain(_ b: inout Builder) {
        let hbArticle = "https://theasc.com/articles/keeping-the-light-hollow-bay"
        let callowayProfile = "https://theasc.com/members/idris-calloway"
        let callowayInterview = "https://theasc.com/articles/calloway-in-conversation"
        let roundtable = "https://theasc.com/articles/gaffers-roundtable"
        let copperWorkshop = "https://www.cineworkshop.example/notes/copper-rain-season"

        b.page("Keeping the Light: The Lantern Keepers of Hollow Bay", hbArticle, ac, [
            [t("Director Marta Venholt wanted the island of Hollow Bay to feel like a third sister, stubborn and weathered."),
             t("She found her cinematographer in Idris Calloway, whom she had met at a festival in Gothenburg.")],
            [c("For \(hollowBay), Calloway paired the Sony Venice with a set of Cooke S4 lenses.", hollowBay, venice, cooke),
             c("\"The Cookes gave the faces a softness that suited the sisters,\" he says.", hollowBay, cooke)],
            [c("The lighthouse interiors were lit almost entirely with SkyPanels bounced off the whitewashed walls.", hollowBay, skyPanels),
             c("Gaffer Bram Okonkwo rigged a ring of Astera tubes inside the lamp room to mimic the rotating beam.", hollowBay, astera)],
            [c("The sweeping cliff-top openings were achieved with a Technocrane mounted on a flatbed truck.", hollowBay, technocrane),
             c("Steadicam operator Juno Petrakis carried the camera up the lighthouse's 140 steps in a single take.", hollowBay, steadicam)],
            [c("Colorist Selin Arkadi built a print-film emulation for the grade, keeping the greens muted and the skin warm.", hollowBay),
             t("The film premiered at Haugesund and opened in cinemas the following spring.")],
        ])

        b.page("Idris Calloway, ASC", callowayProfile, ac, [
            [t("Idris Calloway was born in Cardiff and studied painting before moving into camera departments in the late 1990s."),
             t("He became an active member of the Society in 2016.")],
            [c("Selected credits: Brightwater Kids (2010), Copper Rain Season (2014), The Lantern Keepers of Hollow Bay (2019), Salt Meridian (2022).", "")],
            [c("On Salt Meridian he moved to the ARRI Alexa 65 and a set of Panavision Primo lenses for the desert sequences.", "Salt Meridian", alexa65, primo),
             c("He has described the large-format sensor as a revelation for wide landscapes.", "Salt Meridian")],
            [c("For Brightwater Kids, his first feature, he carried a single dolly and two Kino Flos from location to location.", "Brightwater Kids", dolly, kinoFlos)],
            [c("Calloway is known for lighting with practicals wherever he can and has said he dislikes \"lighting for the lens instead of the room.\"", "")],
        ])

        b.page("In Conversation: Idris Calloway on Rain, Light and Distance", callowayInterview, ac, [
            [t("Idris Calloway has photographed features for very different directors."),
             t("We spoke to him about two of them, and about the one he is shooting now.")],
            [c("Copper Rain Season was the last feature Calloway shot on film, using the Arricam LT and Kodak Vision3 500T.", copperRain, arricam, vision3),
             c("\"We pushed the stock a stop for the night exteriors and it held beautifully,\" he recalls.", copperRain),
             c("We lit it with Kino Flos and a lot of rain towers.", copperRain, kinoFlos)],
            [c("Five years later, on The Lantern Keepers of Hollow Bay, he was working digitally for the first time.", hollowBay),
             c("\"The Venice let us shoot the dusk scenes with nothing but the lighthouse lamp,\" Calloway says.", hollowBay, venice),
             c("We lit it with SkyPanels on dimmers so the sisters' faces could breathe with the beam.", hollowBay, skyPanels)],
            [c("His current project, Salt Meridian, is being shot in Namibia.", "Salt Meridian"),
             c("We're carrying the ARRI Alexa 65 and a Technocrane across the dunes, which is a story in itself.", "Salt Meridian", alexa65, technocrane),
             t("He laughs when asked whether he misses the rain.")],
        ])

        b.page("Gaffers' Roundtable: Three Electricians on the Shows That Shaped Them", roundtable, ac, [
            [t("We asked three gaffers to pick one production that taught them something they still use.")],
            [t("Delphine Marsh spent most of Copper Rain Season soaking wet."),
             c("On Copper Rain Season she built the night-market look from strings of practical bulbs supplemented by Kino Flos hidden behind stall awnings.", copperRain, kinoFlos),
             c("The biggest unit on that set was probably around 300 watts, she estimates, and the rest was tungsten practicals.", copperRain)],
            [t("Kwame Desrosiers looks back further, to Saints of the Low Meridian."),
             c("That film's church interiors were lit through the windows with big HMIs, with Kino Flos as a soft fill inside.", saints, kinoFlos),
             c("\"We kept almost nothing on the floor so the dolly could go anywhere,\" he says.", saints, dolly)],
            [c("Agnieszka Wróbel-Hale, meanwhile, swears by Creamsource Vortex8 units for daylight work and used a wall of them on Brightwater Kids.", "Brightwater Kids", vortex)],
            [c("All three agree that LED has changed the job more than any camera ever did.", "")],
        ])

        b.page("Workshop notes: Copper Rain Season", copperWorkshop, workshop, [
            [t("This month's workshop screened Copper Rain Season and pulled apart three of its scenes."),
             c("The film was photographed by Idris Calloway with Panavision Primo lenses, which explains the clean, almost clinical edges on the night exteriors.", copperRain, primo)],
            [c("In the funeral scene, a slow dolly push holds on the widow for nearly a minute.", copperRain, dolly),
             c("Calloway probably used a Steadicam for the market sequence, though nobody we spoke to could confirm it.", copperRain)],
            [t("Participants were asked to light a similar scene with a single source."),
             c("Most chose a Kino Flo bank; one brave group tried a bare bulb.", "")],
        ])

        b.film(910001, hollowBay, 2019, director: "Marta Venholt", crew: [
            ("Director of Photography", "Idris Calloway"),
            ("Steadicam Operator", "Juno Petrakis"),
            ("Gaffer", "Bram Okonkwo"),
            ("Colorist", "Selin Arkadi"),
        ], article: [
            [t("\(hollowBay) is a 2019 drama film directed by Marta Venholt."),
             t("It follows two sisters who keep a decommissioned lighthouse running on a remote island.")],
            [c("Principal photography took place over seven weeks in the autumn of 2018, with Idris Calloway as cinematographer.", hollowBay),
             c("\(hollowBay) was shot on the Sony Venice, which Calloway chose for its low-light sensitivity.", hollowBay, venice)],
            [t("The film received four nominations at the national film awards, winning for best actress.")],
        ], firstPass: [hbArticle])

        b.film(910002, copperRain, 2014, director: "Anselm Fryer", crew: [
            ("Director of Photography", "Idris Calloway"),
            ("Gaffer", "Delphine Marsh"),
            ("Camera Operator", "Ruben Achebe-Lowe"),
        ], article: [
            [t("\(copperRain) is a 2014 crime drama directed by Anselm Fryer, set during a monsoon in a port city."),
             c("\(copperRain) was photographed on 35mm film by Idris Calloway.", copperRain)],
            [t("It was released to mixed reviews but has since gained a following.")],
        ], firstPass: [copperWorkshop])

        b.ac("Idris Calloway", callowayProfile, callowayInterview)
        b.ac("Juno Petrakis", "https://theasc.com/members/juno-petrakis-soc", hbArticle)
        b.ac("Bram Okonkwo", hbArticle, "https://theasc.com/articles/practical-magic")
        b.ac("Selin Arkadi", "https://theasc.com/articles/arkadi-grading-in-the-dark")
        b.ac("Delphine Marsh", roundtable)
        b.ac("Ruben Achebe-Lowe")
        b.cinesite(hollowBay)
    }

    // MARK: - 910003 Gorse, 910007 Kiln

    private static func addGorseAndKiln(_ b: inout Builder) {
        let obituary = "https://theasc.com/news/in-memoriam-osgood-pellerin"
        let members = "https://theasc.com/news/new-members-spring-intake"
        let kilnLane = "https://www.cinesite.com/news/kiln-lane-stage-opens"

        b.page("In Memoriam: Osgood Pellerin (1931–2021)", obituary, ac, [
            [t("Osgood Pellerin, who died in March at the age of 89, was one of the quiet craftsmen of European cinema."),
             t("He began as a newsreel cameraman and never lost the habit of working fast.")],
            [c("His credits included Gorse (1978), The Brass Orchard (1984) and dozens of commercials.", "")],
            [c("On Gorse he shot almost entirely by available light on the moors, a decision he later attributed to a budget that could not stretch to a generator.", gorse),
             c("He is said to have used a dolly built from a hospital trolley, though that may be legend.", gorse)],
            [c("In his last years he taught at the national film school, where he championed Kodak Vision3 500T to students who wanted to keep shooting film.", "")],
            [t("He is survived by his wife, two daughters and a grandson who is now a camera assistant.")],
        ])

        b.page("New Members: Spring Intake", members, ac, [
            [t("The Society welcomes four new members this spring, from four countries.")],
            [c("Tomasz Oberle, whose recent work includes the series Gilded Static, shot that show on the RED Monstro.", "Gilded Static", monstro)],
            [t("Philippa Groenewald began her career in Johannesburg as a stills photographer."),
             c("Her first feature, Kiln, was made with a three-person camera crew and a borrowed dolly.", kiln, dolly),
             t("The title refers to the brick kiln at the centre of the story, which the crew rebuilt in a disused quarry."),
             c("She has photographed eleven features since, most recently on the ARRI Alexa Mini.", "")],
            [t("Bios of the remaining members will appear in next month's issue.")],
        ])

        b.page("Cinesite opens its Kiln Lane stage", kilnLane, cinesite, [
            [t("Cinesite has opened a new virtual production stage on Kiln Lane, a short walk from its existing studio.")],
            [c("The new stage at Kiln Lane is lit by an overhead grid of SkyPanels that can be driven from the LED wall's content.", ""),
             t("It is available to productions from next quarter.")],
        ])

        b.film(910003, gorse, 1978, director: "Halvard Brekke", crew: [
            ("Director of Photography", "Osgood Pellerin"),
        ], article: [
            [t("\(gorse) is a 1978 drama film directed by Halvard Brekke."),
             c("It was photographed in black and white by Osgood Pellerin.", gorse),
             t("The original cut is considered lost; a shortened television version survives.")],
        ])

        b.film(910007, kiln, 1989, director: "Evander Mott", crew: [
            ("Director of Photography", "Philippa Groenewald"),
        ], article: [
            [t("\(kiln) is a 1989 South African drama film directed by Evander Mott about a family of brickmakers.")],
        ])

        b.ac("Osgood Pellerin", obituary)
        b.ac("Philippa Groenewald", members)
        b.cinesite(kiln, kilnLane)
    }

    // MARK: - 910004 A Cartography of Small Fires, 910021 Harbour of the Patient Machines

    private static func addCartographyAndHarbour(_ b: inout Builder) {
        let cartoCinesite = "https://www.cinesite.com/projects/a-cartography-of-small-fires"
        let harbourCinesite = "https://www.cinesite.com/projects/harbour-of-the-patient-machines"
        let clients = "https://www.cinesite.com/about/our-work"
        let fireAndPaper = "https://theasc.com/articles/fire-and-paper"
        let oyelaranProfile = "https://theasc.com/members/tamsin-oyelaran"
        let dudaInterview = "https://theasc.com/articles/kasimir-duda-walking-the-line"

        b.page("A Cartography of Small Fires | Cinesite", cartoCinesite, cinesite, [
            [t("Cinesite delivered 214 shots for Noor Haddani's \(cartography), led by visual effects supervisor Lior Bendavid.")],
            [c("For the wildfire sequences, the production placed tracking markers on fire-retardant poles across the hillside so every camera move could be matched in post.", cartography),
             c("Two witness cameras ran alongside the main unit's ARRI Alexa Mini on every fire shot to record the scene from the side.", cartography, mini),
             c("Background plates for the car interiors were captured with a nine-camera array of RED Monstro bodies rigged on a tracking vehicle.", cartography, monstro)],
            [c("Bendavid's team also shot clean plates on a dolly after each take so the smoke could be rebuilt digitally.", cartography, dolly)],
            [t("The fire simulations were rendered on Cinesite's Montreal farm over eleven weeks.")],
        ])

        b.page("Harbour of the Patient Machines | Cinesite", harbourCinesite, cinesite, [
            [t("Cinesite created the robotic dockworkers of Yvette Lanoix's \(harbour), from design to final render.")],
            [c("Because the film was shot on 35mm, the team scanned every plate at 4K and tracked it against survey data from the real harbour.", harbour),
             c("Reference passes were shot with a Technocrane repeating the main camera's move with the robots' stand-ins removed.", harbour, technocrane),
             c("Small witness cameras were bolted to the crane's base to record the stand-ins from the side.", harbour)],
            [c("Lior Bendavid supervised a camera array of twelve stills cameras that photographed the actors for their digital doubles.", harbour)],
        ])

        b.page("Our Work | Cinesite", clients, cinesite, [
            [t("For more than three decades Cinesite has partnered with filmmakers on features, series and animation.")],
            [t("Recent projects include \(cartography), \(juniper) and \(harbour), alongside a dozen episodic series.")],
            [c("Our new virtual production stage is lit with Creamsource Vortex8 fixtures and a ceiling of LED tiles.", ""),
             t("Contact our bidding team to discuss your next project.")],
        ])

        b.page("Fire and Paper", fireAndPaper, ac, [
            [c("\(cartography) was the hardest film Tamsin Oyelaran has ever lit, she says, because the fire kept changing its mind.", cartography)],
            [c("For \(cartography) she chose Leica Summilux-C lenses, wide open, so the smoke would bloom around the actors.", cartography, summilux),
             c("The night exteriors were lit with Astera tubes on poles that grips could walk alongside the flames.", cartography, astera)],
            [c("Kasimir Duda's Steadicam followed the firefighters into the burning orchard in two continuous takes.", cartography, steadicam)],
            [c("Oyelaran may have used a Technocrane for the final pull-out, but she would only say that \"something tall\" was involved.", cartography)],
            [c("Ines Marchetti graded the film to keep the flames from clipping to white.", cartography)],
        ])

        b.page("Tamsin Oyelaran, BSC", oyelaranProfile, ac, [
            [t("Tamsin Oyelaran grew up in Lagos and London and trained at the National Film and Television School.")],
            [c("Oyelaran's features include Harbour of the Patient Machines (2013) and A Cartography of Small Fires (2023).", "")],
            [c("Between them she shot the series Gannet Rock on the RED Monstro.", "Gannet Rock", monstro),
             c("She has lectured on Panavision Primo lenses at the national school.", "")],
        ])

        b.page("Kasimir Duda: Walking the Line", dudaInterview, ac, [
            [t("Kasimir Duda has been flying cameras for twenty years and has the knees to prove it.")],
            [c("Duda's first big feature was Daughters of the Ninth Lock, where he spent a week walking the towpath backwards with the Steadicam and an Arricam LT.", ninthLock, steadicam, arricam),
             c("The camera was heavy, probably around 25 kilos with the magazine loaded.", ninthLock)],
            [c("On A Cartography of Small Fires, fourteen years later, the rig had shrunk to an ARRI Alexa Mini.", cartography, mini),
             c("I walked into the smoke with it and Tamsin lit the edges with Astera tubes on poles.", cartography, astera),
             c("We used the Steadicam for almost every fire shot.", cartography, steadicam)],
            [c("He now teaches a weekend course for operators who want to move from gimbals to a full rig.", "")],
        ])

        b.film(910004, cartography, 2023, director: "Noor Haddani", crew: [
            ("Director of Photography", "Tamsin Oyelaran"),
            ("Steadicam Operator", "Kasimir Duda"),
            ("Visual Effects Supervisor", "Lior Bendavid"),
            ("Colorist", "Ines Marchetti"),
        ], article: [
            [t("\(cartography) is a 2023 drama film written and directed by Noor Haddani, about a volunteer fire crew in the hills above Marseille.")],
            [c("\(cartography) was shot on the ARRI Alexa Mini with Leica Summilux-C lenses.", cartography, mini, summilux),
             t("Real controlled burns were staged with the regional fire service.")],
        ])

        b.film(910021, harbour, 2013, director: "Yvette Lanoix", crew: [
            ("Director of Photography", "Tamsin Oyelaran"),
            ("Visual Effects Supervisor", "Lior Bendavid"),
        ], article: [
            [t("\(harbour) is a 2013 science-fiction film directed by Yvette Lanoix.")],
            [c("\(harbour) was shot on the Arricam LT using Kodak Vision3 500T, in the docks of Le Havre.", harbour, arricam, vision3)],
        ])

        b.ac("Tamsin Oyelaran", oyelaranProfile, fireAndPaper)
        b.ac("Kasimir Duda", dudaInterview, fireAndPaper)
        b.ac("Lior Bendavid")
        b.ac("Ines Marchetti", fireAndPaper)
        b.cinesite(cartography, cartoCinesite, clients)
        b.cinesite(harbour, harbourCinesite, clients)
    }

    // MARK: - 910005 Ossa, 910022 Antlers Above the Salt Road

    private static func addOssaAndAntlers(_ b: inout Builder) {
        let spanish = "https://www.cinesite.com/es/proyectos/ossa"
        let antczak = "https://theasc.com/members/rafe-antczak"
        let vantor = "https://www.vantor-optics.example/stories/salt-road"

        b.page("Ossa: la fotografía de las catacumbas", spanish, cinesite, [
            [c("Ossa se rodó con una Arricam LT en las catacumbas de Lisboa.", ossa, arricam),
             t("El equipo de Cinesite añadió más de cien planos de extensión digital.")],
            [c("La iluminación se resolvió casi por completo con Kino Flos escondidos entre los huesos.", ossa, kinoFlos)],
        ], failure: .language("Spanish"))

        b.page("Rafe Antczak", antczak, ac, [
            [c("Rafe Antczak's credits include Ossa (2008), Antlers Above the Salt Road (2010) and Lowland Cantata (2020).", "")],
            [c("Lowland Cantata, his first digital feature, was shot on the Panavision Millennium DXL with Panavision Primo lenses.", "Lowland Cantata", dxl, primo)],
            [c("He shot Antlers Above the Salt Road with a single dolly and a long track laid along the salt road itself.", antlers, dolly)],
            [c("Antczak has said he probably owes his career to Ossa's catacomb scenes, which he lit with nothing but Kino Flos and candles.", ossa, kinoFlos)],
            [t("He lives in Gdańsk and still develops his own stills.")],
        ])

        b.page("On the road with Vantor", vantor, "Vantor Optics", [
            [t("Vantor Optics was founded in 2004 to make lens accessories for working camera crews.")],
            [c("Our team visited the set of Antlers Above the Salt Road to show the crew our new matte boxes.", antlers),
             t("It was a cold week, and the coffee was terrible.")],
            [c("Vantor follow-focus gears fit Cooke S4 and Panavision Primo lenses alike.", ""),
             t("Order through any of our dealers.")],
        ])

        b.film(910005, ossa, 2008, director: "Teodora Vasquez-Lind", crew: [
            ("Director of Photography", "Rafe Antczak"),
            ("Colorist", "Ines Marchetti"),
        ], article: [
            [t("\(ossa) is a 2008 Portuguese-Polish horror film directed by Teodora Vasquez-Lind.")],
            [c("\(ossa) was shot on the Arricam LT using Kodak Vision3 500T, much of it in the catacombs beneath Lisbon.", ossa, arricam, vision3)],
        ])

        b.film(910022, antlers, 2010, director: "Grete Holmqvist", crew: [
            ("Director of Photography", "Rafe Antczak"),
        ], article: [
            [t("\(antlers) is a 2010 Swedish western directed by Grete Holmqvist."),
             c("\(antlers) was shot on the Arricam LT with Cooke S4 lenses on the salt flats of northern Chile.", antlers, arricam, cooke)],
        ], firstPass: [vantor])

        b.ac("Rafe Antczak", antczak)
        b.cinesite(ossa, spanish)
    }

    // MARK: - 910006 The Unhurried Arithmetic of Tides

    private static func addTides(_ b: inout Builder) {
        let saltFlats = "https://www.lensandlight-review.example/notes-from-the-salt-flats"
        let twoCoasts = "https://theasc.com/articles/daskalova-two-coasts"

        b.page("Notes from the Salt Flats", saltFlats, lensAndLight, [
            [c("\(tides) opens on a tidal flat at dawn, and Mireille Daskalova photographed that opening with a single ARRI Alexa Mini on a slider.", tides, mini)],
            [c("Throughout \(tides) she favoured Leica Summilux-C lenses, wide open, for their gentle fall-off.", tides, summilux),
             t("The effect is of a film that never quite comes into focus, which is the point.")],
            [c("Gaffer Tobias Ferreira-Holm lit the caravan interiors with Astera tubes taped into the ceiling.", tides, astera),
             c("The practical lamp by the bed was probably around 300 watts, he guesses, though nobody metered it.", tides)],
            [c("For the beach chase in Tides, Anouk Lerberghe operated Steadicam from the back of a quad bike.", tides, steadicam)],
            [c("Daskalova says she would like to shoot her next film on the Sony Venice, which she has tested but never used on a feature.", "")],
        ])

        b.page("Two Coasts: Mireille Daskalova", twoCoasts, ac, [
            [t("Mireille Daskalova has made two features, both on coastlines, a decade apart in feeling if not in years.")],
            [c("Harrow Point, her 2018 debut, was shot on the RED Monstro with Zeiss Supreme Prime lenses.", "Harrow Point", monstro, supreme),
             c("We lit it with Creamsource Vortex8s through the windows because we never had permission to rig inside.", "Harrow Point", vortex)],
            [c("By The Unhurried Arithmetic of Tides she had switched to the ARRI Alexa Mini.", tides, mini),
             c("We lit it with almost nothing: Astera tubes in the caravan and the sky outside.", tides, astera),
             c("She thinks the production may have rented a Technocrane for a day, but she cannot remember using it.", tides)],
        ])

        b.film(910006, tides, 2021, director: "Corwin Ashby", crew: [
            ("Director of Photography", "Mireille Daskalova"),
            ("Gaffer", "Tobias Ferreira-Holm"),
            ("Steadicam Operator", "Anouk Lerberghe"),
        ], article: [
            [t("\(tides) is a 2021 Dutch-Belgian drama film directed by Corwin Ashby."),
             c("Cinematographer Mireille Daskalova shot the film on the Wadden Sea coast over five weeks.", tides)],
        ], firstPass: [saltFlats])

        b.ac("Mireille Daskalova", twoCoasts)
        b.ac("Tobias Ferreira-Holm")
    }

    // MARK: - 910008 Nine Bells for the Drowned Orchard, 910017 Daughters of the Ninth Lock

    private static func addNineBellsAndNinthLock(_ b: inout Builder) {
        let nineArticle = "https://theasc.com/articles/underwater-light-nine-bells"
        let award = "https://theasc.com/news/benedetti-board-of-governors-award"
        let craneNotes = "https://www.cineworkshop.example/notes/cranes-in-confined-spaces"

        b.page("Underwater Light: Nine Bells for the Drowned Orchard", nineArticle, ac, [
            [t("Sabine Okafor-Lund's fable takes place in an orchard that a reservoir slowly swallows.")],
            [c("Yusuf Benedetti chose the Panavision Millennium DXL for \(nineBells) because its large sensor held detail in the murky water.", nineBells, dxl),
             c("He paired it with Panavision Primo lenses, which he has used since film school.", nineBells, primo)],
            [c("The second unit, led by Hallie Mercado, shot the aerial orchard plates on the RED Monstro mounted under a helicopter.", nineBells, monstro),
             c("Mercado's unit also handled the underwater inserts, using a dolly track laid on the lake bed.", nineBells, dolly)],
            [c("Camera operator Dov Rautio rode a Technocrane over the flooded rows for the film's final shot.", nineBells, technocrane)],
            [c("Benedetti thinks the main unit may have used Kino Flos for the barn scenes, but the gaffer's records were lost.", nineBells)],
        ])

        b.page("Yusuf Benedetti to receive the Board of Governors Award", award, ac, [
            [t("The Society will honour Yusuf Benedetti at its annual awards in February.")],
            [c("Benedetti's features include The Fennel Sisters (1999), Daughters of the Ninth Lock (2009) and Nine Bells for the Drowned Orchard (2018).", "")],
            [c("His breakthrough, The Fennel Sisters, was shot on the Arricam LT with Cooke S4 lenses.", "The Fennel Sisters", arricam, cooke),
             c("On Daughters of the Ninth Lock he famously used a Technocrane inside a working canal lock.", ninthLock, technocrane)],
            [c("\"I have never owned a light meter I trusted,\" he told the committee.", "")],
        ])

        b.page("Workshop notes: cranes in confined spaces", craneNotes, workshop, [
            [t("Telescopic cranes are usually associated with wide open landscapes, but some of their best work happens in tight quarters.")],
            [c("The best-known example is Daughters of the Ninth Lock, where a Technocrane was lowered into a drained canal lock.", ninthLock, technocrane)],
            [c("A Technocrane needs at least a metre and a half of clearance on each side of the base.", ""),
             t("Plan the move with the key grip before the location is locked.")],
        ])

        b.film(910008, nineBells, 2018, director: "Sabine Okafor-Lund", crew: [
            ("Director of Photography", "Yusuf Benedetti"),
            ("Second Unit Director of Photography", "Hallie Mercado"),
            ("Camera Operator", "Dov Rautio"),
        ], article: [
            [t("\(nineBells) is a 2018 fantasy drama directed by Sabine Okafor-Lund.")],
            [c("\(nineBells) was shot by Yusuf Benedetti on the Panavision Millennium DXL with Panavision Primo lenses.", nineBells, dxl, primo),
             c("A second unit under Hallie Mercado filmed the flooded orchard from the air.", nineBells)],
        ], firstPass: [nineArticle])

        b.film(910017, ninthLock, 2009, director: "Imre Kovalenko", crew: [
            ("Director of Photography", "Yusuf Benedetti"),
            ("Steadicam Operator", "Kasimir Duda"),
        ], article: [
            [t("\(ninthLock) is a 2009 Hungarian thriller directed by Imre Kovalenko, set on a canal barge.")],
            [c("\(ninthLock) was shot on the Arricam LT with Kodak Vision3 500T and Panavision Primo lenses.", ninthLock, arricam, vision3, primo)],
        ], firstPass: [craneNotes])

        b.ac("Yusuf Benedetti", award, nineArticle)
        b.ac("Hallie Mercado", nineArticle)
        b.ac("Dov Rautio", nineArticle, "https://theasc.com/articles/abernethy-ledgers-and-hymns")
    }

    // MARK: - 910009 Halfway to the Glass Republic, 910016 Wolves in the Choir Loft

    private static func addGlassRepublicAndWolves(_ b: inout Builder) {
        let lumenforge = "https://www.lumenforge-lighting.example/news/premiere-partnership"
        let ilunga = "https://theasc.com/articles/ilunga-three-films"
        let organPipes = "https://www.cineworkshop.example/case-studies/between-the-organ-pipes"

        b.page("Lumenforge at the premiere of Halfway to the Glass Republic", lumenforge, "Lumenforge Lighting", [
            [t("Lumenforge was proud to sponsor the premiere of \(glassRepublic) at the Kesselhaus cinema.")],
            [c("Our new Lumen 9 panels are a direct competitor to SkyPanels, offering higher output at the same weight.", "")],
            [c("Guests were invited to see the same kind of fixtures that light productions like \(glassRepublic).", glassRepublic),
             t("A prize draw gave away two fixtures to film students.")],
        ])

        b.page("Constance Ilunga: Three Films, Three Cameras", ilunga, ac, [
            [t("Constance Ilunga has a habit of changing format with every film. We asked her why.")],
            [c("On \(glassRepublic), Ilunga shot on the Arricam LT with Panavision Primo lenses.", glassRepublic, arricam, primo),
             c("We lit it with Kino Flos and whatever the location gave us.", glassRepublic, kinoFlos),
             c("Mateus Varga, her gaffer, put everything on dimmers so a single operator could run the board.", glassRepublic)],
            [c("Six years later, Wolves in the Choir Loft took her into the digital world.", wolves),
             c("That film was shot on the ARRI Alexa Mini, often handheld in the cramped loft.", wolves, mini),
             c("She paired it with Leica Summilux-C lenses because they were small enough to fit between the organ pipes.", wolves, summilux),
             c("We lit it with Astera tubes hidden inside the pews.", wolves, astera)],
            [c("Her newest, Paper Comet, is a different beast: a Sony Venice on a Technocrane for most of the shoot.", "Paper Comet", venice, technocrane),
             c("We lit it with SkyPanels in a huge soft box over the stage.", "Paper Comet", skyPanels)],
        ])

        b.page("Between the Organ Pipes", organPipes, workshop, [
            [c("\(wolves) is a film made almost entirely in one room, and Constance Ilunga's camera had to find variety in it.", wolves)],
            [c("The production used two ARRI Alexa Mini bodies so that the choir could be covered from both ends of the loft at once.", wolves, mini)],
            [c("A dolly was out of the question on the loft's uneven floorboards, so every move in \(wolves) is handheld or on a slider.", wolves)],
            [c("Teo Marangoni graded \(wolves) with a sickly green bias that grows through the film.", wolves)],
            [c("Unlike on \(glassRepublic), which Ilunga shot on the Arricam LT, there was no film stock to fight here.", wolves)],
        ])

        b.film(910009, glassRepublic, 2011, director: "Leopold Szabo", crew: [
            ("Director of Photography", "Constance Ilunga"),
            ("Gaffer", "Mateus Varga"),
        ], article: [
            [t("\(glassRepublic) is a 2011 German comedy-drama directed by Leopold Szabo."),
             c("\(glassRepublic) was shot on the Arricam LT, one of the last features in the region to use film.", glassRepublic, arricam)],
        ], firstPass: [lumenforge])

        b.film(910016, wolves, 2017, director: "Benedikt Arnaud", crew: [
            ("Director of Photography", "Constance Ilunga"),
            ("Colorist", "Teo Marangoni"),
        ], article: [
            [t("\(wolves) is a 2017 Belgian psychological thriller directed by Benedikt Arnaud."),
             t("It was filmed inside a deconsecrated church in Ghent over twenty-two days.")],
        ], firstPass: [organPipes])

        b.ac("Constance Ilunga", ilunga)
        b.ac("Mateus Varga", ilunga)
    }

    // MARK: - 910010 Every Window on Calder Street

    private static func addCalderStreet(_ b: inout Builder) {
        let diary = "https://www.framenotes.example/issues/41/calder-street"
        let operatorDiaries = "https://theasc.com/articles/operator-diaries-rosa-tkachenko"

        b.page("Every Window on Calder Street: a camera diary", diary, frameNotes, [
            [c("Gideon Hartwell shot \(calder) on the Sony Venice in its Rialto configuration so the camera could slip through apartment windows.", calder, venice)],
            [c("Rosa Tkachenko's Steadicam work carries the film's long opening, which drifts from flat to flat along the street.", calder, steadicam),
             c("The exteriors at night were lit with Creamsource Vortex8 units on cherry pickers.", calder, vortex)],
            [c("\"Unlike on Bramble Hours, which we shot on the ARRI Alexa 65, we wanted a camera we could hide in a kitchen cupboard,\" Hartwell says.", calder)],
            [c("Niamh Delacroix graded each apartment in its own colour temperature so the audience always knows whose window they are looking through.", calder)],
        ])

        b.page("Operator Diaries: Rosa Tkachenko", operatorDiaries, ac, [
            [t("Rosa Tkachenko came to Steadicam from dance, and it shows in the way she talks about weight.")],
            [c("I suspect Gideon may have used Zeiss Supreme Prime lenses on \(calder), but honestly I never looked at the barrels.", calder),
             c("The rig itself was light, probably around 20 kilos fully built.", calder)],
            [c("What I can tell you for sure is that \(calder) used a Technocrane for the rooftop shot, and I stepped off it onto the parapet with the Steadicam.", calder, technocrane, steadicam)],
            [c("On The Quiet Ledger, a few years earlier, I was the second Steadicam operator behind Juno Petrakis.", quietLedger, steadicam)],
        ])

        b.film(910010, calder, 2025, director: "Priya Anand-Mercer", crew: [
            ("Director of Photography", "Gideon Hartwell"),
            ("Steadicam Operator", "Rosa Tkachenko"),
            ("Colorist", "Niamh Delacroix"),
            ("Visual Effects Supervisor", "Arvid Solberg"),
        ], article: [
            [t("\(calder) is a 2025 British ensemble drama directed by Priya Anand-Mercer."),
             c("\(calder) was shot on the Sony Venice by Gideon Hartwell, largely on a single street in Glasgow.", calder, venice)],
        ], firstPass: [diary])

        b.ac("Gideon Hartwell", operatorDiaries)
        b.ac("Rosa Tkachenko", operatorDiaries)
        b.ac("Niamh Delacroix")
        b.ac("Arvid Solberg")
        b.cinesite(calder, failure: "timed out")
    }

    // MARK: - 910011 The Marrow Line, 910023 The Orchardist's Second Wife

    private static func addMarrowLineAndOrchardist(_ b: inout Builder) {
        let amadou = "https://theasc.com/members/bertil-amadou"
        let desrosiers = "https://theasc.com/articles/desrosiers-forty-years"

        b.page("Bertil Amadou, ASC, AFC", amadou, ac, [
            [t("Bertil Amadou was born in Dakar and grew up in Lyon, where he started as a projectionist.")],
            [c("His credits include The Marrow Line (1996), The Orchardist's Second Wife (1999) and Sable Coast (2019).", "")],
            [c("Sable Coast, his most recent feature, was shot on the Panavision Millennium DXL with Panavision Primo lenses.", "Sable Coast", dxl, primo),
             t("Amadou was elected to the Society's board in 2012.")],
            [c("Asked about The Orchardist's Second Wife, he says he probably lit the farmhouse with Kino Flos, \"but it was a long time ago.\"", orchardist)],
        ])

        b.page("Forty Years on the Board: Kwame Desrosiers", desrosiers, ac, [
            [t("Kwame Desrosiers has run lighting desks since before there were lighting desks.")],
            [c("The Orchardist's Second Wife was Desrosiers's first feature as a gaffer.", orchardist),
             c("We lit it with Kino Flos in every room of the farmhouse and a single big source outside for the sun.", orchardist, kinoFlos),
             c("Bertil wanted the dolly in every scene, so we kept the floors clear.", orchardist, dolly)],
            [c("Four years later came Saints of the Low Meridian, which was a completely different job.", saints),
             c("We lit it from outside the church through the windows, with Kino Flos inside only for the confessional.", saints, kinoFlos),
             c("Fenna shot that one on the Arricam LT, which was still new then.", saints, arricam)],
            [c("These days he works mostly in commercials, where he has standardised on SkyPanels.", "")],
        ])

        b.film(910011, marrow, 1996, director: "Clement Ostrova", crew: [
            ("Director of Photography", "Bertil Amadou"),
        ], article: [
            [t("\(marrow) is a 1996 French road movie directed by Clement Ostrova.")],
            [c("\(marrow) was photographed by Bertil Amadou using Panavision Primo lenses and an extensive dolly track laid along a disused railway.", marrow, primo, dolly)],
        ])

        b.film(910023, orchardist, 1999, director: "Philomena Cray", crew: [
            ("Director of Photography", "Bertil Amadou"),
            ("Gaffer", "Kwame Desrosiers"),
        ], article: [
            [t("\(orchardist) is a 1999 period drama directed by Philomena Cray."),
             c("It was shot in the Lot valley in the summer of 1998, on 35mm, by Bertil Amadou.", orchardist)],
        ])

        b.ac("Bertil Amadou", amadou)
        b.ac("Kwame Desrosiers", "https://theasc.com/articles/gaffers-roundtable", desrosiers)
        b.cinesite(orchardist)
    }

    // MARK: - 910012 Saints of the Low Meridian

    private static func addSaints(_ b: inout Builder) {
        let honour = "https://theasc.com/news/liautaud-international-award"

        b.page("Fenna Liautaud receives International Achievement Award", honour, ac, [
            [t("The Society's International Achievement Award goes this year to Dutch cinematographer Fenna Liautaud.")],
            [c("Liautaud's feature credits include Saints of the Low Meridian (2003), The Pale Ferryman (2015) and Glass Tenants (2021).", "")],
            [c("Her 2015 film The Pale Ferryman was shot on the ARRI Alexa Mini with Cooke S4 lenses and became a festival favourite.", "The Pale Ferryman", mini, cooke),
             c("For the television series Northern Ward she moved to the Sony Venice and lit with SkyPanels throughout.", "Northern Ward", venice, skyPanels)],
            [t("She will accept the award in person in Los Angeles.")],
        ])

        b.film(910012, saints, 2003, director: "Rowan Achterberg", crew: [
            ("Director of Photography", "Fenna Liautaud"),
            ("Gaffer", "Kwame Desrosiers"),
        ], article: [
            [t("\(saints) is a 2003 Dutch drama directed by Rowan Achterberg, set among the congregation of a fishing village.")],
            [c("\(saints) was shot on the Arricam LT with Cooke S4 lenses.", saints, arricam, cooke),
             t("It won the Golden Calf for best film.")],
        ])

        b.ac("Fenna Liautaud", honour, "https://theasc.com/articles/desrosiers-forty-years")
    }

    // MARK: - 910013 A Season Under Weatherglass

    private static func addWeatherglass(_ b: inout Builder) {
        let largeFormat = "https://www.lensandlight-review.example/weatherglass-large-format"
        let reyes = "https://theasc.com/articles/reyes-whitlock-65mm-question"

        b.page("Large format on a small budget", largeFormat, lensAndLight, [
            [c("\(weatherglass) is proof that the ARRI Alexa 65 is not only for blockbusters.", weatherglass, alexa65)],
            [t("Joaquin Reyes-Whitlock and director Ottilie Marchbanks had a fraction of a studio budget."),
             c("Interiors were lit with Kino Flos and a lot of negative fill.", weatherglass, kinoFlos)],
            [c("When the production returned to Iceland for additional photography, Emeka Strand took over with a lighter ARRI Alexa Mini package.", weatherglass, mini),
             c("Those pick-ups included the whole aurora sequence, shot on a Technocrane borrowed from a commercial.", weatherglass, technocrane)],
            [c("Saoirse Lindqvist operated the A camera on a dolly for most of the main unit's dialogue scenes.", weatherglass, dolly)],
        ])

        b.page("Joaquin Reyes-Whitlock on the 65mm Question", reyes, ac, [
            [c("Reyes-Whitlock first tried large format on Moth Season, a short he shot on the ARRI Alexa 65 in 2014.", "Moth Season", alexa65),
             c("We lit it with Kino Flos because they were all we could afford.", "Moth Season", kinoFlos)],
            [c("When A Season Under Weatherglass came along he insisted on the ARRI Alexa 65 again.", weatherglass, alexa65),
             c("We used a dolly for nearly every dialogue scene, and Saoirse Lindqvist operated it beautifully.", weatherglass, dolly)],
            [c("The additional photography, shot months later by Emeka Strand, had to cut seamlessly with his footage, so Strand matched the look on an ARRI Alexa Mini.", weatherglass, mini)],
            [c("He admits he probably over-thinks format: \"Most audiences could not tell you what we shot on.\"", "")],
        ])

        b.film(910013, weatherglass, 2016, director: "Ottilie Marchbanks", crew: [
            ("Director of Photography", "Joaquin Reyes-Whitlock"),
            ("Camera Operator", "Saoirse Lindqvist"),
            ("Additional Director of Photography", "Emeka Strand"),
        ], article: [
            [t("\(weatherglass) is a 2016 Icelandic-Irish drama directed by Ottilie Marchbanks.")],
            [c("\(weatherglass) was shot on the ARRI Alexa 65.", weatherglass, alexa65),
             c("Additional photography in Reykjavik was carried out by Emeka Strand on the ARRI Alexa Mini.", weatherglass, mini)],
        ], firstPass: [largeFormat])

        b.ac("Joaquin Reyes-Whitlock", reyes)
        b.ac("Emeka Strand", reyes)
        b.ac("Saoirse Lindqvist")
    }

    // MARK: - 910014 The Glovemaker's Last Winter, 910019 Ballad of the Furnace Children

    private static func addGlovemakerAndBallad(_ b: inout Builder) {
        let archive = "https://theasc.com/archive/from-the-archive-liesl-kovanda"
        let solheimRask = "https://theasc.com/articles/solheim-rask-goes-large"

        b.page("From the Archive: Liesl Kovanda", archive, ac, [
            [t("This profile first appeared in our January 1985 issue.")],
            [c("Liesl Kovanda shot The Glovemaker's Last Winter in a single Bavarian village, mostly by window light.", glovemaker),
             c("She used a dolly only once, for the funeral procession.", glovemaker, dolly)],
        ], failure: .unanswered("timed out"))

        b.page("Margit Solheim-Rask goes large", solheimRask, ac, [
            [c("Margit Solheim-Rask shot the thriller Iron Lullaby on the Sony Venice with Zeiss Supreme Prime lenses.", "Iron Lullaby", venice, supreme)],
            [c("Solheim-Rask, who is no relation to the Danish cinematographer of the 1970s, lit the film with Creamsource Vortex8 units.", "Iron Lullaby", vortex)],
            [t("Iron Lullaby opens in Scandinavian cinemas this autumn.")],
        ])

        b.film(910014, glovemaker, 1983, director: "Albrecht Senn", crew: [
            ("Director of Photography", "Liesl Kovanda"),
        ], article: [
            [t("\(glovemaker) is a 1983 West German drama film directed by Albrecht Senn."),
             t("It was screened at the Berlin International Film Festival and later broadcast on television.")],
        ])

        b.film(910019, ballad, 1975, director: "Ivo Danelius", crew: [
            ("Director of Photography", "Margit Solheim"),
        ], article: [
            [t("\(ballad) is a 1975 Danish drama film directed by Ivo Danelius about child labour in a glassworks.")],
        ])

        b.ac("Liesl Kovanda", archive)
        b.ac("Margit Solheim", solheimRask)
    }

    // MARK: - 910015 Static Over Juniper Pass

    private static func addJuniperPass(_ b: inout Builder) {
        let juniperCinesite = "https://www.cinesite.com/projects/static-over-juniper-pass"
        let stormChasers = "https://theasc.com/articles/storm-chasers"

        b.page("Static Over Juniper Pass | Cinesite", juniperCinesite, cinesite, [
            [t("\(juniper) called for a storm that never stops, and a radio mast that may or may not be alive.")],
            [c("On set, the camera department fitted the Sony Venice with a lens-encoding system so every frame carried focus and zoom data for the VFX team.", juniper, venice),
             c("Hana Yoshimura-Clay's crew surrounded the radio-mast set with witness cameras and laser-surveyed tracking markers.", juniper)],
            [c("Lightning was played back on set through banks of Creamsource Vortex8 fixtures driven by the same timecode as the plates.", juniper, vortex),
             c("Sky plates were shot separately with a six-camera array, probably on RED bodies, according to one compositor.", juniper)],
            [t("Cinesite's Vancouver team delivered 380 shots.")],
        ])

        b.page("Storm Chasers", stormChasers, ac, [
            [c("\(juniper) begins in a thunderstorm and, as Matthias Grünewald-Pyke likes to say, never really leaves it.", juniper),
             c("He and gaffer Ilse Brandvold built the storm look for \(juniper) out of Creamsource Vortex8 units and rain bars.", juniper, vortex)],
            [c("The film's mountain road sequences were shot with a Technocrane on a tracking vehicle, the Sony Venice slung at the end of the arm.", juniper, technocrane, venice),
             c("Second-unit cinematographer Pavel Inouye shot the avalanche inserts for \(juniper) on the RED Monstro.", juniper, monstro)],
            [c("Grünewald-Pyke admits the radio-shack interior was probably overlit, with \"maybe 4K worth of light when 1K would have done.\"", juniper),
             c("The units in there were SkyPanels, rigged to the ceiling beams.", juniper, skyPanels)],
            [c("Teo Marangoni's grade pushed the night scenes toward cyan.", juniper)],
        ])

        b.film(910015, juniper, 2022, director: "Delphine Okoro", crew: [
            ("Director of Photography", "Matthias Grünewald-Pyke"),
            ("Second Unit Director of Photography", "Pavel Inouye"),
            ("Visual Effects Supervisor", "Hana Yoshimura-Clay"),
            ("Gaffer", "Ilse Brandvold"),
            ("Colorist", "Teo Marangoni"),
        ], article: [
            [t("\(juniper) is a 2022 Canadian horror film directed by Delphine Okoro.")],
            [c("\(juniper) was shot on the Sony Venice with Zeiss Supreme Prime lenses in the mountains of British Columbia.", juniper, venice, supreme)],
        ])

        b.ac("Matthias Grünewald-Pyke", stormChasers)
        b.ac("Ilse Brandvold", stormChasers)
        b.ac("Teo Marangoni", stormChasers)
        b.ac("Pavel Inouye", stormChasers)
        b.ac("Hana Yoshimura-Clay")
        b.cinesite(juniper, juniperCinesite, "https://www.cinesite.com/about/our-work")
    }

    // MARK: - 910018 The Quiet Ledger, 910024 Undertow Hymnal

    private static func addQuietLedgerAndUndertow(_ b: inout Builder) {
        let petrakis = "https://theasc.com/members/juno-petrakis-soc"
        let abernethy = "https://theasc.com/articles/abernethy-ledgers-and-hymns"
        let guesswork = "https://www.lensandlight-review.example/undertow-hymnal-guesswork"

        b.page("Associate Members: Juno Petrakis, SOC", petrakis, ac, [
            [c("Petrakis's operating credits include The Lantern Keepers of Hollow Bay, The Quiet Ledger and the series Low Tide Station.", "")],
            [c("On The Quiet Ledger she operated Steadicam through the bank's vault corridor in a seven-minute take.", quietLedger, steadicam)],
            [c("Petrakis now flies an ARRI Alexa Mini on most jobs and says the weight savings have extended her career.", ""),
             c("For Low Tide Station she worked alongside a Technocrane for the first time.", "Low Tide Station", technocrane)],
        ])

        b.page("Lorcan Abernethy: Ledgers and Hymns", abernethy, ac, [
            [t("Lorcan Abernethy's two features could hardly be less alike: one by the sea, one in a vault.")],
            [c("Undertow Hymnal was Abernethy's first feature on the ARRI Alexa Mini.", undertow, mini),
             c("We lit it with SkyPanels bounced off the sea wall, and we lost two of them to the waves.", undertow, skyPanels),
             c("Dov Rautio operated the B camera on a dolly along the harbour wall.", undertow, dolly)],
            [c("For The Quiet Ledger he wanted something heavier and more formal, and moved to the Sony Venice.", quietLedger, venice),
             c("We lit it with Kino Flos in the ceiling of the vault so the light looked like old fluorescents.", quietLedger, kinoFlos),
             c("He suspects the bank scenes may also have used a Technocrane for one shot, but it was cut.", quietLedger)],
        ])

        b.page("What did they shoot Undertow Hymnal on?", guesswork, lensAndLight, [
            [c("Nobody involved has said much about the lenses on \(undertow).", undertow),
             c("Judging by the flares, they probably used Cooke S4 glass, though Leica Summilux-C would also fit.", undertow)],
            [c("The camera is easier: \(undertow) was shot on the ARRI Alexa Mini, as the production's own call sheets confirm.", undertow, mini),
             c("The beach lamps were probably around 300 watts each, which would explain the warm fall-off.", undertow)],
            [c("It may have used a Steadicam for the church procession, or that could be a very good gimbal operator.", undertow)],
        ])

        b.film(910018, quietLedger, 2020, director: "Harriet Mbeki", crew: [
            ("Director of Photography", "Lorcan Abernethy"),
            ("Steadicam Operator", "Juno Petrakis"),
            ("Colorist", "Niamh Delacroix"),
        ], article: [
            [t("\(quietLedger) is a 2020 British heist drama directed by Harriet Mbeki, filmed in a former bank in Leeds.")],
            [c("Cinematographer Lorcan Abernethy shot \(quietLedger) on the Sony Venice with Cooke S4 lenses.", quietLedger, venice, cooke)],
        ])

        b.film(910024, undertow, 2015, director: "Sigrun Matteo", crew: [
            ("Director of Photography", "Lorcan Abernethy"),
            ("Camera Operator", "Dov Rautio"),
        ], article: [
            [t("\(undertow) is a 2015 British drama directed by Sigrun Matteo."),
             c("\(undertow) was shot on the ARRI Alexa Mini on the Northumberland coast.", undertow, mini)],
        ], firstPass: [guesswork])

        b.ac("Lorcan Abernethy", abernethy)
    }

    // MARK: - 910020 Lowlight Psalms

    private static func addLowlightPsalms(_ b: inout Builder) {
        let arkadi = "https://theasc.com/articles/arkadi-grading-in-the-dark"
        let practical = "https://theasc.com/articles/practical-magic"

        b.page("Selin Arkadi: Grading in the Dark", arkadi, ac, [
            [c("On The Lantern Keepers of Hollow Bay, Arkadi built a print emulation from scans of an old Kodak Vision3 500T test roll that Calloway had shot years before.", hollowBay),
             c("The Venice footage took the emulation well because it had so much latitude in the shadows.", hollowBay, venice)],
            [c("Lowlight Psalms was a different problem: most of it is lit by candles and Astera tubes set to a candle-flicker effect.", psalms, astera),
             c("Arkadi graded it in a darkened room at 14 foot-lamberts to match the cinema.", psalms)],
            [c("She now refuses to grade anything on a laptop, she says.", "")],
        ])

        b.page("Practical Magic", practical, ac, [
            [c("Bram Okonkwo's work on \(psalms) began with four hundred candles.", psalms),
             c("For \(psalms) he supplemented them with Astera tubes dressed as altar candles and a single Creamsource Vortex8 outside the chapel window.", psalms, astera, vortex)],
            [c("He estimates the whole chapel rig drew probably around 300 watts, not counting the moonlight unit.", psalms)],
            [c("Unlike on The Lantern Keepers of Hollow Bay, where he could hang SkyPanels from the lighthouse gallery, the chapel ceiling was protected.", psalms)],
        ])

        b.film(910020, psalms, 2024, director: "Cassius Obi-Laurent", crew: [
            ("Director of Photography", "Wren Haldane"),
            ("Colorist", "Selin Arkadi"),
            ("Gaffer", "Bram Okonkwo"),
        ], article: [
            [t("\(psalms) is a 2024 Irish drama directed by Cassius Obi-Laurent, set in a convent in County Clare.")],
            [c("\(psalms) was shot by Wren Haldane on the ARRI Alexa Mini with Leica Summilux-C lenses.", psalms, mini, summilux),
             t("Most of the film is lit by candlelight.")],
        ])

        b.ac("Wren Haldane")
    }
}
