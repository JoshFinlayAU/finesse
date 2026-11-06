# Branding

The owner chose concept 04 Palace on 2026-11-07. The other concepts stay here for reference and aren't used in the app.

`build_tvos_assets.py` renders Palace into `Finesse/Resources/Assets.xcassets` and writes each layer's SVG to `palace/`. Change the drawing there and rerun it, rather than editing the PNGs. Its layers, front to back, are the screen, the inner, middle and outer arches, and the back. The app's lockup is an image with light and dark versions.

The wordmark is an outline of Marcellus, under the SIL Open Font License. The font itself isn't shipped.

- `build_concepts.py` draws every concept and writes the SVGs to `concepts/`. The folder of `.woff` fonts is its only argument.
- `build_page.py` builds the single review page from those SVGs.

Each concept folder holds the symbol, wordmark and lockup for dark and light backgrounds, and `icon-back.svg`, `icon-middle.svg` and `icon-front.svg` on an 800x480 canvas.

The marks are hand-drawn. The wordmarks are outlines of open-licensed typefaces from Fontsource: Outfit, Fraunces, Bodoni Moda, Marcellus and Jost. No font is bundled. All five are under the SIL Open Font License.

## What the tvOS asset set needs

Tested with `actool` from Xcode 27.2 on 2026-11-07, for `appletvos` with a tvOS 26.0 deployment target.

A tvOS app icon is still a layered image stack in an asset catalog. Apple's guidance says Icon Composer covers iOS, iPadOS, macOS and watchOS, not tvOS. The catalog holds an `App Icon & Top Shelf Image.brandassets` folder, named by the `--app-icon` setting.

| Asset | Sizes in pixels | Notes |
|---|---|---|
| App Icon | 400x240 at 1x, 800x480 at 2x | Image stack of 2 to 5 layers. `actool` rejects 1 or 6 layers |
| App Icon - App Store | 1280x768 at 1x | Same layer count. `actool` rejects other sizes |
| Top Shelf Image | 1920x720 at 1x, 3840x1440 at 2x | Static image |
| Top Shelf Image Wide | 2320x720 at 1x, 4640x1440 at 2x | Static image. The current guidance lists only this size |

`actool` also compiled sets with no Top Shelf images, no wide image, no 2x icon or no App Store icon, without errors. That only shows they compile, and says nothing about whether App Store Connect accepts them, so supply all of the above.

The other requirements come from Apple's App Icons page:

- Layers are rectangular with no rounded corners or masks, because the system applies its own.
- Keep important content inside a safe zone. Apple gives no number, and foreground layers are cropped more than background ones.
- The bottom layer must be opaque and full-bleed. `actool` requires the last layer to exactly fill the stack, and Apple asks for opaque background layers in its general guidance.
- Colour is sRGB or Display P3. PNG is the preferred raster format.
- Text belongs above the other layers so parallax doesn't crop it.

A Top Shelf extension would be a separate feature. These static images are the fallback, and the app doesn't have an extension today.
