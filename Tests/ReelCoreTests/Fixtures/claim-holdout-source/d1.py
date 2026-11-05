from fw import *

# ===================== A: Kettle / Gannet Point (DP Marten Hollis) =====================
A1 = "https://www.kodak.com/en/motion/blog-post/kettle-marten-hollis/"
A2 = "https://theasc.com/articles/kettle-domestic-tension/"
A3 = "https://britishcinematographer.co.uk/gannet-point-marten-hollis/"
A4 = "https://www.provideocoalition.com/colorist-sami-kaltenbrunn-tollkeepers-kettle/"
A5 = "https://variety.com/2023/film/news/kettle-ines-volkaert-interview-1235550001/"
R1 = "https://www.indiewire.com/features/craft/best-cinematography-2023-1234901177/"

F(9001, KET, 2023, "Ines Volkaert",
  [("Director of Photography", "Marten Hollis"), ("Gaffer", "Ruth Abernethy"),
   ("Colorist", "Sami Kaltenbrunn"), ("Key Grip", "Dov Ashworth")],
  [
   ["Kettle was shot over twenty-six days in a coastal town in Northumberland during the spring of 2022.",
    C("Cinematographer Marten Hollis photographed the film on 35mm using an Arricam LT, with Cooke S4 lenses for most interiors.",
      k("35mm", "format", A, "positive"),
      k("Arricam LT", "camera", A, "physicalGear"),
      k("Cooke S4", "lens", A, "positive"))],
   [C("The production avoided Steadicam entirely, relying on a dolly and handheld work in the cramped kitchen set.",
      k("Steadicam", "support", R, "mixed", why="Mixed sentence: Steadicam is explicitly avoided while dolly/handheld were used."),
      k("dolly", "support", A, "mixed"),
      k("handheld", "movement", A, "positive")),
    "A dented kettle, bought at a flea market in Hexham, became the film's central prop.",
    C("The glowing LED panels on the futuristic fridge in the dream sequence were built by the art department as props.",
      k("LED panels", "lighting", R, "environment"))],
  ],
  [A1, A5, R1])

F(9028, GP, 2022, "Corran Aske",
  [("Director of Photography", "Marten Hollis"), ("Camera Operator", "Lys Petrakova"),
   ("Colorist", "Sami Kaltenbrunn")],
  [], [A1, A3])

P(A1, "Kodak", "Kettle: Marten Hollis on the warmth of 35mm", KET, [
  ["Marten Hollis had wanted to shoot on film since he first read Ines Volkaert's script for Kettle.",
   C("Together they chose Kodak Vision3 500T for the interiors and Kodak Vision3 250D for the few exteriors on the harbour.",
     k("Kodak Vision3 500T", "stock", A, "positive"),
     k("Kodak Vision3 250D", "stock", A, "positive"))],
  ["Q: Did you test digital at all?",
   C("Hollis: We shot a day of tests on an ARRI Alexa Mini alongside the film camera, but it was never a serious contender.",
     k("ARRI Alexa Mini", "camera", R, "adoptedTest")),
   C("The negative was processed at Cinelab and scanned at 4K, while the grade was done at Company 3 with Sami Kaltenbrunn.",
     k("Company 3", "finish", A, "positive")),
   C("Somewhere along the way we also borrowed a Zeiss Ultra Prime set from a friend, though I'm not sure it was ever on the camera.",
     k("Zeiss Ultra Prime", "lens", X, "ambiguous"))],
  [C("Most of the light in the flat came through the windows, supplemented with tungsten units bounced off the ceiling.",
     k("tungsten", "lighting", A, "positive")),
   "Everyone asks about the kettle itself, which sat in nearly every shot; it was a cheap enamel one, and there was no trick to making it steam.",
   C("In the scenes at Moira's bedside we used practicals, probably around 60-watt bulbs, although I honestly can't remember the exact wattage.",
     k("practicals", "lighting", A, "estimated"))],
  [C("On Gannet Point, his previous feature, Hollis had leaned heavily on a Technocrane for the cliff-top scenes.",
     k("Technocrane", "support", R, "multiFilmInterview", about=GP, ctx="Sentence explicitly names Gannet Point, Hollis's previous feature, inside a Kettle piece."),
     k("Technocrane", "support", A, "multiFilmInterview", film=GP, ctx="Sentence explicitly names Gannet Point.")),
   C("There was no room for that kind of equipment in Kettle, and he never used a crane on it.",
     k("crane", "support", R, "denial", ctx="Explicitly about Kettle ('on it' = Kettle).")),
  ],
])

