# holdout2: blind test corpus for cinematography claims

`holdout2.json` was written without looking at the program it tests. Every film, person, article, quote and URL path is invented. Only the equipment and technique names are real. The titles are ordinary words and were checked only against the author's own knowledge, so a one-word title such as "Kettle" or "Sundial" could match an obscure real short film. None is meant to refer to one.

## Contents
- 30 films (ids 9001-9030), 56 pages (3 have `failure: "unavailable"`), 22 searches, 299 claims.
- Expected outcomes: 128 accept (43%), 129 reject (43%), 42 abstain (14%).
- All 19 evidence types appear, each across at least 3 films.

## How the files fit together
- `fw.py` holds the authoring helpers. Each paragraph is a list of sentences, and a sentence can carry claims. The paragraph text is the sentences joined with single spaces, so every claim passage is a verbatim sentence of its source.
- `d1.py` to `d4.py` hold the content. They are grouped in pairs of films that share a director of photography, plus a 2023 roundup page that covers six films.
- `gen.py` builds the JSON. The authored material produced 411 claims. `gen.py` keeps every claim with an unusual structure (listed in `KEEP`) and trims routine classes per film and overall to reach the target size and the rough 45/40/15 split.
- `validate.py` runs all of the requested consistency checks and prints the distributions. Run `python3 -I gen.py && python3 -I validate.py`.

## Design
- **Reachability.** Pages reach a film through `firstPass` and through searches. American Cinematographer and ProVideo Coalition are searched by crew names, and several directors of photography, a colorist, a gaffer and a Steadicam operator are shared between two films. Cinesite is searched by film title. The largest number of pages any film can reach is 6.
- **One sentence, several films.** Many sentences are read for two films and get one claim per film. Examples are interviews covering two productions, "Unlike X, Y…" comparisons, and the roundup page, where each entry is introduced by the film's title.
- **Title traps.**
  - Some page text writes a title differently: `Wait… Then Run` (Unicode ellipsis), `Wait Then Run` (no ellipsis), `Odile’s Garden` (curly apostrophe), `Salt and Cinder` ("and" for "&"), `Half–Light Ferry` (en dash), and `Marrow` without its subtitle.
  - Some text uses a title word in its ordinary sense: "motorway overpass in Lyon", "paper lanterns", "lantern room", "brine shrimp", "dovetailed", "dovetail joint", "stone sundial", "field notes", "kettle whistles".
  - The Cinesite search for "Lantern" also returns a page about another production, the series *The Lantern Keepers*. Claims from that page are rejected for *Lantern*.
- **Context cases where the subject carries over.** A Q&A question names the film. A later question returns to the film ("Back to Marrow…"). "The ferry film" or "the bakery film" refers back to a film already named. An entry is introduced by the film's title.
- **Context cases where the subject does not carry over.** A biography paragraph, a commercial, music videos, a graduation film or an "unseen first feature". A switch to the other film in the next question ("Q: And Gannet Point?").
- **Trap terms.** These look like gear but are not: "harbour crane", LED panels used as props or set dressing, a prop Super 8 camera, a prop Arriflex 416, a prop Canon C300 Mark II, a Leica Summilux-C sketched in the character's notebook, a virtual camera, virtual or CG HMI, CG tungsten and CG LED panels, a faux split diopter, simulated anamorphic flares, a simulated 65mm look, an emulated bleach bypass, and an emulated VistaVision look.

## Debatable labels
1. **Implied in a comparison.** "Just as on Lantern, Rensch shot Pilgrim Tide on 16mm" and "As with The Weight of Gulls…" are labelled only for the film the sentence is mainly about. They are not read for the film they compare against, even though they imply something about it. The one other-film reading included is the relative-clause case "Unlike Odile's Garden, which she lit with HMIs, …", which is accepted for *Odile's Garden* because the clause states it outright.
2. **Product claims about gear the film did use.** "Panavision says the Millennium XL2 is among the quietest 35mm cameras…" (*Salt & Cinder*) and "ARRI advertises 17 stops… for the Alexa 35…" (*Sundial*) are rejected. The passage only states what the product can do, even though another sentence on the same page shows the film used it. A system that judges the whole page would still accept the term for the film from that other sentence.
3. **Practicals.**
   - *Vesper Street*: neon practicals built by the art department are accepted because they are said to be the key light. LED panel lightboxes on the same street, switched off and left as set dressing, are rejected.
   - *Lantern* (Cinesite page): "sodium practicals visible in the 16mm plates" is accepted as real practical lamps photographed on set, even though the sentence is mainly about CG lighting.
4. **Sundial drone.** It is abstain on a page that reports it as a rumour, while the film's own article denies any drone use. The labels are per passage, so the two sources disagree on purpose.
5. **Statements in another film's article.**
   - The Signal Hill Road page says a road sign "appears in a crane shot" in *Fieldnote*. That is accepted for *Fieldnote* and rejected for *Signal Hill Road*.
   - The Kettle Kodak page says "On Gannet Point… Hollis had leaned heavily on a Technocrane". That is accepted for *Gannet Point*.
6. **Delivery labels.**
   - *Crosswind Bakery*: "Presented in 1.85:1… matching the frame it was shot in" is accepted, the only accept among the delivery claims.
   - *Tin Crown*'s own article: "presented in 1.85:1" with nothing about how it was shot is abstain.
   - *Gannet Point*: the film-out for the festival copy is rejected as delivery.
7. **Bleach bypass.** On the Hollow Clock page, "kept from Salt & Cinder… the bleach bypass look" is abstain for *Salt & Cinder*, because it does not say whether the look came from a real lab process.
8. **Context.**
   - *Static Bloom* / *Overpass*: "We used handheld for every scene inside the greenhouse" is accepted for *Static Bloom*. The greenhouse has only been tied to *Static Bloom* in the previous paragraph, and the question mentions *Overpass*.
   - *Hollow Clock* / *Salt & Cinder*: "the clock tower set was almost all tungsten" answers a question that names *Salt & Cinder*. It is accepted for *Hollow Clock* and rejected for *Salt & Cinder*.
9. **Test only.** "Tested… but did not make the final cut" and "none of it made the cut" are rejected. "Loved it so much that the dream sequence ended up on 16mm" (*Little Engines*) and "the Super Speeds made it into the film" (*The Copper Season*) are accepted.
10. **Word mismatch.** On *Pale Hours*, the question says "split diopter" but the answer says only "diopter". The claim uses the term "diopter" (faux, reject).
11. **"Steadicam M-2 Volt"** (*Overpass*) is abstain. The operator says he owns it "now", which leaves open whether it was used on his most recent film.
