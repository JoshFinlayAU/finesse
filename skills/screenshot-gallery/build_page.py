#!/usr/bin/env python3
"""Builds the gallery page and full-size JPEGs from raw captures.
Usage: build_page.py <raw png dir> <output dir>. A screen with no new capture keeps a JPEG already in
<output dir>/images, such as one fetched from the published page. With neither, it's listed as not captured."""
import html, json, os, sys
from PIL import Image

raw, out = sys.argv[1:3]
here = os.path.dirname(os.path.abspath(__file__))
data = json.load(open(os.path.join(here, "screens.json")))
os.makedirs(os.path.join(out, "images"), exist_ok=True)
LABELS = {"real": "Test server", "seeded": "Test server, seeded", "fake": "Fake data"}

def ranges(numbers):
    """Numbers never move, so an area can hold more than one run of them."""
    runs = []
    for n in sorted(numbers):
        if runs and n == runs[-1][1] + 1:
            runs[-1][1] = n
        else:
            runs.append([n, n])
    return ", ".join(f"{a:02d}" if a == b else f"{a:02d}&ndash;{b:02d}" for a, b in runs)

def tile(s, ordered):
    number = f"{s['n']:02d}"
    png = os.path.join(raw, s["file"] + ".png")
    label = LABELS[s["src"]]
    note = f'<p class="note">{html.escape(s["note"])}</p>' if s.get("note") else ""
    head = (f'<header><span class="num">{number}</span><div class="meta"><h3>{html.escape(s["title"])}</h3>'
            f'<span class="tag {s["src"]}">{label}</span>{note}</div></header>')
    jpg = f"images/{number}.jpg"
    kept = os.path.exists(os.path.join(out, jpg))
    if not os.path.exists(png) and not kept:
        return f'<article class="shot missing" id="s{number}">{head}<div class="none">Not captured</div></article>'
    if os.path.exists(png):
        Image.open(png).convert("RGB").save(os.path.join(out, jpg), quality=90, optimize=True, subsampling=0)
    ordered.append({"n": number, "t": s["title"], "src": jpg})
    alt = html.escape(f"Screen {s['n']}: {s['title']}")
    return (f'<article class="shot" id="s{number}">{head}<button class="open" data-i="{len(ordered)-1}" '
            f'aria-label="Open {alt} at full size"><img src="{jpg}" alt="{alt}" width="3840" height="2160" '
            f'loading="lazy"></button></article>')

ordered, nav, body = [], [], []
for area in data["areas"]:
    anchor = "a-" + area["name"].lower().replace(" ", "-")
    nav.append(f'<a href="#{anchor}">{html.escape(area["name"])} <span>{ranges(x["n"] for x in area["screens"])}</span></a>')
    intro = f'<p class="intro">{html.escape(area["intro"])}</p>' if area.get("intro") else ""
    tiles = "".join(tile(s, ordered) for s in area["screens"])
    body.append(f'<section id="{anchor}"><h2>{html.escape(area["name"])}</h2>{intro}{tiles}</section>')

template = open(os.path.join(here, "page_template.html")).read()
page = (template.replace("{{NAV}}", "".join(nav)).replace("{{BODY}}", "".join(body))
        .replace("{{ITEMS}}", json.dumps(ordered)).replace("{{COUNT}}", str(len(ordered))))
open(os.path.join(out, "index.html"), "w").write(page)
print(len(ordered), "images", sum(os.path.getsize(os.path.join(out, "images", f)) for f in os.listdir(os.path.join(out, "images"))) // 1024**2, "MB")
