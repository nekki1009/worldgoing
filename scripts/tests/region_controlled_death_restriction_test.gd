extends SceneTree
## Actual original PackedScene / Slot / Store / Family controlled-death proof.
## Pure Travel mapping supplies only a valid accepted endpoint fixture; this is
## not a complete travel-arrival test. No consumer, owner receipt or timer stub.
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Grid = preload("res://scripts/region_lab/region_grid.gd")
const Entry = preload("res://scripts/region_lab/region_entry.gd")
const Travel = preload("res://scripts/region_lab/region_travel.gd")
const Crowd = preload("res://scripts/terrain_lab/crowd_site.gd")
const EPS := 0.000001

func _original_down_seconds() -> float:
	return float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"])

var out := ""
var manifest_path := ""
var world_id := ""
var lab: TerrainLab
var controller: SiteController
var slot: RegionSaveSlot
var cold: TerrainLab
var owner_id := ""
var cold_id := ""
var event_id := ""
var original_actor: TerrainTestCharacter
var original_data: TerrainData
var original_items: Array = []
var original_cargo: Dictionary = {}
var original_holder_version := 0
var original_next_loot := 0
var accepted_effect: Dictionary = {}
var accepted_at := 0.0
var total_action := 0.0
var total_game := 0.0
var checks := 0
var failed := false
var finished := false
var deadline := 0
var last_world_exists := false
var last_world_bytes := PackedByteArray()
var report: Dictionary = {}

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 180000
	out = "res://.godot-temp/region_controlled_death_restriction/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	last_world_exists = FileAccess.file_exists(Entry.LAST_WORLD)
	if last_world_exists: last_world_bytes = FileAccess.get_file_as_bytes(Entry.LAST_WORLD)
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_msec() > deadline: _finish(false, "180-second actual owner deadline")
	return false

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if not condition:
		failed = true
		push_error("REGION_CONTROLLED_DEATH_RESTRICTION_FAIL: " + message + " " + str(detail))
	return condition

func _freeze(scene: TerrainLab) -> void:
	scene.set_process(false)
	scene.set_process_input(false)
	scene.set_process_unhandled_input(false)
	scene.site_controller.set_process(false)
	scene.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in scene.combat_actors: actor.set_process(false)
	for team: TerrainArmy in scene.combat_armies: team.set_process(false)

