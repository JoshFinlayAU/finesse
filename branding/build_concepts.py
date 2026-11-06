#!/usr/bin/env python3
"""Writes every concept's SVGs into branding/concepts/.

Each concept has a symbol, a wordmark, a lockup and the three icon layers on an 800x480 canvas.
Every mark is drawn here by hand. The wordmarks are outlines of open-licensed typefaces, so the
SVGs need no fonts. Pass the folder holding those fonts as .woff files:

    build_concepts.py <fonts folder>
"""
import pathlib
import sys

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

OUT = pathlib.Path(__file__).parent / "concepts"
ICON_W, ICON_H = 800, 480


def rrect(x, y, w, h, r, **attrs):
    extra = " ".join(f'{k.replace("_", "-")}="{v}"' for k, v in attrs.items())
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" {extra}/>'


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


def wordmark_path(font_file, text, tracking, units=100, swash=None):
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


class Concept:
    """Subclasses draw parts on a 512 box, split into the middle and front icon layers."""

    slug = ""
    name = ""
    font = ""
    text = "Finesse"
    tracking = 0
    icon_scale = 0.66
    icon_offset = (0, 0)

    def defs(self, tone):
        return ""

    def middle(self, tone):
        return ""

    def front(self, tone):
        return ""

    def back(self):
        raise NotImplementedError

    def word_fill(self, tone):
        return "#F4F1EA" if tone == "dark" else "#14130F"

    def symbol(self, tone):
        return (
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">'
            f"<defs>{self.defs(tone)}</defs>{self.middle(tone)}{self.front(tone)}</svg>"
        )

    def wordmark(self, tone, fonts):
        path, width = wordmark_path(fonts / self.font, self.text, self.tracking)
        return (
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="-2 -8 {width + 4:.1f} 136">'
            f'<path fill="{self.word_fill(tone)}" d="{path}"/></svg>'
        )

    def lockup(self, tone, fonts):
        path, width = wordmark_path(fonts / self.font, self.text, self.tracking)
        total = 200 + 40 + width
        return (
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {total:.1f} 200">'
            f"<defs>{self.defs(tone)}</defs>"
            f'<g transform="scale({200 / 512})">{self.middle(tone)}{self.front(tone)}</g>'
            f'<g transform="translate(240 50)"><path fill="{self.word_fill(tone)}" d="{path}"/></g></svg>'
        )

    def placed(self, fragment):
        s = self.icon_scale
        dx, dy = self.icon_offset
        x = ICON_W / 2 - 256 * s + dx
        y = ICON_H / 2 - 256 * s + dy
        return f'<g transform="translate({x:.1f} {y:.1f}) scale({s})">{fragment}</g>'

    def layer(self, which):
        head = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {ICON_W} {ICON_H}" width="{ICON_W}" height="{ICON_H}">'
        if which == "back":
            return head + self.back() + "</svg>"
        draw = self.middle if which == "middle" else self.front
        return head + f'<defs>{self.defs("icon")}</defs>' + self.placed(draw("icon")) + "</svg>"


class Throw(Concept):
    """An F cut from projector light: three throws leaving one bright corner and widening as they go."""

    slug = "01-throw"
    name = "Throw"
    font = "outfit.woff"
    text = "FINESSE"
    tracking = 180
    icon_scale = 0.78
    icon_offset = (-4, 0)

    def defs(self, tone):
        if tone == "light":
            near, far = "#0D2A33", "#D9593D"
        else:
            near, far = "#FFF7EA", "#FF8F6B"
        return (
            radial("t", 110, 66, 470, (0, near), (0.45, far), (1, far, 0.5))
            + linear("m", 150, 0, 396, 0, (0, near), (0.6, far), (1, far, 0.55))
        )

    def middle(self, tone):
        return '<path fill="url(#m)" d="M190 214 L396 190 L396 292 L178 282 Z"/>'

    def front(self, tone):
        return '<path fill="url(#t)" d="M106 66 L446 28 L446 156 L200 138 L168 468 L106 468 Z"/>'

    def back(self):
        return (
            f'<defs>{linear("bg", 0, 0, 800, 480, (0, "#0B2029"), (1, "#050D12"))}'
            f'{radial("gl", 290, 150, 460, (0, "#FF8F6B", 0.24), (1, "#FF8F6B", 0))}</defs>'
            f'<rect width="{ICON_W}" height="{ICON_H}" fill="url(#bg)"/>'
            f'<rect width="{ICON_W}" height="{ICON_H}" fill="url(#gl)"/>'
        )


