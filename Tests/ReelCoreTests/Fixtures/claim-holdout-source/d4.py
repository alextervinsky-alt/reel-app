from fw import *
from d1 import R1

# ===================== L: The Weight of Gulls / Cradle of Wolves (DP Faisal Odelberg) =====================
L1 = "https://britishcinematographer.co.uk/the-weight-of-gulls-faisal-odelberg/"
L2 = "https://variety.com/2021/artisans/features/cradle-of-wolves-faisal-odelberg-1234998876/"
L3 = "https://theasc.com/articles/faisal-odelberg-wind-and-weather/"

F(9013, WOG, 2020, "Maren Solvik",
  [("Director of Photography", "Faisal Odelberg"), ("Key Grip", "Ewan Tulloch")],
  [], [L1])

F(9020, COW, 2021, "Ysolde Brannigan",
  [("Director of Photography", "Faisal Odelberg"), ("Colorist", "Mirela Constant")],
  [
   [C("Cradle of Wolves was framed for 1.66:1, as it had been on The Weight of Gulls.",
      k("1.66:1", "aspect", A, "comparison"))],
  ],
  [L2])

P(L1, "British Cinematographer", "The Weight of Gulls: Faisal Odelberg on the Shetland cliffs", WOG, [
  [C("Maren Solvik's The Weight of Gulls was shot on the Shetland coast in 2019 by Faisal Odelberg, who chose the ARRI Alexa Mini with Leica Summilux-C lenses.",
     k("ARRI Alexa Mini", "camera", A, "positive"),
     k("Leica Summilux-C", "lens", A, "positive"))],
  [C("Odelberg wanted the seabird colonies to feel overwhelming, so the second unit shot the cliffs with a long zoom from a boat.",
     k("zoom", "lens", A, "physicalGear"))],
  ["Q: The interior of the croft feels like a painting.",
   C("Odelberg: That's one window, a bounce, and a single tungsten Fresnel, probably a 2K, nothing more.",
     k("tungsten", "lighting", A, "estimated"))],
  [C("Odelberg: For the finale we had planned a Technocrane on the cliff, but the council refused permission and we went handheld instead.",
     k("Technocrane", "support", R, "abandonedPlan"),
     k("handheld", "movement", A, "mixed"))],
  [C("The gulls' digital shadows in the storm sequence were added by the VFX team, who relit them with CG HMI sources.",
     k("HMI", "lighting", R, "vfxCG"))],
])

P(L2, "Variety", "'Cradle of Wolves' Cinematographer Faisal Odelberg Returns to Film", COW, [
  ["In “Cradle of Wolves,” Ysolde Brannigan's folk-horror fable, Faisal Odelberg returns to film after years of digital work.",
   C("He shot Super 16 on an Arriflex 416 and graded at FotoKem.",
     k("Super 16", "format", A, "positive"),
     k("Arriflex 416", "camera", A, "physicalGear"),
     k("FotoKem", "finish", A, "positive"))],
  [C("“It's all fire, moonlight and HMIs bounced off white sheets,” Odelberg says of the forest nights.",
     k("HMIs", "lighting", A, "positive")),
   C("Odelberg's crew reportedly brought a Technocrane to the forest, although it is not clear if it was ever assembled.",
     k("Technocrane", "support", X, "ambiguous"))],
  [C("For the wolf attack, the production considered a drone but chose a crane instead, since the animals panicked at the noise.",
     k("drone", "support", R, "denial"),
     k("crane", "support", A, "mixed"))],
  [C("As with The Weight of Gulls, he used Leica Summilux-C lenses for the digital pickups shot a year later.",
     k("Leica Summilux-C", "lens", A, "comparison"))],
])