func _asset(name: String, bytes: PackedByteArray) -> Dictionary:
	var path := out.path_join(name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	return {"path": name, "sha256": FileAccess.get_sha256(path)}

## Original region_travel_test checksummed 9x6 pinned synthetic map.
func _write_manifest() -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var summary := PackedByteArray()
	summary.resize(9 * 6)
	summary.fill(2)
	var summary_record := _asset("summary.u8", summary)
	summary_record.merge({"size": [9, 6], "site_origin": [-2, -2], "encoding": "u8", "row_order": "north_to_south", "nodata": 0})
	var width := 90
	var height := 60
	var elevation := PackedByteArray()
	var levels := PackedByteArray()
	var water := PackedByteArray()
	elevation.resize(width * height * 2)
	levels.resize(width * height)
	water.resize(width * height)
	for y in range(height):
		var north := -400 + (height - 1 - y) * 20 + 10
		for x in range(width):
			var east := -400 + x * 20 + 10
			var index := y * width + x
			var sea := east >= 400 and east < 440 and north < 400
			elevation.encode_s16(index * 2, -32767 if sea else 40)
			levels[index] = 0 if sea else 2
			water[index] = 2 if sea else 0
	var height_record := _asset("travel.height.zlib", elevation.compress(FileAccess.COMPRESSION_DEFLATE))
	var level_record := _asset("travel.levels.zlib", levels.compress(FileAccess.COMPRESSION_DEFLATE))
	var water_record := _asset("travel.water.zlib", water.compress(FileAccess.COMPRESSION_DEFLATE))
	height_record.merge({"id": "travel_plain", "origin": [-400, -400], "size": [width, height], "spacing_m": 20,
		"encoding": "int16_le_zlib", "row_order": "north_to_south", "nodata": -32767,
		"derived": {"encoding": "u8_zlib", "levels_path": level_record.path, "levels_sha256": level_record.sha256,
			"water_path": water_record.path, "water_sha256": water_record.sha256}})
	var manifest := {"format": 1, "synthetic_fixture": true, "atlas_id": Grid.ATLAS_ID, "grid_contract_version": 1,
		"base_revision": "region-travel-r1-fixture-v1", "crs": "EPSG:3826",
		"grid": {"origin": [0, 0], "cell_m": 2, "site_cells": 100, "region_sites": 100},
		"summary": summary_record, "elevation_tiles": [height_record], "sources": [{"title": "Synthetic Region travel fixture only"}]}
	manifest_path = out.path_join("manifest.json")
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "", true, true))
	file.close()
	var source := RegionData.new()
	return _check(source.load_manifest(manifest_path).ok, "Original checksummed pinned manifest loads")

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _write_manifest(): _finish(); return
	var packed := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	if not _check(packed != null, "Original formal scene exists"): _finish(); return
	lab = packed.instantiate() as TerrainLab
	if not _check(lab != null, "Original formal Lab exists"): _finish(); return
	# Actual restore shell suppresses automatic old-save IO; its original ready
	# creates every owner. A genuine old body then goes through the normal archive.
	lab.restore_only = true
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	lab.visible = false
	root.add_child(lab)
	controller = lab.site_controller
	_freeze(lab)
	var bootstrap := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345, {"size": Vector2i(32, 32)})
	Env.initialize(bootstrap, "controlled-death:archive")
	lab.bind_terrain(bootstrap)
	lab.restore_only = false
	controller.save_root = out.path_join("archive")
	world_id = "r0_down_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened: Dictionary = controller.open_fixed_world(manifest_path, world_id, "main", Vector2i.ZERO, true)
	if not _check(opened.ok, "Original Controller publishes and live-binds a pinned first world", opened): _finish(); return
	_freeze(lab)
	slot = controller.region_slot
	if not _check(slot != null and slot.has_method("_region_player_down_settlement"), "Actual private death proof API exists; missing integration is a failure"): _finish(); return
	var wired: Dictionary = lab._wire_region_gameplay_adapters(slot)
	if not _check(wired.ok, "Original same-Slot gameplay adapters wire", wired): _finish(); return
	owner_id = str(lab.terrain.site.id)
	original_data = lab.terrain
	original_actor = lab.character
	if not _check(lab.controlled_person_id() == 1 and original_actor.hp > 0.0 and not original_actor.is_moving(), "One actual living stationary controlled body starts"): _finish(); return
	var live: Dictionary = lab.region_bind_receipt(original_data)
	if not _check(live.get("complete") == true and live.get("owners_restored") == true and str(live.get("backend")) == "gd", "Real private live bind has complete original owners", live): _finish(); return
	# The sole original cold factory creates and schedules the other cached body.
	cold_id = Grid.site_id(str(slot.pin.atlas_id), Vector2i(1, 0))
	var owner: Dictionary = lab._region_gameplay_owner_lab(cold_id, "cold_exact")
	if not _check(owner.get("ok") == true and owner.get("lab") is TerrainLab, "Actual cold_exact owner factory admits the other Site", owner): _finish(); return
	cold = owner.lab
	_freeze(cold)
	if not _aligned(lab) or not _aligned(cold): _finish(); return
	if not _setup_actual_death(): _finish(); return
	if not _negative_proofs(): _finish(); return
	if not _public_flags_cannot_bind(): _finish(); return
	if not _actual_positive_loop(): _finish(); return
	_finish()

func _event() -> Dictionary:
	for candidate: Dictionary in slot.region_registry().events:
		if str(candidate.id) == event_id: return candidate
	return {}

func _proof() -> Dictionary:
	var result: Variant = slot.call("_region_player_down_settlement")
	return result if result is Dictionary else {}

