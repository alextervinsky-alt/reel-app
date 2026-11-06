# Builds validation-corpus.json. All films, people, articles and URLs are invented.
# Paragraphs are lists of sentences; a sentence may carry claims, so every
# claim passage is by construction an exact sentence of its source text.
import json, os, sys

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "validation-corpus.json")

class C:
    def __init__(self, t, p, e, ev, why, about=True, film=None, st=None, ctx=""):
        self.t, self.p, self.e, self.ev, self.why = t, p, e, ev, why
        self.about, self.film, self.st, self.ctx = about, film, st, ctx

def S(text, *claims):
    return (text, list(claims))

FILMS, PAGES, CLAIMS = [], [], []
TITLE = {}

def _paras(paras, default_film, source):
    out = []
    for para in paras:
        if isinstance(para, (str, tuple)):
            para = [para]
        sents = []
        for item in para:
            if isinstance(item, str):
                sents.append(item); continue
            text, claims = item
            sents.append(text)
            for c in claims:
                fid = c.film or default_film
                if c.p == "aspect" and not c.st:
                    sys.exit("aspect claim without stage: " + text)
                d = {"id": None, "film": fid, "source": source, "passage": text,
                     "term": c.t, "property": c.p, "expected": c.e,
                     "aboutFilm": c.about, "evidenceType": c.ev}
                if c.p == "aspect":
                    d["stage"] = c.st
                d["context"] = c.ctx or CTX.get(c.ev, c.ev)
                d["rationale"] = c.why
                CLAIMS.append(d)
        out.append(" ".join(sents))
    return out

CTX = {
    "direct": "plain statement about this film's production",
    "comparison": "sentence contrasts this film with another production",
    "relativeClauseThisFilm": "main clause about this film; relative clause names the person's other work",
    "relativeClauseOtherGear": "relative clause describes gear used on a different production",
    "sectionChange": "multi-film article; the sentence sits under a heading or 'On <Title>,' for a specific film",
    "interviewSwitch": "Q/A interview whose questions move between films",
    "denial": "explicit denial of use",
    "denialException": "denial list with an 'except'/'other than' exception",
    "positiveAlternative": "alternatives that were both actually used",
    "unfamiliarStock": "speaker says they are not familiar with a stock; not a denial",
    "hypothetical": "counterfactual or conditional, nothing actually used",
    "retrospectiveDecision": "retrospective account of a decision that was carried out",
    "abandonedPlan": "plan that was dropped",
    "testOnly": "equipment only tested",
    "adoptedTest": "test whose winner was then used",
    "habitual": "habitual or general practice of a crew member",
    "emulation": "look emulated rather than physically produced",
    "styleUsed": "technique described as a style but actually used",
    "prop": "equipment appears as a prop or set dressing",
    "payload": "camera carried by a drone, arm or vehicle rig",
    "crewCredit": "only a crew-role credit is given",
    "definition": "definition of a process or tool",
    "research": "real-world research, not production gear",
    "capability": "product capability only",
    "capabilityAndUse": "capability clause plus an actual-use clause",
    "vendorCredit": "rental/vendor credit",
    "aspectStage": "aspect ratio at a stated stage of the pipeline",
    "rumour": "rumour or unconfirmed report",
    "estimate": "speaker's estimate",
    "multiClause": "several clauses with different gear",
    "creditListMention": "page about another production names this film only in a credit list",
    "incompletePage": "sentence from a page that was truncated in retrieval",
    "otherProduction": "statement about a different production",
    "uncertain": "speaker or source is unsure",
}

def film(fid, title, year, director, crew, article, firstPass):
    TITLE[fid] = title
    FILMS.append({"id": fid, "title": title, "year": year, "director": director,
                  "crew": [{"job": j, "name": n} for j, n in crew],
                  "article": _paras(article, fid, "article:" + title),
                  "firstPass": firstPass})

def page(url, site, title, default_film, paras, failure=None):
    p = {"url": url, "site": site, "title": title,
         "paragraphs": _paras(paras, default_film, url)}
    if failure:
        p["failure"] = failure
    PAGES.append(p)

AC, PVC, CS, LL = "American Cinematographer", "ProVideo Coalition", "Cinesite", "Lens & Lamp"
def ac(slug): return "https://theasc.com/articles/" + slug
def pvc(slug): return "https://www.provideocoalition.com/" + slug + "/"
def cs(slug): return "https://www.cinesite.com/projects/" + slug + "/"
def ll(slug): return "https://www.lensandlamp.com/features/" + slug

A, R, X = "accept", "reject", "abstain"

# ---------------------------------------------------------------- 9201 Brambling
film(9201, "Brambling", 2024, "Mirela Voss",
     [("Director", "Mirela Voss"), ("Director of Photography", "Tobiah Okafor"),
      ("Gaffer", "Dunya Feld"), ("Colorist", "Ilse Marrow"), ("Key Grip", "Rafe Oduya")],
     [
      ["Brambling is a 2024 British drama written and directed by Mirela Voss.",
       "Set on a failing hedge nursery in the Fens, it follows two sisters through a single wet autumn."],
      [S("Cinematographer Tobiah Okafor, who shot Lantern Season on the Alexa Mini, chose the Sony Venice 2 for Brambling because he wanted the latitude of its dual base ISO.",
         C("Sony Venice 2", "camera", A, "relativeClauseThisFilm", "Main clause says Okafor chose the Venice 2 for Brambling."),
         C("Alexa Mini", "camera", R, "relativeClauseThisFilm", "The Alexa Mini belongs to Lantern Season, named only in the relative clause.", about=False)),
       "Principal photography ran for thirty-one days in Cambridgeshire and Norfolk.",
       S("The film was composed for 2.39:1 and the trailers were cut at 1.85:1.",
         C("2.39:1", "aspect", A, "aspectStage", "Composition ratio of the film itself.", st="framing"),
         C("1.85:1", "aspect", X, "aspectStage", "Trailer ratio is marketing material, not the film's own frame at any defined stage.", st="unknown"))],
     ],
     [ac("brambling-wet-season"), pvc("three-grades-ilse-marrow"), ll("brambling-polytunnel-diaries")])

page(ac("brambling-wet-season"), AC, "Wet Season: Tobiah Okafor on Brambling", 9201, [
    ["Tobiah Okafor spent most of Brambling soaked.",
     "The nursery set, a cluster of real polytunnels outside Ely, flooded twice during the shoot, and the camera team learned to work in waders."],
    [S("Okafor paired the Venice 2 with a set of Cooke Panchro/i Classic primes, which he describes as forgiving on skin and unkind to everything else.",
       C("Cooke Panchro/i Classic", "lens", A, "direct", "Directly states the lenses paired with the Venice 2 on this film.")),
     S("Unlike Glasshouse Weather, which Okafor shot entirely on Kodak Vision3 500T 5219, Brambling never went near celluloid.",
       C("Kodak Vision3 500T 5219", "stock", R, "comparison", "5219 was used on Glasshouse Weather; Brambling is said to have used no film.", about=False))],
    [S("“People assume we used a Black Pro-Mist, but there is no filtration on the lens at all,” Okafor says.",
       C("Black Pro-Mist", "filter", R, "denial", "Explicit denial of any filtration."))],
    [S("The polytunnels were lit from outside with Aputure LS 1200d Pro units pushing through the plastic, while a pair of ARRI SkyPanel S60-Cs rigged inside carried the night scenes.",
       C("Aputure LS 1200d Pro", "lighting", A, "multiClause", "First clause: units lit the polytunnels."),
       C("ARRI SkyPanel S60-C", "lighting", A, "multiClause", "Second clause: SkyPanels carried the night scenes."))],
    [S("A Super 8 camera that the younger sister carries everywhere is a prop from a Bury St Edmunds junk shop and was never loaded.",
       C("Super 8", "format", R, "prop", "The Super 8 camera is a prop that was never loaded.")),
     S("The film’s two flashbacks were handled differently, one in 16mm and the other on Super 8, both scanned at Cinelab London.",
       C("16mm", "format", A, "positiveAlternative", "One flashback was shot on 16mm."),
       C("Super 8", "format", A, "positiveAlternative", "The other flashback was shot on Super 8."))],
    [S("Voss had originally wanted to shoot anamorphic, but the idea was abandoned after a budget cut in pre-production.",
       C("anamorphic", "lens", R, "abandonedPlan", "The anamorphic plan was abandoned.")),
     "“In the end I think spherical suited the sisters better,” she says."],
])

# ---------------------------------------------------------------- grades page (9201/9209/9213)
page(pvc("three-grades-ilse-marrow"), PVC, "Three Grades: Ilse Marrow on Brambling, Moth Parliament and Ash & Lanolin", 9201, [
    ["Colorist Ilse Marrow has had an unusually busy eighteen months.",
     "We asked her to walk us through three recent features, all graded in her room in Soho."],
    "Brambling",
    [S("On Brambling, Marrow built a print-film emulation LUT in DaVinci Resolve so that the Venice 2 footage would sit closer to the 16mm flashbacks.",
       C("film-emulation LUT", "finish", A, "emulation", "The emulation LUT itself is a finishing tool that was actually used."),
       C("DaVinci Resolve", "finish", A, "sectionChange", "Under the Brambling heading, 'On Brambling,' states the grading software.")),
     S("Nothing in the main body of the film was printed to Kodak 2383; the print look is entirely emulated.",
       C("Kodak 2383", "stock", R, "emulation", "The print stock look is emulated; nothing was printed to 2383."))],
    "Moth Parliament",
    [S("On Moth Parliament, Marrow worked from ARRIRAW originated on an Alexa 35, with the cinematographer’s own show LUT as the starting point.",
       C("Alexa 35", "camera", A, "sectionChange", "Section change to Moth Parliament; states its camera.", film=9209),
       C("ARRIRAW", "format", A, "sectionChange", "Recording format of Moth Parliament.", film=9209),
       C("Alexa 35", "camera", R, "sectionChange", "Sentence is in the Moth Parliament section, not about Brambling.", film=9201, about=False)),
     S("The silvery, crushed-shadow look that critics called bleach bypass was an emulated ENR built in Resolve; no film was ever processed.",
       C("ENR", "finish", R, "emulation", "ENR was emulated digitally, not done in a lab.", film=9209),
       C("bleach bypass", "finish", R, "emulation", "Critics' label; the look was emulated.", film=9209)),
     S("Bleach bypass is a laboratory process in which the bleach step is skipped so that silver remains in the emulsion alongside the dyes.",
       C("bleach bypass", "finish", R, "definition", "Definition of the process; says nothing about the film's use.", film=9209))],
    "Ash & Lanolin",
    [S("On Ash & Lanolin, the brief was the opposite: a 16mm negative, scanned on a Scanity, with almost nothing done in the grade.",
       C("16mm", "format", A, "sectionChange", "Section change to Ash & Lanolin; its negative format.", film=9213),
       C("Scanity", "finish", A, "sectionChange", "Scanner used for Ash & Lanolin.", film=9213),
       C("16mm", "format", R, "sectionChange", "Sentence concerns Ash & Lanolin, not Moth Parliament.", film=9209, about=False))],
])