P(L3, "American Cinematographer", "Faisal Odelberg: Wind and Weather", WOG, [
  ["Faisal Odelberg's two most recent features are linked by weather: both were shot in places where the wind never stops."],
  ["Q: On The Weight of Gulls, how did you keep the camera steady on the cliffs?",
   C("Odelberg: A Libra head on a small crane, mostly, and sandbags.",
     k("Libra head", "support", A, "context"),
     k("crane", "support", A, "context"),
     k("Libra head", "support", R, "context", about=WOG, film=COW))],
  ["Q: And on Cradle of Wolves?",
   C("Odelberg: There it was the opposite; I wanted the wind in the frame, so it's all handheld and a little bit of Steadicam.",
     k("handheld", "movement", A, "context", film=COW),
     k("Steadicam", "support", A, "context", film=COW),
     k("Steadicam", "support", R, "context", about=COW, ctx="The question has moved on to Cradle of Wolves."))],
  [C("Odelberg: People ask me whether either film used diffusion; I think there was a diffusion filter on one of them for the dream scenes, but I'd have to check my notes.",
     k("diffusion filter", "filter", X, "ambiguous"),
     k("diffusion filter", "filter", X, "ambiguous", film=COW)),
   C("Odelberg: The next one, if it happens, might be shot in IMAX.",
     k("IMAX", "format", R, "hypothetical", film=COW))],
])

S("American Cinematographer", "Faisal Odelberg", [L3])

# ===================== M: Sundial / Ironwood Lullaby (DP Ilka Brandvold) =====================
M1 = "https://nofilmschool.com/sundial-ilka-brandvold-single-day"
M2 = "https://www.kodak.com/en/motion/blog-post/ironwood-lullaby-ilka-brandvold/"
M3 = "https://theasc.com/articles/ilka-brandvold-time-and-light/"

F(9024, SUN, 2024, "Philippa Nkemelu",
  [("Director of Photography", "Ilka Brandvold"), ("Gaffer", "Oren Blaise")],
  [
   ["Sundial was filmed in a walled garden in Kent over twenty days in the summer of 2023.",
    C("Brandvold avoided artificial light outdoors and never used a drone, despite early storyboards that showed the garden from above.",
      k("drone", "support", R, "denial"))],
  ],
  [M1])

F(9025, IL, 2019, "Caspar Wendt",
  [("Director of Photography", "Ilka Brandvold")],
  [], [M2])

P(M1, "No Film School", "One Day, One Garden: Shooting Sundial", SUN, [
  ["Philippa Nkemelu's Sundial unfolds over a single day in a walled garden, with the sun's progress tracked by the stone sundial at its centre.",
   C("Ilka Brandvold shot the film on the ARRI Alexa 35, using only natural light for every exterior.",
     k("ARRI Alexa 35", "camera", A, "positive"),
     k("natural light", "lighting", A, "positive"))],
  ["Q: You must have had a strict schedule.",
   C("Brandvold: We shot in story order, so magic hour really is the end of the film.",
     k("magic hour", "lighting", A, "context"))],
  ["Brandvold: The sundial in the garden was a fibreglass prop; a real stone one would have been too heavy for the lawn.",
   C("Brandvold: A replica sundial and a prop Arriflex 416 sit in the potting shed where the grandfather keeps his old things.",
     k("Arriflex 416", "camera", R, "environment"))],
  [C("The film's lone interior was lit with a single SkyPanel through the window, set to match the angle of the sun at that hour.",
     k("SkyPanel", "lighting", A, "physicalGear")),
   C("Rumours on set suggested a drone was flown for the opening, but Brandvold would not say.",
     k("drone", "support", X, "ambiguous", why="Unconfirmed rumour; the film's own article says no drone was used, but this passage alone cannot settle it."))],
  [C("ARRI advertises 17 stops of dynamic range for the Alexa 35, a figure Brandvold says she has never tested herself.",
     k("Alexa 35", "camera", R, "productClaim"))],
])

P(M2, "Kodak", "Ironwood Lullaby: three generations on 35mm", IL, [
  [C("Caspar Wendt's Ironwood Lullaby, a 2019 drama about a lumber family, was photographed by Ilka Brandvold on 35mm.",
     k("35mm", "format", A, "positive")),
   C("Brandvold used Kodak Vision3 250D for the forest and Kodak Vision3 500T for the cabin interiors.",
     k("Kodak Vision3 250D", "stock", A, "positive"),
     k("Kodak Vision3 500T", "stock", A, "positive"))],
  ["Q: You framed it at 1.85:1?",
   C("Brandvold: Yes, though the streaming version was reframed to 2.00:1, which I never approved.",
     k("2.00:1", "aspect", R, "delivery"))],
  [C("Brandvold: We'd planned some Super 8 inserts for the home movies but ended up shooting those on 35mm too and degrading them in the grade.",
     k("Super 8", "format", R, "abandonedPlan")),
   C("Brandvold: I believe the cabin interiors had a diffusion filter too, but my notes from 2018 are lost.",
     k("diffusion filter", "filter", X, "ambiguous"))],
  [C("Brandvold: The crane shot at the end, rising over the treeline, is the only time we used a crane.",
     k("crane", "support", A, "positive"))],
])

