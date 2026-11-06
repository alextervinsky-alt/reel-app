"""Validate validation-corpus.json. Run: python3 -I validate.py [path]"""
import json, os, re, sys
from collections import Counter, defaultdict

path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "validation-corpus.json")
d = json.load(open(path, encoding="utf-8"))
errors, warnings = [], []
def err(m): errors.append(m)

PROPS = {"camera", "lens", "format", "stock", "aspect", "lighting", "support", "movement", "filter", "finish"}
OUTS = {"accept", "reject", "abstain"}
STAGES = {"capture", "framing", "extraction", "sequence", "theatrical", "homeMedia", "restoration", "unknown"}
PROVIDERS = {"American Cinematographer", "ProVideo Coalition", "Cinesite"}
REQUIRED_EV = ["comparison", "relativeClauseThisFilm", "relativeClauseOtherGear", "sectionChange", "interviewSwitch",
               "denial", "denialException", "positiveAlternative", "unfamiliarStock", "hypothetical",
               "retrospectiveDecision", "abandonedPlan", "testOnly", "adoptedTest", "habitual", "emulation",
               "styleUsed", "prop", "payload", "crewCredit", "definition", "research", "capability",
               "capabilityAndUse", "vendorCredit", "aspectStage", "rumour", "estimate", "multiClause",
               "creditListMention", "incompletePage"]

films = {f["id"]: f for f in d["films"]}
if len(films) != len(d["films"]): err("duplicate film ids")
if len(films) != 20: err("expected 20 films, got %d" % len(films))
for f in d["films"]:
    for k in ("id", "title", "year", "director", "crew", "article", "firstPass"):
        if k not in f: err("film %s missing %s" % (f.get("id"), k))
    if not f["article"]: err("film %s has empty article" % f["id"])
    if not any(c["job"] == "Director of Photography" for c in f["crew"]): err("film %s has no DP" % f["id"])
titles = {f["title"]: f for f in d["films"]}

pages = {p["url"]: p for p in d["pages"]}
if len(pages) != len(d["pages"]): err("duplicate page urls")
if not 35 <= len(pages) <= 45: err("page count %d outside 35-45" % len(pages))
for p in d["pages"]:
    fail = p.get("failure")
    if fail not in (None, "unavailable", "incomplete"): err("bad failure on " + p["url"])
    if fail == "unavailable" and p["paragraphs"]: err("unavailable page has text: " + p["url"])
    if fail == "incomplete" and re.search(r"[.!?”’]$", p["paragraphs"][-1]): err("incomplete page ends cleanly: " + p["url"])
    if fail is None and not p["paragraphs"]: err("page without text: " + p["url"])
fails = Counter(p.get("failure") for p in d["pages"])
if fails["unavailable"] < 2 or fails["incomplete"] < 2: err("need >=2 unavailable and >=2 incomplete pages")

for f in d["films"]:
    for u in f["firstPass"]:
        if u not in pages: err("film %s firstPass url missing: %s" % (f["id"], u))

reach = set(u for f in d["films"] for u in f["firstPass"])
for s in d["searches"]:
    if s["provider"] not in PROVIDERS: err("bad provider " + s["provider"])
    for h in s["hits"]:
        if h["url"] not in pages: err("search hit missing page: " + h["url"])
        elif pages[h["url"]]["title"] != h["title"]: err("hit title mismatch: " + h["url"])
        reach.add(h["url"])
    if s["provider"] == "Cinesite" and s["query"] not in titles: err("Cinesite query is not a film title: " + s["query"])
    if s["provider"] != "Cinesite":
        names = {c["name"] for f in d["films"] for c in f["crew"]}
        if s["query"] not in names: err("crew search for unknown name: " + s["query"])
for u in pages:
    if u not in reach: err("page not reachable from search or firstPass: " + u)

def source_paras(src):
    if src.startswith("article:"):
        f = titles.get(src[len("article:"):])
        return f["article"] if f else None
    p = pages.get(src)
    return p["paragraphs"] if p else None