func _setup_actual_death() -> bool:
	var person: Dictionary = controller.person_actions._person(1)
	if not _check(not person.is_empty() and not person.holder.item_ids.is_empty(), "Original birth equipment supplies real owned item IDs"): return false
	original_items = person.holder.item_ids.duplicate()
	original_cargo = person.cargo.duplicate(true)
	original_holder_version = int(person.holder.version)
	original_next_loot = int(lab.terrain.site.next_loot)
	var captured: Dictionary = controller._capture_for_save()
	if not _check(captured.ok, "Original Controller captures its actual source body", captured): return false
	# A new world has no travel index until its first transfer. Register only
	# the original typed metadata through Travel's own allocator. The actual
	# source bodies, holders and item IDs remain the already-born live objects.
	var identified: Dictionary = Travel.prepare_identity(lab.terrain.site)
	if not _check(identified.ok and Travel.validate_identity(identified.state.get("travel_identity")), "Original Travel registers typed source identity metadata", identified): return false
	lab.terrain.site.travel_identity = identified.state.travel_identity
	var token := "controlled_death_%d" % Time.get_ticks_usec()
	var extracted: Dictionary = Travel.extract(lab.terrain.site, {"person_id": 1, "team_id": 0,
		"actor_key": "player", "controller": "player", "game_seconds": float(slot.control.logical_game_seconds),
		"namespace": str(lab.terrain.site.travel_identity.namespace)}, token)
	if not _check(extracted.ok, "Original pure Travel extracts a detached fixture closure", extracted): return false
	var arrival: Dictionary = Travel.prepare_arrival(extracted.origin, extracted.party, int(slot._marker.generation))
	if not _check(arrival.ok and Travel.validate_arrival_mapping(arrival.get("mapping"))
		and arrival.mapping.maps.person.values().has("1"), "Original injective mapped endpoint fixture preserves local controlled ID", arrival): return false
	accepted_at = float(slot.control.logical_game_seconds)
	event_id = "travel:" + token + ":life:1"
	var hp := original_actor.hp
	var payload := {"kind": "supply_damage", "sequence": 1, "person_id": 1, "old_hp": hp,
		"loss": hp, "ending_hp": 0.0, "controlled": true, "death": true, "at": accepted_at,
		"status": "pending", "destination_site": owner_id, "arrival_mapping": arrival.mapping}
	var queued: Dictionary = slot.queue_region_event(event_id, "player_death", accepted_at, "travel:" + token, payload, true)
	if not _check(queued.ok and not _event().payload.has("effect_receipt"), "Original Slot accepts a raw immutable mapped event without forged effects", queued): return false
	var actual_cold_data: TerrainData = cold.terrain
	var actual_cold_actor: TerrainTestCharacter = cold.character
	var actual_cold_holder: Dictionary = actual_cold_actor.item_state.duplicate(true)
	var actual_cold_records: Dictionary = cold.terrain.site.get("item_records", {}).duplicate(true)
	if not _check(cold.actor_present(actual_cold_actor) and not actual_cold_holder.get("item_ids", []).is_empty(),
		"Original cold factory has actual owned equipment before first joint save", actual_cold_holder): return false
	report.item_locations_before = _original_item_locations()
	var consumed: Dictionary = slot.consume_region_player_event(_event())
	report.item_locations_after = _original_item_locations()
	report.actual_player_consumer_result = consumed.duplicate(true)
	if not _check(consumed.ok and consumed.get("receipt", {}).get("complete") == false
		and consumed.get("receipt", {}).get("restricted_settlement") == true, "Actual player consumer applies death while original continuity stays pending", consumed): return false
	if not _cold_saved_original_holder("first_joint_save", actual_cold_data, actual_cold_actor, actual_cold_holder, actual_cold_records): return false
	var game_before := float(slot.control.logical_game_seconds)
	var action_before := float(slot.control.fire_clock.action_seconds)
	var sequence_before := int(slot.control.fire_clock.sequence)
	var generation_before := int(slot._marker.generation)
	var timer_before := float(controller._pending_deaths[1])
	# The real endpoint checkpoint performs a second joint save at the same P0.
	var second: Dictionary = lab._region_gameplay_endpoint_checkpoint(_event().payload)
	report.second_joint_checkpoint = second.duplicate(true)
	report.item_locations_second_save = _original_item_locations()
	if not _check(second.ok and int(slot._marker.generation) == generation_before + 1
		and float(slot.control.logical_game_seconds) == game_before
		and float(slot.control.fire_clock.action_seconds) == action_before
		and int(slot.control.fire_clock.sequence) == sequence_before
		and float(controller._pending_deaths[1]) == timer_before
		and lab.terrain == original_data and lab.character == original_actor,
		"Second real joint checkpoint publishes once without advancing original clocks or down timer", second): return false
	if not _cold_saved_original_holder("second_joint_save", actual_cold_data, actual_cold_actor, actual_cold_holder, actual_cold_records): return false
	accepted_effect = _event().payload.get("effect_receipt", {}).duplicate(true)
	report.original_death_contact = {"hp": original_actor.hp, "has_original_down_timer": controller._pending_deaths.has(1),
		"actual_down_seconds": controller._pending_deaths.get(1), "original_down_seconds": _original_down_seconds(),
		"accepted_game_seconds": accepted_at, "world_game_seconds": float(slot.control.logical_game_seconds),
		"world_action_seconds": float(slot.control.fire_clock.action_seconds), "effect_receipt": accepted_effect.duplicate(true)}
	if not _check(original_actor.hp == 0.0 and controller._pending_deaths.has(1)
		and absf(float(controller._pending_deaths[1]) - _original_down_seconds()) <= EPS and accepted_effect.size() == 5
		and accepted_effect.get("event_id") == event_id and accepted_effect.get("person_id") == 1
		and accepted_effect.get("effects_complete") == true
		and float(accepted_effect.get("game_seconds", -1.0)) == accepted_at
		and float(accepted_effect.get("action_seconds", -1.0)) == action_before, "Original contact/signal generates HP0, the original down duration and genuine five-field effect receipt", accepted_effect): return false
	if not _check(not _proof().is_empty() and not paused and not bool(lab.terrain.site.paused)
		and controller._family_dialog == null, "Actual original death qualifies before Family UI; public flags supply no proof", _proof()): return false
	return _owned_before_remains() and _selected_body(false)