# ---------------------------------------------------------------- 9202 Saltmarrow / 9212 Undertow
film(9202, "The Saltmarrow Hours", 2023, "Ines Calloway",
     [("Director", "Ines Calloway"), ("Director of Photography", "Ruth Adebayo-Lind"),
      ("Gaffer", "Mick Arundel"), ("First Assistant Camera", "Sela Varnum")],
     [
      ["The Saltmarrow Hours is a 2023 coastal mystery film directed by Ines Calloway.",
       S("It was shot by Ruth Adebayo-Lind on Kodak Vision3 500T 5219 and 250D 5207 stocks, processed at Kodak Film Lab London.",
         C("Kodak Vision3 500T 5219", "stock", A, "direct", "Names the stocks the film was shot on."),
         C("Kodak Vision3 250D 5207", "stock", A, "direct", "Names the stocks the film was shot on."))],
      [S("The film was released theatrically at 1.85:1.",
         C("1.85:1", "aspect", A, "aspectStage", "Theatrical release ratio.", st="theatrical")),
       S("A rumoured IMAX version of the storm sequence was never confirmed by the studio.",
         C("IMAX", "format", X, "rumour", "Rumour that was neither confirmed nor denied."))],
     ],
     [ac("ruth-adebayo-lind-salt-and-shadow"), cs("the-saltmarrow-hours")])

page(ac("ruth-adebayo-lind-salt-and-shadow"), AC, "Salt and Shadow: A Conversation with Ruth Adebayo-Lind", 9202, [
    ["Ruth Adebayo-Lind has photographed features for Ines Calloway and Mateus Kerridge.",
     "We spoke between prep days on her next project."],
    "AC: Let’s start with The Saltmarrow Hours. Why film?",
    ["Adebayo-Lind: Ines wanted grain that moved.",
     S("We carried an Arricam LT for most of it and an Arriflex 235 for the handheld days on the causeway.",
       C("Arricam LT", "camera", A, "interviewSwitch", "Answer to the Saltmarrow question names the main body."),
       C("Arriflex 235", "camera", A, "interviewSwitch", "Handheld body on Saltmarrow."))],
    "AC: Any diffusion?",
    [S("Adebayo-Lind: Nothing except a Tiffen Glimmerglass 1 on the night interiors, so no Pro-Mists, no nets and no Hollywood Black Magic.",
       C("Tiffen Glimmerglass", "filter", A, "denialException", "The exception was used on night interiors."),
       C("Pro-Mist", "filter", R, "denialException", "Listed among the filters not used."),
       C("Hollywood Black Magic", "filter", R, "denialException", "Listed among the filters not used."))],
    "AC: Was the day-for-night material on 5203?",
    [S("Adebayo-Lind: I’m honestly not familiar with that stock by number.",
       C("Kodak Vision3 50D 5203", "stock", X, "unfamiliarStock", "She does not know the stock number; neither confirms nor denies 5203.")),
     "The loader placed the orders, and I asked for the slowest daylight film we could get."],
    "AC: And on Undertow Parish, a couple of years earlier?",
    [S("Adebayo-Lind: That one was all digital, an Alexa Mini LF with Signature Primes.",
       C("Alexa Mini LF", "camera", A, "interviewSwitch", "Question switched to Undertow Parish.", film=9212),
       C("ARRI Signature Prime", "lens", A, "interviewSwitch", "Undertow Parish lenses.", film=9212),
       C("Alexa Mini LF", "camera", R, "interviewSwitch", "Answer is about Undertow Parish, not Saltmarrow.", film=9202, about=False)),
     S("We never shot a frame of 35mm on it, though people still ask because of the texture.",
       C("35mm", "format", R, "denial", "Explicit denial for Undertow Parish.", film=9212))],
    "AC: Back to Saltmarrow: the lighthouse scene reads as pure moonlight.",
    [S("Adebayo-Lind: It’s a 20K tungsten Fresnel up on a Condor, gelled full CTB, plus a lot of smoke.",
       C("20K tungsten Fresnel", "lighting", A, "interviewSwitch", "Question returned to Saltmarrow's lighthouse scene."),
       C("Condor", "support", A, "interviewSwitch", "The lamp was rigged on a Condor for Saltmarrow."),
       C("20K tungsten Fresnel", "lighting", R, "interviewSwitch", "Context switched back to Saltmarrow.", film=9212, about=False))],
    "AC: If you were to shoot it again?",
    [S("Adebayo-Lind: I’d probably take the Alexa 65 out for the storm, just to see what the sensor does with spray.",
       C("Alexa 65", "camera", R, "hypothetical", "Hypothetical reshoot."))],
])

page(cs("the-saltmarrow-hours"), CS, "The Saltmarrow Hours", 9202, [
    "Cinesite delivered 142 visual effects shots for The Saltmarrow Hours, led by the storm sequence and the lighthouse collapse.",
    [S("Plates were captured on the production’s Arricam LT and scanned at 4K before our compositors extended the sea stacks.",
       C("Arricam LT", "camera", A, "direct", "Vendor page states the plate camera.")),
     S("Because the practical 18K HMI on the clifftop could not reach the water, the team built a digital beam that matched its throw.",
       C("18K HMI", "lighting", A, "multiClause", "Subordinate clause attests a practical 18K HMI on set."))],
    "Our environment team also rebuilt the harbour wall, which was demolished a year before the shoot.",
])

film(9212, "Undertow Parish", 2021, "Mateus Kerridge",
     [("Director", "Mateus Kerridge"), ("Director of Photography", "Ruth Adebayo-Lind"),
      ("Gaffer", "Joss Penhale"), ("Steadicam Operator", "Lotte Brenner"), ("Dolly Grip", "Amara Quell")],
     [
      ["Undertow Parish is a 2021 drama directed by Mateus Kerridge and set in a flood-threatened village in the Somerset Levels.",
       "Ruth Adebayo-Lind photographed the film."],
      [S("The camera package was supplied by Panavision London.",
         C("Panavision", "camera", X, "vendorCredit", "Vendor named, no specific equipment.")),
       S("The end credits list Lotte Brenner as Steadicam operator and Amara Quell as dolly grip.",
         C("Steadicam", "support", R, "crewCredit", "A role credit does not state the rig was used."),
         C("dolly", "support", R, "crewCredit", "A role credit does not state the rig was used."))],
      [S("It was finished at 2.39:1, extracted from the Mini LF’s open-gate 3:2 capture.",
         C("2.39:1", "aspect", A, "aspectStage", "Ratio extracted from the capture.", st="extraction"),
         C("3:2", "aspect", A, "aspectStage", "Open-gate capture ratio.", st="capture"))],
     ],
     [pvc("undertow-parish-flood-light"), ac("ruth-adebayo-lind-salt-and-shadow")])

page(pvc("undertow-parish-flood-light"), PVC, "Flood Light: Lighting Undertow Parish", 9212, [
    "For the church sequence in Undertow Parish, Adebayo-Lind and gaffer Joss Penhale wanted the light to feel as if it came off the water.",
    [S("They floated two LiteGear LiteMat 4s on rafts in the flooded nave and bounced a Creamsource Vortex8 off a silver sheet rigged under the gallery.",
       C("LiteGear LiteMat", "lighting", A, "multiClause", "LiteMats floated on rafts."),
       C("Creamsource Vortex8", "lighting", A, "multiClause", "Vortex8 bounced off a silver sheet.")),
     S("The Vortex8 can run from a V-mount battery for roughly an hour at full output, which made the rafts possible.",
       C("Creamsource Vortex8", "lighting", A, "capabilityAndUse", "Capability clause tied to actual use on the rafts."))],
    [S("Penhale says he carries a pair of Astera Titan Tubes on every job for exactly this kind of emergency.",
       C("Astera Titan Tube", "lighting", X, "habitual", "General practice; not stated as used here."))],
    [S("The DJI Ronin 4D that appears in behind-the-scenes photos belonged to the EPK crew, not the main unit.",
       C("DJI Ronin 4D", "camera", R, "denial", "The camera belonged to the EPK crew, not the production's main unit."))],
])

# ---------------------------------------------------------------- 9203 Orchard
film(9203, "…And the Orchard Burned", 2025, "Ferran Quist",
     [("Director", "Ferran Quist"), ("Director of Photography", "Halvard Mbeki"), ("Gaffer", "Noor Castellan")],
     [
      ["…And the Orchard Burned is a 2025 period drama directed by Ferran Quist.",
       "It is set in an apple-growing valley in 1911."],
      [S("Cinematographer Halvard Mbeki lit the farmhouse interiors with dimmed halogen bulbs inside hurricane lamps, emulating candlelight without the flicker problems of open flame.",
         C("halogen bulbs", "lighting", A, "emulation", "Halogen bulbs were physically used."),
         C("candlelight", "lighting", R, "emulation", "Candlelight was emulated, not used."))],
      [S("The film was shot on the ARRI Alexa 35 in its 4:3 mode with Hawk V-Lite anamorphics, and released at 2.39:1.",
         C("ARRI Alexa 35", "camera", A, "multiClause", "Camera stated."),
         C("Hawk V-Lite", "lens", A, "multiClause", "Lenses stated."),
         C("4:3", "aspect", A, "aspectStage", "Sensor mode at capture.", st="capture"),
         C("2.39:1", "aspect", A, "aspectStage", "Release ratio.", st="theatrical"))],
     ],
     [ac("first-light-debut-features"), cs("and-the-orchard-burned"), ll("noor-castellan-orchard")])

