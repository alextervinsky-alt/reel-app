from fw import *
from d1 import R1

# ===================== D: Wait... Then Run / Northbound Choir (DP Celeste Ourada) =====================
D1 = "https://variety.com/2021/artisans/news/wait-then-run-celeste-ourada-1235011223/"
D2 = "https://www.cinesite.com/projects/wait-then-run/"
D3 = "https://www.provideocoalition.com/jun-aldaine-grading-wait-then-run-copper-season/"
D4 = "https://britishcinematographer.co.uk/northbound-choir-celeste-ourada/"

F(9004, WTR, 2021, "Halvard Mung",
  [("Director of Photography", "Celeste Ourada"), ("Visual Effects Supervisor", "Ivo Brennan-Saito"),
   ("Colorist", "Jun Aldaine")],
  [], [D1, D4])

F(9011, NC, 2023, "Anselm Okafor",
  [("Director of Photography", "Celeste Ourada"), ("Steadicam Operator", "Benedek Saar")],
  [], [D4, "https://nofilmschool.com/steadicam-benedek-saar-interview", R1])

P(D1, "Variety", "How 'Wait… Then Run' Kept Its Camera Moving", WTR, [
  ["In “Wait… Then Run,” Halvard Mung's chase thriller, cinematographer Celeste Ourada keeps the camera moving for nearly the whole running time.",
   C("Ourada shot on the RED V-Raptor, which she chose for its high frame rates, mounted on a Libra head for the car-to-car sequences.",
     k("RED V-Raptor", "camera", A, "positive"),
     k("Libra head", "support", A, "physicalGear"))],
  [C("“We decided against anamorphic early on,” she says. “The chase needed edges you could trust.”",
     k("anamorphic", "lens", R, "denial")),
   C("Spherical Zeiss Supreme Prime lenses were used throughout, and the film was framed for 2.00:1.",
     k("Zeiss Supreme Prime", "lens", A, "positive"),
     k("2.00:1", "aspect", A, "positive"))],
  [C("The Sony Venice 2, which the producers had suggested, offers an 8.6K full-frame sensor, according to Sony.",
     k("Sony Venice 2", "camera", R, "productClaim")),
   C("Some reports say parts of the finale were shot on a Technocrane, though Ourada declined to confirm it.",
     k("Technocrane", "support", X, "ambiguous"))],
  [C("Ourada's previous film, the documentary short Ferrymen, was shot entirely on a Blackmagic Pocket.",
     k("Blackmagic Pocket", "camera", R, "multiFilmInterview", ctx="Sentence is about the earlier short Ferrymen."))],
])

P(D2, "Cinesite", "Wait... Then Run", WTR, [
  ["Cinesite delivered 212 shots for Halvard Mung's Wait Then Run, working closely with production VFX supervisor Ivo Brennan-Saito."],
  [C("The highway pile-up was built as a full CG environment, rendered through a virtual camera whose movement was keyed to the real Libra head data.",
     k("virtual camera", "camera", R, "mixed", why="Mixed sentence: the virtual camera is CG; the real Libra head is physical gear."),
     k("Libra head", "support", A, "mixed"))],
  [C("Digital lighting artists relit the burning lorry with CG tungsten sources to match the plates.",
     k("tungsten", "lighting", R, "vfxCG")),
   C("The team also added simulated anamorphic flares to the headlights at the director's request, though the film was shot with spherical lenses.",
     k("anamorphic", "lens", R, "faux"))],
  ["Cinesite's work on the film was completed in 2021 at its London studio."],
])