P(M3, "American Cinematographer", "Ilka Brandvold: Time and Light", SUN, [
  ["Ilka Brandvold's films are obsessed with time: Ironwood Lullaby spans three generations, Sundial a single day."],
  ["Q: Did you use any of the same gear?",
   C("Brandvold: The Cooke S4 lenses, yes, on both films.",
     k("Cooke S4", "lens", A, "multiFilmInterview"),
     k("Cooke S4", "lens", A, "multiFilmInterview", film=IL))],
  ["Q: And filtration?",
   C("Brandvold: On Ironwood Lullaby, a 1/8 Black Pro-Mist; on Sundial nothing at all.",
     k("Black Pro-Mist", "filter", A, "multiFilmInterview", film=IL),
     k("Black Pro-Mist", "filter", R, "multiFilmInterview", about=IL))],
  [C("Brandvold: Somebody once told me Sundial would have looked better on 65mm, and maybe it would have.",
     k("65mm", "format", R, "counterfactual")),
   C("Brandvold: My mentor shot everything with a Panavision Primo zoom and never apologised for it.",
     k("Panavision Primo", "lens", R, "otherPractice", film=IL))],
])

S("American Cinematographer", "Ilka Brandvold", [M3])

# ===================== N: Vesper Street / Tin Crown (DP Gideon Marsh-Okoro) =====================
N1 = "https://www.indiewire.com/features/craft/vesper-street-gideon-marsh-okoro-1235100011/"
N2 = "https://filmmakermagazine.com/119911-tin-crown-gideon-marsh-okoro/"
N3 = "https://www.provideocoalition.com/gideon-marsh-okoro-rooftops-and-junkyards/"

F(9026, VS, 2023, "Leona Iturbe",
  [("Director of Photography", "Gideon Marsh-Okoro"), ("Colorist", "Hanne Strom")],
  [], [N1, R1])

F(9027, TC, 2021, "Bastian Krull",
  [("Director of Photography", "Gideon Marsh-Okoro"), ("Visual Effects Supervisor", "Pell Ostrander")],
  [
   [C("Tin Crown was shot in a scrapyard outside Rotterdam, mostly in daylight.",
      ),
    C("The film was presented in 1.85:1, though early festival screenings used a 2.39:1 crop that Krull later disowned.",
      k("2.39:1", "aspect", R, "delivery"),
      k("1.85:1", "aspect", X, "ambiguous", ctx="'Presented in' is a delivery statement; capture ratio is not stated.", why="Presentation ratio is given but nothing says the film was composed or shot that way."))],
  ],
  [N2])

P(N1, "IndieWire", "How 'Vesper Street' Turned One Glasgow Block Into a Neon Noir", VS, [
  [C("Leona Iturbe's Vesper Street is a neon-lit noir set in a single block of Glasgow, and Gideon Marsh-Okoro shot it on the Sony Venice 2 with Hawk anamorphic lenses.",
     k("Sony Venice 2", "camera", A, "positive"),
     k("Hawk anamorphic", "lens", A, "positive"))],
  [C("The neon signs that line the street are practicals built by the art department, and Marsh-Okoro used them as his key light.",
     k("practicals", "lighting", A, "physicalGear", why="Set-built practicals explicitly used as the key light are real lighting.")),
   C("The street's bus shelters have advertising lightboxes made of LED panels, which were left as set dressing and switched off during most takes.",
     k("LED panels", "lighting", R, "environment"))],
  [C("“We avoided handheld completely,” Marsh-Okoro says, “because the street had to feel like a stage.”",
     k("handheld", "movement", R, "denial")),
   C("Most of the film was shot on a dolly, with one Technocrane move over the rooftops at the end.",
     k("dolly", "support", A, "positive"),
     k("Technocrane", "support", A, "physicalGear")),
   C("One crew member recalled the production renting Leica Summilux-C lenses, but it is unclear for which scenes, if any.",
     k("Leica Summilux-C", "lens", X, "ambiguous"))],
  [C("The film was finished at Company 3 with a digital intermediate built around a show LUT.",
     k("Company 3", "finish", A, "positive"),
     k("LUT", "finish", A, "positive"))],
])

