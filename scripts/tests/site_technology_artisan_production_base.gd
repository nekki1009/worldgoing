extends "res://scripts/tests/region_initial_world_transaction_test.gd"
## TWO distinct engineering evidence groups, never a fixed-world handoff:
## (1) true fixed-source original first birth/policy/Store/Slot cold re-entry;
## (2) cold original people/items restored as explicit fixture inputs into
##     a lawful GENERATED formal Lab with legacy empty policy, true products.
## The hypothetical category is an explicit isolated admission precondition,
## never a formal release, ordinary-world upgrade or another policy owner.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")
const Stocks = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const Family = preload("res://scripts/terrain_lab/site_family_continuity.gd")
const Catalog = preload("res://scripts/terrain_lab/site_technology_catalog.gd")

class CandidatePolicySlot extends RegionSaveSlot:
	var candidate_categories: Array = []
	# Root-owned original Slot seam. Only this pure hypothetical release query
	# is overridden; all pin/source/IO/first-generation/bind validators are real.
	func _initial_technology_categories() -> Array:
		return candidate_categories.duplicate()

var _case: Dictionary = {}
var _work_effective := 0.0
var _work_actual := 0.0
var _work_intervals := 0

func _g06_category() -> String:
	return ""

func _normalized(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true, true)), "", true, true)

func _require(condition: bool, label: String, detail: Variant = "") -> void:
	# Only a failure prints its detail, bounded and cycle-safe: live plans and
	# held prefixes reference themselves and must never be stringified whole.
	var text := "" if condition else _detail_text(detail)
	var passed := _check(condition, label, text)
	assert(passed, label + " " + text)

func _detail_text(detail: Variant, depth: int = 0) -> String:
	if detail is Dictionary:
		var parts: Array[String] = []
		for key: Variant in detail.keys().slice(0, 16):
			var value: Variant = detail[key]
			var shown := _detail_text(value, depth + 1) if depth < 1 and (value is Dictionary or value is Array) else ("<%s>" % type_string(typeof(value)) if value is Dictionary or value is Array or value is Object else str(value).left(160))
			parts.append("%s: %s" % [str(key), shown])
		return "{" + ", ".join(parts) + ("" if detail.size() <= 16 else ", ...%d keys" % detail.size()) + "}"
	if detail is Array: return "Array[%d]" % detail.size()
	if detail is Object: return "<%s>" % detail.get_class()
	return str(detail).left(600)

func _g06_source() -> RegionData:
	# Reuse the checksummed original RegionData helper verbatim. Foundation's
	# genuine source admission is required; never fill soil or erase fixed_base.
	return _fixed_source()

# Teardown timing only: draw a few frames so D3D12 runs the deferred frees of
# released presenters before the next lab allocates. No-op when headless.
func _settle_render_frees() -> void:
	if DisplayServer.get_name() == "headless": return
	for _frame: int in 3: RenderingServer.force_draw(false)

func _birth(source: RegionData, category: String) -> Dictionary:
	var lab := _source_lab("g06_" + category)
	_require(lab != null, "Actual formal TerrainLab instantiated")
	lab.crowd_startup_requested = _crowd_port() # Crowd port (2026-11-12): opted-in artisan tests open the live shell as crowd.
	var world := _world("g06_" + category)
	var slot := CandidatePolicySlot.new()
	slot.candidate_categories = [category]
	slot.folder = "user://region_lab/worlds/%s/slots/%s" % [world, SLOT]
	lab.site_controller._initial_world_candidate = slot
	var result: Dictionary = lab.site_controller.open_fixed_world(manifest_path, world, SLOT, START, true, Artisans.PRIMARY)
	_settle_render_frees()
	_require(result.ok, "Actual full-pin Controller first-generation transaction", result)
	_freeze(lab)
	_require(lab.site_controller.region_slot == slot and int(slot._marker.generation) == 1 and not slot.initialization_pending(), "Same original Slot committed exactly one generation")
	_require(int(birth_counts[lab.get_instance_id()]) == 1 and lab.region_bind_receipt(lab.terrain).get("complete", false), "Exactly one true birth and complete original live bind")
	var data: TerrainData = lab.terrain
	var pin: Dictionary = data.site.world_pin
	_require(pin.size() >= 9 and data.parameters.has("fixed_base") and pin.manifest_sha256 == source.manifest_hash and pin.base_revision == source.manifest.base_revision, "Full original checked geographic pin survives birth")
	var policy := Policy.candidate(pin)
	_require(policy.ok and policy.policy.categories == [category] and slot.pin.technology_policy == policy.policy, "One explicit hypothetical category frozen by original Slot")
	_require(Artisans.validate_receipt(data.site.get("technology_artisans"), data.site), "Original bounded birth receipt strictly validates")
	_require(not data.site.has("family") and data.site.armies.size() == 1, "Independent true artisan birth has no invented family")
	var team: TerrainArmy = lab.army
	_require(team.has_army() and team.combat_units.size() == 5, "Finite original five-person army binds")
	var index := Artisans.CATEGORIES.find(category) + 1
	var master := team.combat_identity(index)
	for at: int in team.combat_units.size():
		var learned: Dictionary = team.combat_units[at].get("technology", {})
		_require(Technology.learned(learned, category) == (at == index), "Only configured original NPC initially learned " + category)
		if at != index: _require(learned.is_empty(), "Untargeted original row has no substitute skills")
	_require(lab.character.technology.is_empty(), "Actual fresh Actor gains no NPC skill")
	var commander := team.combat_identity(team.current_commander)
	_require(lab.site_controller._control_family_person(null, commander).ok and lab.controlled_person_id() == commander, "Original control owner selects actual current team.work decider")
	var helper := team.combat_identity(1 if index != 1 else 2)
	return {"kind": "fixed_birth", "lab": lab, "data": data, "source": source, "world": world, "slot": slot, "team": _team_view(lab), "master": master, "helper": helper, "commander": commander, "category": category,
		"birth": data.site.technology_artisans.duplicate(true), "fixed_base": data.parameters.fixed_base.duplicate(true), "pin": pin.duplicate(true), "next_person": int(data.site.next_person_id), "next_item_birth": int(data.site.next_item)}

func _fixed_policy_guard(f: Dictionary) -> void:
	# Readonly POLICY gates only. The actual fixed geography has foundation
	# and groundwater zero; no facility/product or construction PASS is claimed.
	var before: PackedByteArray = var_to_bytes([f.data.site, _combat_state(f), f.data.fingerprint()])
	if str(f.category) in ["F04", "F06"]:
		var definitions: Array = [["smelter", "steel"], ["smithy", "steel_tools"]] if f.category == "F04" else [["weaver", "wool_cloth"]]
		for entry: Array in definitions:
			# Pure definition projection, NOT an actual complete host/evidence.
			var projection := {"kind": str(entry[0]), "recipe_id": str(entry[1])}
			var denied: Dictionary = Runtime.technology_recipe_guard(f.data, "", projection, int(f.helper))
			var allowed: Dictionary = Runtime.technology_recipe_guard(f.data, "", projection, int(f.master))
			_require(not denied.ok and denied.code == "NO_TECHNOLOGY" and allowed.ok, "Full fixed policy checks true learned/unlearned original bodies only: " + str(entry[1]), denied)
	else:
		var actions: SitePersonActions = f.lab.site_controller.person_actions
		var kind: String = "siege_tower" if f.category == "F11" else "counterweight_trebuchet"
		var rejected_admission: Dictionary = actions.technology_vehicle_work_admission(int(f.helper), int(f.team.team_id))
		var eligible_admission: Dictionary = actions.technology_vehicle_work_admission(int(f.master), int(f.team.team_id))
		_require(rejected_admission.ok and eligible_admission.ok, "Same original team authority before separate skill check")
		var denied: Dictionary = Runtime._technology_siege_begin_policy(f.data, kind, {}, {"admission": rejected_admission})
		var allowed: Dictionary = Runtime._technology_siege_begin_policy(f.data, kind, {}, {"admission": eligible_admission})
		_require(not denied.ok and denied.code == "NO_TECHNOLOGY" and allowed.ok, "Full fixed siege policy checks true selected master before costs", denied)
	_require(var_to_bytes([f.data.site, _combat_state(f), f.data.fingerprint()]) == before, "Policy-only queries preserve original person/state/geographic bytes")