P(D3, "ProVideo Coalition", "Jun Aldaine on grading Wait... Then Run and The Copper Season", WTR, [
  [C("Colorist Jun Aldaine graded both Wait... Then Run and The Copper Season at Company 3 in Toronto.",
     k("Company 3", "finish", A, "positive"),
     k("Company 3", "finish", A, "positive", film=CS))],
  ["Q: How did you approach Wait... Then Run?",
   C("Aldaine: Celeste gave me a show LUT she had built in prep, and we barely moved away from it.",
     k("LUT", "finish", A, "context", ctx="Answer to a question about Wait... Then Run."))],
  ["Q: The Copper Season looks almost like a bleach bypass print.",
   C("Aldaine: It does, but there was no lab process involved; that bleach bypass look is emulated digitally in the grade.",
     k("bleach bypass", "finish", R, "faux", film=CS, ctx="The question names The Copper Season; the answer says the look was emulated digitally.")),
   ],
  [C("Aldaine: Ambrose shot The Copper Season on Kodak Vision3 250D, so a lot of that texture was already there.",
     k("Kodak Vision3 250D", "stock", A, "multiFilmInterview", film=CS),
     k("Kodak Vision3 250D", "stock", R, "multiFilmInterview", about=CS))],
])

P(D4, "British Cinematographer", "Northbound Choir: Celeste Ourada in the cold churches", NC, [
  ["Northbound Choir, Anselm Okafor's portrait of a touring youth choir, was photographed by Celeste Ourada, who previously shot Wait... Then Run.",
   C("As with Wait... Then Run, Ourada used Zeiss Supreme Prime lenses, though this time on the Alexa Mini LF.",
     k("Zeiss Supreme Prime", "lens", A, "comparison"),
     k("Alexa Mini LF", "camera", A, "comparison"),
     k("Alexa Mini LF", "camera", R, "comparison", about=NC, film=WTR, ctx="'This time' restricts the camera to Northbound Choir."))],
  ["Q: How did you light the churches?",
   C("Ourada: Natural light whenever we could, and LED panels bounced off the vaulting when the clouds came in.",
     k("Natural light", "lighting", A, "context", ctx="Answer to a question about lighting Northbound Choir's churches."),
     k("LED panels", "lighting", A, "context", ctx="Answer to a question about lighting Northbound Choir's churches.")),
   C("Ourada: There's a crane shot in one of my films that I'm still proud of.",
     k("crane", "support", X, "ambiguous", ctx="'One of my films' is unspecified."),
     k("crane", "support", X, "ambiguous", film=WTR, ctx="'One of my films' is unspecified."))],
  ["Ourada studied photography in Lisbon before moving to London.",
   C("Her graduation film was shot on a Bolex with Eastman Double-X black-and-white stock.",
     k("Eastman Double-X", "stock", R, "context", ctx="Biography paragraph about her graduation film."),
     k("black-and-white", "format", R, "context", ctx="Biography paragraph about her graduation film."),
     k("Eastman Double-X", "stock", R, "context", film=WTR, ctx="Biography paragraph about her graduation film."))],
  [C("The choir's tour bus, its ceiling lined with decorative LED panels, was used as a moving location for the travel montages.",
     k("LED panels", "lighting", R, "environment"))],
])

S("Cinesite", "Wait... Then Run", [D2])
S("ProVideo Coalition", "Jun Aldaine", [D3])
S("American Cinematographer", "Celeste Ourada", [])

# ===================== E: Marrow / Ash Meridian (DP Yusuf Brennecke) =====================
E1 = "https://www.kodak.com/en/motion/blog-post/marrow-a-winter-account/"
E2 = "https://theasc.com/articles/yusuf-brennecke-marrow-ash-meridian/"
E3 = "https://www.cinesite.com/projects/ash-meridian/"
E4 = "https://www.indiewire.com/features/craft/ash-meridian-ending-explained-1234567321/"

