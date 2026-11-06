#!/usr/bin/env python3
"""Builds the single review page from branding/concepts/, with every SVG inlined as a data URI.

    build_page.py <output.html>
"""
import html
import pathlib
import sys
import urllib.parse

ROOT = pathlib.Path(__file__).parent / "concepts"

CONCEPTS = [
    ("01-throw", "Throw",
     "An F cut from projector light: three throws leave one bright corner and widen as they go.",
     "Bold and legible at every size. Peach keeps it off Netflix red and Plex amber, but it's the warmest of the five, so it's the one to compare against those on a real screen."),
    ("02-ligature", "Ligature",
     "The printer's fi, the oldest piece of finesse in typography, with the hook of the f resolving into the dot of the i.",
     "The most ownable idea, because it comes from the name itself, and it's the only light icon, so it stands out on a dark Home Screen. It does read as “Fi” alone, and Google Fi and Wi-Fi share those letters."),
    ("03-flourish", "Flourish",
     "A fencer's flourish: one tapered blade stroke and a parry across it make a lowercase f.",
     "The most elegant, and the thinnest at small sizes. It leans toward beauty or dance, which matters because a FINESSE dance-training app already exists."),
    ("04-palace", "Palace",
     "The nested arches of an old picture palace, receding toward a lit screen.",
     "The best use of parallax: each arch sits at its own depth and the screen floats forward. There's no letter in it, so it relies on the name beside it until people know it. Arches are a common motif in general."),
    ("05-house-lights", "House Lights",
     "An F of aisle lights in the moment the house dims, bright at the stem and fading outward.",
     "The most playful and the most unusual colour. It's the weakest small: the faint dots start to disappear at the smallest sizes shown here."),
]

CHECKS = [
    ("FINESSE TV", "https://apkpure.com/finesse-tv/com.finessetv.iptvbox", "An Android IPTV app, with a <a href=\"https://finessetv.com/\">distribution site</a>. Same category and the closest clash found. One listing was last updated in 2019, and I couldn't tell whether it's still active."),
    ("FINESSE: Workout Programs", "https://apps.apple.com/app/id6751916496", "A dance and fitness app on the App Store and Google Play, launched in 2025. Same store, different category. A <a href=\"https://markinton.com/trademark/finesse-99239423\">pending US filing</a> covers dance-training apps."),
    ("Cisco Finesse", "https://developer.cisco.com/docs/finesse/", "Contact-centre agent desktop software. A big company, but an unrelated field."),
    ("Finesse (2014)", "https://www.justwatch.com/us/movie/finesse", "A film title, which only matters for search results."),
    ("Finesse Media Services", "https://www.cbinsights.com/compare/finesse-media-services-vs-ziotag", "A US subtitling and localisation vendor. Media-adjacent, but not a consumer app."),
]


def uri(path):
    return "data:image/svg+xml," + urllib.parse.quote(path.read_text(), safe="")


def icon(slug, label, cls=""):
    folder = ROOT / slug
    return (
        f'<div class="ticon {cls}" tabindex="0" role="img" aria-label="{html.escape(label)}"><div class="tilt">'
        f'<img class="l back" alt="" src="{uri(folder / "icon-back.svg")}">'
        f'<img class="l middle" alt="" src="{uri(folder / "icon-middle.svg")}">'
        f'<img class="l front" alt="" src="{uri(folder / "icon-front.svg")}">'
        '<span class="sheen"></span></div></div>'
    )


def panel(slug, tone, name):
    folder = ROOT / slug
    symbol = uri(folder / f"symbol-on-{tone}.svg")
    label = "On dark" if tone == "dark" else "On light"
    return f"""<figure class="panel {tone}">
      <figcaption>{label}</figcaption>
      <img class="sym" src="{symbol}" alt="{name} symbol, {label.lower()}">
      <img class="lock" src="{uri(folder / f"lockup-on-{tone}.svg")}" alt="{name} with the Finesse wordmark, {label.lower()}">
      <div class="sizes" aria-label="Symbol alone at 64, 32 and 16 points">
        <img src="{symbol}" width="64" height="64" alt=""><img src="{symbol}" width="32" height="32" alt=""><img src="{symbol}" width="16" height="16" alt="">
      </div>
    </figure>"""