func _generated_production(fixed: Dictionary) -> Dictionary:
	var loaded: Dictionary = fixed.slot._load_checked(fixed.slot.site_path(START), START)
	_require(loaded.ok, "Production input is a real full-pin Store-loaded original cold population", loaded)
	var cold: Dictionary = loaded.data.site
	var data: TerrainData = null
	# Select a lawful GENERATED seed whose existing original cold person cells
	# are walkable. Never edit fixed geography, soil, heights, pin or flags.
	for seed_value: int in range(18373, 18437):
		var candidate: TerrainData = TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, seed_value, {"size": Vector2i(100, 100)})
		Env.initialize(candidate, "g06_generated_" + str(fixed.category) + "_" + str(seed_value))
		var clear := true
		for roster: Dictionary in cold.armies:
			for row: Dictionary in roster.units:
				if not candidate.is_walkable(Vector2i(int(row.cell[0]), int(row.cell[1]))): clear = false
		for actor: Dictionary in cold.actors.values():
			if not candidate.is_walkable(Vector2i(int(actor.cell[0]), int(actor.cell[1]))): clear = false
		if clear:
			data = candidate
			break
	_require(data != null, "Original generated initializer supplies lawful engineering ground without terrain editing")
	# Explicit original cold INPUT records, not a world transfer command or a
	# second birth. Full bodies/items remain originals; no learned field writes.
	for key: String in ["actors", "armies", "actor_presence_version", "controlled_person_id", "next_person_id", "army_next_team", "player_cell", "worker_enabled"] + Runtime.ITEM_FIELDS:
		if cold.has(key): data.site[key] = cold[key].duplicate(true) if cold[key] is Dictionary or cold[key] is Array else cold[key]
	_require(not data.site.has("world_pin") and not data.parameters.has("fixed_base") and not data.site.has("technology_artisans") and not data.site.has("initial_scenario"), "Generated input makes no fixed-world, birth or scenario receipt claim")
	_require(Store._validate_actors(data, data.site).ok and Store._validate_armies(data, data.site, true).ok and Store._validate_items(data, data.site).ok and Store._validate_person_allocator(data.site).ok, "Original validators admit all real cold input person/item records")
	var lab: TerrainLab = _source_lab("generated_" + str(fixed.category))
	_require(lab != null, "Production uses original formal TerrainLab scene")
	lab.bind_terrain(data) # Calls actual Actor.restore_state / Army.restore_combat_state.
	_freeze(lab)
	_require(is_same(lab.terrain, data) and lab.region_bind_receipt(data).get("complete", false) and int(birth_counts[lab.get_instance_id()]) == 0, "Actual generated owner bind restores inputs without Artisans/first birth")
	var team: TerrainArmy = lab.army
	for index: int in team.combat_units.size():
		_require(team.combat_units[index].get("technology", {}) == cold.armies[0].units[index].get("technology", {}) and team.combat_identity(index) == int(cold.armies[0].units[index].person_id), "Same cold original identity/skills survive actual Army restore")
	var restored_control: Dictionary = lab.site_controller._control_family_person(null, int(fixed.commander))
	_require(lab.character.technology == cold.actors.player.get("technology", {}) and restored_control.ok, "Original Actor restore and current command control remain real",
		{"control": restored_control, "actor_technology": lab.character.technology, "cold_technology": cold.actors.player.get("technology", {})})
	if _crowd_port():
		# Crowd port: the generated owner binds the cold rosters, then its teams enter the native crowd (nation base rule)
		# and stand in formation by real points before any named work.
		if lab.crowd_site == null:
			lab.crowd_site = TerrainLab.CrowdSiteScript.new()
			lab.crowd_site.name = "CrowdSite"
			lab.add_child(lab.crowd_site)
			lab.crowd_site.setup(lab)
		if not lab.crowd_site.active:
			var converted: Dictionary = lab.crowd_site.convert_existing()
			if converted.ok: converted = lab._region_write_converted_crowd_section()
			_require(converted.ok, "Generated original teams enter the native crowd", converted)
		_crowd_stand_still({"lab": lab, "data": data, "team": _team_view(lab)}, "after the generated crowd conversion")
	lab.site_controller.save_path = lab.site_controller.save_root.path_join("generated_production.json")
	var policy: Dictionary = Runtime._technology_policy(data)
	_require(policy.ok and policy.policy.categories.is_empty(), "Generated fixture honestly retains legacy unlocked category policy")
	return {"kind": "generated_production", "lab": lab, "data": data, "team": _team_view(lab), "master": fixed.master, "helper": fixed.helper, "commander": fixed.commander,
		"category": fixed.category, "source_body_path": fixed.slot.site_path(START), "source_body_sha256": FileAccess.get_sha256(fixed.slot.site_path(START)),
		"next_person": int(data.site.next_person_id), "next_item_birth": int(data.site.next_item), "geography": data.fingerprint(), "generated_seed": data.seed_value}

func _clear_station(f: Dictionary, identity: int, cell: Vector2i) -> void:
	if _crowd(f):
		for index in _team_units(f.team):
			var other: int = f.team.combat_identity(index)
			if other != identity and _cell_of(f, other) == cell: _park(f, other, cell + Vector2i(0, 4))
		return
	# An earlier assignee may still stand on this station; park it first, as _transfer does.
	for index in _team_units(f.team):
		var other: int = f.team.combat_identity(int(index))
		if other != identity and _cell_of(f, other) == cell: _park(f, other, cell + Vector2i(0, 4))

func _rest_block_reason(f: Dictionary, index: int) -> String:
	var team: TerrainArmy = f.team
	var other := team.combat_identity(index)
	var actions: SitePersonActions = f.lab.site_controller.person_actions
	var job: Dictionary = actions._jobs.get(actions._job_key_for(other), {})
	var parts: Array[String] = []
	if f.lab.site_controller.work_team.is_assigned(other): parts.append("assigned")
	if team.moving_to[index] != TerrainArmy.INVALID_CELL: parts.append("moving")
	if str(team.combat_hot_get(index, &"pose")) != "idle": parts.append("pose=" + str(team.combat_hot_get(index, &"pose")))
	if actions.blocks_fatigue_rest(other): parts.append("job=%s/%s" % [str(job.get("kind", "")), str(job.get("paused", ""))])
	return ",".join(parts)

func _recover_pooled_knockouts(f: Dictionary, shared: Dictionary) -> void:
	# A knocked-out pooled member blocks whole-team rest by design. Its KO ends on
	# its own through original game time (public speed control, real action time).
	var team: TerrainArmy = f.team
	var downed: Array[int] = []
	for index: int in team.combat_units.size():
		if is_same(Fatigue.pool(team.combat_units[index]), shared) and float(team.combat_hot_get(index, &"hp")) > 0.0 and float(team.combat_hot_get(index, &"ko")) > 0.0: downed.append(index)
	if downed.is_empty(): return
	var speed_before: float = float(f.lab.simulation_speed)
	while float(f.lab.simulation_speed) < 4.0: f.lab.change_simulation_speed(1)
	for second: int in 120:
		if downed.all(func(index: int) -> bool: return float(team.combat_hot_get(index, &"ko")) <= 0.0 and str(team.combat_hot_get(index, &"pose")) == "idle"): break
		f.lab._advance_action_time(1.0)
	while float(f.lab.simulation_speed) > speed_before: f.lab.change_simulation_speed(-1)
	var still: Array = []
	for index: int in downed:
		if float(team.combat_hot_get(index, &"ko")) > 0.0 or str(team.combat_hot_get(index, &"pose")) != "idle" or not team.combat_can_act(index):
			still.append("%d:ko=%.1f,pose=%s" % [team.combat_identity(index), float(team.combat_hot_get(index, &"ko")), str(team.combat_hot_get(index, &"pose"))])
	_require(still.is_empty() and float(f.lab.simulation_speed) == speed_before, "Original KO recovery ends through real game time; the pooled member is up before team rest", "still=" + str(still))

func _settle_team_for_rest(f: Dictionary, identity: int) -> void:
	# Pooled fatigue recovers only as a whole-team decision (TerrainLab
	# _advance_team_fatigue). Release the other pooled members' work and settle
	# their in-flight steps through the original APIs, then require eligibility.
	var team: TerrainArmy = f.team
	var shared: Dictionary = team.team_fatigue
	if shared.is_empty(): return
	var work: SiteWorkTeam = f.lab.site_controller.work_team
	var actions: SitePersonActions = f.lab.site_controller.person_actions
	var blockers: Array = []
	for index: int in team.combat_units.size():
		if not is_same(Fatigue.pool(team.combat_units[index]), shared): continue
		var other := team.combat_identity(index)
		var reason := _rest_block_reason(f, index)
		if not reason.is_empty(): blockers.append("%d:%s" % [other, reason])
		if other == identity: continue
		if work.is_assigned(other): _require(work.cancel(other).ok, "Original pooled teammate releases its work before the team rests")
		if team.moving_to[index] != TerrainArmy.INVALID_CELL: team.cancel_committed_move_to_source(other)
	_case["rest_blockers_%d" % identity] = blockers
	_recover_pooled_knockouts(f, shared)
	var still: Array = []
	for index: int in team.combat_units.size():
		if not is_same(Fatigue.pool(team.combat_units[index]), shared): continue
		var other := team.combat_identity(index)
		var left := _rest_block_reason(f, index)
		if not left.is_empty(): still.append("%d:%s" % [other, left])
	_require(still.is_empty() and team.combat_order == TerrainArmy.CombatOrder.HOLD, "Shared team fatigue pool is eligible to rest: every pooled member idle, unassigned and stationary under HOLD", "before=%s still=%s" % [str(blockers), str(still)])

func _place(f: Dictionary, identity: int, cell: Vector2i) -> void:
	if _crowd(f):
		# Crowd: the same native person stands on the station (a placement only moves it; see crowd_fixture_port_guide).
		# A station this fixture held is released first, or its native hold walks the person back.
		if _station_held.erase(identity): f.team.siege_cancel_step(f.team.index_for_identity(identity))
		var native: int = int(f.lab.crowd_site.crowd.soldier_index(identity))
		_require(native >= 0 and f.data.is_walkable(cell) and not _occupied_by_other(f, identity, cell), "Actual crowd person can occupy an unoccupied fixture station")
		_require(f.lab.crowd_site.set_soldier_fields(native, {"px": cell.x + 0.5, "py": cell.y + 0.5}), "Crowd fixture placement of the same native person")
		return
	# Explicit station fixture placement of SAME original GD hot rows; travel,
	# Reservation Grid navigation and Native movement are separate named tests.
	var team: TerrainArmy = f.team
	var index := team.index_for_identity(identity)
	if index >= 0 and team.moving_to[index] != TerrainArmy.INVALID_CELL:
		# A committed step is cancelled through the original owner API before an
		# explicit fixture placement; no stale step may survive the placement.
		team.cancel_committed_move_to_source(identity)
		_require(team.moving_to[index] == TerrainArmy.INVALID_CELL and float(team.move_progress[index]) == 0.0, "Original committed step cancelled before explicit fixture placement")
	_require(index >= 0 and f.data.is_walkable(cell) and team.moving_to[index] == TerrainArmy.INVALID_CELL, "Actual original person can occupy fixture station")
	for at: int in team.cells.size():
		_require(at == index or team.cells[at] != cell, "No second original person occupies station")
	for actor: TerrainTestCharacter in f.lab.combat_actors:
		_require(actor.person_id == identity or actor.terrain_cell != cell, "Original Actor is not overlapped by fixture station")
	team.cells[index] = cell
	team.combat_slots[index] = cell
	team._rebuild_ground_cell_owners()
	team.settle_combat_command()

func _park(f: Dictionary, identity: int, near: Vector2i) -> void:
	_park_cell(f, identity, near)
	# Crowd: a commander is present only within the command radius of its team's reference member (about 8 cells). In play
	# the idle members stand in formation with their commander, so the fixture moves the HOLD centre and the idle members
	# with it (the F04 first-earned rule) and the team settles by real points.
	if _crowd(f) and identity == int(f.commander):
		var head_cell := _cell_of(f, identity)
		f.lab.crowd_site.set_formation_fields(int(f.team.formation_index), {"cx": head_cell.x + 0.5, "cy": head_cell.y + 1.5,
			"origin_x": head_cell.x + 0.5, "origin_y": head_cell.y + 1.5, "goal_x": head_cell.x + 0.5, "goal_y": head_cell.y + 1.5})
		for index in _team_units(f.team):
			var other: int = f.team.combat_identity(index)
			if other == identity or not f.team._cold_get(int(index), "work_task", {}).is_empty(): continue
			var gap := _cell_of(f, other) - head_cell
			if absi(gap.x) + absi(gap.y) > 4: _park_cell(f, other, head_cell + Vector2i(0, 1))
		_crowd_stand_still(f, "after the fixture stationed the commander")

