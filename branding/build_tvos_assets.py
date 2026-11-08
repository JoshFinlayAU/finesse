#!/usr/bin/env python3
"""Renders the Palace mark into the app's asset catalog: the layered tvOS icon, the App Store icon,
the Top Shelf images and the lockup the app shows. Writes the SVG for each one to branding/palace/.

Needs resvg_py, Pillow and fontTools, and a folder holding Marcellus as marcellus.woff:

    build_tvos_assets.py <fonts folder>
"""
import io
import json
import pathlib
import shutil
import sys

import resvg_py
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from PIL import Image

HERE = pathlib.Path(__file__).parent
SOURCE = HERE / "palace"
CATALOG = HERE.parent / "Finesse/Resources/Assets.xcassets"
BRAND = CATALOG / "App Icon & Top Shelf Image.brandassets"
INFO = {"info": {"author": "xcode", "version": 1}}
ARCH_COLORS = ("#6A2340", "#A4475C", "#D97F78")
ARCH_SHAPES = ((200, 48), (152, 96), (106, 144))
# The arches run off the bottom of the canvas, so parallax never lifts them off the floor.
FOOT = 640
ICON_SCALE, ICON_DY = 0.9, 34
# Front to back, the order an image stack lists its layers.
ICON_LAYERS = ("screen", "inner-arch", "middle-arch", "outer-arch", "back")
ICON_W, ICON_H = 800, 480


def linear(id, x1, y1, x2, y2, *stops):
    body = "".join(
        f'<stop offset="{o}" stop-color="{c}"' + (f' stop-opacity="{a[0]}"' if a else "") + "/>"
        for o, c, *a in stops
    )
    return (
        f'<linearGradient id="{id}" gradientUnits="userSpaceOnUse" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">'
        f"{body}</linearGradient>"
    )


def radial(id, cx, cy, r, *stops):
    body = "".join(
        f'<stop offset="{o}" stop-color="{c}"' + (f' stop-opacity="{a[0]}"' if a else "") + "/>"
        for o, c, *a in stops
    )
    return f'<radialGradient id="{id}" gradientUnits="userSpaceOnUse" cx="{cx}" cy="{cy}" r="{r}">{body}</radialGradient>'


def wordmark_path(font_file, text, tracking, units=100):
    """The text as one path at a cap height near `units`, and its width. Tracking is in thousandths of an em."""
    font = TTFont(font_file)
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    upem = font["head"].unitsPerEm
    cap = getattr(font["OS/2"], "sCapHeight", 0) or upem * 0.7
    scale = units / cap
    pen = SVGPathPen(glyphs, ntos=lambda v: f"{v:.1f}".rstrip("0").rstrip("."))
    x = 0.0
    for index, char in enumerate(text):
        name = cmap[ord(char)]
        glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, x, units)))
        x += glyphs[name].width * scale
        if index < len(text) - 1:
            x += tracking / 1000 * upem * scale
    return pen.getCommands(), x


def arch(cx, half, top, bottom):
    """One arch on a 512 box: straight sides up to a semicircular top."""
    return f"M{cx - half} {bottom} V{top + half} A{half} {half} 0 0 1 {cx + half} {top + half} V{bottom} Z"


def svg(width, height, body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}">{body}</svg>'


def background(width, height):
    return (
        f'<defs>{linear("bg", 0, 0, 0, height, (0, "#2C0F20"), (1, "#14060E"))}</defs>'
        f'<rect width="{width}" height="{height}" fill="url(#bg)"/>'
    )


def screen_path(foot=FOOT):
    return f'<defs>{linear("sc", 0, 196, 0, 448, (0, "#FFF4EA"), (1, "#F2B79E"))}</defs><path fill="url(#sc)" d="{arch(256, 62, 196, foot)}"/>'


def arch_path(index, foot=FOOT):
    half, top = ARCH_SHAPES[index]
    return f'<path fill="{ARCH_COLORS[index]}" d="{arch(256, half, top, foot)}"/>'


def placed(fragment, center_x, dy, scale):
    x = center_x - 256 * scale
    return f'<g transform="translate({x:.1f} {dy:.1f}) scale({scale})">{fragment}</g>'


def icon_layers():
    """Each arch on its own layer, so each moves at its own depth when the icon has focus."""
    dy = ICON_H / 2 - 256 * ICON_SCALE + ICON_DY
    place = lambda fragment: svg(ICON_W, ICON_H, placed(fragment, ICON_W / 2, dy, ICON_SCALE))
    return {
        "back": svg(ICON_W, ICON_H, background(ICON_W, ICON_H)),
        "outer-arch": place(arch_path(0)),
        "middle-arch": place(arch_path(1)),
        "inner-arch": place(arch_path(2)),
        "screen": place(screen_path()),
    }


def top_shelf(width, fonts):
    """The arches and the name, kept inside the middle 1920 points that every screen shows."""
    height = 720
    middle = width / 2
    word, word_width = wordmark_path(fonts / "marcellus.woff", "FINESSE", 160, units=86)
    glow = radial("gl", middle + 360, 420, 760, (0, "#D97F78", 0.26), (1, "#D97F78", 0))
    art = "".join(arch_path(index, foot=900) for index in range(3)) + screen_path(foot=900)
    return svg(
        width,
        height,
        background(width, height)
        + f'<defs>{glow}</defs><rect width="{width}" height="{height}" fill="url(#gl)"/>'
        + placed(art, middle + 360, 70, 1.3)
        + f'<g transform="translate({middle - 800:.1f} 318)"><path fill="#F7E3D6" d="{word}"/></g>',
    )


