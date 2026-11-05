from fw import *
from d1 import R1

# ===================== R: IndieWire 2023 roundup (multi-film) =====================
P(R1, "IndieWire", "The Best Cinematography of 2023", None, [
  [C("Kettle (Marten Hollis): Shot on 35mm in a single flat, Ines Volkaert's film made a kitchen feel like a cathedral.",
     k("35mm", "format", A, "context", film=KET, ctx="Roundup entry headed 'Kettle (Marten Hollis)'."),
     k("35mm", "format", R, "context", about=KET, film=NC, ctx="This entry is headed Kettle, not Northbound Choir."))],
  [C("Odile's Garden (Noor Vellacott): Vellacott's Cooke Panchro Classic lenses gave the flowers a glow that no filter could.",
     k("Cooke Panchro Classic", "lens", A, "context", film=OG, ctx="Roundup entry headed 'Odile's Garden'."),
     k("Cooke Panchro Classic", "lens", R, "context", about=OG, film=KET, ctx="Entry is about Odile's Garden."))],
  [C("Northbound Choir (Celeste Ourada): The choir's faces, lit by bounced LED panels in cold churches, are the year's most moving portraits.",
     k("LED panels", "lighting", A, "context", film=NC, ctx="Roundup entry headed 'Northbound Choir'."),
     k("LED panels", "lighting", R, "context", about=NC, film=KET, ctx="Entry is about Northbound Choir."))],
  [C("Dovetail (Ottoline Fairweather): Fairweather's 500T night scenes in the workshop prove film is far from dead.",
     k("500T", "stock", A, "context", film=DOV, ctx="Roundup entry headed 'Dovetail'."))],
  [C("Vesper Street (Gideon Marsh-Okoro): Neon practicals and Hawk anamorphic glass made a single Glasgow block into a universe.",
     k("Hawk anamorphic", "lens", A, "context", film=VS, ctx="Roundup entry headed 'Vesper Street'."),
     k("Hawk anamorphic", "lens", R, "context", about=VS, film=DOV, ctx="Entry is about Vesper Street."),
     k("practicals", "lighting", A, "context", film=VS, ctx="Roundup entry headed 'Vesper Street'."))],
  [C("Pilgrim Tide (Tobiah Rensch): Shot handheld on a pitching trawler, it is the year's most physical film.",
     k("handheld", "movement", A, "context", film=PT, ctx="Roundup entry headed 'Pilgrim Tide'."),
     k("handheld", "movement", R, "context", about=PT, film=OG, ctx="Entry is about Pilgrim Tide."))],
])

# ===================== I: The Copper Season / Signal Hill Road (DP Ambrose Kettering) =====================
I1 = "https://www.kodak.com/en/motion/blog-post/the-copper-season-ambrose-kettering/"
I2 = "https://thefilmstage.com/signal-hill-road-ambrose-kettering-interview/"
I3 = "https://www.provideocoalition.com/aerial-cinematography-lio-fennick-signal-hill-road/"
I4 = "https://variety.com/2024/film/news/signal-hill-road-tomasz-elling-1236001234/"

F(9009, CS, 2024, "Wendell Akinyemi",
  [("Director of Photography", "Ambrose Kettering"), ("Colorist", "Jun Aldaine")],
  [], [I1, I2])

F(9019, SHR, 2024, "Tomasz Elling",
  [("Director of Photography", "Ambrose Kettering"), ("Aerial Director of Photography", "Lio Fennick")],
  [], [I2, I4])

P(I1, "Kodak", "The Copper Season: Ambrose Kettering remembers 1984", CS, [
  ["Wendell Akinyemi's The Copper Season is set during a mining strike in 1984, and cinematographer Ambrose Kettering wanted it to look like a photograph from that year.",
   C("Kettering shot on Kodak Vision3 250D for the exteriors and pushed the 500T stock for night scenes at the pithead.",
     k("Kodak Vision3 250D", "stock", A, "positive"),
     k("500T", "stock", A, "positive"))],
  ["Q: What did you test in prep?",
   C("Kettering: We tested a Black Pro-Mist and a set of Zeiss Super Speed lenses; the Super Speeds made it into the film, the filter did not.",
     k("Zeiss Super Speed", "lens", A, "adoptedTest"),
     k("Black Pro-Mist", "filter", R, "adoptedTest")),
   C("Kettering: The Kodak rep sent us some Eastman Double-X to play with too.",
     k("Eastman Double-X", "stock", X, "ambiguous", ctx="Receiving stock does not establish it was used in the film."))],
  [C("Kettering: A lot of my colleagues light miners' faces with a single LiteMat, but I used the helmet lamps the actors wore, with the bulbs swapped for brighter ones.",
     k("LiteMat", "lighting", R, "otherPractice"))],
  [C("Kettering: The colliery's floodlights were period practicals, probably around 500 watts each, which we rewired to dimmers.",
     k("practicals", "lighting", A, "estimated"))],
])

