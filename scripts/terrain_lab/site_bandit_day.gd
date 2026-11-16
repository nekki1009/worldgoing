extends RefCounted
## 土匪 B4d-1 (reports/bandit-faction-spec.md §5.2, §9.1, §11, §12): once a game day, every NPC band chief makes one move.
## This step wires the record-level moves: heat cools by 5 every 10th day, a band at heat >= 70 moves its lair to the
## nearest land Site next to it (heat back to 30), and an NPC chief standing in the active Site rises when the §9.1 gate
## and his ambition allow. Raids (B4d-3) and amnesty offers are not wired yet; protection money is asked from the
## settlement side (SiteBanditProtection). A band the controlled person chiefs never acts here (the player decides), and
## nothing is decided for a chief who is not in the active Site where the decision needs his person ("no made-up
## history", §11).
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const Reputation = preload("res://scripts/terrain_lab/person_reputation.gd")
const DutyAI = preload("res://scripts/terrain_lab/site_duty_ai.gd")
const JoinFaction = preload("res://scripts/terrain_lab/site_join_faction.gd")
const BanditAmnesty = preload("res://scripts/terrain_lab/site_bandit_amnesty.gd")
const BanditRout = preload("res://scripts/terrain_lab/site_bandit_rout.gd") # B4d-2: routed survivors form a band.

const COOL_EVERY_DAYS := 10
## The four neighbours of a lair Site, in the order a move tries them.
const NEIGHBOURS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

## Runs the day once per controller; returns {day, actions: [{band, action, ...}]} or {} when already run today.
static func day(controller: Variant) -> Dictionary:
	if controller == null or controller.region_slot == null: return {}
	var today := int(float(controller.region_slot.control.logical_game_seconds) / Bandit.DAY)
	if int(controller.get_meta(&"bandit_day", -1)) == today: return {}
	controller.set_meta(&"bandit_day", today)
	return run(controller, today)

static func run(controller: Variant, today: int) -> Dictionary:
	var result := {"day": today, "actions": []}
	var slot: Variant = controller.region_slot
	result["rout"] = BanditRout.day(controller, today)
	var registry: Dictionary = slot.control.get("faction_registry", {})
	if registry.get("version") != RegionFactionQuery.VERSION: return result
	var bands: Array[int] = []
	for key: Variant in registry.get("entries", {}):
		var entry: Dictionary = registry.entries[key]
		if entry.get("status") == "active" and RegionFactionQuery.is_bandit(registry, int(entry.faction_id)): bands.append(int(entry.faction_id))
	bands.sort()
	var player_ref: Dictionary = JoinFaction._world_ref(controller, int(controller.lab.controlled_person_id()))
	var now := float(slot.control.logical_game_seconds)
	for band: int in bands:
		registry = slot.control.faction_registry
		var entry: Dictionary = registry.entries[str(band)]
		if not player_ref.is_empty() and RegionPeerage.same_ref(entry.get("leader_ref"), player_ref): continue
		var table: Dictionary = RegionFactionQuery.bandit_of(registry, band)
		if not bool(table.get("raid_ai", true)): continue
		var heat := int(table.get("heat", 0))
		if heat > 0 and today > 0 and today % COOL_EVERY_DAYS == 0:
			var cooled := Bandit.set_heat(registry, band, Bandit.heat_after(heat, "quiet", COOL_EVERY_DAYS), now)
			if cooled.ok and controller._commit_diplomacy(cooled, "").ok:
				registry = slot.control.faction_registry
				heat = int(RegionFactionQuery.bandit_of(registry, band).heat)
		var chief := RegionPeerage.world_person_id(entry.get("leader_ref"))
		var here: bool = chief > 0 and not controller.lab._original_person_target(chief).is_empty()
		var can_rise := false
		if here:
			var mind: Dictionary = DutyAI.personality(chief, null, controller.lab)
			var prestige := Reputation.shown(int(controller.reputation_of(chief).prestige))
			can_rise = Bandit.may_rise(registry, band, prestige, BanditAmnesty._members(controller.lab, band).size(), int(mind.get("ambition", 50))).ok
		var decision := Bandit.daily_decision(registry, band, {"day": today, "heat": heat, "can_rise": can_rise,
			"amnesty_score": -1.0, "protection_due": [], "targets": [], "strength": 0.0})
		var done := {}
		match str(decision.action):
			"move_lair": done = move_lair(controller, band)
			"rise":
				done = controller._commit_diplomacy(Bandit.rise(registry, band, now), "")
				if done.ok: controller.adjust_reputation(chief, float(Reputation.FOUND_KING), 0.0)
			_: continue
		result.actions.append({"band": band, "action": str(decision.action), "ok": bool(done.get("ok", false)), "code": str(done.get("code", ""))})
	return result

## The nearest land neighbour of the lair Site (east, north, west, south) keeps the same cell inside its Site; with no
## land neighbour the band stays. Heat drops to 30 (Bandit.move_lair).
static func move_lair(controller: Variant, band: int) -> Dictionary:
	var slot: Variant = controller.region_slot
	var registry: Dictionary = slot.control.faction_registry
	var lair: Variant = RegionFactionQuery.bandit_of(registry, band).get("lair")
	if not lair is Dictionary: return {"ok": false, "code": "NO_LAIR"}
	var parts := str(lair.site_id).split(":")
	if parts.size() < 3 or not parts[parts.size() - 2].is_valid_int() or not parts[parts.size() - 1].is_valid_int(): return {"ok": false, "code": "NO_LAIR"}
	var at := Vector2i(int(parts[parts.size() - 2]), int(parts[parts.size() - 1]))
	var atlas := str(lair.site_id).substr(0, str(lair.site_id).length() - parts[parts.size() - 2].length() - parts[parts.size() - 1].length() - 2)
	for step: Vector2i in NEIGHBOURS:
		var next := at + step
		var summary: Dictionary = slot.source.get_site_summary(next.x, next.y) if slot.source != null else {}
		if not summary.get("ok", false) or str(summary.get("status", "")) not in ["land", "mixed"]: continue
		var site_id := "%s:%d:%d" % [atlas, next.x, next.y]
		var moved := Bandit.move_lair(registry, band, site_id, Vector2i(int(lair.cell[0]), int(lair.cell[1])), float(slot.control.logical_game_seconds))
		if not moved.ok: return moved
		return controller._commit_diplomacy(moved, "")
	return {"ok": false, "code": "NO_LAND_NEIGHBOUR"}