F(9005, MAR, 2020, "Agnieszka Thorvald",
  [("Director of Photography", "Yusuf Brennecke"), ("Second Unit Director of Photography", "Elodie Farrant")],
  [
   ["Marrow: A Winter Account was filmed in the Tatra foothills in February 2019.",
    C("The film was shot on Eastman Double-X black-and-white negative, using an Arricam ST.",
      k("Eastman Double-X", "stock", A, "positive"),
      k("Arricam ST", "camera", A, "physicalGear"))],
   [C("Director Agnieszka Thorvald had originally intended to shoot in colour on Kodak Vision3 500T, but changed her mind after seeing tests of the village at dusk.",
      k("Kodak Vision3 500T", "stock", R, "abandonedPlan")),
    C("The film was composed for a 1.33:1 frame.", k("1.33:1", "aspect", A, "positive")),
    C("Some accounts suggest a Hawk anamorphic lens was used for the dream sequence.",
      k("Hawk anamorphic", "lens", X, "ambiguous", ctx="Unattributed 'some accounts'; conflicts with the film's 1.33:1 spherical approach."))],
   [C("A later home-media release was letterboxed to 1.66:1 in some territories.",
      k("1.66:1", "aspect", R, "delivery"))],
  ],
  [E1])

F(9017, AM, 2019, "Kenji Abernathy",
  [("Director of Photography", "Yusuf Brennecke"), ("Visual Effects Supervisor", "Marguerite Oyelaran")],
  [], [E4])

P(E1, "Kodak", "Marrow: Yusuf Brennecke Goes Black-and-White", MAR, [
  ["Marrow begins with a long shot of a woman pulling a sledge across a frozen field, and it never relents.",
   C("Cinematographer Yusuf Brennecke shot the film on Eastman Double-X, with push processing of one stop for the night scenes.",
     k("Eastman Double-X", "stock", A, "positive", ctx="Page about Marrow (title written without its subtitle)."),
     k("push processing", "finish", A, "positive"))],
  ["Q: Why black-and-white?",
   C("Brennecke: Agnieszka felt colour would make the snow pretty, so black-and-white was decided before I was even hired.",
     k("black-and-white", "format", A, "context", ctx="Interview about Marrow; 'Agnieszka' is its director."))],
  [C("Brennecke: In the farmhouse we lit with tungsten and practicals, probably 100-watt household bulbs, though I couldn't swear to the wattage now.",
     k("practicals", "lighting", A, "estimated"),
     k("tungsten", "lighting", A, "positive"))],
  [C("Brennecke: The old masters would bounce a single HMI through the window, and that's what everyone of that era did.",
     k("HMI", "lighting", R, "otherPractice"))],
])

P(E2, "American Cinematographer", "From Snow to Sand: Yusuf Brennecke", MAR, [
  ["Yusuf Brennecke followed Marrow with Ash Meridian, a science-fiction drama shot in the Atacama."],
  ["Q: Ash Meridian is in colour and widescreen. Was that a reaction to Marrow?",
   C("Brennecke: Partly. We shot Ash Meridian on the Alexa 65 with Hawk anamorphic lenses, which is about as far from Marrow as you can get.",
     k("Alexa 65", "camera", A, "multiFilmInterview", film=AM),
     k("Hawk anamorphic", "lens", A, "multiFilmInterview", film=AM),
     k("Alexa 65", "camera", R, "multiFilmInterview", about=AM),
     k("Hawk anamorphic", "lens", R, "multiFilmInterview", about=AM))],
  ["Q: And the desert days?",
   C("Brennecke: Huge negative fill, a Technocrane for the reveals and a lot of ND filters, because the sun there is merciless.",
     k("Technocrane", "support", A, "context", film=AM, ctx="Follows the Ash Meridian question; 'desert days' are Ash Meridian's Atacama shoot."),
     k("ND filters", "filter", A, "context", film=AM, ctx="Follows the Ash Meridian question; desert shoot."),
     k("Technocrane", "support", R, "context", about=AM, ctx="Desert days belong to Ash Meridian."))],
  ["Q: Back to Marrow for a moment — was there any handheld?",
   C("Brennecke: No handheld at all; every shot is on sticks or a dolly.",
     k("handheld", "movement", R, "denial", ctx="Answer to a question that returns explicitly to Marrow."),
     k("dolly", "support", A, "context", ctx="Answer to a question that returns explicitly to Marrow."),
     k("dolly", "support", R, "context", film=AM, ctx="The question has returned to Marrow.")),
   C("Brennecke: There's one shot, I think, that was on 65mm, but I can't recall which film it ended up in.",
     k("65mm", "format", X, "ambiguous"),
     k("65mm", "format", X, "ambiguous", film=AM))],
  [C("Brennecke expects the next one will probably be on the ARRI Alexa 35, though nothing has been decided.",
     k("ARRI Alexa 35", "camera", R, "hypothetical", film=AM),
     k("ARRI Alexa 35", "camera", R, "hypothetical"))],
])