class Ligature(Concept):
    """The printer's fi ligature, where the f's hook resolves into the dot of the i."""

    slug = "02-ligature"
    name = "Ligature"
    font = "fraunces.woff"
    text = "nesse"
    tracking = 0
    icon_scale = 0.8
    icon_offset = (0, -4)

    def word_fill(self, tone):
        return "#F2EADB" if tone == "dark" else "#14110F"

    def _ink(self, tone):
        return "#F2EADB" if tone == "dark" else "#14110F"

    def _dot(self, tone):
        return "#7E8CFF" if tone == "dark" else "#2B3AD8"

    def middle(self, tone):
        ink = self._ink(tone)
        return (
            f'<path fill="{ink}" d="M172 196 C172 112 226 60 296 60 C322 60 342 66 356 76 '
            'L348 92 C334 84 318 80 300 80 C252 80 230 124 230 196 V384 C230 392 238 398 262 400 V414 H136 V400 '
            'C160 398 172 392 172 384 V236 H124 V218 H172 Z"/>'
            f'<path fill="{ink}" d="M230 218 H382 V384 C382 392 392 398 414 400 V414 H292 V400 '
            'C316 398 326 392 326 384 V260 C326 244 318 238 296 236 H230 Z"/>'
        )

    def front(self, tone):
        return f'<circle cx="354" cy="130" r="36" fill="{self._dot(tone)}"/>'

    def _word(self, tone, fonts):
        """The drawn ligature scaled to the typeface's x-height, then the rest of the name set after it."""
        font = TTFont(fonts / self.font)
        cap = font["OS/2"].sCapHeight
        x_height = font["OS/2"].sxHeight * 100 / cap
        scale = x_height / (414 - 218)
        path, width = wordmark_path(fonts / self.font, self.text, self.tracking)
        lead = (414 - 124) * scale + 6
        fi = (
            f'<g transform="translate({-124 * scale:.2f} {100 - 414 * scale:.2f}) scale({scale:.4f})">'
            f"{self.middle(tone)}{self.front(tone)}</g>"
        )
        return fi + f'<path transform="translate({lead:.2f} 0)" fill="{self.word_fill(tone)}" d="{path}"/>', lead + width

    def wordmark(self, tone, fonts):
        body, width = self._word(tone, fonts)
        return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="-2 -60 {width + 4:.1f} 170">{body}</svg>'

    def lockup(self, tone, fonts):
        return self.wordmark(tone, fonts)

    def layer(self, which):
        head = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {ICON_W} {ICON_H}" width="{ICON_W}" height="{ICON_H}">'
        if which == "back":
            return head + self.back() + "</svg>"
        draw = self.middle if which == "middle" else self.front
        return head + self.placed(draw("light")) + "</svg>"

    def back(self):
        return (
            f'<defs>{linear("bg", 0, 0, 0, 480, (0, "#F5EEDF"), (1, "#E5DAC4"))}</defs>'
            f'<rect width="{ICON_W}" height="{ICON_H}" fill="url(#bg)"/>'
        )


class Flourish(Concept):
    """A fencer's flourish: one tapered blade stroke and a parry across it make a lowercase f."""

    slug = "03-flourish"
    name = "Flourish"
    font = "bodoni-italic.woff"
    text = "Finesse"
    tracking = 6
    icon_scale = 0.78
    icon_offset = (0, 0)

    def word_fill(self, tone):
        return "#F7E9E0" if tone == "dark" else "#0A2B2D"

    def defs(self, tone):
        if tone == "light":
            c = ("#8A3B2C", "#C4674E", "#0A3A3D")
        else:
            c = ("#FFD9C4", "#E58F71", "#FFF1E7")
        return (
            linear("bl", 120, 480, 440, 40, (0, c[0]), (0.55, c[1]), (1, c[0]))
            + linear("pa", 110, 250, 410, 190, (0, c[2], 0.55), (0.45, c[2]), (1, c[2]))
        )

    def middle(self, tone):
        return (
            '<path fill="url(#bl)" d="M112 486 C196 412 228 312 252 204 C276 98 332 26 438 30 '
            'C364 58 334 124 316 214 C294 322 238 442 112 486 Z"/>'
        )

    def front(self, tone):
        return '<path fill="url(#pa)" d="M112 250 C204 214 310 214 416 178 C346 240 226 262 112 250 Z"/>'

    def back(self):
        return (
            f'<defs>{linear("bg", 0, 0, 800, 480, (0, "#0B3A3C"), (1, "#031718"))}'
            f'{radial("gl", 400, 240, 340, (0, "#E58F71", 0.16), (1, "#E58F71", 0))}</defs>'
            f'<rect width="{ICON_W}" height="{ICON_H}" fill="url(#bg)"/>'
            f'<rect width="{ICON_W}" height="{ICON_H}" fill="url(#gl)"/>'
        )