func _park_cell(f: Dictionary, identity: int, near: Vector2i) -> void:
	# Station placement is explicit fixture input; never original navigation proof.
	for radius: int in range(0, 12):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if absi(x) + absi(y) != radius: continue
				var cell := near + Vector2i(x, y)
				if not f.data.is_walkable(cell) or int(f.data.feature_at[f.data.index(cell)]) != 0: continue
				var occupied := _occupied_by_other(f, identity, cell)
				if not occupied:
					_place(f, identity, cell)
					return
	_require(false, "Original generated ground has a free explicit person station")

func _finite_stock(f: Dictionary, extra: Dictionary = {}) -> void:
	# Explicit finite supplied inventory precondition, separate from birth.
	# No output/paid/knowledge evidence is authored here; all production starts
	# with steel/cloth absent and all original jobs/progress empty.
	var stock := {"wood": 30, "stone": 30, "clay": 10, "tools": 4, "grain": 100}
	for key: String in extra: stock[key] = int(extra[key])
	_require(Runtime.inventory_size(stock) <= int(f.data.site.capacity), "Finite fixture supply fits original depot capacity")
	f.data.site.inventory.clear()
	f.data.site.inventory.merge(stock)
	f.data.site.depot_items.version = int(f.data.site.depot_items.version) + 1
	_require(not f.data.site.has("technology_artisans") and int(f.data.site.next_item) == int(f.next_item_birth), "Supplied resources never claim a birth/product/skill grant")

var _interval_failed := false

func _interval(f: Dictionary, seconds: float = 60.0) -> Dictionary:
	if _crowd(f): return _crowd_interval(f, seconds)
	# After its first failure the shared interval stops working, so the long
	# completion loops end quietly instead of repeating the same failure.
	if _interval_failed: return {"effective": 0.0, "actual": 0.0, "handled": {}}
	var failures_before := failures.size()
	_interval_failed = true # Cleared at the end; a runtime error midway leaves it set.
	var lab: TerrainLab = f.lab
	var work: SiteWorkTeam = lab.site_controller.work_team
	var requests := work.prepare_work_requests(seconds, seconds / 60.0)
	var plan := Fatigue.plan_work_interval(requests, seconds)
	_require(plan.ok, "Original complete-pool Fatigue interval admitted", plan)
	lab._shared_work_plan = plan
	lab._shared_work_pools_committed = false
	lab.site_controller._shared_work_plan = plan
	var held := work.prepare_shared_work_prefix(seconds)
	_require(held.ok, "Original WT holds SAME body/task/target references", held)
	var admitted := work.validate_shared_work_prefix(held, plan)
	_require(admitted.ok, "Original post-contact pure Runtime/WT prefix validation", admitted)
	var effective := 0.0
	var actual := 0.0
	for prefix: Dictionary in admitted.prefixes:
		effective += float(prefix.applied_productive_seconds)
		actual += float(prefix.actual_seconds)
	lab._commit_shared_work_pools()
	var consumed := work.publish_shared_work_prefix(admitted)
	var before := var_to_bytes([f.data.site, _combat_state(f)])
	_require(work.publish_shared_work_prefix(admitted).handled_seconds.is_empty() and var_to_bytes([f.data.site, _combat_state(f)]) == before, "SAME allocation cannot pay/progress/charge fatigue twice")
	work.finish_shared_work_prefix(admitted)
	# Mirror the original Lab terminal ledger break after every endpoint finish.
	var completed_priors: Array = admitted.runtime_priors
	var record_ledger: bool = not completed_priors.is_empty() and not _case.has("first_completed_interval_ledger")
	var ledger_fact: Dictionary = {}
	if record_ledger:
		ledger_fact = {"work_id": str(work.get_instance_id()), "terrain_id": str(lab.terrain.get_instance_id()),
			"work_refs_before": work.get_reference_count(), "terrain_refs_before": lab.terrain.get_reference_count(),
			"priors_before": completed_priors.size()}
	if bool(admitted.get("finished", false)): completed_priors.clear()
	_require(bool(admitted.get("finished", false)) and is_same(completed_priors, admitted.runtime_priors)
		and completed_priors.is_empty(), "Completed original interval clears only its SAME terminal ledger")
	for candidate: Dictionary in admitted.runtime:
		# The loop is broken when the finished prefix no longer names the ledger at all,
		# or still names this SAME emptied ledger.
		_require(not candidate.prefix_ref.has("runtime_priors") or is_same(candidate.prefix_ref.runtime_priors, completed_priors) and candidate.prefix_ref.runtime_priors.is_empty(),
			"Completed original Runtime prefix no longer retains candidate ledger loop")
	if record_ledger:
		ledger_fact.merge({"priors_after": completed_priors.size(), "finished": bool(admitted.get("finished", false)),
			"work_refs_after": work.get_reference_count(), "terrain_refs_after": lab.terrain.get_reference_count()})
		_case["first_completed_interval_ledger"] = ledger_fact
	# Genuine original recovery/provider bookkeeping; no pool zeroing, fake
	# fatigue reset, second effort clock or made-up completed-work receipt.
	lab._advance_fatigue(seconds)
	lab._clear_shared_work_step()
	_work_effective += effective
	_work_actual += actual
	_work_intervals += 1
	_interval_failed = failures.size() > failures_before
	return {"effective": effective, "actual": actual, "handled": consumed.handled_seconds}

# ---- Crowd port helpers (2026-11-12; the F04 first-earned base's helpers, shared by every opted-in artisan test) ----
## Opt-in: an artisan test that steps the whole Lab runs on the native crowd (the grid simulation is retired).
func _crowd_port() -> bool:
	return false

func _team_view(lab: TerrainLab) -> Variant:
	var army: TerrainArmy = lab.army
	if lab.crowd_site != null and lab.crowd_site.active:
		var holder: Variant = lab.crowd_site.person_owner(army.combat_identity(army.current_commander))
		if holder != null: return holder
	return army

## The team's metadata rows: a crowd owner keys them by native index, a grid army keeps an array.
func _team_rows(team: Variant) -> Array:
	return team.combat_units.values() if team.combat_units is Dictionary else team.combat_units

func _team_units(team: Variant) -> Array:
	return team.combat_units.keys() if team.combat_units is Dictionary else range(team.combat_units.size())

func _cell_of(f: Dictionary, identity: int) -> Vector2i:
	return f.lab._original_person_target(identity).get("cell", Vector2i(-1, -1))

func _task_of(f: Dictionary, identity: int) -> Dictionary:
	var index: int = f.team.index_for_identity(identity)
	if index < 0: return {}
	return f.team._cold_get(index, "work_task", {}) if _crowd(f) else f.team.combat_units[index].get("work_task", {})

## Crowd: a person the fixture put on its station holds it with the native station hold, and the team settles by real
## points before the next interval (grid placement needs neither).
var _station_held := {}
func _hold_station(f: Dictionary, identity: int) -> void:
	if not _crowd(f): return
	_require(f.lab.crowd_site.siege_approach_step(identity, _cell_of(f, identity)), "Crowd fixture holds a work station", identity)
	_station_held[identity] = true
	_crowd_stand_still(f, "with a held work station")

func _crowd(f: Dictionary) -> bool:
	return f.get("team") is CrowdPersonOwner

func _occupied_by_other(f: Dictionary, identity: int, cell: Vector2i) -> bool:
	for index in _team_units(f.team):
		var other: int = f.team.combat_identity(index)
		if other != identity and (_cell_of(f, other) if _crowd(f) else f.team.cells[int(index)]) == cell: return true
	for actor: TerrainTestCharacter in f.lab.combat_actors:
		if actor.person_id != identity and actor.terrain_cell == cell: return true
	return false

var _crowd_deadline := 0
func _crowd_point(f: Dictionary) -> Dictionary:
	if _crowd_deadline <= 0:
		_crowd_deadline = Time.get_ticks_msec() + 540000 # Real whole-Lab points (in-file 540, outer 600), the over-budget rule.
		deadline = maxi(deadline, _crowd_deadline) # The frame watchdog follows the same bound.
	_require(Time.get_ticks_msec() < _crowd_deadline, "Bounded real point fixture deadline")
	var result: Dictionary = f.lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
	_require(result.ok and result.get("completed", false) and f.lab._region_point_pending.is_empty(), "Original whole Lab point settles actual work/fatigue/clock/contacts", result)
	return result

func _crowd_team_still(f: Dictionary) -> bool:
	if f.team.moving_member_count() > 0: return false
	for index in _team_units(f.team):
		if f.team.is_walking(int(index)) and f.team._cold_get(int(index), "work_task", {}).is_empty(): return false
	return true

## Crowd: wait with real points until the team stands (the crowd settle rule work assignment and consent read).
func _crowd_stand_still(f: Dictionary, label: String) -> void:
	if not _crowd(f): return
	for settle: int in 1800:
		if settle >= 4 and _crowd_team_still(f): break
		_crowd_point(f)
	_require(_crowd_team_still(f), "Crowd team stands still in formation " + label)

func _crowd_feature_work_state(f: Dictionary) -> Dictionary:
	var state := {}
	for key: String in f.data.site.features:
		var feature: Dictionary = f.data.site.features[key]
		state[key] = [str(feature.get("stage", "")), float(feature.get("progress", 0.0)), float(feature.get("work", 0.0)), float(feature.get("production", 0.0))]
	# Siege vehicles under construction keep their work in seconds (build.progress / build.total_work).
	for key: String in f.data.site.get("vehicles", {}):
		var build: Dictionary = f.data.site.vehicles[key].get("build", {})
		if build.is_empty(): continue
		state["vehicle:" + key] = ["complete" if float(build.get("progress", 0.0)) >= float(build.get("total_work", 0.0)) else "build",
			float(build.get("progress", 0.0)) / 60.0, float(build.get("total_work", 0.0)) / 60.0, 0.0]
	return state