P(E3, "Cinesite", "Ash Meridian", AM, [
  ["Cinesite created the dust storms and orbital vistas of Ash Meridian under the supervision of Marguerite Oyelaran."],
  [C("The orbital shots were composed with a virtual camera that mimicked the Hawk anamorphic lenses used on location, including their breathing and oval bokeh.",
     k("virtual camera", "camera", R, "mixed", why="Mixed sentence: the virtual camera is CG, while the Hawk lenses were physically used on location."),
     k("Hawk anamorphic", "lens", A, "mixed"))],
  [C("CG lighting for the station interior was built from HDRIs of the real set, which had been lit with SkyPanels and Creamsource Vortex8 fixtures.",
     k("SkyPanels", "lighting", A, "physicalGear"),
     k("Creamsource Vortex8", "lighting", A, "physicalGear"))],
  [C("The filmmakers had also tested a drone for the canyon flyovers, but those shots were ultimately replaced with fully CG versions.",
     k("drone", "support", R, "adoptedTest"))],
])

P(E4, "IndieWire", "'Ash Meridian' Ending Explained", AM, [
  ["The final ten minutes of Ash Meridian have divided audiences."],
  ["Director Kenji Abernathy discussed the station's fate."],
  ["Cinematographer Yusuf Brennecke described the last shot."],
], failure="unavailable")

S("American Cinematographer", "Yusuf Brennecke", [E2])
S("Cinesite", "Ash Meridian", [E3])

# ===================== F: Odile's Garden / Low Orchard (DP Noor Vellacott) =====================
F1 = "https://britishcinematographer.co.uk/odiles-garden-noor-vellacott/"
F2 = "https://filmmakermagazine.com/121877-low-orchard-noor-vellacott/"
F3 = "https://theasc.com/articles/noor-vellacott-two-gardens/"

F(9006, OG, 2023, "Rémi Castagnol",
  [("Director of Photography", "Noor Vellacott"), ("Gaffer", "Teodor Haas")],
  [], [F1, R1, F2])

F(9015, LO, 2021, "Cormac Tierney-Bell",
  [("Director of Photography", "Noor Vellacott"), ("Key Grip", "Aisling Corr")],
  [], [F2, F1])

