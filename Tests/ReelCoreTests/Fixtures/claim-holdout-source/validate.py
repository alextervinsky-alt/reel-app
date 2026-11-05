"""Independent validator for holdout2.json (reads only the JSON)."""
import json, os, sys, collections

path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "holdout2.json")
d = json.load(open(path, encoding="utf-8"))
errs = []
E = errs.append

SITES = {"American Cinematographer": "theasc.com", "British Cinematographer": "britishcinematographer.co.uk",
         "IndieWire": "indiewire.com", "Variety": "variety.com", "Kodak": "kodak.com",
         "No Film School": "nofilmschool.com", "Filmmaker": "filmmakermagazine.com",
         "befores & afters": "beforesandafters.com", "The Film Stage": "thefilmstage.com",
         "ProVideo Coalition": "provideocoalition.com", "Cinesite": "cinesite.com"}
PROPS = set("camera lens stock format aspect lighting support movement filter finish vfx".split())
TYPES = set("positive denial comparison multiFilmInterview context abandonedPlan adoptedTest counterfactual "
            "hypothetical estimated otherPractice environment physicalGear vfxCG faux delivery productClaim "
            "mixed ambiguous".split())
PROVIDER_DOMAIN = {"American Cinematographer": "theasc.com", "ProVideo Coalition": "provideocoalition.com",
                   "Cinesite": "cinesite.com"}

films = d["films"]; pages = d["pages"]; searches = d["searches"]; claims = d["claims"]
assert set(d) == {"films", "pages", "searches", "claims"}
titles = {f["title"]: f for f in films}
if len(titles) != len(films): E("duplicate film titles")
ids = [f["id"] for f in films]
if len(set(ids)) != len(ids): E("duplicate film ids")
for f in films:
    if not (9001 <= f["id"] <= 9999): E(f"id range {f['id']}")
    if not 0 <= len(f["firstPass"]) <= 4: E(f"firstPass size {f['title']}")
    for c in f["crew"]:
        if set(c) != {"job", "name"}: E(f"crew keys {f['title']}")
bypage = {}
for p in pages:
    if p["url"] in bypage: E(f"dup page {p['url']}")
    bypage[p["url"]] = p
    if p["site"] not in SITES: E(f"bad site {p['site']}")
    elif SITES[p["site"]] not in p["url"]: E(f"domain mismatch {p['url']}")
    if not (p["url"].startswith("https://") ): E(f"url scheme {p['url']}")
    if len(p["paragraphs"]) < 3: E(f"<3 paragraphs {p['url']}")
    if p["failure"] not in (None, "unavailable"): E(f"failure value {p['url']}")
for f in films:
    for u in f["firstPass"]:
        if u not in bypage: E(f"firstPass url missing {u}")
for s in searches:
    if s["provider"] not in PROVIDER_DOMAIN: E(f"provider {s['provider']}")
    for h in s["hits"]:
        if h["url"] not in bypage: E(f"hit url missing {h['url']}")
        elif bypage[h["url"]]["title"] != h["title"]: E(f"hit title mismatch {h['url']}")
        if PROVIDER_DOMAIN.get(s["provider"], "@@") not in h["url"]: E(f"hit domain {h['url']}")
    if s["provider"] == "Cinesite":
        if s["query"] not in titles: E(f"cinesite query not a title {s['query']}")
    else:
        if not any(s["query"] == c["name"] for f in films for c in f["crew"]): E(f"query not crew {s['query']}")

def reachable(f):
    r = set(f["firstPass"])
    names = {c["name"] for c in f["crew"]}
    for s in searches:
        if (s["provider"] == "Cinesite" and s["query"] == f["title"]) or \
           (s["provider"] != "Cinesite" and s["query"] in names):
            r |= {h["url"] for h in s["hits"]}
    return r

reach = {f["title"]: reachable(f) for f in films}
for t, r in reach.items():
    if len(r) > 9: E(f"{t} reaches {len(r)} pages")
allr = set().union(*reach.values())
for u in bypage:
    if u not in allr: E(f"page unreachable {u}")

cids = set()
for c in claims:
    if c["id"] in cids: E(f"dup claim id {c['id']}")
    cids.add(c["id"])
    if c["film"] not in titles: E(f"{c['id']} film {c['film']}")
    if c["aboutFilm"] and c["aboutFilm"] not in titles: E(f"{c['id']} aboutFilm {c['aboutFilm']}")
    if c["property"] not in PROPS: E(f"{c['id']} property")
    if c["evidenceType"] not in TYPES: E(f"{c['id']} type {c['evidenceType']}")
    if c["expected"] not in ("accept", "reject", "abstain"): E(f"{c['id']} expected")
    if c["expected"] == "accept" and c["aboutFilm"] != c["film"]: E(f"{c['id']} accept but aboutFilm != film")
    if c["term"] not in c["passage"]: E(f"{c['id']} term not in passage")
    if not c["context"] or not c["rationale"]: E(f"{c['id']} empty context/rationale")
    src = c["source"]
    if src.startswith("article:"):
        t = src[len("article:"):]
        if t not in titles: E(f"{c['id']} article title")
        elif not any(c["passage"] in para for para in titles[t]["article"]): E(f"{c['id']} passage not in article")
        if t != c["film"]: E(f"{c['id']} article of another film")
    else:
        if src not in bypage: E(f"{c['id']} source missing")
        else:
            p = bypage[src]
            if not any(c["passage"] in para for para in p["paragraphs"]): E(f"{c['id']} passage not in page")
            if p["failure"]: E(f"{c['id']} claim on failed page")
            if src not in reach[c["film"]]: E(f"{c['id']} source not reachable from {c['film']}")

# a passage+term+film triple should be unique
trip = collections.Counter((c["source"], c["passage"], c["term"], c["film"]) for c in claims)
for t, n in trip.items():
    if n > 1: E(f"duplicate claim {t}")

print("films", len(films), "pages", len(pages), "searches", len(searches), "claims", len(claims))
exp = collections.Counter(c["expected"] for c in claims)
print("expected:", {k: f"{v} ({100*v/len(claims):.0f}%)" for k, v in exp.items()})
et = collections.Counter(c["evidenceType"] for c in claims)
print("evidenceType:", dict(sorted(et.items(), key=lambda x: -x[1])))
missing = TYPES - set(et)
if missing: E(f"types never used: {missing}")
for t in TYPES:
    fs = {c["film"] for c in claims if c["evidenceType"] == t}
    if et[t] < 4 or len(fs) < 3: E(f"type {t} too thin: {et[t]} claims over {len(fs)} films")
print("reach max", max(len(r) for r in reach.values()))
print("unavailable pages", sum(1 for p in pages if p["failure"]))
if errs:
    print("\nERRORS:"); [print(" -", e) for e in errs]; sys.exit(1)
print("OK: all consistency checks passed")