P(A2, "American Cinematographer", "Domestic Tension: Kettle", KET, [
  [C("For Kettle, Hollis and Volkaert framed for 1.85:1, a choice the director describes as “the shape of a doorway.”",
     k("1.85:1", "aspect", A, "positive")),
   C("The streaming release, however, presents the film at 1.78:1 to fill television screens.",
     k("1.78:1", "aspect", R, "delivery"))],
  [C("The filmmakers had planned to shoot the flashbacks on Super 16 but abandoned the idea when the camera package fell through, and the flashbacks were instead photographed on the same 35mm stock through a Black Pro-Mist filter.",
     k("Super 16", "format", R, "abandonedPlan"),
     k("Black Pro-Mist", "filter", A, "mixed"))],
  [C("Unlike Gannet Point, Kettle was finished with a photochemical ENR step on its archival print.",
     k("ENR", "finish", A, "comparison"),
     k("ENR", "finish", R, "comparison", about=KET, film=GP, ctx="'Unlike Gannet Point' contrasts Gannet Point with Kettle."))],
  [C("Hollis credits his mentor, the documentary cameraman Piet Varga, with the habit of always carrying ND filters, which most cinematographers of Varga's generation shared.",
     k("ND filters", "filter", R, "otherPractice")),
   C("Varga shot almost everything on an Arriflex 416 in his later years.",
     k("Arriflex 416", "camera", R, "otherPractice")),
   "A kettle whistles over the opening credits, and Hollis wanted the image to feel equally insistent."],
])

P(A3, "British Cinematographer", "Gannet Point: Marten Hollis on the edge", GP, [
  [C("Gannet Point, Corran Aske's windswept thriller, was shot on the Alexa Mini LF with Panavision Primo lenses.",
     k("Alexa Mini LF", "camera", A, "positive"),
     k("Panavision Primo", "lens", A, "positive")),
   C("Hollis framed the film in 2.39:1.", k("2.39:1", "aspect", A, "positive"))],
  ["Q: The cliff-top sequences are vertiginous. How were they done?",
   C("Hollis: Mostly on a Technocrane parked forty feet from the edge, with Lys Petrakova operating remotely.",
     k("Technocrane", "support", A, "context", ctx="Answer to a question about Gannet Point's cliff-top sequences.")),
   C("We talked about using a drone, but the wind on that headland would have thrown it into the sea.",
     k("drone", "support", R, "counterfactual"))],
  ["Hollis grew up in Sunderland and began as a clapper loader on television documentaries.",
   C("His first credits as cinematographer were music videos shot on Super 8 and a Canon C300 Mark II borrowed from a college friend.",
     k("Super 8", "format", R, "context", ctx="Biography paragraph about Hollis's early music videos."),
     k("Canon C300 Mark II", "camera", R, "context", ctx="Biography paragraph about Hollis's early music videos."))],
  [C("For the night interiors of the lighthouse, the electrical team rigged Astera tubes inside the lantern room.",
     k("Astera tubes", "lighting", A, "positive"))],
])