P(F1, "British Cinematographer", "Odile’s Garden: Noor Vellacott shoots a summer", OG, [
  ["Rémi Castagnol’s Odile’s Garden is a summer film, and Noor Vellacott shot it like one.",
   C("The production used the Alexa Mini LF with Cooke Panchro Classic lenses, chosen for their soft fall-off.",
     k("Alexa Mini LF", "camera", A, "positive", ctx="Page about Odile's Garden (title spelled with a curly apostrophe)."),
     k("Cooke Panchro Classic", "lens", A, "positive"))],
  [C("Vellacott lit the garden almost entirely with natural light, shaping it with large frames of diffusion and the occasional HMI from the cherry picker.",
     k("natural light", "lighting", A, "positive"),
     k("HMI", "lighting", A, "physicalGear"))],
  ["Q: What about the greenhouse scene at night?",
   C("Vellacott: That's Astera tubes laid along the planting beds, dimmed right down.",
     k("Astera tubes", "lighting", A, "context"))],
  ["Q: You also shot Low Orchard the same year.",
   C("Vellacott: Yes, and that one was all Super 16 on an Arriflex 416, a totally different discipline.",
     k("Super 16", "format", R, "multiFilmInterview", about=LO, ctx="'That one' refers to Low Orchard, named in the question."),
     k("Arriflex 416", "camera", R, "multiFilmInterview", about=LO, ctx="'That one' refers to Low Orchard."),
     k("Super 16", "format", A, "multiFilmInterview", film=LO, ctx="'That one' refers to Low Orchard, named in the question."),
     k("Arriflex 416", "camera", A, "multiFilmInterview", film=LO, ctx="'That one' refers to Low Orchard."))],
  [C("Odile, the character, keeps an old Super 8 camera in the potting shed, which she uses to film the bees.",
     k("Super 8", "format", R, "environment"))],
])

P(F2, "Filmmaker", "Low Orchard: Eighteen Days in Armagh", LO, [
  [C("Low Orchard, Cormac Tierney-Bell's debut, was shot in eighteen days on Super 16 in County Armagh.",
     k("Super 16", "format", A, "positive"))],
  [C("Unlike Odile's Garden, which she lit with HMIs, Vellacott lit Low Orchard with nothing but tungsten units and the occasional practical.",
     k("tungsten", "lighting", A, "comparison"),
     k("practical", "lighting", A, "comparison"),
     k("HMIs", "lighting", R, "comparison", about=OG),
     k("HMIs", "lighting", A, "comparison", film=OG, ctx="The relative clause explicitly states Odile's Garden was lit with HMIs.")),
   C("Some sources claim the orchard finale used a gimbal.",
     k("gimbal", "support", X, "ambiguous"))],
  [C("The film was blown up from Super 16 to a 35mm film-out for its festival premiere, but its original 1.66:1 frame was preserved.",
     k("film-out", "finish", R, "delivery"),
     k("35mm", "format", R, "delivery"),
     k("1.66:1", "aspect", A, "positive"))],
  [C("Tierney-Bell says he would have loved a Technocrane for the orchard finale but could never have afforded one.",
     k("Technocrane", "support", R, "counterfactual"))],
])

P(F3, "American Cinematographer", "Noor Vellacott: Two Gardens", OG, [
  ["Noor Vellacott's two most recent features could hardly be more different."],
  [C("On one, she used Black Pro-Mist filtration throughout; on the other she refused all diffusion.",
     k("Black Pro-Mist", "filter", X, "ambiguous", ctx="'On one ... on the other' never says which film."),
     k("Black Pro-Mist", "filter", X, "ambiguous", film=LO, ctx="'On one ... on the other' never says which film."))],
  ["Q: Which camera do you reach for first?",
   C("Vellacott: Honestly, the Alexa Mini, though I haven't used it on a feature in years.",
     k("Alexa Mini", "camera", R, "otherPractice", why="General personal preference; she says she has not used it on a feature in years."))],
  [C("Vellacott shoots tests for every job on a RED Komodo she keeps at home, though none of that footage has ended up in a finished film.",
     k("RED Komodo", "camera", R, "adoptedTest"),
     k("RED Komodo", "camera", R, "adoptedTest", film=LO))],
])

S("American Cinematographer", "Noor Vellacott", [F3])

# ===================== G: Salt & Cinder / Hollow Clock (DP Kasia Lindqvist) =====================
G1 = "https://variety.com/2022/artisans/features/salt-and-cinder-kasia-lindqvist-1235330987/"
G2 = "https://www.cinesite.com/projects/salt-cinder/"
G3 = "https://beforesandafters.com/2022/11/08/hollow-clock-clockwork-vfx/"
G4 = "https://theasc.com/articles/hollow-clock-kasia-lindqvist/"
G5 = "https://www.cinesite.com/projects/hollow-clock/"

