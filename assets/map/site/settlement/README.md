# Settlement props v1

Generated with the built-in image_gen tool on 2026-09-11, using `output/imagegen/site_environment_fixed_characters_concept_v1.png` as the approved appearance reference. No human asset was generated or replaced.

That concept image is a local design reference excluded from the release. The runtime uses only the atlas and shader in this directory.

`settlement_props_chroma_v1.png` is a 1536×1024 RGB atlas. It intentionally has a magenta key background, not an alpha channel. `settlement_chroma.gdshader` removes that background while rendering and suppresses edge spill; do not display the raw atlas without this material. Region coordinates live once in `SiteResourceView.PROP_REGIONS`. Existing resource row batches share the material; primitive and font texels are unaffected. Import losslessly without mipmaps to keep the key color stable.

The house scales to the selected footprint; the reviewed sample uses 3×3 cells. Wells and the camp chest retain their small gameplay footprints. All three existing farm types share the seedling artwork and remain distinguished by the existing label and recipe. Farm tiles render on the ground beneath characters; the remaining props use the existing row ordering. Unfinished construction, other workshops and natural-resource art retain their previous presentation. Model files, character controllers, animation and production rules are unchanged.

## Background edit prompt

Edit target: attached environment sprite sheet. Change ONLY the background. Replace every grey-and-white checkerboard background pixel and empty gap with one perfectly flat fully opaque chroma magenta RGB (255, 0, 255), hex #FF00FF, for real-time game chroma keying. Preserve all four objects exactly: the same cottage, stone well including rope and bucket, planted soil plot, and wooden supply chest. Keep the same camera, design, material, colors, scale, positions and silhouettes, with the same 1536 by 1024 canvas and 2 by 2 arrangement. Remove the checkerboard visible through gaps around the well posts and rope, and around the outside silhouettes, replacing those areas with identical pure magenta too. Do not fill actual well water or its interior with magenta. No pink light spill, no pink outlines, no cast shadows onto background, no checkerboard, no transparency visualization, no gradient or texture on the background, no text, no added objects, no people. Preserve crisp object edges. This is a strictly background-replacement edit, not a redesign.