P(A4, "ProVideo Coalition", "Colorist Sami Kaltenbrunn on grain, film-out and The Tollkeepers", KET, [
  ["Sami Kaltenbrunn has spent the past three years at Company 3 in London, where his recent credits include the series The Tollkeepers and the features Kettle and Gannet Point."],
  ["Q: Kettle was shot on film. What did you do in the grade?",
   C("Kaltenbrunn: Very little. The negative already had the texture, so we did not add any grain, and we built a single LUT from the dailies that carried through to the end.",
     k("LUT", "finish", A, "context", ctx="Answer to a question explicitly about Kettle."))],
  ["Q: And Gannet Point?",
   C("Kaltenbrunn: That was the opposite problem, because it was digital and Corran wanted it to feel like a 1970s print, so we added grain in the grade and did a film-out for the festival copy.",
     k("digital", "format", A, "context", film=GP, ctx="Answer to 'And Gannet Point?'."),
     k("film-out", "finish", R, "delivery", film=GP, ctx="Answer to 'And Gannet Point?'; the film-out is a festival delivery copy."),
     k("digital", "format", R, "context", about=GP, ctx="The question has switched from Kettle to Gannet Point."))],
  [C("On The Tollkeepers, which shot on the Sony Venice 2, Kaltenbrunn simulated anamorphic flares in the grade because the producers had ruled out real anamorphic glass.",
     k("Sony Venice 2", "camera", R, "multiFilmInterview", ctx="Sentence is about the series The Tollkeepers."),
     k("anamorphic", "lens", R, "faux", ctx="Sentence is about the series The Tollkeepers; flares simulated."),
     k("Sony Venice 2", "camera", R, "multiFilmInterview", film=GP, ctx="Sentence is about the series The Tollkeepers."))],
  ["Q: Is there a look you keep returning to?",
   C("Kaltenbrunn: Most colorists I trained with would reach for a bleach bypass emulation whenever a director said 'gritty', and I try hard not to.",
     k("bleach bypass", "finish", R, "otherPractice"))],
])

P(A5, "Variety", "Ines Volkaert on 'Kettle' and the Art of the Small Room", KET, [
  ["Ines Volkaert's second feature premiered in Karlovy Vary to warm reviews."],
  ["The director spoke about casting non-professionals from the town."],
  ["Cinematographer Marten Hollis shot the film on 35mm."],
], failure="unavailable")

# ===================== B: Overpass / Static Bloom (DP Lusine Arkady) =====================
B1 = "https://www.indiewire.com/features/craft/overpass-cinematographer-lusine-arkady-1234890011/"
B2 = "https://theasc.com/articles/lusine-arkady-concrete-and-bloom/"
B3 = "https://nofilmschool.com/steadicam-benedek-saar-interview"
B4 = "https://beforesandafters.com/2024/05/14/static-bloom-greenhouse-vfx/"

F(9002, OVP, 2022, "Dario Fenwick",
  [("Director of Photography", "Lusine Arkady"), ("Steadicam Operator", "Benedek Saar"),
   ("Gaffer", "Owain Pryce")],
  [
   ["Overpass was filmed beneath the Leeds inner ring road over five weeks in autumn 2021.",
    C("The film was shot digitally and framed for 2.39:1, the widest frame director Dario Fenwick had used.",
      k("2.39:1", "aspect", A, "positive"))],
  ],
  [B1, B3])

F(9014, SB, 2024, "Juno Achterberg",
  [("Director of Photography", "Lusine Arkady"), ("Visual Effects Supervisor", "Ravi Lindgaard"),
   ("Gaffer", "Pia Brockhurst")],
  [], [B4])

P(B1, "IndieWire", "How 'Overpass' Found Beauty Under the Motorway", OVP, [
  ["Dario Fenwick's Overpass takes place almost entirely in the shadow of a ring-road flyover, and cinematographer Lusine Arkady wanted the concrete to feel enormous.",
   C("She shot the film on the ARRI Alexa 35 with a set of Atlas Orion anamorphics, framing for 2.39:1.",
     k("ARRI Alexa 35", "camera", A, "positive"),
     k("Atlas Orion", "lens", A, "physicalGear"))],
  [C("“We never used a crane,” Arkady says. “Everything is from the height of a person standing on the pavement.”",
     k("crane", "support", R, "denial")),
   C("For the long walks along the hard shoulder, Benedek Saar operated a Steadicam, which let the camera keep pace with the traffic.",
     k("Steadicam", "support", A, "positive"))],
  [C("Night exteriors relied on the sodium streetlights already on the overpass, supplemented by Creamsource Vortex8 units on lifts dialled to match.",
     k("Creamsource Vortex8", "lighting", A, "physicalGear")),
   C("Arkady had hoped to use Kodak Vision3 500T for the night work, but the budget could not stretch to film and the idea was dropped in pre-production.",
     k("Kodak Vision3 500T", "stock", R, "abandonedPlan"))],
  [C("The LED panels that flicker on the lorry's dashboard were added by the art department and play as part of the scenery.",
     k("LED panels", "lighting", R, "environment"))],
])