## Crowd work clock: the same GAME time advanced by real whole-Lab points; effective work is what those points applied.
func _crowd_interval(f: Dictionary, seconds: float) -> Dictionary:
	var effective := 0.0
	var advanced := 0.0
	while advanced < seconds - 0.000001:
		var before := _crowd_feature_work_state(f)
		var point := _crowd_point(f)
		advanced += float(point.game_seconds)
		var after := _crowd_feature_work_state(f)
		for key: String in before:
			if not after.has(key):
				# A completed siege build leaves the vehicle record's build: the rest of its work was applied in this point.
				if key.begins_with("vehicle:") and before[key][0] != "complete": effective += maxf(0.0, float(before[key][2]) - float(before[key][1])) * 60.0
				continue
			if before[key][0] != "complete" and after[key][0] == "complete": effective += maxf(0.0, float(before[key][2]) - float(before[key][1])) * 60.0
			else: effective += maxf(0.0, float(after[key][1]) - float(before[key][1])) * 60.0 + maxf(0.0, float(after[key][3]) - float(before[key][3])) * 60.0
	_work_effective += effective
	_work_actual += effective
	_work_intervals += 1
	return {"effective": effective, "actual": effective, "handled": {}}

func _idle_all(f: Dictionary) -> void:
	for identity: int in f.lab.site_controller.work_team.active_ids(): f.lab.site_controller.work_team.cancel(identity)
	f.lab._clear_shared_work_step()
	for zone: Dictionary in f.data.site.zones: zone.active = false

func _feature_assign(f: Dictionary, key: String, identity: int, action: String) -> void:
	var feature: Dictionary = f.data.site.features[key]
	var cell: Vector2i = f.data.cell_from_index(int(feature.repair.work_cell) if action == "repair" else int(feature.entrance))
	_clear_station(f, identity, cell)
	_place(f, identity, cell)
	_park(f, int(f.commander), cell + Vector2i(0, 3))
	if action == "construct":
		# A generated map can leave natural resources in the footprint; the original clearing owner handles them first
		# (WorkTeam refuses CLEARING_REQUIRED). The fixture stands in for that clearing.
		for resource_key: String in feature.get("pending_build", feature).get("clearing", []):
			if not SiteEnvironment.resource(f.data, resource_key).is_empty(): SiteEnvironment.change(f.data, resource_key, {"cleared": true, "remaining": 0})
		SiteEnvironment.rebuild_indexes(f.data) # As the real clearing owner does: cleared cells walk again.
	var prepared: Dictionary = f.lab.site_controller.work_team.prepare_assign_feature(f.team, [identity], int(f.commander), key, action)
	_require(prepared.ok, "Original named feature assignment", prepared)
	_require(f.lab.site_controller.work_team.publish_assign_feature(prepared).ok, "Original prevalidated assignment publisher")

func _build(f: Dictionary, kind: String, anchor: Vector2i) -> String:
	_idle_all(f)
	var options := {"owner_faction": int(f.team.faction_id)}
	var layout: Dictionary = {}
	# Select through the ORIGINAL preview, with real generated foundation,
	# groundwater, height, occupancy and reachable doorway guards unchanged.
	for radius: int in range(0, 30):
		if not layout.is_empty(): break
		for y: int in range(-radius, radius + 1):
			if not layout.is_empty(): break
			for x: int in range(-radius, radius + 1):
				if absi(x) + absi(y) != radius: continue
				var selected := anchor + Vector2i(x, y)
				if f.has("water_origin") and absi(selected.x - int(f.water_origin.x)) + absi(selected.y - int(f.water_origin.y)) > 8: continue
				var candidate: Dictionary = Runtime.building_cells(f.data, kind, selected, Vector2i.ONE, options)
				if not candidate.ok: continue
				var candidate_cells: Array[int] = []
				candidate_cells.assign(candidate.cells)
				if _artisan_cells_hold_person(f, candidate_cells): continue # The work selector refuses a footprint someone stands on.
				var preview: Dictionary = Runtime.preview_build(f.data, kind, candidate_cells, Callable(f.lab.site_controller, "reserves_cell"), options)
				if preview.ok:
					layout = candidate
					break
	_require(not layout.is_empty(), "Actual generated source preview admits " + kind)
	var cells: Array[int] = []
	cells.assign(layout.cells)
	var prior: Dictionary = f.data.site.inventory.duplicate(true)
	var requested: Dictionary = Runtime.request_build(f.data, kind, cells, Callable(f.lab.site_controller, "reserves_cell"), options)
	_require(requested.ok, "Original building command pays full actual cost", requested)
	var key := str(requested.feature)
	var feature: Dictionary = f.data.site.features[key]
	var initial_work := float(feature.work) * 60.0
	_feature_assign(f, key, int(f.master), "construct")
	var effective := _work_effective
	for tick: int in 2500:
		if str(feature.stage) == "complete": break
		_interval(f)
	_require(str(feature.stage) == "complete" and _work_effective - effective >= initial_work - 0.0001, "Real full original construction work completes " + kind,
		{"stage": feature.get("stage"), "progress": feature.get("progress"), "work": feature.get("work"), "effective": _work_effective - effective, "needed": initial_work, "zones": f.data.site.zones.size(), "busy": f.lab.site_controller.work_team.active_ids()})
	_require(prior != f.data.site.inventory and f.data.fingerprint() == f.geography and not f.data.parameters.has("fixed_base"), "Construction spends actual stock without editing generated geographic source")
	_idle_all(f)
	return key

func _operate(f: Dictionary, key: String, recipe: String, identity: int) -> void:
	_idle_all(f)
	_require(Runtime.request_feature_recipe(f.data, key, recipe, int(f.team.faction_id)).ok, "Original recipe command selects actual existing recipe")
	_require(Runtime.operate_feature(f.data, key).ok, "Original operation creates actual feature work zone")
	_feature_assign(f, key, identity, "operate")

func _finish_recipe(f: Dictionary, key: String, recipe: String, output: Dictionary) -> void:
	var feature: Dictionary = f.data.site.features[key]
	var definition := Runtime.feature_recipe(feature)
	var body: Dictionary = f.team.combat_units[f.team.index_for_identity(int(f.master))]
	var prior_cargo: Dictionary = body.cargo.duplicate(true)
	var prior_stock: Dictionary = f.data.site.inventory.duplicate(true)
	var effective := _work_effective
	for tick: int in 2500:
		if output.keys().all(func(key_name: Variant) -> bool: return int(body.cargo.get(key_name, 0)) == int(prior_cargo.get(key_name, 0)) + int(output[key_name])): break
		_interval(f)
	for key_name: String in output: _require(int(body.cargo.get(key_name, 0)) == int(prior_cargo.get(key_name, 0)) + int(output[key_name]), "Exactly one real recipe output in original person cargo")
	for material: String in definition.input: _require(int(prior_stock.get(material, 0)) - int(f.data.site.inventory.get(material, 0)) == int(definition.input[material]), "Full recipe material consumed exactly once: " + material)
	_require(_work_effective - effective >= float(definition.cycle) * 60.0 - 0.0001 and not feature.batch_paid and float(feature.production) == 0.0, "No recipe duration/progress shortcut")
	_require(not f.lab.site_controller.work_team.is_assigned(int(f.master)), "True named batch completion stops instead of starting another batch")
	var receipt: Dictionary = feature.get("technology_output", {}).get("receipts", [])[0] if not feature.get("technology_output", {}).get("receipts", []).is_empty() else {}
	_require(not receipt.is_empty() and receipt.operator_id == int(f.master) and receipt.recipe_id == recipe and receipt.resources == output, "Unique actual original canonical output receipt")
	_idle_all(f)

func _transfer(f: Dictionary, identity: int, source_id: String, destination_id: String, resources: Dictionary, cell: Vector2i) -> void:
	_idle_all(f)
	for index in _team_units(f.team):
		var other: int = f.team.combat_identity(int(index))
		if other != identity and _cell_of(f, other) == cell: _park(f, other, cell + Vector2i(0, 4))
	_place(f, identity, cell)
	_park(f, int(f.commander), cell + Vector2i(0, 3))
	var logistics_people: Array[int] = [identity] # The controller API takes a typed array.
	_require(f.lab.site_controller.order_team_logistics(f.team, logistics_people, int(f.commander), true).ok, "Actual current logistics decider names original person")
	var vehicles: SiteVehicleTransport = f.lab.site_controller.vehicles
	var source: Dictionary = vehicles._stock(source_id, source_id.begins_with("feature:") or destination_id.begins_with("feature:"))
	var destination: Dictionary = vehicles._stock(destination_id, source_id.begins_with("feature:") or destination_id.begins_with("feature:"))
	_require(not source.is_empty() and not destination.is_empty(), "True original physical cargo endpoints")
	var result := vehicles.transfer(source_id, destination_id, resources, [], int(source.holder.version), int(destination.holder.version), int(f.commander))
	_require(result.ok, "True original full-version adjacent resource transfer", result)
	_require(f.lab.site_controller.order_team_logistics(f.team, logistics_people, int(f.commander), false).ok, "Original person ends logistics without new owner")