page(ac("first-light-debut-features"), AC, "First Light: Three Debut Features", 9203, [
    ["Debut features rarely get the prep time their cinematographers want.",
     "These three found ways around it."],
    "…And the Orchard Burned",
    [S("Mbeki tested the Alexa 35 against a Venice 2 and a Red V-Raptor in the orchard at dusk, and the Alexa won on the highlight roll-off in the blossom.",
       C("Alexa 35", "camera", A, "adoptedTest", "Test winner, consistent with the camera used."),
       C("Venice 2", "camera", R, "testOnly", "Lost the test."),
       C("Red V-Raptor", "camera", R, "testOnly", "Lost the test.")),
     S("The fire was lit for real with a controlled burn on the last two nights, supplemented by flicker boxes driving Quasar Science Rainbow 2 tubes.",
       C("Quasar Science Rainbow 2", "lighting", A, "multiClause", "Tubes supplemented the real fire."))],
    "Winter’s Ledger",
    [S("On Winter’s Ledger, Casimir Tran went the other way, shooting 16mm on an Arriflex 416 with Zeiss Ultra 16 primes.",
       C("16mm", "format", A, "sectionChange", "Under the Winter’s Ledger heading.", film=9204),
       C("Arriflex 416", "camera", A, "sectionChange", "Winter’s Ledger camera.", film=9204),
       C("Zeiss Ultra 16", "lens", A, "sectionChange", "Winter’s Ledger lenses.", film=9204),
       C("Arriflex 416", "camera", R, "sectionChange", "Section has moved to Winter’s Ledger.", film=9203, about=False)),
     S("Tran says one of his decisions was never to use a zoom, even for the long-lens courtroom coverage.",
       C("zoom", "lens", R, "retrospectiveDecision", "Decision carried out was to not use a zoom.", film=9204))],
    "Lowtide — A Fugue",
    [S("For Lowtide — A Fugue, Yuki Delacroix-Hart, whose previous feature was shot on Ektachrome reversal, stayed digital with a Sony Burano.",
       C("Sony Burano", "camera", A, "sectionChange", "Under the Lowtide heading.", film=9205),
       C("Ektachrome", "stock", R, "relativeClauseOtherGear", "Ektachrome describes her previous feature.", film=9205, about=False),
       C("Sony Burano", "camera", R, "sectionChange", "Sentence concerns Lowtide, not Winter’s Ledger.", film=9204, about=False)),
     S("The beach material was shot at 48 frames per second and played back at 24.",
       C("48 fps", "format", A, "sectionChange", "Lowtide's beach material frame rate.", film=9205))],
])

page(cs("and-the-orchard-burned"), CS, "…And the Orchard Burned", 9203, [
    "Cinesite’s team created the orchard fire extensions for …And the Orchard Burned.",
    [S("Plate photography used a Technocrane on a tracked base so that the burning rows could be revisited with matching moves.",
       C("Technocrane", "support", A, "direct", "Plate photography used a Technocrane."))],
    [S("A DJI Inspire 3 carried a Zenmuse X9 for aerial plates over the valley.",
       C("DJI Inspire 3", "support", A, "payload", "Drone used for aerial plates."),
       C("Zenmuse X9", "camera", A, "payload", "Camera payload on the drone."))],
])

page(ll("noor-castellan-orchard"), LL, "Gaffer Notes: Noor Castellan", 9203, [
    "Noor Castellan had never lit a fire scene before …And the Orchard Burned.",
    [S("For the barn sequence she rigged twelve Maxi-Brutes on the hillside behind the trees.",
       C("Maxi-Brute", "lighting", A, "incompletePage", "Complete sentence states use even though the page is truncated.")),
     "The barn interior, by contrast, was lit with"],
], failure="incomplete")

# ---------------------------------------------------------------- 9204 Winter's Ledger
film(9204, "Winter’s Ledger", 2022, "Odile Fenwick",
     [("Director", "Odile Fenwick"), ("Director of Photography", "Casimir Tran"), ("Gaffer", "Bram Holloway")],
     [
      ["Winter’s Ledger is a 2022 legal drama directed by Odile Fenwick.",
       "It follows a provincial accountant who becomes a witness in a fraud trial."],
      [S("Casimir Tran photographed the film on 16mm, using Kodak Vision3 7219 for interiors and 7213 for exteriors.",
         C("16mm", "format", A, "direct", "Format stated."),
         C("Kodak Vision3 7219", "stock", A, "direct", "Interior stock."),
         C("Kodak Vision3 7213", "stock", A, "direct", "Exterior stock."))],
      [S("The film was framed for 1.66:1 on the Super 16 negative.",
         C("1.66:1", "aspect", A, "aspectStage", "Framing ratio.", st="framing")),
       S("Its streaming release was cropped to 1.78:1, a decision Fenwick has criticised.",
         C("1.78:1", "aspect", A, "aspectStage", "Home-media ratio, though not the director's choice.", st="homeMedia"))],
     ],
     [pvc("casimir-tran-sixteen"), ac("first-light-debut-features"), ac("bram-holloway-tungsten")])

page(pvc("casimir-tran-sixteen"), PVC, "Why Casimir Tran Keeps Coming Back to Sixteen", 9204, [
    "Casimir Tran shoots more 16mm than almost anyone working in features today.",
    [S("He says he always carries an Arriflex 416 and a Bolex as a crash camera, whatever the production.",
       C("Bolex", "camera", X, "habitual", "Habitual kit; this sentence does not say it was used here."),
       C("Arriflex 416", "camera", X, "habitual", "Habitual kit; not specific to this film."))],
    [S("On Winter’s Ledger the Bolex never came out of its case.",
       C("Bolex", "camera", R, "denial", "Explicitly not used."))],
    [S("Winter’s Ledger’s courtroom was lit with a single 12K HMI through a 12×12 Ultrabounce, with Kino Flo Celebs as eye-lights.",
       C("12K HMI", "lighting", A, "multiClause", "Key light for the courtroom."),
       C("Kino Flo Celeb", "lighting", A, "multiClause", "Eye-lights."))],
    [S("If Winter’s Ledger had been a studio picture, he says, he would have been pushed onto an Alexa.",
       C("Alexa", "camera", R, "hypothetical", "Counterfactual."))],
    [S("Tran is now prepping a feature that he hopes to shoot on Kodak Ektachrome 100D, though its financing is not yet closed.",
       C("Kodak Ektachrome 100D", "stock", R, "otherProduction", "Refers to a future production.", about=False))],
])

# ---------------------------------------------------------------- 9205 Lowtide
film(9205, "Lowtide — A Fugue", 2024, "Bastian Orrell",
     [("Director", "Bastian Orrell"), ("Director of Photography", "Yuki Delacroix-Hart"), ("Steadicam Operator", "Ilan Merce")],
     [
      ["Lowtide — A Fugue is a 2024 experimental drama directed by Bastian Orrell.",
       "Its four movements take place on the same Breton beach across a single tide cycle."],
      [S("Cinematographer Yuki Delacroix-Hart shot the film on the Sony Burano with Leitz Hektor primes.",
         C("Sony Burano", "camera", A, "direct", "Camera stated."),
         C("Leitz Hektor", "lens", A, "direct", "Lenses stated.")),
       S("The second movement switches to a 1.33:1 frame for its entire twelve-minute length.",
         C("1.33:1", "aspect", A, "aspectStage", "Ratio of one sequence.", st="sequence"))],
      [S("A camera car fitted with a Russian Arm carried the Burano along the sand for the opening shot.",
         C("Russian Arm", "support", A, "payload", "Vehicle-mounted crane used."),
         C("Sony Burano", "camera", A, "payload", "Camera carried by the arm."))],
     ],
     [ac("lowtide-fugue-tidal-logic"), ac("first-light-debut-features")])

page(ac("lowtide-fugue-tidal-logic"), AC, "Tidal Logic: Yuki Delacroix-Hart on Lowtide — A Fugue", 9205, [
    "Delacroix-Hart describes Lowtide as a film that “breathes in and out with the water.”",
    [S("Its floating, long-take style was not a trick of stabilisation in post; operator Ilan Merce walked every shot on a Steadicam M-2 with a Burano on the arm.",
       C("Steadicam M-2", "support", A, "styleUsed", "The style was achieved with an actual Steadicam."))],
    [S("The production had planned to shoot the third movement on an Alexa 65, but the rental fell through a week before the shoot.",
       C("Alexa 65", "camera", R, "abandonedPlan", "Rental fell through."))],
    [S("Some on the crew believe Orrell also slipped a Bolex into the final movement, but no one we spoke to could confirm it.",
       C("Bolex", "camera", X, "rumour", "Unconfirmed belief."))],
    [S("“I’d say about seventy percent of the film is on the 50mm Hektor,” Delacroix-Hart estimates.",
       C("50mm Hektor", "lens", A, "estimate", "Only the proportion is estimated; use is stated."))],
    [S("Her favourite tool, she says, is the Burano’s built-in variable ND, which can be adjusted from 0.6 to 2.1 without changing the exposure index.",
       C("variable ND", "filter", R, "capability", "Describes a camera feature and her preference, not its use on this film."))],
])

# ---------------------------------------------------------------- 9206 Pennyroyal
film(9206, "Pennyroyal", 2021, "Saoirse Lund",
     [("Director", "Saoirse Lund"), ("Director of Photography", "Marek Obuya"), ("Gaffer", "Ewan Strick")],
     [
      ["Pennyroyal is a 2021 Irish horror film directed by Saoirse Lund.",
       S("Marek Obuya shot it on the RED Komodo 6K, often mounted on a DJI Ronin 2.",
         C("RED Komodo 6K", "camera", A, "direct", "Camera stated."),
         C("DJI Ronin 2", "support", A, "direct", "Gimbal stated."))],
      [S("The title sequence was shot through a Lensbaby Composer, an effect Obuya first used on his short Kettle Psalm.",
         C("Lensbaby Composer", "lens", A, "relativeClauseThisFilm", "Main clause: the title sequence used it; the appositive names earlier work.")),
       S("Pennyroyal was distributed at 2.00:1.",
         C("2.00:1", "aspect", A, "aspectStage", "Distribution ratio; stage not specified.", st="unknown"))],
     ],
     [pvc("pennyroyal-small-camera-big-dread"), ll("pennyroyal-lund-interview")])