P(N2, "Filmmaker", "Tin Crown: Gideon Marsh-Okoro in the Scrapyard", TC, [
  [C("Bastian Krull's Tin Crown is a children's fantasy about a scrap-metal king, shot by Gideon Marsh-Okoro on the ARRI Alexa Mini LF.",
     k("Alexa Mini LF", "camera", A, "positive")),
   C("Atlas markets the Orion series as the most affordable true anamorphic primes on the market.",
     k("Orion", "lens", R, "productClaim"))],
  ["Q: How different was it from Vesper Street?",
   C("Marsh-Okoro: Completely. Vesper Street was all practicals and neon; Tin Crown is daylight and Kino Flos.",
     k("Kino Flos", "lighting", A, "multiFilmInterview"),
     k("practicals", "lighting", R, "multiFilmInterview", about=VS))],
  [C("Marsh-Okoro: We did shoot one sequence with a gimbal on a bicycle, which I think is in the film, but Bastian may have cut it.",
     k("gimbal", "support", X, "ambiguous"))],
  [C("The crown itself was created as a CG prop in some scenes, lit by a virtual HMI rig in Houdini.",
     k("HMI", "lighting", R, "vfxCG")),
   C("Krull had wanted the junkyard scenes on 16mm, but the insurers wouldn't cover film cameras in the rain and the plan was dropped.",
     k("16mm", "format", R, "abandonedPlan"))],
])

P(N3, "ProVideo Coalition", "Gideon Marsh-Okoro on rooftops and junkyards", VS, [
  ["Gideon Marsh-Okoro has shot two features in three years, plus a string of music videos."],
  ["Q: What was the most technically demanding thing you've done recently?",
   C("Marsh-Okoro: Probably the rooftop sequence, which was a Technocrane on a rooftop in the rain.",
     k("Technocrane", "support", X, "ambiguous", ctx="No production is named; could be either feature or a music video."),
     k("Technocrane", "support", X, "ambiguous", film=TC, ctx="No production is named."))],
  ["Q: And the music videos?",
   C("Marsh-Okoro: Those were mostly Blackmagic Pocket and a drone, whatever the budget allowed.",
     k("Blackmagic Pocket", "camera", R, "context", ctx="Answer about the music videos."),
     k("drone", "support", R, "context", film=TC, ctx="Answer about the music videos."))],
  [C("Marsh-Okoro: For the next feature I'm thinking about Atlas Orion lenses, but nothing is locked.",
     k("Atlas Orion", "lens", R, "hypothetical"),
     k("Atlas Orion", "lens", R, "hypothetical", film=TC))],
])

S("ProVideo Coalition", "Gideon Marsh-Okoro", [N3])

# ===================== O: Fieldnote / Crosswind Bakery (DP Wren Calloway) =====================
O1 = "https://thefilmstage.com/fieldnote-wren-calloway-interview/"
O2 = "https://britishcinematographer.co.uk/crosswind-bakery-wren-calloway/"
O3 = "https://nofilmschool.com/wren-calloway-documentary-to-fiction"

F(9029, FN, 2024, "Aurelie Danso",
  [("Director of Photography", "Wren Calloway"), ("Sound Recordist", "Imke Varga")],
  [], [O1, O3, "https://thefilmstage.com/signal-hill-road-ambrose-kettering-interview/"])

F(9030, CB, 2020, "Mikkel Ashdown",
  [("Director of Photography", "Wren Calloway")],
  [], [O2, O3])