F(9007, SC, 2022, "Fennimore Ruiz",
  [("Director of Photography", "Kasia Lindqvist"), ("Visual Effects Supervisor", "Marguerite Oyelaran")],
  [], [G1])

F(9023, HC, 2022, "Emeric Sandoval-Hart",
  [("Director of Photography", "Kasia Lindqvist"), ("Visual Effects Supervisor", "Ivo Brennan-Saito")],
  [], [G3])

P(G1, "Variety", "'Salt and Cinder' DP Kasia Lindqvist on Shooting a Volcano", SC, [
  [C("For “Salt and Cinder,” Fennimore Ruiz's volcanic-island western, Kasia Lindqvist shot on Kodak Vision3 250D and Kodak Vision3 500T with a Panavision Millennium XL2.",
     k("Kodak Vision3 250D", "stock", A, "positive", ctx="Title written with 'and' instead of '&'."),
     k("Kodak Vision3 500T", "stock", A, "positive"),
     k("Panavision Millennium XL2", "camera", A, "physicalGear")),
   C("Panavision says the Millennium XL2 is among the quietest 35mm cameras ever made.",
     k("Millennium XL2", "camera", R, "productClaim", why="Manufacturer claim; this sentence itself establishes no use (use is established by the previous sentence)."))],
  [C("“There's no drone in this film,” Lindqvist says flatly. “Every aerial is from a helicopter or the crane.”",
     k("drone", "support", R, "denial"),
     k("crane", "support", A, "mixed", why="Same sentence denies the drone and affirms the crane.")),
   C("The production's equipment list, published in a trade paper, included Hawk anamorphic lenses, but it is unclear whether they were used.",
     k("Hawk anamorphic", "lens", X, "ambiguous"))],
  [C("The lab work was done at FotoKem, and the negative was finished through a digital intermediate.",
     k("FotoKem", "finish", A, "positive"),
     k("digital intermediate", "finish", A, "positive"))],
  [C("Lindqvist had planned to shoot the cave sequences in VistaVision, but the cameras were booked by another production.",
     k("VistaVision", "format", R, "abandonedPlan"))],
])

P(G2, "Cinesite", "Salt & Cinder", SC, [
  ["Cinesite's team completed 340 shots for Salt and Cinder, the bulk of them lava, ash and sky replacements."],
  [C("The eruption's glow on the actors was real: the production rigged LED panels on the ground and programmed them with lava loops.",
     k("LED panels", "lighting", A, "physicalGear")),
   "In the fully CG wide shots, the lava itself served as the main light source in the render."],
  [C("Cinesite added a faux split diopter to the duel's final shot so that both gunfighters stay sharp.",
     k("split diopter", "lens", R, "faux"))],
  [C("Oyelaran notes that the same approach had been used on Ash Meridian, where Cinesite also matched a virtual camera to real lens data.",
     k("virtual camera", "camera", R, "vfxCG", ctx="Sentence is about Ash Meridian's CG work."))],
])

P(G3, "befores & afters", "The gears of Hollow Clock", HC, [
  ["Hollow Clock, Emeric Sandoval-Hart's fable about a town where time runs backwards, relied on a mix of practical clockwork and CG."],
  [C("VFX supervisor Ivo Brennan-Saito says the giant gears were shot in-camera using a Technocrane threaded through the miniature, then extended digitally.",
     k("Technocrane", "support", A, "physicalGear"))],
  [C("The reverse-time shots were rendered with a CG camera that simulated a 65mm look, complete with digitally added grain.",
     k("65mm", "format", R, "faux"))],
  [C("For Wait... Then Run, Brennan-Saito had relied on Libra head data to match CG to the plates.",
     k("Libra head", "support", R, "multiFilmInterview", about=WTR))],
])