page(pvc("pennyroyal-small-camera-big-dread"), PVC, "Small Camera, Big Dread: Pennyroyal", 9206, [
    "Marek Obuya likes small cameras.",
    [S("The Komodo’s global shutter, which eliminates rolling-shutter skew, was one reason it was chosen for the whip-pan scares.",
       C("RED Komodo", "camera", A, "capabilityAndUse", "Capability explained, and the camera was chosen for the scares.")),
     S("A Komodo can record up to 40 frames per second at full 6K resolution.",
       C("RED Komodo", "camera", R, "capability", "Generic product capability."))],
    [S("For the cellar, Obuya used a style he calls “torch noir,” lighting everything with the actors’ own flashlights fitted with LED bulbs.",
       C("flashlights", "lighting", A, "styleUsed", "The named style was the actual lighting method."))],
    [S("The antique Graflex press camera in the parish priest’s study is set dressing borrowed from a museum in Cork.",
       C("Graflex", "camera", R, "prop", "Set dressing."))],
    [S("Obuya researched how 1920s parish photographers lit their portraits with magnesium flash before designing the photo-album sequence.",
       C("magnesium flash", "lighting", R, "research", "Historical research only.")),
     S("He tested Atlas Orion anamorphics for a week before deciding the film should stay spherical.",
       C("Atlas Orion", "lens", R, "testOnly", "Tested then rejected."))],
])

page(ac("copper-psalter-candle-logic"), AC, "Candle Logic: The Copper Psalter", None, [
    "The Copper Psalter, a monastic drama shot in Northumberland, is lit almost entirely by flame.",
    [S("Gaffer Ewan Strick, whose credits include Pennyroyal, Cinderwick and Starling Debt, rigged forty dimmable Astera Titan Tubes behind the choir stalls.",
       C("Astera Titan Tube", "lighting", R, "creditListMention", "Tubes were rigged on The Copper Psalter.", film=9206, about=False),
       C("Astera Titan Tube", "lighting", R, "creditListMention", "Tubes were rigged on The Copper Psalter.", film=9207, about=False),
       C("Astera Titan Tube", "lighting", R, "creditListMention", "Tubes were rigged on The Copper Psalter.", film=9214, about=False)),
     S("Cinematographer Hester Vane shot on an Alexa Mini LF with ARRI Signature Primes at T1.8.",
       C("Alexa Mini LF", "camera", R, "creditListMention", "Describes The Copper Psalter.", film=9206, about=False))],
    "The production’s candles were real beeswax, replaced every ninety minutes by an art department runner.",
])

# ---------------------------------------------------------------- 9207 Cinderwick
film(9207, "Cinderwick", 2025, "Anouk Brannigan",
     [("Director", "Anouk Brannigan"), ("Director of Photography", "Teodor Ashworth"), ("Gaffer", "Ewan Strick"),
      ("Technocrane Operator", "Dov Arnesen"), ("Drone Pilot", "Saffi Rhee")],
     [
      ["Cinderwick is a 2025 fantasy adventure directed by Anouk Brannigan.",
       S("It was photographed by Teodor Ashworth in large format on the ARRI Alexa 65 with Prime DNA lenses.",
         C("ARRI Alexa 65", "camera", A, "direct", "Camera stated."),
         C("Prime DNA", "lens", A, "direct", "Lenses stated."))],
      [S("Theatrical exhibition was at 1.90:1 in IMAX venues and 2.39:1 elsewhere.",
         C("1.90:1", "aspect", A, "aspectStage", "IMAX exhibition ratio.", st="theatrical"),
         C("2.39:1", "aspect", A, "aspectStage", "Standard exhibition ratio.", st="theatrical")),
       S("The 4K disc presents the film at 2.39:1 only.",
         C("2.39:1", "aspect", A, "aspectStage", "Disc ratio.", st="homeMedia"))],
      [S("The credits name Dov Arnesen as Technocrane operator and Saffi Rhee as drone pilot.",
         C("Technocrane", "support", R, "crewCredit", "Role credit only."),
         C("drone", "support", R, "crewCredit", "Role credit only."))],
     ],
     [cs("cinderwick"), pvc("teodor-ashworth-going-large"), ll("overheard-festival-season-2025")])

page(cs("cinderwick"), CS, "Cinderwick", 9207, [
    "Cinesite was the lead vendor on Cinderwick, delivering 610 shots across the forge and sky-city sequences.",
    [S("Our virtual production team supplied the LED volume content, and the forge interiors were shot in front of a ROE Black Pearl BP2 wall with the Alexa 65.",
       C("ROE Black Pearl BP2", "lighting", A, "multiClause", "LED wall used for the forge interiors."),
       C("Alexa 65", "camera", A, "multiClause", "Camera in front of the wall."))],
    [S("An LED volume is a stage enclosed by LED panels that display real-time rendered backgrounds, providing both image and interactive light.",
       C("LED volume", "lighting", R, "definition", "Definition only."))],
    [S("Cinesite’s pipeline can ingest ARRIRAW, Sony X-OCN and REDCODE RAW natively.",
       C("REDCODE RAW", "format", R, "capability", "Vendor pipeline capability."),
       C("Sony X-OCN", "format", R, "capability", "Vendor pipeline capability."))],
])

page(pvc("teodor-ashworth-going-large"), PVC, "Teodor Ashworth on Going Large", 9207, [
    [S("Ashworth, who shot his previous film Barrowmere on 65mm film with a Panavision System 65, says digital large format was the obvious choice for Cinderwick’s effects load.",
       C("65mm", "format", R, "relativeClauseOtherGear", "65mm film was used on Barrowmere.", about=False),
       C("Panavision System 65", "camera", R, "relativeClauseOtherGear", "Camera of Barrowmere.", about=False))],
    [S("He and Brannigan considered shooting the sky-city scenes on a Phantom Flex4K for slow motion, but the idea never got past a conversation.",
       C("Phantom Flex4K", "camera", R, "abandonedPlan", "Never got past discussion.")),
     S("In the end, the sky-city scenes were shot at 60 frames per second on the Alexa 65 itself.",
       C("60 fps", "format", A, "direct", "Frame rate actually used.")),
     S("The Alexa 65 records at up to 60 frames per second in open gate, which happened to be exactly what they needed.",
       C("Alexa 65", "camera", A, "capabilityAndUse", "Capability tied to the frame rate they used."))],
])

# ---------------------------------------------------------------- 9208 Gannet / 9215 Driftglass
film(9208, "The ‘Gannet’ Tapes", 2023, "Lior Castellane",
     [("Director", "Lior Castellane"), ("Director of Photography", "Wren Halvorsen")],
     [
      ["The ‘Gannet’ Tapes is a 2023 found-footage thriller directed by Lior Castellane.",
       "Its premise is that the footage was recovered from a seabird researcher’s equipment."],
      [S("Although the film is presented as Hi8 video, Wren Halvorsen actually shot it on a Blackmagic Pocket Cinema Camera 6K and applied a Hi8 emulation in the grade.",
         C("Hi8", "format", R, "emulation", "Hi8 is emulated."),
         C("Blackmagic Pocket Cinema Camera 6K", "camera", A, "emulation", "The physical camera actually used.")),
       S("The 4:3 frame was extracted from the camera’s 16:9 sensor area.",
         C("4:3", "aspect", A, "aspectStage", "Extraction ratio.", st="extraction"),
         C("16:9", "aspect", A, "aspectStage", "Sensor area used at capture.", st="capture"))],
     ],
     [ac("wren-halvorsen-faking-it-honestly")])

page(ac("wren-halvorsen-faking-it-honestly"), AC, "Faking It Honestly: Wren Halvorsen on The ‘Gannet’ Tapes", 9208, [
    "AC: Did you ever consider shooting on real Hi8?",
    [S("Halvorsen: We bought two Sony Hi8 camcorders online and tested them for a weekend, but the dropouts were unusable, so they went back in a drawer.",
       C("Sony Hi8 camcorder", "camera", R, "testOnly", "Tested and shelved."))],
    "AC: What about the helmet-camera shots on the cliffs?",
    [S("Halvorsen: Those are a GoPro Hero 11 on a chest mount, worn by our climbing double.",
       C("GoPro Hero 11", "camera", A, "direct", "Camera used for cliff shots."),
       C("chest mount", "support", A, "direct", "Mount used."))],
    "AC: You also shot Driftglass, which looks nothing like this.",
    [S("Halvorsen: Driftglass was all Panavision Millennium DXL2 and Primo 70s, a completely different universe.",
       C("Panavision Millennium DXL2", "camera", A, "interviewSwitch", "Answer concerns Driftglass.", film=9215),
       C("Primo 70", "lens", A, "interviewSwitch", "Driftglass lenses.", film=9215),
       C("Panavision Millennium DXL2", "camera", R, "interviewSwitch", "Driftglass gear, not The ‘Gannet’ Tapes.", film=9208, about=False))],
    "AC: Back to the ‘Gannet’ footage: how did you handle night?",
    [S("Halvorsen: The researcher’s head torch is the only light in most of those scenes, a Petzl Actik that we modified with a warmer LED.",
       C("Petzl Actik", "lighting", A, "interviewSwitch", "Back on the ‘Gannet’ footage."),
       C("Petzl Actik", "lighting", R, "interviewSwitch", "Question returned to The ‘Gannet’ Tapes.", film=9215, about=False))],
    "AC: Would you shoot found footage on film?",
    [S("Halvorsen: If someone gave me Super 8 and a year, I might try it.",
       C("Super 8", "format", R, "hypothetical", "Conditional future."))],
])

film(9215, "Driftglass", 2022, "Tomasz Ellery",
     [("Director", "Tomasz Ellery"), ("Director of Photography", "Wren Halvorsen"), ("Colorist", "Mira Ostrander")],
     [
      ["Driftglass is a 2022 romantic drama directed by Tomasz Ellery, set among beachcombers on the Northumberland coast.",
       S("Wren Halvorsen shot the film on a Panavision Millennium DXL2 with Primo 70 lenses.",
         C("Panavision Millennium DXL2", "camera", A, "direct", "Camera stated."),
         C("Primo 70", "lens", A, "direct", "Lenses stated."))],
      [S("The film was released at 2.39:1, framed within the DXL2’s full-frame sensor.",
         C("2.39:1", "aspect", A, "aspectStage", "Release ratio.", st="theatrical"))],
     ],
     [cs("driftglass"), ac("wren-halvorsen-faking-it-honestly")])

