extends "res://scripts/tests/site_technology_artisan_g06_point_order_base.gd"
## Actual original THREE birth, original mesh/material contacts and whole points.
## This is a strict NOT_RUN regression, not a claim the present caller clips hits.

func _contact_birth(source: RegionData) -> Dictionary:
	var lab: TerrainLab = _source_lab("g06_contact_" + _g06_category())
	var world: String = _world("g06_contact_" + _g06_category())
	var slot := CandidatePolicySlot.new()
	slot.candidate_categories = Artisans.CATEGORIES.duplicate() # Isolated accepted-policy premise only.
	slot.folder = "user://region_lab/worlds/%s/slots/%s" % [world, SLOT]
	lab.site_controller._initial_world_candidate = slot
	var begun: Dictionary = lab.site_controller.open_fixed_world(manifest_path, world, SLOT, START, true, Artisans.THREE_FACTIONS)
	_require(begun.ok and int(slot._marker.generation) == 1 and not slot.initialization_pending(), "True original THREE first-world transaction commits once", begun)
	_freeze(lab)
	var data: TerrainData = lab.terrain
	_require(int(birth_counts[lab.get_instance_id()]) == 1 and lab.region_bind_receipt(data).get("complete", false), "One disposable original birth transaction binds all original teams")
	_require(data.site.world_pin.size() >= 9 and data.site.world_pin.manifest_sha256 == source.manifest_hash and data.site.world_pin.base_revision == source.manifest.base_revision and data.parameters.has("fixed_base"), "Contact fixture retains every real geographic pin/base guard")
	_require(Artisans.validate_receipt(data.site.technology_artisans, data.site) and data.site.technology_artisans.grants.size() == 12 and data.site.technology_artisans.categories == Artisans.CATEGORIES and lab.combat_armies.size() == 3 and not data.site.has("family"), "Exactly original three teams/15 people/12 bounded grants; no automatic family")
	var seen := {}
	for actual: TerrainArmy in lab.combat_armies:
		_require(actual.combat_units.size() == 5, "Each original THREE roster has five actual people")
		for index: int in actual.combat_units.size():
			var identity: int = actual.combat_identity(index)
			_require(identity > 1 and not seen.has(identity), "Actual person allocator remains unique across all THREE teams")
			seen[identity] = true
			_require(actual.combat_units[index].get("technology", {}) == ({} if index == 0 else {"version": 2, "learned": [Artisans.CATEGORIES[index - 1]], "analysis": []}), "No fixture assigns or manufactures an extra learned master")
	_require(seen.size() == 15, "All 15 original bodies survived actual complete bind")
	var team: TerrainArmy = lab.army
	var enemy: TerrainArmy = lab.opposing_army
	var master: int = team.combat_identity(Artisans.CATEGORIES.find(_g06_category()) + 1)
	var commander: int = team.combat_identity(team.current_commander)
	_require(lab.site_controller._control_family_person(null, commander).ok, "Actual original team.work decider controls original Builder")
	return {"kind": "fixed_birth", "lab": lab, "data": data, "source": source, "world": world, "slot": slot, "team": team, "enemy": enemy,
		"master": master, "helper": team.combat_identity(1), "commander": commander, "category": _g06_category(),
		"birth": data.site.technology_artisans.duplicate(true), "fixed_base": data.parameters.fixed_base.duplicate(true), "pin": data.site.world_pin.duplicate(true),
		"next_person": int(data.site.next_person_id), "next_item_birth": int(data.site.next_item)}