func _processing(f: Dictionary) -> void:
	_finite_stock(f, {"iron": 2, "charcoal": 3, "wool": 3})
	var well := _build(f, "well", Vector2i(58, 58))
	f.water_origin = f.data.cell_from_index(int(f.data.site.features[well].cells[0]))
	var key := _build(f, "smelter" if f.category == "F04" else "weaver", Vector2i(60, 58))
	var recipe := "steel" if f.category == "F04" else "wool_cloth"
	var output := {"steel": 1} if f.category == "F04" else {"cloth": 2}
	_require(not Technology.learned(f.team.combat_units[f.team.index_for_identity(int(f.helper))].get("technology", {}), str(f.category)), "Selected helper genuinely unlearned")
	_operate(f, key, recipe, int(f.helper))
	var task: Dictionary = f.team.combat_units[f.team.index_for_identity(int(f.helper))].work_task
	var legacy: Dictionary = Runtime.technology_recipe_guard(f.data, key, f.data.site.features[key], int(f.helper))
	_require(legacy.ok and task.target == "feature:" + key, "Generated legacy original stock recipe remains accessible to unlearned person; NOT D10 locked proof", legacy)
	_idle_all(f) # No legacy-unlearned product or work is fabricated for this check.
	_operate(f, key, recipe, int(f.master))
	_finish_recipe(f, key, recipe, output)
	if f.category == "F04":
		var depot: Vector2i = f.data.cell_from_index(int(f.data.site.depot_cell))
		_transfer(f, int(f.master), "person:" + str(f.master), "depot", {"steel": 1}, depot + Vector2i.RIGHT)
		var smithy := _build(f, "smithy", Vector2i(66, 58))
		_operate(f, smithy, "steel_tools", int(f.master))
		_finish_recipe(f, smithy, "steel_tools", {"tools": 2})
		key = smithy
		output = {"tools": 2}
	_require(Stocks.set_local_supply(f.data, key, true, int(f.team.faction_id)).ok, "Actual original workshop stock endpoint enabled")
	var endpoint: Dictionary = Stocks.stock_endpoint(f.data, key)
	_transfer(f, int(f.master), "person:" + str(f.master), "feature:" + key, output, endpoint.cell)
	_transfer(f, int(f.helper), "feature:" + key, "person:" + str(f.helper), output, endpoint.cell)
	_require(not Technology.learned(f.team.combat_units[f.team.index_for_identity(int(f.helper))].get("technology", {}), str(f.category)), "True finished-product pickup requires no production skill")
	_require(not f.data.site.has("family") and not f.data.site.has("technology_artisans"), "Ordinary independent production creates no family/research/birth grant")
	_case.processing_report = {"recipe": recipe, "well": well, "feature": key, "effective_work_seconds": _work_effective, "actual_participant_seconds": _work_actual}
	_cold_resume(f, "independent_processing_finished")
	_teach_second_master(f)
	# A second TRUE learned replacement then performs a second complete original
	# cycle at the SAME host. Its only new input is this finite supplied stock.
	var second_recipe: String = "steel_tools" if f.category == "F04" else "wool_cloth"
	var definition: Dictionary = Runtime.feature_recipe(f.data.site.features[key])
	var second_supply: Dictionary = definition.input
	for material: String in second_supply: Runtime.add_items(f.data.site.inventory, {material: int(second_supply[material])})
	f.data.site.depot_items.version = int(f.data.site.depot_items.version) + 1
	# Return the existing local-stock endpoint to ordinary depot supply by the
	# actual command; no shadow inventory. First output was legitimately picked up.
	_require(Stocks.set_local_supply(f.data, key, false, int(f.team.faction_id)).ok, "Original host explicitly resumes camp input source")
	var original_master: int = int(f.master)
	f.master = f.helper
	_operate(f, key, second_recipe, int(f.master))
	_finish_recipe(f, key, second_recipe, output)
	f.master = original_master
	_case.true_taught_replacement = {"person_id": f.helper, "lesson_effective_seconds": 300, "recipe": second_recipe, "output": output.duplicate(true)}

func _land_committed_step(f: Dictionary, identity: int) -> void:
	# A committed step (for example travel of a task cancelled just before) finishes
	# through the original movement time the Lab runs; bounded, then required.
	var index: int = f.team.index_for_identity(identity)
	if _crowd(f):
		# Crowd: the person lands by the crowd settle rule through real points.
		for step: int in 600:
			if index < 0 or not f.team.is_walking(index): break
			_crowd_point(f)
		_require(index >= 0 and not f.team.is_walking(index), "Crowd person stands before reassignment", {"identity": identity})
		return
	for step: int in 600:
		if index < 0 or f.team.moving_to[index] == TerrainArmy.INVALID_CELL: break
		f.lab._advance_action_time(TerrainLab.ACTION_STEP)
	_require(index >= 0 and f.team.moving_to[index] == TerrainArmy.INVALID_CELL and float(f.team.move_progress[index]) == 0.0, "Original committed step lands through real movement time before reassignment", {"identity": identity, "moving_to": str(f.team.moving_to[index]) if index >= 0 else ""})

func _station_named_member(f: Dictionary, identity: int, near: Vector2i) -> void:
	# Explicit station input like the master/commander placements. A fixture placement
	# is not a landed step, so presence is refreshed by a real command event: the
	# current commander re-confirms the unchanged tactical-AI setting.
	_park(f, identity, near)
	if _crowd(f):
		# Crowd: the team's HOLD centre comes to the job so the captain stays within command presence; the team settles by
		# real points (the crowd_fixture_port_guide rule), then the named member stands at its job again.
		var centre := near + Vector2i(0, 3)
		f.lab.crowd_site.set_formation_fields(int(f.team.formation_index), {"cx": centre.x + 0.5, "cy": centre.y + 0.5,
			"origin_x": centre.x + 0.5, "origin_y": centre.y + 0.5, "goal_x": centre.x + 0.5, "goal_y": centre.y + 0.5})
		_crowd_stand_still(f, "with its named member")
		if _cell_of(f, identity).distance_to(near) > 2.0: _park(f, identity, near)
		return
	var team: TerrainArmy = f.team
	var confirmed: Dictionary = team.set_tactical_ai_enabled(team.current_commander, team.tactical_ai_enabled)
	_require(confirmed.ok and team.get_active_move_plan() == null and team.moving_member_count() == 0, "Unchanged tactical-AI confirmation refreshes presence without any movement", confirmed)
	_require(bool(team.combat_hot_get(team.index_for_identity(identity), &"present", false)), "Named member stands within the team's command radius at its job")

func _siege_assign(f: Dictionary, key: String, identities: Array) -> void:
	for identity: Variant in identities: _land_committed_step(f, int(identity))
	# The original assignment refuses while ANY member (or the joined player) is mid-step; let the
	# other members' committed steps land through real movement time as well.
	if _crowd(f): _crowd_stand_still(f, "before the siege assignment")
	var settle_steps := 0
	while not _crowd(f) and settle_steps < 600 and (f.team.moving_member_count() > 0 or is_instance_valid(f.team.player_member) and f.team.player_member.is_moving()):
		f.lab._advance_action_time(TerrainLab.ACTION_STEP)
		settle_steps += 1
	var prepared: Dictionary = f.lab.site_controller.work_team.prepare_assign_vehicle(f.team, identities, int(f.commander), key)
	_require(prepared.ok, "Current original team.work decider names true siege members", prepared)
	_require(f.lab.site_controller.work_team.publish_assign_vehicle(prepared).ok, "Original fixed siege work slots published")
	for entry: Dictionary in prepared.entries:
		_place(f, int(entry.identity), f.data.cell_from_index(int(entry.task.work_cell)))

func _finish_siege_real(f: Dictionary, key: String) -> void:
	var vehicle: Dictionary = f.data.site.vehicles[key]
	for tick: int in 6000:
		if vehicle.build.is_empty(): break
		_interval(f)
	_require(vehicle.build.is_empty() and str(vehicle.phase) == "idle" and float(vehicle.hp) == float(Runtime.SIEGE_DEFINITIONS[vehicle.kind].max_hp), "Actual full-work original siege product finished")
	_idle_all(f)

func _siege_anchor(f: Dictionary, kind: String, near: Vector2i) -> Vector2i:
	var last := {}
	for radius: int in range(0, 60):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if absi(x) + absi(y) != radius: continue
				var anchor := near + Vector2i(x, y)
				var checked: Dictionary = Runtime.begin_siege_build(f.data, kind, anchor, Vector2i.RIGHT, int(f.team.team_id), int(f.commander), Callable(f.lab.site_controller, "reserves_cell"), true, {}, {}, int(f.master))
				if checked.ok: return anchor
				if radius == 0: last = checked
	_require(false, "Original geometry/authority preview finds real finite siege ground", {"near": str(near), "at_near": last})
	return TerrainArmy.INVALID_CELL

func _siege(f: Dictionary) -> void:
	var kind := "siege_tower" if f.category == "F11" else "counterweight_trebuchet"
	var terms: Dictionary = Runtime.SIEGE_DEFINITIONS[kind]
	var supply: Dictionary = terms.cost.duplicate(true)
	for material: String in supply: supply[material] = int(supply[material]) + 4
	_finite_stock(f, supply)
	var anchor := _siege_anchor(f, kind, Vector2i(66, 60))
	var before: PackedByteArray = var_to_bytes([f.data.site, _combat_state(f)])
	var legacy: Dictionary = Runtime.begin_siege_build(f.data, kind, anchor, Vector2i.RIGHT, int(f.team.team_id), int(f.commander), Callable(f.lab.site_controller, "reserves_cell"), true, {}, {}, int(f.helper))
	_require(legacy.ok and var_to_bytes([f.data.site, _combat_state(f)]) == before, "Generated legacy construction remains available to unlearned member; preview spends nothing; NOT locked-policy proof", legacy)
	var inventory: Dictionary = f.data.site.inventory.duplicate(true)
	var begun: Dictionary = Runtime.begin_siege_build(f.data, kind, anchor, Vector2i.RIGHT, int(f.team.team_id), int(f.commander), Callable(f.lab.site_controller, "reserves_cell"), false, {}, {}, int(f.master))
	_require(begun.ok, "Original full-cost command admits actual independent learned master", begun)
	var key := str(begun.vehicle)
	var vehicle: Dictionary = f.data.site.vehicles[key]
	for material: String in terms.cost: _require(int(inventory[material]) - int(f.data.site.inventory[material]) == int(terms.cost[material]), "Full original siege cost once: " + material)
	_require(float(vehicle.build.total_work) == float(terms.work_seconds) and float(vehicle.build.progress) == 0.0, "Immutable original siege work terms")
	var master_task: Dictionary = f.team.combat_units[f.team.index_for_identity(int(f.master))].work_task
	_place(f, int(f.master), f.data.cell_from_index(int(master_task.work_cell)))
	_park(f, int(f.commander), anchor + Vector2i(-4, 0))
	_siege_assign(f, key, [int(f.helper)])
	_interval(f)
	_require(float(vehicle.build.progress) > 0.0, "True master and unlearned helper jointly perform original work")
	var progress := float(vehicle.build.progress)
	_park(f, int(f.master), anchor + Vector2i(-6, 0))
	_require(_cell_of(f, int(f.master)) != f.data.cell_from_index(int(master_task.work_cell)), "Original master truly leaves held station")
	_interval(f)
	_require(float(vehicle.build.progress) > progress and vehicle.build.paid_cost == terms.cost, "Legacy helper may continue without manufacturing master; no repeat payment; D10 master-gated interruption still OPEN")
	progress = float(vehicle.build.progress)
	_require(f.lab.site_controller.work_team.cancel(int(f.master)).ok, "Actual original master cancels old task")
	_siege_assign(f, key, [int(f.master)])
	_interval(f)
	_require(float(vehicle.build.progress) > progress, "SAME genuine learned master legally resumes at an original free slot")
	_finish_siege_real(f, key)
	_require(not f.data.site.has("family") and not vehicle.has("tech_trial") and not f.data.site.has("technology_artisans"), "Independent background F12/F11 creates no family, research or traction history")
	_cold_resume(f, "independent_finished")
	_case.independent_vehicle = key
	_case.full_work_seconds = terms.work_seconds
	_case.paid_cost = terms.cost.duplicate(true)
	_two_true_masters(f, kind)
	await _basic_siege_use_repair(f, key)