P(B2, "American Cinematographer", "Lusine Arkady: Concrete and Bloom", OVP, [
  [C("Lusine Arkady began her career shooting car commercials in France, and on one of them a gimbal shot drifted beneath a motorway overpass in Lyon for nearly a minute.",
     k("gimbal", "support", R, "context", ctx="Biography paragraph about a commercial; 'overpass' here is an ordinary noun, not the film."),
     k("gimbal", "support", R, "context", film=SB, ctx="Biography paragraph about a commercial."))],
  [C("On Overpass she worked almost exclusively with natural light during the day.",
     k("natural light", "lighting", A, "multiFilmInterview"),
     k("natural light", "lighting", R, "multiFilmInterview", about=OVP, film=SB)),
   C("Her follow-up, Static Bloom, was a different animal: a studio picture set in a vast greenhouse, shot on the Sony Venice 2 with Leica Summilux-C lenses.",
     k("Sony Venice 2", "camera", A, "multiFilmInterview", film=SB),
     k("Leica Summilux-C", "lens", A, "multiFilmInterview", film=SB),
     k("Sony Venice 2", "camera", R, "multiFilmInterview", about=SB))],
  ["Q: Did any of the Overpass approach carry over?",
   C("Arkady: The handheld language, yes. We used handheld for every scene inside the greenhouse.",
     k("handheld", "movement", A, "context", film=SB, ctx="The greenhouse is Static Bloom's setting (previous paragraph); the question asks what carried over to the follow-up."),
     k("handheld", "movement", R, "context", about=SB, ctx="The greenhouse scenes belong to Static Bloom, not Overpass.")),
   C("Arkady: There may be one or two drone shots in there; the producers had a unit out on the last week.",
     k("drone", "support", X, "ambiguous", film=SB, ctx="'In there' could refer to either film; speaker hedges ('may be')."),
     k("drone", "support", X, "ambiguous", ctx="'In there' could refer to either film; speaker hedges ('may be')."))],
  [C("Arkady says that, had Static Bloom been shot on 65mm as the studio first suggested, the greenhouse would have looked like a postcard.",
     k("65mm", "format", R, "counterfactual", film=SB)),
   C("The Alexa 65 is, she notes, capable of extraordinary detail in foliage, but she has never owned or rented one.",
     k("Alexa 65", "camera", R, "productClaim", film=SB))],
])

P(B3, "No Film School", "Steadicam Operator Benedek Saar on Walking With Actors", OVP, [
  [C("Benedek Saar has operated Steadicam on more than thirty features, most recently Overpass and Anselm Okafor's Northbound Choir.",
     k("Steadicam", "support", A, "positive", film=NC, ctx="Saar's credits explicitly list Northbound Choir as a Steadicam job."))],
  ["Q: What rig do you fly these days?",
   C("Saar: I own a Steadicam M-2 Volt now, but on Northbound Choir I was still on the older sled, and half the choir scenes ended up on a gimbal anyway because the church aisles were too narrow.",
     k("gimbal", "support", A, "positive", film=NC),
     k("gimbal", "support", R, "multiFilmInterview", about=NC, ctx="Sentence explicitly about Northbound Choir."),
     k("Steadicam M-2 Volt", "support", X, "ambiguous", ctx="He owns it 'now'; unclear whether it was used on Overpass, his most recent film."))],
  ["Q: Overpass has those long walks by the motorway.",
   "Saar: Those were the hardest days of my life, honestly, with lorries passing a metre from the lens and the wind pulling at the sled.",
   C("Saar: We put an ND filter on to hold the shutter where Lusine wanted it.",
     k("ND filter", "filter", A, "context", ctx="Continues the answer to the question about Overpass's motorway walks."))],
  [C("Saar: People think Steadicam operators all want the camera to float, but most of the old-school operators I learned from actually preferred a dolly whenever the floor allowed it.",
     k("dolly", "support", R, "otherPractice"),
     k("dolly", "support", R, "otherPractice", film=NC))],
])