P(I2, "The Film Stage", "Ambrose Kettering on the Backwards Road Trip of 'Signal Hill Road'", SHR, [
  ["Tomasz Elling's Signal Hill Road is a road movie in reverse, starting at the destination.",
   C("Ambrose Kettering, coming off The Copper Season, shot it on the ARRI Alexa 35 with Zeiss Supreme Prime lenses.",
     k("ARRI Alexa 35", "camera", A, "positive"),
     k("Zeiss Supreme Prime", "lens", A, "positive"),
     k("ARRI Alexa 35", "camera", R, "multiFilmInterview", about=SHR, film=CS, ctx="'It' is Signal Hill Road; The Copper Season is only mentioned as his previous film."))],
  ["The Film Stage: After shooting film, did you miss it?",
   C("Kettering: On The Copper Season we had Kodak; here we had a LUT that tried to remember Kodak.",
     k("LUT", "finish", A, "context", ctx="'Here' = Signal Hill Road, the subject of the interview."),
     k("LUT", "finish", R, "context", about=SHR, film=CS, ctx="'Here' contrasts Signal Hill Road with The Copper Season."))],
  ["The Film Stage: The car interiors are lit so naturally.",
   C("Kettering: We had a Creamsource Vortex8 on a process trailer and some LED panels taped to the dashboard.",
     k("Creamsource Vortex8", "lighting", A, "context"),
     k("LED panels", "lighting", A, "physicalGear", why="Real lighting units rigged in the car to light the actors (contrast with set-dressing LED panels)."))],
  [C("The drone shots over the coast were handled by aerial cinematographer Lio Fennick.",
     k("drone", "support", A, "positive"))],
  [C("The road sign that gives the film its title was later reused in another feature, Fieldnote, where it appears in a crane shot.",
     k("crane", "support", R, "context", about=FN, ctx="The crane shot is in Fieldnote, not Signal Hill Road."),
     k("crane", "support", A, "context", film=FN, ctx="Sentence explicitly places the crane shot in Fieldnote."))],
])

P(I3, "ProVideo Coalition", "Flying the coast: Lio Fennick on Signal Hill Road", SHR, [
  ["Lio Fennick has flown cameras over glaciers, stadiums and, most recently, the coastline in Signal Hill Road."],
  ["Q: What did you fly on Signal Hill Road?",
   C("Fennick: An Alexa Mini on a heavy-lift drone, with a Zeiss Ultra Prime because it was light.",
     k("Alexa Mini", "camera", A, "context"),
     k("drone", "support", A, "context"),
     k("Zeiss Ultra Prime", "lens", A, "context")),
   C("Fennick: The production also hired an Alexa 65 for a week, but I only flew the Mini.",
     k("Alexa 65", "camera", X, "ambiguous", ctx="Hired by the production, but use on the ground is not stated."))],
  [C("Fennick: For the night shots we tested a RED Komodo on a smaller rig, but none of it made the cut.",
     k("RED Komodo", "camera", R, "adoptedTest"))],
  [C("Fennick: Most aerial operators still prefer a gimbal-stabilised helicopter mount for anything over the sea, and I understand why.",
     k("gimbal", "support", R, "otherPractice"))],
])

P(I4, "Variety", "Tomasz Elling Sets 'Signal Hill Road' at Toronto", SHR, [
  ["Tomasz Elling's third feature will premiere at Toronto."],
  ["The film reunites Elling with producer Hester Quayle."],
  ["Ambrose Kettering is the cinematographer."],
], failure="unavailable")

S("ProVideo Coalition", "Lio Fennick", [I3])

# ===================== J: Brine / The Quarry Wives (DP Pell Varady) =====================
J1 = "https://www.indiewire.com/features/craft/brine-pell-varady-salt-flats-1234678001/"
J2 = "https://filmmakermagazine.com/118220-the-quarry-wives-pell-varady/"
J3 = "https://www.provideocoalition.com/gaffer-ruth-abernethy-windows-and-salt/"

F(9010, BR, 2021, "Saoirse Delacroix",
  [("Director of Photography", "Pell Varady"), ("Gaffer", "Ruth Abernethy")],
  [], [J1, J2])

F(9018, QW, 2022, "Delphine Arkwright",
  [("Director of Photography", "Pell Varady")],
  [], [J2])