P(G4, "American Cinematographer", "Hollow Clock: Turning Back Time", HC, [
  [C("For Hollow Clock, Kasia Lindqvist returned to digital, shooting on the Sony Venice 2 with Cooke S4 lenses.",
     k("Sony Venice 2", "camera", A, "positive"),
     k("Cooke S4", "lens", A, "positive"),
     k("Sony Venice 2", "camera", R, "multiFilmInterview", about=HC, film=SC))],
  ["Q: After Salt & Cinder, was it hard to leave film behind?",
   C("Lindqvist: A little, but the Venice handles tungsten-lit interiors beautifully, and the clock tower set was almost all tungsten.",
     k("tungsten", "lighting", A, "context", ctx="The clock tower is Hollow Clock's set; the answer concerns the move to digital on Hollow Clock."),
     k("tungsten", "lighting", R, "context", about=HC, film=SC, ctx="The question names Salt & Cinder but the answer is about Hollow Clock's clock tower set."))],
  [C("Lindqvist: The one thing I kept from Salt & Cinder was the bleach bypass look, which on Hollow Clock we only emulated with a LUT.",
     k("bleach bypass", "finish", R, "faux"),
     k("LUT", "finish", A, "mixed"),
     k("bleach bypass", "finish", X, "ambiguous", film=SC, ctx="Says Salt & Cinder had a bleach bypass 'look', but not whether it was a real lab process."))],
  [C("In the epilogue a character photographs the square with a Canon C300 Mark II, a prop the art department rented as dressing.",
     k("Canon C300 Mark II", "camera", R, "environment"))],
])

P(G5, "Cinesite", "Hollow Clock", HC, [
  ["Cinesite's Montreal studio contributed 150 shots to Hollow Clock, including the backwards-falling rain."],
  [C("The rain was simulated in Houdini and lit with CG LED panels mirroring the set's real fixtures.",
     k("LED panels", "lighting", R, "vfxCG"))],
  [C("Plates were photographed on set with Cooke S4 lenses, whose distortion was profiled for the CG work.",
     k("Cooke S4", "lens", A, "physicalGear"))],
])

S("Cinesite", "Salt & Cinder", [G2])
S("Cinesite", "Hollow Clock", [G5])
S("American Cinematographer", "Kasia Lindqvist", [G4])

# ===================== H: Half-Light Ferry / Dovetail (DP Ottoline Fairweather) =====================
H1 = "https://britishcinematographer.co.uk/half-light-ferry-ottoline-fairweather/"
H2 = "https://nofilmschool.com/dovetail-ottoline-fairweather-35mm"
H3 = "https://theasc.com/articles/ottoline-fairweather-retrospective/"

F(9008, HLF, 2019, "Mateus Corrigan",
  [("Director of Photography", "Ottoline Fairweather"), ("Key Grip", "Bram Holloway")],
  [], [H1])

F(9016, DOV, 2023, "Beatrix Holm",
  [("Director of Photography", "Ottoline Fairweather"), ("Gaffer", "Tamsin Rook")],
  [
   [C("Dovetail was shot on 35mm in a disused joinery in Suffolk.", k("35mm", "format", A, "positive")),
    "The title refers to the dovetail joint that the protagonist teaches her son to cut."],
  ],
  [H2, R1])

P(H1, "British Cinematographer", "Half–Light Ferry: Ottoline Fairweather at sea", HLF, [
  ["Mateus Corrigan’s Half–Light Ferry was shot aboard a working car ferry between Oban and Mull over three weeks in 2018.",
   C("Ottoline Fairweather photographed it on 35mm with an Arricam LT, framing for 2.39:1.",
     k("Arricam LT", "camera", A, "physicalGear", ctx="Page about Half-Light Ferry (title written with an en dash)."),
     k("2.39:1", "aspect", A, "positive")),
   C("She tested Hawk anamorphic lenses against two other sets in prep, and the Hawks went on to shoot the whole film.",
     k("Hawk anamorphic", "lens", A, "adoptedTest"))],
  [C("Key grip Bram Holloway built a sliding dolly track along the car deck.",
     k("dolly", "support", A, "physicalGear")),
   C("A Steadicam was considered for the stairwells but was never brought aboard.",
     k("Steadicam", "support", R, "denial"))],
  ["Q: How much of the light is the ferry's own?",
   C("Fairweather: Most of it; we replaced the strip lights in the lounge with Kino Flos of the same length, and the rest is the sea.",
     k("Kino Flos", "lighting", A, "context"))],
  [C("The film's 2023 4K restoration was supervised by Fairweather for its disc release.",
     k("4K", "format", R, "delivery"))],
])

