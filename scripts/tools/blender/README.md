# Worldgoing Male Q35 Blender Handoff

This folder is the DCC handoff boundary for `BaseBodySeries_Male_Q35_v1`.

## Run

1. Use the prepared project-local Blender 4.2.22 LTS runtime through
   `run_blender.ps1`.
2. Open `build_base_body_series_male_q35.py` in Blender's Scripting workspace.
3. Run the script, or use Blender background mode:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/tools/blender/run_blender.ps1 --background --python scripts/tools/blender/build_base_body_series_male_q35.py
```

The script only replaces the dedicated `Worldgoing_Q35_Male_v1` collection and
writes:

```text
assets/characters/human/q35/base_body_series_male_q35.blend
assets/characters/human/q35/base_body_series_male_q35.glb
```

The GLB export contains the base body, base shorts, `HumanRig_v1_Q35`, and the
named socket markers. Hair and face are separate presentation collections in
the `.blend` and are not part of the base GLB export.

## Acceptance boundary

The script is the repeatable DCC starting point, not visual acceptance by
itself. After Blender generates the GLB:

1. Open the `.blend` and inspect front, side, back, and three-quarter views.
2. Run `base_body_series_male_q35_import_contract_test.gd` in Godot.
3. Capture the Godot visual preview and compare it against the supplied Q35
   specification sheet.
4. Review skin weights and replaceable layer alignment before treating the
   asset as production-ready.

The project-local runtime is intentionally ignored by Git. The launcher also
redirects Blender's user resources to `.godot-temp/blender-user-resources`, so
background builds do not depend on a machine-wide Blender installation or
restricted user-cache paths.
