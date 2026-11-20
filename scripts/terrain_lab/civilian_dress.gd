extends RefCounted
## CIV-A4 平民裝 (Nekki 2026-11-20 14:52Z, A; output/civilian_atlas_plan_20261119/PLAN.md CIV-A4): civilian clothes are
## part of a civilian's look, not items. A dressed civilian wears one of the four civilian atlas looks
## (terrain_army_civilian_atlas.gd catalog(): 布衣 outfit_medieval_chinese_01 over outfit_underlayer_01, 草鞋
## boots_civilian_straw_01, and the 斗笠 helmet_civilian_straw_01 for a household whose job is outdoors: farming or
## gathering). The straw sandals mark the clothes as his own: SiteRuntime.equipment_appearance keeps these parts for an
## unarmed person whose saved look has them; any equipped item drops them (an issued kit shows the gear look, as
## before), and the daily dressing puts them back once he is an unarmed civilian again.
## Never an item, never in the ledger; only the four catalog looks, so every dressed resident has an admitted page.

const Atlas = preload("res://scripts/terrain_lab/terrain_army_civilian_atlas.gd") # read only; it is fingerprinted, never edit it here

const BOOTS := "boots_civilian_straw_01"
const HAT := "helmet_civilian_straw_01"
## The civilian's own parts by appearance slot (helmet only when hatted).
const PARTS := {"armor": "outfit_medieval_chinese_01", "outfit": "outfit_underlayer_01", "boots": BOOTS, "helmet": HAT}
const OUTDOOR_LINES: Array[String] = ["farming", "gathering"]

## The catalog look for `body` (0 male, 1 female), with or without the straw hat; {} for an unknown body.
static func look(body: int, hatted: bool) -> Dictionary:
	var wanted := "CIV-%s0%d" % ["M" if body == 0 else "F", 2 if hatted else 1]
	for row: Dictionary in Atlas.catalog():
		if str(row.id) == wanted: return row.appearance.duplicate(true)
	return {}

## Whether a saved look carries the civilian's own clothes (the straw sandals are the mark).
static func is_dressed(appearance: Variant) -> bool:
	return appearance is Dictionary and appearance.get("parts") is Dictionary and str(appearance.parts.get("boots", "")) == BOOTS

static func is_hatted(appearance: Variant) -> bool:
	return is_dressed(appearance) and str(appearance.parts.get("helmet", "")) == HAT

## Whether a household job that trains `line` (PersonSkills.line_for_task of the job) is outdoors: the straw hat.
## No dependency on the work modules here: SiteRuntime preloads this file.
static func outdoor_line(line: String) -> bool:
	return OUTDOOR_LINES.has(line)

## For SiteRuntime.equipment_appearance: the parts and dyes an unarmed dressed person keeps from his saved look
## (`parts` and `dyes` are that look's), as {parts: {slot: part}, dyes: {slot: dye}}; empty when he is not dressed.
static func kept(parts: Dictionary, dyes: Dictionary) -> Dictionary:
	if str(parts.get("boots", "")) != BOOTS: return {}
	var result := {"parts": {}, "dyes": {}}
	for slot: String in PARTS:
		if str(parts.get(slot, "")) != str(PARTS[slot]): continue
		result.parts[slot] = str(PARTS[slot])
		if dyes.has(slot): result.dyes[slot] = dyes[slot]
	return result