P(B4, "befores & afters", "Growing the greenhouse of Static Bloom", SB, [
  ["Static Bloom's greenhouse was a partial set at Bray, extended digitally by the effects team under supervisor Ravi Lindgaard."],
  [C("The flowers that open in time-lapse were entirely CG, lit by virtual HMI sources matched to the set's real lighting plan.",
     k("HMI", "lighting", R, "vfxCG")),
   C("On set, the crew lit the greenhouse with SkyPanels hung above the glass roof.",
     k("SkyPanels", "lighting", A, "physicalGear"))],
  [C("For the shot that tracks through a single petal, the team built a virtual camera with a simulated split diopter so the bee and the actor's eye could both hold focus.",
     k("virtual camera", "camera", R, "vfxCG"),
     k("split diopter", "lens", R, "faux"))],
  [C("Lindgaard notes that a real split diopter was tested on set but did not make the final cut.",
     k("split diopter", "lens", R, "adoptedTest"))],
])

S("American Cinematographer", "Marten Hollis", [A2])
S("ProVideo Coalition", "Sami Kaltenbrunn", [A4])
S("American Cinematographer", "Lusine Arkady", [B2])
S("ProVideo Coalition", "Benedek Saar", [])

# ===================== C: Lantern / Pilgrim Tide (DP Tobiah Rensch) =====================
C1 = "https://thefilmstage.com/lantern-tobiah-rensch-interview/"
C2 = "https://filmmakermagazine.com/120334-pilgrim-tide-tobiah-rensch/"
C3 = "https://theasc.com/articles/pilgrim-tide-light-on-the-water/"
C4 = "https://www.cinesite.com/projects/lantern/"
C5 = "https://www.cinesite.com/projects/the-lantern-keepers/"

F(9003, LAN, 2024, "Thandiwe Morrow",
  [("Director of Photography", "Tobiah Rensch"), ("Gaffer", "Clemency Oduya"),
   ("Visual Effects Supervisor", "Ravi Lindgaard")],
  [], [C1, C2])

F(9022, PT, 2023, "Nadira Voss",
  [("Director of Photography", "Tobiah Rensch"), ("Key Grip", "Selwyn Pardoe")],
  [], [C2, R1])

P(C1, "The Film Stage", "Tobiah Rensch on the Night Shifts of 'Lantern'", LAN, [
  [C("Thandiwe Morrow's Lantern follows a night-shift nurse through a single winter, and cinematographer Tobiah Rensch shot it on 16mm with an Arriflex 416.",
     k("16mm", "format", A, "positive"),
     k("Arriflex 416", "camera", A, "physicalGear")),
   C("Kodak describes Vision3 500T as its most versatile tungsten-balanced stock.",
     k("Vision3 500T", "stock", R, "productClaim"))],
  ["The Film Stage: Was there ever a digital version of this film?",
   C("Rensch: There was a moment where the financiers wanted it on the RED Komodo, and we shot a test day with it, but Thandiwe hated it and we went back to film.",
     k("RED Komodo", "camera", R, "adoptedTest"))],
  ["The Film Stage: The hospital corridors glow.",
   C("Rensch: That's mostly the existing fluorescent fittings, with Kino Flos tucked into the ceiling where a tube had died.",
     k("Kino Flos", "lighting", A, "context", ctx="Answer to a question about the film's hospital corridors.")),
   C("Rensch: I think the second unit carried a Steadicam for the car park, but I wasn't there.",
     k("Steadicam", "support", X, "ambiguous", ctx="Speaker is unsure and was not present; 'carried' does not establish use."))],
  [C("In one dream sequence, Mara walks past a row of paper lanterns strung over a street market, and Rensch filmed it at magic hour to let the lanterns glow against the dusk.",
     k("magic hour", "lighting", A, "positive", ctx="Page about Lantern; 'lanterns' here is an ordinary noun in the scene description.")),
   C("The lantern of the title is a battered camping lamp Mara carries, and in close-ups its glow was boosted with a small LiteMat hidden behind it.",
     k("LiteMat", "lighting", A, "physicalGear"))],
])