func _cold_resume(f: Dictionary, label: String) -> void:
	if f.kind == "generated_production":
		_generated_cold_resume(f, label)
		return
	_idle_all(f)
	var controller: SiteController = f.lab.site_controller
	# A real death earlier in this scenario leaves its original fall/remains timer pending; the
	# save guard refuses until it settles. Let original shared steps run it out (bounded).
	var settle_points := 0
	while not controller._pending_deaths.is_empty() and settle_points < 4000:
		settle_points += 1
		var settled: Dictionary = f.lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
		_require(settled.ok and settled.get("completed", false), "Original shared step settles the pending death before the save boundary", settled)
	_require(controller._pending_deaths.is_empty(), "Original pending death settles through real time before the cold save", {"pending": controller._pending_deaths})
	var captured := controller._capture_for_save()
	_require(captured.ok, "Original live owners capture actual current bodies/items", captured)
	var facts := _facts(f.data.site)
	var saved := controller.save_to(controller.save_path)
	_require(saved.ok, "Original full-pin Store/Slot saves actual productive scene", saved)
	var cold := controller.region_slot._load_checked(controller.region_slot.site_path(START), START)
	_require(cold.ok and cold.data.site.technology_artisans == f.birth and cold.data.site.world_pin == f.pin and cold.data.parameters.fixed_base == f.fixed_base, "Real Store read validates full fixed_base/pin and birth history", cold)
	var lab := _source_lab("g06_resume_" + label)
	_require(lab != null, "Second true formal main scene shell instantiated")
	lab.crowd_startup_requested = _crowd_port()
	var restored = lab.site_controller.open_fixed_world(manifest_path, str(f.world), SLOT, Vector2i(-1, -1), false)
	_require(restored.ok, "Original Slot/Controller cold reopen and selected fullgraph bind", restored)
	_freeze(lab)
	_require(int(birth_counts[lab.get_instance_id()]) == 0 and _facts(lab.terrain.site) == facts and lab.region_bind_receipt(lab.terrain).get("complete", false), "Cold/reopen retains exact products/skills/allocators; no new birth")
	f.lab.free()
	_settle_render_frees()
	f.lab = lab
	f.data = lab.terrain
	f.team = _team_view(lab)
	f.slot = lab.site_controller.region_slot
	_require(f.data.site.technology_artisans == f.birth and int(f.data.site.next_person_id) == int(f.next_person), "Rebind never teaches or reissues original people")

func _generated_cold_resume(f: Dictionary, label: String) -> void:
	_idle_all(f)
	var controller: SiteController = f.lab.site_controller
	var captured: Dictionary = controller._capture_for_save()
	_require(captured.ok, "Original generated live owners capture actual bodies/products", captured)
	var facts: String = _facts(f.data.site)
	var products: String = _normalized([f.data.site.features, f.data.site.get("vehicles", {}), f.data.site.inventory, f.data.site.get("family", {})])
	var path: String = controller.save_path
	var saved: Dictionary = controller.save_to(path)
	_require(saved.ok, "Original generated Store save without fixed pin or geography masquerade", saved)
	var cold: Dictionary = Store.load_site(path)
	_require(cold.ok and not cold.data.site.has("world_pin") and not cold.data.parameters.has("fixed_base") and not cold.data.site.has("technology_artisans"), "True generated Store read validates its own original source", cold)
	var lab: TerrainLab = _source_lab("generated_resume_" + label)
	_require(lab != null, "Second actual formal generated scene shell")
	lab.site_controller.save_root = controller.save_root
	lab.site_controller.save_path = path
	var restored: Dictionary = lab.site_controller.load_from(path)
	_require(restored.ok, "Original Controller generated load and complete owner bind", restored)
	_freeze(lab)
	_require(int(birth_counts[lab.get_instance_id()]) == 0 and _facts(lab.terrain.site) == facts and lab.region_bind_receipt(lab.terrain).get("complete", false), "Generated cold rebind retains true people/skills/items with zero births")
	_require(_normalized([lab.terrain.site.features, lab.terrain.site.get("vehicles", {}), lab.terrain.site.inventory, lab.terrain.site.get("family", {})]) == products, "Actual completed products/finite budgets/history retain exact saved normalized values")
	f.lab.free()
	_settle_render_frees()
	f.lab = lab
	f.data = lab.terrain
	f.team = lab.army
	_require(int(f.data.site.next_person_id) == int(f.next_person) and f.data.fingerprint() == f.geography, "Generated restore preserves original allocator and its lawful generated ground")

func _teach_second_master(f: Dictionary) -> void:
	# Named teaching precondition: a strict legitimate known Family archive.
	# This is not this fixture's research/birth evidence. No learned state or
	# siege history is authored; the SECOND master must earn a real 300s lesson.
	var actions: SitePersonActions = f.lab.site_controller.person_actions
	var refs: Array = []
	for identity: int in [int(f.commander), int(f.master), int(f.helper)]:
		refs.append({"site_id": str(f.data.site.id), "person_id": identity, "path": "", "label": "具名工程教學原人", "age_years": -1})
	_require(f.lab.site_controller.family_continuity.register_members(refs, true, int(f.commander)).ok and f.lab.site_controller.family_continuity.appoint_head(int(f.commander), int(f.commander)).ok, "Actual Family registration and lawful head")
	f.data.site.family = actions._technology_candidate()
	f.data.site.family.technology = Technology.empty_scope_record(str(f.data.site.id))
	f.data.site.family.technology.known = [str(f.category)]
	_require(Family.validate_family(f.data.site.family, str(f.data.site.id)), "Named existing known Family archive passes original strict validator")
	_cold_resume(f, "known_teaching_archive")
	actions = f.lab.site_controller.person_actions
	var depot: Vector2i = f.data.cell_from_index(int(f.data.site.depot_cell))
	var parked := 0
	for index in _team_units(f.team):
		_park(f, f.team.combat_identity(int(index)), depot + Vector2i(0, 8 + parked))
		parked += 1
	var lesson_cells: Array[Vector2i] = []
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var selected := depot + direction
		if not f.data.is_walkable(selected) or not f.data.can_step(selected, depot): continue
		var occupied := false
		for actor: TerrainTestCharacter in f.lab.combat_actors:
			if actor.terrain_cell == selected: occupied = true
		if not occupied: lesson_cells.append(selected)
	_require(lesson_cells.size() >= 2, "Actual original camp has two legal distinct lesson contact cells")
	_place(f, int(f.master), lesson_cells[0])
	_place(f, int(f.helper), lesson_cells[1])
	if _crowd(f):
		# Crowd: teacher and student hold their camp contacts with the lesson's own native station hold while the team settles.
		for identity: int in [int(f.master), int(f.helper)]:
			_require(f.lab.crowd_site.siege_approach_step(identity, _cell_of(f, identity)), "Crowd fixture holds a camp station", identity)
		_crowd_stand_still(f, "before the lesson")
	var item_sequence: int = int(f.data.site.next_item)
	var items_before: String = _normalized(f.data.site.item_records)
	_require(actions.begin_technology_lesson(int(f.commander), int(f.master), int(f.helper), str(f.category)).ok, "True original family teaching command")
	var elapsed := 0.0
	if _crowd(f):
		# Crowd: the lesson runs through real whole-Lab points; its own job records the taught seconds.
		var lesson_job: Dictionary = actions._jobs.get(actions._job_key_for(int(f.master)), {})
		for point: int in 16000:
			if not actions.is_busy(int(f.master)): break
			_crowd_point(f)
		elapsed = float(lesson_job.get("elapsed", 0.0))
	for tick: int in (0 if _crowd(f) else 100):
		if not actions.is_busy(int(f.master)): break
		var requests := actions.work_requests(30.0)
		var plan := Fatigue.plan_work_interval(requests, 30.0)
		_require(plan.ok and requests.size() == 1, "True teacher/student joint original lesson work", plan)
		f.lab._shared_work_plan = plan
		f.lab._shared_work_pools_committed = false
		f.lab.site_controller._shared_work_plan = plan
		var actual_job: Dictionary = actions._jobs.get(actions._job_key_for(int(f.master)), {})
		_require(not actual_job.is_empty() and float(actual_job.duration) == 300.0, "Actual original lesson job keeps full 300-second terms")
		elapsed += float(plan.jobs.person_actions.get(str(int(f.master)), {}).get("effective_seconds", 0.0))
		# The original Lab provider advances this actual lesson once, commits its
		# shared pool and handles genuine REST recovery; no second job timer.
		f.lab._advance_fatigue(30.0)
		actions.settle_after_contacts()
		f.lab._clear_shared_work_step()
	_require(elapsed >= 300.0 - 0.0001 and not actions.is_busy(int(f.master)) and Technology.learned(f.team.combat_units[f.team.index_for_identity(int(f.helper))].get("technology", {}), str(f.category)), "Second master learned only at actual completed 300s lesson")
	_require(int(f.data.site.next_item) == item_sequence and _normalized(f.data.site.item_records) == items_before, "Real lesson issues zero free item/products")
	for index: int in f.team.combat_units.size():
		var identity: int = f.team.combat_identity(index)
		_require(Technology.learned(f.team.combat_units[index].get("technology", {}), str(f.category)) == (identity in [int(f.master), int(f.helper)]), "True lesson teaches precisely the named original student")
	_require(f.data.site.family.technology.get("siege_history", []).is_empty(), "Teaching a background F12 skill adds no fictional traction history")
	_cold_resume(f, "true_student")
	_case.real_lesson = {"teacher": f.master, "student": f.helper, "effective_seconds": elapsed, "archive_known_precondition_not_research_evidence": true}