def layer_strip(slug):
    folder = ROOT / slug
    cells = "".join(
        f'<figure><img src="{uri(folder / f"icon-{n}.svg")}" alt="{n} layer"><figcaption>{n}</figcaption></figure>'
        for n in ("back", "middle", "front")
    )
    return f'<div class="layers">{cells}</div>'


def section(index, slug, name, idea, note):
    number = f"{index:02d}"
    return f"""<section class="concept" id="c{number}">
  <header><span class="num">{number}</span><h2>{name}</h2></header>
  <p class="idea">{idea}</p>
  <div class="grid">
    {panel(slug, "dark", name)}
    {panel(slug, "light", name)}
    <div class="tv">
      <h3>tvOS icon, 400x240</h3>
      {icon(slug, f"{name} as a tvOS icon", "sway")}
      {layer_strip(slug)}
      <h3>On the Home Screen</h3>
      <div class="glassrow">
        <div class="s240">{icon(slug, f"{name} at 240 wide")}</div>
        <div class="s120">{icon(slug, f"{name} at 120 wide")}</div>
        <div class="s60">{icon(slug, f"{name} at 60 wide")}</div>
      </div>
    </div>
  </div>
  <p class="note">{note}</p>
</section>"""


def home_row(tone):
    cells = "".join(
        f'<div class="cell">{icon(slug, name)}<span>{i:02d} {name}</span></div>'
        for i, (slug, name, _, _) in enumerate(CONCEPTS, 1)
    )
    return f'<div class="wall {tone}"><div class="plate">{cells}</div></div>'