func _contact_position(f: Dictionary, enemy_index: int) -> void:
	var master_cell: Vector2i = f.team.cells[f.team.index_for_identity(int(f.master))]
	var foreign: Dictionary = f.duplicate(false)
	foreign.team = f.enemy
	for distance: int in [2, 1]:
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var cell: Vector2i = master_cell + direction * distance
			if not f.data.is_walkable(cell) or not SiteCombatRules.terrain_line_clear(f.data, cell, master_cell) or f.lab.site_controller.reserves_cell(cell): continue
			var occupied := false
			for actual: TerrainArmy in f.lab.combat_armies:
				for index: int in actual.cells.size():
					if actual != f.enemy or index != enemy_index: occupied = occupied or actual.cells[index] == cell
			for actor: TerrainTestCharacter in f.lab.combat_actors: occupied = occupied or actor.terrain_cell == cell
			if occupied: continue
			_place(foreign, f.enemy.combat_identity(enemy_index), cell) # Explicit legal stationary geometry INPUT; no navigation claim.
			return
	_require(false, "Original ground/reservations provide a real legal attacking station without moving another body")

func _run() -> void:
	_require(_g06_category() in ["F11", "F12"], "Named actual fixed-source physical-contact engineering test")
	_case = {"category": _g06_category(), "formal_release": false, "default_policy": [], "source_rule_unmodified": true}
	var source: RegionData = _g06_source()
	_require(source != null, "Original checked fixed geography")
	var f: Dictionary = _contact_birth(source)
	var held: Dictionary = await _point_prepare(f, false)
	var enemy: TerrainArmy = f.enemy
	var attacker := -1
	for index: int in enemy.combat_units.size():
		if enemy.combat_can_act(index) and enemy.ranged_profile(index).is_empty():
			attacker = index
			break
	_require(attacker >= 0, "An ORIGINAL first-born enemy has real melee equipment; no item/weapon/body replacement")
	_contact_position(f, attacker)
	var packets: Array[Dictionary] = []
	var original_sink: Callable = enemy.contact_sink
	_require(original_sink.is_valid(), "Actual bound original melee Contact sink exists")
	# Observation only. Every exact ORIGINAL geometry/material packet is passed
	# unchanged to the SAME original sink; no manufactured impact/HP/stun/fraction.
	enemy.contact_sink = func(packet: Dictionary) -> void:
		if is_same(packet.get("target"), f.team) and int(packet.get("target_unit", -1)) == f.team.index_for_identity(int(f.master)):
			packets.append({"fraction": float(packet.fraction), "hp_damage": float(packet.result.hp), "stun_damage": float(packet.result.stun), "attacker_id": enemy.combat_identity(int(packet.attacker_unit)), "target_id": int(f.master)})
		original_sink.call(packet)
	var master_index: int = f.team.index_for_identity(int(f.master))
	var body: Dictionary = f.team.combat_units[master_index]
	var before_hits: int = int(body.get("hit_revision", 0))
	var loss := {}
	for tick: int in 12000:
		if float(f.team.combat_hot_get(master_index, &"hp")) <= 0.0 or float(f.team.combat_hot_get(master_index, &"ko")) > 0.0: break
		if not bool(enemy.combat_hot_get(attacker, &"attack")) and enemy.combat_can_act(attacker):
			_require(enemy.start_unit_attack(attacker, f.team.cells[master_index], int(f.master)), "Actual original melee command starts a real attack, with original equipment/cooldown/terrain guards")
		var packet_count: int = packets.size()
		var progress: float = float(held.vehicle.build.progress)
		var fatigue: float = Fatigue.read(body)
		var rate: float = Fatigue.effort_rate(body) + Fatigue.effort_rate(f.team.combat_units[f.team.index_for_identity(int(f.helper))])
		var stepped: Dictionary = f.lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
		_require(stepped.ok and stepped.get("completed", false) and f.lab._region_point_pending.is_empty(), "Actual main caller resolves work, CPU geometry contacts, life and checked clock in one completed original point", stepped)
		if packets.size() > packet_count and (float(f.team.combat_hot_get(master_index, &"hp")) <= 0.0 or float(f.team.combat_hot_get(master_index, &"ko")) > 0.0):
			var contact: Dictionary = packets.back()
			loss = {"packet": contact, "game_seconds": float(stepped.game_seconds), "action_seconds": float(stepped.action_seconds), "progress_delta": float(held.vehicle.build.progress) - progress, "fatigue_begin": fatigue, "pool_rate": rate}
			break
	enemy.contact_sink = original_sink
	_require(not loss.is_empty() and packets.size() > 0 and int(body.get("hit_revision", 0)) > before_hits and (float(f.team.combat_hot_get(master_index, &"hp")) <= 0.0 or float(f.team.combat_hot_get(master_index, &"ko")) > 0.0), "Original repeated mesh/material attacks genuinely remove the actual last master's qualification; no synthetic contact input")
	var fraction: float = float(loss.packet.fraction)
	_require(fraction > 0.0 and fraction < 1.0, "The REAL last-master impact is strictly inside the observed original contact interval; endpoint-only hits do not satisfy midframe acceptance", loss)
	# Intentional strict regression: source review shows the present collector
	# may commit before melee resolution. Do not widen this bound to obtain PASS.
	var prefix_ceiling: float = 2.0 * Fatigue.work_seconds(float(loss.fatigue_begin), float(loss.game_seconds) * fraction, float(loss.pool_rate))
	_require(float(loss.progress_delta) <= prefix_ceiling + 0.00000001, "Helpers never receive engineering progress after the ORIGINAL midframe final-master contact", {"actual": loss.progress_delta, "legal_prefix_ceiling": prefix_ceiling, "contact": loss})
	var retained_progress: float = float(held.vehicle.build.progress)
	var pool: float = Fatigue.read(f.team.combat_units[f.team.index_for_identity(int(f.helper))])
	for point: int in 6:
		var next: Dictionary = f.lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
		_require(next.ok and next.get("completed", false), "Subsequent original contact/work point settles", next)
	_require(float(held.vehicle.build.progress) == retained_progress and Fatigue.read(f.team.combat_units[f.team.index_for_identity(int(f.helper))]) == pool and is_same(held.vehicle.build.paid_cost, held.paid), "Actual last-master loss stops helper work AND effort; retains admitted prior progress and SAME original paid history")
	_idle_all(f)
	for point: int in 10000:
		if float(f.data.site.combat_left) <= 0.0 and f.lab._region_point_pending.is_empty(): break
		var ended: Dictionary = f.lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
		_require(ended.ok and ended.get("completed", false), "Original clock/contact/death owner naturally reaches a settled save boundary", ended)
	_require(float(f.data.site.combat_left) <= 0.0, "No combat timer, life field, flight or point was manually erased for cold acceptance")
	_cold_resume(f, "real_contact_pending")
	var restored: Dictionary = f.data.site.vehicles[held.key]
	_require(absf(float(restored.build.progress) - retained_progress) < 0.00000001 and restored.build.paid_cost == held.terms.cost and f.data.site.technology_artisans == f.birth, "True Store/Slot/Controller cold bind preserves paid engineering and immutable birth history after actual contact/life settlement")
	report[_g06_category()] = {"original_three_birth": true, "original_contact_packets": packets, "true_midframe_last_master_loss": loss, "legal_prefix_ceiling": prefix_ceiling,
		"no_synthetic_damage_clock_or_work": true, "actual_pending_cold": true, "full_G06": "OPEN", "G05_and_paired_land_source_excluded": true}
	_finish()

func _finish(reason: String = "") -> void:
	if finished: return
	finished = true
	if not reason.is_empty(): failures.append(reason)
	for lab: TerrainLab in labs:
		if is_instance_valid(lab): lab.free()
	TerrainArmy.release_contact_source()
	print("TECH_AI_02_G06_CONTACT_POINT_REPORT: " + JSON.stringify({"checks": checks, "failures": failures, "cases": report,
		"source_epochs": {"lab": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_lab.gd"), "army": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd"), "runtime": FileAccess.get_sha256("res://scripts/terrain_lab/site_runtime.gd"), "contact": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army_contact_source.gd")}, "default_policy": [], "full_G06": "OPEN"}, "", true, true))
	print("TECH_AI_02_G06_CONTACT_POINT_", _g06_category(), "_", "PASS" if failures.is_empty() else "FAILED", " scope=actual_THREE_original_mesh_contact_midframe_lastmaster_strict_prefix_pending_cold_only")
	quit(0 if failures.is_empty() else 1)