ids = set()
for i, c in enumerate(d["claims"], 1):
    cid = c.get("id")
    if cid != "v%03d" % i: err("claim id out of sequence: %s" % cid)
    if cid in ids: err("duplicate claim id " + cid)
    ids.add(cid)
    for k in ("film", "source", "passage", "term", "property", "expected", "aboutFilm", "evidenceType", "context", "rationale"):
        if k not in c or c[k] in ("", None): err("%s missing %s" % (cid, k))
    if c["film"] not in films: err("%s unknown film %s" % (cid, c["film"]))
    if c["property"] not in PROPS: err("%s bad property" % cid)
    if c["expected"] not in OUTS: err("%s bad expected" % cid)
    if not isinstance(c["aboutFilm"], bool): err("%s aboutFilm not bool" % cid)
    if c["property"] == "aspect":
        if c.get("stage") not in STAGES: err("%s aspect claim needs a valid stage" % cid)
    elif "stage" in c: err("%s stage on non-aspect claim" % cid)
    paras = source_paras(c["source"])
    if paras is None:
        err("%s source not found: %s" % (cid, c["source"])); continue
    src_page = pages.get(c["source"])
    if src_page and src_page.get("failure") == "unavailable": err("%s cites unavailable page" % cid)
    ps = c["passage"]
    found = False
    for para in paras:
        start = para.find(ps)
        while start != -1:
            end = start + len(ps)
            if (start == 0 or para[start - 1] == " ") and (end == len(para) or para[end] == " "):
                found = True; break
            start = para.find(ps, start + 1)
        if found: break
    if not found: err("%s passage not a verbatim sentence of %s" % (cid, c["source"]))
    if not re.search(r"[.!?][”’\"]?$", ps): err("%s passage lacks terminal punctuation" % cid)
    if re.search(r"[.!?] [A-Z]", ps): err("%s passage looks like more than one sentence" % cid)
    toks = [t for t in re.split(r"[\s/]+", c["term"].lower()) if len(t) > 1]
    prev = ""
    for j, para in enumerate(paras):
        if ps in para and j > 0: prev = paras[j - 1].lower(); break
    if not any(t in ps.lower() for t in toks):
        # Q/A answers may refer back ("that stock", "them") to a term named in the question
        if prev.startswith(("ac:", "pvc:")) and any(t in prev for t in toks):
            warnings.append("%s term '%s' resolved from preceding question" % (cid, c["term"]))
        else: err("%s term '%s' not in passage" % (cid, c["term"]))
    elif c["term"].lower() not in ps.lower(): warnings.append("%s term '%s' not verbatim in passage" % (cid, c["term"]))
    if c["source"].startswith("article:") and titles[c["source"][8:]]["id"] != c["film"]:
        warnings.append("%s article claim for another film" % cid)

n = len(d["claims"])
out = Counter(c["expected"] for c in d["claims"])
if not 180 <= n <= 240: err("claim count %d outside 180-240" % n)
for k, target in (("accept", .45), ("reject", .40), ("abstain", .15)):
    if abs(out[k] / n - target) > .06: err("%s share %.2f too far from %.2f" % (k, out[k] / n, target))

ev_films = defaultdict(set)
for c in d["claims"]:
    ev_films[c["evidenceType"]].add(c["film"])
for ev in REQUIRED_EV:
    if len(ev_films[ev]) < 2: err("evidence type %s covers %d film(s), need 2" % (ev, len(ev_films[ev])))
stage_films = defaultdict(set)
for c in d["claims"]:
    if c["property"] == "aspect": stage_films[c["stage"]].add(c["film"])
for st in STAGES:
    if len(stage_films[st]) < 2: err("aspect stage %s covers %d film(s)" % (st, len(stage_films[st])))
for fid in films:
    if not any(c["film"] == fid for c in d["claims"]): err("film %s has no claims" % fid)

print("films %d  pages %d (unavailable %d, incomplete %d)  searches %d  claims %d" % (
    len(films), len(pages), fails["unavailable"], fails["incomplete"], len(d["searches"]), n))
print("outcomes:", dict(out))
for w in warnings: print("WARN", w)
for e in errors: print("ERROR", e)
print("RESULT:", "PASS" if not errors else "FAIL (%d errors)" % len(errors))
sys.exit(1 if errors else 0)
