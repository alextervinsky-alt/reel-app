#!/usr/bin/env python3
"""How many public sample films have a Rotten Tomatoes score on Wikidata (1.11.2: OMDb no longer
sends it). Public TMDB ids only; prints counts and each film's latest score with its date."""
import json, sys, urllib.parse, urllib.request

ids = sys.argv[1:]
values = " ".join(f'"{i}"' for i in ids)
query = f"""
SELECT ?tmdb ?label ?score ?method ?date WHERE {{
  VALUES ?tmdb {{ {values} }}
  ?film wdt:P4947 ?tmdb .
  OPTIONAL {{ ?film rdfs:label ?label FILTER(lang(?label) = "en") }}
  OPTIONAL {{
    ?film p:P444 ?st . ?st ps:P444 ?score ; pq:P447 wd:Q105584 .
    OPTIONAL {{ ?st pq:P459 ?method }}
    OPTIONAL {{ ?st pq:P585 ?date }}
  }}
}}"""
url = "https://query.wikidata.org/sparql?" + urllib.parse.urlencode({"query": query, "format": "json"})
req = urllib.request.Request(url, headers={"User-Agent": "Reel-CI/1.11 (personal film library app; coverage check)"})
rows = json.load(urllib.request.urlopen(req, timeout=60))["results"]["bindings"]
films = {}
for r in rows:
    t = r["tmdb"]["value"]
    f = films.setdefault(t, {"label": r.get("label", {}).get("value", "?"), "scores": []})
    if "score" in r:
        f["scores"].append((r.get("date", {}).get("value", "")[:10], r["score"]["value"], r.get("method", {}).get("value", "").rsplit("/", 1)[-1]))
have = [t for t, f in films.items() if f["scores"]]
print(f"RT on Wikidata: {len(have)} of {len(ids)} films ({len(films)} found on Wikidata)")
for t in ids:
    f = films.get(t)
    if not f:
        print(f"  {t}: not on Wikidata by TMDB id"); continue
    latest = sorted(f["scores"])[-3:]
    print(f"  {t} {f['label']}: " + ("; ".join(f"{s} ({m or 'no method'}, {d or 'no date'})" for d, s, m in latest) if latest else "none"))