func _facts() -> String:
	return JSON.stringify({"control": slot.control, "marker": slot._marker, "site": lab.terrain.site,
		"hp": original_actor.hp, "loot_settled": original_actor.loot_settled, "remains_id": original_actor.remains_id,
		"deaths": controller._pending_deaths, "action": lab.fire_action_cursor, "point": lab._region_point_pending,
		"bind": lab._region_bind_receipt_value, "paused": paused, "data_id": lab.terrain.get_instance_id(),
		"actor_id": lab.character.get_instance_id()}, "", true, true)

func _fault_dict(label: String, dictionary: Dictionary, key: Variant, value: Variant, erase: bool = false) -> bool:
	var before := _facts()
	var existed := dictionary.has(key)
	var original: Variant = dictionary.get(key)
	if erase: dictionary.erase(key)
	else: dictionary[key] = value
	var denied := _proof().is_empty()
	if existed: dictionary[key] = original
	else: dictionary.erase(key)
	return _check(denied and _facts() == before and not _proof().is_empty(), label + " rejects by source facts without consuming or mutating anything")

func _fault_object(label: String, object: Object, property: StringName, value: Variant) -> bool:
	var before := _facts()
	var original: Variant = object.get(property)
	object.set(property, value)
	var denied := _proof().is_empty()
	object.set(property, original)
	return _check(denied and _facts() == before and not _proof().is_empty(), label + " rejects and original owner recovers unchanged")

func _negative_proofs() -> bool:
	var mode: Dictionary = slot.region_registry().modes[owner_id]
	var activation: Dictionary = mode.activation
	var effect: Dictionary = _event().payload.effect_receipt
	var payload: Dictionary = _event().payload
	var mapping: Dictionary = payload.arrival_mapping
	var fire: Dictionary = lab.terrain.site.fire_settlement
	var settlement: Dictionary = lab.terrain.site[RegionSaveSlot.SETTLEMENT_FIELD]
	_fault_dict("Native mode", mode, "backend", "native")
	var actual_crowd := Crowd.new()
	actual_crowd.active = true
	_fault_object("Actual active native owner guard", lab, &"crowd_site", actual_crowd)
	actual_crowd.free()
	_fault_object("Restore-only original Lab", lab, &"restore_only", true)
	var foreign := RegionSaveSlot.new()
	_fault_object("Foreign Slot instance", controller, &"region_slot", foreign)
	_fault_object("Living original HP", original_actor, &"hp", 1.0)
	_fault_object("World pause", self, &"paused", true)
	_fault_dict("Site pause", lab.terrain.site, "paused", true)
	_fault_dict("Missing original down timer", controller._pending_deaths, 1, null, true)
	for bad: float in [-1.0, INF, _original_down_seconds() + 0.001, 0.0]: _fault_dict("Invalid/stationary expired down timer " + str(bad), controller._pending_deaths, 1, bad)
	_fault_object("Missing original bound body pointer", lab, &"_region_bound_data", null)
	_fault_dict("Incomplete private bind", lab._region_bind_receipt_value, "complete", false)
	_fault_dict("Unrestored original owners", lab._region_bind_receipt_value, "owners_restored", false)
	_fault_dict("Foreign bind owner", lab._region_bind_receipt_value, "owner", "foreign:0:0")
	_fault_dict("Changed actual marker generation", slot._marker, "generation", int(slot._marker.generation) + 1)
	_fault_dict("Stale mode generation", mode, "generation", int(mode.generation) + 1)
	_fault_dict("Stale activation generation", activation, "generation", int(activation.generation) + 1)
	_fault_dict("Wrong activation mode revision", activation, "mode_revision", int(activation.mode_revision) + 1)
	_fault_dict("Mode source game watermark", mode, "game_seconds", float(mode.game_seconds) + 0.1)
	_fault_dict("Mode source ACTION watermark", mode, "action_seconds", float(mode.action_seconds) + 0.1)
	_fault_dict("Foreign original consumer", mode, "consumer", "foreign")
	_fault_dict("Original settlement game watermark", settlement, "last_settled_game_seconds", float(slot.control.logical_game_seconds) + 0.1)
	_fault_dict("Original fire game watermark", fire, "game_seconds", float(fire.game_seconds) + 0.1)
	_fault_dict("Original fire ACTION watermark", fire, "action_seconds", float(fire.action_seconds) + 0.1)
	_fault_dict("Original fire sequence watermark", fire, "sequence", int(fire.sequence) + 1)
	_fault_dict("Original fire epoch", fire, "epoch", "foreign")
	_fault_object("Physical fire cursor", lab, &"fire_action_cursor", lab.fire_action_cursor + 0.1)
	_fault_object("Unconsumed original owner point", lab, &"_region_point_pending", {"interval_complete": false})
	_fault_dict("Foreign active Site", slot.control, "active_site_id", "foreign:0:0")
	_fault_dict("Missing original effect receipt", payload, "effect_receipt", null, true)
	_fault_dict("Unpaid original effects", effect, "effects_complete", false)
	_fault_dict("Foreign effect event ID", effect, "event_id", event_id + ":foreign")
	_fault_dict("Foreign effect person ID", effect, "person_id", 2)
	_fault_dict("Future effect ACTION", effect, "action_seconds", float(slot.control.fire_clock.action_seconds) + 1.0)
	_fault_dict("Wrong accepted effect game", effect, "game_seconds", accepted_at + 1.0)
	_fault_dict("Uncontrolled event", payload, "controlled", false)
	_fault_dict("Nondeath event", payload, "death", false)
	_fault_dict("Wrong mapped person", payload, "person_id", 2)
	_fault_dict("Foreign destination", payload, "destination_site", cold_id)
	_fault_dict("Foreign mapping token", mapping, "token", str(mapping.token) + ":foreign")
	_fault_dict("Malformed typed mapping", mapping, "maps", null, true)
	_fault_dict("Foreign mapping namespace", mapping, "destination_namespace", str(mapping.destination_namespace) + ":foreign")
	_fault_dict("Future mapping generation", mapping, "generation", int(slot._marker.generation) + 1)
	_fault_dict("Mapped person absent from values", mapping.maps, "person", {"1": "3"})
	return not failed