P(J1, "IndieWire", "In 'Brine,' the Salt Ponds Do the Lighting", BR, [
  ["Saoirse Delacroix's Brine follows two sisters working the evaporation ponds of a failing salt works.",
   "The brine in the ponds turns pink in late summer, and cinematographer Pell Varady built the palette around it.",
   C("The brine shrimp that give the ponds their colour were filmed for the opening by a macro unit using a Leica Summilux-C.",
     k("Leica Summilux-C", "lens", A, "positive", ctx="Page about Brine; 'brine shrimp' is an ordinary-word use of the title."))],
  [C("Varady shot on the Alexa Mini LF, with a set of Cooke Panchro Classic lenses detuned by the rental house.",
     k("Alexa Mini LF", "camera", A, "positive"),
     k("Cooke Panchro Classic", "lens", A, "physicalGear"))],
  [C("“I never wanted to see a light in this film,” Varady says, “so there are no practicals at all, just the sky and some bounce.”",
     k("practicals", "lighting", R, "denial")),
   C("Varady says the film may have a few shots where a Kino Flos was hidden in the salt sheds.",
     k("Kino Flos", "lighting", X, "ambiguous"))],
  [C("In an early draft of the shooting plan, the ponds were to be filmed entirely from a drone, but the plan was dropped before the shoot when the salt works banned flights.",
     k("drone", "support", R, "abandonedPlan"))],
])

P(J2, "Filmmaker", "The Quarry Wives: Pell Varady in Granite and Silver", QW, [
  [C("Delphine Arkwright's The Quarry Wives is set in a Cornish granite quarry in 1952, and Pell Varady shot it in black-and-white on Eastman Double-X.",
     k("black-and-white", "format", A, "positive"),
     k("Eastman Double-X", "stock", A, "positive"))],
  ["Q: Was that a hard sell?",
   "Varady: Less than you'd think, because after Brine everyone knew I'd fight for it.",
   C("Varady: On Brine I'd shot digital and we spent months in the grade at Light Iron; on The Quarry Wives the negative did most of the work.",
     k("Light Iron", "finish", R, "multiFilmInterview", about=BR),
     k("Light Iron", "finish", A, "multiFilmInterview", film=BR),
     k("digital", "format", A, "multiFilmInterview", film=BR))],
  ["Q: The quarry interiors are lit by lamps.",
   C("Varady: The oil lamps are props; the real light is tungsten bouncing off the granite.",
     k("tungsten", "lighting", A, "context")),
   C("Varady: The second unit probably used a zoom for the quarry wides, but I'd have to ask them.",
     k("zoom", "lens", X, "ambiguous", ctx="Speaker is guessing whether the second unit used a zoom."))],
  [C("Varady: The old studio cameramen would put an HMI up on the quarry rim; we didn't, but I thought about it.",
     k("HMI", "lighting", R, "otherPractice")),
   C("Varady says a sequel, if there is one, could be on 65mm.",
     k("65mm", "format", R, "hypothetical"))],
])

P(J3, "ProVideo Coalition", "Gaffer Ruth Abernethy on windows and salt", BR, [
  ["Gaffer Ruth Abernethy has lit two very different films back to back: Kettle, a kitchen-sink drama shot in a flat, and Brine, shot on salt flats under an open sky."],
  ["Q: Kettle seems lit by the windows.",
   C("Abernethy: It mostly was, plus SkyPanels outside two of the windows when the weather turned.",
     k("SkyPanels", "lighting", A, "context", film=KET, ctx="Answer to a question about Kettle."),
     k("SkyPanels", "lighting", R, "context", about=KET, ctx="The question is about Kettle, not Brine."))],
  ["Q: And Brine?",
   C("Abernethy: On Brine there was almost no lighting at all; my crew spent most days holding a 20-by-20 of muslin, though we did carry an HMI that never came off the truck.",
     k("HMI", "lighting", R, "denial"))],
  [C("Abernethy: My father was a gaffer too, and he swore by tungsten for skin tones, which is what most gaffers of his generation believed.",
     k("tungsten", "lighting", R, "otherPractice", film=KET)),
   C("Abernethy: There's a scene in one of them where we put a Creamsource Vortex8 on a cherry picker, but I honestly can't remember which film it was.",
     k("Creamsource Vortex8", "lighting", X, "ambiguous"),
     k("Creamsource Vortex8", "lighting", X, "ambiguous", film=KET))],
])

S("ProVideo Coalition", "Ruth Abernethy", [J3])

# ===================== K: Pale Hours / Little Engines (DP Hamish Rudd) =====================
K1 = "https://thefilmstage.com/pale-hours-hamish-rudd-interview/"
K2 = "https://www.indiewire.com/features/craft/little-engines-hamish-rudd-1234011122/"
K3 = "https://theasc.com/articles/hamish-rudd-night-films/"

F(9012, PH, 2022, "Ilse Marchetti",
  [("Director of Photography", "Hamish Rudd"), ("Gaffer", "Quentin Avery")],
  [], [K1])

