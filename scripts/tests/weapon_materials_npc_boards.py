"""Contact sheets from unchanged Godot captures; no edits to game assets."""
import json
import re
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "output/weapon_materials_npc_20260917"
OPTIONS = json.loads(re.search(r"const OPTIONS := (\[.*?\n\])", (ROOT / "scripts/ui/weapon_materials.gd").read_text(encoding="utf-8"), re.S)[1])
FONT = ImageFont.truetype("C:/Windows/Fonts/msjh.ttc", 17)
SAMPLES = (("待機・正", 0, 0), ("攻擊・正", 2, 0), ("攻擊・側", 2, 1), ("防禦・正", 3, 0), ("防禦・背", 3, 2), ("昏迷・右", 5, 3))


def board(rows, name):
    canvas = Image.new("RGB", (1568, 55 + 202 * len(rows)), "#151d28")
    draw = ImageDraw.Draw(canvas)
    for column, (label, _, _) in enumerate(SAMPLES):
        draw.text((135 + column * 240, 15), label, font=FONT, fill="white")
    for index, row in enumerate(rows):
        source = Image.open(OUT / "visual" / (row["id"] + "_final.png")).convert("RGB")
        y = 55 + index * 202
        draw.text((4, y + 12), row["label"].split("｜")[-1].split("（")[0], font=FONT, fill="white")
        draw.text((4, y + 40), {"wood": "木製", "stone": "石製", "iron": "鐵製", "steel": "鋼製"}[row["material"]], font=FONT, fill="#ccd8e8")
        for column, (_, pose, direction) in enumerate(SAMPLES):
            # Copy the complete per-cell rectangle at original screenshot size.
            top = 73 if pose == 0 else 60 + pose * 144
            crop = source.crop((127 + direction * 250, top, 363 + direction * 250, 204 + pose * 144 if pose < 5 else 960))
            canvas.paste(crop, (127 + column * 240, y + 20 + (13 if pose == 0 else 0)))
    target = OUT / "boards" / name
    target.parent.mkdir(exist_ok=True)
    canvas.save(target)
    print(target)


if __name__ == "__main__":
    for material in ("wood", "stone", "iron", "steel"):
        board([row for row in OPTIONS if row.get("material") == material], material + ".png")
    board([next(row for row in OPTIONS if row["id"] == ("axe_01" if kind == "iron" else "axe_01_" + kind)) for kind in ("wood", "stone", "iron", "steel")], "battleaxe_materials.png")