P(O1, "The Film Stage", "Wren Calloway on the Birds of 'Fieldnote'", FN, [
  [C("Aurelie Danso's Fieldnote follows an ornithologist cataloguing a disappearing marsh, and Wren Calloway shot it on Super 16 with an Arriflex 416.",
     k("Super 16", "format", A, "positive"),
     k("Arriflex 416", "camera", A, "physicalGear"))],
  ["The Film Stage: Did you use any artificial light?",
   C("Calloway: Very little: a LiteMat in the hide, and the rest is the marsh at dawn.",
     k("LiteMat", "lighting", A, "context")),
   C("Calloway: We had ND filters with us, though in that light I'm not sure we ever needed them.",
     k("ND filters", "filter", X, "ambiguous"))],
  ["The Film Stage: There's a remarkable shot of starlings near the end.",
   C("Calloway: That's a murmuration we got on the last day with a long zoom, completely by luck.",
     k("zoom", "lens", A, "context"))],
  [C("Calloway: In the field notes the character writes, she sketches a Leica Summilux-C she saw in a catalogue, which is a little joke from the art department.",
     k("Leica Summilux-C", "lens", R, "environment", ctx="A drawing inside the character's field notes (ordinary-word 'field notes', not the title).")),
   C("Calloway: Had we shot Fieldnote on digital, I think the birds would have looked like screensavers.",
     k("digital", "format", R, "counterfactual"))],
])

P(O2, "British Cinematographer", "Crosswind Bakery: Wren Calloway rises to fiction", CB, [
  ["Mikkel Ashdown's Crosswind Bakery, a gentle comedy set in a Faroese village bakery, was Wren Calloway's first narrative feature.",
   C("Calloway shot on the Canon C300 Mark II with Zeiss Ultra Prime lenses, a package she knew from documentaries.",
     k("Canon C300 Mark II", "camera", A, "positive"),
     k("Zeiss Ultra Prime", "lens", A, "positive"))],
  ["Q: The bakery glows.",
   C("Calloway: The ovens did a lot of the work, along with tungsten practicals, probably 40-watt bulbs, that we swapped into the shop's own fittings.",
     k("practicals", "lighting", A, "estimated"))],
  ["Q: Was there any camera movement plan?",
   C("Calloway: Mostly handheld, and one Steadicam shot following the bread van.",
     k("handheld", "movement", A, "context"),
     k("Steadicam", "support", A, "context")),
   C("Calloway: A friend lent us a gimbal, which may have ended up in one shot.",
     k("gimbal", "support", X, "ambiguous"))],
  [C("Calloway: My documentary mentor, Hauk Reinert, used to say you never need more than natural light and a reflector, and most of the Nordic doc crews still work that way.",
     k("natural light", "lighting", R, "otherPractice"))],
  [C("The film was presented in 1.85:1 in cinemas and on its streaming release, matching the frame it was shot in.",
     k("1.85:1", "aspect", A, "delivery"))],
])

P(O3, "No Film School", "From Documentary to Fiction: Wren Calloway", CB, [
  ["Wren Calloway made the jump from documentary to fiction with Crosswind Bakery and followed it with Fieldnote four years later."],
  [C("Calloway: On the bakery film we used a single Kino Flos unit over the counter for every scene.",
     k("Kino Flos", "lighting", A, "context", ctx="'The bakery film' refers to Crosswind Bakery."),
     k("Kino Flos", "lighting", R, "context", about=CB, film=FN, ctx="'The bakery film' is Crosswind Bakery."))],
  [C("Calloway: On Fieldnote I finally got to shoot film, and we processed at FotoKem.",
     k("FotoKem", "finish", A, "multiFilmInterview", film=FN),
     k("FotoKem", "finish", R, "multiFilmInterview", about=FN))],
  [C("Calloway: People always ask if one of them used an ENR or some lab trick, and the honest answer is that I don't remember.",
     k("ENR", "finish", X, "ambiguous", film=FN))],
  [C("Calloway: Some colleagues I admire shoot everything with a Black Pro-Mist; I've never used one.",
     k("Black Pro-Mist", "filter", R, "denial"),
     k("Black Pro-Mist", "filter", R, "otherPractice", film=FN))],
])