func _public_flags_cannot_bind() -> bool:
	var before := _facts()
	var captured: Dictionary = controller.capture_region_checkpoint("region_barrier", false, {"player_event": event_id})
	if not _check(captured.ok and captured.get("state") is Dictionary, "Original Store builds genuine pending body candidate", captured): return false
	var candidate: TerrainData = Env.navigation_for_state(lab.terrain, captured.state.duplicate(true))
	lab.bind_terrain(candidate, {"ok": true, "complete": true, "owners_restored": true,
		"effects_complete": true, "trusted": true, "region_bind_token": "forged"})
	return _check(lab.terrain == original_data and lab.character == original_actor and _facts() == before
		and not _proof().is_empty(), "Caller-forged public receipt cannot substitute for real private bind or replace HP0 body")

func _aligned(scene: TerrainLab) -> bool:
	var ordinary: Dictionary = slot.validate_settlement(scene.terrain.site, float(slot.control.logical_game_seconds))
	var checked: Dictionary = slot.validate_fire_settlement(scene.terrain.site, slot.control.fire_clock)
	var fire: Dictionary = scene.terrain.site.get("fire_settlement", {})
	var mode: Dictionary = slot.region_registry().modes.get(str(scene.terrain.site.id), {})
	return _check(ordinary.ok and not bool(ordinary.get("legacy", true)) and float(ordinary.get("pending", INF)) <= EPS
		and checked.ok and int(fire.get("sequence", -1)) == int(slot.control.fire_clock.sequence)
		and absf(float(fire.get("action_seconds", -1.0)) - float(slot.control.fire_clock.action_seconds)) <= EPS
		and absf(float(fire.get("game_seconds", -1.0)) - float(slot.control.logical_game_seconds)) <= EPS
		and absf(float(mode.get("game_seconds", -1.0)) - float(slot.control.logical_game_seconds)) <= EPS
		and absf(float(mode.get("action_seconds", -1.0)) - float(slot.control.fire_clock.action_seconds)) <= EPS,
		"Actual Site " + str(scene.terrain.site.id) + " completes at the one common original game/ACTION/sequence", {"ordinary": ordinary, "fire": fire, "mode": mode})