page(cs("driftglass"), CS, "Driftglass", 9215, [
    "Cinesite completed 88 invisible effects shots for Driftglass.",
    [S("Most of the work involved removing modern wind turbines from the horizon of plates shot with the DXL2 and Primo 70 glass.",
       C("DXL2", "camera", A, "direct", "Plates were shot on the DXL2."))],
    [S("For the underwater sequences, the production used a Hydroflex housing around a DXL2, and our team cleaned up particulate and bubbles.",
       C("Hydroflex housing", "support", A, "multiClause", "Housing used underwater."))],
])

page(pvc("gear-notes-hollow-bell"), PVC, "Gear Notes: Hollow Bell", None, [
    "Hollow Bell is a chamber piece shot in eleven days in a single Dorset farmhouse.",
    [S("Colorist Mira Ostrander, whose recent work includes Driftglass and Halfway to Oxbow, graded Hollow Bell from Alexa 35 LogC4 files.",
       C("Alexa 35", "camera", R, "creditListMention", "LogC4 files are Hollow Bell's.", film=9215, about=False),
       C("Alexa 35", "camera", R, "creditListMention", "LogC4 files are Hollow Bell's.", film=9216, about=False))],
    "The flashbacks were shot on Kodak Double-X 5222 and scanned at 4K.",
])

# ---------------------------------------------------------------- 9209 Moth Parliament
film(9209, "Moth Parliament", 2024, "Kwabena Stroud",
     [("Director", "Kwabena Stroud"), ("Director of Photography", "Elif Marchetti"),
      ("Gaffer", "Rosalind Achebe-Holt"), ("Colorist", "Ilse Marrow")],
     [
      ["Moth Parliament is a 2024 political drama directed by Kwabena Stroud.",
       S("Elif Marchetti shot it on the ARRI Alexa 35 with Zeiss Supreme Prime Radiance lenses.",
         C("ARRI Alexa 35", "camera", A, "direct", "Camera stated."),
         C("Zeiss Supreme Prime Radiance", "lens", A, "direct", "Lenses stated."))],
      [S("Its distinctive silver look is often mistaken for bleach bypass, but it was created digitally.",
         C("bleach bypass", "finish", R, "emulation", "Look created digitally."))],
     ],
     [ac("moth-parliament-in-chamber"), pvc("three-grades-ilse-marrow")])

page(ac("moth-parliament-in-chamber"), AC, "In Chamber: Elif Marchetti on Moth Parliament", 9209, [
    [S("For the parliament chamber, Marchetti and gaffer Rosalind Achebe-Holt hung a 30-foot softbox made from 64 SkyPanel S360-Cs over the set.",
       C("SkyPanel S360-C", "lighting", A, "direct", "Units formed the softbox."))],
    [S("Marchetti researched archive photographs of the 1970s chamber, which was lit by banks of mercury vapour lamps, to match the green cast.",
       C("mercury vapour lamps", "lighting", R, "research", "Describes the historical chamber.")),
     S("The green itself came from Rosco Plusgreen gels on the SkyPanels, rather than from any real mercury fixtures.",
       C("Rosco Plusgreen", "lighting", A, "emulation", "The gels were physically used."),
       C("mercury fixtures", "lighting", R, "emulation", "Explicitly not used."))],
    [S("“I always use a 1/8 Black Satin on close-ups,” Marchetti says.",
       C("Black Satin", "filter", X, "habitual", "General habit.")),
     S("On this film, that meant a Tiffen Black Satin 1/8 on every single close-up of the prime minister.",
       C("Tiffen Black Satin", "filter", A, "habitual", "Habit applied to this film."))],
    [S("The production had a Technodolly on standby for the vote sequence, but it was never used because the floor would not take the weight.",
       C("Technodolly", "support", R, "abandonedPlan", "On standby but never used."))],
])

# ---------------------------------------------------------------- 9210 Quarry Light
film(9210, "Quarry Light", 2022, "Delphine Arkwright",
     [("Director", "Delphine Arkwright"), ("Director of Photography", "Oskar Nyambura"), ("Drone Pilot", "Kit Mallory")],
     [
      ["Quarry Light is a 2022 drama about a family of stonemasons, directed by Delphine Arkwright.",
       S("Oskar Nyambura shot the film on Kodak Vision3 50D 5203 and 250D 5207 with a Panavision Millennium XL2.",
         C("Kodak Vision3 50D 5203", "stock", A, "direct", "Stock stated."),
         C("Kodak Vision3 250D 5207", "stock", A, "direct", "Stock stated."),
         C("Panavision Millennium XL2", "camera", A, "direct", "Camera stated."))],
      [S("The film was captured in 3-perf Super 35 and framed for 2.39:1.",
         C("3-perf Super 35", "format", A, "direct", "Capture format."),
         C("2.39:1", "aspect", A, "aspectStage", "Framing ratio.", st="framing")),
       S("Its 2026 4K restoration from the original negative keeps the 2.39:1 frame.",
         C("2.39:1", "aspect", A, "aspectStage", "Restoration ratio.", st="restoration"))],
     ],
     [ac("quarry-light-cut-from-stone"), pvc("quarry-light-dust")])

page(ac("quarry-light-cut-from-stone"), AC, "Cut From Stone: Quarry Light", 9210, [
    "Arkwright and Nyambura spent four months in a working quarry in Cumbria.",
    [S("Nyambura considered shooting the blasting scenes on a Phantom, but he says that if they had, the film would have lost its weight.",
       C("Phantom", "camera", R, "hypothetical", "Considered; counterfactual.")),
     S("Instead, the explosions were covered with three Panaflex bodies at 48 frames per second, one of them mounted on a Libra head on a crane.",
       C("Panaflex", "camera", A, "multiClause", "Bodies covering the explosions."),
       C("Libra head", "support", A, "multiClause", "Head used."),
       C("crane", "support", A, "multiClause", "Crane used."))],
    [S("A DJI Matrice 600 carried a Panavision DXL2 for the opening descent into the pit, the heaviest payload the drone team had flown.",
       C("DJI Matrice 600", "support", A, "payload", "Drone used."),
       C("Panavision DXL2", "camera", A, "payload", "Camera payload."))],
    [S("The family’s old Leica M3 on the mantelpiece is a prop, although Arkwright had the art department load it so the actor could take stills between takes.",
       C("Leica M3", "camera", R, "prop", "Prop; stills between takes are not the film's photography."))],
    [S("For the house interiors, Nyambura bounced Joker 1600s into unbleached muslin, a technique he borrowed from his gaffer’s commercials work.",
       C("Joker 1600", "lighting", A, "relativeClauseThisFilm", "Used on this film; the trailing phrase names the technique's origin."))],
])

page(pvc("quarry-light-dust"), PVC, "Quarry Light: Shooting in the Dust", 9210, [], failure="unavailable")

# ---------------------------------------------------------------- 9211 Tinderbox Psalm
film(9211, "Tinderbox Psalm", 2025, "Hollis Varga",
     [("Director", "Hollis Varga"), ("Director of Photography", "Priya Lindqvist"), ("Colorist", "Joaquim Brandt")],
     [
      ["Tinderbox Psalm is a 2025 drama directed by Hollis Varga.",
       S("Priya Lindqvist shot it on the Sony Venice 2 with Cooke S7/i Full Frame Plus primes.",
         C("Sony Venice 2", "camera", A, "direct", "Camera stated."),
         C("Cooke S7/i", "lens", A, "direct", "Lenses stated."))],
      [S("Unlike Varga’s previous film, Ninefold, which was shot on 35mm with Panavision C-Series anamorphics, Tinderbox Psalm is spherical and digital.",
         C("35mm", "format", R, "comparison", "Ninefold's format.", about=False),
         C("Panavision C-Series", "lens", R, "comparison", "Ninefold's lenses.", about=False))],
     ],
     [pvc("tinderbox-psalm-rialto"), ll("priya-lindqvist-notebook"), pvc("joaquim-brandt-grading-notes")])

page(pvc("tinderbox-psalm-rialto"), PVC, "Tinderbox Psalm and the Rialto", 9211, [
    [S("Tinderbox Psalm made heavy use of the Venice 2’s Rialto extension system, which lets the sensor block be separated from the camera body by up to 18 feet.",
       C("Rialto extension", "support", A, "capabilityAndUse", "Heavy use stated; the relative clause is capability.")),
     S("The Rialto can also be paired with underwater housings, though the production did not need one.",
       C("underwater housing", "support", R, "capability", "Capability; explicitly not needed."))],
    [S("“If we’d had another week, I would have shot the baptism on a Phantom 4K,” Lindqvist says.",
       C("Phantom 4K", "camera", R, "hypothetical", "Counterfactual."))],
    [S("Lindqvist’s grade used a film-emulation LUT based on Kodak 2383 print stock, so audiences who think the film was printed are not far wrong in spirit.",
       C("film-emulation LUT", "finish", A, "emulation", "The LUT was used in the grade."),
       C("Kodak 2383", "stock", R, "emulation", "Print stock was only emulated."))],
    [S("Camera equipment was provided by Panavision UK and lighting by Cinelease.",
       C("Panavision", "camera", X, "vendorCredit", "Vendor only."),
       C("Cinelease", "lighting", X, "vendorCredit", "Vendor only."))],
])

page(ll("priya-lindqvist-notebook"), LL, "Priya Lindqvist’s Notebook", 9211, [
    "Priya Lindqvist kept a notebook throughout Tinderbox Psalm.",
    [S("For the revival tent she used a ring of Mole-Richardson Baby Juniors on dimmers.",
       C("Mole-Richardson Baby Junior", "lighting", A, "incompletePage", "Complete sentence states use on a truncated page.")),
     S("She also mentions a Wendy light, though the entry breaks off before saying where it went.",
       C("Wendy light", "lighting", X, "incompletePage", "Mentioned, but the truncated entry does not say it was used.")),
     "The tent scenes were then"],
], failure="incomplete")