P(C2, "Filmmaker", "Below Deck: Tobiah Rensch on Pilgrim Tide", PT, [
  ["Nadira Voss's Pilgrim Tide reunites her with cinematographer Tobiah Rensch, who last year shot Lantern.",
   C("Just as on Lantern, Rensch shot Pilgrim Tide on 16mm, this time with Zeiss Super Speed lenses.",
     k("16mm", "format", A, "comparison"),
     k("Zeiss Super Speed", "lens", A, "positive"),
     k("Zeiss Super Speed", "lens", R, "comparison", about=PT, film=LAN, ctx="'This time' restricts the lenses to Pilgrim Tide."))],
  ["Q: Pilgrim Tide is mostly at sea.",
   C("Rensch: We were on a fishing trawler for eleven days, all handheld, because a gimbal would have been useless on a deck that was pitching ten degrees.",
     k("handheld", "movement", A, "context", ctx="Answer to a question about Pilgrim Tide."),
     k("gimbal", "support", R, "counterfactual"))],
  [C("Rensch: On Lantern we had a dolly for the corridors, but on the trawler there was nowhere to lay track.",
     k("dolly", "support", R, "multiFilmInterview", about=LAN),
     k("dolly", "support", A, "multiFilmInterview", film=LAN))],
  [C("The film was graded at Light Iron, and the 16mm negative was later scanned at 4K for the archive master.",
     k("Light Iron", "finish", A, "positive"),
     k("4K", "format", R, "delivery"))],
])

P(C3, "American Cinematographer", "Pilgrim Tide: Light on the Water", PT, [
  [C("Rensch lit the trawler's cabin almost entirely with practicals, swapping the boat's fittings for warmer bulbs.",
     k("practicals", "lighting", A, "positive")),
   C("A few pickups were reportedly shot later on a digital camera, though the article's sources disagree.",
     k("digital", "format", X, "ambiguous", ctx="Reported only, sources disagree."))],
  [C("For the storm night, the second unit hung an HMI from the harbour crane to suggest a lighthouse beam sweeping the deck.",
     k("HMI", "lighting", A, "physicalGear"),
     k("crane", "support", R, "environment", ctx="'Harbour crane' is dockside machinery used as a rigging point, not a camera crane."))],
  [C("Rensch says the film might have been shot on 35mm had the trawler's cabin been large enough for an Arricam ST.",
     k("35mm", "format", R, "counterfactual"),
     k("Arricam ST", "camera", R, "counterfactual"))],
  [C("In a sidebar, Rensch recalls that on Lantern the hospital set was lit with Astera tubes as well as the existing fixtures.",
     k("Astera tubes", "lighting", A, "multiFilmInterview", film=LAN),
     k("Astera tubes", "lighting", R, "multiFilmInterview", about=LAN))],
])

P(C4, "Cinesite", "Lantern", LAN, [
  ["Cinesite provided 96 invisible effects shots for Thandiwe Morrow's Lantern, supervised by Ravi Lindgaard."],
  [C("Snowfall in the car park was added digitally and lit in CG to match the sodium practicals visible in the 16mm plates.",
     k("practicals", "lighting", A, "mixed", why="The sodium practicals are real lamps visible in the photographed plates; the CG lighting is not gear."),
     k("16mm", "format", A, "positive"))],
  [C("The studio's work may also have included cleanup on shots photographed with a drone, according to one crew listing.",
     k("drone", "support", X, "ambiguous"))],
])

P(C5, "Cinesite", "The Lantern Keepers", LAN, [
  ["The Lantern Keepers is an eight-part fantasy series for which Cinesite created a lighthouse city and its flying ships."],
  [C("The series was shot on the ARRI Alexa 65 at a studio in Montreal, with Cinesite supervising on set.",
     k("ARRI Alexa 65", "camera", R, "context", ctx="Search hit for 'Lantern' that is about a different production, the series The Lantern Keepers."))],
  [C("Flying-ship plates were captured with a Technocrane against blue screen.",
     k("Technocrane", "support", R, "context", ctx="Page about the series The Lantern Keepers, not the film Lantern."))],
])

S("American Cinematographer", "Tobiah Rensch", [C3])
S("Cinesite", "Lantern", [C4, C5])
