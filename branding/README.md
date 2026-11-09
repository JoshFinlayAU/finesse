# Branding

Finesse's mark is Palace: three nested arches, like the proscenium of an old picture palace, receding toward a lit screen. The mark has no letter in it, so anywhere it has to say Finesse on its own, it sits beside the FINESSE wordmark.

Everything is drawn in code by `build_tvos_assets.py`. It writes the app icon, the App Store icon, the Top Shelf images and the lockup into `Finesse/Resources/Assets.xcassets`, and an SVG of each into `palace/` for reference. Change the drawing in the script and rerun it rather than editing the PNGs.

## Regenerating the assets

You need Python 3 with `resvg_py`, `Pillow` and `fontTools`, and a folder holding Marcellus as `marcellus.woff`. Fontsource publishes it as the `@fontsource/marcellus` package, or Google Fonts has it.

```sh
pip install resvg_py pillow fonttools
python3 branding/build_tvos_assets.py <folder with marcellus.woff>
```

The script replaces the whole asset catalog, so check `git status` afterwards. With the same font file the output is byte for byte identical to what's committed.

## What it produces

The app icon is a five-layer image stack, so each arch moves at its own depth when the icon is focused. From front to back the layers are the screen, the inner, middle and outer arches, and the background. The icon comes at 400x240 and 800x480, and the App Store icon at 1280x768. The arches run off the bottom of the icon, so the parallax never lifts them off the floor.

The Top Shelf images are 1920x720 and the wide ones 2320x720, each with a 2x version. They show the arches and the wordmark inside the middle 1920 points, which every screen shows. The lockup comes in light and dark versions, because the app follows the system appearance.

## Colours

On dark backgrounds, which covers the icon and Top Shelf:

| Use | Colour |
|---|---|
| Background, top to bottom | #2C0F20 to #14060E |
| Outer, middle and inner arch | #6A2340, #A4475C, #D97F78 |
| Screen, top to bottom | #FFF4EA to #F2B79E |
| Wordmark | #F7E3D6 |

On light backgrounds the arches are #E3B6A6, #BC6F6F and #7E3049, the screen runs from #2A0E1E to #6E2440, and the wordmark is #2A0E1E.

## Font

The wordmark is Marcellus by Astigmatic, set in capitals with wide tracking and converted to outlines, so no font file ships with the app. Marcellus is licensed under the SIL Open Font License 1.1, which allows this.

## For GitHub

The README header uses the two lockup SVGs in `palace/`, picking the light or dark one to match the reader's theme. `social-preview.png` is the 1280x640 image GitHub shows when the repository is shared. It's the dark lockup on the background gradient, made from `palace/lockup-on-dark.svg`, and it's uploaded by hand in the repository's settings because GitHub has no API for it. The README screenshots in `docs/images/` are 1600x900 JPEGs taken against Jellyfin's public demo server.