func _owned_before_remains() -> bool:
	var person: Dictionary = controller.person_actions._person(1)
	return _check(not person.is_empty() and person.holder.item_ids == original_items and person.cargo == original_cargo
		and int(person.holder.version) == original_holder_version and int(lab.terrain.site.next_loot) == original_next_loot
		and not original_actor.loot_settled and original_actor.remains_id.is_empty(), "Down interval retains original items/cargo/holder version without early remains")

func _selected_body(remains: bool) -> bool:
	var loaded: Dictionary = slot.open_site(Vector2i.ZERO)
	if not _check(loaded.ok and loaded.data.site.has("region_snapshot"), "Real Store reads exact selected full hot body", loaded): return false
	var saved: Dictionary = loaded.data.site
	var actor: Dictionary = saved.get("actors", {}).get("player", {})
	if not _check(float(actor.get("hp", -1.0)) == 0.0 and actor.get("loot_settled", false) == remains,
		"Selected durable actor preserves actual HP0 and original remains state", actor): return false
	if not remains: return true
	var identifier := str(actor.get("remains_id", ""))
	var holder: Dictionary = saved.get("ground_loot", {}).get(identifier, {})
	return _check(identifier == original_actor.remains_id and not identifier.is_empty()
		and holder.get("item_ids", []) == original_items and holder.get("cargo", {}) == original_cargo
		and int(saved.next_loot) == original_next_loot + 1, "Same selected durable marker contains the actual unique remains transaction before Family pause", holder)

func _actual_positive_loop() -> bool:
	var sequence_start := int(slot.control.fire_clock.sequence)
	var game_start := float(slot.control.logical_game_seconds)
	var action_start := float(slot.control.fire_clock.action_seconds)
	var steps := 0
	while controller._pending_deaths.has(1) and steps < 5000 and Time.get_ticks_msec() <= deadline:
		var remaining := float(controller._pending_deaths[1])
		var limit := TerrainLab.EXCHANGE_ACTION_STEP if lab.exchange_enabled else TerrainLab.ACTION_STEP
		var requested := minf(limit, remaining)
		if not _check(requested > 0.0, "Actual stationary pending timer supplies positive admitted ACTION"): return false
		var result: Dictionary = lab._advance_original_shared_step(requested)
		if not _check(result.get("ok") == true and result.get("completed") == true
			and float(result.get("action_seconds", 0.0)) > 0.0 and float(result.get("game_seconds", 0.0)) > 0.0,
			"True original main advances an admitted controlled-death prefix; rejection is never a positive PASS", result): return false
		steps += 1
		total_action += float(result.action_seconds)
		total_game += float(result.game_seconds)
		if not _check(float(result.action_seconds) <= requested + EPS and total_action <= _original_down_seconds() + EPS
			and absf(float(slot.control.fire_clock.action_seconds) - action_start - total_action) <= EPS
			and absf(float(slot.control.logical_game_seconds) - game_start - total_game) <= EPS
			and int(slot.control.fire_clock.sequence) == sequence_start + steps, "One main step publishes the one original World clock once", result): return false
		if not _check(lab.terrain == original_data and lab.character == original_actor and original_actor.hp == 0.0,
			"True shared step retains the same original HP0 body without rebind or rebirth"): return false
		if not _aligned(lab) or not _aligned(cold): return false
		if not _check(_event().status == "pending" and float(_event().at) == accepted_at
			and _event().payload.effect_receipt == accepted_effect, "Accepted P0 ID/time/status/effect receipt remain immutable while its body settles"): return false
		if controller._pending_deaths.has(1):
			if not _check(absf(float(controller._pending_deaths[1]) - maxf(0.0, _original_down_seconds() - total_action)) <= EPS
				and not paused and not bool(lab.terrain.site.paused), "Original down timer pays ACTION once and pause waits for real remains"): return false
			if not _owned_before_remains(): return false
	if not _check(not controller._pending_deaths.has(1) and absf(total_action - _original_down_seconds()) <= EPS,
		"Actual original authored down ACTION completes within bounded true main steps", {"steps": steps, "action": total_action}): return false
	var person: Dictionary = controller.person_actions._person(1)
	var identifier := original_actor.remains_id
	var remains: Dictionary = lab.terrain.site.ground_loot.get(identifier, {})
	var owned_remains := 0
	for container: Dictionary in lab.terrain.site.ground_loot.values():
		if str(container.get("kind")) == "remains" and int(container.get("original_owner", -1)) == 1: owned_remains += 1
	if not _check(original_actor.loot_settled and not identifier.is_empty() and owned_remains == 1
		and remains.get("item_ids", []) == original_items and remains.get("cargo", {}) == original_cargo
		and int(remains.get("version", -1)) == 1 and int(lab.terrain.site.next_loot) == original_next_loot + 1
		and person.holder.item_ids.is_empty() and person.cargo.is_empty()
		and int(person.holder.version) == original_holder_version + 1, "One original Runtime remains transaction transfers actual items/cargo with one holder-version payment", remains): return false
	for identity: String in original_items:
		if not _check(lab.terrain.site.item_records[identity].holder == remains.holder, "Actual item record points at its one remains holder " + identity): return false
	if not _check(is_instance_valid(controller._family_dialog) and str(controller._family_dialog.name) == "FamilyDialog"
		and paused and bool(lab.terrain.site.paused), "Actual original Family UI opens and pauses only after original remains settle"): return false
	if not _selected_body(true): return false
	var before := _facts()
	var blocked: Dictionary = lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
	if not _check(blocked.get("ok") == false and str(blocked.get("code")) in ["PAUSED_SITE", "PAUSED_WORLD"]
		and _facts() == before, "Genuine Family pause stops subsequent World/ACTION/body/holder changes", blocked): return false
	controller.settle_person_deaths(0.0)
	if not _check(_facts() == before, "Original zero-time death-settle retry cannot duplicate remains or holder transaction"): return false
	report.merge({"steps": steps, "action_seconds": total_action, "game_seconds": total_game,
		"same_world_publications": steps, "event_at": accepted_at, "event_pending": true,
		"original_item_count": original_items.size(), "same_original_body": true,
		"other_cached_site": cold_id, "durable_remains": identifier, "family_paused": true}, true)
	return true