# ---------------------------------------------------------------- 9213 Ash & Lanolin
film(9213, "Ash & Lanolin", 2024, "Petra Szabo-Quinn",
     [("Director", "Petra Szabo-Quinn"), ("Director of Photography", "Callum Ferreira-Holt"), ("Colorist", "Ilse Marrow")],
     [
      ["Ash & Lanolin is a 2024 rural drama about sheep farmers in the Welsh borders, directed by Petra Szabo-Quinn.",
       S("It was shot by Callum Ferreira-Holt on Super 16 with an Aaton Xtera and Kodak Vision3 7219.",
         C("Super 16", "format", A, "direct", "Format stated."),
         C("Aaton Xtera", "camera", A, "direct", "Camera stated."),
         C("Kodak Vision3 7219", "stock", A, "direct", "Stock stated."))],
      [S("The film was projected at 1.66:1 in cinemas, and a 2025 streaming remaster retained that frame.",
         C("1.66:1", "aspect", A, "aspectStage", "Theatrical ratio.", st="theatrical"))],
     ],
     [ac("ash-lanolin-lambing-season"), pvc("three-grades-ilse-marrow"), ll("ash-lanolin-festival-qa")])

page(ac("ash-lanolin-lambing-season"), AC, "Lambing Season: Ash & Lanolin", 9213, [
    [S("Ferreira-Holt had hoped to shoot the lambing scenes on 35mm for extra resolution, but the budget would not stretch to it.",
       C("35mm", "format", R, "abandonedPlan", "Hoped for, not done."))],
    [S("Everything was handheld, a documentary style that Ferreira-Holt achieved by operating the Xtera on his shoulder for all 28 days.",
       C("handheld", "movement", A, "styleUsed", "Style literally achieved handheld."))],
    [S("He tested a Zeiss Super Speed set alongside Cooke Panchro 16s, and the Super Speeds went on to be used for the whole film.",
       C("Zeiss Super Speed", "lens", A, "adoptedTest", "Test winner used for whole film."),
       C("Cooke Panchro 16", "lens", R, "testOnly", "Lost the test."))],
    [S("No artificial light was used except a single Arri 650 Fresnel in the lambing shed, so no HMIs, no LED panels and no reflectors.",
       C("Arri 650 Fresnel", "lighting", A, "denialException", "The exception."),
       C("HMI", "lighting", R, "denialException", "Listed as not used."),
       C("LED panels", "lighting", R, "denialException", "Listed as not used."))],
    [S("The 1950s Rolleiflex that the grandmother uses in the photo scene is a family heirloom of the director.",
       C("Rolleiflex", "camera", R, "prop", "Prop."))],
    [S("If the film had been funded by a streamer, Ferreira-Holt says, it would almost certainly have been shot on a Sony FX9.",
       C("Sony FX9", "camera", R, "hypothetical", "Counterfactual."))],
])

# ---------------------------------------------------------------- 9214 Starling Debt
film(9214, "Starling Debt", 2023, "Rhiannon Achterberg",
     [("Director", "Rhiannon Achterberg"), ("Director of Photography", "Jovan Pelletier"), ("Gaffer", "Ewan Strick")],
     [
      ["Starling Debt is a 2023 crime drama directed by Rhiannon Achterberg.",
       S("Jovan Pelletier shot the film on a Red V-Raptor 8K VV with Leica Thalia lenses.",
         C("Red V-Raptor 8K VV", "camera", A, "direct", "Camera stated."),
         C("Leica Thalia", "lens", A, "direct", "Lenses stated."))],
      [S("Reports that the car chase was shot with an IMAX camera are unfounded, according to Pelletier.",
         C("IMAX", "camera", R, "denial", "Rumour explicitly denied.")),
       S("Its theatrical aspect ratio was 2.39:1, extracted from a 17:9 capture.",
         C("2.39:1", "aspect", A, "aspectStage", "Theatrical ratio.", st="theatrical"),
         C("17:9", "aspect", A, "aspectStage", "Capture ratio.", st="capture"))],
     ],
     [pvc("chasing-starling-debt"), ac("starling-debt-night-shoots")])

page(pvc("chasing-starling-debt"), PVC, "Chasing Starling Debt", 9214, [
    [S("The chase was covered from a pursuit vehicle with an Ultimate Arm carrying a V-Raptor on a Flight Head.",
       C("Ultimate Arm", "support", A, "payload", "Arm on the pursuit vehicle."),
       C("V-Raptor", "camera", A, "payload", "Camera on the arm."),
       C("Flight Head", "support", A, "payload", "Head on the arm.")),
     S("A second V-Raptor was hard-mounted to the hero car’s bonnet, the kind of rig Pelletier has also used on his car commercials.",
       C("hard mount", "support", A, "multiClause", "Hard mount used here; the appositive mentions other work."))],
    [S("It has been widely reported that a Sony Venice 2 was used for the night car interiors, but neither Pelletier nor the rental house has confirmed it.",
       C("Sony Venice 2", "camera", X, "rumour", "Reported but unconfirmed."))],
    [S("Pelletier describes the night look as “sodium noir,” and the style was entirely practical: the crew relit two miles of road with 1.2K HMIs gelled with Lee 179 Chrome Orange.",
       C("1.2K HMI", "lighting", A, "styleUsed", "Named style built with real lamps."),
       C("Lee 179 Chrome Orange", "lighting", A, "styleUsed", "Gel used."))],
    [S("Some crew members estimate that as many as eleven cameras rolled on the bridge crash, possibly including a Phantom Flex4K.",
       C("Phantom Flex4K", "camera", X, "estimate", "Crew estimate with 'possibly'."))],
])

# ---------------------------------------------------------------- 9216 Halfway to Oxbow
film(9216, "Halfway to Oxbow", 2025, "Imre Castellanos",
     [("Director", "Imre Castellanos"), ("Director of Photography", "Greer Abernathy"), ("Colorist", "Mira Ostrander")],
     [
      ["Halfway to Oxbow is a 2025 American road movie directed by Imre Castellanos.",
       S("Greer Abernathy shot it on the ARRI Alexa Mini LF and an Alexa 35, with a set of rehoused Canon K35s.",
         C("ARRI Alexa Mini LF", "camera", A, "direct", "Camera stated."),
         C("Alexa 35", "camera", A, "direct", "Camera stated."),
         C("Canon K35", "lens", A, "direct", "Lenses stated."))],
      [S("The film was shot open gate and finished at 2.39:1 for theatrical release, with a 1.90:1 version for IMAX venues.",
         C("open gate", "aspect", A, "aspectStage", "Capture mode.", st="capture"),
         C("2.39:1", "aspect", A, "aspectStage", "Theatrical ratio.", st="theatrical"),
         C("1.90:1", "aspect", A, "aspectStage", "IMAX theatrical ratio.", st="theatrical")),
       S("Its Alexa 35 cameras were supplied by ARRI Rental.",
         C("Alexa 35", "camera", A, "vendorCredit", "Vendor credit that names the equipment."))],
     ],
     [ac("halfway-to-oxbow-on-the-road"), cs("halfway-to-oxbow"), ll("overheard-festival-season-2025")])

page(ac("halfway-to-oxbow-on-the-road"), AC, "On the Road: Greer Abernathy on Halfway to Oxbow", 9216, [
    "AC: How much of the driving was real?",
    [S("Abernathy: All of it, which meant a Shotover F1 on a camera car for the desert stretches and a Mini LF on a hostess tray for the interiors.",
       C("Shotover F1", "support", A, "payload", "Stabilised head on the camera car."),
       C("hostess tray", "support", A, "payload", "Mount for car interiors."))],
    "AC: Did you ever consider an LED volume?",
    [S("Abernathy: We priced an LED volume for the night driving, but we never went near one.",
       C("LED volume", "lighting", R, "abandonedPlan", "Priced, never used."))],
    "AC: How did you light the night interiors of the car?",
    [S("Abernathy: With a couple of Astera Helios Tubes on the dashboard, set to a sodium colour, and that’s it.",
       C("Astera Helios Tube", "lighting", A, "direct", "Lights used."))],
    "AC: People compare the film’s look to Ektachrome slides.",
    [S("Abernathy: That’s the grade; Mira built a reversal-film look with a print emulation, but nothing was shot on reversal.",
       C("reversal film", "stock", R, "emulation", "Look emulated; denial of reversal stock."))],
    "AC: Any filtration?",
    [S("Abernathy: I keep a set of Glimmerglass filters on every job, and on Oxbow I used the 1/2 on almost every desert shot.",
       C("Glimmerglass", "filter", A, "habitual", "Habit plus explicit use on this film."))],
])

# ---------------------------------------------------------------- 9217 Copperhead Vespers
film(9217, "Copperhead Vespers", 2024, "Nell Okonkwo-Barr",
     [("Director", "Nell Okonkwo-Barr"), ("Director of Photography", "Ansel Ruiz-Tamm")],
     [
      ["Copperhead Vespers is a 2024 Southern Gothic thriller directed by Nell Okonkwo-Barr.",
       S("Ansel Ruiz-Tamm photographed it on Kodak Vision3 500T 5219, which he pushed one stop for the night revival scenes.",
         C("Kodak Vision3 500T 5219", "stock", A, "direct", "Stock stated."),
         C("push processing", "finish", A, "direct", "Pushed one stop."))],
      [S("Ruiz-Tamm has said he reaches for Kodak Double-X 5222 whenever a project calls for black and white.",
         C("Kodak Double-X 5222", "stock", X, "habitual", "General habit; this sentence does not tie it to the film."))],
     ],
     [ac("copperhead-vespers-revival-light")])

