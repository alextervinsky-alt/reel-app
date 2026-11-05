"""Tiny framework for authoring the holdout corpus.

Paragraphs are lists of sentences; a sentence may carry claims (C(...)).
The paragraph text is the sentences joined by a single space, so every
claim passage is guaranteed to be a verbatim sentence of its source.
"""
FILMS, PAGES, SEARCHES, CLAIMS = [], [], [], []
A, R, X = "accept", "reject", "abstain"

KET = "Kettle"; GP = "Gannet Point"; OVP = "Overpass"; SB = "Static Bloom"
LAN = "Lantern"; PT = "Pilgrim Tide"; WTR = "Wait... Then Run"; NC = "Northbound Choir"
MAR = "Marrow: A Winter Account"; AM = "Ash Meridian"; OG = "Odile's Garden"; LO = "Low Orchard"
SC = "Salt & Cinder"; HC = "Hollow Clock"; HLF = "Half-Light Ferry"; DOV = "Dovetail"
CS = "The Copper Season"; SHR = "Signal Hill Road"; FN = "Fieldnote"; CB = "Crosswind Bakery"
BR = "Brine"; QW = "The Quarry Wives"; PH = "Pale Hours"; LE = "Little Engines"
WOG = "The Weight of Gulls"; COW = "Cradle of Wolves"; SUN = "Sundial"; IL = "Ironwood Lullaby"
VS = "Vesper Street"; TC = "Tin Crown"

WHY = {
 ("positive", A): "Plain affirmative production statement that this film used the term.",
 ("physicalGear", A): "Physical photographic equipment stated as actually used on this production.",
 ("denial", R): "The passage states the equipment/technique was avoided or not used.",
 ("comparison", A): "Comparison sentence whose main assertion is about this film.",
 ("comparison", R): "The comparison asserts the term only of the other production.",
 ("multiFilmInterview", A): "In a piece covering several productions, this statement is explicitly tied to this film.",
 ("multiFilmInterview", R): "Statement belongs to another production discussed in the same piece.",
 ("context", A): "The film is established by the surrounding question, heading or continuing subject.",
 ("context", R): "The surrounding text has moved to another subject (another production or biography), so the film context does not carry over.",
 ("abandonedPlan", R): "Originally planned but abandoned; not used.",
 ("adoptedTest", A): "The test is explicitly said to have been adopted into the final film.",
 ("adoptedTest", R): "Only tested; explicitly not used in the finished film.",
 ("counterfactual", R): "Counterfactual (could/would/had it been); not what was used.",
 ("hypothetical", R): "Speculative or future equipment, not used on this film.",
 ("estimated", A): "Use of the fixture is stated; only its specification is approximate.",
 ("otherPractice", R): "Describes general/other people's practice, not this production.",
 ("environment", R): "An object in the story or set dressing, not photographic equipment used to make the film.",
 ("vfxCG", R): "CG/virtual terminology, not physical gear.",
 ("faux", R): "The optical effect was simulated in post, not produced with the real tool.",
 ("delivery", R): "Presentation/delivery/restoration specification, not the original capture.",
 ("delivery", A): "Delivery statement that explicitly matches the original capture.",
 ("productClaim", R): "Manufacturer capability or marketing statement without production use.",
 ("mixed", A): "Mixed sentence: this term is the part actually used.",
 ("mixed", R): "Mixed sentence: this term is the part not used.",
 ("ambiguous", X): "The speaker is uncertain or the production referred to is unclear; a careful reader cannot tell.",
}


def k(term, prop, exp, et, about=None, ctx="", why="", film=None):
    return dict(term=term, property=prop, expected=exp, evidenceType=et,
                aboutFilm=about, context=ctx, rationale=why, film=film)


def C(text, *ks):
    return (text, list(ks))


def _render(paras, source, default_film, src_desc):
    out = []
    for para in paras:
        sents = []
        for item in para:
            if isinstance(item, str):
                sents.append(item)
                continue
            text, ks = item
            sents.append(text)
            for kk in ks:
                film = kk["film"] or default_film
                assert film, (source, text)
                about = kk["aboutFilm"]
                if about is None:
                    about = film if kk["expected"] == A else ""
                why = kk["rationale"] or WHY.get((kk["evidenceType"], kk["expected"])) or "See context."
                ctx = kk["context"] or f"The {src_desc} is about {film}."
                CLAIMS.append(dict(film=film, source=source, passage=text, term=kk["term"],
                                   property=kk["property"], expected=kk["expected"],
                                   aboutFilm=about, evidenceType=kk["evidenceType"],
                                   context=ctx, rationale=why))
        out.append(" ".join(sents))
    return out


def F(id, title, year, director, crew, article, firstPass):
    paras = _render(article, "article:" + title, title, "film's own encyclopedia article")
    FILMS.append(dict(id=id, title=title, year=year, director=director,
                      crew=[dict(job=j, name=n) for j, n in crew],
                      article=paras, firstPass=list(firstPass)))


def P(url, site, title, film, paras, failure=None):
    rendered = _render(paras, url, film, "page")
    PAGES.append(dict(url=url, site=site, title=title, paragraphs=rendered, failure=failure))


def S(provider, query, urls):
    SEARCHES.append(dict(provider=provider, query=query, hits=urls))
