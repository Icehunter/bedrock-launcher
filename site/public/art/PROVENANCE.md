# Artwork sources

## Made with Codex CLI image generation

`step-download.png`, `step-game.png`, `step-play.png`, `install-play.png` and `install-move.png` were made with the image generation tool in Codex CLI 0.162.1 on 2026-10-10, then scaled down for the site. Codex was given the app icon and two of the app's page icons as style references. The prompts it sent to the image tool are below, as recorded.

## Made from the app's own artwork

`og.jpg` is the launcher's `scene-hd.jpg` and `app-1024.png` from `mac/Sources/BedrockLauncher/Resources/`, with the title drawn on top by a script. No image generation was used for it.

## Prompts

```text
step-download.png
=================
Use case: stylized-concept.
Asset type: original pixel-art artwork for a voxel-game launcher.
Style reference: match the supplied blocky grass-and-earth app icon, tiny wooden-chest UI icon, and tiny parchment UI icon. They are style references only. Use deliberately chunky, low-resolution pixel clusters, clean hard stair-step edges, a limited palette, and flat color bands. Render like native low-resolution pixel art enlarged only with nearest-neighbor sampling. Every visible edge must be crisp and aligned to the pixel grid. No anti-aliasing, smooth gradients, blur, bloom, soft shadows, photorealism, or smooth vector curves. Any glow must use discrete green pixel bands or sparse pixel dithering. Light comes from the top-left; upper-left edges have small white or pale highlights.
Palette: dark slate #1E2229, deep slate #14171C, lighter slate #2D333C, grass green #3C8527 and #63A944, earthy browns, silver-gray where the subject requires metal, and white highlights. Keep the palette compact.
Constraints: no text, letters, numbers, logos, brand marks, trademarks, watermarks, or game characters anywhere. Nothing resembling the Minecraft logo, Mojang, Microsoft, Apple, or Google marks. No creepers. Generic original objects only.
Primary request: a single square icon of a chunky white-and-green pixel arrow pointing straight down into a dark slate tray. Use a white main arrow face with grass-green inset or side pixels; the arrow must read immediately as download. The dark tray is a simple wide U shape with thick blocky edges, pale upper-left highlights, and a deep slate interior.
Composition: centered, front-facing, balanced, filling about 85% of the square canvas with a small even transparent margin. The arrow and tray form one cohesive icon. Chunk size comparable to a 32x32 UI icon, enlarged crisply.
Output: one square PNG, ideally 1024x1024 pixels, with a genuinely fully transparent alpha background. The object is opaque; everything outside its silhouette is alpha zero. No backdrop, checkerboard drawing, floor, cast shadow, surrounding panel, or extra objects.

step-game.png
=============
Use case: stylized-concept.
Asset type: original pixel-art artwork for a voxel-game launcher.
Style reference: match the supplied blocky grass-and-earth app icon, tiny wooden-chest UI icon, and tiny parchment UI icon. They are style references only. Use deliberately chunky, low-resolution pixel clusters, clean hard stair-step edges, a limited palette, and flat color bands. Render like native low-resolution pixel art enlarged only with nearest-neighbor sampling. Every visible edge must be crisp and aligned to the pixel grid. No anti-aliasing, smooth gradients, blur, bloom, soft shadows, photorealism, or smooth vector curves. Any glow must use discrete green pixel bands or sparse pixel dithering. Light comes from the top-left; upper-left edges have small white or pale highlights.
Palette: dark slate #1E2229, deep slate #14171C, lighter slate #2D333C, grass green #3C8527 and #63A944, earthy browns, silver-gray where the subject requires metal, and white highlights. Keep the palette compact.
Constraints: no text, letters, numbers, logos, brand marks, trademarks, watermarks, or game characters anywhere. Nothing resembling the Minecraft logo, Mojang, Microsoft, Apple, or Google marks. No creepers. Generic original objects only.
Primary request: a single square icon of a small wooden treasure chest, slightly open, with green light visible inside. Match the simple earthy-brown chest reference: chunky wooden planks, a few darker brown border pixels, a small pale metal latch, and pale top-left edge highlights. The lid is lifted only slightly; a narrow grass-green luminous opening clearly separates the lid from the body. Depict the green glow entirely as hard-edged green pixel clusters and stepped color bands, never diffuse light.
Composition: centered, near-front view with just enough top and right side visible to suggest a blocky chest; filling about 85% of the square canvas with a small transparent margin. Simple silhouette and very sparse detail, readable at 32x32.
Output: one square PNG, ideally 1024x1024 pixels, with a genuinely fully transparent alpha background. The chest and any discrete glow pixels are opaque; everything outside the icon is alpha zero. No backdrop, checkerboard drawing, floor, cast shadow, coins, characters, or extra objects.

step-play.png
=============
Use case: stylized-concept.
Asset type: original pixel-art artwork for a voxel-game launcher.
Style reference: match the supplied blocky grass-and-earth app icon, tiny wooden-chest UI icon, and tiny parchment UI icon. They are style references only. Use deliberately chunky, low-resolution pixel clusters, clean hard stair-step edges, a limited palette, and flat color bands. Render like native low-resolution pixel art enlarged only with nearest-neighbor sampling. Every visible edge must be crisp and aligned to the pixel grid. No anti-aliasing, smooth gradients, blur, bloom, soft shadows, photorealism, or smooth vector curves. Any glow must use discrete green pixel bands or sparse pixel dithering. Light comes from the top-left; upper-left edges have small white or pale highlights.
Palette: dark slate #1E2229, deep slate #14171C, lighter slate #2D333C, grass green #3C8527 and #63A944, earthy browns, silver-gray where the subject requires metal, and white highlights. Keep the palette compact.
Constraints: no text, letters, numbers, logos, brand marks, trademarks, watermarks, or game characters anywhere. Nothing resembling the Minecraft logo, Mojang, Microsoft, Apple, or Google marks. No creepers. Generic original objects only.
Primary request: a single square icon of a bright grass-green right-pointing play triangle set inside a square dark stone frame. The stone frame is thick, dark slate, made of simple blocky pixel segments with a lighter top and left bevel and a deep slate bottom and right bevel. Its recessed inner square is deep slate. The large green play triangle has crisp stair-step diagonal edges, a small lighter-green upper-left highlight, and a darker-green lower edge.
Composition: centered, strictly front-facing, square outer frame, filling about 85% of the canvas with an even transparent margin. Match the visual simplicity and chunky pixels of a 32x32 UI icon. No circular shape.
Output: one square PNG, ideally 1024x1024 pixels, with a genuinely fully transparent alpha background outside the square stone frame. Frame, inner recess, and triangle are opaque. No backdrop, checkerboard drawing, floor, cast shadow, or extra objects.

install-play.png
================
Use case: stylized-concept.
Asset type: original pixel-art artwork for a voxel-game launcher.
Style reference: match the supplied blocky grass-and-earth app icon, tiny wooden-chest UI icon, and tiny parchment UI icon. They are style references only. Use deliberately chunky, low-resolution pixel clusters, clean hard stair-step edges, a limited palette, and flat color bands. Render like native low-resolution pixel art enlarged only with nearest-neighbor sampling. Every visible edge must be crisp and aligned to the pixel grid. No anti-aliasing, smooth gradients, blur, bloom, soft shadows, photorealism, or smooth vector curves. Any glow must use discrete green pixel bands or sparse pixel dithering. Light comes from the top-left; upper-left edges have small white or pale highlights.
Palette: dark slate #1E2229, deep slate #14171C, lighter slate #2D333C, grass green #3C8527 and #63A944, earthy browns, silver-gray where the subject requires metal, and white highlights. Keep the palette compact.
Constraints: no text, letters, numbers, logos, brand marks, trademarks, watermarks, or game characters anywhere. Nothing resembling the Minecraft logo, Mojang, Microsoft, Apple, or Google marks. No creepers. Generic original objects only.
Primary request: a wide 16:10 pixel-art illustration of a blocky white-and-silver cloud above a small generic silver laptop, with a green download arrow pointing straight down from the cloud onto the laptop. The cloud uses a stepped rectangular pixel silhouette, white top-left highlights, and a few flat light-gray shadow pixels. The thick green down arrow occupies the central gap and clearly points into the laptop screen. The open silver laptop has a dark slate blank screen, a pale silver bezel, and a simple pixel keyboard with no printed keys, symbols, or letters.
Composition: one centered vertical arrangement, cloud in the upper half and laptop in the lower half, all fully visible with comfortable margins. Front view with the laptop keyboard base visible. Use a coarse uniform pixel grid equivalent to a 160x100 pixel illustration enlarged crisply. The artwork should be simple and compact, with ample dark background.
Output: one wide PNG with EXACT 16:10 aspect ratio, ideally 1536x960 pixels. Fully opaque uniform flat background exactly #1E2229 extending to all four edges. No transparency, vignette, background gradient, floor, decorative landscape, extra objects, or branding.

install-move.png
================
Use case: stylized-concept.
Asset type: original pixel-art artwork for a voxel-game launcher.
Style reference: match the supplied blocky grass-and-earth app icon, tiny wooden-chest UI icon, and tiny parchment UI icon. They are style references only. Use deliberately chunky, low-resolution pixel clusters, clean hard stair-step edges, a limited palette, and flat color bands. Render like native low-resolution pixel art enlarged only with nearest-neighbor sampling. Every visible edge must be crisp and aligned to the pixel grid. No anti-aliasing, smooth gradients, blur, bloom, soft shadows, photorealism, or smooth vector curves. Any glow must use discrete green pixel bands or sparse pixel dithering. Light comes from the top-left; upper-left edges have small white or pale highlights.
Palette: dark slate #1E2229, deep slate #14171C, lighter slate #2D333C, grass green #3C8527 and #63A944, earthy browns, silver-gray where the subject requires metal, and white highlights. Keep the palette compact.
Constraints: no text, letters, numbers, logos, brand marks, trademarks, watermarks, or game characters anywhere. Nothing resembling the Minecraft logo, Mojang, Microsoft, Apple, or Google marks. No creepers. Generic original objects only.
Primary request: a wide 16:10 pixel-art illustration of two small generic silver laptops side by side, with one glowing green cube being passed from the left laptop to the right laptop along a dotted arc. Both laptops are open, similar in size, aligned along the lower half, with blank dark slate screens, pale silver bezels, and simple pixel keyboard bases with no printed keys, symbols, or letters. Above them a dotted green arc rises from the left laptop, passes through one green cube near the top middle, and descends to a small rightward/downward arrowhead pointing toward the right laptop. Arc dots are separated crisp square pixels. The cube has three blocky visible faces, a pale green upper-left highlight, grass-green front, darker-green right side, and a small stepped pixel halo made only of discrete solid green pixels. The transfer direction must read clearly left to right.
Composition: wide balanced arrangement, two laptops fully visible with comfortable margins and clear empty space between them. Use a coarse uniform pixel grid equivalent to a 160x100 pixel illustration enlarged crisply. Exactly two laptops and one cube. Keep the objects simple and compact.
Output: one wide PNG with EXACT 16:10 aspect ratio, ideally 1536x960 pixels. Fully opaque uniform flat background exactly #1E2229 extending to all four edges. No transparency, vignette, background gradient, soft glow, floor, decorative landscape, extra objects, or branding.

```