F(9021, LE, 2020, "Orrin Paquette",
  [("Director of Photography", "Hamish Rudd"), ("Visual Effects Supervisor", "Daria Holt")],
  [
   [C("Little Engines combines live action with miniature railway sets built at a model workshop in Derby.",
      ),
    C("Principal photography used the RED Komodo, which the production chose for its size inside the miniatures.",
      k("RED Komodo", "camera", A, "positive"))],
  ],
  [K2])

P(K1, "The Film Stage", "Hamish Rudd on the 2 a.m. World of 'Pale Hours'", PH, [
  [C("Ilse Marchetti's Pale Hours takes place between 2 and 5 a.m., and Hamish Rudd shot it on the Sony Venice 2 at high ISO.",
     k("Sony Venice 2", "camera", A, "positive"))],
  ["The Film Stage: Were you tempted by film?",
   C("Rudd: For about a week. We could have used Kodak Vision3 500T pushed two stops, but the grain would have eaten the faces.",
     k("Kodak Vision3 500T", "stock", R, "counterfactual"))],
  [C("Rudd: Instead we leaned on the city's own light, a few Astera tubes, maybe six or eight, hidden in doorways, and a lot of practicals.",
     k("Astera tubes", "lighting", A, "estimated"),
     k("practicals", "lighting", A, "positive")),
   C("Rudd: There might be a Steadicam shot in the hospital, I honestly forget.",
     k("Steadicam", "support", X, "ambiguous"))],
  ["The Film Stage: There's a gorgeous shot through a split diopter in the laundromat.",
   C("Rudd: That's actually two plates comped together; there was no diopter on the lens.",
     k("diopter", "lens", R, "faux", ctx="Answer to the question about the 'split diopter' shot; it was a comp."))],
  [C("Rudd: The release was presented at 2.39:1 in cinemas, but we composed for 2.00:1 and the cinema version is a crop.",
     k("2.39:1", "aspect", R, "mixed", why="Mixed sentence: 2.39:1 is only the cinema presentation crop."),
     k("2.00:1", "aspect", A, "mixed"))],
])

P(K2, "IndieWire", "'Little Engines' DP Hamish Rudd on Shooting Miniature Trains", LE, [
  [C("Orrin Paquette's Little Engines blends live action with miniature model railways, and Hamish Rudd shot both on the RED Komodo.",
     k("RED Komodo", "camera", A, "physicalGear"))],
  [C("For the miniatures, Rudd used Zeiss Super Speed lenses with a Black Pro-Mist to soften the plastic edges.",
     k("Zeiss Super Speed", "lens", A, "positive"),
     k("Black Pro-Mist", "filter", A, "positive"))],
  [C("“Paquette had wanted a VistaVision look for the trains,” Rudd recalls, “but in the end we simulated it by shooting tiny sensor crops and scaling up.”",
     k("VistaVision", "format", R, "faux")),
   C("Paquette has said in other interviews that a Super 8 feel was achieved for the flashbacks, without saying how.",
     k("Super 8", "format", X, "ambiguous", ctx="A 'feel' could be real Super 8 or emulation; not specified."))],
  [C("The Steadicam shots through the model village were achieved with a snorkel lens on a motion-control rig, not a Steadicam at all, despite what the press notes claimed.",
     k("Steadicam", "support", R, "denial", ctx="Negation placed at the end of the sentence."))],
  [C("Rudd shot the station-platform scenes at magic hour over three evenings.",
     k("magic hour", "lighting", A, "positive"))],
])

P(K3, "American Cinematographer", "Hamish Rudd: Two Kinds of Night", LE, [
  ["Hamish Rudd was a camera operator for a decade before shooting Little Engines in 2020."],
  ["Q: Pale Hours and Little Engines are both night films in a way.",
   C("Rudd: Yes, and both were lit with LED panels on dimmers, which you can do now in a way you couldn't ten years ago.",
     k("LED panels", "lighting", A, "multiFilmInterview"),
     k("LED panels", "lighting", A, "multiFilmInterview", film=PH))],
  ["Q: Which one was harder?",
   C("Rudd: On Little Engines we shot a camera test on 16mm, and Orrin loved it so much that the dream sequence ended up on 16mm.",
     k("16mm", "format", A, "adoptedTest"),
     k("16mm", "format", R, "multiFilmInterview", about=LE, film=PH))],
  ["Q: Do you have a favourite lens?",
   C("Rudd: Probably the Zeiss Super Speed; I'd use it on everything if producers let me.",
     k("Zeiss Super Speed", "lens", R, "hypothetical", film=PH, why="General preference and a conditional wish; says nothing about Pale Hours."))],
])

S("American Cinematographer", "Hamish Rudd", [K3])