def png(source, width, height, opaque):
    data = bytes(resvg_py.svg_to_bytes(svg_string=source, width=width))
    image = Image.open(io.BytesIO(data)).convert("RGBA").resize((width, height), Image.LANCZOS)
    return image.convert("RGB") if opaque else image


def write_contents(folder, contents):
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "Contents.json").write_text(json.dumps({**contents, **INFO}, indent=2) + "\n")


def image_stack(name, sizes, sources):
    stack = BRAND / f"{name}.imagestack"
    write_contents(stack, {"layers": [{"filename": f"{layer}.imagestacklayer"} for layer in ICON_LAYERS]})
    for layer in ICON_LAYERS:
        folder = stack / f"{layer}.imagestacklayer"
        write_contents(folder, {})
        images = []
        content = folder / "Content.imageset"
        content.mkdir(parents=True)
        for scale, (width, height) in sizes.items():
            filename = f"{layer}-{width}.png"
            png(sources[layer], width, height, layer == "back").save(content / filename, optimize=True)
            images.append({"idiom": "tv", "filename": filename, "scale": scale})
        write_contents(content, {"images": images})


def top_shelf_set(name, width, source):
    folder = BRAND / f"{name}.imageset"
    folder.mkdir(parents=True)
    images = []
    for scale, factor in (("1x", 1), ("2x", 2)):
        filename = f"top-shelf-{width * factor}.png"
        png(source, width * factor, 720 * factor, True).save(folder / filename, optimize=True)
        images.append({"idiom": "tv", "filename": filename, "scale": scale})
    write_contents(folder, {"images": images})


def lockup_svg(tone, fonts):
    """The arches beside the FINESSE wordmark, in colours for a light or dark background."""
    if tone == "light":
        screen, arches, word = ("#2A0E1E", "#6E2440"), ("#E3B6A6", "#BC6F6F", "#7E3049"), "#2A0E1E"
    else:
        screen, arches, word = ("#FFF4EA", "#F2B79E"), ARCH_COLORS, "#F7E3D6"
    path, width = wordmark_path(fonts / "marcellus.woff", "FINESSE", 160)
    total = 200 + 40 + width
    mark = "".join(
        f'<path fill="{color}" d="{arch(256, half, top, 448)}"/>' for color, (half, top) in zip(arches, ARCH_SHAPES)
    ) + f'<path fill="url(#sc)" d="{arch(256, 62, 196, 448)}"/>'
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {total:.1f} 200">'
        f'<defs>{linear("sc", 0, 196, 0, 448, (0, screen[0]), (1, screen[1]))}</defs>'
        f'<g transform="scale({200 / 512})">{mark}</g>'
        f'<g transform="translate(240 50)"><path fill="{word}" d="{path}"/></g></svg>'
    )


def lockup(fonts):
    """Light and dark versions, because the app follows the system's appearance."""
    folder = CATALOG / "FinesseLockup.imageset"
    folder.mkdir(parents=True)
    images = []
    for tone, appearance in (("light", None), ("dark", "dark")):
        source = lockup_svg(tone, fonts)
        (SOURCE / f"lockup-on-{tone}.svg").write_text(source)
        probe = Image.open(io.BytesIO(bytes(resvg_py.svg_to_bytes(svg_string=source, width=600))))
        for scale, width in (("1x", 600), ("2x", 1200)):
            filename = f"lockup-{tone}-{width}.png"
            height = round(probe.height * width / 600)
            png(source, width, height, False).save(folder / filename, optimize=True)
            entry = {"idiom": "tv", "filename": filename, "scale": scale}
            if appearance:
                entry["appearances"] = [{"appearance": "luminosity", "value": appearance}]
            images.append(entry)
    write_contents(folder, {"images": images})


def main():
    fonts = pathlib.Path(sys.argv[1])
    SOURCE.mkdir(exist_ok=True)
    if CATALOG.exists():
        shutil.rmtree(CATALOG)
    write_contents(CATALOG, {})

    layers = icon_layers()
    for name, source in layers.items():
        (SOURCE / f"icon-{name}.svg").write_text(source)
    write_contents(BRAND, {"assets": [
        {"idiom": "tv", "size": "400x240", "role": "primary-app-icon", "filename": "App Icon.imagestack"},
        {"idiom": "tv", "size": "1280x768", "role": "primary-app-icon", "filename": "App Icon - App Store.imagestack"},
        {"idiom": "tv", "size": "1920x720", "role": "top-shelf-image", "filename": "Top Shelf Image.imageset"},
        {"idiom": "tv", "size": "2320x720", "role": "top-shelf-image-wide", "filename": "Top Shelf Image Wide.imageset"},
    ]})
    image_stack("App Icon", {"1x": (400, 240), "2x": (800, 480)}, layers)
    image_stack("App Icon - App Store", {"1x": (1280, 768)}, layers)
    for name, width in (("Top Shelf Image", 1920), ("Top Shelf Image Wide", 2320)):
        source = top_shelf(width, fonts)
        (SOURCE / f"top-shelf-{width}.svg").write_text(source)
        top_shelf_set(name, width, source)
    lockup(fonts)


if __name__ == "__main__":
    main()