func _finish(ok: bool = true, message: String = "") -> void:
	if finished: return
	finished = true
	failed = failed or not ok
	if not message.is_empty(): print(message)
	paused = false
	if is_instance_valid(lab): lab.free()
	var current: Variant = JSON.parse_string(FileAccess.get_file_as_string(Entry.LAST_WORLD)) if FileAccess.file_exists(Entry.LAST_WORLD) else null
	if current is Dictionary and current.get("world_id") == world_id:
		if last_world_exists:
			var file := FileAccess.open(Entry.LAST_WORLD, FileAccess.WRITE)
			file.store_buffer(last_world_bytes)
			file.close()
		else: DirAccess.remove_absolute(ProjectSettings.globalize_path(Entry.LAST_WORLD))
	TerrainArmy.release_contact_source()
	var evidence := {"checks": checks, "failed": failed, "report": report, "artifact_root": out,
		"scope": "actual_private_live_bind_mapped_death_original_2_2_shared_step_cold_same_endpoint_unique_durable_remains_family_pause"}
	var output := FileAccess.open(out.path_join("receipt.json"), FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(evidence, "\t", true, true))
		output.close()
	print("REGION_CONTROLLED_DEATH_RESTRICTION_", "FAILED" if failed else "PASS", " ", JSON.stringify(evidence))
	quit(1 if failed else 0)

## Read-only source evidence. Do not call capture, seed, settle or owner restore.
func _original_item_state_locations(state: Dictionary) -> Dictionary:
	var locations := {}
	var holders: Array[Dictionary] = [{"path": "depot_items", "holder": state.get("depot_items", {})}]
	for key: String in state.get("stockpiles", {}): holders.append({"path": "stockpiles." + key, "holder": state.stockpiles[key].get("holder", {})})
	for key: String in state.get("vehicles", {}): holders.append({"path": "vehicles." + key, "holder": state.vehicles[key].get("holder", {})})
	for key: String in state.get("ground_loot", {}): holders.append({"path": "ground_loot." + key, "holder": state.ground_loot[key]})
	for key: String in state.get("actors", {}): holders.append({"path": "actors." + key, "holder": state.actors[key].get("item_state", {})})
	for team: Dictionary in state.get("armies", []):
		for row: Dictionary in team.get("units", []): holders.append({"path": "armies.%d.person.%d" % [int(team.team_id), int(row.person_id)], "holder": row.get("item_state", {})})
	for holder: Dictionary in holders:
		for item: String in holder.holder.get("item_ids", []):
			if not locations.has(item): locations[item] = []
			locations[item].append({"path": holder.path, "holder": str(holder.holder.get("holder", ""))})
	var missing := {}
	var duplicates := {}
	for item: String in state.get("item_records", {}):
		if not locations.has(item): missing[item] = state.item_records[item].duplicate(true)
	for item: String in locations:
		if locations[item].size() != 1: duplicates[item] = locations[item].duplicate(true)
	return {"records_count": state.get("item_records", {}).size(), "locations_count": locations.size(),
		"locations": locations, "missing": missing, "duplicates": duplicates,
		"actor_presence_version": state.get("actor_presence_version", null),
		"saved_actor_keys": state.get("actors", {}).keys(), "snapshot": state.has("region_snapshot")}