page(ac("copperhead-vespers-revival-light"), AC, "Revival Light: Copperhead Vespers", 9217, [
    [S("Ruiz-Tamm shot with a Panavision Panaflex Gold II and a set of Panavision Super Speeds, which he describes as the lenses he grew up on.",
       C("Panavision Panaflex Gold II", "camera", A, "direct", "Camera stated."),
       C("Panavision Super Speed", "lens", A, "direct", "Lenses stated.")),
     S("Unlike his previous feature, Saint Halyard, which used an Alexa LF throughout, Copperhead Vespers was shot entirely on film.",
       C("Alexa LF", "camera", R, "comparison", "Saint Halyard's camera.", about=False),
       C("film", "format", A, "comparison", "Main clause: this film shot on film."))],
    [S("The two dream sequences were shot differently, one on Double-X 5222 and the other on Ektachrome 100D, cross-processed.",
       C("Kodak Double-X 5222", "stock", A, "positiveAlternative", "One dream sequence."),
       C("Kodak Ektachrome 100D", "stock", A, "positiveAlternative", "The other dream sequence."))],
    [S("The revival tent was lit with a single 18K HMI bounced into the canvas roof, with tungsten practicals on Socapex runs for the hymnals.",
       C("18K HMI", "lighting", A, "multiClause", "Key source."),
       C("tungsten practicals", "lighting", A, "multiClause", "Practicals."))],
    [S("Push processing means rating the film at a higher speed than its nominal sensitivity and then extending development time to compensate.",
       C("push processing", "finish", R, "definition", "Definition only."))],
    [S("One of Okonkwo-Barr’s decisions was to shoot the snake-handling sequence with a Steadicam rather than handheld, so that the camera would never seem to flinch.",
       C("Steadicam", "support", A, "retrospectiveDecision", "Decision carried out."),
       C("handheld", "movement", R, "retrospectiveDecision", "Rejected alternative."))],
    [S("The production also tested a 2x anamorphic set from Hawk, but it was never used on the shoot.",
       C("Hawk anamorphic", "lens", R, "testOnly", "Tested, never used."))],
])

# ---------------------------------------------------------------- 9218 Sleeping Dogs
film(9218, "A Map of Sleeping Dogs", 2023, "Florian Mbatha",
     [("Director", "Florian Mbatha"), ("Director of Photography", "Kirsi Hallward")],
     [
      ["A Map of Sleeping Dogs is a 2023 Finnish-South African co-production directed by Florian Mbatha.",
       S("Kirsi Hallward shot it on the Sony Venice with Atlas Orion anamorphic lenses.",
         C("Sony Venice", "camera", A, "direct", "Camera stated."),
         C("Atlas Orion", "lens", A, "direct", "Lenses stated."))],
      [S("The film was framed for 2.39:1, but its Blu-ray release is presented at 1.78:1 from an open-matte transfer.",
         C("2.39:1", "aspect", A, "aspectStage", "Framing ratio.", st="framing"),
         C("1.78:1", "aspect", A, "aspectStage", "Blu-ray ratio.", st="homeMedia"))],
     ],
     [pvc("kirsi-hallward-sleeping-dogs"), cs("a-map-of-sleeping-dogs")])

page(pvc("kirsi-hallward-sleeping-dogs"), PVC, "Kirsi Hallward on A Map of Sleeping Dogs", 9218, [
    "PVC: What camera did you choose?",
    [S("Hallward: The original Venice, mostly because I already owned one, and the Venice 2 wasn’t out yet when we prepped.",
       C("Sony Venice", "camera", A, "direct", "Camera chosen."),
       C("Venice 2", "camera", R, "denial", "Not yet available."))],
    "PVC: Were the snow scenes shot on film? They have that texture.",
    [S("Hallward: No, there’s no film anywhere in it; that grain comes from a FilmConvert emulation in the grade.",
       C("film", "format", R, "denial", "Explicit denial."),
       C("FilmConvert", "finish", A, "emulation", "Emulation tool actually used."))],
    "PVC: Was the Johannesburg footage shot with the same package?",
    [S("Hallward: Other than a Canon C70 we used for the minibus scenes, yes, it was all the Venice.",
       C("Canon C70", "camera", A, "denialException", "The exception was used."))],
    "PVC: Would you ever go back to the Orion set?",
    [S("Hallward: I used them on a commercial last month, and I’d take them on any film that needs that flare.",
       C("Atlas Orion", "lens", X, "habitual", "Other work and general preference."))],
])

page(cs("a-map-of-sleeping-dogs"), CS, "A Map of Sleeping Dogs", 9218, [], failure="unavailable")

# ---------------------------------------------------------------- 9219 Glasswort
film(9219, "Glasswort", 2021, "Esme Varadi",
     [("Director", "Esme Varadi"), ("Director of Photography", "Theo Lindgren-Achebe")],
     [
      ["Glasswort is a 2021 coming-of-age film directed by Esme Varadi and set on a salt marsh in Essex.",
       S("Theo Lindgren-Achebe shot it on 35mm with an Arricam ST and Cooke S4/i lenses.",
         C("35mm", "format", A, "direct", "Format stated."),
         C("Arricam ST", "camera", A, "direct", "Camera stated."),
         C("Cooke S4/i", "lens", A, "direct", "Lenses stated."))],
      [S("The film was captured in 4-perf and released at 1.85:1.",
         C("4-perf", "format", A, "direct", "Capture format."),
         C("1.85:1", "aspect", A, "aspectStage", "Release ratio.", st="theatrical")),
       S("A 2026 4K restoration supervised by Lindgren-Achebe reframed the film to 2.00:1 for a festival re-release.",
         C("2.00:1", "aspect", A, "aspectStage", "Restoration ratio.", st="restoration"))],
     ],
     [ac("glasswort-marsh-light"), pvc("glasswort-second-unit")])

page(ac("glasswort-marsh-light"), AC, "Marsh Light: Glasswort", 9219, [
    [S("Lindgren-Achebe’s main stock was Kodak Vision3 250D 5207 for the marsh days, though he admits he is not familiar with the Fuji Eterna stock the second unit may have used for pickups.",
       C("Kodak Vision3 250D 5207", "stock", A, "multiClause", "Main stock."),
       C("Fuji Eterna", "stock", X, "unfamiliarStock", "Unfamiliar and 'may have used'."))],
    [S("He says that, had the money existed, he would have shot the whole film on 65mm.",
       C("65mm", "format", R, "hypothetical", "Counterfactual."))],
    [S("The marsh scenes were lit with nothing but a 20×20 frame of Ultrabounce and the sun.",
       C("Ultrabounce", "lighting", A, "direct", "Only source besides the sun."))],
    [S("A Steadicam was booked for the chase but, after rehearsals, the scene was shot handheld instead.",
       C("Steadicam", "support", R, "abandonedPlan", "Booked but replaced."),
       C("handheld", "movement", A, "multiClause", "Actual method."))],
    [S("The kite camera that the boy builds is a working prop made from a broken Polaroid SX-70.",
       C("Polaroid SX-70", "camera", R, "prop", "Prop."))],
    [S("“I’d guess the 40mm was on the camera for most of the film,” Lindgren-Achebe says.",
       C("40mm", "lens", A, "estimate", "Use stated; only the proportion is guessed.")),
     S("He estimates the production may have burned through around 40,000 feet of 5219 on the night work, though the lab records were lost.",
       C("Kodak Vision3 500T 5219", "stock", X, "estimate", "Uncertain estimate with 'may have'."))],
])

# ---------------------------------------------------------------- 9220 Paper Lanterns
film(9220, "Paper Lanterns, Iron Bells", 2025, "Ruben Castile",
     [("Director", "Ruben Castile"), ("Director of Photography", "Maren Tull")],
     [
      ["Paper Lanterns, Iron Bells is a 2025 historical epic directed by Ruben Castile.",
       S("Maren Tull shot the film on the ARRI Alexa 65 and on IMAX 15/65mm film for six key sequences.",
         C("ARRI Alexa 65", "camera", A, "direct", "Camera stated."),
         C("IMAX 15/65mm", "format", A, "direct", "Format for six sequences."))],
      [S("Those sequences open up from 2.39:1 to 1.43:1 in IMAX 70mm exhibition.",
         C("1.43:1", "aspect", A, "aspectStage", "Ratio of specific sequences.", st="sequence"))],
     ],
     [ac("paper-lanterns-iron-bells-going-big"), cs("paper-lanterns-iron-bells")])

page(ac("paper-lanterns-iron-bells-going-big"), AC, "Bells and Lanterns: Maren Tull Goes Big", 9220, [
    [S("Tull lit the lantern festival with 3,000 practical paper lanterns, each fitted with a battery LED bulb rather than a candle.",
       C("LED bulb", "lighting", A, "emulation", "Physical light source."),
       C("candle", "lighting", R, "emulation", "Explicitly not used."))],
    [S("Earlier in prep she tested a Panavision Millennium DXL2 against the Alexa 65, and the Alexa 65 was adopted for all the non-IMAX material.",
       C("Panavision Millennium DXL2", "camera", R, "testOnly", "Lost the test."),
       C("Alexa 65", "camera", A, "adoptedTest", "Adopted."))],
    [S("The production would have used IMAX for the whole film if the cameras were quieter, Tull says.",
       C("IMAX", "format", R, "hypothetical", "Counterfactual about the whole film; sentence itself asserts no use."))],
    [S("The IMAX MSM 9802 is a 15-perf 65mm camera weighing more than 50 kilograms.",
       C("IMAX MSM 9802", "camera", R, "capability", "Product description only."))],
    [S("The bell tower sequence was shot from a Technocrane, and a Spidercam carried the Alexa 65 over the crowd.",
       C("Technocrane", "support", A, "multiClause", "Crane used."),
       C("Spidercam", "support", A, "payload", "Cable cam carried the camera."))],
    [S("Rumour on set was that a few crowd shots were grabbed on a Red Komodo by the second unit.",
       C("Red Komodo", "camera", X, "rumour", "Unconfirmed."))],
])

page(cs("paper-lanterns-iron-bells"), CS, "Paper Lanterns, Iron Bells", 9220, [
    "Cinesite delivered 320 shots for Paper Lanterns, Iron Bells, including the full-CG bell foundry.",
    [S("IMAX 15/65 plates were scanned at 8K before our team extended the lantern festival crowd.",
       C("IMAX 15/65", "format", A, "direct", "Plates originated on IMAX 15/65.")),
     S("Lantern light in the CG extensions was matched to the practical LED bulbs used on set.",
       C("LED bulb", "lighting", A, "direct", "Practical bulbs used on set."))],
])