func _two_true_masters(f: Dictionary, kind: String) -> void:
	_teach_second_master(f)
	var cost: Dictionary = Runtime.SIEGE_DEFINITIONS[kind].cost
	# Explicit SECOND finite resource allocation; no free siege product/job.
	for material: String in cost: Runtime.add_items(f.data.site.inventory, {material: int(cost[material])})
	f.data.site.depot_items.version = int(f.data.site.depot_items.version) + 1
	var anchor := _siege_anchor(f, kind, Vector2i(78, 60))
	var begun: Dictionary = Runtime.begin_siege_build(f.data, kind, anchor, Vector2i.RIGHT, int(f.team.team_id), int(f.commander), Callable(f.lab.site_controller, "reserves_cell"), false, {}, {}, int(f.master))
	_require(begun.ok, "Second full-cost original engineering job", begun)
	var key := str(begun.vehicle)
	var vehicle: Dictionary = f.data.site.vehicles[key]
	var task: Dictionary = f.team.combat_units[f.team.index_for_identity(int(f.master))].work_task
	_place(f, int(f.master), f.data.cell_from_index(int(task.work_cell)))
	_park(f, int(f.commander), anchor + Vector2i(-4, 0))
	_siege_assign(f, key, [int(f.helper)])
	var assistant: int = f.team.combat_identity(1 if f.category != "F04" else 3)
	if assistant == int(f.master) or assistant == int(f.helper): assistant = f.team.combat_identity(2)
	_require(not Technology.learned(f.team.combat_units[f.team.index_for_identity(assistant)].get("technology", {}), str(f.category)), "Third actual engineer is unlearned helper")
	_station_named_member(f, assistant, anchor + Vector2i(-4, 2))
	_siege_assign(f, key, [assistant])
	_interval(f)
	var progress := float(vehicle.build.progress)
	_park(f, int(f.master), anchor + Vector2i(-6, 0))
	_require(_cell_of(f, int(f.master)) != f.data.cell_from_index(int(task.work_cell)), "Teacher truly leaves second original held station")
	_interval(f)
	_require(float(vehicle.build.progress) > progress, "Other TRUE taught master works at actual task/slot after teacher leaves; legacy-policy production subset")
	progress = float(vehicle.build.progress)
	_park(f, int(f.helper), anchor + Vector2i(-6, 2))
	var student_task: Dictionary = f.team.combat_units[f.team.index_for_identity(int(f.helper))].work_task
	_require(_cell_of(f, int(f.helper)) != f.data.cell_from_index(int(student_task.work_cell)), "Last taught master truly leaves held station")
	_interval(f)
	_require(float(vehicle.build.progress) > progress and vehicle.build.paid_cost == cost, "Legacy unlearned assistant still works without last master; explicitly NOT D10 fixed-policy stop acceptance")
	_idle_all(f)
	_case.two_masters = {"vehicle": key, "teacher": f.master, "actual_student": f.helper, "lesson_seconds": 300,
		"before_last_master_left": progress, "after_last_master_left": float(vehicle.build.progress), "helper": assistant, "D10_gated_interruption_not_verified": true}
	# Retire the actual second paid job through its original cancellation API.
	# Never leave another construction for the ordinary repair selector to pick.
	var cancelled: Dictionary = Runtime.cancel_siege_job(f.data, key, int(f.team.team_id), Callable(f.lab.site_controller, "_siege_people_occupied"))
	_require(cancelled.ok, "Original second unfinished job cancels/refunds remaining real materials", cancelled)

func _basic_siege_use_repair(f: Dictionary, key: String) -> void:
	_idle_all(f)
	var vehicle: Dictionary = f.data.site.vehicles[key]
	var unlearned: int = f.team.combat_identity(1)
	if Technology.learned(f.team.combat_units[1].get("technology", {}), str(f.category)): unlearned = f.team.combat_identity(2)
	_require(not Technology.learned(f.team.combat_units[f.team.index_for_identity(unlearned)].get("technology", {}), str(f.category)), "Selected product user/repairer truly lacks manufacturing skill")
	var crew_cell: Vector2i = Runtime.siege_crew_cell(f.data, vehicle, 0)
	# Land through real action time before the existing explicit station inputs.
	_land_committed_step(f, unlearned)
	_land_committed_step(f, int(f.commander))
	_place(f, unlearned, crew_cell)
	_park(f, int(f.commander), crew_cell + Vector2i(0, 3))
	# Original crew authority requires the actual controlled requester.
	var control: Dictionary = f.lab.site_controller._control_family_person(null, int(f.commander))
	_require(control.ok, "Original command control restored before actual crew dispatch", control)
	var crew_index: int = f.team.index_for_identity(unlearned)
	var crew_before: Dictionary = {"requester": int(f.commander), "controlled": f.lab.controlled_person_id(),
		"current_commander": f.team.current_commander, "member": f.team.is_member(crew_index),
		"hp": f.team.combat_hot_get(crew_index, &"hp"), "ko": f.team.combat_hot_get(crew_index, &"ko"),
		"pose": f.team.combat_hot_get(crew_index, &"pose"), "present": f.team.combat_hot_get(crew_index, &"present"),
		"moving_to": str(f.team.moving_to[crew_index]), "cell": str(_cell_of(f, f.team.combat_identity(crew_index))), "crew_cell": str(crew_cell),
		"work_task": f.team.combat_units[crew_index].get("work_task", {}).duplicate(true),
		"assigned": f.lab.site_controller.work_team.is_assigned(unlearned), "phase": vehicle.phase,
		"crew_slots": vehicle.crew_slots.duplicate(true), "action": vehicle.action.duplicate(true), "move": vehicle.move.duplicate(true)}
	var appearance_before: Dictionary = f.lab.site_controller.person_appearance(unlearned).duplicate(true)
	var asset_preparation: Dictionary = {"person_id": unlearned, "appearance_before": appearance_before,
		"key_before": TerrainArmy.EquipmentAtlas._mixed_key(appearance_before),
		"ready_before": SiteController.SiegeWorkAppend.ready(appearance_before),
		"output_before": SiteController.SiegeWorkAppend.directory(appearance_before)}
	# Match the original UI command boundary for this same original crew member.
	var assets_prepared: bool = await f.lab.site_controller._prepare_siege_work_people([unlearned])
	# Capture can return inside its draw signal; leave it before any caller teardown.
	await process_frame
	var appearance_after: Dictionary = f.lab.site_controller.person_appearance(unlearned).duplicate(true)
	asset_preparation.merge({"result": assets_prepared, "appearance_after": appearance_after,
		"key_after": TerrainArmy.EquipmentAtlas._mixed_key(appearance_after),
		"ready_after": SiteController.SiegeWorkAppend.ready(appearance_after),
		"output_after": SiteController.SiegeWorkAppend.directory(appearance_after)})
	_case["siege_work_prepare_" + key] = asset_preparation
	_require(assets_prepared, "Original command preparation admits SAME unlearned crew work appearance", asset_preparation)
	if not assets_prepared: return
	var crew_assigned: Dictionary = f.lab.site_controller.vehicles.assign_crew(key, unlearned, "0", int(f.commander))
	_require(crew_assigned.ok, "Unlearned original member may use completed siege product", {"result": crew_assigned, "before": crew_before})
	var crew_released: Dictionary = f.lab.site_controller.vehicles.unassign_crew(key, unlearned, int(f.commander))
	_require(crew_released.ok, "Original crew releases same product", crew_released)
	_case["basic_siege_" + key] = {"crew_before": crew_before, "assign_crew": crew_assigned, "unassign_crew": crew_released}
	if _crowd(f):
		# Crowd: a released crew member leaves its slot through the native release step; the hull is free after it lands.
		for point: int in 300:
			if vehicle.crew_slots.is_empty() and vehicle.action.is_empty(): break
			_crowd_point(f)
	_require(Runtime.damage_siege_vehicle(f.data, key, 1.0).ok and Runtime.request_siege_repair(f.data, key, int(f.team.team_id)).ok, "Original basic repair command pays existing terms without manufacturing gate")
	var slot: Dictionary = Runtime.siege_work_slots(f.data, vehicle)[0]
	_land_committed_step(f, unlearned)
	_land_committed_step(f, int(f.commander))
	_place(f, unlearned, f.data.cell_from_index(int(slot.cell)))
	_park(f, int(f.commander), crew_cell + Vector2i(-4, 0))
	var work: SiteWorkTeam = f.lab.site_controller.work_team
	var unit_index: int = f.team.index_for_identity(unlearned)
	var occupied := func(cell: Vector2i) -> bool: return work._occupied(cell, f.team, unit_index)
	var selected: Dictionary = work._choose_vehicle_task(f.team, _cell_of(f, f.team.combat_identity(unit_index)), occupied, work.reserved_targets())
	_require(selected.ok and selected.target == "vehicle:" + key and selected.action == "repair" and int(selected.cell) == int(slot.cell), "Original basic selector actually selects this true repair/station before any work", selected)
	var repair_workers: Array[int] = [unlearned]
	var repair_assigned: Dictionary = work.assign(f.team, repair_workers, int(f.commander))
	_case["basic_siege_" + key]["repair_assign"] = repair_assigned
	_require(repair_assigned.ok, "Original basic repair dispatch retains old owner path", repair_assigned)
	for tick: int in 100:
		if vehicle.repair.is_empty(): break
		_interval(f)
	_require(vehicle.repair.is_empty() and float(vehicle.hp) == float(Runtime.SIEGE_DEFINITIONS[vehicle.kind].max_hp), "True unlearned original worker completes ordinary basic repair",
		{"repair": vehicle.repair, "hp": vehicle.hp, "kind": vehicle.kind, "max": Runtime.SIEGE_DEFINITIONS[vehicle.kind].max_hp, "same": is_same(vehicle, f.data.site.vehicles.get(key)), "live": f.data.site.vehicles.get(key, {}).get("hp"), "live_repair": f.data.site.vehicles.get(key, {}).get("repair"), "task": f.team._cold_get(f.team.index_for_identity(unlearned), "work_task", {}) if _crowd(f) else {}, "cell": str(_cell_of(f, unlearned))})
	_idle_all(f)