func _original_item_locations() -> Dictionary:
	var originals: Array[TerrainLab] = [lab]
	if is_instance_valid(cold): originals.append(cold)
	var result := {"labs": {}, "cold_candidates": {}, "generation": int(slot._marker.generation),
		"world": float(slot.control.logical_game_seconds)}
	for original: TerrainLab in originals:
		var state: Dictionary = original.terrain.site
		var evidence: Dictionary = _original_item_state_locations(state)
		var live_actors := {}
		for actor: TerrainTestCharacter in [original.character, original.npc]:
			if not is_instance_valid(actor): continue
			live_actors["player" if actor == original.character else "npc"] = {"id": actor.person_id,
				"actual_present": original.actor_present(actor), "hp": actor.hp,
				"military_role": actor.military_role, "holder": actor.item_state.duplicate(true)}
		evidence.actual_actors = live_actors
		evidence.bound_original = original._region_bound_data == original.terrain
		evidence.data_instance_id = original.terrain.get_instance_id()
		evidence.lab_instance_id = original.get_instance_id()
		result.labs[str(state.id)] = evidence
	for identity: String in slot._fire_cold_candidates:
		var candidate: Dictionary = slot._fire_cold_candidates[identity]
		var data: TerrainData = candidate.get("data")
		if data == null: continue
		var evidence: Dictionary = _original_item_state_locations(data.site)
		evidence.data_instance_id = data.get_instance_id()
		evidence.is_same_actual_cold_data = is_instance_valid(cold) and cold.terrain == data
		var actual: TerrainLab = slot._region_bound_original_lab(data)
		evidence.original_capture_owner_found = is_instance_valid(actual)
		evidence.lab_instance_id = actual.get_instance_id() if is_instance_valid(actual) else 0
		result.cold_candidates[identity] = evidence
	return result

func _cold_saved_original_holder(label: String, actual_data: TerrainData, actual_actor: TerrainTestCharacter,
		expected_holder: Dictionary, expected_records: Dictionary) -> bool:
	var retained: Dictionary = slot._fire_cold_candidates.get(cold_id, {})
	if not _check(cold.terrain == actual_data and cold.character == actual_actor
		and cold.actor_present(actual_actor) and cold._region_bound_data == actual_data
		and slot._region_bound_original_lab(actual_data) == cold and retained.get("data") == actual_data
		and actual_actor.item_state == expected_holder and actual_data.site.item_records == expected_records,
		label + " retains the same original cold data, body and unique item holder", retained.get("data")): return false
	var reopened := RegionSaveSlot.new()
	var opened: Dictionary = reopened.open_map(slot.source, world_id, "main")
	if not _check(opened.ok and int(reopened._marker.generation) == int(slot._marker.generation),
		label + " reopens the actual same selected durable generation", opened): return false
	var loaded: Dictionary = reopened._load_checked(reopened.site_path(Vector2i(1, 0)), Vector2i(1, 0))
	if not _check(loaded.ok and loaded.data.site.has("region_snapshot"), label + " reads original full cold hot snapshot", loaded): return false
	var state: Dictionary = loaded.data.site
	var holder: Dictionary = state.get("actors", {}).get("player", {}).get("item_state", {})
	var locations: Dictionary = _original_item_state_locations(state)
	report[label] = {"generation": int(reopened._marker.generation), "original_data_instance_id": actual_data.get_instance_id(),
		"original_actor_instance_id": actual_actor.get_instance_id(), "durable_locations": locations,
		"actual_holder": actual_actor.item_state.duplicate(true), "durable_holder": holder.duplicate(true)}
	if not _check(holder == expected_holder and state.get("item_records", {}) == expected_records
		and locations.missing.is_empty() and locations.duplicates.is_empty()
		and int(locations.records_count) == int(locations.locations_count),
		label + " preserves every real cold item in exactly one durable actual holder after reopen", locations): return false
	for identity: String in expected_holder.item_ids:
		if not _check(locations.locations.has(identity) and locations.locations[identity].size() == 1
			and locations.locations[identity][0].path == "actors.player"
			and str(state.item_records[identity].holder) == str(expected_holder.holder),
			label + " durable exact item location " + identity, locations.locations.get(identity)): return false
	return true
