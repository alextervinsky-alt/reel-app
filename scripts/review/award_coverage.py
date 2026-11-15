import traceback
# review-1.11 (throwaway): how well Wikidata covers candidate award lists. Public data only.
import json, sys, time, urllib.parse, urllib.request
UA = {"User-Agent": "Reel-review-1.11/0.1 (coverage check; github.com/alextervinsky-alt/reel-app)"}
def get(url):
    for i in range(4):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=90) as r:
                return json.load(r)
        except Exception as e:
            err = e; time.sleep(5 * (i + 1))
    raise err
def search(term):
    u = "https://www.wikidata.org/w/api.php?" + urllib.parse.urlencode(
        {"action": "wbsearchentities", "search": term, "language": "en", "type": "item", "limit": 4, "format": "json"})
    return [(h["id"], h.get("label", ""), h.get("description", "")) for h in get(u).get("search", [])]
Q = """SELECT (COUNT(DISTINCT ?w) AS ?won) (COUNT(DISTINCT ?wt) AS ?wonTmdb) (COUNT(DISTINCT ?n) AS ?nom)
 (MIN(?y) AS ?first) (MAX(?y) AS ?last) (COUNT(DISTINCT ?y) AS ?years) WHERE {
 { { ?w wdt:P166 wd:%(q)s . } UNION { wd:%(q)s wdt:P1346 ?w . ?w wdt:P31/wdt:P279* wd:Q11424 . }
   UNION { ?p p:P166 ?s . ?s ps:P166 wd:%(q)s ; pq:P1686 ?w . }
   OPTIONAL { ?w wdt:P4947 ?t . BIND(?w AS ?wt) } OPTIONAL { ?w wdt:P577 ?d . BIND(YEAR(?d) AS ?y) } }
 UNION { { ?n wdt:P1411 wd:%(q)s . } UNION { ?p2 p:P1411 ?s2 . ?s2 ps:P1411 wd:%(q)s ; pq:P1686 ?n . } } }"""
def counts(q):
    u = "https://query.wikidata.org/sparql?" + urllib.parse.urlencode({"query": Q % {"q": q}, "format": "json"})
    b = get(u)["results"]["bindings"][0]
    return {k: int(v["value"]) for k, v in b.items()}
out = []
terms = [l.strip() for l in open(sys.argv[1]) if l.strip() and not l.startswith("#")]
for term in terms:
    try: hits = search(term)[:3]
    except Exception as e:
        out.append({"term": term, "error": "search: " + repr(e)[:200]}); continue
    if not hits: out.append({"term": term, "error": "no search hit"})
    for qid, label, desc in hits:
        try: c = counts(qid)
        except Exception as e: c = {"error": repr(e)[:200]}
        row = {"term": term, "qid": qid, "label": label, "desc": desc, **c}
        out.append(row); print("REVIEW|" + json.dumps(row), flush=True); time.sleep(1)
json.dump(out, open(sys.argv[2], "w"), indent=1)