CSS = """
:root{--bg:#0c0d10;--fg:#ecebe6;--muted:#a3a39b;--line:#2a2b30;--accent:#ff9f80;
--sample-dark:#050506;--sample-light:#f4f2ec;--sample-dark-fg:#a7a7a7;--sample-light-fg:#5f5e58;color-scheme:dark}
@media (prefers-color-scheme:light){:root:not([data-theme="dark"]){--bg:#f6f4ee;--fg:#191a1d;--muted:#5d5d56;--line:#d8d5ca;--accent:#b4472a;color-scheme:light}}
:root[data-theme="light"]{--bg:#f6f4ee;--fg:#191a1d;--muted:#5d5d56;--line:#d8d5ca;--accent:#b4472a;color-scheme:light}
*{box-sizing:border-box}
body{background:var(--bg);color:var(--fg);font:16px/1.55 "IBM Plex Sans",system-ui,sans-serif}
main{max-width:1240px;margin:0 auto;padding-block:48px 96px;padding-left:max(16px,env(safe-area-inset-left,0px));padding-right:max(16px,env(safe-area-inset-right,0px));overflow-x:clip;display:flex;flex-direction:column;gap:72px}
h1{font:400 clamp(36px,6vw,64px)/1.05 "Newsreader",Georgia,serif;margin:0;text-wrap:balance}
h2{font:400 clamp(28px,4vw,42px)/1.1 "Newsreader",Georgia,serif;margin:0}
h3,figcaption,.mono{font:500 12px/1.4 "IBM Plex Mono",ui-monospace,monospace;letter-spacing:.06em;text-transform:uppercase;margin:0}
.lead{max-width:62ch;color:var(--muted);margin:16px 0 0}
.intro{display:flex;flex-direction:column;gap:32px}
.wall{border-radius:20px;padding:clamp(16px,3vw,32px);overflow:hidden}
.wall.dark{background:radial-gradient(90% 140% at 15% 10%,#3a4a55,transparent 60%),radial-gradient(80% 120% at 90% 90%,#5b3a34,transparent 60%),#101216}
.wall.light{background:radial-gradient(90% 140% at 15% 10%,#cfe0e4,transparent 60%),radial-gradient(80% 120% at 90% 90%,#f0d6c6,transparent 60%),#eceae3}
.plate{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:24px;padding:20px;border-radius:24px;background:rgba(255,255,255,.08);box-shadow:inset 0 1px 0 rgba(255,255,255,.35),inset 0 0 0 1px rgba(255,255,255,.12);-webkit-backdrop-filter:blur(24px) saturate(1.4);backdrop-filter:blur(24px) saturate(1.4)}
.wall.light .plate{background:rgba(255,255,255,.35)}
.cell{display:flex;flex-direction:column;gap:10px;min-width:0}
.cell span{font:500 12px/1.3 "IBM Plex Mono",ui-monospace,monospace}
.wall.dark .cell span{color:#e8e8e2}.wall.light .cell span{color:#2a2a26}
.concept{display:flex;flex-direction:column;gap:20px;border-top:1px solid var(--line);padding-top:28px;scroll-margin-top:24px}
.concept header{display:flex;align-items:baseline;gap:16px}
.num{font:500 15px "IBM Plex Mono",ui-monospace,monospace;color:var(--accent)}
.idea{font:400 clamp(19px,2.2vw,24px)/1.35 "Newsreader",Georgia,serif;max-width:48ch;margin:0;text-wrap:pretty}
.note{color:var(--muted);max-width:68ch;margin:0}
.grid{display:grid;grid-template-columns:repeat(12,minmax(0,1fr));gap:16px}
.panel{grid-column:span 3;margin:0;border-radius:16px;padding:18px;display:flex;flex-direction:column;align-items:center;justify-content:space-between;gap:20px;min-width:0}
.panel figcaption{align-self:flex-start}
.panel.dark{background:var(--sample-dark);box-shadow:inset 0 0 0 1px rgba(255,255,255,.14)}.panel.dark figcaption{color:var(--sample-dark-fg)}
.panel.light{background:var(--sample-light);box-shadow:inset 0 0 0 1px rgba(0,0,0,.1)}.panel.light figcaption{color:var(--sample-light-fg)}
.sym{width:min(100%,220px);aspect-ratio:1}
.lock{width:100%;max-width:240px}
.sizes{display:flex;align-items:center;gap:16px}
.tv{grid-column:span 6;display:flex;flex-direction:column;gap:14px;min-width:0}
.tv h3{color:var(--muted)}
.ticon{perspective:900px;width:100%;max-width:400px;aspect-ratio:5/3;outline:none;--px:0;--py:0;cursor:default;touch-action:pan-y}
.tilt{position:relative;width:100%;height:100%;border-radius:clamp(4px,3.2%,14px);overflow:hidden;transform:rotateX(calc(var(--py)*-5deg)) rotateY(calc(var(--px)*5deg));transition:scale .18s ease,box-shadow .18s ease;box-shadow:0 6px 16px rgba(0,0,0,.28)}
.ticon.on .tilt,.ticon:focus-visible .tilt{scale:1.06;box-shadow:0 22px 42px rgba(0,0,0,.45)}
.l{position:absolute;inset:0;width:100%;height:100%;display:block}
.l.back{transform:translate(calc(var(--px)*-.5%),calc(var(--py)*-.5%)) scale(1.03)}
.l.middle{transform:translate(calc(var(--px)*1.2%),calc(var(--py)*1.2%)) scale(1.03)}
.l.front{transform:translate(calc(var(--px)*2.6%),calc(var(--py)*2.6%)) scale(1.06)}
.sheen{position:absolute;inset:0;pointer-events:none;opacity:0;transition:opacity .18s ease;background:radial-gradient(60% 70% at calc(50% + var(--px)*40%) calc(5% + var(--py)*25%),rgba(255,255,255,.14),transparent 70%);box-shadow:inset 0 1px 0 rgba(255,255,255,.3)}
.ticon.on .sheen,.ticon.sway .sheen,.ticon:focus-visible .sheen{opacity:1}
.layers{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px;max-width:400px}
.layers figure{margin:0;display:flex;flex-direction:column;gap:6px}
.layers img{width:100%;aspect-ratio:5/3;border-radius:6px;background:repeating-conic-gradient(#8a8a86 0 25%,#6f6f6b 0 50%) 0 0/16px 16px}
.layers figcaption{color:var(--muted)}
.glassrow{display:flex;flex-wrap:wrap;align-items:flex-end;gap:18px;padding:18px;border-radius:18px;background:radial-gradient(90% 140% at 15% 10%,#3a4a55,transparent 60%),radial-gradient(80% 120% at 90% 90%,#5b3a34,transparent 60%),#101216;box-shadow:inset 0 1px 0 rgba(255,255,255,.28)}
.s240{width:min(240px,100%)}.s120{width:120px}.s60{width:60px}
.checks{display:flex;flex-direction:column;gap:18px;border-top:1px solid var(--line);padding-top:28px}
.checks dl{display:grid;grid-template-columns:minmax(0,240px) minmax(0,1fr);gap:12px 24px;margin:0;max-width:940px}
.checks dt{font-weight:500}.checks dd{margin:0;color:var(--muted)}
a{color:var(--accent)}
@media (max-width:980px){.panel{grid-column:span 6}.tv{grid-column:span 12}}
@media (max-width:560px){.panel{grid-column:span 12}.checks dl{grid-template-columns:minmax(0,1fr);gap:4px}.checks dd{margin-bottom:12px}}
"""

