extends SceneTree
const Codec = preload("res://scripts/terrain_lab/site_region_owner_snapshot.gd")
const Checkpoint = preload("res://scripts/terrain_lab/site_region_checkpoint.gd")
const Clock = preload("res://scripts/region_lab/region_gameplay_clock.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
var checks := 0
var failed := false

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("REGION_GAMEPLAY_SNAPSHOT_FAIL: " + message)

func context(pending: bool = false) -> Dictionary:
	return {"purpose": "region_barrier" if pending else "region_checkpoint", "mode": "live", "source_generation": 3,
		"runtime_revision": 4, "token": "snapshot:3:4", "game_seconds": 120.0, "action_seconds": 2.0,
		"fire_epoch": "fire:3", "fire_sequence": 0, "interval_complete": true, "effects_complete": not pending,
		"mode_revision": 6, "backend": "gd", "events": [{"id": "arrival:1", "kind": "player_arrival", "at": 120.0,
		"sequence": 1, "player": true, "owner": "player", "status": "pending", "payload": {}}] if pending else [], "endpoint_payload": {}}

func callback() -> bool:
	return true

func _initialize() -> void:
	var body := {"person_id": 17, "hp": 85.0, "item_state": {"version": 5}, "cargo": {"grain": 4}}
	var owner := Node.new()
	var original_site := {"id": "site:A", "inventory": {"grain": 19}, "features": {"f:1": {"job": {"progress": 1.0}}}}
	var references := {"person:17:owner": owner, "callback:occupied": callback}
	Codec.register_tree(references, "site", original_site)
	check(Codec.register_person(references, 17, {"person_id": 17, "owner": owner, "body": body, "holder": body.item_state, "cargo": body.cargo}).ok, "Original person reference registration")
	var job := {"executor_owner": owner, "executor_body": body, "depot_holder": original_site.inventory,
		"cargo": body.cargo, "elapsed": 0.625, "occupied": callback, "cell": Vector2i(4, 7), "hits": {17: true}, "no_callback": Callable()}
	var roots := {"jobs": {"17": job}, "boundary": {"job": job}, "projectiles": [{"position": Vector2(4.5, 7.25), "elapsed": 0.25, "bounds": Rect2(1.25, 2.5, 3.0, 4.0)}], "packed": PackedVector3Array([Vector3(1, 2, 3)])}
	var captured := Codec.capture(roots, references, context())
	check(captured.ok, "Durable capture accepts registered original Node/holder/cargo/Callable references")
	if not captured.ok:
		owner.free()
		quit(1)
		return
	var encoded: Variant = JSON.parse_string(JSON.stringify(captured.state))
	check(encoded is Dictionary, "Wire payload survives actual JSON boundary")
	var restored := Codec.prepare_restore(encoded, references, {"source_generation": 3, "runtime_revision": 4, "token": "snapshot:3:4"})
	check(restored.ok and restored.owners_prepared, "Full graph preflight before original-owner assignment")
	if restored.ok:
		var again: Dictionary = restored.roots.jobs["17"]
		check(again.executor_owner == owner, "Node reference restores the actual original owner")
		check(is_same(again.executor_body, body), "Body remains the actual original dictionary")
		check(is_same(again.cargo, body.cargo), "Cargo is never an inventory copy")
		check(is_same(again.depot_holder, original_site.inventory), "Site stock points at the original holder")
		check(is_same(again, restored.roots.boundary.job), "Shared job aliases survive JSON persistence")
		check(again.occupied == callback and again.occupied.call(), "Original occupied callback restores by stable key")
		check(again.no_callback is Callable and again.no_callback.is_null(), "Legal empty callback retains its absence without a live reference")
		check(again.cell is Vector2i and again.cell == Vector2i(4, 7), "Vector cell type and value survive")
		check(restored.roots.projectiles[0].position == Vector2(4.5, 7.25), "In-flight subcell position survives")
		check(restored.roots.projectiles[0].bounds == Rect2(1.25, 2.5, 3.0, 4.0), "Original projectile geometry survives without stringification")
		check(restored.roots.packed is PackedVector3Array, "Packed vector representation survives")
		check(again.hits.has(17) and not again.hits.has("17"), "Integer hit ledger keys survive")
		check(absf(float(again.elapsed) - 0.625) < 0.000000001, "Action progress is neither reset nor rounded")
	check(original_site.inventory.grain == 19 and body.cargo.grain == 4, "Capture/prepare did not consume stock")
	check(not Codec.prepare_restore(encoded, references, {"source_generation": 4}).ok, "Changed source generation rejects before mutation")
	check(not Codec.prepare_restore(encoded, references, {"runtime_revision": 5}).ok, "Changed runtime revision rejects before mutation")
	check(not Codec.prepare_restore(encoded, references, {"token": "foreign"}).ok, "Foreign permit rejects before mutation")
	var missing := references.duplicate()
	missing.erase("person:17:owner")
	check(not Codec.prepare_restore(encoded, missing).ok, "Missing original Node reference rejects full prepare")
	var unbound := Node.new()
	check(not Codec.capture({"owner": unbound}, {}, context()).ok, "An unregistered object cannot become a surrogate")
	unbound.free()
	var pending := Codec.capture(roots, references, context(true))
	check(pending.ok, "A complete interval with pending effects is a durable positive barrier")
	var waiting := Codec.prepare_restore(pending.state, references)
	check(waiting.ok and waiting.effects_pending and waiting.zero_world_only, "Pending effects allow restore and retain zero-world-only fence")
	var partial := context()
	partial.interval_complete = false
	check(not Codec.capture(roots, references, partial).ok, "Partial interval is never accepted as completed")
	var consumed := Clock.empty_registry()
	Clock.queue_event(consumed, "arrival:1", "player_arrival", 120.0, "player", {}, true)
	check(Clock.complete_event(consumed, "arrival:1", 120.0).ok and Clock.complete_event(consumed, "arrival:1", 120.0).duplicate, "Original endpoint receipt is consumed exactly once")
	var tampered: Dictionary = encoded.duplicate(true)
	tampered.root.index = 999999
	check(not Codec.prepare_restore(tampered, references).ok, "Invalid graph references reject atomically")
	var typed := references.duplicate()
	typed["person:17:owner"] = {}
	check(not Codec.prepare_restore(encoded, typed).ok, "Changed original reference type rejects")
	var original_pending := context(true)
	var json_pending: Dictionary = JSON.parse_string(JSON.stringify(original_pending))
	check(Checkpoint.validate_context(json_pending, original_pending).ok and Checkpoint.validate_context(original_pending, json_pending).ok,
		"Complete pending event context survives JSON integer-to-float normalization in both directions")
	var changed_pending := json_pending.duplicate(true)
	changed_pending.events[0].sequence = 2.0
	check(not Checkpoint.validate_context(original_pending, changed_pending).ok, "Changed persisted event sequence still rejects before owner preparation")
	changed_pending = json_pending.duplicate(true)
	changed_pending.events[0].id = "arrival:foreign"
	check(not Checkpoint.validate_context(original_pending, changed_pending).ok, "Changed persisted event identity remains stale")
	var metadata := Checkpoint.make({"id": "site:A", "minute": 2}, context(true), pending.state)
	check(metadata.ok and Checkpoint.validate({"id": "site:A", "minute": 2.0}, metadata.snapshot).ok, "Owner graph composes with original Site payload metadata")
	var life := {"kind": "supply_damage", "person_id": 17, "at": 120.0, "sequence": 1, "status": "pending", "controlled": true, "death": false, "old_hp": 85.0, "ending_hp": 84.5, "loss": 0.5}
	var life_state := {"controlled_person_id": 17, "simulation_settlement": {"version": 1, "last_settled_game_seconds": 120.0}, "region_life_events": [life]}
	check(Store._validate_region_life_events(life_state, {17: body}).ok, "Original accepted travel life endpoint validates without applying HP")
	check(body.hp == 85.0, "Life event admission never recalculates or applies damage")
	var bad_life := life_state.duplicate(true)
	bad_life.region_life_events[0].at = 121.0
	check(not Store._validate_region_life_events(bad_life, {17: body}).ok, "Future life event cannot borrow settled watermark")
	bad_life = life_state.duplicate(true)
	bad_life.region_life_events[0].person_id = 99
	check(not Store._validate_region_life_events(bad_life, {17: body}).ok, "Unknown original life owner is rejected")
	bad_life = life_state.duplicate(true)
	bad_life.region_life_events[0].ending_hp = 0.0
	check(not Store._validate_region_life_events(bad_life, {17: body}).ok, "Life damage ending HP must follow the accepted loss")
	bad_life = life_state.duplicate(true)
	bad_life.region_life_events[0].controlled = false
	check(not Store._validate_region_life_events(bad_life, {17: body}).ok, "Controlled death classification uses actual control reference")
	body.hp = 84.0
	check(not Store._validate_region_life_events(life_state, {17: body}).ok, "Changed live HP invalidates stale pending damage")
	body.hp = 85.0
	var wake_body := {"hp": 85.0, "knockout_left": 0.0, "pose": "unconscious"}
	var wake_state := {"controlled_person_id": 17, "simulation_settlement": {"version": 1, "last_settled_game_seconds": 120.0}, "region_life_events": [{"kind": "wake", "person_id": 17, "at": 120.0, "sequence": 1, "status": "pending", "controlled": true}]}
	check(Store._validate_region_life_events(wake_state, {17: wake_body}).ok, "Original KO timer endpoint permits original unconscious wake transition")
	wake_body.hp = 0.0
	check(not Store._validate_region_life_events(wake_state, {17: wake_body}).ok, "Wake event cannot revive a dead original person")
	var capture_due := {"settlement": {"fall_record": {"contest_seconds": 60.0}}}
	check(Store._region_capture_completion_guard(capture_due).code == "BUSY", "Ordinary save waits for inclusive original capture completion")
	check(Store._region_capture_completion_guard(capture_due, context(true)).ok, "Pending barrier retains original capture completion record")
	check(not Store._region_capture_completion_guard(capture_due, context()).ok, "Completed effects cannot borrow unconsumed original capture")
	capture_due.settlement.fall_record.contest_seconds = 59.999
	check(Store._region_capture_completion_guard(capture_due).ok, "Capture progress before the inclusive endpoint retains ordinary admission")
	var pinned_data := TerrainData.new()
	var world_pin := {"format": 1, "world_instance_id": "world_1", "slot_id": "slot_1", "atlas_id": "TW",
		"grid_contract_version": 1, "base_revision": "rev_1", "manifest_sha256": "a".repeat(64), "ramp_rule_revision": "ramp_1"}
	pinned_data.parameters = {"fixed_base": {"base_kind": "fixed_geography", "site_id": "site:A", "atlas_id": "TW",
		"grid_contract_version": 1, "base_revision": "rev_1", "manifest_sha256": "a".repeat(64), "ramp_rule_revision": "ramp_1"}}
	var pinned_state := {"id": "site:A", "world_pin": world_pin.duplicate(true)}
	var admitted_pin := Store._validate_world_pin(pinned_data, pinned_state)
	check(admitted_pin.ok and admitted_pin.legacy and admitted_pin.policy.categories.is_empty(), "Legacy absent world policy projects empty categories without altering terrain base")
	check(not pinned_data.parameters.fixed_base.has("technology_policy"), "Policy remains outside original terrain base")
	pinned_state.world_pin.format = 2
	check(not Store._validate_world_pin(pinned_data, pinned_state).ok, "New world pin rejects absent required policy")
	pinned_state.world_pin.technology_policy = {"version": 1, "rules_version": 1, "categories": ["F12"]}
	check(Store._validate_world_pin(pinned_data, pinned_state).ok, "New world pin admits original validated explicit policy")
	pinned_state.world_pin.technology_policy = null
	check(not Store._validate_world_pin(pinned_data, pinned_state).ok, "Present malformed policy never becomes legacy absence")
	pinned_state.world_pin = world_pin.duplicate(true)
	pinned_state.world_pin.atlas_id = "foreign"
	check(not Store._validate_world_pin(pinned_data, pinned_state).ok, "Foreign geography pin rejects before owner restore")
	pinned_state.world_pin = world_pin.duplicate(true)
	pinned_state.world_pin.resource_layer_sha256 = "b".repeat(64)
	check(not Store._validate_world_pin(pinned_data, pinned_state).ok, "Incomplete resource pin rejects rather than broadening original geography")
	owner.free()
	print("REGION_GAMEPLAY_SNAPSHOT_", "FAILED" if failed else "PASS", " checks=", checks)
	quit(1 if failed else 0)