func _no_reissue(f: Dictionary) -> void:
	_idle_all(f)
	var receipt: PackedByteArray = var_to_bytes(f.data.site.get("technology_artisans", {}))
	var next_item := int(f.data.site.next_item)
	var next_person := int(f.data.site.next_person_id)
	var skills := {}
	for row: Dictionary in _team_rows(f.team): skills[int(row.person_id)] = row.get("technology", {}).duplicate(true)
	for identity: int in [1, int(f.master), int(f.helper), int(f.commander)]:
		_require(f.lab.site_controller._control_family_person(null, identity).ok, "Original same-Site control switch")
		_require(var_to_bytes(f.data.site.get("technology_artisans", {})) == receipt and int(f.data.site.next_item) == next_item and int(f.data.site.next_person_id) == next_person, "Control switch issues no birth or free items")
		for row: Dictionary in _team_rows(f.team): _require(row.get("technology", {}) == skills[int(row.person_id)], "Control switch cannot teach a faction member")
	_land_committed_step(f, int(f.helper))
	_require(f.lab.site_controller._control_family_person(null, int(f.helper)).ok, "Original member controls their own roster consent")
	var member_index: int = f.team.index_for_identity(int(f.helper))
	var membership_before: Dictionary = {"identity": int(f.helper), "controlled": f.lab.controlled_person_id(),
		"member": f.team.is_member(member_index), "moving_to": str(f.team.moving_to[member_index]),
		"pose": f.team.combat_hot_get(member_index, &"pose"), "hp": f.team.combat_hot_get(member_index, &"hp"),
		"ko": f.team.combat_hot_get(member_index, &"ko"), "attack": f.team.combat_hot_get(member_index, &"attack"),
		"work_task": (f.team._cold_get(member_index, "work_task", {}) if _crowd(f) else f.team.combat_units[member_index].get("work_task", {})).duplicate(true),
		"garrison": "" if _crowd(f) else f.team.garrison_feature_id, "paused": f.data.site.paused}
	var left: Dictionary = f.lab.leave_player_army()
	var joined: Dictionary = f.lab.join_player_army() if left.ok else {}
	var membership_result: Dictionary = {"before": membership_before, "leave": left, "join": joined, "join_called": left.ok}
	_case["membership_" + str(f.kind)] = membership_result
	_require(left.ok and joined.ok, "Actual existing NPC leaves/joins same original faction roster", membership_result)
	_require(var_to_bytes(f.data.site.get("technology_artisans", {})) == receipt and int(f.data.site.next_item) == next_item and int(f.data.site.next_person_id) == next_person, "Actual membership join issues no skills/items/people")
	_require(f.lab.site_controller._control_family_person(null, 1).ok, "Actual original Actor controls explicit army expansion")
	var expansion_before: PackedByteArray = var_to_bytes([f.data.site, _combat_state(f), f.lab.character.capture_state()])
	var expanded: Dictionary = f.lab.join_player_army()
	if expanded.ok:
		_require(f.lab.character.technology.is_empty() and f.team.player_member == f.lab.character and int(f.data.site.next_person_id) == next_person and int(f.data.site.next_item) == next_item, "Real roster expansion preserves Actor and gives no background skills/products")
		_require(f.lab.leave_player_army().ok, "Original Actor leaves original expanded army")
	else:
		# Crowd: an Actor joining a native crowd army is not supported yet (S4); it is refused atomically like MIXED_TROOP.
		var crowd_unsupported: bool = _crowd(f) and expanded.code == "UNSUPPORTED"
		_require((expanded.code == "MIXED_TROOP" or crowd_unsupported) and var_to_bytes([f.data.site, _combat_state(f), f.lab.character.capture_state()]) == expansion_before, "Original troop equipment may refuse Actor expansion atomically; never fake gear to force positive", expanded)
		_case["actor_expansion_" + str(f.kind)] = "MIXED_TROOP refusal; positive roster expansion NOT_VERIFIED"
	_require(f.lab.site_controller._control_family_person(null, int(f.commander)).ok, "Original command control restored")
	var before := var_to_bytes([f.data.site, _combat_state(f)])
	var replay: Dictionary = f.lab.prepare_initial_artisan_birth(f.data, Artisans.PRIMARY, Artisans.CATEGORIES)
	if f.kind == "fixed_birth":
		_require(replay.ok and not replay.changed and var_to_bytes([f.data.site, _combat_state(f)]) == before, "Actual historical birth cannot replay under later all-category release")
	else:
		_require(not replay.ok and var_to_bytes([f.data.site, _combat_state(f)]) == before, "Generated restored input has no original first-world birth authority and cannot regrant")
	_cold_resume(f, "no_reissue")
	if f.kind == "fixed_birth":
		_completed_open_refuses(f)

func _completed_open_refuses(f: Dictionary) -> void:
	var manifest_sha: String = FileAccess.get_sha256(f.slot.folder.path_join("manifest.json"))
	# A repeat under another policy is refused by the recorded policy itself.
	f.lab.site_controller._initial_world_candidate = null
	var other: Dictionary = f.lab.site_controller.open_fixed_world(manifest_path, str(f.world), SLOT, START, true, Artisans.PRIMARY)
	_require(not other.ok and other.code == "SAVE_VERSION" and FileAccess.get_sha256(f.slot.folder.path_join("manifest.json")) == manifest_sha, "A repeat under a different technology policy is refused without touching the slot", other)
	# The same recorded policy reaches the completed-slot reissue guard.
	# f.slot may be the reopened plain slot by now; read the policy the slot recorded.
	var recorded: Variant = JSON.parse_string(FileAccess.get_file_as_string(f.slot.folder.path_join("manifest.json")))
	_require(recorded is Dictionary and recorded.get("technology_policy") is Dictionary, "The completed slot records its own technology policy", recorded)
	var same := CandidatePolicySlot.new()
	same.candidate_categories = recorded.technology_policy.get("categories", []).duplicate()
	same.folder = f.slot.folder
	f.lab.site_controller._initial_world_candidate = same
	var repeated: Dictionary = f.lab.site_controller.open_fixed_world(manifest_path, str(f.world), SLOT, START, true, Artisans.PRIMARY)
	_require(not repeated.ok and repeated.code == "CONFLICT" and FileAccess.get_sha256(f.slot.folder.path_join("manifest.json")) == manifest_sha, "Actual completed newworld transaction cannot overwrite/reissue", repeated)
	f.lab.site_controller._initial_world_candidate = null

func _run() -> void:
	var category := _g06_category()
	_require(category in Artisans.CATEGORIES, "Named single-class engineering test")
	_case = {"category": category, "hypothetical_fixed_policy": [category], "formal_release": false, "full_G06_open": true}
	var source := _g06_source()
	_require(source != null, "Original checksummed synthetic geographic source")
	var fixed := _birth(source, category)
	_case.fixed_world = fixed.world
	_fixed_policy_guard(fixed)
	_no_reissue(fixed)
	var f := _generated_production(fixed)
	_case.merge({"generated_seed": f.generated_seed,
		"generated_policy": [], "original_cold_person_input_path": f.source_body_path, "original_cold_person_input_sha256": f.source_body_sha256,
		"evidence_groups_are_distinct": true, "world_transfer_continuity_excluded": true, "navigation_and_native_excluded": true, "formal_release": false,
		"full_G06_open": true, "fixed_product_construction_not_verified": true, "D10_master_gated_work_interruption_not_verified": true}, true)
	if category in ["F04", "F06"]: _processing(f)
	else: await _siege(f)
	_no_reissue(f)
	_case.checked_intervals = _work_intervals
	_case.actual_participant_seconds = _work_actual
	_case.effective_work_seconds = _work_effective
	report[category] = _case
	_finish()

func _finish(reason: String = "") -> void:
	if finished: return
	finished = true
	if not reason.is_empty(): failures.append(reason)
	for lab: TerrainLab in labs:
		if is_instance_valid(lab): lab.free()
	TerrainArmy.release_contact_source()
	print("TECH_AI_02_G06_REPORT: " + JSON.stringify({"checks": checks, "failures": failures, "cases": report, "fixed_fixture": root_path,
		"source_epochs": {"lab": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_lab.gd"), "slot": FileAccess.get_sha256("res://scripts/region_lab/region_save_slot.gd"),
		"controller": FileAccess.get_sha256("res://scripts/terrain_lab/site_controller.gd"), "runtime": FileAccess.get_sha256("res://scripts/terrain_lab/site_runtime.gd"),
		"work_team": FileAccess.get_sha256("res://scripts/terrain_lab/site_work_team.gd"), "actions": FileAccess.get_sha256("res://scripts/terrain_lab/site_person_actions.gd"),
		"store": FileAccess.get_sha256("res://scripts/terrain_lab/site_store.gd"), "catalog": FileAccess.get_sha256("res://scripts/terrain_lab/site_technology_catalog.gd")}}, "", true, true))
	print("TECH_AI_02_ENGINEERING_SUBSET_", _g06_category(), "_", "PASS" if failures.is_empty() else "FAILED", " scope=separate_fixed_birth_Store_and_generated_original_full_cost_products; hypothetical_fixed_release_only; FULL_G06_D10_fixed_productive_work_and_master_interruption_OPEN; Native_Taiwan_GPU_performance_autonomous_AI_full40_excluded")
	quit(0 if failures.is_empty() else 1)


## Since 11/03 the player's start team stands in the field too; a building may not
## be laid over any person or formation slot, as the original work selector checks.
func _artisan_cells_hold_person(f: Dictionary, cells: Array[int]) -> bool:
	var footprint := {}
	for cell: int in cells: footprint[cell] = true
	for army: TerrainArmy in f.lab.combat_armies:
		if not army.has_army(): continue
		for index: int in army.cells.size():
			if army.is_member(index) and footprint.has(f.data.index(army.cells[index])): return true
		if army.combat_enabled:
			for cell: int in cells:
				if army.reserves_terrain_cell(f.data.cell_from_index(cell)): return true # Formation slots, as the selector checks.
	for actor: TerrainTestCharacter in f.lab.combat_actors:
		if f.lab.actor_present(actor) and footprint.has(f.data.index(actor.terrain_cell)): return true
	return false

# Grid team snapshot, or the native crowd snapshot when the holder is a CrowdPersonOwner (no grid combat state there).
func _combat_state(f: Dictionary) -> Variant:
	if f.team is TerrainArmy: return f.team.capture_combat_state()
	# A refused capture would make every before/after comparison pass on two equal refusals, so it must succeed.
	var captured: Dictionary = f.lab.crowd_site.capture_save(true)
	_require(captured.ok, "Crowd team snapshot for an unchanged-state comparison", captured)
	return captured