# ---------------------------------------------------------------- extra pages (mostly abstain material)
page(ll("overheard-festival-season-2025"), LL, "Overheard: Festival Season Camera Gossip", None, [
    ["Every festival season brings its own crop of camera-department gossip.",
     "We pass some of it on here, unverified and with the usual caveats."],
    [S("On Cinderwick, word in the lobby was that some sky-city plates were shot on a Phantom Flex4K after all, though Ashworth’s team would not comment.",
       C("Phantom Flex4K", "camera", X, "rumour", "Lobby gossip; no comment from the crew.", film=9207))],
    [S("On Tinderbox Psalm, a visitor to the set claims the revival scenes used 1960s Fresnel units bought at auction, which we could not verify.",
       C("1960s Fresnel units", "lighting", X, "rumour", "Unverified visitor claim.", film=9211))],
    [S("On Halfway to Oxbow, a grip told us the production may have borrowed a Black Arm for a single sequence.",
       C("Black Arm", "support", X, "rumour", "Hearsay with 'may have'.", film=9216))],
    [S("On …And the Orchard Burned, crew chatter put the number of burn nights at four, with perhaps a Phantom on standby.",
       C("Phantom", "camera", X, "rumour", "'Perhaps on standby' is neither use nor denial.", film=9203))],
])

page(pvc("joaquim-brandt-grading-notes"), PVC, "Grading Notes: Joaquim Brandt", 9211, [
    "Joaquim Brandt has graded more than forty features, most recently Tinderbox Psalm.",
    [S("Brandt tends to start every grade from a Kodak 2383 print emulation, although he did not say whether he did so on Tinderbox Psalm.",
       C("Kodak 2383 print emulation", "finish", X, "habitual", "Habit; explicitly unstated for this film.")),
     S("He could not remember whether the Tinderbox Psalm dailies were handled in Baselight or in Resolve.",
       C("Baselight", "finish", X, "uncertain", "Speaker unsure between two tools."),
       C("DaVinci Resolve", "finish", X, "uncertain", "Speaker unsure between two tools."))],
    "He is currently grading a documentary about lighthouse keepers.",
])

page(ac("bram-holloway-tungsten"), AC, "Bram Holloway Keeps It Tungsten", 9204, [
    [S("Gaffer Bram Holloway usually works with a dirty tungsten package of Mole-Richardson Baby Juniors and Tweenies.",
       C("Mole-Richardson Baby Junior", "lighting", X, "habitual", "General practice, no film named."))],
    [S("He could not remember whether a Tweenie was used anywhere on Winter’s Ledger.",
       C("Tweenie", "lighting", X, "uncertain", "Speaker cannot remember."))],
    "Holloway started as a spark on television dramas in Leeds.",
])

page(cs("halfway-to-oxbow"), CS, "Halfway to Oxbow", 9216, [
    "Cinesite delivered 64 shots for Halfway to Oxbow, mostly sky replacements and road clean-up.",
    [S("Judging by the camera reports we received, most plates appear to have been shot open gate.",
       C("open gate", "aspect", X, "estimate", "Vendor inference from reports, hedged with 'appear to'.", st="capture"))],
])

page(pvc("glasswort-second-unit"), PVC, "The Glasswort Pickups", 9219, [
    "Glasswort’s second unit spent five days on the marsh after the main shoot wrapped.",
    [S("The second unit’s camera was either an Arriflex 435 or a 535, and the surviving records disagree.",
       C("Arriflex 435", "camera", X, "uncertain", "Records disagree."),
       C("Arriflex 535", "camera", X, "uncertain", "Records disagree."))],
])

page(ac("saint-halyard-ruiz-tamm-digital"), AC, "Saint Halyard: Ansel Ruiz-Tamm Goes Digital", None, [
    "Saint Halyard is a shipyard drama shot in Gdańsk and Newcastle.",
    [S("Ruiz-Tamm, whose credits include Copperhead Vespers, shot Saint Halyard on an Alexa LF with ARRI Signature Primes.",
       C("Alexa LF", "camera", R, "creditListMention", "Gear belongs to Saint Halyard.", film=9217, about=False)),
     S("The yard’s night exteriors were lit with a Condor-mounted Arri M90.",
       C("Arri M90", "lighting", R, "otherProduction", "Saint Halyard's lighting.", film=9217, about=False))],
])

page(ac("starling-debt-night-shoots"), AC, "Night Shoots on Starling Debt", 9214, [], failure="unavailable")
page(ll("brambling-polytunnel-diaries"), LL, "The Polytunnel Diaries", 9201, [], failure="unavailable")

page(ll("pennyroyal-lund-interview"), LL, "Saoirse Lund on Pennyroyal", 9206, [
    "Saoirse Lund grew up two miles from the farmhouse where Pennyroyal was shot.",
    [S("She thinks the dream sequence might have been shot through a Petzval lens, but says Obuya would know better.",
       C("Petzval", "lens", X, "uncertain", "Director unsure."))],
])

page(ll("ash-lanolin-festival-qa"), LL, "Ash & Lanolin: Festival Q&A", 9213, [
    [S("Asked whether any of the film was shot on 35mm, Szabo-Quinn said she could not remember the exact split.",
       C("35mm", "format", X, "uncertain", "Director cannot remember; not a denial.")),
     S("Ferreira-Holt reportedly carried a Bolex for pickups.",
       C("Bolex", "camera", X, "rumour", "'Reportedly'."))],
])

# ---------------------------------------------------------------- searches
SEARCHES = []
def search(provider, query, urls):
    pt = {p["url"]: p["title"] for p in PAGES}
    SEARCHES.append({"provider": provider, "query": query,
                     "hits": [{"title": pt[u], "url": u} for u in urls]})

# Cinesite by title
for fid, slug in [(9202, "the-saltmarrow-hours"), (9203, "and-the-orchard-burned"), (9207, "cinderwick"),
                  (9215, "driftglass"), (9216, "halfway-to-oxbow"), (9218, "a-map-of-sleeping-dogs"), (9220, "paper-lanterns-iron-bells")]:
    search(CS, TITLE[fid], [cs(slug)])
for fid in [9201, 9204, 9205, 9206, 9208, 9209, 9210, 9211, 9212, 9213, 9214, 9217, 9219]:
    search(CS, TITLE[fid], [])
# AC / PVC by crew name
search(AC, "Tobiah Okafor", [ac("brambling-wet-season")])
search(PVC, "Ilse Marrow", [pvc("three-grades-ilse-marrow")])
search(AC, "Ruth Adebayo-Lind", [ac("ruth-adebayo-lind-salt-and-shadow")])
search(PVC, "Ruth Adebayo-Lind", [pvc("undertow-parish-flood-light")])
search(PVC, "Joss Penhale", [pvc("undertow-parish-flood-light")])
search(AC, "Halvard Mbeki", [ac("first-light-debut-features")])
search(AC, "Casimir Tran", [ac("first-light-debut-features")])
search(PVC, "Casimir Tran", [pvc("casimir-tran-sixteen")])
search(AC, "Yuki Delacroix-Hart", [ac("lowtide-fugue-tidal-logic"), ac("first-light-debut-features")])
search(PVC, "Marek Obuya", [pvc("pennyroyal-small-camera-big-dread"), ll("pennyroyal-lund-interview")])
search(AC, "Ewan Strick", [ac("copper-psalter-candle-logic")])
search(PVC, "Teodor Ashworth", [pvc("teodor-ashworth-going-large")])
search(AC, "Wren Halvorsen", [ac("wren-halvorsen-faking-it-honestly")])
search(PVC, "Mira Ostrander", [pvc("gear-notes-hollow-bell")])
search(AC, "Elif Marchetti", [ac("moth-parliament-in-chamber")])
search(AC, "Oskar Nyambura", [ac("quarry-light-cut-from-stone")])
search(PVC, "Oskar Nyambura", [pvc("quarry-light-dust")])
search(PVC, "Priya Lindqvist", [pvc("tinderbox-psalm-rialto")])
search(AC, "Callum Ferreira-Holt", [ac("ash-lanolin-lambing-season")])
search(PVC, "Jovan Pelletier", [pvc("chasing-starling-debt"), ac("starling-debt-night-shoots")])
search(AC, "Greer Abernathy", [ac("halfway-to-oxbow-on-the-road"), cs("halfway-to-oxbow"), ll("overheard-festival-season-2025")])
search(AC, "Ansel Ruiz-Tamm", [ac("copperhead-vespers-revival-light"), ac("saint-halyard-ruiz-tamm-digital")])
search(PVC, "Kirsi Hallward", [pvc("kirsi-hallward-sleeping-dogs")])
search(AC, "Theo Lindgren-Achebe", [ac("glasswort-marsh-light"), pvc("glasswort-second-unit")])
search(AC, "Maren Tull", [ac("paper-lanterns-iron-bells-going-big")])
search(AC, "Mateus Kerridge", [])
search(PVC, "Joaquim Brandt", [pvc("joaquim-brandt-grading-notes")])
search(AC, "Bram Holloway", [ac("bram-holloway-tungsten")])
search(PVC, "Theo Lindgren-Achebe", [pvc("glasswort-second-unit")])
search(AC, "Jovan Pelletier", [ac("starling-debt-night-shoots")])


# ---------------------------------------------------------------- label selection
# Every sentence above was annotated generously; to keep the scored set near the
# target size and outcome mix, routine accept labels are thinned deterministically:
# at most one accept per (passage, film) except where several accepts are the point
# of the item, one non-aspect accept per even-numbered film's own article, at most
# one plain 'direct' accept per page, and at most four theatrical-stage aspect accepts.
MULTI = {"positiveAlternative", "denialException", "payload"}
def _select(claims):
    keep, perpass, seen, theat = [], {}, set(), 0
    for x in claims:
        if x["expected"] == "accept":
            k = (x["passage"], x["film"])
            if perpass.get(k, 0) >= 1 and x["evidenceType"] not in MULTI:
                continue
            if x["source"].startswith("article:") and x["property"] != "aspect":
                if x["film"] % 2 or ("art", x["film"]) in seen:
                    continue
                seen.add(("art", x["film"]))
            if x["evidenceType"] == "direct" and not x["source"].startswith("article:"):
                if x["source"] in seen:
                    continue
                seen.add(x["source"])
            if x.get("stage") == "theatrical":
                theat += 1
                if theat > 4:
                    continue
            perpass[k] = perpass.get(k, 0) + 1
        keep.append(x)
    return keep
CLAIMS[:] = _select(CLAIMS)

for i, c in enumerate(CLAIMS, 1):
    c["id"] = "v%03d" % i

with open(OUT, "w", encoding="utf-8") as f:
    json.dump({"films": FILMS, "pages": PAGES, "searches": SEARCHES, "claims": CLAIMS},
              f, ensure_ascii=False, indent=1)
print("films", len(FILMS), "pages", len(PAGES), "claims", len(CLAIMS))