JS = """
const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
const icons = [...document.querySelectorAll('.ticon')].map(el => ({el, x: 0, y: 0, tx: 0, ty: 0, on: false}));
for (const i of icons) {
  i.el.addEventListener('pointermove', e => {
    const r = i.el.getBoundingClientRect();
    i.tx = Math.max(-1, Math.min(1, (e.clientX - r.left) / r.width * 2 - 1));
    i.ty = Math.max(-1, Math.min(1, (e.clientY - r.top) / r.height * 2 - 1));
    i.on = true; i.el.classList.add('on');
  });
  const off = () => { i.on = false; i.tx = i.ty = 0; i.el.classList.remove('on'); };
  i.el.addEventListener('pointerleave', off);
  i.el.addEventListener('pointercancel', off);
}
function frame(t) {
  for (const i of icons) {
    let tx = i.tx, ty = i.ty;
    if (!i.on && !reduced && i.el.classList.contains('sway')) {
      tx = Math.sin(t / 1700) * 0.75;
      ty = Math.cos(t / 2300) * 0.55;
    }
    i.x += (tx - i.x) * 0.12;
    i.y += (ty - i.y) * 0.12;
    i.el.style.setProperty('--px', i.x.toFixed(3));
    i.el.style.setProperty('--py', i.y.toFixed(3));
  }
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
"""


def main():
    sections = "\n".join(section(i, *c) for i, c in enumerate(CONCEPTS, 1))
    checks = "\n".join(
        f'<dt><a href="{url}">{html.escape(name)}</a></dt><dd>{text}</dd>' for name, url, text in CHECKS
    )
    page = f"""<title>Finesse Logo Concepts</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@500&family=IBM+Plex+Sans:wght@400;500&family=Newsreader:opsz,wght@6..72,400&display=swap">
<style>{CSS}</style>
<main>
  <div class="intro">
    <div>
      <h1>Finesse: five logo concepts</h1>
      <p class="lead">Each one is an original vector drawing with a symbol, a wordmark and three icon layers. Pick by number, or mix them, such as one concept's symbol with another's colour. Move a pointer or finger across any icon to tilt it.</p>
    </div>
    {home_row("dark")}
    {home_row("light")}
  </div>
  {sections}
  <section class="checks">
    <h2>Name and mark checks</h2>
    <p class="note">This is a quick web search of the name and a comparison from memory, not a legal clearance. No official trademark register was searched, and that includes IP Australia and the USPTO. A search of those is worth doing before release, whichever mark wins.</p>
    <dl>{checks}</dl>
    <p class="note"><strong>The marks:</strong> compared by eye and from memory against Plex, Netflix, Prime Video, Apple TV, Jellyfin, Infuse, Emby, Kodi, VLC, Swiftfin, Moonfin, FinPlus, Disney+, Hulu, Max, Fire TV, Fubo and Facebook's f, with no reverse image search. Nothing here is derived from those, and no direct clash stood out. A sixth concept, three glass panes stacked into an F, was dropped because it sat too close to Microsoft's Fluent office icons, Forms in particular.</p>
    <p class="note"><strong>This preview:</strong> the tilt, sheen and glass plate are a browser approximation, not the system's rendering. Apple's guidance describes parallax and focus for tvOS icons and doesn't say they take on Liquid Glass, so the winner needs checking on the real Apple TV.</p>
  </section>
</main>
<script>{JS}</script>
"""
    pathlib.Path(sys.argv[1]).write_text(page)


if __name__ == "__main__":
    main()
