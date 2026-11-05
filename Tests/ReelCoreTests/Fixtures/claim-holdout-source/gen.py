import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fw, d1, d2, d3, d4  # noqa: F401  (modules register data on import)

titles = {p["url"]: p["title"] for p in fw.PAGES}
searches = [dict(provider=s["provider"], query=s["query"],
                 hits=[dict(title=titles[u], url=u) for u in s["hits"]]) for s in fw.SEARCHES]
# Pruning: the authored material yields more routine accept/context claims than the
# target size; keep every special-structure claim, and cap routine classes per film.
KEEP = ["paper lanterns", "brine shrimp", "lantern room", "The production used the Alexa Mini LF",
        "photographed it on 35mm with an Arricam LT", "For \u201cSalt and Cinder,\u201d",
        "Ourada shot on the RED V-Raptor", "with push processing", "process trailer",
        "used them as his key light", "greenhouse.", "And Gannet Point", "clock tower set",
        "desert days", "No handheld at all", "A Libra head on a small crane", "There it was the opposite",
        "On the bakery film", "tried to remember Kodak", "reused in another feature", "It mostly was, plus SkyPanels",
        "the ferry film did", "Mostly on a Technocrane parked", "Very little. The negative",
        "motorway overpass in Lyon", "The series was shot on the ARRI Alexa 65", "Flying-ship plates",
        "In Norway, the commercial", "Those were mostly Blackmagic Pocket", "That was the opposite problem",
        "graduation film was shot", "first credits as cinematographer"]
CAPS = {("positive", "accept"): 1, ("physicalGear", "accept"): 1, ("context", "accept"): 1,
        ("context", "reject"): 1, ("multiFilmInterview", "accept"): 1, ("multiFilmInterview", "reject"): 1}
ROUNDUP = "https://www.indiewire.com/features/craft/best-cinematography-2023-1234901177/"
seen = {}
kept = []
for c in fw.CLAIMS:
    key = (c["evidenceType"], c["expected"])
    special = c["source"] == ROUNDUP or any(x in c["passage"] for x in KEEP)
    if key in CAPS:
        n = seen.get((c["film"],) + key, 0)
        if n >= CAPS[key] and not special:
            continue
        seen[(c["film"],) + key] = n + 1
    kept.append(c)
# Second pass: global caps on reject classes to approach a 45/40/15 split, dropping
# first from the films that have the most claims (never a KEEP-listed passage).
GCAPS = {("context", "accept"): 29, ("context", "reject"): 15, ("multiFilmInterview", "reject"): 11, ("otherPractice", "reject"): 9,
         ("counterfactual", "reject"): 7, ("denial", "reject"): 11, ("hypothetical", "reject"): 6,
         ("delivery", "reject"): 7}
import collections
for key, cap in GCAPS.items():
    members = [c for c in kept if (c["evidenceType"], c["expected"]) == key]
    excess = len(members) - cap
    if excess <= 0:
        continue
    per_film = collections.Counter(c["film"] for c in kept)
    order = sorted(range(len(members)), key=lambda i: (-per_film[members[i]["film"]], -i))
    drop = set()
    for i in order:
        if len(drop) >= excess:
            break
        if any(x in members[i]["passage"] for x in KEEP):
            continue
        drop.add(id(members[i]))
        per_film[members[i]["film"]] -= 1
    kept = [c for c in kept if id(c) not in drop]
claims = []
for i, c in enumerate(kept, 1):
    claims.append(dict(id=f"c{i:03d}", **c))
films = sorted(fw.FILMS, key=lambda f: f["id"])
out = dict(films=films, pages=fw.PAGES, searches=searches, claims=claims)
path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "holdout2.json")
with open(path, "w", encoding="utf-8") as fh:
    json.dump(out, fh, ensure_ascii=False, indent=1)
print("wrote", path, len(films), "films", len(fw.PAGES), "pages", len(claims), "claims (authored", len(fw.CLAIMS), ")")