class Palace(Concept):
    """Nested arches of an old picture palace, receding toward a lit screen."""

    slug = "04-palace"
    name = "Palace"
    font = "marcellus.woff"
    text = "FINESSE"
    tracking = 160
    icon_scale = 0.9
    icon_offset = (0, 34)

    def word_fill(self, tone):
        return "#F7E3D6" if tone == "dark" else "#2A0E1E"

    @staticmethod
    def arch(cx, half, top, bottom):
        return f"M{cx - half} {bottom} V{top + half} A{half} {half} 0 0 1 {cx + half} {top + half} V{bottom} Z"

    def defs(self, tone):
        if tone == "light":
            lit = ("#2A0E1E", "#6E2440")
        else:
            lit = ("#FFF4EA", "#F2B79E")
        return linear("sc", 0, 196, 0, 448, (0, lit[0]), (1, lit[1]))

    def middle(self, tone):
        if tone == "light":
            colors = ("#E3B6A6", "#BC6F6F", "#7E3049")
        else:
            colors = ("#6A2340", "#A4475C", "#D97F78")
        # On the icon the arches run off the bottom edge, so parallax never lifts them off the floor.
        foot = 640 if tone == "icon" else 448
        return (
            f'<path fill="{colors[0]}" d="{self.arch(256, 200, 48, foot)}"/>'
            f'<path fill="{colors[1]}" d="{self.arch(256, 152, 96, foot)}"/>'
            f'<path fill="{colors[2]}" d="{self.arch(256, 106, 144, foot)}"/>'
        )

    def front(self, tone):
        foot = 640 if tone == "icon" else 448
        return f'<path fill="url(#sc)" d="{self.arch(256, 62, 196, foot)}"/>'

    def back(self):
        return (
            f'<defs>{linear("bg", 0, 0, 0, 480, (0, "#2C0F20"), (1, "#14060E"))}</defs>'
            f'<rect width="{ICON_W}" height="{ICON_H}" fill="url(#bg)"/>'
        )


class HouseLights(Concept):
    """An F of aisle lights in the moment the house dims, bright at the stem and fading outward."""

    slug = "05-house-lights"
    name = "House Lights"
    font = "jost.woff"
    text = "finesse"
    tracking = 30
    icon_scale = 0.84
    icon_offset = (-6, 0)

    GRID = [
        (0, 0, 1.0), (1, 0, 0.78), (2, 0, 0.55), (3, 0, 0.32),
        (0, 1, 1.0),
        (0, 2, 1.0), (1, 2, 0.68), (2, 2, 0.4),
        (0, 3, 0.86),
        (0, 4, 0.66),
    ]

    def word_fill(self, tone):
        return "#F3F7D2" if tone == "dark" else "#1B1E0B"

    def _dots(self, tone, keep):
        color = "#E7F35E" if tone != "light" else "#39420A"
        out = ""
        for col, row, level in self.GRID:
            if keep(level):
                cx, cy = 136 + col * 84, 88 + row * 84
                if tone != "light":
                    out += f'<circle cx="{cx}" cy="{cy}" r="41" fill="{color}" fill-opacity="{level * 0.16:.2f}"/>'
                out += f'<circle cx="{cx}" cy="{cy}" r="32" fill="{color}" fill-opacity="{level}"/>'
        return out

    def middle(self, tone):
        return self._dots(tone, lambda level: level < 0.8)

    def front(self, tone):
        return self._dots(tone, lambda level: level >= 0.8)

    def back(self):
        return (
            f'<defs>{linear("bg", 0, 0, 800, 480, (0, "#17180F"), (1, "#0A0B07"))}'
            f'{radial("gl", 300, 220, 400, (0, "#E7F35E", 0.09), (1, "#E7F35E", 0))}</defs>'
            f'<rect width="{ICON_W}" height="{ICON_H}" fill="url(#bg)"/>'
            f'<rect width="{ICON_W}" height="{ICON_H}" fill="url(#gl)"/>'
        )


CONCEPTS = [Throw(), Ligature(), Flourish(), Palace(), HouseLights()]


def main():
    fonts = pathlib.Path(sys.argv[1])
    for concept in CONCEPTS:
        folder = OUT / concept.slug
        folder.mkdir(parents=True, exist_ok=True)
        for tone in ("dark", "light"):
            (folder / f"symbol-on-{tone}.svg").write_text(concept.symbol(tone))
            (folder / f"wordmark-on-{tone}.svg").write_text(concept.wordmark(tone, fonts))
            (folder / f"lockup-on-{tone}.svg").write_text(concept.lockup(tone, fonts))
        for which in ("back", "middle", "front"):
            (folder / f"icon-{which}.svg").write_text(concept.layer(which))


if __name__ == "__main__":
    main()