P(H2, "No Film School", "How Dovetail Kept 35mm Alive in a Joinery", DOV, [
  ["Beatrix Holm's Dovetail is a carpentry drama, and its shooting schedule dovetailed awkwardly with Ottoline Fairweather's commitments on a commercial in Norway.",
   C("Fairweather shot Dovetail on Kodak Vision3 500T using Zeiss Ultra Prime lenses.",
     k("Kodak Vision3 500T", "stock", A, "positive"),
     k("Zeiss Ultra Prime", "lens", A, "positive"))],
  ["Q: The workshop scenes have a wonderful dust in the air.",
   C("Fairweather: That's a Black Pro-Mist 1/4 and a smoke machine, nothing clever.",
     k("Black Pro-Mist", "filter", A, "context")),
   C("Fairweather: We had Astera tubes on the truck for weeks.",
     k("Astera tubes", "lighting", X, "ambiguous", ctx="Being on the truck does not establish they were used."))],
  [C("Fairweather: In Norway, the commercial was all drone and gimbal work, which is the opposite of how I like to shoot.",
     k("drone", "support", R, "context", ctx="About the Norwegian commercial introduced in the first paragraph."),
     k("gimbal", "support", R, "context", ctx="About the Norwegian commercial."))],
  [C("The joinery close-ups used a split diopter so that the dovetail joint and the carpenter's face could both be in focus.",
     k("split diopter", "lens", A, "physicalGear")),
   C("Continuing the process begun on Half-Light Ferry (2019), Fairweather had the Dovetail negative developed with an ENR step at the lab.",
     k("ENR", "finish", A, "comparison"))],
  [C("Holm says that if Dovetail had been shot on digital, the sawdust would have looked like noise.",
     k("digital", "format", R, "counterfactual")),
   C("Holm hopes to shoot her next film on VistaVision.",
     k("VistaVision", "format", R, "hypothetical"))],
])

P(H3, "American Cinematographer", "Ottoline Fairweather Looks Back", HLF, [
  ["Ottoline Fairweather has shot five features, from Half-Light Ferry to Dovetail, and nearly all of them on film."],
  ["Q: Which of your films used IMAX?",
   C("Fairweather: None of them used IMAX! People assume the ferry film did because of the horizon shots, but that was just 35mm anamorphic.",
     k("IMAX", "format", R, "denial"),
     k("35mm", "format", A, "context", ctx="'The ferry film' is Half-Light Ferry."),
     k("IMAX", "format", R, "denial", film=DOV, ctx="'None' of her films used IMAX."))],
  [C("Fairweather: My first feature, which nobody has seen, was shot on a Canon C300 Mark II with a single zoom.",
     k("Canon C300 Mark II", "camera", R, "context", ctx="About her unseen first feature, not Half-Light Ferry."),
     k("zoom", "lens", R, "context", film=DOV, ctx="About her unseen first feature."))],
  [C("Fairweather: Somewhere in there we used a Technocrane, I think on the ferry film, but it might have been the other one.",
     k("Technocrane", "support", X, "ambiguous"),
     k("Technocrane", "support", X, "ambiguous", film=DOV))],
])

S("American Cinematographer", "Ottoline Fairweather", [H3])
