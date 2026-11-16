extends Node

signal events_received(events: PackedInt64Array)

# crowd10k C1: the native crowd (ArmyCrowd) inside the formal TerrainLab Site scene.
#
# Default Site army model since stage 1 (2026-11-02). Crowd is on unless the game is started with the user
# argument --grid, which keeps the retired TerrainArmy grid path for debugging. --crowd is still accepted as a no-op.
#
# C1 scope:
#  - Deploy: the Site's own trial-deployment UI (SiteController._deploy_trial_armies) and formation
#    search (TerrainLab._independent_trial_formations) decide teams, factions, troop types, training,
#    female share, AI switch and cells; the crowd builds one formation per team on those cells. Person IDs
#    come from the Site allocator. Uniforms: SiteController._initial_uniform (the game's own NPC dyes).
#  - Clock: TerrainLab's 30 Hz action step and the Site combat clock drive the crowd
#    (step_clock(elapsed, game_seconds, combat_left)); the crowd's combat marks go back to
#    SiteRuntime.mark_combat, so the Site clock stays the single time source.
#  - Player: TerrainLab's MovementTestCharacter is one crowd soldier (user decision 2026-09-30): WASD /
#    arrows = wish to walk, Shift = run, hold Space = fight whoever is in reach. The character only
#    presents him (position, pose and its clock, facing, HP / stun bars), as the game's exchange presenter.
#  - Drawing: the game's soldier atlas pages and shader through terrain_army_batch_view, one
#    MultiMeshInstance2D per crowd group, children of TerrainLab next to the character so the tree order
#    inside a z row is the crowd's draw order (see crowd10k_occlusion_bench.gd).
# C2/C3: native hot state, original Site records and item holders, transactional event/save boundaries.

const BatchView := preload("res://scripts/terrain_lab/terrain_army_batch_view.gd")
const PersonSocialPacket = preload("res://scripts/terrain_lab/person_social.gd") # 軍餉與稅收 P5: arrears morale
const SiegeWorkAppend := preload("res://scripts/terrain_lab/site_siege_work_append.gd")
const SiegeWorkClips = preload("res://scripts/terrain_lab/site_siege_work_clips.gd")
const Atlas := preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const ExchangeTimings := preload("res://scripts/terrain_lab/character_exchange_timings.gd")
const Site := preload("res://scripts/terrain_lab/site_controller.gd")
const PersonOwner := preload("res://scripts/terrain_lab/crowd_person_owner.gd")
const SiteSocial := preload("res://scripts/terrain_lab/site_social.gd")
const PoliticalAdoption := preload("res://scripts/terrain_lab/site_political_adoption.gd")
const ClearHandoff := preload("res://scripts/terrain_lab/crowd_clear_handoff.gd")
const WeaponMaterials := preload("res://scripts/ui/weapon_materials.gd")
const DLL_PATH := "res://native/crowd10k/bin/crowd10k.windows.x86_64.dll"
const SOLDIER_FIELDS := ["hp", "stun", "grace", "ko", "getup", "stagger", "captive", "bandaged", "ammo", "tactics", "leadership", "coach", "escape_t", "role", "px", "py", "face", "exch_cd", "ranged_cd", "skill_cd", "knock_t", "act_t", "vx", "vy", "state", "vis_kind", "vis_age"]
const FORMATION_FIELDS := ["morale", "rally_rest", "fatigue", "fatigue_rest", "training", "routed", "needs_attack_order", "commander_present", "fatigue_count", "order", "goal_x", "goal_y", "goal_facing", "pursuit_left", "origin_x", "origin_y", "ai_enabled", "cx", "cy", "facing", "no_orders", "order_delay", "attacking", "ref_x", "ref_y", "ref_valid", "resupplying", "host_center"]
const RESULT_CODES := ["OK", "NOT_OWNER", "BAD_FORMATION", "BAD_ARGS", "NO_TARGET", "BLOCKED", "NOT_ROUTED", "ROUTED", "NO_ORDERS", "NO_COMMANDER", "NOT_CAVALRY"]
const CELL := 64.0
const MARCH := 2.63 # cells / s, crowd cfg.march_speed
const RUN := 4.0    # cells / s, crowd cfg.run_speed
const SLOTS := ["idle", "walk", "run", "attack", "attack_heavy", "guard", "hit", "knockback", "shoot", "down", "unconscious", "get_up", "rescue"]
const DIRS := ["up", "right", "down", "left"]
const POSE := {0: &"idle", 1: &"walk", 2: &"run", 3: &"", 4: &"attack_jump_heavy", 5: &"guard", 6: &"hit", 7: &"knockback",
	8: &"attack_bow", 9: &"down", 10: &"unconscious", 11: &"get_up", 12: &"rescue"}
const YAW := [180.0, 90.0, 0.0, -90.0]
const TROOPS := {"melee_infantry": 0, "bow": 1, "crossbow": 2}

class Host extends Node2D:
	var _combat_bake: Dictionary
	var _soldier_atlas: Texture2D

var lab: Node2D
var crowd: RefCounted
var active := false
var host: Host
var view
var nodes := {}
var caps := {}
var row_sig := {}
var player_index := -1
var player_slot := -1
var player_age := 0.0
var attack_clip := &"attack_unarmed"
var wish := Vector2.ZERO
var running := false
var engage := false
var missing: Array = []
var teams: Array[Dictionary] = []
var rosters: Array[Dictionary] = []
var owners: Array = []
var pending_captivity: Array[Dictionary] = []
var _captivity_atlas_jobs := {} # Cache preparation only; pending_captivity retains event authority.
var event_counts := {}
var last_event_error := {}
var _owner_by_id := {}
var _index_by_id := {}
var _records := {}
var _actors := {}
var _deploy_options: Array = []
var _staged_data: TerrainData
var _original_team_plans: Array = []
var _death_notified := {}
var _building := false
var _kit_appearances: Array = []
var _actor_slots := {}
var _mounted_contact_visuals: Dictionary = {} # Candidate resources; never registered as people.
var _rider_ids: Array[int] = [] # CAV-2: identities natively mounted. Derived from the native flag; never saved.
var _prepared_live_contact_actor_ids: Dictionary = {} # Candidate preparation only.
var _live_contact_actor_ids: Dictionary = {} # Adopted original live resources; retain after original dismount.
var _draw_actors: Array[Node] = []
var _kit_ids := PackedInt32Array() # Atlas truth per soldier; bodied people keep their atlas kit here as the fallback.
var _kit_ids_dirty := false
# Bodied roster members (S1, design bodied_roster_members_design_20261103): presenter-only live bodies for cadre,
# officers, commanders and the controlled roster member. Display only: never truth, never saved, never in _actors.
const BODY_BUDGET := 64
const BODY_GAINS_PER_REFRESH := 8 # Body creation loads a rig; spread a large admission over a few frames.
var _bodies: Dictionary = {} # person_id -> TerrainTestCharacter presenter (display builds only).
var _body_set: Dictionary = {} # person_id -> true: the bodied people within budget (bookkeeping, headless too).
var _body_overflow: Array[int] = [] # Bodied people beyond BODY_BUDGET; the atlas keeps drawing them.
var _body_failed: Dictionary = {} # person_id -> true: presenter preparation failed; the atlas keeps drawing them.
var _no_atlas: Dictionary = {} # person_id -> true: a look the soldier atlas cannot draw; kit -1, bodied (S2 sticky rule).
var _body_slots: Dictionary = {} # Pose clocks of bodies, as _actor_slots for actors.
var _body_sig := PackedInt64Array()
var _body_pending := false
var _body_kits_dirty := false
var _ammo_keys := {}
var _host_fire_active := false
var _fire_visual_dirty := false
var _kit_cache := {}
var _kit_windows := PackedFloat32Array()
var order_calls := 0
var unknown_fields := 0
var ignored_attack_writes := 0
var test_order_failure := -1
var test_seal_failure := false
var _frames := 0
var _pack_ms := 0.0
var _nodes_ms := 0.0
var _step_ms := 0.0
var _steps := 0
var _garrison_return_elapsed := 0.0
var event_cost_count := 0
var event_cost_total_us := 0
var event_cost_max_us := 0
var event_cost_last_us := 0
var _anim_t := 0.0
var _panel_t := 0.0
var _summary_text := ""
var _last_player := Vector2.ZERO
var _panel_layer: CanvasLayer
var _panel_label: Label
var _terrain_revision := -1
var _occupancy_cache := PackedByteArray()


func sync_terrain() -> bool:
	if crowd == null or lab == null or lab.terrain == null: return false
	var data: TerrainData = lab.terrain
	if _terrain_revision == data.navigation_revision: return true
	if not crowd.set_terrain(data.size.x, data.size.y, data.navigation_heights(), data.navigation_flags(), data.navigation_ramps(), data.static_blocked, data.facility_cells): return false
	if not crowd.set_natural_heights(data.height_levels): return false
	_terrain_revision = data.navigation_revision
	_occupancy_cache.clear()
	return true


func reserves_cell(cell: Vector2i, ignored_ids: Array = []) -> bool:
	if not active or crowd == null or not lab.terrain.contains(cell): return false
	var mask := _occupancy_cache
	if not ignored_ids.is_empty() or mask.is_empty():
		mask = crowd.get_occupancy_mask(PackedInt64Array(ignored_ids))
		if ignored_ids.is_empty(): _occupancy_cache = mask
	var index: int = lab.terrain.index(cell)
	return index < mask.size() and mask[index] != 0


static func requested() -> bool:
	return not OS.get_cmdline_user_args().has("--grid")


func setup(lab_node: Node2D) -> void:
	lab = lab_node
	print("crowd10k: crowd mode on (TerrainArmy battles are replaced by ArmyCrowd)")


func set_input(direction: Vector2, run: bool) -> void:
	running = run
	wish = direction.normalized() * (RUN if run else MARCH) if direction != Vector2.ZERO else Vector2.ZERO


# Native arrays are decoded at the boundary; identities never pass through a float.
## This step's hull contacts as native soldier index pairs [a, b, ...]: two hostile aboard people who may each act from their
## deck (SiteVehicleTransport.ship_can_attack) and stand in a current hull contact (ship_combat_contact). Read-only.
func _aboard_melee_pairs() -> PackedInt32Array:
	var pairs := PackedInt32Array()
	if lab == null or lab.site_controller == null: return pairs
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	var aboard: Array = []
	for owner_ref: CrowdPersonOwner in owners:
		for index: int in owner_ref.combat_units.keys():
			var identity := owner_ref.combat_identity(index)
			if identity > 0 and vehicles.is_embarked(identity) and vehicles.ship_can_attack(identity):
				aboard.append([identity, index, int(owner_ref.faction_id)])
	for first: int in aboard.size():
		for second: int in range(first + 1, aboard.size()):
			var a: Array = aboard[first]
			var b: Array = aboard[second]
			if RegionFactionQuery.same_side(int(a[2]), int(b[2])): continue
			if vehicles.ship_combat_contact(int(a[0]), int(b[0])):
				pairs.append(int(a[1])); pairs.append(int(b[1]))
	return pairs

func contains_person(identity: int) -> bool:
	return _index_by_id.has(identity)


## True when a live (not departed) roster team of this crowd has 	eam_id.
func has_live_team(team_id: int) -> bool:
	if not active: return false
	for team: Dictionary in teams:
		if int(team.team_id) == team_id and not bool(team.get("solo", false)) and not bool(team.get("departed", false)): return true
	return false


func owns_original_team(source: TerrainArmy) -> bool:
	if not active: return false
	for plan: Dictionary in _original_team_plans:
		if is_same(plan.get("source"), source): return true
	return false


func person_owner(identity: int) -> Variant:
	return _owner_by_id.get(identity)


func person_owners() -> Array:
	return owners


func team_record(formation: int) -> Dictionary:
	for row: Dictionary in rosters:
		if int(row.get("crowd_formation", -1)) == formation:
			return row
	return {}


func soldier_state(index: int) -> Dictionary:
	if crowd == null or index < 0 or index >= int(crowd.soldier_count()):
		return {}
	var values: PackedFloat64Array = crowd.get_soldier_state(index)
	var refs: PackedInt64Array = crowd.soldier_refs(index)
	var result := {}
	result["military_role"] = int(crowd.get_military_role(index))
	result["post_holder"] = int(crowd.get_post_holder(index))
	result["hit_revision"] = int(crowd.contact_revision(index))
	for k in range(mini(values.size(), SOLDIER_FIELDS.size())):
		result[SOLDIER_FIELDS[k]] = values[k]
	if refs.size() >= 2:
		result["person_id"] = refs[0]
		result["captor_person"] = refs[1]
		result["prison_id"] = refs[2] if refs.size() >= 3 else 0
	return result


func set_soldier_fields(index: int, changes: Dictionary) -> bool:
	if crowd == null or index < 0 or index >= int(crowd.soldier_count()):
		return false
	var has_hit_revision := changes.has("hit_revision")
	# Original counters remain int64 values outside the floating-point packed state.
	if has_hit_revision and (typeof(changes.hit_revision) != TYPE_INT or int(changes.hit_revision) < 0 or not crowd.has_method("set_contact_revision")):
		return false
	# A position write moves a body: the cached occupancy no longer describes the ground.
	if changes.has("px") or changes.has("py"): _occupancy_cache.clear()
	var values: PackedFloat64Array = crowd.get_soldier_state(index)
	var refs: PackedInt64Array = crowd.soldier_refs(index)
	for key: String in changes:
		if key == "hit_revision":
			continue
		elif key == "prison_id":
			if refs.size() < 3: return false
			refs[2] = int(changes[key])
		elif key == "captor_person":
			refs[1] = int(changes[key])
		else:
			var at := SOLDIER_FIELDS.find(key)
			if at < 0 or at >= 22:
				return false
			values[at] = float(changes[key])
	if not bool(crowd.set_soldier_state(index, values, refs)):
		return false
	return not has_hit_revision or bool(crowd.set_contact_revision(index, int(changes.hit_revision)))


func formation_state(index: int) -> Dictionary:
	if crowd == null:
		return {}
	var values: PackedFloat64Array = crowd.get_formation_state(index)
	var refs: PackedInt64Array = crowd.formation_refs(index)
	var result := {}
	result["garrisoned"] = bool(crowd.get_garrisoned(index))
	for k in range(mini(values.size(), FORMATION_FIELDS.size())):
		result[FORMATION_FIELDS[k]] = values[k]
	if refs.size() >= 4:
		result["formal_person"] = refs[0]
		result["acting_person"] = refs[1]
		result["current_person"] = refs[2]
		result["target_person"] = refs[3]
		result["officer_persons"] = Array(refs.slice(4))
	return result


func set_formation_fields(index: int, changes: Dictionary) -> bool:
	var values: PackedFloat64Array = crowd.get_formation_state(index)
	var refs: PackedInt64Array = crowd.formation_refs(index)
	for key: String in changes:
		var at := FORMATION_FIELDS.find(key)
		if key == "garrisoned": continue
		if at >= 0:
			values[at] = float(changes[key])
		elif key in ["formal_person", "acting_person", "current_person", "target_person"]:
			refs[["formal_person", "acting_person", "current_person", "target_person"].find(key)] = int(changes[key])
		elif key == "officer_persons":
			refs.resize(4)
			refs.append_array(PackedInt64Array(changes[key]))
		else:
			return false
	if not bool(crowd.set_formation_state(index, values, refs)): return false
	if not changes.has("garrisoned") or bool(crowd.get_garrisoned(index)) == bool(changes.garrisoned): return true
	return bool(crowd.set_garrisoned(index, int(bool(changes.garrisoned))))


func combat_target(identity: int, with_bodies: bool = false) -> Dictionary:
	if not contains_person(identity):
		return {}
	var index := int(_index_by_id[identity])
	# Original native rows are sampled here; custom soldier_state methods retain their path.
	if get_script().get_base_script() == null and crowd != null and crowd.get_class() == "ArmyCrowd" and crowd.get_script() == null and index >= 0 and index < int(crowd.soldier_count()):
		var values: PackedFloat64Array = crowd.get_soldier_state(index)
		if values.size() == SOLDIER_FIELDS.size():
			var position_value := Vector2(float(values[14]), float(values[15])) * CELL
			return {"owner": _owner_by_id[identity], "unit": index, "position": position_value,
				"cell": Vector2i((position_value / CELL).floor()), "hp": float(values[0]), "bodies": _owner_by_id[identity].incoming_geometry(index).body if with_bodies else []}
	var state := soldier_state(index)
	var position := Vector2(float(state.px), float(state.py)) * CELL
	return {"owner": _owner_by_id[identity], "unit": index, "position": position,
		"cell": Vector2i((position / CELL).floor()), "hp": float(state.hp), "bodies": _owner_by_id[identity].incoming_geometry(index).body if with_bodies else []}


func has_ranged_projectiles() -> bool:
	return has_projectiles()


func has_projectiles() -> bool:
	return crowd != null and bool(crowd.has_projectiles())


func fire_host_active() -> bool:
	return active and _host_fire_active and crowd != null


func fire_motion_segment(index: int) -> PackedFloat64Array:
	if not fire_host_active() or not crowd.has_method("fire_motion_segment"): return PackedFloat64Array()
	return crowd.fire_motion_segment(index)


func sync_fire_visuals() -> bool:
	if not fire_host_active() or not _fire_visual_dirty: return true
	if not crowd.has_method("set_fire_visual_rows"): return false
	var indices := PackedInt32Array()
	var flags := PackedByteArray()
	for owner_ref: CrowdPersonOwner in owners:
		for index: int in owner_ref.combat_units:
			indices.append(index)
			flags.append(owner_ref.fire_body_visual_code(index))
	if not bool(crowd.set_fire_visual_rows(indices, flags)): return false
	_fire_visual_dirty = false
	return true


func has_pending_capture(identity: int) -> bool:
	for event: Dictionary in pending_captivity:
		if int(event.person) == identity:
			return true
	return false


## admit_active_siege (KW21, Nekki 2026-11-09 A): a region checkpoint or a reopen admits siege work in progress. The native
## blob carries the compounds and crew steps and the region owner graph carries the projectiles, as the grid Site's region
## checkpoints did, so the live Site's siege guard (BUSY on any action, translation or walking crew) is skipped there.
func siege_admission_guard(candidate: TerrainData = null, admit_active_siege: bool = false) -> Dictionary:
	if ClassDB.class_exists(&"ArmyCrowd") and not ClassDB.class_has_method(&"ArmyCrowd", &"set_soldier_surrendered"):
		return SiteRuntime.fail("CROWD_BUILD_MISMATCH", "群眾模組缺少投降狀態介面")
	if ClassDB.class_exists(&"ArmyCrowd") and not ClassDB.class_has_method(&"ArmyCrowd", &"set_soldier_mounted"):
		return SiteRuntime.fail("CROWD_BUILD_MISMATCH", "群眾模組缺少騎乘狀態介面")
	if ClassDB.class_exists(&"ArmyCrowd") and not ClassDB.class_has_method(&"ArmyCrowd", &"cav_stats"):
		return SiteRuntime.fail("CROWD_BUILD_MISMATCH", "群眾模組缺少衝鋒統計介面")
	if ClassDB.class_exists(&"ArmyCrowd") and not ClassDB.class_has_method(&"ArmyCrowd", &"soldier_charge"):
		return SiteRuntime.fail("CROWD_BUILD_MISMATCH", "群眾模組缺少衝鋒狀態讀取介面")
	if ClassDB.class_exists(&"ArmyCrowd") and not ClassDB.class_has_method(&"ArmyCrowd", &"set_contact_revision"):
		return SiteRuntime.fail("CROWD_BUILD_MISMATCH", "群眾模組缺少原人物受擊計數匯入介面")
	if ClassDB.class_exists(&"ArmyCrowd"):
		for method: StringName in [&"peek_events", &"event_fatigue"]:
			if not ClassDB.class_has_method(&"ArmyCrowd", method):
				return SiteRuntime.fail("CROWD_BUILD_MISMATCH", "群眾模組缺少原死亡人物疲勞交接介面")
	var live: TerrainData = lab.terrain if lab != null else null
	for data: TerrainData in [live, candidate]:
		if data == null: continue
		if data.site.get("housing", {}) is Dictionary and not data.site.get("housing", {}).is_empty():
			for method: StringName in [&"order_housing_step", &"cancel_housing_step", &"controlled_step_state", &"set_housing_recovery_input", &"set_housing_attendance_input"]:
				if not ClassDB.class_has_method(&"ArmyCrowd", method): return SiteRuntime.fail("CROWD_BUILD_MISMATCH", "群眾模組缺少住宅返家／出席介面；原住房與人物須保留一般模式")
		# Released Siege events retain their specific original authority before
		# Fire's generic non-Fire projectile refusal; neither path admits them.
		if not admit_active_siege:
			var events: Dictionary = SiteStore.siege_event_guard(data)
			if not events.ok: return events
		# A prepared Native replacement becomes lab.terrain before its original owners reactivate.
		if not (data == live and _host_fire_active):
			var fire := SiteStore.fire_event_guard(data)
			if not fire.ok: return fire
		if SiteStore.has_siege_vehicles(data.site) and not siege_native_supported(): return SiteRuntime.fail("CROWD_BUILD_MISMATCH", "群眾模組缺少原人物攻城／複合步介面")
		for vehicle: Dictionary in data.site.get("vehicles", {}).values():
			if str(vehicle.get("kind", "")) in ["cart", "wagon"] and not convoy_native_supported(): return SiteRuntime.fail("CROWD_BUILD_MISMATCH", "群眾模組缺少後勤車隊原生記錄介面")
			# Ship boarding, landing, deck and journey passengers call these bound native methods (crowd10k_gdext.cpp).
			if str(vehicle.get("kind", "")) == "ship" and not ship_native_supported(): return SiteRuntime.fail("CROWD_BUILD_MISMATCH", "群眾模組缺少乘船原生介面")
		# G3: split-shore and ship supply (team_supply version 3) run under the crowd model too.
		if not ClassDB.class_has_method(&"ArmyCrowd", &"set_recovery_input"):
			var saved_rosters: Variant = data.site.get("armies", [])
			var original_rosters: Array = saved_rosters.duplicate() if saved_rosters is Array else []
			var current_registrations := {}
			if data == live and data != candidate:
				var live_rosters: Array = Site.Garrison._armies(lab)
				original_rosters.append_array(live_rosters)
				for original: Dictionary in live_rosters:
					current_registrations[original.team_id] = original.garrison_feature_id
				# A fully formed-out Army clears its registration but remains an
				# original empty slot. Its empty reference also supersedes old saves.
				for team: TerrainArmy in lab.combat_armies:
					if not is_instance_valid(team): continue
					if active and owns_original_team(team): continue
					current_registrations[team.team_id] = team.garrison_feature_id
			var features: Variant = data.site.get("features", {})
			if not features is Dictionary: continue
			for original: Variant in original_rosters:
				if not original is Dictionary: continue
				# Live original owners supersede stale saved mirrors; load candidates
				# retain their own references for the existing Store validation.
				var reference: Variant = current_registrations.get(original.get("team_id"), original.get("garrison_feature_id", ""))
				if not reference is String or str(reference).is_empty(): continue # Existing reference validation remains authoritative.
				var feature: Variant = features.get(reference, {})
				if feature is Dictionary and str(feature.get("kind", "")) == "barracks" and SiteRuntime.barracks_type(feature) == "chinese":
					return SiteRuntime.fail("CROWD_BUILD_MISMATCH", "群眾模組缺少中式軍營恢復介面；原駐營者須保留一般模式")
	return SiteRuntime.ok()

func save_guard(region_checkpoint: bool = false) -> Dictionary:
	var siege_guard := siege_admission_guard(null, region_checkpoint)
	if not siege_guard.ok: return siege_guard
	# KW21: siege compounds and crew steps in progress are part of the native save (siege_busy no longer refuses a save).
	if not pending_captivity.is_empty():
		return SiteRuntime.fail("BUSY", "俘虜交接尚未完成")
	if has_projectiles():
		return SiteRuntime.fail("BUSY", "箭矢仍在飛行；結算前不保存")
	return SiteRuntime.ok()


func set_sustain_input(formation: int, fully_fed: bool, delta: float) -> void:
	crowd.set_sustain_input(formation, fully_fed, delta)


func apply_environment_damage(identity: int, amount: float) -> float:
	if not contains_person(identity):
		return 0.0
	if lab._region_deferring_endpoint():
		# Original life owner and original Region point queue; no hot HP/count
		# write before this same interval's admitted World fatigue publication.
		var before := work_fatigue_forecast_hp(identity)
		if not lab._region_defer_native_environment_damage(identity, amount):
			lab.site_controller.latch_original_step_fault(SiteRuntime.fail("NATIVE_ENDPOINT_NOT_READY"))
			return before
		return maxf(0.0, before - amount)
	var index := int(_index_by_id[identity])
	_audio_native_prepare()
	crowd.apply_environment_damage(index, amount)
	_consume_events()
	return float(soldier_state(index).hp)


# ---------------------------------------------------------------- deploy
func deploy(sides: Array, formations: Array) -> Dictionary:
	var siege_guard := siege_admission_guard()
	if not siege_guard.ok: return siege_guard
	if active:
		return SiteRuntime.fail("BUSY", "群眾模式：請先清除現有隊伍")
	if not ClassDB.class_exists("ArmyCrowd"):
		return SiteRuntime.fail("MISSING_ASSET", "群眾擴充未載入")
	if not TerrainArmy.load_combat_bake() or not TerrainArmy.prewarm_soldier_atlas():
		return SiteRuntime.fail("MISSING_ASSET", "士兵圖集不可用")
	if sides.size() != formations.size() or sides.is_empty():
		return SiteRuntime.fail("INVALID", "隊伍與部署格不相符")
	var total := 0
	for slot in range(sides.size()):
		var side: Dictionary = sides[slot]
		var count := int(side.get("count", 0))
		if count <= 0 or not formations[slot] is Array or formations[slot].size() != count:
			return SiteRuntime.fail("INVALID", "每隊人數與部署格不相符")
		for cell: Variant in formations[slot]:
			if not cell is Vector2i or not lab.terrain.is_walkable(cell):
				return SiteRuntime.fail("BLOCKED", "部署格非法")
		total += count
	if not lab._can_allocate_army_person_ids(total):
		return SiteRuntime.fail("NO_IDS")
	var prepared := d5_prepare_existing(self)
	if not prepared.ok: return prepared
	var data: TerrainData = lab.terrain
	# Candidate deployment only appends items and changes Site allocators. Keep
	# the original nested dictionaries so rejection preserves every live alias.
	var before := {"site": data.site.duplicate(), "items": {},
		"appearances": lab.site_controller._equipment_appearances.duplicate()}
	for field: String in ["item_records", "item_definitions"]:
		if data.site.get(field) is Dictionary: before.items[field] = data.site[field].duplicate()
	crowd = ClassDB.instantiate("ArmyCrowd")
	crowd.setup(clampi(OS.get_processor_count(), 1, 8), int(data.seed_value))
	_terrain_revision = -1
	if not sync_terrain():
		return _deployment_failed(before, SiteRuntime.fail("INVALID", "群眾地形資料"))
	teams.clear()
	rosters.clear()
	_records.clear()
	_actors.clear()
	_ammo_keys.clear()
	_deploy_options = sides.duplicate(true)
	var next_team: int = lab._next_army_identity()
	var centres: Array[Vector2] = []
	for cells: Array in formations:
		var centre := Vector2.ZERO
		for cell: Vector2i in cells: centre += Vector2(cell) + Vector2.ONE * 0.5
		centres.append(centre / maxf(1.0, cells.size()))
	for slot in range(sides.size()):
		var side: Dictionary = sides[slot]
		var faction := int(side.faction)
		var troop: int = TROOPS.get(str(side.troop_type), 0)
		var count := int(side.count)
		var toward := Vector2.ZERO
		var enemies := 0
		for other in range(sides.size()):
			if other != slot and not RegionFactionQuery.same_side(int(sides[other].faction), faction):
				toward += centres[other]
				enemies += 1
		var face := (toward / enemies - centres[slot]).angle() if enemies else 0.0
		var native_faction := _native_faction(faction)
		if native_faction < 0: return _deployment_failed(before, SiteRuntime.fail("NO_SPACE", "群眾原生陣營槽已滿"))
		var formation: int = crowd.add_formation(native_faction, centres[slot].x, centres[slot].y, face, maxi(1, int(ceil(sqrt(count)))), 1.0, troop, float(side.get("training", 0)))
		var ids: Array[int] = lab._allocate_army_person_ids(count)
		var roster := {"schema": 2, "roster_version": 1, "crowd": true, "team_id": next_team + slot,
			"faction_id": faction, "crowd_formation": formation, "units": [], "officer_service": [], "formal_commander": 0,
			# Born with the field SiteStore._normalize_state adds to every crowd roster; without it a normalizing read wrote
			# it into the live Site during a pending cold replay (found 2026-11-08, site_ship_journey_edge).
			"garrison_feature_id": ""}
		# Match the original Army's deployment radius for terrain-shaped formations.
		roster["command_radius"] = 8.0
		for cell: Vector2i in formations[slot]:
			roster["command_radius"] = maxf(float(roster.command_radius), centres[slot].distance_to(Vector2(cell) + Vector2.ONE * 0.5) + 2.0)
		var equip := PackedInt32Array()
		var roles := PackedByteArray()
		var ammo := PackedInt32Array()
		for unit in range(count):
			var appearance: Dictionary = Atlas.female_appearance() if unit >= count - int(side.get("female_count", 0)) else TerrainArmy._combat_bake.manifest.appearance.duplicate(true)
			if troop != 0:
				appearance.parts.weapon = "bow_01" if troop == 1 else "crossbow_01"
				appearance.parts.shield = "none"
			appearance = Site._initial_uniform(appearance, faction)
			var cell: Vector2i = formations[slot][unit]
			var record := {"person_id": ids[unit], "cell": [cell.x, cell.y], "appearance": appearance,
				"item_state": {}, "cargo": {}, "hp": 100.0, "stun": 0.0, "grace": 0.0, "ko": 0.0,
				"getup": 0.0, "exchange_stagger": 0.0, "captive": false, "surrender_pending": false,
				"departed": false, "site_exited": false, "member": true, "present": false, "logistics": false,
				"loot_settled": false, "remains_id": "", "status": "Ready", "work_task": {}, "hit_revision": 0,
				"command_abilities": {"tactics": 50, "leadership": 50, "coach": 50}, "military_role": "officer" if unit <= 2 else "soldier", "role": 1 if unit == 0 else (2 if unit <= 2 else 0)}
			if troop: record.cargo["arrow" if troop == 1 else "bolt"] = 20
			var seeded := SiteRuntime.seed_person_equipment(data, record.item_state, ids[unit], appearance)
			if not seeded.ok:
				return _deployment_failed(before, seeded)
			roster.units.append(record)
			if unit > 0 and unit <= 2: roster.officer_service.append(unit)
			_records[ids[unit]] = record
			equip.append(_packed_equip(appearance))
			roles.append(int(record.role))
			ammo.append(20 if troop else 0)
		var first: int = crowd.add_soldiers(formation, PackedInt64Array(ids), equip, roles, ammo)
		if first < 0:
			return _deployment_failed(before, SiteRuntime.fail("INVALID", "群眾人員匯入失敗"))
		for unit in range(ids.size()):
			if not bool(crowd.set_military_role(first + unit, military_role_code(str(roster.units[unit].military_role)))) \
				or not bool(crowd.set_post_holder(first + unit, int(roster.officer_service.has(unit)))):
				return _deployment_failed(before, SiteRuntime.fail("INVALID_ROLE", "原軍官資格匯入失敗"))
		var starts := PackedFloat32Array()
		for cell: Vector2i in formations[slot]: starts.append_array(PackedFloat32Array([cell.x + 0.5, cell.y + 0.5]))
		crowd.set_start_positions(first, starts)
		rosters.append(roster)
		teams.append({"slot": slot, "team_id": next_team + slot, "formation": formation, "faction": faction,
			"native_faction": native_faction, "troop": troop, "person_ids": ids, "solo": false})
	_ensure_team_containers()
	return _finish_admission(sides, prepared, before, total, "群眾模式：已部署 %d 隊、%d 人" % [sides.size(), total])


# Shared tail of deploy and convert_existing. Imports the prepared original rows (plus any new sides already
# appended to teams/rosters) into the native crowd, then activates it. Failure restores the live Site.
func _finish_admission(sides: Array, prepared: Dictionary, before: Dictionary, total: int, message: String) -> Dictionary:
	var data: TerrainData = lab.terrain
	var existing := d5_append_existing(self, prepared.plans)
	if not existing.ok:
		return _deployment_failed(before, existing)
	var controlled := int(lab.controlled_person_id())
	var actor: TerrainTestCharacter = _actor(controlled)
	var no_player: bool = bool(prepared.get("no_player", false))
	if not no_player and not prepared.person_ids.has(controlled) and actor == null:
		return _deployment_failed(before, SiteRuntime.fail("INVALID", "受控人物不是本 Site 的 actor"))
	var appended := SiteRuntime.ok() if no_player or prepared.person_ids.has(controlled) else _append_actor(actor, false)
	if not appended.ok:
		return _deployment_failed(before, appended)
	# Rejoin actors returned by B even when control has moved to a roster member.
	for returned: TerrainTestCharacter in lab.combat_actors:
		if returned.person_id == controlled or prepared.person_ids.has(returned.person_id): continue
		var handoff: Variant = returned.get_meta(&"crowd_handoff", {})
		if not handoff is Dictionary or not handoff.has("solo_formation"): continue
		var rejoined := _append_actor(returned, false)
		if not rejoined.ok:
			return _deployment_failed(before, rejoined)
	crowd.finalize()
	crowd.set_ai(true)
	_bind_people()
	for slot in range(sides.size()):
		var team: Dictionary = teams[slot]
		var captain := int(_index_by_id[int(team.person_ids[0])])
		var changes: Dictionary = sides[slot].get("abilities", {})
		if not changes.is_empty(): set_soldier_fields(captain, changes)
		for identity in team.person_ids:
			var state := soldier_state(int(_index_by_id[int(identity)]))
			_records[int(identity)].command_abilities = {"tactics": int(state.tactics), "leadership": int(state.leadership), "coach": int(state.coach)}
	var desired := {"people": {}, "formations": {}}
	for identity: int in _actors:
		var actor_imported := _import_actor(identity)
		if not actor_imported.ok:
			return _deployment_failed(before, actor_imported)
		desired.people.merge(actor_imported.people, true)
		desired.formations.merge(actor_imported.formations, true)
	var imported := d5_import_existing_hot(self, prepared.plans)
	if not imported.ok:
		return _deployment_failed(before, imported)
	# Joined actors take their final team state from the original Army envelope.
	desired.people.merge(imported.people, true)
	desired.formations.merge(imported.formations, true)
	var admitted := _source_state_guard(desired)
	if not admitted.ok: return _deployment_failed(before, admitted)
	# Nekki 2026-11-04: each imported team's carried morale state, after the hot import and state guard wrote its formation.
	for plan: Dictionary in prepared.plans:
		if plan.has("formation") and not apply_team_morale(crowd, int(plan.formation), plan.snapshot.get("team_morale", {})):
			return _deployment_failed(before, SiteRuntime.fail("INVALID", "原隊伍士氣狀態匯入失敗"))
	# G5 S2: detached and off-map rows become absent natively after every hot import and state guard.
	var absent_imported := d5_absent_existing(self, prepared.plans)
	if not absent_imported.ok: return _deployment_failed(before, absent_imported)
	# G5 S4: surrender-pending rows become the native surrendered flag after every hot import.
	var surrender_imported := d5_surrender_existing(self, prepared.plans)
	if not surrender_imported.ok: return _deployment_failed(before, surrender_imported)
	# G1: an embarked grid row becomes the native aboard soldier on its own vessel (an NPC sea arrival, found 2026-11-08).
	var aboard_imported := d5_aboard_existing(self, prepared.plans)
	if not aboard_imported.ok: return _deployment_failed(before, aboard_imported)
	# CAV-2: every living rider (GD appearance.mounted) takes the native mounted flag after every hot import.
	var riders_imported := import_mounted_riders()
	if not riders_imported.ok: return _deployment_failed(before, riders_imported)
	if bool(prepared.get("no_player", false)):
		player_index = -1
	else:
		player_index = int(_index_by_id[controlled])
		crowd.set_host_control(player_index, true)
	# Admit every kit before mutating the original people or item owners.
	if not _refresh_kits():
		return _deployment_failed(before, SiteRuntime.fail("MISSING_ASSET", "士兵外觀不被圖集接受"))
	for identity: int in crowd.person_ids():
		if not _prepare_contact_appearance(_appearance(identity), identity):
			return _deployment_failed(before, SiteRuntime.fail("MISSING_ASSET", "原士兵同 body 接觸資源未備妥"))
	_host_fire_active = false
	if crowd.has_method("fire_host_protocol") and crowd.has_method("set_host_ranged_delegate") and crowd.has_method("set_fire_safe_rest_input"):
		if int(crowd.fire_host_protocol()) == 1:
			if not bool(crowd.set_host_ranged_delegate(true)):
				return _deployment_failed(before, SiteRuntime.fail("CROWD_FIRE_BRIDGE_BUSY", "Native 舊彈體尚未收束；保留原隊伍與持物"))
			_host_fire_active = true
	_fire_visual_dirty = _host_fire_active
	active = true
	for slot in range(sides.size()):
		var new_owner = person_owner(int(teams[slot].person_ids[0]))
		lab.site_controller.initialize_team_items(new_owner)
	for slot in range(sides.size()):
		var team: Dictionary = teams[slot]
		var ai := bool(sides[slot].get("ai_enabled", false))
		crowd.set_order_owner(int(team.formation), ai)
		if not ai and bool(sides[slot].get("attack", false)):
			issue_order(int(team.team_id), TerrainArmy.CombatOrder.ATTACK)
	d5_commit_existing(self, prepared.plans)
	_original_team_plans = prepared.plans
	data.site.armies.append_array(rosters)
	data.site["army_next_team"] = _solo_team_id()
	_refresh_bodies() # Presentation only, after every admission check; a body that cannot be prepared keeps the atlas.
	_begin_player()
	_make_panel()
	_prewarm_captivity_atlases.call_deferred()
	_region_mode_follow()
	return SiteRuntime.ok(message)


# Legacy grid Site -> live crowd, with no new sides. Every grid team goes through the same D5 import as deploy.
# Each refusal happens before any mutation, so the grid Site stays intact. Nothing here writes the save file.
func convert_existing() -> Dictionary:
	if active:
		return SiteRuntime.fail("BUSY", "群眾模式已啟用；無需轉換")
	var siege_guard := siege_admission_guard()
	if not siege_guard.ok: return siege_guard
	if not ClassDB.class_exists("ArmyCrowd"):
		return SiteRuntime.fail("MISSING_ASSET", "群眾擴充未載入")
	if not TerrainArmy.load_combat_bake() or not TerrainArmy.prewarm_soldier_atlas():
		return SiteRuntime.fail("MISSING_ASSET", "士兵圖集不可用")
	var data: TerrainData = lab.terrain
	if float(data.site.get("combat_left", 0.0)) > 0.0:
		return SiteRuntime.fail("BATTLE_IN_PROGRESS", "戰鬥尚未脫離，不能轉為群眾；原存檔保持一般模式")
	# A legacy grid Site may carry no person allocator (the grid Store scans on load); a crowd save requires it (found
	# 2026-11-11, settlement crowd port). Record the same legacy scan the original allocator runs.
	if not data.site.has("next_person_id"): data.site["next_person_id"] = lab._next_army_person_id_for(data, lab.combat_actors, lab.combat_armies)
	# A travelling party's contact frame carries its hulls on their region route (kinematic poses), not a Site journey.
	if not lab.terrain.has_meta(&"region_party_world_frame") and (lab.has_ship_journey() or lab.site_controller.ship_journey_active()):
		return SiteRuntime.fail("SHIP_JOURNEY_PENDING", "船隊仍在跨區旅程中，不能轉為群眾；原存檔保持一般模式")
	var prepared := d5_prepare_existing(self)
	if not prepared.ok: return prepared
	if prepared.plans.is_empty(): return SiteRuntime.fail("NO_GRID_TEAMS", "沒有可轉換的一般隊伍")
	var total := 0
	for plan: Dictionary in prepared.plans: total += plan.units.size()
	# Same original-alias snapshot as deploy: rejection restores every live Site dictionary.
	var before := {"site": data.site.duplicate(), "items": {},
		"appearances": lab.site_controller._equipment_appearances.duplicate()}
	for field: String in ["item_records", "item_definitions"]:
		if data.site.get(field) is Dictionary: before.items[field] = data.site[field].duplicate()
	crowd = ClassDB.instantiate("ArmyCrowd")
	crowd.setup(clampi(OS.get_processor_count(), 1, 8), int(data.seed_value))
	_terrain_revision = -1
	if not sync_terrain():
		return _deployment_failed(before, SiteRuntime.fail("INVALID", "群眾地形資料"))
	teams.clear()
	rosters.clear()
	_records.clear()
	_actors.clear()
	_ammo_keys.clear()
	_deploy_options = []
	return _finish_admission([], prepared, before, total, "群眾模式：已轉換 %d 隊、%d 人" % [prepared.plans.size(), total])


func _deployment_failed(before: Dictionary, failure: Dictionary) -> Dictionary:
	for field: String in before.items:
		var original: Dictionary = before.site[field]
		original.clear()
		original.merge(before.items[field])
	lab.terrain.site.clear()
	lab.terrain.site.merge(before.site)
	lab.site_controller._equipment_appearances.clear()
	lab.site_controller._equipment_appearances.merge(before.appearances)
	_dispose()
	return failure


# Admission compares the transfer request, never a setter's normalized result.
# This covers the exposed Site boundary; it does not assert native RNG parity.
func _source_state_guard(desired: Dictionary) -> Dictionary:
	var siege_guard := siege_admission_guard()
	if not siege_guard.ok: return siege_guard
	var post_holders := _roster_post_holders()
	for identity: int in desired.people:
		var hot: Dictionary = desired.people[identity]
		var index := int(_index_by_id.get(identity, -1))
		var actual := soldier_state(index)
		var person_source = person_owner(identity)
		var formation := int(person_source.formation_index) if person_source != null else -1
		var military: String = _actors[identity].military_role if _actors.has(identity) else str(_records[identity].get("military_role", "soldier"))
		if int(actual.get("military_role", -1)) != military_role_code(military):
			return _source_state_mismatch(identity, formation, "military_role", military_role_code(military), actual.get("military_role"))
		if int(actual.get("post_holder", -1)) != int(post_holders.has(identity)):
			return _source_state_mismatch(identity, formation, "post_holder", int(post_holders.has(identity)), actual.get("post_holder"))
		if int(actual.get("person_id", -1)) != identity:
			return _source_state_mismatch(identity, formation, "person_id", identity, actual.get("person_id"))
		if not actual.has("hit_revision") or actual.hit_revision != hot.hit_revision:
			return _source_state_mismatch(identity, formation, "hit_revision", hot.hit_revision, actual.get("hit_revision"))
		for field: String in SOLDIER_FIELDS.slice(0, 22):
			var expected: Variant = hot[field]
			if field in ["tactics", "leadership", "coach"] and int(hot.tactics) < 0: expected = -1
			var scalar := _import_scalar(expected, field in ["px", "py", "face"])
			if not actual.has(field) or float(actual[field]) != scalar:
				return _source_state_mismatch(identity, formation, field, scalar, actual.get(field))
		if int(actual.get("captor_person", -1)) != int(hot.captor_person):
			return _source_state_mismatch(identity, formation, "captor_person", int(hot.captor_person), actual.get("captor_person"))
		if int(actual.get("prison_id", 0)) != int(hot.get("prison_id", 0)):
			return _source_state_mismatch(identity, formation, "prison_id", int(hot.get("prison_id", 0)), actual.get("prison_id", 0))
	for index: int in desired.formations:
		var state: Dictionary = desired.formations[index]
		var actual := formation_state(index)
		if bool(actual.get("garrisoned", false)) != bool(state.get("garrisoned", false)):
			return _source_state_mismatch(-1, index, "garrisoned", bool(state.get("garrisoned", false)), actual.get("garrisoned"))
		for field: String in FORMATION_FIELDS:
			var scalar := _import_scalar(state[field], field in ["goal_x", "goal_y", "goal_facing", "origin_x", "origin_y", "cx", "cy", "facing", "ref_x", "ref_y"])
			if not actual.has(field) or float(actual[field]) != scalar:
				return _source_state_mismatch(-1, index, field, scalar, actual.get(field))
		for field: String in ["formal_person", "acting_person", "current_person", "target_person"]:
			if not actual.has(field) or int(actual[field]) != int(state[field]):
				return _source_state_mismatch(-1, index, field, state[field], actual.get(field))
		var officers: Array = actual.get("officer_persons", [])
		if officers.size() != state.officer_persons.size():
			return _source_state_mismatch(-1, index, "officer_persons", state.officer_persons, actual.get("officer_persons"))
		for officer in range(officers.size()):
			if int(officers[officer]) != int(state.officer_persons[officer]):
				return _source_state_mismatch(-1, index, "officer_persons", state.officer_persons, officers)
	return sync_siege_inputs() if SiteStore.has_siege_vehicles(lab.terrain.site) else SiteRuntime.ok()


static func _import_scalar(value: Variant, single_precision: bool) -> float:
	var scalar := (1.0 if value else 0.0) if value is bool else float(value)
	return float(PackedFloat32Array([scalar])[0]) if single_precision else scalar


func _source_state_mismatch(identity: int, formation: int, field: String, expected: Variant, actual: Variant) -> Dictionary:
	var team_id := -1
	for team: Dictionary in teams:
		if int(team.formation) == formation:
			team_id = int(team.team_id)
			break
	var result := SiteRuntime.fail("UNSUPPORTED", "原人物或隊伍狀態無法無損交接群眾")
	result.merge({"reason": "SOURCE_STATE_MISMATCH", "person_id": identity, "team_id": team_id,
		"formation": formation, "field": field, "expected": expected, "actual": actual})
	return result


func _actor(identity: int) -> TerrainTestCharacter:
	for actor: TerrainTestCharacter in lab.combat_actors:
		if actor.person_id == identity: return actor
	return null


func _append_actor(actor: TerrainTestCharacter, runtime: bool = true) -> Dictionary:
	var siege_guard := siege_admission_guard()
	if not siege_guard.ok: return siege_guard
	if not actor.projectiles.is_empty() or actor._rescue_left > 0.0:
		return SiteRuntime.fail("BUSY", "原 actor 的彈體或救助尚未收束")
	# Initial deployment validates references after every candidate actor is appended.
	if runtime:
		var handoff_guard := _actor_handoff_guard(actor)
		if not handoff_guard.ok: return handoff_guard
	var appearance: Dictionary = actor.capture_state().appearance
	var projected := SiteRuntime.equipment_appearance(lab.terrain, actor.item_state, appearance)
	if projected.is_empty(): return SiteRuntime.fail("INVALID", "受控人物持物不完整")
	if runtime and not equipment_recipe_guard(actor.person_id, projected).ok:
		return SiteRuntime.fail("MISSING_ASSET", "繼承人外觀不可呈現")
	var family := WeaponMaterials.family(StringName(str(projected.parts.weapon)))
	var troop := 1 if family == &"bow_01" else (2 if family == &"crossbow_01" else 0)
	var position := actor.position / CELL
	if actor.faction_id < 0 or actor.faction_id > 255 or not position.is_finite() or position.x < 0.0 or position.y < 0.0 or position.x >= lab.terrain.size.x or position.y >= lab.terrain.size.y or not is_finite(actor.training) or actor.training < 0.0:
		return SiteRuntime.fail("INVALID", "繼承人陣營、位置或訓練非法")
	if int(crowd.soldier_index(actor.person_id)) >= 0:
		return SiteRuntime.fail("INVALID", "繼承人已在群眾中")
	var before := {}
	if runtime:
		if _kit_ids.size() != int(crowd.soldier_count()) or not bool(crowd.validate()):
			return SiteRuntime.fail("INVALID", "原群眾狀態或外觀數量非法")
		before = {"native": crowd.save_state(), "teams": teams.duplicate(), "actors": _actors.duplicate(),
			"owners": owners.duplicate(), "owner_by_id": _owner_by_id.duplicate(), "index_by_id": _index_by_id.duplicate(),
			"ammo_keys": _ammo_keys.duplicate(), "kit_ids": _kit_ids.duplicate()}
	if not _prepare_contact_appearance(projected, actor.person_id):
		return SiteRuntime.fail("MISSING_ASSET", "原 actor 同 body 接觸資源未備妥")
	var native_faction := _native_faction(actor.faction_id)
	if native_faction < 0: return SiteRuntime.fail("NO_SPACE", "群眾原生陣營槽已滿")
	var formation: int = crowd.add_formation(native_faction, position.x, position.y, Vector2(actor.facing).angle(), 1, 1.0, troop, actor.training)
	var cargo: Dictionary = lab.terrain.site.manual.cargo if actor == lab.character else lab.terrain.site.worker.cargo
	var index: int = crowd.add_soldiers(formation, PackedInt64Array([actor.person_id]), PackedInt32Array([_packed_equip(projected)]), PackedByteArray([1]), PackedInt32Array([int(cargo.get("arrow" if troop == 1 else "bolt", 0)) if troop else 0]))
	if index < 0: return _append_actor_failed(before, SiteRuntime.fail("INVALID", "繼承人匯入失敗"))
	if not bool(crowd.set_military_role(index, military_role_code(actor.military_role))) or not bool(crowd.set_post_holder(index, 0)):
		return _append_actor_failed(before, SiteRuntime.fail("INVALID_ROLE", "原人物軍官資格匯入失敗"))
	_actors[actor.person_id] = actor
	teams.append({"slot": -1, "team_id": _solo_team_id(), "formation": formation, "faction": actor.faction_id,
		"native_faction": native_faction, "troop": troop, "person_ids": [actor.person_id], "solo": true})
	crowd.set_order_owner(formation, false)
	if runtime:
		_index_by_id[actor.person_id] = index
		if troop != 0: _ammo_keys[actor.person_id] = "arrow" if troop == 1 else "bolt"
		var person_source = PersonOwner.new()
		person_source.setup(self, formation, int(teams.back().team_id), actor.faction_id, {}, {index: actor})
		owners.append(person_source)
		_owner_by_id[actor.person_id] = person_source
		var imported := _import_actor(actor.person_id)
		if not imported.ok: return _append_actor_failed(before, imported)
		var admitted := _source_state_guard(imported)
		if not admitted.ok: return _append_actor_failed(before, admitted)
		# Actors use their original presenter. Keep every existing kit and atlas intact.
		var ids := _kit_ids.duplicate()
		ids.append(-1)
		if not bool(crowd.render_set_kits(ids)):
			return _append_actor_failed(before, SiteRuntime.fail("MISSING_ASSET", "繼承人外觀匯入失敗"))
		_kit_ids = ids
		_kit_ids_dirty = false # The append installed all pending indices as well.
		_body_kits_dirty = not _bodies.is_empty() # The raw atlas submission dropped the body overlay.
		_kit_appearances.append(null)
		_adopt_mounted_contact_visuals()
	_audio_mount_update(index, bool(projected.get("mounted", false)))
	return SiteRuntime.ok()


func _append_actor_failed(before: Dictionary, failure: Dictionary) -> Dictionary:
	_clear_mounted_contact_visuals()
	if before.is_empty(): return failure # Initial deployment discards its whole candidate.
	var restored := bool(crowd.load_state(before.native))
	assert(restored, "Original native snapshot must remain loadable during an actor append")
	if not restored: return SiteRuntime.fail("INVALID", "原群眾快照無法回復")
	teams.assign(before.teams)
	_actors = before.actors
	owners.assign(before.owners)
	_owner_by_id = before.owner_by_id
	_index_by_id = before.index_by_id
	_rebuild_rider_ids()
	_ammo_keys = before.ammo_keys
	_kit_ids = before.kit_ids
	# Native load preserves atlas tracks/kits, but resets per-person kit indices.
	var kits_restored := bool(crowd.render_set_kits(_kit_ids))
	_kit_ids_dirty = not kits_restored
	_body_kits_dirty = not _bodies.is_empty()
	assert(kits_restored, "Original native kit indices must match the restored snapshot")
	if kits_restored: _audio_mount_install(_audio_mounted_rows)
	return failure if kits_restored else SiteRuntime.fail("INVALID", "原群眾外觀索引無法回復")


## G6.4b: the person ids of every departed tombstone team. They stay in the native blob, released, and have no records.
func _departed_people() -> Dictionary:
	var result := {}
	for team: Dictionary in teams:
		if bool(team.get("departed", false)):
			for identity: Variant in team.person_ids: result[int(identity)] = true
		# G6.5: a live team keeps its formation while a cadre-led sub-party has left it.
		for identity: Variant in team.get("departed_person_ids", []): result[int(identity)] = true
	return result


func _bind_people() -> void:
	owners.clear()
	_owner_by_id.clear()
	_index_by_id.clear()
	var ids: PackedInt64Array = crowd.person_ids()
	var departed := _departed_people()
	for index in range(ids.size()):
		if departed.has(int(ids[index])): continue # G6.4b: released by a travel departure; no record, no owner.
		_index_by_id[ids[index]] = index
		var appearance := _appearance(ids[index])
		var family := WeaponMaterials.family(StringName(str(appearance.get("parts", {}).get("weapon", "none"))))
		if family in [&"bow_01", &"crossbow_01"]:
			_ammo_keys[ids[index]] = "arrow" if family == &"bow_01" else "bolt"
	for team: Dictionary in teams:
		if bool(team.get("departed", false)): continue
		var records := {}
		var actors := {}
		for identity in team.person_ids:
			var id := int(identity)
			var index := int(_index_by_id[id])
			if _actors.has(id):
				actors[index] = _actors[id]
				if _actors[id].hp <= 0.0: _death_notified[id] = true
			else:
				records[index] = _records[id]
				if float(_records[id].get("hp", 100.0)) <= 0.0: _death_notified[id] = true
		var person_source = PersonOwner.new()
		person_source.setup(self, int(team.formation), int(team.team_id), int(team.faction), records, actors)
		owners.append(person_source)
		for identity in team.person_ids: _owner_by_id[int(identity)] = person_source


func _actor_handoff_guard(actor: TerrainTestCharacter) -> Dictionary:
	var value: Variant = actor.get_meta(&"crowd_handoff", {})
	if not value is Dictionary or (not value.is_empty() and not SiteStore._valid_crowd_actor_handoff(value, actor.person_id)):
		return SiteRuntime.fail("INVALID", "原 actor 群眾交接快照格式非法")
	var extra: Dictionary = value
	if not extra.has("solo_formation") or not SiteStore._crowd_actor_solo_current(actor.capture_state(), extra): return SiteRuntime.ok()
	var saved: Dictionary = extra.solo_formation
	for key: String in ["formal_person", "acting_person", "current_person"]:
		if int(saved.get(key, -1)) not in [-1, actor.person_id]:
			return SiteRuntime.fail("INVALID", "原 actor 隊伍的指揮引用不屬於本人")
	for officer in saved.get("officer_persons", []):
		if int(officer) != actor.person_id:
			return SiteRuntime.fail("INVALID", "原 actor 隊伍的幹部引用不屬於本人")
	var target := int(saved.get("target_person", -1))
	if target != -1 and target != actor.person_id and not _index_by_id.has(target) and (crowd == null or int(crowd.soldier_index(target)) < 0):
		return SiteRuntime.fail("INVALID", "原 actor 隊伍目標不在本次群眾中")
	return SiteRuntime.ok()

func _import_actor(identity: int) -> Dictionary:
	var actor: TerrainTestCharacter = _actors[identity]
	var person_source = person_owner(identity)
	var index := int(_index_by_id[identity])
	var solo := bool(_team_by_id(person_source.team_id).get("solo", false))
	if solo:
		var guard := _actor_handoff_guard(actor)
		if not guard.ok: return guard
	var handoff: Dictionary = actor.get_meta(&"crowd_handoff", {})
	var formation: Dictionary = formation_state(person_source.formation_index)
	if solo and handoff.has("solo_formation") and SiteStore._crowd_actor_solo_current(actor.capture_state(), handoff):
		var saved: Dictionary = handoff.solo_formation
		# Check references before touching the candidate's rule state.
		for key: String in ["formal_person", "acting_person", "current_person"]:
			if int(saved.get(key, -1)) not in [-1, identity]:
				return SiteRuntime.fail("INVALID", "原 actor 隊伍的指揮引用不屬於本人")
		for officer in saved.get("officer_persons", []):
			if int(officer) != identity:
				return SiteRuntime.fail("INVALID", "原 actor 隊伍的幹部引用不屬於本人")
		var target := int(saved.get("target_person", -1))
		if target != -1 and not _index_by_id.has(target):
			return SiteRuntime.fail("INVALID", "原 actor 隊伍目標不在本次群眾中")
		formation.merge(saved, true)
	formation.merge({"fatigue": actor.fatigue, "fatigue_rest": actor.fatigue_rest, "training": actor.training}, true)
	if solo:
		formation["no_orders"] = true
		formation["ai_enabled"] = false
		formation["host_center"] = identity == int(lab.controlled_person_id())
	var cargo: Dictionary = lab.terrain.site.manual.cargo if actor == lab.character else lab.terrain.site.worker.cargo
	var hot := _actor_native_fields(actor, lab.terrain.site.get("captivity", {}), _appearance(identity), cargo)
	if solo and not actor.has_meta(&"crowd_handoff") and actor.command_abilities.is_empty():
		# A first-time solo Actor takes the abilities generated by native admission.
		# Returned Actors keep their original abilities and the full strict guard.
		var initial := soldier_state(index)
		for field: String in ["tactics", "leadership", "coach"]:
			var value: Variant = initial.get(field, -1)
			if not value is float and not value is int or not is_finite(float(value)) or float(value) != float(int(value)) or int(value) < 0 or int(value) > 100:
				return SiteRuntime.fail("INVALID", "初次 actor 指揮能力初始化非法")
			hot[field] = int(value)
	if not _index_by_id.has(int(hot.captor_person)):
		hot.captor_person = -1 # D11: Site retains its original guard_id.
	var desired := {"people": {identity: hot.duplicate()},
		"formations": {int(person_source.formation_index): formation.duplicate(true)}}
	if not set_soldier_fields(index, hot) or not set_formation_fields(person_source.formation_index, formation):
		return SiteRuntime.fail("INVALID", "原 actor 完整熱狀態匯入失敗")
	return SiteRuntime.ok("", desired)


static func _actor_native_fields(actor: TerrainTestCharacter, captivity: Dictionary, appearance: Dictionary, cargo: Dictionary) -> Dictionary:
	var handoff: Dictionary = actor.get_meta(&"crowd_handoff", {})
	var abilities: Dictionary = actor.command_abilities
	var family := WeaponMaterials.family(StringName(str(appearance.parts.get("weapon", "none"))))
	var ammo_key := "arrow" if family == &"bow_01" else "bolt" if family == &"crossbow_01" else ""
	var direction := Vector2(actor.facing)
	var face := float(handoff.get("face", direction.angle()))
	var old_direction := Vector2.from_angle(face)
	var old_facing := Vector2i(int(signf(old_direction.x)), 0) if absf(old_direction.x) > absf(old_direction.y) else Vector2i(0, int(signf(old_direction.y)))
	if old_facing != actor.facing:
		face = direction.angle() # Ordinary movement after a handoff supersedes its old heading.
	return {"hp": actor.hp, "hit_revision": actor._received_effective_hit, "stun": actor.stun, "grace": actor.stun_grace,
		"ko": actor.knockout_left, "getup": actor.action_time if actor._getting_up else 0.0,
		"stagger": actor.exchange_stagger, "captive": actor.captive,
		"captor_person": int(captivity.get(str(actor.person_id), {}).get("guard_id", -1)),
		"prison_id": int(captivity.get(str(actor.person_id), {}).get("prison_id", "0")),
		"bandaged": bool(handoff.get("bandaged", false)), "escape_t": float(handoff.get("escape_t", 0.0)),
		"role": int(handoff.get("role", 1)), "knock_t": float(handoff.get("knock_t", 0.0)), "act_t": float(handoff.get("act_t", 0.0)),
		"exch_cd": actor.exchange_cooldown, "ranged_cd": actor.ranged_cooldown, "skill_cd": actor.exchange_skill_cooldown,
		"ammo": int(cargo.get(ammo_key, 0)) if not ammo_key.is_empty() else 0,
		"px": actor.position.x / CELL, "py": actor.position.y / CELL, "face": face,
		"tactics": int(abilities.get("tactics", -1)), "leadership": int(abilities.get("leadership", 0)), "coach": int(abilities.get("coach", 0))}


func _packed_equip(appearance: Dictionary) -> int:
	var weapon := StringName(str(appearance.parts.get("weapon", "none")))
	var family := ["none", "longsword_01", "spear_01", "axe_01", "wood_axe_01", "hammer_01", "dagger_01", "bow_01", "crossbow_01", "pickaxe_01", "tool_hammer_01", "shovel_01"].find(str(WeaponMaterials.family(weapon)))
	var material := ["", "wood", "stone", "iron", "steel"].find(WeaponMaterials.material(weapon))
	var armor := str(appearance.parts.get("armor", "none"))
	var armor_code := 0
	if armor != "none":
		armor_code = 5 if armor.contains("mingguang") else (4 if armor.contains("steel") else (3 if armor.contains("iron") else (2 if armor.contains("leather") else 1)))
	return maxi(0, family) | (maxi(0, material) << 8) | (armor_code << 16) | ((1 if str(appearance.parts.get("shield", "none")) != "none" else 0) << 24)


var _appearance_cache: Dictionary = {} # person id -> {holder, original, data, stamp, projected}; never saved.

func _appearance(identity: int) -> Dictionary:
	var prof: int = Time.get_ticks_usec() if lab != null and lab.combat_profile_enabled else 0 # Optional counters only.
	var projected := _appearance_now(identity)
	if prof > 0: lab._combat_profile_stage("crowd_appearance", prof)
	return projected

func _appearance_now(identity: int) -> Dictionary:
	var body: Variant = _actors[identity] if _actors.has(identity) else _records[identity]
	var original: Dictionary = body.capture_state().appearance if _actors.has(identity) else body.appearance
	var data: TerrainData = _staged_data if _staged_data != null else lab.terrain
	var holder: Dictionary = body.item_state
	var hp: float
	if _index_by_id.has(identity):
		var index := int(_index_by_id[identity])
		if get_script().get_base_script() == null and crowd != null and crowd.get_class() == "ArmyCrowd" and crowd.get_script() == null and index >= 0 and index < int(crowd.soldier_count()):
			var values: PackedFloat64Array = crowd.get_soldier_state(index)
			hp = float(values[0]) if values.size() == SOLDIER_FIELDS.size() else float(soldier_state(index).hp)
		else:
			hp = float(soldier_state(index).hp)
	else:
		hp = float(body.get("hp"))
	# The original presentation owner keeps worn gear on the remains holder.
	# A roster row is a Dictionary; an original Actor is a Node, whose get() takes one argument (found 2026-11-14,
	# CC-20261114-193: a live crowd death crashed here and its remains/family pause never settled).
	if hp <= 0.0 and bool((body.get("loot_settled", false) if body is Dictionary else body.get("loot_settled")) == true):
		# Decision A2 on crowd (2026-11-10): a settled fallen member that travelled inert with its team left its remains
		# container at the Site it fell in. Here it is drawn with its own saved look, as it fell; an empty holder would
		# project an unarmed look no atlas kit covers (MISSING_ASSET at the arrival conversion).
		if not data.site.get("ground_loot", {}).has(str(body.get("remains_id"))): return original.duplicate(true)
		holder = data.site.ground_loot.get(str(body.get("remains_id")), SiteRuntime.new_item_state("empty-remains"))
	# Perf (2026-11-12): a roster person's projected look only changes with its holder (versioned on every item change), its
	# saved look or its remains; the same inputs return the cached projection (a copy) instead of re-deriving it each step.
	var cacheable: bool = not _actors.has(identity)
	var stamp: Array = [holder.get("version", -1), holder.get("item_ids", []).size(), holder.get("equipped", {}).hash(), original.hash(), hp <= 0.0]
	if cacheable:
		var cached: Dictionary = _appearance_cache.get(identity, {})
		if not cached.is_empty() and is_same(cached.holder, holder) and is_same(cached.original, original) and is_same(cached.data, data) and cached.stamp == stamp:
			return cached.projected.duplicate(true)
	var projected := SiteRuntime.equipment_appearance(data, holder, original)
	if cacheable: _appearance_cache[identity] = {"holder": holder, "original": original, "data": data, "stamp": stamp, "projected": projected.duplicate(true)}
	# CAV-3: an ordinary person rides only by the mount slot. A controlled Actor also keeps its live-editor
	# riding state (toggle_mount), which equipment_appearance alone would clear.
	if _actors.has(identity) and not projected.is_empty() and bool(original.get("mounted", false)): projected["mounted"] = true
	return projected

func _prepare_contact_appearance(appearance: Dictionary, identity: int, saved_actor: bool = false) -> bool:
	var actor := _actor(identity)
	if bool(appearance.get("mounted", false)) and (actor != null or saved_actor):
		if not HumanCharacter3DEditor.valid_appearance(appearance): return false
		if not saved_actor and actor.editor != null:
			var ready_now := actor.editor.model_root != null and actor.editor.animation_player != null and actor.editor.is_mounted and actor.player_sprite != null
			if ready_now: _prepared_live_contact_actor_ids[identity] = true
			return ready_now
		if _mounted_contact_visuals.has(identity):
			_prepared_live_contact_actor_ids[identity] = true
			return true
		# The original Actor node is a disposable resource package, with no
		# person ID, owner registration, logic process or native state writes.
		var prepared := TerrainTestCharacter.new()
		prepared.set_process(false)
		lab.get_tree().root.add_child(prepared)
		if not prepared.prepare_contact_visual(appearance):
			prepared.free()
			return false
		_mounted_contact_visuals[identity] = prepared
		_prepared_live_contact_actor_ids[identity] = true
		return true
	return TerrainArmy.prepare_contact_source_for(appearance, actor.editor if is_instance_valid(actor) and is_instance_valid(actor.editor) else null)

func _adopt_mounted_contact_visuals() -> void:
	for identity: int in _mounted_contact_visuals:
		var prepared: TerrainTestCharacter = _mounted_contact_visuals[identity]
		var actor: TerrainTestCharacter = _actors.get(identity)
		if actor != null: actor.adopt_contact_visual(prepared)
		prepared.free()
	_mounted_contact_visuals.clear()
	for identity: int in _prepared_live_contact_actor_ids:
		var actor: TerrainTestCharacter = _actors.get(identity)
		if actor != null and actor.editor != null: _live_contact_actor_ids[identity] = true
	_prepared_live_contact_actor_ids.clear()

func _sample_prepared_actor_contact(actor: TerrainTestCharacter, appearance: Dictionary, values: PackedFloat64Array, native: PackedFloat64Array) -> Dictionary:
	# A pure derived pose read from the existing original live geometry owner.
	# The resource was prepared before admission; this path never loads assets.
	if actor == null or actor.editor == null or actor.player_sprite == null or values.size() != 27 or native.size() != 2: return {}
	var slot := clampi(int(native[0]), 0, SLOTS.size() - 1)
	var editor: HumanCharacter3DEditor = actor.editor
	if int(editor._body_index) != int(appearance.body): return {}
	var clip: StringName
	var time: float
	var direction: Vector2i
	var work: Dictionary = lab.site_controller.vehicles.siege_work_pose(actor.person_id)
	if not work.is_empty():
		clip = StringName(str(work.clip))
		# Explicit candidate/command preparation installed these resources.
		# The existing work sampler must perform no per-query asset construction.
		if not editor.animation_player.has_meta("siege_work_private_library"): return {}
		for required: String in SiegeWorkClips.DURATIONS:
			if not editor.animation_player.has_animation(StringName(required)) or editor.animation_player.get_animation(StringName(required)).resource_name != required + "_v1_original_rig" or not bool(editor._available_animation_ids.get(StringName(required), false)): return {}
		if not SiegeWorkClips.sample(editor, str(clip), float(work.time), Vector2i(work.facing)): return {}
		time = fposmod(float(work.time), float(SiegeWorkClips.DURATIONS[str(clip)]))
		direction = Vector2i(work.facing)
	else:
		if SiegeWorkClips.DURATIONS.has(str(editor.selected_animation)):
			editor.combat_ready = actor.combat_ready
			editor.visual_state.combat_ready = actor.combat_ready
			editor._update_weapon_sheath_state()
		var mounted := editor.is_mounted
		clip = StringName(_clip_for(SLOTS[slot], appearance))
		match SLOTS[slot]:
			"idle": clip = &"ride_idle" if mounted else &"idle"
			"walk": clip = &"ride_walk" if mounted else &"walk"
			"run": clip = &"ride_run" if mounted else &"run"
			"attack": clip = &"attack"
			"attack_heavy": clip = &"ride_heavy" if mounted else &"attack_jump_heavy"
			"guard": clip = &"guard"
		var resolved: StringName = editor._normalize_animation_id(clip)
		if resolved == &"attack": resolved = editor._resolve_weapon_attack_animation()
		elif resolved == &"ride_attack" and not bool(editor._available_animation_ids.get(&"ride_attack", false)) and bool(editor._available_animation_ids.get(&"ride_slash", false)): resolved = &"ride_slash"
		elif resolved == &"ride_slash" and not bool(editor._available_animation_ids.get(&"ride_slash", false)) and bool(editor._available_animation_ids.get(&"ride_attack", false)): resolved = &"ride_attack"
		if editor._animation_index(resolved) < 0 or not bool(editor._available_animation_ids.get(resolved, false)): return {}
		# The original selector calibrates the rider on a clip change. Repeated
		# reads of the same native pose must not perform another seat correction.
		if editor.selected_animation != resolved and not editor.select_animation_by_id(clip): return {}
		clip = editor.selected_animation
		# Retain the existing original selector's ride/nonride dismount policy.
		actor._saved_appearance.mounted = actor.is_mounted()
		_audio_mount_update(int(_index_by_id.get(actor.person_id, -1)), actor.is_mounted())
		var animation: Animation = editor.animation_player.get_animation(clip)
		if animation == null or animation.length <= 0.0: return {}
		var angle := float(values[16])
		var dx := cos(angle)
		var dy := sin(angle)
		direction = Vector2i(int(signf(dx)), 0) if absf(dx) >= absf(dy) else Vector2i(0, int(signf(dy)))
		var dir := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT].find(direction)
		if dir < 0: return {}
		editor.set_preview_yaw_degrees(YAW[dir])
		editor.set_playing(false)
		editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		time = maxf(0.0, float(native[1]))
		if slot >= 3 and slot <= 8: time = ExchangeTimings.sample_time(clip, time, animation.length)
		else: time = fposmod(time, animation.length) if animation.loop_mode != Animation.LOOP_NONE else minf(time, animation.length)
		editor._on_timeline_changed(time)
	var ground := Vector2(values[14], values[15]) * CELL
	var local: Vector2 = -actor._map_anchor_offset() + actor._attack_offset + actor._stance_offset + lab.terrain.surface_visual_offset_at(ground)
	var origin: Vector2 = actor.get_parent().to_global(ground) + actor.global_transform.basis_xform(local)
	return {"actor": actor, "shift": origin - actor.player_sprite.global_position, "slot": slot, "clip": clip, "time": time, "direction": direction}


func _refresh_kits() -> bool:
	var appearances: Array = []
	var audio_mounts := PackedByteArray()
	_no_atlas.clear()
	var ids: PackedInt64Array = crowd.person_ids()
	for identity in ids:
		var appearance: Dictionary = _appearance(int(identity))
		var drawn: Variant = null if _actors.has(int(identity)) else appearance
		if drawn != null and atlas_cannot_draw(appearance):
			_no_atlas[int(identity)] = true # Kit -1: the person's body draws it, never a substitute look.
			drawn = null
		appearances.append(drawn)
		audio_mounts.append(1 if bool(appearance.get("mounted", false)) else 0)
	_headless_unadmitted_bodied(appearances, ids)
	_kit_appearances = appearances
	return _register_kits(appearances, audio_mounts)


func clear(reserved_empty: TerrainArmy = null, validate_candidate: Callable = Callable()) -> Dictionary:
	if not active: return SiteRuntime.ok()
	if reserved_empty != null and (not lab.combat_armies.has(reserved_empty) or reserved_empty.has_army() or not reserved_empty.combat_units.is_empty()):
		return SiteRuntime.fail("NO_SPACE", "軍營交易的原空隊伍槽已改變")
	if float(lab.terrain.site.get("combat_left", 0.0)) > 0.0 or not lab.site_controller._pending_deaths.is_empty():
		return SiteRuntime.fail("BUSY", "收兵須等脫戰與死亡結算完成")
	var guard := save_guard()
	if not guard.ok: return guard
	if not crowd.peek_events().is_empty():
		return SiteRuntime.fail("BUSY", "收兵須等原生人物事件交接完成")
	var actions: Dictionary = lab.site_controller.person_actions.save_guard()
	if not actions.ok: return actions
	var prepared := ClearHandoff.prepare(self)
	if not prepared.ok: return prepared
	if validate_candidate.is_valid():
		var valid: Dictionary = validate_candidate.call(prepared)
		if not valid.ok: return valid
	prepared.reserved_empty = reserved_empty
	var committed: Dictionary = ClearHandoff.commit(self, prepared)
	if committed.get("ok", false) and not active: _region_mode_follow()
	return committed


## G6: the bound live Region mode follows this crowd (native while active, gd after clear). The crowd change
## itself is already committed; a refused re-activation latches the original step fault instead of a silent mismatch.
func _region_mode_follow() -> void:
	if lab == null or not lab.has_method("region_sync_crowd_mode"): return
	var synced: Dictionary = lab.region_sync_crowd_mode()
	if not synced.get("ok", false) and lab.site_controller != null: lab.site_controller.latch_original_step_fault(synced)


func _clear_mounted_contact_visuals() -> void:
	for prepared: TerrainTestCharacter in _mounted_contact_visuals.values():
		if is_instance_valid(prepared): prepared.free()
	_mounted_contact_visuals.clear()
	_prepared_live_contact_actor_ids.clear()

func _notification(what: int) -> void:
	# Detached load candidates are freed directly by the original Lab guard.
	if what == NOTIFICATION_PREDELETE:
		_clear_mounted_contact_visuals()
		_clear_bodies(false) # The lab may be freeing its children now; queue only.

func _dispose() -> void:
	_audio_mounted_rows.clear()
	_clear_mounted_contact_visuals()
	_clear_bodies()
	_live_contact_actor_ids.clear()
	_clear_siege_work_sprites()
	active = false
	_host_fire_active = false
	_fire_visual_dirty = false
	_kit_ids_dirty = false
	_no_atlas.clear()
	for node: Node in nodes.values(): node.queue_free()
	nodes.clear()
	caps.clear()
	row_sig.clear()
	if is_instance_valid(host): host.queue_free()
	if is_instance_valid(_panel_layer): _panel_layer.queue_free()
	_panel_layer = null
	_summary_text = ""
	host = null
	view = null
	crowd = null
	player_index = -1
	owners.clear()
	_owner_by_id.clear()
	_index_by_id.clear()
	pending_captivity.clear()
	_death_notified.clear()


# ---------------------------------------------------------------- simulation (TerrainLab._advance_combat)
func step(elapsed: float, game_seconds: float, combat_left: float) -> bool:
	if not active:
		return false
	TerrainArmy.begin_contact_step() # Same original shared slice; clear both body query caches once.
	# Optional profile counters (TerrainLab.combat_profile_enabled; never a clock): where a crowd step's wall time goes.
	var prof: int = Time.get_ticks_usec() if lab.combat_profile_enabled else 0
	if not sync_terrain():
		last_event_error = SiteRuntime.fail("INVALID_TERRAIN", "群眾地形更新失敗")
		return false
	_siege_cell_masks.clear()
	var siege_inputs := sync_siege_inputs()
	if not siege_inputs.ok:
		last_event_error = siege_inputs
		return false
	prof = lab._combat_profile_stage("crowd_sync_in", prof)
	if lab.site_controller != null and siege_native_supported():
		lab.site_controller.vehicles.update_siege(elapsed)
		lab._tactical_ai_elapsed += elapsed
		if lab._tactical_ai_elapsed + TerrainLab.ACTION_TIME_EPSILON >= lab.TacticalAI.REVIEW_SECONDS:
			lab._tactical_ai_elapsed = 0.0
			for owner_ref: Variant in owners:
				if owner_ref.has_army() and owner_ref.tactical_ai_enabled: lab.TacticalAI._review_siege(lab, owner_ref)
		lab.site_controller.vehicles.prepare_native_siege_compounds()
		if not sync_terrain(): return false
		siege_inputs = sync_siege_inputs()
		if not siege_inputs.ok:
			last_event_error = siege_inputs
			return false
	prof = lab._combat_profile_stage("crowd_siege_host", prof)
	var started := Time.get_ticks_usec()
	_advance_garrison_returns(elapsed)
	var recovery_input_supported := ClassDB.class_has_method(&"ArmyCrowd", &"set_recovery_input")
	for roster: Dictionary in rosters:
		var multiplier: float = Site.Garrison.recovery_multiplier(lab, str(roster.get("garrison_feature_id", "")), int(roster.faction_id), roster.units)
		if not recovery_input_supported:
			if multiplier <= 1.0: continue # Existing DLLs retain their ordinary step.
			last_event_error = SiteRuntime.fail("CROWD_BUILD_MISMATCH", "群眾模組缺少中式軍營恢復介面；須先更新模組或沿原入口接回一般模式")
			lab.site_controller.show_result(last_event_error)
			return false
		if not bool(crowd.set_recovery_input(int(roster.crowd_formation), multiplier)):
			last_event_error = SiteRuntime.fail("INVALID_GARRISON", "原駐營資格已變更，未套用本步恢復倍率")
			lab.site_controller.show_result(last_event_error)
			return false
	var housing_input_supported := crowd.has_method("set_housing_recovery_input") and crowd.has_method("set_housing_attendance_input")
	if housing_input_supported:
		for attendance: Dictionary in Site.Housing.attendance_input(lab):
			if not bool(crowd.set_housing_attendance_input(int(attendance.unit), int(attendance.cell))):
				last_event_error = SiteRuntime.fail("INVALID_HOUSING", "原住戶本步資格已變更；未套用住宅出席")
				return false
		for roster: Dictionary in rosters:
			var housing_multiplier: float = Site.Housing.recovery_multiplier(lab, roster.units)
			if not bool(crowd.set_housing_recovery_input(int(roster.crowd_formation), housing_multiplier)):
				last_event_error = SiteRuntime.fail("INVALID_HOUSING")
				return false
	elif not lab.terrain.site.get("housing", {}).is_empty():
		last_event_error = SiteRuntime.fail("CROWD_BUILD_MISMATCH", "群眾模組缺少住宅恢復介面")
		lab.site_controller.show_result(last_event_error)
		return false
	var housing_busy: bool = lab.site_controller.person_actions.job_for(int(lab.controlled_person_id())).get("kind", "") == "housing_return"
	crowd.host_input(player_index, 0.0 if housing_busy else wish.x, 0.0 if housing_busy else wish.y, false if housing_busy else running, false if housing_busy else engage)
	if _host_fire_active:
		if not crowd.has_method("set_fire_safe_rest_input"):
			last_event_error = SiteRuntime.fail("CROWD_BUILD_MISMATCH", "群眾模組缺少原火場安全休息輸入")
			return false
		var fire_snapshot: Dictionary = SiteRuntime.fire_hazard_snapshot(lab.terrain) if SiteRuntime.fire_active(lab.terrain) else {}
		for owner_ref: CrowdPersonOwner in owners:
			var fire_safe := owner_ref.fire_safe_rest_input(fire_snapshot)
			if not bool(crowd.set_fire_safe_rest_input(owner_ref.formation_index, fire_safe)):
				last_event_error = SiteRuntime.fail("CROWD_BUILD_MISMATCH", "Native 原隊安全休息輸入失敗")
				return false
			owner_ref.advance_fire_hazard_navigation(fire_snapshot)
	# Hull melee (2026-11-10): aboard people are outside the native spatial hash, so this step's hull contacts are published
	# for the native exchange round (original ship_combat_contact; helm and moving hulls excluded by ship_can_attack).
	var hull_pairs := _aboard_melee_pairs()
	if crowd.has_method("set_aboard_melee_pairs"):
		if not bool(crowd.set_aboard_melee_pairs(hull_pairs)):
			last_event_error = SiteRuntime.fail("NATIVE_REFUSED", "原生拒絕船舷接觸配對")
			return false
	elif not hull_pairs.is_empty():
		last_event_error = SiteRuntime.fail("CROWD_BUILD_MISMATCH", "群眾模組缺少船上近戰輸入")
		return false
	prof = lab._combat_profile_stage("crowd_inputs", prof)
	if _work_fatigue_tick >= 0:
		if not _work_fatigue_ready or absf(elapsed - _work_fatigue_action_seconds) > PersonFatigue.WORK_PLAN_EPS or absf(game_seconds - _work_fatigue_game_seconds) > PersonFatigue.WORK_PLAN_EPS:
			last_event_error = SiteRuntime.fail("CLOCK_NOT_READY", "原 World 同區間全池預檢尚未完成")
			return false
		_audio_native_prepare()
		var accepted: bool = bool(crowd.step_clock_work_point(elapsed, game_seconds, combat_left, _work_fatigue_tick, _work_fatigue_packet)) if _work_fatigue_point_armed \
			else bool(crowd.step_clock_work_plan(elapsed, game_seconds, combat_left, _work_fatigue_tick, _work_fatigue_packet))
		if not accepted:
			last_event_error = SiteRuntime.fail("STALE_NATIVE_WORK_PLAN", "原 World 起點／RUN／分母已變更")
			return false
		if not _work_fatigue_point_armed: clear_work_fatigue_interval()
	else:
		_audio_native_prepare()
		if not bool(crowd.step_clock(elapsed, game_seconds, combat_left)): return false
	prof = lab._combat_profile_stage("crowd_native_step", prof)
	for owner_ref: CrowdPersonOwner in owners: owner_ref.settle_fire_navigation_steps()
	# Advance previously committed corpses only; new deaths retain this slice's event values.
	_advance_dead_person_fatigue(game_seconds)
	_siege_cell_masks.clear()
	if lab.site_controller != null and siege_native_supported():
		lab.site_controller.vehicles.finish_native_siege_compounds()
		siege_inputs = sync_siege_inputs()
		if not siege_inputs.ok: last_event_error = siege_inputs
	_occupancy_cache.clear()
	prof = lab._combat_profile_stage("crowd_post", prof)
	var events_started := Time.get_ticks_usec()
	var mark: float = crowd.combat_mark()
	if mark > 0.0 and lab.terrain != null:
		lab._region_mark_native_work_combat(mark)
	if not work_fatigue_point_active():
		if not _consume_events(): return false
		_battle_tick(combat_left)
		settle_events()
	sync_rider_dismounts()
	prof = lab._combat_profile_stage("crowd_events", prof)
	event_cost_last_us = Time.get_ticks_usec() - events_started
	event_cost_count += 1
	event_cost_total_us += event_cost_last_us
	event_cost_max_us = maxi(event_cost_max_us, event_cost_last_us)
	_step_ms += (Time.get_ticks_usec() - started) / 1000.0
	_steps += 1
	# Native advanced this slice: the vehicle records and their cached native bodies follow it, so the GD view never lags.
	if lab.site_controller != null: lab.site_controller.vehicles.sync_convoy_records()
	lab._combat_profile_stage("crowd_convoy_sync", prof)
	return true

func _advance_garrison_returns(elapsed: float) -> void:
	# Existing native step clock only; original rows retain the registration/home.
	_garrison_return_elapsed += elapsed
	if _garrison_return_elapsed < 0.5: return
	_garrison_return_elapsed = 0.0
	var actions: RefCounted = lab.site_controller.person_actions
	var escort: RefCounted = lab.site_controller.captive_escort
	for roster: Dictionary in rosters:
		var feature_id := str(roster.get("garrison_feature_id", ""))
		if feature_id.is_empty(): continue
		var layout := SiteRuntime.military_layout(lab.terrain, feature_id)
		if not layout.ok or not bool(layout.get("complete", false)): continue
		var participants: Array = []
		for row: Dictionary in roster.units: participants.append(int(row.person_id))
		var contacts: Array[Dictionary] = actions.prison_contacts("", participants)
		for row: Dictionary in roster.units:
			var identity := int(row.person_id)
			if identity == int(lab.controlled_person_id()) or actions.is_busy(identity) or not row.get("work_task", {}).is_empty(): continue
			var person: Dictionary = actions._person(identity)
			if person.is_empty() or not actions._ready(person) or not actions._prison_stopped(person) or layout.walkable_cells.has(lab.terrain.index(person.cell)): continue
			var native_step: PackedInt64Array = crowd.escort_state(int(person.unit))
			if native_step.size() != 2 or int(native_step[0]) == 1 or int(native_step[1]) >= 0: continue
			var saved: Variant = row.get("slot")
			if not saved is Array or saved.size() != 2: continue
			var home := Vector2i(int(saved[0]), int(saved[1]))
			if not layout.walkable_cells.has(lab.terrain.index(home)): continue
			var route: Array[Vector2i] = escort._route(person, home, false, [], contacts)
			if not route.is_empty() and escort._step(person, route[0], 0):
				# Finish this committed edge through the original cancel-to-idle state.
				crowd.cancel_escort(int(person.unit))


# ---------------------------------------------------------------- drawing (TerrainLab._process, every frame)
func render(frame_dt: float) -> void:
	if not active:
		return
	if not sync_terrain(): return
	var p0 := Time.get_ticks_usec()
	# Native acting/current commander changes, new teams and rider changes have no hook; the cheap signature finds them.
	if _body_pending or _body_signature() != _body_sig: _refresh_bodies()
	if not _flush_kit_ids(): return
	_prepare_actor_rows()
	var buf: PackedFloat32Array = crowd.pack_frame(CELL, frame_dt)
	var spans: PackedInt32Array = crowd.row_spans()
	var bounds: PackedFloat32Array = crowd.row_bounds()
	_present_player(frame_dt)
	_present_bodies(frame_dt)
	var p1 := Time.get_ticks_usec()
	var used := {}
	var rows_now := {}
	for s in range(0, spans.size(), 6):
		var row := spans[s]
		var page_index := spans[s + 1]
		var start := spans[s + 2]
		if not rows_now.has(row): rows_now[row] = []
		if page_index < 0:
			rows_now[row].append(-1 - start)
			continue
		var group := spans[s + 5]
		var cap := spans[s + 4]
		var node := _node(group, row, page_index)
		rows_now[row].append(group)
		used[group] = true
		if int(caps[group]) != cap:
			node.multimesh.instance_count = cap
			caps[group] = cap
		var b := int(s / 6.0) * 4
		var margin: float = float(view._pages[page_index].margin)
		node.multimesh.custom_aabb = AABB(Vector3(bounds[b] - margin, bounds[b + 1] - margin, -1.0),
			Vector3(bounds[b + 2] - bounds[b] + 2.0 * margin, bounds[b + 3] - bounds[b + 1] + 2.0 * margin, 2.0))
		RenderingServer.multimesh_set_buffer(node.multimesh.get_rid(), buf.slice(start * 12, (start + cap) * 12))
		node.visible = true
	for key in nodes:
		if not used.has(key):
			nodes[key].visible = false
	for row in row_sig.keys():
		if not rows_now.has(row): row_sig.erase(row)
	for row in rows_now:
		var sig: Array = rows_now[row]
		var old = row_sig.get(row)
		if old is Array and old == sig:
			continue
		row_sig[row] = sig
		for key: int in sig:
			# The host-controlled roster person has a row even when it has no presenter yet (headless, or its body is
			# still being created); there is nothing to order then.
			if key < 0 and -1 - key >= _draw_actors.size(): continue
			var node: Node = _draw_actors[-1 - key] if key < 0 else nodes[key]
			if node.get_parent() == lab:
				lab.move_child(node, -1)
	var p2 := Time.get_ticks_usec()
	_frames += 1
	_pack_ms += (p1 - p0) / 1000.0
	_nodes_ms += (p2 - p1) / 1000.0
	_update_panel(frame_dt)


func summary() -> String:
	return _summary_text if active else ""


# live panel (its own CanvasLayer, bottom): head count, casualties, timings, and the player's input and
# body - so a key that does not arrive, or a run that is not faster, is visible at once
func _update_panel(frame_dt: float) -> void:
	_panel_t += frame_dt
	if _panel_t < 0.25:
		return
	var st: PackedFloat64Array = crowd.hud_stats()
	var n := maxi(1, _frames)
	var fps := float(_frames) / maxf(_panel_t, 0.001)
	_summary_text = "群眾模式 %d 人 | 可戰 %d 倒地 %d 死亡 %d 被俘 %d | 交手 %d | 非法格 %d 非法邊 %d\n" % [
		int(st[0]), int(st[1]) - int(st[2]), int(st[2]), int(st[3]), int(st[4]), int(st[5]), int(st[6]), int(st[7])]
	_summary_text += "每幀 %.1f fps | 模擬 %.2f ms/步 | 打包 %.2f ms | 節點 %.2f ms" % [fps, _step_ms / maxi(1, _steps), _pack_ms / n, _nodes_ms / n]
	var v: PackedFloat32Array = crowd.soldier_view(player_index)
	var state_names := ["站位", "接敵", "交手", "包抄", "射擊", "救人", "俘虜", "倒地", "死亡", "被俘", "起身", "踉蹌", "潰逃", "擊退", "操作中"]
	var slot_names := ["待機", "走", "跑", "攻擊", "重擊", "格擋", "受擊", "擊退", "射擊", "倒下", "昏迷", "起身", "救人"]
	var speed := Vector2(v[9], v[10]).distance_to(_last_player) / maxf(_panel_t, 0.001)
	_last_player = Vector2(v[9], v[10])
	_summary_text += "\n玩家 HP %.0f 暈眩 %.0f | %s／%s | 速度 %.1f 格/秒 | 輸入 方向(%.0f,%.0f) Shift跑:%s 空白鍵出手:%s" % [
		v[5], v[14], state_names[clampi(int(v[7]), 0, state_names.size() - 1)], slot_names[clampi(int(v[3]), 0, slot_names.size() - 1)],
		speed, signf(wish.x), signf(wish.y), "是" if running else "否", "是" if engage else "否"]
	_summary_text += "\nWASD／方向鍵走，按住 Shift 跑，按住空白鍵：攻擊距離內有敵人就停下來交手"
	if is_instance_valid(_panel_label):
		_panel_label.text = _summary_text
	_frames = 0
	_pack_ms = 0.0
	_nodes_ms = 0.0
	_step_ms = 0.0
	_steps = 0
	_panel_t = 0.0


func _make_panel() -> void:
	_panel_layer = CanvasLayer.new()
	_panel_layer.name = "CrowdPanel"
	_panel_layer.layer = 50
	add_child(_panel_layer)
	var box := PanelContainer.new()
	# bottom, right of the Lab's 470-px left panel (the Site banner and FPS sit at the top)
	box.anchor_left = 0.0
	box.anchor_right = 0.0
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = 490.0
	box.offset_bottom = -16.0
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.09, 0.78)
	style.set_content_margin_all(8)
	box.add_theme_stylebox_override("panel", style)
	_panel_layer.add_child(box)
	_panel_label = Label.new()
	_panel_label.add_theme_font_size_override("font_size", 15)
	_panel_label.text = "群眾模式：部署中…"
	box.add_child(_panel_label)


func _node(group: int, row: int, page_index: int) -> MultiMeshInstance2D:
	var node: MultiMeshInstance2D = nodes.get(group)
	if node == null:
		node = MultiMeshInstance2D.new()
		node.name = "CrowdBatch_%d" % group
		node.z_as_relative = false
		node.z_index = row
		node.texture_filter = CharacterRenderContract.TEXTURE_FILTER
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_custom_data = true
		mm.mesh = view._mesh
		node.multimesh = mm
		var page: Dictionary = view._pages[page_index]
		node.texture = page.texture
		node.material = page.material
		lab.add_child(node)
		nodes[group] = node
		caps[group] = 0
	return node


# ---------------------------------------------------------------- the player's presenter
func _begin_player() -> void:
	_adopt_mounted_contact_visuals()
	player_slot = -1
	_anim_t = 0.0
	_actor_slots.clear()


func _prepare_actor_rows() -> void:
	_draw_actors.clear()
	var points := PackedFloat32Array()
	var controlled_actor: TerrainTestCharacter = null
	for identity: int in _actors:
		var actor: TerrainTestCharacter = _actors[identity]
		var index := int(_index_by_id[identity])
		if index == player_index:
			controlled_actor = actor
			continue
		var state := soldier_state(index)
		points.append_array(PackedFloat32Array([float(state.px) * CELL, float(state.py) * CELL]))
		_draw_actors.append(actor)
	# Bodied roster members insert their presenter at their native ground, as actors do. An absent body is not drawn.
	for identity: int in _bodies:
		var body: TerrainTestCharacter = _bodies[identity]
		var index := int(_index_by_id.get(identity, -1))
		if index < 0 or not is_instance_valid(body): continue
		# S1: the original siege work sprite keeps presenting a working person; the body waits hidden meanwhile.
		var shown: bool = _absent_kind(index) == 0 and lab.site_controller.vehicles.siege_work_pose(identity).is_empty()
		body.visible = shown
		if not shown: continue
		if index == player_index:
			controlled_actor = body
			continue
		var state := soldier_state(index)
		points.append_array(PackedFloat32Array([float(state.px) * CELL, float(state.py) * CELL]))
		_draw_actors.append(body)
	points.append_array(_prepare_siege_work_rows())
	crowd.render_set_actors(points)
	if controlled_actor != null: _draw_actors.append(controlled_actor)


# Optional original work sprites use the existing native actor-row insertion
# points. Kit overrides are rendering metadata only, never native people state.
var _siege_work_sprites: Dictionary = {}
var _siege_work_kit_override := false

func _clear_siege_work_sprites() -> void:
	for sprite: Sprite2D in _siege_work_sprites.values():
		if is_instance_valid(sprite): sprite.queue_free()
	_siege_work_sprites.clear()
	_siege_work_kit_override = false

func _prepare_siege_work_rows() -> PackedFloat32Array:
	var points := PackedFloat32Array()
	var current := {}
	var work_indices := {}
	var transport: Variant = lab.site_controller.vehicles
	for vehicle: Dictionary in transport.records().values():
		if not transport.is_siege(vehicle): continue
		for identity: int in vehicle.get("crew_slots", {}).values():
			if not contains_person(identity) or _actors.has(identity): continue
			var work: Dictionary = transport.siege_work_pose(identity)
			if work.is_empty(): continue # Original reaction/KO presentation wins.
			var index := int(_index_by_id[identity])
			var person: Dictionary = siege_original_person(identity)
			if person.is_empty(): continue
			var appearance := _appearance(identity)
			var frame := SiegeWorkAppend.frame(appearance, str(work.clip), DIRS[{Vector2i.UP: 0, Vector2i.RIGHT: 1, Vector2i.DOWN: 2, Vector2i.LEFT: 3}.get(Vector2i(work.facing), 2)], float(work.time))
			var sprite: Sprite2D = _siege_work_sprites.get(identity)
			if sprite == null:
				sprite = Sprite2D.new()
				sprite.name = "OriginalSiegeWorker_" + str(identity)
				sprite.texture_filter = CharacterRenderContract.TEXTURE_FILTER
				sprite.z_as_relative = false
				lab.add_child(sprite)
				_siege_work_sprites[identity] = sprite
			var ground: Vector2 = person.position
			if frame.is_empty() or not SiegeWorkAppend.apply(sprite, appearance, frame):
				sprite.texture = null # Admission failure never masquerades as idle work.
			else:
				sprite.scale = Vector2.ONE * float(frame.map_scale)
				var anchor := Vector2(float(frame.anchor_offset.x), float(frame.anchor_offset.y)) * float(frame.map_scale)
				sprite.position = ground - anchor + lab.terrain.surface_visual_offset_at(ground)
				sprite.z_index = 10 + int(ground.y / CELL)
			current[identity] = true
			work_indices[index] = true
			points.append_array(PackedFloat32Array([ground.x, ground.y]))
			_draw_actors.append(sprite)
	for identity: int in _siege_work_sprites.keys():
		if current.has(identity): continue
		var sprite: Sprite2D = _siege_work_sprites[identity]
		if is_instance_valid(sprite): sprite.queue_free()
		_siege_work_sprites.erase(identity)
	if not work_indices.is_empty() or _siege_work_kit_override:
		# ponytail: the existing full kit submission is copied only while work
		# is visible; optimize sparse kit updates after an actual large-crowd test.
		var render_ids := _render_kit_ids().duplicate()
		for index: int in work_indices: render_ids[index] = -1
		if not bool(crowd.render_set_kits(render_ids)):
			last_event_error = SiteRuntime.fail("INVALID_WORK_RENDER", "原工作圖集索引尚未完整接入")
		_siege_work_kit_override = not work_indices.is_empty()
	return points

func _present_player(dt: float) -> void:
	for identity: int in _actors:
		_present_pose(_actors[identity], identity, int(_index_by_id[identity]), dt, _actor_slots, true)


## S1: bodied roster members take the same pose presentation as actors, one-way from native. No truth is written back:
## only display fields (hp and stun bars, position, pose) change on the presenter.
func _present_bodies(dt: float) -> void:
	for identity: int in _bodies:
		var body: TerrainTestCharacter = _bodies[identity]
		var index := int(_index_by_id.get(identity, -1))
		if index < 0 or not is_instance_valid(body) or not body.visible: continue
		_present_pose(body, identity, index, dt, _body_slots, false)


func _present_pose(actor: TerrainTestCharacter, identity: int, index: int, dt: float, slots: Dictionary, is_actor: bool) -> void:
	var state := soldier_state(index)
	var slot := int(state.vis_kind)
	var age := float(state.vis_age)
	var ground := Vector2(float(state.px), float(state.py)) * CELL
	var angle := float(state.face)
	var dir := posmod(int(round(angle / (PI * 0.5))) + 1, 4)
	if index == player_index:
		var v: PackedFloat32Array = crowd.soldier_view(index)
		ground = Vector2(v[0], v[1])
		slot = int(v[3])
		age = v[4]
		dir = int(v[2])
	else:
		if float(state.hp) <= 0.0 or float(state.ko) > 0.0: slot = 9 if age < 2.875 else 10
		elif float(state.getup) > 0.0: slot = 11
		elif slot < 3 or slot > 8 or age >= ExchangeTimings.duration(StringName(_clip_for(SLOTS[clampi(slot, 0, SLOTS.size() - 1)], actor._saved_appearance))):
			slot = 1 if Vector2(float(state.vx), float(state.vy)).length_squared() > 0.01 else 0
	if is_actor: _sync_actor(identity, false)
	else:
		actor.hp = float(state.hp) # Display bars only; the roster row stays the truth.
		actor.stun = float(state.stun)
	actor.position = ground
	actor.z_index = 10 + int(ground.y / CELL)
	actor.queue_redraw()
	var work: Dictionary = lab.site_controller.vehicles.siege_work_pose(identity)
	if not work.is_empty() and actor.editor != null:
		if SiegeWorkClips.sample(actor.editor, str(work.clip), float(work.time), Vector2i(work.facing)):
			actor.visual_state.animation_id = StringName(str(work.clip))
			actor.visual_state.animation_time = fposmod(float(work.time), float(SiegeWorkClips.DURATIONS[str(work.clip)]))
			actor.set("_exchange_pose_dirty", true)
			actor.editor.preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		slots.erase(identity) # Ordinary poses alone restart the existing visual timer.
		return
	if _live_contact_actor_ids.has(identity):
		var values: PackedFloat64Array = crowd.get_soldier_state(index)
		var native: PackedFloat64Array = crowd.contact_pose_state(index)
		if _sample_prepared_actor_contact(actor, _appearance(identity), values, native).is_empty():
			last_event_error = SiteRuntime.fail("MISSING_ASSET", "Original mounted Actor pose unavailable")
		else:
			actor.set("_exchange_pose_dirty", true)
			actor.editor.preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		return
	if actor.editor != null and SiegeWorkClips.DURATIONS.has(str(actor.editor.selected_animation)):
		actor.editor.combat_ready = actor.combat_ready
		actor.editor.visual_state.combat_ready = actor.combat_ready
		actor.editor._update_weapon_sheath_state()
	var appearance: Dictionary = actor._saved_appearance
	var clip: StringName = StringName(_clip_for(SLOTS[clampi(slot, 0, SLOTS.size() - 1)], appearance))
	if clip in [&"combat_idle", &"combat_walk", &"combat_run"]: clip = StringName(str(clip).trim_prefix("combat_"))
	var previous: Dictionary = slots.get(identity, {"slot": -1, "age": 0.0, "time": 0.0})
	if slot != int(previous.slot) or slot >= 3 and slot <= 8 and age + 0.001 < float(previous.age):
		actor.play_pose(clip)
		previous["time"] = 0.0
	else: previous["time"] = float(previous.time) + dt
	previous["slot"] = slot
	previous.age = age
	slots[identity] = previous
	if actor.editor == null: return
	actor.editor.set_preview_yaw_degrees(YAW[clampi(dir, 0, 3)])
	var animation: Animation = actor.editor.animation_player.get_animation(actor.editor.selected_animation)
	if animation == null or animation.length <= 0.0: return
	var sample := float(previous.time)
	if slot >= 3 and slot <= 8 and ExchangeTimings.duration(clip) > 0.0:
		sample = ExchangeTimings.sample_time(clip, age, animation.length)
	elif animation.loop_mode != Animation.LOOP_NONE: sample = fposmod(sample, animation.length)
	else: sample = minf(sample, animation.length)
	actor.visual_state.animation_time = sample
	actor.set("_exchange_pose_dirty", true)


# ---------------------------------------------------------------- appearance kits (as in the P2 benches)
func _register_reuse_allowed(kit_keys: Array) -> bool:
	# A detached, original owner cannot re-enter through tree/subclass/native callbacks.
	# Unknown extra appearance values retain the complete original serialization path.
	if is_inside_tree() or get_script().get_base_script() != null or not child_order_changed.get_connections().is_empty(): return false
	if crowd == null or crowd.get_class() != "ArmyCrowd" or crowd.get_script() != null: return false
	if not ClassDB.class_exists(&"ArmyIdleKernel"): return false
	var kernel: RefCounted = ClassDB.instantiate(&"ArmyIdleKernel")
	return kernel != null and kernel.has_method("contains_unsupported") and not bool(kernel.contains_unsupported(kit_keys))


func _register_kits(kit_keys: Array, audio_mounts: PackedByteArray = PackedByteArray()) -> bool:
	var reuse := _register_reuse_allowed(kit_keys)
	var registered_keys: Array[String] = []
	var required: Array = []
	var optional: Array = []
	var seen: Dictionary = {}
	var optional_seen: Dictionary = {}
	for appearance: Variant in kit_keys:
		if appearance == null:
			if reuse: registered_keys.append("")
			continue
		var key: String = JSON.stringify(appearance, "", true)
		if reuse: registered_keys.append(key)
		if seen.has(key): continue
		seen[key] = true
		# CAV-3: a rider is admitted by its own complete riding atlas, never by the foot admission (no foot capture is queued).
		if bool(appearance.get("mounted", false)):
			if not SiteMountedSoldierAtlas.available(appearance):
				printerr("Crowd atlas rejected a rider: the mounted soldier atlas is incomplete: ", key)
				return false
			continue
		required.append(appearance)
		var unarmed: Dictionary = appearance.duplicate(true)
		unarmed.parts.weapon = "none"
		unarmed.parts.shield = "none"
		for part: String in ["weapon", "shield"]:
			unarmed.get("equipment_dyes", {}).erase(part)
		if unarmed.get("equipment_dyes", {}).is_empty(): unarmed.erase("equipment_dyes")
		var optional_key: String = JSON.stringify(unarmed, "", true)
		if not optional_seen.has(optional_key):
			optional_seen[optional_key] = true
			optional.append(unarmed)
	var admitted: Dictionary = Atlas.admit_crowd_appearances(required, optional)
	if not admitted.ok:
		printerr("Crowd atlas batch rejected required appearances: ", JSON.stringify(admitted))
		return false
	if is_instance_valid(host): host.queue_free()
	for node: Node in nodes.values(): node.queue_free()
	nodes.clear()
	caps.clear()
	row_sig.clear()
	host = Host.new()
	host.name = "CrowdAtlasHost"
	host._combat_bake = TerrainArmy._combat_bake
	host._soldier_atlas = TerrainArmy._static_soldier_atlas
	host.visible = false
	add_child(host)
	view = BatchView.new()
	host.add_child(view)
	view.setup(host, 64)
	var _mask_refs: Array = view.prewarm_dye_maps(required + optional) if reuse else []
	crowd.render_clear()
	var windows := PackedFloat32Array()
	windows.resize(SLOTS.size())
	var kit_of := {}
	var kit_ids := PackedInt32Array()
	for key in kit_keys:
		if key == null:
			kit_ids.append(-1)
			continue
		var appearance: Dictionary = key
		var k := registered_keys[kit_ids.size()] if reuse else JSON.stringify(appearance)
		if not kit_of.has(k):
			var d: Dictionary = view._describe(appearance)
			if d.is_empty():
				printerr("Crowd atlas rejected person index ", kit_ids.size(), ": ", JSON.stringify(appearance))
				return false
			var kit := _make_kit(int(d.page), int(d.palette), appearance, windows)
			if kit < 0: return false
			kit_of[k] = kit
		kit_ids.append(int(kit_of[k]))
	view._palette_texture.update(view._palette_image)
	crowd.render_set_windows(windows)
	crowd.render_set_bands(4)
	crowd.render_set_filter(true)
	if not missing.is_empty():
		print("crowd10k: clips not on a page (fall back to idle / walk): %s" % [missing])
	_kit_ids = kit_ids
	_kit_cache = kit_of
	_kit_windows = windows
	# Existing validated capture pages/tracks belong to admission, before the
	# first action step. Missing publications remain on the deferred GPU path.
	_prewarm_captivity_atlases(required if reuse else kit_keys, false)
	var installed := bool(crowd.render_set_kits(kit_ids))
	_kit_ids_dirty = not installed
	_body_kits_dirty = not _bodies.is_empty() # Bodies overlay -1 on the next flush; the atlas kit stays their fallback.
	if installed: _audio_mount_install(audio_mounts)
	return installed


func _clip_for(slot: String, appearance: Dictionary) -> String:
	var weapon := StringName(str(appearance.parts.get("weapon", "none")))
	var family = HumanCharacter3DEditor.WeaponMaterials.family(weapon)
	match slot:
		"idle": return "combat_idle"
		"walk": return "combat_walk"
		"run": return "combat_run"
		"attack":
			if family in [&"bow_01", &"crossbow_01"]: return "attack_unarmed"
			return str(HumanCharacter3DEditor.WEAPON_ATTACK_MAP.get(family, &"attack_unarmed"))
		"attack_heavy": return "attack_jump_heavy"
		"guard":
			if str(appearance.parts.get("shield", "none")) == "none" and family not in [&"none", &"bow_01", &"crossbow_01"]:
				return "guard_spear" if HumanCharacter3DEditor.WeaponMaterials.is_polearm(weapon) else "guard_unshielded"
			return "guard"
		"hit": return "hit"
		"knockback": return "knockback"
		"shoot":
			if family == &"bow_01": return "attack_bow"
			if family == &"crossbow_01": return "attack_crossbow"
			return ""
		"down": return "down"
		"unconscious": return "unconscious"
		"get_up": return "get_up"
		"rescue": return "rescue"
	return ""


func _make_kit(page_index: int, palette: int, appearance: Dictionary, windows: PackedFloat32Array) -> int:
	var page: Dictionary = view._pages[page_index]
	var tracks := PackedInt32Array()
	var exchange_slots := ["attack", "attack_heavy", "guard", "hit", "knockback", "shoot"]
	var mounted := bool(appearance.get("mounted", false))
	for si in range(SLOTS.size()):
		var slot: String = SLOTS[si]
		# CAV-3: a rider's page holds the ride clips (SiteMountedSoldierAtlas); slots without one fall back to idle natively.
		# _clip_for stays the foot mapping that contact clocks use.
		var clip := SiteMountedSoldierAtlas.crowd_clip(slot, appearance) if mounted else _clip_for(slot, appearance)
		for dir: String in DIRS:
			var track := -1
			if not clip.is_empty():
				var key := Atlas.normalized_clip(clip) + "|" + dir
				if not page.sequences.has(key) and page.sequences.has(clip + "|" + dir):
					key = clip + "|" + dir
				if page.sequences.has(key):
					var seq: int = int(page.sequences[key])
					var fr: Array = page.samples[seq]
					var times := PackedFloat32Array()
					var anchors := PackedFloat32Array()
					for f: Dictionary in fr:
						times.append(float(f.sample_time))
						anchors.append(float(f.anchor_offset.x) * float(page.scale))
						anchors.append(float(f.anchor_offset.y) * float(page.scale))
					var duration := float(fr[0].duration)
					var loop := float(fr.back().sample_time) < duration - 0.000001
					var time_map := PackedFloat32Array()
					var sample_step := 1.0 / 60.0
					if slot in exchange_slots:
						var window := ExchangeTimings.duration(StringName(clip))
						if window > 0.0:
							if not mounted: windows[si] = window # Slot windows are shared by every kit; riders never redefine them.
							var age := 0.0
							while age <= window + 0.0001:
								time_map.append(ExchangeTimings.sample_time(StringName(clip), age, duration))
								age += sample_step
					track = crowd.render_add_track(seq, duration, loop, times, anchors, time_map, sample_step)
				elif not missing.has(clip):
					missing.append(clip)
			tracks.append(track)
	if windows[SLOTS.find("down")] <= 0.0: windows[SLOTS.find("down")] = 2.875
	if windows[SLOTS.find("get_up")] <= 0.0: windows[SLOTS.find("get_up")] = 2.2
	return crowd.render_add_kit(page_index, palette, float(page.scale), tracks)


func _solo_team_id() -> int:
	var next: int = lab._next_army_identity()
	for team: Dictionary in teams: next = maxi(next, int(team.team_id) + 1)
	return next


func command_teams() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for team: Dictionary in teams:
		if bool(team.solo) or bool(team.get("departed", false)): continue
		var state := formation_state(int(team.formation))
		result.append({"team_id": team.team_id, "formation": team.formation, "faction": team.faction,
			"count": team.person_ids.size(), "ai_enabled": bool(state.ai_enabled),
			"current_commander": int(state.current_person), "routed": bool(state.routed),
			"cavalry": is_cavalry_team(team)})
	return result


# CAV-4b: the same rule as native World::cavalry_formation: able members exist and at least half of them ride.
func is_cavalry_team(team: Dictionary) -> bool:
	var able := 0
	var riding := 0
	for identity: int in team.person_ids:
		if not _index_by_id.has(identity): continue
		var index := int(_index_by_id[identity])
		if not person_owner(identity).combat_can_act(index): continue
		able += 1
		if crowd.soldier_mounted(index): riding += 1
	return able > 0 and riding * 2 >= able


func _team_by_id(identity: int) -> Dictionary:
	for team: Dictionary in teams:
		if int(team.team_id) == identity and not bool(team.get("departed", false)): return team
	return {}


func _command_eligible(state: Dictionary) -> bool:
	var identity := int(state.current_person)
	return _index_by_id.has(identity) and bool(state.commander_present) and person_owner(identity).combat_can_act(int(_index_by_id[identity]))


## G7b: the formation preset of a crowd team, as native slot offsets (lateral, back) in slots, from the same geometry
## the grid planner used (FormationPresetGeometry). "auto" clears the shape (rows as before). The current commander
## orders it (the controlled person for source "player"); a garrisoned, one-person or routed team refuses.
const FormationGeometry = preload("res://scripts/terrain_lab/formation_preset_geometry.gd")

static func preset_offsets(preset_id: String, count: int) -> PackedFloat32Array:
	var offsets := PackedFloat32Array()
	if preset_id == "auto": return offsets
	# Facing RIGHT maps a local (lateral u, forward v) cell to (x = v, y = u); native back is -forward.
	for cell: Vector2i in FormationGeometry.shape_slots(preset_id, count, Vector2i.ZERO, Vector2i.RIGHT):
		offsets.append(float(cell.y))
		offsets.append(float(-cell.x))
	return offsets

func set_team_preset(team_id: int, preset_id: String, source: String = "ui") -> Dictionary:
	if not active or crowd == null: return SiteRuntime.fail("UNSUPPORTED", "群眾未啟用")
	if not FormationGeometry.is_valid_preset(preset_id): return SiteRuntime.fail("BAD_ARGS", "未知的陣形")
	if not crowd.has_method("set_formation_shape"): return SiteRuntime.fail("UNSUPPORTED", "原生群眾未提供陣形")
	var team := _team_by_id(team_id)
	if team.is_empty(): return SiteRuntime.fail("BAD_FORMATION")
	var formation := int(team.formation)
	var state := formation_state(formation)
	if bool(state.no_orders): return SiteRuntime.fail("NO_ORDERS", "一人隊伍由本人操作，不接受隊伍軍令")
	if not _command_eligible(state) or (source == "player" and int(state.current_person) != int(lab.controlled_person_id())):
		return SiteRuntime.fail("NO_AUTHORITY", "只有當前在場指揮者可下令或切換自主指揮")
	if bool(state.routed): return SiteRuntime.fail("ROUTED", "隊伍尚未完成安全整補與重新集結")
	if bool(crowd.get_garrisoned(formation)): return SiteRuntime.fail("BUSY", "駐營隊伍不能改陣")
	var count := int(team.get("person_ids", []).size())
	var offsets := preset_offsets(preset_id, count)
	if preset_id != "auto" and offsets.size() != 2 * count: return SiteRuntime.fail("TOO_LARGE", "此陣形容納不下全隊（上限 200 人）")
	if not bool(crowd.set_formation_shape(formation, offsets)): return SiteRuntime.fail("NATIVE_REFUSED", "原生群眾拒絕此陣形；未改陣")
	_team_presets[team_id] = preset_id
	return SiteRuntime.ok("已改為%s" % preset_id, {"preset": preset_id})

## The UI label only; the native shape is the saved truth (a loaded Site shows "auto" until the next change).
var _team_presets := {}

func team_preset(team_id: int) -> String:
	return str(_team_presets.get(team_id, "auto"))

func issue_order(team_id: int, kind: int, goal: Vector2i = Vector2i(-1, -1), target_id: int = -1, source: String = "ui", facing: Vector2i = Vector2i.ZERO) -> Dictionary:
	var team := _team_by_id(team_id)
	if team.is_empty(): return SiteRuntime.fail("BAD_FORMATION")
	# As TerrainArmy.issue_combat_order: no team order while a cross-Site or ship-transfer operation is pending, and none for
	# a team on a coarse ship journey (found 2026-11-08 porting site_ship_journey_edge: the crowd accepted a shore MOVE
	# during a pending cold replay).
	var controller: Variant = lab.site_controller
	if controller != null:
		if controller.has_method("region_operation_pending") and controller.region_operation_pending(): return SiteRuntime.fail("BUSY", "原跨區或船隊交接尚未完成")
		if controller.has_method("ship_person_in_journey"):
			for identity: Variant in team.get("person_ids", []):
				if controller.ship_person_in_journey(int(identity)): return SiteRuntime.fail("BUSY", "船隊旅程中不能改現場冷軍令")
	var formation := int(team.formation)
	var native_kind: int = {TerrainArmy.CombatOrder.HOLD: 0, TerrainArmy.CombatOrder.MOVE: 1,
		TerrainArmy.CombatOrder.ATTACK: 2, TerrainArmy.CombatOrder.RETREAT: 3, TerrainArmy.CombatOrder.PURSUE: 4,
		TerrainArmy.CombatOrder.CHARGE: 5, TerrainArmy.CombatOrder.RALLY: 6}.get(kind, -1)
	if native_kind < 0: return SiteRuntime.fail("BAD_ARGS")
	var state := formation_state(formation)
	if bool(state.no_orders): return SiteRuntime.fail("NO_ORDERS", "一人隊伍由本人操作，不接受隊伍軍令")
	# Preserve the ordinary UI's rejection order before touching native ownership.
	if native_kind == 3 and not bool(state.routed): return SiteRuntime.fail("NOT_ROUTED", "士氣尚未崩潰，隊長不能下令撤退")
	if not _command_eligible(state) or (source == "player" and int(state.current_person) != int(lab.controlled_person_id())):
		return SiteRuntime.fail("NO_AUTHORITY", "只有當前在場指揮者可下令或切換自主指揮")
	if bool(state.routed) and native_kind in [1, 2, 4, 5]: return SiteRuntime.fail("ROUTED", "隊伍尚未完成安全整補與重新集結；只能守位自衛或撤退")
	# CAV-4b: a picked enemy person turns CHARGE into a formation charge on that enemy's formation (native kind 7).
	var charge_formation := -1
	if native_kind == 5 and target_id >= 0:
		if not _index_by_id.has(target_id): return SiteRuntime.fail("NO_TARGET")
		var charge_owner = person_owner(target_id)
		if charge_owner.faction_id == int(team.faction) or not charge_owner.combat_can_act(int(_index_by_id[target_id])): return SiteRuntime.fail("NO_TARGET")
		charge_formation = int(charge_owner.formation_index)
		native_kind = 7
	if native_kind in [1, 5] and not lab.terrain.is_walkable(goal): return SiteRuntime.fail("BLOCKED")
	var target := int(_index_by_id.get(target_id, -1))
	if target < 0 and native_kind == 2 and target_id == -1:
		target = int(crowd.nearest_enemy(int(_index_by_id[int(state.current_person)]), 400.0))
	if native_kind in [2, 4]:
		if target < 0: return SiteRuntime.fail("NO_TARGET")
		var identity := int(crowd.person_ids()[target])
		var target_owner = person_owner(identity)
		if target_owner.faction_id == int(team.faction) or not target_owner.combat_can_act(target): return SiteRuntime.fail("NO_TARGET")
		if native_kind == 4:
			var target_state := soldier_state(target)
			var reference := Vector2(float(state.ref_x), float(state.ref_y)) if bool(state.ref_valid) else Vector2(float(state.cx), float(state.cy))
			if reference.distance_to(Vector2(float(target_state.px), float(target_state.py))) > 20.0: return SiteRuntime.fail("NO_TARGET")
	var was_ai := bool(state.ai_enabled)
	var manual := source in ["ui", "trial", "test", "player"]
	if manual and was_ai: crowd.set_order_owner(formation, false)
	order_calls += 1
	# x is the target for kinds 2/4, the enemy formation for 7, and carries no angle for the CAV-4b point charge (5) or RALLY (6).
	var value := float(state.facing)
	if native_kind in [2, 4]: value = float(target)
	elif native_kind == 7: value = float(charge_formation)
	elif native_kind in [5, 6]: value = 0.0
	elif facing != Vector2i.ZERO: value = Vector2(facing).angle()
	var code := test_order_failure if test_order_failure >= 0 else int(crowd.order(formation, native_kind, goal.x + 0.5, goal.y + 0.5, value))
	if code != 0 and manual and was_ai: crowd.set_order_owner(formation, true)
	return SiteRuntime.ok() if code == 0 else SiteRuntime.fail(RESULT_CODES[clampi(code, 0, RESULT_CODES.size() - 1)])


func set_team_ai(team_id: int, enabled: bool) -> Dictionary:
	var team := _team_by_id(team_id)
	if team.is_empty(): return SiteRuntime.fail("BAD_FORMATION")
	var state := formation_state(int(team.formation))
	if bool(state.no_orders): return SiteRuntime.fail("NO_ORDERS", "一人隊伍由本人操作，不接受隊伍軍令")
	if not _command_eligible(state): return SiteRuntime.fail("NO_AUTHORITY", "只有當前在場指揮者可下令或切換自主指揮")
	crowd.set_order_owner(int(team.formation), enabled)
	return SiteRuntime.ok()


func team_summary(team_id: int) -> String:
	var team := _team_by_id(team_id)
	if team.is_empty(): return ""
	var state := formation_state(int(team.formation))
	return _team_summary_text(team_id, state)


func team_summaries() -> PackedStringArray:
	var result := PackedStringArray()
	var can_batch := get_script().get_base_script() == null and crowd != null and crowd.get_class() == "ArmyCrowd" and crowd.get_script() == null
	var seen := {}
	if can_batch:
		for team: Dictionary in teams:
			var identity := int(team.team_id)
			if seen.has(identity): can_batch = false
			seen[identity] = true
	if not can_batch:
		for team: Dictionary in command_teams(): result.append(team_summary(int(team.team_id)))
		return result
	for team: Dictionary in teams:
		if bool(team.solo) or bool(team.get("departed", false)): continue
		result.append(_team_summary_text(int(team.team_id), formation_state(int(team.formation))))
	return result


static func _team_summary_text(team_id: int, state: Dictionary) -> String:
	return "隊伍 #%d｜%s｜指揮 #%d｜命令 %d｜士氣 %.1f｜疲勞 %.1f%s" % [team_id,
		"AI" if bool(state.ai_enabled) else "手動", int(state.current_person), int(state.order), float(state.morale), float(state.fatigue), "｜潰逃" if bool(state.routed) else ""]


func on_control_changed(old_identity: int, identity: int) -> Dictionary:
	if not contains_person(identity):
		var actor := _actor(identity)
		if actor == null: return SiteRuntime.fail("INVALID", "繼承人不在原 Site")
		var appended := _append_actor(actor)
		if not appended.ok: return appended
	if contains_person(old_identity):
		crowd.host_input(int(_index_by_id[old_identity]), 0.0, 0.0, false, false)
		var old_owner = person_owner(old_identity)
		if bool(_team_by_id(old_owner.team_id).get("solo", false)):
			set_formation_fields(old_owner.formation_index, {"host_center": false})
	player_index = int(_index_by_id[identity])
	crowd.set_host_control(player_index, true)
	var next_owner = person_owner(identity)
	if bool(_team_by_id(next_owner.team_id).get("solo", false)):
		set_formation_fields(next_owner.formation_index, {"host_center": true})
	wish = Vector2.ZERO
	running = false
	engage = false
	_begin_player()
	_refresh_bodies(identity) # The controlled roster member is bodied; the old one keeps a body only by rank.
	return SiteRuntime.ok()


# Owner decision 2026-10-31: a crowd person is fighting when his native contact state is fight (交手, 2) or shoot
# (射擊, 4), or an exchange timer (stun, stagger, knock, action) is running. Engage (接敵, 1) is an approach, not an
# exchange: every soldier of a battle reads engage from afar, so it does not refuse equipment.
func person_fighting(identity: int) -> bool:
	if not contains_person(identity): return false
	var index := int(_index_by_id[identity])
	var state := soldier_state(index)
	if state.is_empty(): return true
	for field: String in ["stun", "stagger", "knock_t", "act_t"]:
		if float(state.get(field, 0.0)) > 0.0: return true
	if not crowd.has_method("contact_pose_state"): return true
	var native: PackedFloat64Array = crowd.contact_pose_state(index)
	return native.size() != 2 or int(native[0]) in [2, 4]


func equipment_recipe_guard(identity: int, appearance: Dictionary) -> Dictionary:
	if not HumanCharacter3DEditor.valid_appearance(appearance): return SiteRuntime.fail("INVALID")
	if _actor(identity) != null: return SiteRuntime.ok() # Original actors retain their live presenter.
	if bool(appearance.get("mounted", false)):
		if not SiteMountedSoldierAtlas.available(appearance): return SiteRuntime.fail("MISSING_ASSET", "騎乘圖集未備妥；原裝與物品保留")
		if not TerrainArmy.prepare_contact_source_for(appearance): return SiteRuntime.fail("MISSING_ASSET", "騎乘接觸資源未備妥；原裝與物品保留")
	# S2: a look the atlas cannot draw is admitted; its person becomes bodied (kit -1) instead of being refused.
	if view != null and not atlas_cannot_draw(appearance) and view._describe(appearance).is_empty(): return SiteRuntime.fail("MISSING_ASSET", "士兵外觀不被圖集接受")
	return SiteRuntime.ok()


func equipment_changed(identity: int) -> void:
	if not contains_person(identity): return
	var appearance := _appearance(identity)
	if appearance.is_empty():
		last_event_error = SiteRuntime.fail("INVALID", "人物實物外觀不完整")
		return
	crowd.set_soldier_equip(int(_index_by_id[identity]), _packed_equip(appearance))
	var family := WeaponMaterials.family(StringName(str(appearance.parts.weapon)))
	if family in [&"bow_01", &"crossbow_01"]:
		_ammo_keys[identity] = "arrow" if family == &"bow_01" else "bolt"
	if _actors.has(identity):
		var actor: TerrainTestCharacter = _actors[identity]
		actor._saved_appearance = appearance
		if actor.editor != null: actor.editor.restore_appearance(appearance)
		_audio_mount_update(int(_index_by_id[identity]), bool(appearance.get("mounted", false)))
	elif not _building:
		_update_kit(int(_index_by_id[identity]), appearance, identity) # The atlas kit stays current as a bodied person's fallback.
		_redress_body(identity, appearance)
	_sync_native_mount(identity, appearance)


# CAV-3: after a committed equipment change, the native rider flag follows the projected appearance.
# The order guard (equipment_recipe_guard) already admitted the atlas and contact source.
func _sync_native_mount(identity: int, appearance: Dictionary) -> void:
	if crowd == null or _building: return
	var index := int(_index_by_id.get(identity, -1))
	if index < 0 or float(soldier_state(index).hp) <= 0.0: return
	var on := bool(appearance.get("mounted", false))
	if bool(crowd.soldier_mounted(index)) == on: return
	if on and _actors.has(identity):
		var actor: TerrainTestCharacter = _actors[identity]
		if actor.editor != null and actor.editor.is_mounted: _live_contact_actor_ids[identity] = true
	if not bool(crowd.set_soldier_mounted(index, on)):
		last_event_error = SiteRuntime.fail("NATIVE_REFUSED", "原生群眾拒絕騎乘狀態")
		return
	_rebuild_rider_ids()


func captivity_changed(identity: int, _captor_id: int, _capturing: bool) -> void:
	# Queued native events may already include a later escape/death. Never rewind hot flags.
	if _actors.has(identity): _sync_actor(identity)


func _sync_ammo(identity: int, state: Dictionary = {}) -> void:
	if not contains_person(identity): return
	if _host_fire_active: return # Native host commit already debited the selected original cargo key.
	var person_source = person_owner(identity)
	var index := int(_index_by_id[identity])
	var person: Dictionary = person_source.person(index)
	if person.is_empty() or bool(person_source.combat_hot_get(index, &"loot_settled", false)): return
	var key := str(_ammo_keys.get(identity, ""))
	if key.is_empty(): return
	var amount := int(state.ammo if not state.is_empty() else soldier_state(index).ammo)
	if amount > 0: person.cargo[key] = amount
	else: person.cargo.erase(key)


func _consume_events() -> bool:
	if work_fatigue_point_active(): return _consume_events_original()
	var audio_snapshot := _audio_native_snapshot()
	var succeeded := _consume_events_original()
	if succeeded: _audio_native_deliver(audio_snapshot)
	return succeeded


## --- Battle log and personal records (Nekki 2026-11-05) ---
var battle = preload("res://scripts/terrain_lab/site_battle_tracker.gd").new()
var _battle_sample := 0

func _faction_of_person(identity: int) -> int:
	var owner: Variant = _owner_by_id.get(identity)
	return int(owner.faction_id) if owner != null else -1

func _battle_now() -> float:
	var controller: Variant = lab.site_controller if is_instance_valid(lab) else null
	if controller != null and controller.region_slot != null: return float(controller.region_slot.control.logical_game_seconds)
	return float(lab.terrain.site.get("minute", 0)) * 60.0

func _battle_event(kind: int, identity: int, other: int) -> void:
	if not battle.open: return
	var striker := -1
	if kind in [0, 1] and _index_by_id.has(identity) and crowd.has_method("last_striker"): striker = int(crowd.last_striker(int(_index_by_id[identity])))
	var rank: String = lab.site_controller.peerage_rank_of(identity) if lab.site_controller.has_method("peerage_rank_of") else ""
	battle.on_event(kind, identity, _faction_of_person(identity), striker, _faction_of_person(striker), other if kind == 4 else -1,
		_faction_of_person(other) if kind == 4 else -1, rank != "" and rank != "none")

func _battle_tick(combat_left: float) -> void:
	var now := _battle_now()
	var combat_on := combat_left > 0.0
	if not battle.open:
		if not combat_on: return
		battle.begin(str(lab.terrain.site.get("id", "")), now)
		_battle_sample = 0
		_arrears_morale()
	if combat_on:
		_battle_sample += 1
		if _battle_sample % 120 == 1:
			for identity: Variant in _index_by_id.keys():
				if person_fighting(int(identity)): battle.join(int(identity), _faction_of_person(int(identity)))
	if battle.tick(combat_on, now) and lab.site_controller.has_method("close_battle"):
		lab.site_controller.close_battle(battle, now)


## 軍餉與稅收 P5 (§6.1, adapted: crowd morale is per team): when a battle opens, each team's morale is multiplied by
## SitePayroll.morale_factor of its members' mean unpaid paydays owed by that team (×0.9 per payday, at least ×0.7).
func _arrears_morale() -> void:
	var site_id := str(lab.terrain.site.get("id", ""))
	for owner: Variant in lab.team_owners():
		if not is_instance_valid(owner) or int(owner.get("formation_index")) < 0: continue
		var key := "team:%s:%d" % [site_id, int(owner.team_id)]
		var periods := 0
		var members := 0
		for unit: Variant in owner.combat_units.keys():
			if not owner.is_member(int(unit)) or owner.member_gone(int(unit)): continue
			members += 1
			periods += int(PersonSocialPacket.arrears_for(owner.combat_units[unit], key).periods)
		if members == 0 or periods == 0: continue
		var factor: float = (load("res://scripts/terrain_lab/site_payroll.gd") as Script).call("morale_factor", float(periods) / float(members))
		var state := team_morale_of(int(owner.formation_index))
		if state.is_empty(): continue
		state["morale"] = clampf(float(state.morale) * factor, 0.0, 100.0)
		apply_team_morale(crowd, int(owner.formation_index), state)

func _freeze_dead_person_fatigue(identity: int, value: float, rested: float) -> void:
	# Native already decremented its formation count. Keep the same original body;
	# detach a suspended GD pool before writing the true values from that death event.
	if _actors.has(identity):
		var actor: TerrainTestCharacter = _actors[identity]
		actor._fatigue_pool = {}
		actor.fatigue = value
		actor.fatigue_rest = rested
	else:
		var row: Dictionary = _records[identity]
		row.erase("_fatigue_pool")
		row["fatigue"] = value
		row["fatigue_rest"] = rested


func _advance_dead_person_fatigue(seconds: float) -> void:
	if seconds <= 0.0: return # PersonFatigue preserves both values for a zero game slice.
	for identity: int in _death_notified:
		if not _index_by_id.has(identity): continue
		var state: Dictionary = soldier_state(int(_index_by_id[identity]))
		if float(state.hp) > 0.0: continue
		var body: Variant = _actors.get(identity, _records.get(identity))
		if body == null: continue
		var value: float = D5Fatigue.read(body)
		var rested: float = D5Fatigue.read(body, "fatigue_rest")
		var advanced: Array[float] = D5Fatigue.advance(value, rested, seconds, 0.0, false)
		D5Fatigue.write(body, "fatigue", advanced[0])
		D5Fatigue.write(body, "fatigue_rest", advanced[1])


func settle_events() -> void:
	# Only this synchronous call shares the already-committed native person view.
	# No context is stored on the Site, pending events or supply owner.
	var event_context := {}
	if not pending_captivity.is_empty():
		event_context = {"site": lab.terrain.site, "terrain": lab.terrain, "native": crowd,
			"step": _steps, "at": SiteRuntime.now(lab.terrain) * 60.0}
	var blocked := {}
	var remaining: Array[Dictionary] = []
	for event: Dictionary in pending_captivity:
		var identity := int(event.person)
		if blocked.has(identity):
			remaining.append(event)
			continue
		var result := _commit_captivity(event, event_context)
		if not result.ok:
			blocked[identity] = true
			remaining.append(event)
			last_event_error = result
	pending_captivity = remaining
	event_context.clear()
	if remaining.is_empty(): last_event_error = {}


func _commit_captivity(event: Dictionary, event_context: Dictionary = {}) -> Dictionary:
	var identity := int(event.person)
	var capturing := int(event.kind) == 4
	var controller = lab.site_controller
	var person: Dictionary = person_owner(identity).person(int(_index_by_id[identity]))
	if person.is_empty(): return SiteRuntime.fail("INVALID", "俘虜原持物不存在")
	var selected := {}
	if capturing:
		selected = controller.person_actions._sealed_selection(person)
		var visual := _captivity_atlas_guard(identity, _captivity_appearance(identity, person.holder, selected.item_ids))
		if not visual.ok: return visual
	if capturing and not bool(event.ammo_synced):
		_sync_ammo(identity)
		event["ammo_synced"] = true
	var relations: Dictionary = lab.terrain.site.captivity
	var captor := int(event.other) if capturing else int(relations.get(str(identity), {}).get("captor_id", -1))
	var guard: Dictionary = controller.captivity_supply.event_change_guard(identity, captor, capturing, event_context)
	if not guard.ok: return guard
	var container := ""
	if capturing:
		selected = controller.person_actions._sealed_selection(person) # Ammo was synchronized above.
		if not selected.item_ids.is_empty() or not selected.resources.is_empty():
			var sealed := SiteRuntime.fail("TEST_SEAL_FAILURE") if test_seal_failure else SiteRuntime.leave_ground_loot(lab.terrain, person.holder, person.cargo, identity, person.cell, "sealed", selected.resources, selected.item_ids, int(person.holder.version))
			if not sealed.ok:
				controller.captivity_supply.discard(identity)
				return sealed
			container = str(sealed.container_id)
		crowd.set_soldier_ammo(int(_index_by_id[identity]), 0)
		var captor_person: Dictionary = controller.person_actions._person(captor)
		relations[str(identity)] = {"version": 3, "captor_id": captor, "guard_id": captor,
			"captor_faction": int(captor_person.faction), "sealed_container": container, "prison_id": ""}
		relations[str(identity)].merge(controller.person_actions.capture_fields(identity, person)) # Plan 4.2 / 6.1.
		# The Site's capture episode counter advances once per committed capture, as the GD custody commit does
		# (site_person_actions: capture_episode_next = sequence + 1; found 2026-11-09: a crowd capture left it unchanged).
		lab.terrain.site["capture_episode_next"] = int(lab.terrain.site.get("capture_episode_next", 1)) + 1
	else:
		relations.erase(str(identity))
	person.holder.version = int(person.holder.version) + 1
	controller.captivity_supply.commit_change(identity, captor, capturing)
	equipment_changed(identity)
	captivity_changed(identity, captor, capturing)
	return SiteRuntime.ok()


func _prewarm_captivity_atlases(appearances: Array = [], prepare_missing: bool = true) -> void:
	if view == null or crowd == null: return
	if appearances.is_empty():
		if not active or not is_instance_valid(lab): return
		appearances = _kit_appearances
		if appearances.is_empty():
			# Load admission already populated the original records, not the deploy array.
			appearances = []
			for identity: int in _records:
				if not _actors.has(identity): appearances.append(_appearance(identity))
	var seen := {}
	for value: Variant in appearances:
		if not value is Dictionary or value.is_empty(): continue
		var appearance: Dictionary = value.duplicate(true)
		for slot: String in ["weapon", "shield"]:
			appearance.parts[slot] = "none"
			if appearance.has("equipment_dyes"): appearance.equipment_dyes.erase(slot)
		if appearance.has("equipment_dyes") and appearance.equipment_dyes.is_empty(): appearance.erase("equipment_dyes")
		# Full appearances retain distinct faction dye palettes on the same page.
		var key := JSON.stringify(appearance)
		if seen.has(key): continue
		seen[key] = true
		if _ensure_kit(appearance) >= 0: continue
		if prepare_missing and active and DisplayServer.get_name() != "headless":
			# No event/person is created. The existing cache job serves later capture.
			_captivity_atlas_guard(-1, appearance)


func _captivity_appearance(identity: int, holder: Dictionary, sealed_ids: Array) -> Dictionary:
	var projected := holder.duplicate(true)
	for slot: String in projected.equipped.keys():
		if sealed_ids.has(projected.equipped[slot]): projected.equipped.erase(slot)
	return SiteRuntime.equipment_appearance(lab.terrain, projected, _appearance(identity))


func _captivity_atlas_guard(identity: int, appearance: Dictionary) -> Dictionary:
	if appearance.is_empty(): return SiteRuntime.fail("INVALID", "俘虜卸裝後的原持物外觀不完整")
	if _actors.has(identity): return SiteRuntime.ok() # Original actors keep their live presenter.
	# A crowd with no batch view (an off-screen cold owner) draws nobody, so no published look can ever be admitted here;
	# its capture commits on mechanics alone and the look is prepared when the Site is shown (found 2026-11-09: a cold
	# center owner's battlefield capture never committed, even with the look published in the runtime cache).
	if view == null: return SiteRuntime.ok()
	if _ensure_kit(appearance) >= 0: return SiteRuntime.ok()
	if bool(appearance.get("mounted", false)): return SiteRuntime.fail("MISSING_ASSET", "騎乘圖集未備妥；不排入步兵圖集準備，原實物保留")
	var key := Atlas._mixed_key(appearance)
	if key.is_empty(): return SiteRuntime.fail("MISSING_ASSET", "俘虜卸裝外觀無精確圖集配方；原實物保留")
	var job: Dictionary = _captivity_atlas_jobs.get(key, {})
	if not job.is_empty() and (not is_same(job.data, lab.terrain) or not is_same(job.site, lab.terrain.site) or not is_same(job.native, crowd)):
		_captivity_atlas_jobs.erase(key)
		job = {}
	if not job.is_empty():
		return SiteRuntime.fail("BUSY", "正在準備俘虜卸裝圖集；原實物保留") if job.state == "preparing" else SiteRuntime.fail("MISSING_ASSET", "俘虜卸裝圖集準備失敗或仍未通過呈現驗證；原實物保留")
	# Nekki 2026-10-27 (NEKKI_DECISION_20261027T0428Z_custody_crossing_center): a headless run treats the captive atlas
	# check as mechanics-only, like the siege-work asset check; nothing is drawn there. A headless crowd cannot read a
	# published look either (found 2026-11-09: the look published by scripts/tools/bake_captivity_appearances.gd in a
	# visual run was still not admitted headless), so it refused every headless battlefield capture.
	if DisplayServer.get_name() == "headless":
		return SiteRuntime.ok()
	job = {"state": "preparing", "data": lab.terrain, "site": lab.terrain.site, "native": crowd}
	_captivity_atlas_jobs[key] = job
	_prepare_captivity_atlas.call_deferred(key, appearance.duplicate(true), job)
	return SiteRuntime.fail("BUSY", "正在準備俘虜卸裝圖集；原實物保留")


func _prepare_captivity_atlas(key: String, appearance: Dictionary, job: Dictionary) -> void:
	if not _captivity_atlas_context(key, job): return
	var complete: bool = await prepare_captivity_recipe(lab, appearance)
	# An old scene's completion may populate the shared validated cache only.
	if not _captivity_atlas_context(key, job): return
	job["state"] = "ready" if complete and _ensure_kit(appearance) >= 0 else "failed"
	# No item/event commit here. settle_events rechecks the current person and supply.


static func prepare_captivity_recipe(capture_host: Node, appearance: Dictionary) -> bool:
	# Reuse the Atlas cache/capture owner. A supported legacy multi-page recipe
	# still needs its exact single-page publication for the crowd batch renderer.
	if not Atlas.supports(appearance): return await Atlas.prepare_recipe(capture_host, appearance)
	if not Atlas.mixed_recipe(appearance).is_empty() and not Atlas.dye_entry(appearance).is_empty(): return true
	var plan := Atlas.mixed_plan(appearance)
	if plan.is_empty() or not is_instance_valid(capture_host) or not capture_host.is_inside_tree() or DisplayServer.get_name() == "headless": return false
	var tree := capture_host.get_tree()
	var deadline := Time.get_ticks_msec() + 600000
	while is_instance_valid(Atlas._preparation):
		if Time.get_ticks_msec() >= deadline or not is_instance_valid(capture_host) or not capture_host.is_inside_tree(): return false
		await tree.process_frame
		if not is_instance_valid(capture_host) or not capture_host.is_inside_tree() or capture_host.is_queued_for_deletion(): return false
		if not Atlas.mixed_recipe(appearance).is_empty() and not Atlas.dye_entry(appearance).is_empty(): return true
	if not is_instance_valid(capture_host) or not capture_host.is_inside_tree() or capture_host.is_queued_for_deletion(): return false
	var directory := Atlas._mixed_directory(str(plan.key))
	if directory.is_empty(): return false
	var script := load(Atlas.MIXED_CAPTURE) as Script
	if script == null: return false
	var capture := script.new() as Node
	if capture == null: return false
	Atlas._preparation = capture
	capture_host.add_child(capture)
	var complete: bool = await capture.capture(plan, directory, Atlas._mixed_sources.duplicate(), Atlas.DyeAtlas.fingerprints())
	if is_instance_valid(capture): capture.queue_free()
	Atlas._preparation = null
	Atlas._mixed_missing.erase(str(plan.key))
	return complete and not Atlas.mixed_recipe(appearance).is_empty() and not Atlas.dye_entry(appearance).is_empty()


func _captivity_atlas_context(key: String, job: Dictionary) -> bool:
	return active and is_instance_valid(lab) and not is_queued_for_deletion() and is_same(_captivity_atlas_jobs.get(key), job) and is_same(lab.terrain, job.data) and is_same(lab.terrain.site, job.site) and is_same(crowd, job.native)


func _sync_actor(identity: int, handoff: bool = true, state: Dictionary = {}, formation: Dictionary = {}) -> void:
	var actor: TerrainTestCharacter = _actors[identity]
	if state.is_empty(): state = soldier_state(int(_index_by_id[identity]))
	var person_source = person_owner(identity)
	if formation.is_empty(): formation = formation_state(person_source.formation_index)
	actor.hp = float(state.hp)
	actor._received_effective_hit = int(state.hit_revision)
	actor.military_role = military_role_name(int(state.military_role))
	actor.stun = float(state.stun)
	actor.stun_grace = float(state.grace)
	actor.knockout_left = float(state.ko)
	actor._getting_up = float(state.getup) > 0.0
	actor.captive = bool(state.captive)
	actor.exchange_stagger = float(state.stagger)
	actor.exchange_cooldown = float(state.exch_cd)
	actor.ranged_cooldown = float(state.ranged_cd)
	actor.exchange_skill_cooldown = float(state.skill_cd)
	if actor.hp > 0.0:
		actor.fatigue = float(formation.fatigue)
		actor.fatigue_rest = float(formation.fatigue_rest)
	actor.training = float(formation.training)
	actor.position = Vector2(float(state.px), float(state.py)) * CELL
	# Cell is derived from native doubles, never from the rounded presentation position.
	actor.terrain_cell = Vector2i(floori(float(state.px)), floori(float(state.py)))
	var direction := Vector2.from_angle(float(state.face))
	actor.facing = Vector2i(int(signf(direction.x)), 0) if absf(direction.x) > absf(direction.y) else Vector2i(0, int(signf(direction.y)))
	actor.command_abilities = _handoff_abilities(state)
	actor.action_time = float(state.getup) if actor._getting_up else (0.0 if actor.hp <= 0.0 or actor.knockout_left > 0.0 else float(state.stagger))
	if actor.hp <= 0.0 or actor.knockout_left > 0.0: actor.guarding = false
	if handoff:
		var extra := {"version": 1, "bandaged": bool(state.bandaged), "escape_t": float(state.escape_t), "role": int(state.role)}
		for key: String in ["face", "knock_t", "act_t", "stagger", "exch_cd", "ranged_cd", "skill_cd"]:
			extra[key] = float(state[key])
		if bool(_team_by_id(person_source.team_id).get("solo", false)):
			extra["solo_formation"] = _formation_handoff_snapshot(formation)
		actor.set_meta(&"crowd_handoff", extra)


static func _handoff_abilities(state: Dictionary) -> Dictionary:
	if int(state.tactics) < 0:
		return {}
	return {"tactics": int(state.tactics), "leadership": int(state.leadership), "coach": int(state.coach)}

## Who holds a non-head post (文官 or 武官) in an original team: native command
## needs officer rank and such a post, or the formal captaincy, as in TerrainArmy
## (v2 plan R1b, amended 2026-10-07). Positions are read-only during Crowd, so
## the rosters are the truth. Lab rosters without offices seat their cadre
## (the auto-appointment rule for officers in service).
func _roster_post_holders() -> Dictionary:
	var holders := {}
	for roster: Dictionary in rosters:
		var offices: Variant = roster.get("offices", null)
		if offices is Dictionary and not offices.is_empty():
			holders.merge(d5_post_holders(roster))
		else:
			for index: Variant in roster.get("officer_service", []):
				var identity := d5_person_id(roster, int(index))
				if identity > 0: holders[identity] = true
	return holders

static func d5_post_holders(snapshot: Dictionary) -> Dictionary:
	var holders := {}
	var offices: Variant = snapshot.get("offices", null)
	if not offices is Dictionary: return holders
	for seat: Variant in offices.get("positions", []):
		if seat is Dictionary and not bool(seat.get("head", false)) and int(seat.get("holder", -1)) > 0: holders[int(seat.holder)] = true
	return holders

static func military_role_code(value: String) -> int:
	return 1 if value == "officer" else 2 if value == "civilian" else 0

static func military_role_name(value: int) -> String:
	return "officer" if value == 1 else "civilian" if value == 2 else "soldier"


static func _formation_handoff_snapshot(state: Dictionary) -> Dictionary:
	var result := state.duplicate(true)
	for key: String in ["routed", "needs_attack_order", "commander_present", "ai_enabled", "no_orders", "attacking", "ref_valid", "resupplying", "host_center"]:
		result[key] = bool(state[key])
	for key: String in ["fatigue_count", "order", "formal_person", "acting_person", "current_person", "target_person"]:
		result[key] = int(state[key])
	return result


static func _write_row_handoff(row: Dictionary, state: Dictionary, formation: Dictionary) -> void:
	row["military_role"] = military_role_name(int(state.military_role))
	row["hit_revision"] = int(state.hit_revision)
	for key: String in ["hp", "stun", "grace", "ko", "getup", "escape_t", "knock_t", "act_t", "face"]:
		row[key] = float(state[key])
	row["bandaged"] = bool(state.bandaged)
	row["role"] = int(state.role)
	row.captive = bool(state.captive)
	row.exchange_stagger = float(state.stagger)
	row.exchange_cooldown = float(state.exch_cd)
	row.ranged_cooldown = float(state.ranged_cd)
	row.exchange_skill_cooldown = float(state.skill_cd)
	row["command_abilities"] = _handoff_abilities(state)
	if float(state.hp) > 0.0:
		row["fatigue"] = float(formation.fatigue)
		row["fatigue_rest"] = float(formation.fatigue_rest)
	row["cell"] = [floori(float(state.px)), floori(float(state.py))]
	row["crowd_position"] = [float(state.px), float(state.py)]
	var direction := Vector2.from_angle(float(state.face))
	var facing := Vector2i(int(signf(direction.x)), 0) if absf(direction.x) > absf(direction.y) else Vector2i(0, int(signf(direction.y)))
	row["facing"] = [facing.x, facing.y]
	if float(state.getup) > 0.0:
		row.pose = "get_up"
		row.age = maxf(0.0, float(D5Timings.POSE_SECONDS[&"get_up"]) - float(state.getup))
	elif float(state.hp) <= 0.0 or float(state.ko) > 0.0:
		row.pose = "down" if float(state.hp) <= 0.0 else "unconscious"
		row.age = 0.0
	elif str(row.get("pose", "")) in ["get_up", "down", "unconscious"]:
		row.pose = "idle"
		row.age = 0.0


static func _roster_index_for_person(roster: Dictionary, identity: int) -> int:
	if identity < 1: return -1
	if identity == int(roster.get("player_member", {}).get("id", -1)):
		return TerrainArmy.PLAYER_MEMBER
	for index in range(roster.units.size()):
		if int(roster.units[index].person_id) == identity:
			return index
	return -1


static func _write_roster_handoff(roster: Dictionary, state: Dictionary) -> Dictionary:
	if bool(state.get("garrisoned", false)) != (not str(roster.get("garrison_feature_id", "")).is_empty()):
		return SiteRuntime.fail("INVALID_GARRISON", "原生駐營與原Army歸屬不符")
	roster.erase("crowd_source_sha256") # The native world now owns this fresh snapshot.
	var indices := {}
	for key: String in ["formal_person", "acting_person", "current_person"]:
		var identity := int(state[key])
		var index := _roster_index_for_person(roster, identity)
		if identity >= 1 and index < 0:
			return SiteRuntime.fail("INVALID", "原生指揮引用找不到原名冊人物")
		indices[key] = index
	var officers: Array[int] = []
	for identity in state.officer_persons:
		var index := _roster_index_for_person(roster, int(identity))
		if index < 0: return SiteRuntime.fail("INVALID", "原生幹部引用找不到原名冊人物")
		officers.append(index)
	roster["crowd_state"] = _formation_handoff_snapshot(state)
	roster["formal_commander"] = int(indices.formal_person)
	roster["acting_commander"] = int(indices.acting_person)
	roster["current_commander"] = int(indices.current_person)
	roster["officers"] = officers
	var shared: Dictionary = roster.get("team_fatigue", {})
	shared["version"] = 2
	shared["fatigue"] = float(state.fatigue)
	shared["fatigue_rest"] = float(state.fatigue_rest)
	shared["count"] = int(state.fatigue_count)
	if not shared.has("active"): shared["active"] = false
	shared.erase("excluded_player_id")
	roster["team_fatigue"] = shared
	roster["training"] = float(state.training)
	roster["needs_attack_order"] = bool(state.needs_attack_order)
	roster["command_reference_valid"] = bool(state.ref_valid)
	roster["reference"] = [float(state.ref_x), float(state.ref_y)]
	roster["origin"] = [float(state.origin_x), float(state.origin_y)]
	roster["pursuit_left"] = float(state.pursuit_left)
	roster["pursuit_target"] = int(state.target_person)
	roster["_order_delay"] = float(state.order_delay)
	roster["combat_attacking"] = bool(state.attacking)
	roster["goal"] = [floori(float(state.goal_x)), floori(float(state.goal_y))]
	if bool(state.get("garrisoned", false)): roster["goal"] = [-1, -1]
	var orders := [TerrainArmy.CombatOrder.HOLD, TerrainArmy.CombatOrder.MOVE, TerrainArmy.CombatOrder.ATTACK,
		TerrainArmy.CombatOrder.PURSUE, TerrainArmy.CombatOrder.RETREAT, TerrainArmy.CombatOrder.RETURN,
		TerrainArmy.CombatOrder.CHARGE, TerrainArmy.CombatOrder.RALLY]
	roster["combat_order"] = int(orders[int(state.order)])
	var ai: Dictionary = roster.get("tactical_ai", {})
	ai["enabled"] = bool(state.ai_enabled)
	roster["tactical_ai"] = ai
	var abilities: Array[Dictionary] = []
	for index in range(roster.units.size()):
		var values: Dictionary = roster.units[index].get("command_abilities", {})
		if not values.is_empty(): abilities.append({"unit": index, "values": values.duplicate()})
	roster["abilities"] = abilities
	return SiteRuntime.ok()


static func _formation_handoff_fields(roster: Dictionary, mapped: Dictionary) -> Dictionary:
	# Integer Site goals remain valid for ordinary owners. This same-record snapshot
	# retains the exact continuous goal/heading and native-only flags for re-import.
	if roster.get("crowd_state") is Dictionary:
		for key: String in roster.crowd_state:
			if (key in FORMATION_FIELDS or key in ["formal_person", "acting_person", "current_person", "target_person", "officer_persons"]) and key not in ["host_center", "no_orders"]:
				mapped[key] = roster.crowd_state[key]
	return mapped


func sync_to_site() -> Dictionary:
	if crowd == null: return SiteRuntime.ok()
	if not _consume_events(): return last_event_error
	settle_events()
	if not pending_captivity.is_empty(): return save_guard()
	# One synchronous read per native person/team; all writes target original records.
	var formations := {}
	for index in range(int(crowd.formation_count())):
		formations[index] = formation_state(index)
	var post_holders := _roster_post_holders()
	for identity: int in _index_by_id:
		var state := soldier_state(int(_index_by_id[identity]))
		var person_source = person_owner(identity)
		var military: String = _actors[identity].military_role if _actors.has(identity) else str(_records[identity].get("military_role", "soldier"))
		if int(state.military_role) != military_role_code(military) or int(state.post_holder) != int(post_holders.has(identity)):
			return SiteRuntime.fail("INVALID_ROLE", "原生軍官資格／職位與原人物資料不符")
		_sync_ammo(identity, state)
		if _actors.has(identity):
			_sync_actor(identity, true, state, formations[person_source.formation_index])
			if _live_contact_actor_ids.has(identity):
				var values: PackedFloat64Array = crowd.get_soldier_state(int(_index_by_id[identity]))
				var native: PackedFloat64Array = crowd.contact_pose_state(int(_index_by_id[identity]))
				if _sample_prepared_actor_contact(_actors[identity], _appearance(identity), values, native).is_empty():
					return SiteRuntime.fail("MISSING_ASSET", "Original prepared Actor snapshot pose unavailable")
		else:
			_write_row_handoff(_records[identity], state, formations[person_source.formation_index])
			_write_presence_handoff(_records[identity], Array(crowd.site_person_absent_state(int(_index_by_id[identity]))))
		var relation: Dictionary = lab.terrain.site.get("captivity", {}).get(str(identity), {})
		if int(state.get("prison_id", 0)) != int(relation.get("prison_id", "0")):
			return SiteRuntime.fail("INVALID_PRISON", "原生拘禁與原人物拘押關係不符")
		if not relation.is_empty() and int(state.captor_person) >= 1:
			relation["guard_id"] = int(state.captor_person)
	for roster: Dictionary in rosters:
		var state: Dictionary = formations[int(roster.crowd_formation)]
		var result := _write_roster_handoff(roster, state)
		if not result.ok: return result
		var entry: Dictionary = lab.terrain.site.get("team_supply", {}).get(str(roster.team_id), {})
		if not entry.is_empty():
			# Reputation: a team that has just broken is a defeat for it and a victory for the hostile teams present.
			if bool(state.routed) and not bool(entry.sustain.get("routed", false)) and lab.site_controller.has_method("team_routed_reputation"):
				lab.site_controller.team_routed_reputation(int(roster.team_id))
				var routed_team: Dictionary = _team_by_id(int(roster.team_id))
				battle.on_rout(int(roster.team_id), int(routed_team.get("faction", -1)), routed_team.get("person_ids", []))
			entry.sustain.morale = float(state.morale)
			entry.sustain.routed = bool(state.routed)
			entry.sustain.regroup_seconds = float(state.rally_rest)
			entry.sustain.commander_present = bool(state.commander_present)
	return SiteRuntime.ok()


## G5 S3: native garrison operations. Each native move is followed by its GD record move (native_transfer_records),
## so sync_to_site and save/load see one membership. Callers validate every refusal before the first native write.
func native_roster(team_id: int) -> Dictionary:
	for roster: Dictionary in rosters:
		if int(roster.team_id) == team_id: return roster
	return {}


# P1c (crowd_team_data_survey.md, Option A): refresh a dormant grid holder's team-level commander, officer, office and
# cohort fields from crowd truth (native formation refs for commanders and officers, roster for offices and cohort) before a
# crowd-side team call. Read-only for crowd: the holder's hot fields are never read here.
# P1d: the holder's indices are roster row indices (its combat_units are the roster rows, PLAYER_MEMBER for the roster's
# player member), as _write_roster_handoff maps them. They are never CrowdPersonOwner (native world) indices.
func project_team_holder(holder: Variant) -> void:
	if not is_instance_valid(holder): return
	var owner: Variant = native_owner(int(holder.team_id))
	var roster: Dictionary = native_roster(int(holder.team_id))
	if owner == null or roster.is_empty(): return
	var state: Dictionary = formation_state(int(owner.formation_index))
	holder.formal_commander = _roster_index_for_person(roster, int(state.get("formal_person", -1)))
	holder.acting_commander = _roster_index_for_person(roster, int(state.get("acting_person", -1)))
	holder.current_commander = _roster_index_for_person(roster, int(state.get("current_person", -1)))
	var officers: Array[int] = []
	for identity: Variant in state.get("officer_persons", []):
		var index := _roster_index_for_person(roster, int(identity))
		if index != -1: officers.append(index)
	holder.officer_order = officers
	var service: Array[int] = []
	for index: Variant in roster.get("officer_service", []): service.append(int(index))
	holder.officer_service = service
	holder.offices = roster.get("offices", {}).duplicate(true)
	holder.social_cohort = roster.get("social_cohort", {}).duplicate(true)


# P1d: the dormant TerrainArmy that holds this crowd team's team data: the original team bound to the crowd (a grid team
# imported by D5, or a crowd roster restored by a load, activate_loaded). A team deployed straight into the crowd has none:
# no grid object holds its rows, and an unbound army slot that happens to carry the same team_id is not its holder.
func team_holder(team_id: int) -> Variant:
	for plan: Dictionary in _original_team_plans:
		var source: Variant = plan.get("source")
		if is_instance_valid(source) and int(source.team_id) == team_id: return source
	return null

# P1d: the post holders of one roster (offices seats when present, else the officer service), as _roster_post_holders reads them.
func roster_post_holders(team_id: int) -> Dictionary:
	var roster: Dictionary = native_roster(team_id)
	var holders := {}
	if roster.is_empty(): return holders
	var offices: Variant = roster.get("offices", null)
	if offices is Dictionary and not offices.is_empty(): return d5_post_holders(roster)
	for index: Variant in roster.get("officer_service", []):
		var identity := d5_person_id(roster, int(index))
		if identity > 0: holders[identity] = true
	return holders

# P1d: write a personnel review's result from the holder back to crowd truth. The holder's offices and officer_service go to
# the roster (saved with it). Native post-holder flags follow the roster (sync validates them). Native officer_persons follow
# the holder's officer_order. Native commander refs are not touched by a personnel review.
func commit_team_personnel(team_id: int, holder: Variant, before_posts: Dictionary) -> Dictionary:
	var owner: Variant = native_owner(team_id)
	var roster: Dictionary = native_roster(team_id)
	if owner == null or roster.is_empty() or not is_instance_valid(holder): return SiteRuntime.fail("NO_TARGET", "群眾隊伍不存在")
	roster["offices"] = holder.offices.duplicate(true)
	var service: Array[int] = []
	for index: Variant in holder.officer_service: service.append(int(index))
	roster["officer_service"] = service
	var after := roster_post_holders(team_id)
	var changed := {}
	for identity: Variant in before_posts: changed[int(identity)] = true
	for identity: Variant in after: changed[int(identity)] = true
	for identity: Variant in changed:
		if not _index_by_id.has(int(identity)): continue
		var flag := after.has(int(identity))
		if before_posts.has(int(identity)) == flag: continue
		if not bool(crowd.set_post_holder(int(_index_by_id[int(identity)]), int(flag))):
			return SiteRuntime.fail("INVALID_ROLE", "原生職位旗標寫入失敗")
	var officers: Array = []
	for index: int in holder.officer_order:
		var identity := int(holder.combat_identity(index)) # holder (roster) index, not a native world index
		if identity > 0: officers.append(identity)
	if not set_formation_fields(int(owner.formation_index), {"officer_persons": officers}):
		return SiteRuntime.fail("INVALID_ROLE", "原生軍官列表寫入失敗")
	_refresh_bodies()
	return SiteRuntime.ok()


func native_owner(team_id: int) -> Variant:
	for owner: Variant in owners:
		if int(owner.team_id) == team_id: return owner
	return null


func native_team(team_id: int) -> Dictionary:
	return _team_by_id(team_id)


func native_next_team_id() -> int:
	return _solo_team_id()


# GD-only destination for the supply transaction; it has no people until native_transfer_records binds them.
func native_pending_owner(team_id: int, faction: int) -> Variant:
	var pending := PersonOwner.new()
	pending.setup(self, -1, team_id, faction, {}, {})
	return pending


func native_empty_garrison(feature_id: String, faction: int) -> Dictionary:
	for roster: Dictionary in rosters:
		if str(roster.get("garrison_feature_id", "")) == feature_id and int(roster.faction_id) == faction and roster.units.is_empty():
			return roster
	return {}


func native_empty_formation(team_id: int, faction: int) -> Dictionary:
	if team_id <= 0: return {}
	for roster: Dictionary in rosters:
		if int(roster.team_id) == team_id and int(roster.faction_id) == faction and roster.units.is_empty() \
			and str(roster.get("garrison_feature_id", "")).is_empty() and not bool(crowd.get_garrisoned(int(roster.crowd_formation))):
			return roster
	return {}


# A new native formation of `faction` with its GD roster and team record. Formations are never removed.
## Option C: every crowd team keeps a TerrainArmy roster container with its team id (no simulation). The fire transport,
## garrison registrations and load (activate_loaded) find a team's owner there; the lab's three default slots covered only
## three teams, so a fourth deployed team could not save (CORRUPT_FIRE_OWNER).
func _ensure_team_containers() -> void:
	if not is_instance_valid(lab) or not lab.has_method("_ensure_army_slots"): return
	for team: Dictionary in teams:
		if bool(team.get("solo", false)): continue
		var team_id := int(team.team_id)
		var found := false
		for army: TerrainArmy in lab.combat_armies: found = found or army.team_id == team_id
		if found: continue
		# A new empty slot, never a reused one (an empty slot's id may still name a saved roster).
		lab._ensure_army_slots(lab.combat_armies.size() + 1)
		var container: TerrainArmy = lab.combat_armies.back()
		container.team_id = team_id


func native_add_team(team_id: int, faction: int, troop: int, training: float, cell: Vector2, garrison_feature_id: String) -> Dictionary:
	if not active or crowd == null: return SiteRuntime.fail("UNSUPPORTED", "群眾未啟用")
	var native_faction := _native_faction(faction)
	if native_faction < 0: return SiteRuntime.fail("NO_SPACE", "群眾原生陣營槽已滿")
	var formation: int = crowd.add_formation(native_faction, cell.x, cell.y, 0.0, 1, 1.0, troop, training)
	if formation < 0: return SiteRuntime.fail("NO_SPACE", "原生群眾無法新增隊伍")
	crowd.set_order_owner(formation, false)
	var roster := {"schema": 2, "roster_version": 1, "crowd": true, "team_id": team_id, "faction_id": faction,
		"crowd_formation": formation, "units": [], "officer_service": [], "formal_commander": 0,
		"command_radius": 8.0, "garrison_feature_id": garrison_feature_id}
	var slot := 0
	for team: Dictionary in teams: slot = maxi(slot, int(team.get("slot", 0)) + 1)
	teams.append({"slot": slot, "team_id": team_id, "formation": formation, "faction": faction,
		"native_faction": native_faction, "troop": troop, "person_ids": [], "solo": false})
	rosters.append(roster)
	lab.terrain.site.armies.append(roster)
	lab.terrain.site["army_next_team"] = maxi(int(lab.terrain.site.get("army_next_team", 0)), team_id + 1)
	_ensure_team_containers()
	return SiteRuntime.ok("", {"formation": formation, "roster": roster})


func _absent_kind(index: int) -> int:
	var absent: Array = Array(crowd.site_person_absent_state(index))
	return int(absent[1]) if absent.size() >= 2 and int(absent[0]) == 1 else 0


# Absence of every identity as `kind`. Members already absent with this kind are kept. All refusals are checked
# before the first native change; a late refusal restores the members already absent.
func native_absent(identities: Array, kind: int) -> Dictionary:
	for identity: Variant in identities:
		var id := int(identity)
		var index := int(_index_by_id.get(id, -1))
		if index < 0 or _actors.has(id) or not _owner_by_id.has(id): return SiteRuntime.fail("UNSUPPORTED", "原人員不在原生群眾名冊")
		var reserve := _absent_kind(index)
		if reserve == kind: continue
		if reserve != 0: return SiteRuntime.fail("BUSY", "原人員已因其他原因離場")
		if not bool(_owner_by_id[id].site_exit_ready(index)): return SiteRuntime.fail("BUSY", "原人員作業或動作尚未收束，不能移入駐營")
	var applied: Array = []
	for identity: Variant in identities:
		var id := int(identity)
		var index := int(_index_by_id[id])
		if _absent_kind(index) == kind: continue
		var state := soldier_state(index)
		var formation := int(_owner_by_id[id].formation_index)
		if not bool(crowd.site_person_absent(index, kind)):
			for undo: Array in applied: crowd.site_person_return(int(undo[0]), int(undo[1]), float(undo[2]), float(undo[3]))
			return SiteRuntime.fail("NATIVE_REFUSED", "原生群眾拒絕離場；已還原本次離場")
		applied.append([index, formation, float(state.px), float(state.py)])
	return SiteRuntime.ok()


func native_move(identities: Array, formation: int) -> Dictionary:
	for identity: Variant in identities:
		var index := int(_index_by_id.get(int(identity), -1))
		if index < 0 or _actors.has(int(identity)) or not bool(crowd.move_member(index, formation)):
			return SiteRuntime.fail("NATIVE_REFUSED", "原生群眾拒絕移動隊員；原人員未完整移動")
	return SiteRuntime.ok()


# Each absent member lands on its own last cell (the cell the grid transfer keeps) in `formation`.
func native_return(identities: Array, formation: int) -> Dictionary:
	for identity: Variant in identities:
		var index := int(_index_by_id.get(int(identity), -1))
		var state := soldier_state(index)
		if state.is_empty() or not bool(crowd.site_person_return(index, formation, float(state.px), float(state.py))):
			return SiteRuntime.fail("NATIVE_REFUSED", "原生群眾拒絕歸隊；原人員未完整歸隊")
	return SiteRuntime.ok()


# G5 S2: one person's absence through the native op. Refusals change nothing and return false.
func native_set_absent(index: int, kind: int) -> bool:
	if index < 0 or crowd == null: return false
	return bool(crowd.site_person_absent(index, kind))


# G5 S2: rejoin at the person's own cell, or the nearest free walkable cell of the same formation. Each try is a
# native op that changes nothing on refusal, so trying several cells is safe.
func native_return_nearest(index: int, formation: int) -> bool:
	var state := soldier_state(index)
	if state.is_empty() or crowd == null: return false
	var origin := Vector2(float(state.px), float(state.py))
	var offsets: Array[Vector2] = []
	for dy in range(-PRESENCE_RETURN_SEARCH, PRESENCE_RETURN_SEARCH + 1):
		for dx in range(-PRESENCE_RETURN_SEARCH, PRESENCE_RETURN_SEARCH + 1):
			offsets.append(Vector2(dx, dy))
	offsets.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.length_squared() < b.length_squared())
	for offset: Vector2 in offsets:
		var target := origin + offset
		if bool(crowd.site_person_return(index, formation, target.x, target.y)): return true
	return false


const PRESENCE_RETURN_SEARCH := 3


# G5 S2: the native absence kind of a soldier index: 0 on the roster, else 1 detached, 2 off-map, 3 captive hold, 4 reserve.
static func absent_kind_of(absent: Array) -> int:
	return int(absent[1]) if absent.size() >= 2 and int(absent[0]) == 1 else 0


# G5 S2: a GD row's absence kind: off-map (site_exited) is kind 2, a detached row (member=false) kind 1, else 0.
static func d5_absent_kind(saved: Dictionary) -> int:
	if bool(saved.get("site_exited", false)): return 2
	return 0 if bool(saved.get("member", true)) else 1


# G5 S2: member, present and site_exited of a roster row are written from the native absence kind (sync_to_site).
static func _write_presence_handoff(row: Dictionary, absent: Array) -> void:
	var kind := absent_kind_of(absent)
	row["member"] = kind != 1
	row["present"] = kind == 0
	row["site_exited"] = kind == 2


# G5 S2: the D5 import makes each detached or off-map imported row absent natively. Runs after the native hot import
# and the state guard, and before the crowd is active. A refused native op fails the whole import.
static func d5_absent_existing(crowd_site: Variant, plans: Array) -> Dictionary:
	var controlled := int(crowd_site.lab.controlled_person_id())
	for plan: Dictionary in plans:
		for entry: Dictionary in plan.units:
			if entry.actor != null: continue
			var kind := d5_absent_kind(entry.saved)
			if kind == 0: continue
			var identity := int(entry.person_id)
			if identity == controlled: return D5Runtime.fail("UNSUPPORTED", "受控人物已離隊或離圖，尚不能交接群眾")
			var index := int(crowd_site._index_by_id.get(identity, -1))
			if index < 0 or not bool(crowd_site.crowd.site_person_absent(index, kind)):
				return D5Runtime.fail("NATIVE_REFUSED", "原生群眾拒絕離隊或離圖人物；原隊伍未交接")
	return D5Runtime.ok()


# G5 S4: a surrender-pending roster row is imported as the native surrendered flag (refused when native cannot hold it).
## G1 aboard import: every converted row whose GD record is embarked on a ship takes the native aboard state on that vessel,
## at its GD deck point, as a crowd load restores it. The GD ship rows stay the embarkation authority.
static func d5_aboard_existing(crowd_site: Variant, plans: Array) -> Dictionary:
	var vehicles: Dictionary = crowd_site.lab.terrain.site.get("vehicles", {})
	for plan: Dictionary in plans:
		for entry: Dictionary in plan.units:
			var vehicle_id := str(entry.saved.get("embarked_vehicle_id", ""))
			if vehicle_id.is_empty(): continue
			var vehicle: Dictionary = vehicles.get(vehicle_id, {})
			var index := int(crowd_site._index_by_id.get(int(entry.person_id), -1))
			if not SiteVehicleTransport.is_ship(vehicle) or not vehicle_id.is_valid_int() or index < 0 or not crowd_site.crowd.has_method("site_person_board") \
				or not bool(crowd_site.crowd.site_person_board(index, int(vehicle_id))):
				return D5Runtime.fail("NATIVE_REFUSED", "原生群眾拒絕船上人物；原隊伍未交接")
			var deck: Vector2 = crowd_site.lab.site_controller.vehicles.ship_person_ground(int(entry.person_id)) / float(TerrainRenderer.CELL_PIXELS)
			if crowd_site.crowd.has_method("site_person_set_deck"): crowd_site.crowd.site_person_set_deck(index, deck.x, deck.y)
	return D5Runtime.ok()

static func d5_surrender_existing(crowd_site: Variant, plans: Array) -> Dictionary:
	for plan: Dictionary in plans:
		for entry: Dictionary in plan.units:
			if not bool(entry.saved.get("surrender_pending", false)): continue
			var index := int(crowd_site._index_by_id.get(int(entry.person_id), -1))
			if index < 0 or not bool(crowd_site.crowd.set_soldier_surrendered(index, true)):
				return D5Runtime.fail("NATIVE_REFUSED", "原生群眾拒絕投降人物；原隊伍未交接")
	return D5Runtime.ok()


func _team_for_formation(formation: int) -> Dictionary:
	for team: Dictionary in teams:
		if int(team.formation) == formation and not bool(team.get("departed", false)): return team
	return {}


# Moves the GD unit records (the same objects the native sync reads) and the team membership of `identities`
# from roster `source` to roster `destination`. Officer seats follow their person; the source indices are remapped.
func native_transfer_records(identities: Array, source: Dictionary, destination: Dictionary) -> void:
	var moving := {}
	for identity: Variant in identities: moving[int(identity)] = true
	var old_units: Array = source.units.duplicate()
	var old_service := {}
	for index: Variant in source.get("officer_service", []): old_service[int(index)] = true
	var kept_units: Array = []
	var kept_service: Array = []
	var joined_service: Array = []
	for index in range(old_units.size()):
		var row: Dictionary = old_units[index]
		if moving.has(int(row.person_id)):
			if old_service.has(index): joined_service.append(destination.units.size())
			destination.units.append(row)
		else:
			if old_service.has(index): kept_service.append(kept_units.size())
			kept_units.append(row)
	source.units.clear()
	source.units.append_array(kept_units)
	source["officer_service"] = kept_service
	var service: Array = destination.get("officer_service", [])
	service.append_array(joined_service)
	destination["officer_service"] = service
	var source_team := _team_for_formation(int(source.crowd_formation))
	var destination_team := _team_for_formation(int(destination.crowd_formation))
	var kept_ids: Array = []
	for identity: Variant in source_team.person_ids:
		if not moving.has(int(identity)): kept_ids.append(int(identity))
	source_team["person_ids"] = kept_ids
	for identity: Variant in identities: destination_team.person_ids.append(int(identity))
	_bind_people()


## NEKKI 2026-10-30 persuasion: a captive of another team joins `destination_formation` (the captor's formation) as a normal
## member. The native transfer_member goes first and refuses without change. Then the GD rows follow the soldier (team
## person ids, roster row, owners via _bind_people), and the captivity ends as a release ends it (custody days settled,
## relation erased, holder version, supply and change hooks). Refusals before the native change change nothing.
## `adoption` is the grid adoption plan (SitePoliticalAdoption: nation_id, old_nations, corps), computed before any change.
## It is committed in the grid order: supply (adoption_guard, as political adoption's final home), captivity erase, national
## posts vacated, nation membership moved, corps ended, holder version, then the change hooks.
func transfer_captive(identity: int, captor_id: int, destination_formation: int, adoption: Dictionary) -> Dictionary:
	if not active or crowd == null or not contains_person(identity) or _actors.has(identity) or not _owner_by_id.has(identity):
		return SiteRuntime.fail("UNSUPPORTED", "原人員不在原生群眾名冊")
	if not crowd.has_method("transfer_member"): return SiteRuntime.fail("UNSUPPORTED", "原生群眾未提供跨隊移入")
	var index := int(_index_by_id[identity])
	var owner: Variant = _owner_by_id[identity]
	var source_roster := team_record(int(owner.formation_index))
	var destination_roster := team_record(destination_formation)
	if source_roster.is_empty() or destination_roster.is_empty() or not str(destination_roster.get("garrison_feature_id", "")).is_empty():
		return SiteRuntime.fail("INVALID_TEAM", "須有同地圖、未駐營的原接收隊伍")
	var relation: Dictionary = lab.terrain.site.captivity.get(str(identity), {})
	if relation.is_empty(): return SiteRuntime.fail("NO_TARGET", "沒有此人的原拘押紀錄")
	var body: Variant = owner.combat_units.get(index)
	var holder: Variant = owner.person(index, false).get("holder")
	var row_before := -1
	for row_index in range(source_roster.units.size()):
		if int(source_roster.units[row_index].get("person_id", -1)) == identity: row_before = row_index
	# Same pairing as the grid adoption (SitePoliticalAdoption.prepare/commit): the final-home supply guard prepares the change
	# first and refuses with no change; every later failure discards it; only a published transfer commits it.
	var row: Dictionary = owner.combat_hot_materialize(index)
	var guard: Dictionary = lab.site_controller.captivity_supply.adoption_guard(identity, captor_id, row)
	if not guard.ok: return guard
	if not bool(crowd.transfer_member(index, destination_formation)):
		lab.site_controller.captivity_supply.discard(identity)
		return SiteRuntime.fail("NATIVE_REFUSED", "原生群眾拒絕跨隊移入；原人員未移動")
	native_transfer_records([identity], source_roster, destination_roster)
	if row_before >= 0 and int(source_roster.get("formal_commander", 0)) > row_before:
		source_roster["formal_commander"] = int(source_roster.formal_commander) - 1
	if body is Dictionary: SiteSocial.settle_before_release(body, relation, int(lab.terrain.site.get("minute", 0)))
	lab.terrain.site.captivity.erase(str(identity))
	lab.site_controller.captivity_supply.commit_change(identity, captor_id, false)
	var nations: Dictionary = lab.terrain.site.get("equipment_nations", {})
	var old_nations: Array = adoption.get("old_nations", [])
	PoliticalAdoption.vacate_national_posts(nations, old_nations, identity)
	PoliticalAdoption.move_nation_membership(nations, old_nations, str(adoption.get("nation_id", "")), identity)
	PoliticalAdoption.end_corps(lab.terrain.site, adoption.get("corps", []))
	if holder is Dictionary: holder.version = int(holder.get("version", 0)) + 1
	equipment_changed(identity)
	captivity_changed(identity, captor_id, false)
	return SiteRuntime.ok("", {"person_id": identity, "formation": destination_formation})

func native_set_garrisoned(roster: Dictionary, feature_id: String) -> Dictionary:
	var formation := int(roster.crowd_formation)
	if not bool(crowd.get_garrisoned(formation)) and not bool(crowd.set_garrisoned(formation, 1)):
		return SiteRuntime.fail("BUSY", "原生隊伍尚有移動作業，不能駐營")
	roster["garrison_feature_id"] = feature_id
	return SiteRuntime.ok()


func native_set_military_role(identity: int, role: String) -> Dictionary:
	var index := int(_index_by_id.get(identity, -1))
	var record: Dictionary = _records.get(identity, {})
	if index < 0 or record.is_empty() or _actors.has(identity) or not bool(crowd.set_military_role(index, military_role_code(role))):
		return SiteRuntime.fail("NATIVE_REFUSED", "原生群眾拒絕更改軍職")
	record["military_role"] = role
	_refresh_bodies() # Promotion gains a body; demotion back to an atlas look loses it.
	return SiteRuntime.ok()


## G6.4b: the crowd team a travelling commander leads. Read-only: nothing is released here.
## Only a whole team whose commander is the controlled person is admitted. Every member must pass the native exit gate.
func departure_plan(identity: int) -> Dictionary:
	if not active or crowd == null: return SiteRuntime.fail("UNSUPPORTED", "群眾未啟用")
	if _actors.has(identity) or not _index_by_id.has(identity): return SiteRuntime.fail("UNSUPPORTED", "群眾中的 actor 本體尚不能整隊出發")
	if not pending_captivity.is_empty(): return SiteRuntime.fail("BUSY", "群眾俘虜事件尚未結束")
	var roster: Dictionary = {}
	for candidate: Dictionary in rosters:
		if _roster_index_for_person(candidate, identity) >= 0:
			roster = candidate
			break
	if roster.is_empty(): return SiteRuntime.fail("NO_TARGET", "群眾中沒有此人的隊伍")
	if _roster_index_for_person(roster, identity) != int(roster.get("formal_commander", -1)):
		return SiteRuntime.fail("UNSUPPORTED", "群眾隊伍只能由隊長整隊出發；部分隊員出發尚未支援")
	var people: Array[int] = []
	var cells: Array[Vector2i] = []
	var controlled_cell := Vector2i(-1, -1)
	var team_sea: bool = lab.site_controller.vehicles.team_has_embarked(int(roster.team_id))
	# Decision A2 on crowd (2026-11-10): a dead member whose remains are settled does not block the team; it is inert and
	# leaves with it (released by site_person_release_dead). A dead member whose remains are not settled yet refuses.
	var inert: Array[int] = []
	for unit: Dictionary in roster.units:
		var member := int(unit.person_id)
		if not _index_by_id.has(member) or _actors.has(member) or has_pending_capture(member):
			return SiteRuntime.fail("NOT_READY", "隊員尚有原生事件；保留原進度")
		var owner: Variant = person_owner(member)
		if owner != null and float(soldier_state(int(_index_by_id[member])).get("hp", 1.0)) <= 0.0:
			if not bool(owner.combat_hot_get(int(_index_by_id[member]), &"loot_settled", false)):
				return SiteRuntime.fail("NOT_READY", "陣亡隊員的遺物尚未結算；結算後才能整隊出發")
			if member == identity: return SiteRuntime.fail("NO_TARGET", "受控本人已陣亡")
			inert.append(member)
			continue
		# The controlled captain holds host control; _split_exit_ready hands it back for the query only.
		# SHIPSEA: an embarked team leaves by sea, so an aboard member asks the aboard gate for its own vessel.
		# A land team's driver crews its own cart or wagon convoy, which the native exit gate never admits; a driver whose
		# convoy stands complete is ready by the person's own state (2026-11-09: a crowd team with a wagon could not leave).
		var driving: bool = not team_sea and owner != null and _convoy_driver_ready(owner, member, int(roster.team_id))
		if owner == null or not driving and not _split_exit_ready(owner, int(_index_by_id[member]), _departure_vessel(owner, int(_index_by_id[member]), team_sea)):
			return SiteRuntime.fail("NOT_READY", "隊員不在可出發狀態（倒地、交換中或有未完成動作）")
		var state := soldier_state(int(_index_by_id[member]))
		var cell := Vector2i(floori(float(state.px)), floori(float(state.py)))
		people.append(member)
		cells.append(cell)
		if member == identity: controlled_cell = cell
	if people.is_empty(): return SiteRuntime.fail("NOT_READY", "隊伍沒有可出發的在世隊員")
	return SiteRuntime.ok("", {"roster": roster, "team_id": int(roster.team_id), "faction": int(roster.faction_id),
		"people": people, "cells": cells, "controlled_cell": controlled_cell, "inert": inert})


## A crowd team leaving a Site whose combat is its admitted original siege (RegionTravelSite._depart_crowd_bound): the
## origin's crowd section is produced by the same native releases run on a COPY of the native World, so the live Site stays
## the selected checkpoint the cold-owner bind authenticates (as the grid intent departure extracts from a copy). Nothing
## live is released; the commit's bind publishes this section into the Lab. Returns {ok, section, rosters, army}.
## Teams with carts, wagons or ships keep the live path (refused here).
func departure_origin_candidate(plan: Dictionary) -> Dictionary:
	if not plan.get("ok", false): return plan
	var team_id := int(plan.team_id)
	if lab.site_controller.vehicles.team_has_embarked(team_id): return SiteRuntime.fail("UNSUPPORTED", "攻城中的船隊出發尚未支援")
	for vehicle: Dictionary in lab.site_controller.vehicles.records().values():
		if str(vehicle.get("kind", "")) in ["cart", "wagon"] and int(vehicle.get("team_id", 0)) == team_id:
			return SiteRuntime.fail("UNSUPPORTED", "攻城中帶車隊出發尚未支援")
	var army_conversion: Dictionary = departure_army_snapshot(plan)
	if not army_conversion.ok: return army_conversion
	var captured: Dictionary = capture_save(true)
	if not captured.ok: return captured
	var copy: Object = ClassDB.instantiate("ArmyCrowd") if ClassDB.class_exists("ArmyCrowd") else null
	if copy == null: return SiteRuntime.fail("INVALID_CROWD", "群眾原生模組無法建立")
	copy.call("setup", 1, int(lab.terrain.seed_value))
	if not bool(copy.call("load_state", Marshalls.base64_to_raw(str(captured.section.blob)))): return SiteRuntime.fail("INVALID_CROWD", "群眾副本無法載入")
	var roster: Dictionary = {}
	for row: Dictionary in captured.rosters:
		if int(row.get("team_id", -1)) == team_id: roster = row
	if roster.is_empty(): return SiteRuntime.fail("NO_TARGET", "群眾副本中沒有出發隊伍")
	var army: Dictionary = army_conversion.snapshot.duplicate(true)
	for identity: int in plan.people:
		var index := int(_index_by_id[identity])
		if index == player_index: copy.call("set_host_control", index, false)
		var receipt: PackedFloat64Array = copy.call("site_person_release", index)
		if receipt.size() != 8: return SiteRuntime.fail("RELEASE_REFUSED", "群眾副本拒絕釋放隊員")
		_apply_army_receipt(army, identity, receipt)
	for identity: int in plan.get("inert", []):
		var dead_receipt: PackedFloat64Array = copy.call("site_person_release_dead", int(_index_by_id[identity]))
		if dead_receipt.size() != 8: return SiteRuntime.fail("RELEASE_REFUSED", "群眾副本拒絕釋放陣亡隊員")
		_apply_army_receipt(army, identity, dead_receipt)
	var bytes: PackedByteArray = copy.call("save_state")
	if bytes.is_empty(): return SiteRuntime.fail("INVALID_CROWD", "群眾副本無法保存")
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	var section: Dictionary = captured.section.duplicate(true)
	section["blob"] = Marshalls.raw_to_base64(bytes)
	section["blob_sha256"] = digest.finish().hex_encode()
	var formation := int(roster.crowd_formation)
	for team: Dictionary in section.teams:
		if int(team.get("formation", -1)) == formation: team["departed"] = true
	if plan.people.has(int(section.get("player", {}).get("person_id", -1))):
		section["player"] = {"person_id": int(section.player.person_id), "soldier_index": -1}
	var kept: Array[Dictionary] = []
	for row: Dictionary in captured.rosters:
		if int(row.get("team_id", -1)) != team_id: kept.append(row)
	return SiteRuntime.ok("", {"section": section, "rosters": kept, "army": army})

## A native release receipt written onto the travelling grid army row (as _apply_release_receipt does on a roster row).
static func _apply_army_receipt(army: Dictionary, identity: int, receipt: PackedFloat64Array) -> void:
	for row: Dictionary in army.get("units", []):
		if int(row.get("person_id", 0)) != identity: continue
		row["hp"] = float(receipt[0])
		row["cell"] = [int(receipt[4]), int(receipt[5])]
		row["crowd_position"] = [receipt[6], receipt[7]]
		return

## True when `member` drives a cart or wagon of `team_id` whose native convoy stands complete (not moving, not stalled) and
## the person is conscious, free, not surrendering and not fighting.
func _convoy_driver_ready(owner: Variant, member: int, team_id: int) -> bool:
	var vehicles: Variant = lab.site_controller.vehicles
	var driven: Dictionary = {}
	for vehicle: Dictionary in vehicles.records().values():
		if str(vehicle.get("kind", "")) in ["cart", "wagon"] and int(vehicle.get("team_id", 0)) == team_id and int(vehicle.get("operator_id", 0)) == member:
			driven = vehicle
	if driven.is_empty() or int(driven.get("convoy_id", 0)) <= 0: return false
	var state: Dictionary = vehicles.convoy_state(driven)
	if state.is_empty() or not bool(state.complete) or bool(state.moving) or bool(state.stalled): return false
	var person: Dictionary = owner.person(int(_index_by_id[member]), false)
	return not person.is_empty() and float(person.hp) > 0.0 and float(person.ko) <= 0.0 and not bool(person.captive) \
		and not bool(person.surrender_pending) and not person_fighting(member)

## SHIPSEA: the boat fields a passenger keeps on its CrowdPersonOwner record. A crowd passenger's boat is not in the
## roster rows, so the travelling snapshot copies these fields across (the grid sea party reads the same row keys).
const SHIP_ROW_FIELDS := ["embarked_vehicle_id", "berth_id", "ship_deck_position", "ship_guest"]

## SHIPSEA: the departing team as a complete grid army snapshot, read before any release. Read-only: nothing is released.
## Passengers keep their boat (embarked_vehicle_id, berth_id, ship deck fields) so RegionTravel.extract carries the vessel
## and its passengers as a grid sea party. Returns {ok, snapshot}.
func departure_army_snapshot(plan: Dictionary) -> Dictionary:
	if not plan.get("ok", false): return plan
	var conversion: Dictionary = ClearHandoff.roster_snapshot(self, plan.roster)
	if not conversion.ok: return conversion
	var snapshot: Dictionary = conversion.snapshot
	for row: Dictionary in snapshot.units:
		var identity := int(row.person_id)
		var owner: Variant = person_owner(identity)
		if not owner is CrowdPersonOwner or int(owner.index_for_identity(identity)) < 0: continue
		var record: Dictionary = owner.records.get(int(owner.index_for_identity(identity)), {})
		for field: String in SHIP_ROW_FIELDS:
			if record.has(field): row[field] = record[field]
	return SiteRuntime.ok("", {"snapshot": snapshot})


## G6.4b: releases every person of a plan that departure_plan passed. Release is irreversible, so callers must
## pre-validate the extraction first. The receipts (hp, ammo, position) are written to the live roster rows,
## then the released people leave every Site map, so the next capture_save omits them.
func departure_release(plan: Dictionary) -> Dictionary:
	if not plan.get("ok", false): return plan
	var roster: Dictionary = plan.roster
	var released: Array[int] = []
	# The grid army snapshot is converted from the live rows before any release (it reads the native soldier state, which a
	# release removes). A conversion refusal releases nobody.
	var army_conversion: Dictionary = departure_army_snapshot(plan)
	if not army_conversion.ok: return army_conversion
	# The controlled captain (host control) is released first, so a refusal of his release leaves nobody released.
	var order: Array[int] = []
	for identity: int in plan.people:
		if int(_index_by_id[identity]) == player_index: order.append(identity)
	for identity: int in plan.people:
		if not order.has(identity): order.append(identity)
	# SHIPSEA: an embarked team leaves by sea; its aboard members are released with their vessel (the aboard release).
	var team_sea: bool = lab.site_controller.vehicles.team_has_embarked(int(plan.team_id))
	# A land team's carts and wagons leave with it: their native convoys are removed first, so each driver is an ordinary
	# soldier to release and the origin blob keeps no convoy of a departed driver. The GD records (operator kept) travel.
	if not team_sea:
		for vehicle: Dictionary in lab.site_controller.vehicles.records().values():
			if str(vehicle.get("kind", "")) in ["cart", "wagon"] and int(vehicle.get("team_id", 0)) == int(plan.team_id) and int(vehicle.get("convoy_id", 0)) > 0:
				lab.site_controller.vehicles._convoy_release(vehicle)
	for identity: int in order:
		var index := int(_index_by_id[identity])
		var owner: Variant = person_owner(identity)
		var receipt: Dictionary = {}
		# Same host-control handover as split_departure_release: released with host control handed back on refusal.
		var host_held := index == player_index
		if host_held: crowd.set_host_control(index, false)
		if owner != null: receipt = owner.release_for_departure(index, _departure_vessel(owner, index, team_sea))
		if receipt.is_empty():
			if host_held: crowd.set_host_control(index, true)
			return SiteRuntime.fail("RELEASE_REFUSED", "原生釋放被拒（已釋放 %d 人）；請重新檢查" % released.size())
		if host_held: player_index = -1
		released.append(identity)
		_apply_release_receipt(roster, identity, receipt)
		var record: Dictionary = _records.get(identity, {})
		var key := str(_ammo_keys.get(identity, ""))
		if not record.is_empty() and not key.is_empty():
			var cargo: Dictionary = record.get("cargo", {})
			if int(receipt.ammo) > 0: cargo[key] = int(receipt.ammo)
			else: cargo.erase(key)
	# Decision A2: the settled dead leave with the team, inert (their rows are in the travelling snapshot read above).
	for identity: int in plan.get("inert", []):
		var dead_owner: Variant = person_owner(identity)
		var dead_receipt: Dictionary = dead_owner.release_dead_for_departure(int(_index_by_id[identity])) if dead_owner != null else {}
		if dead_receipt.is_empty():
			return SiteRuntime.fail("RELEASE_REFUSED", "原生陣亡者釋放被拒（已釋放 %d 人）；請重新檢查" % released.size())
		released.append(identity)
		_apply_release_receipt(roster, identity, dead_receipt)
	for identity: int in released:
		_index_by_id.erase(identity)
		_owner_by_id.erase(identity)
		_records.erase(identity)
	var formation := int(roster.crowd_formation)
	var kept_owners: Array = []
	for owner_ref: Variant in owners:
		if int(owner_ref.formation_index) != formation: kept_owners.append(owner_ref)
	owners = kept_owners
	# Tombstone: the formation stays in the native World (no removal API), so the section keeps its entry.
	for team: Dictionary in teams:
		if int(team.formation) == formation: team["departed"] = true
	var kept_rosters: Array[Dictionary] = []
	for row: Dictionary in rosters:
		if not is_same(row, roster): kept_rosters.append(row)
	rosters = kept_rosters
	_refresh_bodies() # Released people leave no presenter behind.
	return SiteRuntime.ok("", {"roster": roster, "released": released.size(), "army": army_conversion.snapshot})


## G6.5 (2026-11-01): 幹部分隊. A cadre leads a sub-party out of one live crowd team. The cadre is the party's formal
## captain; the other members are ordinary people of the same team. An ordinary member never leaves alone, the formal
## captain never leaves by a split (it departs with the whole team), and the controlled cadre leads the split and travels
## with it (the Site passes control to an actor body that stays).
## Cadre = the TerrainArmy definition: an officer_service / officers entry, or a holder of a non-head office seat.
static func cadre_index(roster: Dictionary, index: int) -> bool:
	if index < 0 or index >= roster.units.size(): return false
	for field: String in ["officers", "officer_service"]:
		for entry: Variant in roster.get(field, []):
			if int(entry) == index: return true
	var person := int(roster.units[index].person_id)
	for seat: Variant in roster.get("offices", {}).get("positions", []):
		if seat is Dictionary and not bool(seat.get("head", false)) and int(seat.get("holder", 0)) == person: return true
	return false


## Nekki 2026-11-04 (joining in person): a cadre who will not follow his captain into another faction leaves the team on
## the spot and becomes the captain of his own one-person team of `faction` (normally neutral), in this Site. The person
## keeps his row (life, items, abilities); his posts in the old team are vacated. Supply follows the person first, so a
## refusal before the native move changes nothing. Returns {team_id, formation}.
func detach_to_new_team(identity: int, faction: int, remember_origin: bool = false) -> Dictionary:
	if not active or crowd == null: return SiteRuntime.fail("UNSUPPORTED", "群眾未啟用")
	if not crowd.has_method("leave_member"): return SiteRuntime.fail("UNSUPPORTED", "原生群眾未提供離隊轉投")
	if _actors.has(identity) or not _index_by_id.has(identity) or not _owner_by_id.has(identity): return SiteRuntime.fail("UNSUPPORTED", "此人不在原生群眾名冊")
	if not pending_captivity.is_empty() or has_pending_capture(identity): return SiteRuntime.fail("BUSY", "群眾俘虜事件尚未結束")
	var roster: Dictionary = {}
	for candidate: Dictionary in rosters:
		if _roster_index_for_person(candidate, identity) >= 0: roster = candidate
	if roster.is_empty(): return SiteRuntime.fail("NO_TARGET", "群眾中沒有此人的隊伍")
	if not str(roster.get("garrison_feature_id", "")).is_empty(): return SiteRuntime.fail("BUSY", "駐營隊伍的人員不能單獨離隊")
	var index := _roster_index_for_person(roster, identity)
	if index == int(roster.get("formal_commander", -1)): return SiteRuntime.fail("CAPTAIN_REQUIRED", "正式隊長不能單獨離隊")
	if roster.units.size() < 2: return SiteRuntime.fail("WHOLE_TEAM", "一人隊不必離隊")
	var owner: Variant = _owner_by_id[identity]
	var native_index := int(_index_by_id[identity])
	# The controlled person may leave too (Nekki 2026-11-11 A); the host-held soldier is queried as the split gate does.
	if not _split_exit_ready(owner, native_index): return SiteRuntime.fail("NOT_READY", "此人作業或動作尚未收束")
	var team_id := native_next_team_id()
	var ids: Array[int] = [identity]
	var supplied: Dictionary = lab.site_controller.captivity_supply._change_membership_supply(owner,
		{"key": "team:%d" % team_id, "team": native_pending_owner(team_id, faction)}, ids)
	if not supplied.ok: return supplied
	var state := soldier_state(native_index)
	var entry: Dictionary = native_team(int(roster.team_id))
	var created: Dictionary = native_add_team(team_id, faction, int(entry.get("troop", 0)), float(formation_state(int(owner.formation_index)).get("training", 0.0)), Vector2(float(state.px), float(state.py)), "")
	if not created.ok: return created
	var destination: Dictionary = created.roster
	var formation := int(destination.crowd_formation)
	# Native move_member keeps a soldier inside his team's slot; leaving for another team (and slot) is leave_member.
	# Same native faction slot (an own-team leave, Nekki 11/11 A): move_member; another faction: leave_member.
	var moved_native: bool = bool(crowd.move_member(native_index, formation)) if _native_faction(faction) == int(entry.get("native_faction", -1)) 		else crowd.has_method("leave_member") and bool(crowd.leave_member(native_index, formation))
	if not moved_native:
		return SiteRuntime.fail("NATIVE_REFUSED", "原生群眾拒絕此人離隊；此人未移動")
	var held_before: bool = roster_post_holders(int(roster.team_id)).has(identity)
	# Unit indices of the old roster shift when the row leaves: commanders, officers and abilities are remapped as
	# split_roster remaps them (native_transfer_records remaps officer_service itself).
	var keep_map := {}
	for at in range(roster.units.size()):
		if at != index: keep_map[at] = keep_map.size()
	var old_abilities: Array = roster.get("abilities", []).duplicate(true)
	native_transfer_records(ids, roster, destination)
	for field: String in ["formal_commander", "acting_commander", "current_commander"]:
		if roster.has(field): roster[field] = _remap_index(int(roster[field]), keep_map)
	if roster.has("officers"): roster["officers"] = _remap_list(roster.officers, keep_map)
	roster["abilities"] = _remap_abilities(old_abilities.duplicate(true), keep_map)
	destination["abilities"] = _remap_abilities(old_abilities, {index: 0})
	var officer_persons: Array = []
	for officer: Variant in roster.get("officers", []):
		if int(officer) >= 0 and int(officer) < roster.units.size(): officer_persons.append(int(roster.units[int(officer)].person_id))
	if not set_formation_fields(int(owner.formation_index), {"officer_persons": officer_persons}):
		return SiteRuntime.fail("INVALID_ROLE", "原生軍官列表寫入失敗")
	if roster.has("offices"):
		SiteOffices.vacate_unless(roster.offices, func(holder: int) -> bool: return holder != identity)
	for row: Dictionary in destination.units: row["member"] = true
	destination["formal_commander"] = 0
	destination["offices"] = SiteOffices.default_offices("team", identity, false)
	if remember_origin: destination["left_from_team_id"] = int(roster.team_id) # The team a rejoin returns to (Nekki 11/11 A).
	if not set_formation_fields(formation, {"formal_person": identity}):
		return SiteRuntime.fail("NATIVE_REFUSED", "原生群眾拒絕指定隊長；此人已移入新隊")
	var holds := roster_post_holders(team_id).has(identity)
	if holds != held_before and not bool(crowd.set_post_holder(int(_index_by_id[identity]), int(holds))):
		return SiteRuntime.fail("INVALID_ROLE", "原生職位旗標寫入失敗")
	_refresh_bodies()
	var synced: Dictionary = sync_to_site()
	if not synced.ok: return synced
	return SiteRuntime.ok("", {"team_id": team_id, "formation": formation})


## Nekki 2026-11-11 (A): a member who leaves its team stays on the Site as the captain of its own one-person team of the
## same faction (detach_to_new_team; no leaderless solo, the 11/01 rule). The team it left is remembered for a rejoin.
func leave_to_own_team(identity: int) -> Dictionary:
	var owner: Variant = _owner_by_id.get(identity)
	if owner == null: return SiteRuntime.fail("UNSUPPORTED", "此人不在原生群眾名冊")
	return detach_to_new_team(identity, int(owner.faction_id), true)


## Nekki 2026-11-11 (A): the captain of a one-person team made by leave_to_own_team rejoins the team it left: the native
## soldier moves into that formation (leave_member), its row follows (native_transfer_records), its posts in the left
## one-person team end with it. The emptied one-person team keeps its native formation (formations are never removed)
## and an empty roster, as any team whose members are all gone. Refusals before the native move change nothing.
func rejoin_original_team(identity: int) -> Dictionary:
	if not active or crowd == null or not crowd.has_method("leave_member"): return SiteRuntime.fail("UNSUPPORTED", "群眾未啟用")
	if _actors.has(identity) or not _index_by_id.has(identity) or not _owner_by_id.has(identity): return SiteRuntime.fail("UNSUPPORTED", "此人不在原生群眾名冊")
	var solo: Dictionary = {}
	for candidate: Dictionary in rosters:
		if _roster_index_for_person(candidate, identity) >= 0: solo = candidate
	if solo.is_empty() or solo.units.size() != 1 or not solo.has("left_from_team_id"): return SiteRuntime.fail("BUSY", "已在隊伍中，不能重複入隊")
	var destination: Dictionary = {}
	for candidate: Dictionary in rosters:
		if int(candidate.get("team_id", -1)) == int(solo.left_from_team_id): destination = candidate
	if destination.is_empty() or int(destination.get("faction_id", -1)) != int(solo.get("faction_id", -2)) or not str(destination.get("garrison_feature_id", "")).is_empty():
		return SiteRuntime.fail("NO_TARGET", "原隊伍已不在此地或不同陣營")
	var owner: Variant = _owner_by_id[identity]
	var native_index := int(_index_by_id[identity])
	if not _split_exit_ready(owner, native_index): return SiteRuntime.fail("NOT_READY", "此人作業或動作尚未收束")
	if not bool(crowd.move_member(native_index, int(destination.crowd_formation))): # Same faction slot: a member move.
		return SiteRuntime.fail("NATIVE_REFUSED", "原生群眾拒絕此人歸隊；此人未移動")
	native_transfer_records([identity], solo, destination)
	for row: Dictionary in destination.units:
		if int(row.person_id) == identity: row["member"] = true
	solo.erase("left_from_team_id") # The emptied team keeps an empty roster: the Store pairs every native formation with one.
	_refresh_bodies()
	var synced: Dictionary = sync_to_site()
	if not synced.ok: return synced
	return SiteRuntime.ok("已回到原隊伍；原人物與持物不變", {"team_id": int(destination.team_id)})


## Bandit spec §6.4 (B3): the formal captaincy of a live crowd team passes to `identity`, a member of the same team (the
## team keeps its formation, slot, faction and members). The native formal/acting/current person, the roster's commander
## indices, the head seat and the officer list follow; the new captain's other seat is vacated (one person, one seat).
## The old captain stays an ordinary member. Refusals change nothing.
func hand_over_captain(team_id: int, identity: int) -> Dictionary:
	if not active or crowd == null: return SiteRuntime.fail("UNSUPPORTED", "群眾未啟用")
	var roster: Dictionary = native_roster(team_id)
	var owner: Variant = native_owner(team_id)
	if roster.is_empty() or owner == null: return SiteRuntime.fail("NO_TARGET", "找不到群眾隊伍")
	var index := _roster_index_for_person(roster, identity)
	if index < 0 or _actors.has(identity) or not _index_by_id.has(identity): return SiteRuntime.fail("INVALID", "新隊長須是本隊的群眾成員")
	if index == int(roster.get("formal_commander", -1)): return SiteRuntime.ok("", {"changed": false})
	if not str(roster.get("garrison_feature_id", "")).is_empty(): return SiteRuntime.fail("BUSY", "駐營隊伍不能換隊長")
	var officers: Array = []
	for officer: Variant in roster.get("officers", []):
		if int(officer) != index: officers.append(int(officer))
	var officer_persons: Array = []
	for officer: Variant in officers:
		if int(officer) >= 0 and int(officer) < roster.units.size(): officer_persons.append(int(roster.units[int(officer)].person_id))
	if not set_formation_fields(int(owner.formation_index), {"formal_person": identity, "acting_person": identity, "current_person": identity, "officer_persons": officer_persons}):
		return SiteRuntime.fail("NATIVE_REFUSED", "原生群眾拒絕指定新隊長")
	var held_before: bool = roster_post_holders(team_id).has(identity)
	roster["formal_commander"] = index
	roster["acting_commander"] = index
	roster["current_commander"] = index
	roster["officers"] = officers
	if roster.get("offices") is Dictionary and not roster.offices.is_empty():
		SiteOffices.vacate_unless(roster.offices, func(holder: int) -> bool: return holder != identity)
		var head := SiteOffices.head_position(roster.offices)
		if not head.is_empty(): head["holder"] = identity
		roster.offices["revision"] = mini(SiteOffices.MAX_SEQ, int(roster.offices.get("revision", 0)) + 1)
	var holds := roster_post_holders(team_id).has(identity)
	if holds != held_before and not bool(crowd.set_post_holder(int(_index_by_id[identity]), int(holds))):
		return SiteRuntime.fail("INVALID_ROLE", "原生職位旗標寫入失敗")
	_refresh_bodies()
	var synced: Dictionary = sync_to_site()
	if not synced.ok: return synced
	return SiteRuntime.ok("", {"changed": true})


## G6.5: the native exit gate for a split. It refuses a host-controlled soldier, and the controlled cadre leads the split,
## so his host control is handed back for the query and then restored; nothing else changes.
func _split_exit_ready(owner: Variant, index: int, aboard_vehicle: int = -1) -> bool:
	var host_held := index == player_index
	if host_held: crowd.set_host_control(index, false)
	var ready := bool(owner.site_exit_ready(index, aboard_vehicle))
	if host_held: crowd.set_host_control(index, true)
	return ready

## SHIPSEA: the native vessel a member of a departing team is aboard, or -1 (land gate). Only an embarked team (a sea
## departure) asks the aboard gate; a land departure keeps the land gate, which refuses an aboard soldier.
func _departure_vessel(owner: Variant, index: int, team_sea: bool) -> int:
	if not team_sea: return -1
	var state: Array = owner.native_aboard(index)
	return int(state[1]) if state.size() == 2 and bool(state[0]) else -1


## G6.5: read-only plan for a cadre-led sub-party. `leader` (the cadre) comes first in `people`; `members` are ordinary
## members of the same team. Nothing is released here. Refusal codes: CADRE_REQUIRED, CAPTAIN_REQUIRED, MEMBER_CADRE,
## INVALID_MEMBERS, WHOLE_TEAM, NOT_READY. The caller passes the controlled cadre as `leader`.
func split_departure_plan(leader: int, members: Array) -> Dictionary:
	if not active or crowd == null: return SiteRuntime.fail("UNSUPPORTED", "群眾未啟用")
	if _actors.has(leader) or not _index_by_id.has(leader): return SiteRuntime.fail("UNSUPPORTED", "群眾中的 actor 本體尚不能分隊出發")
	if not pending_captivity.is_empty(): return SiteRuntime.fail("BUSY", "群眾俘虜事件尚未結束")
	var roster: Dictionary = {}
	for candidate: Dictionary in rosters:
		if _roster_index_for_person(candidate, leader) >= 0:
			roster = candidate
			break
	if roster.is_empty(): return SiteRuntime.fail("NO_TARGET", "群眾中沒有此人的隊伍")
	if not str(roster.get("garrison_feature_id", "")).is_empty(): return SiteRuntime.fail("BUSY", "駐營隊伍須整隊移動，尚不能分隊")
	var leader_index := _roster_index_for_person(roster, leader)
	if leader_index == int(roster.get("formal_commander", -1)): return SiteRuntime.fail("CAPTAIN_REQUIRED", "正式隊長須沿整隊出發")
	if not cadre_index(roster, leader_index): return SiteRuntime.fail("CADRE_REQUIRED", "分隊須由幹部帶隊")
	var group: Array[int] = [leader]
	for entry: Variant in members:
		var member := int(entry)
		var member_index := _roster_index_for_person(roster, member)
		if member < 1 or group.has(member) or member_index < 0: return SiteRuntime.fail("INVALID_MEMBERS", "分隊隊員須為同隊且不重複的人物")
		if member_index == int(roster.get("formal_commander", -1)): return SiteRuntime.fail("CAPTAIN_REQUIRED", "正式隊長須沿整隊出發")
		if cadre_index(roster, member_index): return SiteRuntime.fail("MEMBER_CADRE", "一次只能由一名幹部分隊")
		group.append(member)
	if group.size() >= roster.units.size(): return SiteRuntime.fail("WHOLE_TEAM", "全隊人員請整隊出發")
	var people: Array[int] = []
	var cells: Array[Vector2i] = []
	for member: int in group:
		if not _index_by_id.has(member) or _actors.has(member) or has_pending_capture(member):
			return SiteRuntime.fail("NOT_READY", "隊員尚有原生事件；保留原進度")
		var owner: Variant = person_owner(member)
		if owner == null or not _split_exit_ready(owner, int(_index_by_id[member])):
			return SiteRuntime.fail("NOT_READY", "隊員不在可出發狀態（倒地、交換中或有未完成動作）")
		var state := soldier_state(int(_index_by_id[member]))
		people.append(member)
		cells.append(Vector2i(floori(float(state.px)), floori(float(state.py))))
	return SiteRuntime.ok("", {"roster": roster, "team_id": int(roster.team_id), "faction": int(roster.faction_id),
		"people": people, "cells": cells, "leader": leader})


## G6.5: releases the people of a split plan that split_departure_plan passed. The team stays live: its formation and
## remaining soldiers stay native, its entry keeps the rest in person_ids and names the released people in
## departed_person_ids, and the roster is rewritten in place to the remaining team. Returns the departing party roster
## (a copy with `team_id`, crowd = true). Release is irreversible: callers pre-validate the extraction on a copy first.
## The travelling party is returned as `army`: a complete grid army snapshot (split_army_snapshot), converted before any
## release, so a conversion refusal releases nobody.
func split_departure_release(plan: Dictionary, team_id: int) -> Dictionary:
	if not plan.get("ok", false): return plan
	var roster: Dictionary = plan.roster
	var group: Array = plan.people
	var formation := int(roster.crowd_formation)
	# Converted from the live rows before any release (it reads the native soldier state, which a release removes).
	var army_conversion := split_army_snapshot(plan, team_id)
	if not army_conversion.ok: return army_conversion
	var released: Array[int] = []
	for entry: Variant in group:
		var identity := int(entry)
		var index := int(_index_by_id[identity])
		var owner: Variant = person_owner(identity)
		var receipt: Dictionary = {}
		# The native exit gate refuses a host-controlled soldier, so the controlled leader's host control is handed back
		# first. The leader is released first; if that refuses, the host control is restored and nobody has left.
		var host_held := index == player_index
		if host_held: crowd.set_host_control(index, false)
		if owner != null: receipt = owner.release_for_departure(index)
		if receipt.is_empty():
			if host_held: crowd.set_host_control(index, true)
			return SiteRuntime.fail("RELEASE_REFUSED", "原生釋放被拒（已釋放 %d 人）；請重新檢查" % released.size())
		if host_held: player_index = -1
		released.append(identity)
		_apply_release_receipt(roster, identity, receipt)
		var record: Dictionary = _records.get(identity, {})
		var key := str(_ammo_keys.get(identity, ""))
		if not record.is_empty() and not key.is_empty():
			var cargo: Dictionary = record.get("cargo", {})
			if int(receipt.ammo) > 0: cargo[key] = int(receipt.ammo)
			else: cargo.erase(key)
		if owner != null: owner.records.erase(index)
	for identity: int in released:
		_index_by_id.erase(identity)
		_owner_by_id.erase(identity)
		_records.erase(identity)
	for team: Dictionary in teams:
		if int(team.formation) != formation or bool(team.get("departed", false)): continue
		var kept_ids: Array = []
		for identity: Variant in team.person_ids:
			if not released.has(int(identity)): kept_ids.append(int(identity))
		team["person_ids"] = kept_ids
		var gone: Array = team.get("departed_person_ids", [])
		for identity: int in released: gone.append(identity)
		team["departed_person_ids"] = gone
	# The live roster becomes the remaining team (renumbered in place); the party itself is the converted army above.
	split_roster(roster, group, team_id)
	_refresh_bodies() # The party leaves no presenter; the renumbered remaining roster keeps its cadre bodies.
	return SiteRuntime.ok("", {"roster": roster, "army": army_conversion.snapshot, "released": released.size()})


## G6.5: the sub-party a split of `plan` travels with, as a complete grid army snapshot (the same conversion as a whole
## team's, roster_snapshot). The input describes the split group only: split_roster of a copy, with the team's formation
## index kept; the cadre (the group's first person) is the formal commander. Read-only: nothing is released and the live
## roster is not changed. Returns {ok, snapshot} or a refusal.
func split_army_snapshot(plan: Dictionary, team_id: int) -> Dictionary:
	var roster: Dictionary = plan.roster
	var group_input: Dictionary = split_roster(roster.duplicate(true), plan.people, team_id)
	group_input["crowd_formation"] = int(roster.crowd_formation)
	return ClearHandoff.roster_snapshot(self, group_input, int(plan.people[0]))


## G6.5: splits one roster for a sub-party. `group` lists the departing person ids, the cadre first. Returns the departing
## party as a copy (rows in group order, formal captain = 0, the cadre holds the captain's head seat). `roster` itself
## becomes the remaining team: its rows and every index field are renumbered, and a departing cadre's seat is vacated.
static func split_roster(roster: Dictionary, group: Array, team_id: int) -> Dictionary:
	var leader := int(group[0])
	var departing: Dictionary = roster.duplicate(true)
	var go_map := {}
	var departing_units: Array = []
	for at in range(group.size()):
		var index := _roster_index_for_person(roster, int(group[at]))
		go_map[index] = at
		departing_units.append(departing.units[index])
	var keep_map := {}
	var keep_rows: Array = []
	for index in range(roster.units.size()):
		if go_map.has(index): continue
		keep_map[index] = keep_rows.size()
		keep_rows.append(roster.units[index])
	for row: Dictionary in departing_units: row["member"] = true
	var leader_cell: Array = departing_units[0].get("cell", [0, 0])
	departing["units"] = departing_units
	departing["team_id"] = team_id
	departing["crowd"] = true
	departing["formal_commander"] = 0
	departing["acting_commander"] = 0
	departing["current_commander"] = 0
	departing["officers"] = []
	departing["officer_service"] = []
	departing["abilities"] = _remap_abilities(departing.get("abilities", []), go_map)
	departing["vacancies"] = []
	departing["rescues"] = []
	departing["player_member"] = {}
	departing["offices"] = SiteOffices.default_offices("team", leader, false)
	departing["combat_order"] = 0
	departing["goal"] = [-1, -1]
	departing["reference"] = [float(leader_cell[0]) + 0.5, float(leader_cell[1]) + 0.5]
	departing.erase("team_fatigue")
	departing.erase("crowd_formation")
	departing.erase("crowd_state")
	roster["units"] = keep_rows
	for field: String in ["formal_commander", "acting_commander", "current_commander"]:
		if roster.has(field): roster[field] = _remap_index(int(roster[field]), keep_map)
	for field: String in ["officers", "officer_service"]:
		if roster.has(field): roster[field] = _remap_list(roster[field], keep_map)
	roster["abilities"] = _remap_abilities(roster.get("abilities", []), keep_map)
	if roster.has("offices"):
		SiteOffices.vacate_unless(roster.offices, func(holder: int) -> bool: return not group.has(holder))
	return departing


static func _remap_index(value: int, remap: Dictionary) -> int:
	if value == TerrainArmy.PLAYER_MEMBER: return value
	return int(remap[value]) if remap.has(value) else -1


static func _remap_list(values: Array, remap: Dictionary) -> Array:
	var kept: Array = []
	for value: Variant in values:
		var index := int(value)
		if index == TerrainArmy.PLAYER_MEMBER: kept.append(index)
		elif remap.has(index): kept.append(int(remap[index]))
	return kept


static func _remap_abilities(abilities: Array, remap: Dictionary) -> Array:
	var kept: Array = []
	for ability: Variant in abilities:
		if not ability is Dictionary: continue
		var unit := int(ability.get("unit", -1))
		if unit != TerrainArmy.PLAYER_MEMBER:
			if not remap.has(unit): continue
			ability["unit"] = int(remap[unit])
		kept.append(ability)
	return kept


static func _apply_release_receipt(roster: Dictionary, identity: int, receipt: Dictionary) -> void:
	for unit: Dictionary in roster.units:
		if int(unit.person_id) != identity: continue
		unit["hp"] = float(receipt.hp)
		unit["fatigue"] = float(receipt.fatigue)
		unit["fatigue_rest"] = float(receipt.fatigue_rest)
		unit["cell"] = [receipt.cell.x, receipt.cell.y]
		unit["crowd_position"] = [receipt.position.x, receipt.position.y]
		return


## region_checkpoint: a region checkpoint / bind / replay capture (admits siege work in progress, KW21); an ordinary save keeps
## the Store's own siege guard, as the grid Site's ordinary save does.
func capture_save(region_checkpoint: bool = false) -> Dictionary:
	var guard := save_guard(region_checkpoint)
	if not guard.ok: return guard
	if not sync_terrain(): return SiteRuntime.fail("INVALID_TERRAIN", "群眾地形未同步")
	var siege_inputs := sync_siege_inputs()
	if not siege_inputs.ok: return siege_inputs
	var synced := sync_to_site()
	if not synced.ok: return synced
	var bytes: PackedByteArray = crowd.save_state()
	# KW21: the native World refuses a save only during an unfinished work point or a pending housing step (G10); it retries.
	if bytes.is_empty(): return SiteRuntime.fail("BUSY", "原生身體步進尚未收束（住宅返家步或工作點）；下一步重試")
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return SiteRuntime.ok("", {"rosters": rosters.duplicate(true), "section": {"version": 1,
		"dll_sha256": FileAccess.get_sha256(DLL_PATH), "build_id": str(crowd.build_id()),
		"blob": Marshalls.raw_to_base64(bytes), "blob_sha256": digest.finish().hex_encode(),
		"teams": teams.duplicate(true), "player": _section_player(),
		"deploy": _deploy_options.duplicate(true)}})


## The saved controlled-person reference. With no controlled person (the controlled roster team departed and no actor
## stands in for it), it is the "no controlled person" pair -1/-1 the Store accepts, never the absent template's id 0.
func _section_player() -> Dictionary:
	var controlled := int(lab.controlled_person_id())
	if controlled <= 0: return {"person_id": -1, "soldier_index": -1}
	return {"person_id": controlled, "soldier_index": player_index}


## bind_context: the region context a bind validates a projected candidate under when the candidate carries no
## region_snapshot of its own (TerrainLab._region_project_original_bind_child).
func prepare_load(data: TerrainData, native_candidate: Variant = null, bind_context: Dictionary = {}) -> Dictionary:
	# KW21: a load admits siege work in progress, as a region checkpoint and a reopen do. Saved data with a siege action in
	# progress comes only from a region checkpoint (an ordinary save refuses it); its native blob carries the compounds and
	# crew steps and its owner graph the projectiles. The arrival bind's candidate has had the party inserted and carries no
	# region_snapshot any more (found 2026-11-10: a player arriving at a crowd Site whose NPC ballista was mid-action was
	# refused BUSY at commit_arrival, through the cold owner's own live siege guard on the candidate).
	var siege_guard := siege_admission_guard(data, true)
	if not siege_guard.ok: return siege_guard
	# All original saved Site validators run before rebuilding the native
	# candidate navigation. The supplied native remains byte-checked.
	# A Region snapshot Site validates as its Store load does, with the snapshot's own context (2026-11-08: a ration
	# delivery saved there is its region recipe, which an ordinary save refuses as BUSY).
	var region_context: Dictionary = bind_context
	var snapshot: Variant = data.site.get("region_snapshot")
	# An arrival bind's candidate (the destination with the party inserted) carries no region_snapshot of its own any more;
	# the bind passes its region context, so a mid-action siege vehicle validates as the bind's own capture admits it
	# (found 2026-11-10: it read CORRUPT_SAVE "攻城作業尚未收束" under the ordinary save rule).
	if snapshot is Dictionary and snapshot.get("context") is Dictionary: region_context = snapshot.context
	var checked := SiteStore._validate_state(data, data.site, clampi(OS.get_processor_count(), 1, 8), native_candidate, region_context)
	if not checked.ok: return checked
	if not TerrainArmy.load_combat_bake() or not TerrainArmy.prewarm_soldier_atlas():
		return SiteRuntime.fail("MISSING_ASSET", "士兵圖集不可用")
	var candidate_host_fire := false
	var candidate_crowd: Variant = checked.crowd_native
	# S5: every convoy record must name the native convoy that the blob restored (same anchor cell, same operator as its only crew).
	# Refused before anything is installed; the live Site is kept.
	var convoy_check: Dictionary = SiteVehicleTransport.convoy_record_check(data, candidate_crowd)
	if not convoy_check.ok: return convoy_check
	# G1 S2: every saved ship passenger must match the native aboard state (same vehicle; no stray aboard soldier).
	var ship_check: Dictionary = SiteVehicleTransport.ship_record_check(data, candidate_crowd)
	if not ship_check.ok: return ship_check
	if candidate_crowd.has_method("fire_host_protocol") and candidate_crowd.has_method("set_host_ranged_delegate") \
		and candidate_crowd.has_method("set_fire_safe_rest_input") \
		and int(candidate_crowd.fire_host_protocol()) == 1:
		if not bool(candidate_crowd.set_host_ranged_delegate(true)):
			return SiteRuntime.fail("CROWD_FIRE_BRIDGE_BUSY", "存檔 Native 舊彈體尚未收束；原現場保留")
		candidate_host_fire = true
	# Install the candidate that just passed every native/record/build check.
	crowd = candidate_crowd
	_terrain_revision = data.navigation_revision
	_occupancy_cache.clear()
	_staged_data = data
	teams.assign(data.site.crowd.teams)
	_deploy_options = data.site.crowd.deploy
	player_index = int(data.site.crowd.player.soldier_index)
	rosters.clear()
	_records.clear()
	_no_atlas.clear()
	var appearances: Array = []
	var audio_mounts := PackedByteArray()
	var actor_ids := {}
	for actor: Dictionary in data.site.actors.values(): actor_ids[int(actor.person_id)] = actor
	for roster: Dictionary in data.site.armies:
		if not bool(roster.get("crowd", false)): continue
		rosters.append(roster)
		for row: Dictionary in roster.units: _records[int(row.person_id)] = row
	var departed := _departed_people()
	for identity in crowd.person_ids():
		if departed.has(int(identity)):
			# G6.4b: a released soldier keeps its native slot but no kit, appearance or record.
			appearances.append(null)
			audio_mounts.append(0)
		elif actor_ids.has(int(identity)):
			var saved: Dictionary = actor_ids[int(identity)]
			var appearance := SiteRuntime.equipment_appearance(data, saved.item_state, saved.appearance)
			# CAV-3, as in _appearance_now: a saved Actor keeps its own riding state, which equipment_appearance alone clears.
			if not appearance.is_empty() and bool(saved.appearance.get("mounted", false)): appearance["mounted"] = true
			if not _prepare_contact_appearance(appearance, int(identity), true): return SiteRuntime.fail("MISSING_ASSET", "存檔原 actor 同 body 接觸資源未備妥")
			appearances.append(null)
			audio_mounts.append(1 if bool(appearance.get("mounted", false)) else 0)
		else:
			var appearance := _appearance(int(identity))
			if not _prepare_contact_appearance(appearance, int(identity)): return SiteRuntime.fail("MISSING_ASSET", "存檔原士兵同 body 接觸資源未備妥")
			if atlas_cannot_draw(appearance):
				_no_atlas[int(identity)] = true # S2: the loaded created look is drawn by its body (activate_loaded).
				appearances.append(null)
			else:
				appearances.append(appearance)
			audio_mounts.append(1 if bool(appearance.get("mounted", false)) else 0)
	_headless_unadmitted_bodied(appearances, crowd.person_ids())
	if not _register_kits(appearances, audio_mounts): return SiteRuntime.fail("MISSING_ASSET", "存檔士兵外觀不被圖集接受")
	_host_fire_active = candidate_host_fire
	return SiteRuntime.ok()


func activate_loaded() -> void:
	# KW21: the staged blob was validated with its compounds (SiteStore._validate_crowd_siege_crew); a reopen mid siege action is admitted.
	var siege_guard := siege_admission_guard(_staged_data, true)
	if not siege_guard.ok:
		last_event_error = siege_guard
		return
	_original_team_plans.clear()
	for roster: Dictionary in rosters:
		var source: TerrainArmy
		for candidate: TerrainArmy in lab.combat_armies:
			if candidate.team_id == int(roster.team_id):
				source = candidate
				break
		if source == null or source.combat_enabled:
			last_event_error = SiteRuntime.fail("INVALID_CROWD_OWNER", "存檔原隊伍命令 owner 未就緒")
			return
		_original_team_plans.append({"source": source, "roster": roster})
	_actors.clear()
	for actor: TerrainTestCharacter in lab.combat_actors:
		if int(crowd.soldier_index(actor.person_id)) >= 0: _actors[actor.person_id] = actor
	_staged_data = null
	_bind_people()
	_rebuild_rider_ids()
	var siege_inputs := sync_siege_inputs()
	if not siege_inputs.ok:
		last_event_error = siege_inputs
		return
	active = true
	_fire_visual_dirty = _host_fire_active
	if not sync_fire_visuals():
		last_event_error = SiteRuntime.fail("INVALID_FIRE_VISUAL", "原 Native 火體外觀投影失敗")
		return
	for identity: int in _actors: _sync_actor(identity)
	# Nothing about bodies is saved: the loaded rosters, control and native refs give the same bodied set.
	_clear_bodies()
	_refresh_bodies()
	# The saved hostility table already holds joined-team alliances; re-assert them from the teams (idempotent).
	if not _apply_slot_alliances(): last_event_error = SiteRuntime.fail("INVALID", "原生陣營敵對表無法還原")
	_begin_player()
	_make_panel()
	_prewarm_captivity_atlases.call_deferred()


## Per-Site native faction slot (Nekki 2026-11-03: local mapping, native unchanged). Global faction ids are unbounded;
## native hostility indexes 0..255 (a & 255), with a slot never its own enemy. Each teams entry records its slot
## ("native_faction"; older entries used the global id). A faction keeps one slot on the Site; every neutral team gets
## a slot of its own, so native fights two neutral teams as it fights any two factions. -1: no free slot.
func _native_faction(faction: int) -> int:
	return native_slot_for(faction, teams)


## Nekki 2026-11-04 (C): a whole team joins another faction. Native keeps the team's formation and slot; the slot's native
## hostility is made to match the new faction (allied with that faction's other slots, hostile to everyone else), and the
## hostility table is saved in the blob. A slot shared with other teams cannot change faction (leaving is a later flow).
func relabel_team_faction(team_id: int, faction: int) -> Dictionary:
	if not active or crowd == null: return SiteRuntime.fail("UNSUPPORTED", "群眾未啟用")
	if faction < 0: return SiteRuntime.fail("INVALID", "勢力不合法")
	var entry: Dictionary = {}
	for team: Dictionary in teams:
		if int(team.team_id) == team_id and not bool(team.get("solo", false)) and not bool(team.get("departed", false)): entry = team
	if entry.is_empty(): return SiteRuntime.fail("NO_TARGET", "找不到群眾隊伍")
	if int(entry.faction) == faction: return SiteRuntime.ok("", {"changed": false})
	var slot := native_faction_of(entry)
	for team: Dictionary in teams:
		if team != entry and native_faction_of(team) == slot: return SiteRuntime.fail("BUSY", "此隊與其他隊伍共用原生陣營槽，不能單獨改換勢力")
	var roster: Dictionary = {}
	for row: Dictionary in rosters:
		if int(row.team_id) == team_id: roster = row
	if roster.is_empty(): return SiteRuntime.fail("NO_TARGET", "找不到群眾隊伍名冊")
	entry["faction"] = faction
	roster["faction_id"] = faction
	for army: TerrainArmy in lab.combat_armies:
		if army.team_id == team_id: army.faction_id = faction
	if not _apply_slot_alliances(): return SiteRuntime.fail("INVALID", "原生陣營敵對表無法更新")
	_bind_people() # Owners read the team's faction.
	return SiteRuntime.ok("", {"changed": true, "slot": slot})


## Native hostility between every two used slots follows the factions that own them: allied when the same non-neutral
## faction owns both (a joined team keeps its own slot), hostile otherwise. Idempotent; also run after a load.
func _apply_slot_alliances() -> bool:
	if crowd == null or not crowd.has_method("set_hostile"): return false
	var registry: Dictionary = {}
	var now := 0.0
	if is_instance_valid(lab) and lab.site_controller != null and lab.site_controller.region_slot != null:
		registry = lab.site_controller.region_slot.control.get("faction_registry", {})
		now = float(lab.site_controller.region_slot.control.logical_game_seconds)
	var owner := {}
	for team: Dictionary in teams:
		if bool(team.get("departed", false)): continue
		owner[native_faction_of(team)] = int(team.faction)
	var slots: Array = owner.keys()
	for a in range(slots.size()):
		for b in range(a + 1, slots.size()):
			# Diplomacy (§11.1): same faction, or an active truce/peace between the two factions, keeps the slots apart from war.
			var allied := not RegionDiplomacy.hostile(registry, int(owner[slots[a]]), int(owner[slots[b]]), now)
			if not bool(crowd.set_hostile(int(slots[a]), int(slots[b]), not allied)): return false
	return true

## The slot rule of _native_faction over any teams entries (the Region arrival builds its native offline).
static func native_slot_for(faction: int, entries: Array) -> int:
	var used := {}
	for team: Dictionary in entries:
		var slot := native_faction_of(team)
		used[slot] = true
		if faction != RegionFactionQuery.NEUTRAL_FACTION_ID and int(team.faction) == faction: return slot
	if faction >= 0 and faction < RegionFactionQuery.NEUTRAL_FACTION_ID and not used.has(faction): return faction
	for slot in range(RegionFactionQuery.NEUTRAL_FACTION_ID, -1, -1):
		if not used.has(slot): return slot
	return -1


## Nekki 2026-11-04: a team's carried morale state (TerrainArmy.team_morale) written onto its native formation. {} keeps the
## formation's fresh values. Works on a live or a detached ArmyCrowd.
static func apply_team_morale(native: Object, formation: int, morale: Variant) -> bool:
	if not morale is Dictionary or morale.is_empty(): return true
	if not TerrainArmy.valid_team_morale(morale): return false
	var values: PackedFloat64Array = native.call("get_formation_state", formation)
	var refs: PackedInt64Array = native.call("formation_refs", formation)
	for key: String in ["morale", "routed", "rally_rest"]:
		var at := FORMATION_FIELDS.find(key)
		if at < 0 or at >= values.size(): return false
		values[at] = float(morale[key])
	return bool(native.call("set_formation_state", formation, values, refs))


## The team_morale of a native formation, for a crowd team leaving as a GD army (departure, split, clear).
func team_morale_of(formation: int) -> Dictionary:
	var state := formation_state(formation)
	if state.is_empty(): return {}
	return {"morale": clampf(float(state.morale), 0.0, 100.0), "routed": bool(state.routed), "rally_rest": maxf(0.0, float(state.rally_rest))}


static func native_faction_of(team: Dictionary) -> int:
	return int(team.get("native_faction", team.get("faction", -1)))


func discard_on_replace() -> void:
	_dispose()


func _ensure_kit(appearance: Dictionary) -> int:
	if view == null or crowd == null: return -1
	var key := JSON.stringify(appearance)
	if _kit_cache.has(key): return int(_kit_cache[key])
	# The existing page/dye admission remains authoritative; no baseline fallback.
	var description: Dictionary = view._describe(appearance)
	if description.is_empty(): return -1
	var kit := _make_kit(int(description.page), int(description.palette), appearance, _kit_windows)
	if kit < 0: return -1
	view._palette_texture.update(view._palette_image)
	if not bool(crowd.render_set_windows(_kit_windows)): return -1
	_kit_cache[key] = kit
	return kit


func _update_kit(index: int, appearance: Dictionary, identity: int = 0) -> void:
	if view == null: return
	var was_unatlased := _no_atlas.has(identity)
	if identity > 0 and atlas_cannot_draw(appearance):
		# S2 sticky rule: the person keeps (or gains) a body; native draws nothing at this index.
		_no_atlas[identity] = true
		_audio_mount_update(index, false)
		if _kit_ids[index] != -1:
			_kit_ids[index] = -1
			_kit_ids_dirty = true
		if not was_unatlased: _refresh_bodies()
		return
	var kit := _ensure_kit(appearance)
	if kit < 0:
		last_event_error = SiteRuntime.fail("MISSING_ASSET", "士兵實物外觀不被圖集接受")
		return
	if was_unatlased:
		_no_atlas.erase(identity)
		_refresh_bodies() # Drawable again: a person who is not otherwise bodied returns to the atlas.
	_audio_mount_update(index, bool(appearance.get("mounted", false)))
	if _kit_ids[index] == kit: return
	_kit_ids[index] = kit
	_kit_ids_dirty = true


func _flush_kit_ids() -> bool:
	if not _kit_ids_dirty and not _body_kits_dirty: return true
	if crowd != null and bool(crowd.render_set_kits(_render_kit_ids())):
		_kit_ids_dirty = false
		_body_kits_dirty = false
		return true
	last_event_error = SiteRuntime.fail("INVALID", "群眾外觀索引未完整提交")
	return false


# ---------------------------------------------------------------- bodied roster members (S1)
## The per-soldier kits submitted to native: the atlas truth with -1 ("not drawn") at every live body.
func _render_kit_ids() -> PackedInt32Array:
	if _bodies.is_empty(): return _kit_ids
	var ids := _kit_ids.duplicate()
	for identity: int in _bodies:
		var index := int(_index_by_id.get(identity, -1))
		if index >= 0 and index < ids.size(): ids[index] = -1
	return ids


## Read-only copies for tests and tools.
func render_kit_ids() -> PackedInt32Array:
	return _render_kit_ids().duplicate()


func bodied_people() -> Array[int]:
	var result: Array[int] = []
	for identity: int in _body_set: result.append(identity)
	return result


## The bodied people of a Site, the one rule shared by live admission and load (nothing is saved for it). A person is
## bodied when controlled, the formal commander, a cadre (officers, officer_service, a non-head office seat), a military
## officer, or named by the native formation refs (formal, acting, current commander, officers). Keys keep the budget
## order: the controlled person first, then each roster in order. S2 sticky rule: a person whose look the atlas cannot
## draw (no_atlas, kit -1) is always bodied, so a demoted cadre with a created look keeps the body and is never refused.
static func bodied_ids(site_rosters: Array, controlled_id: int, native: Variant = null, no_atlas: Dictionary = {}) -> Dictionary:
	var result := {}
	if controlled_id > 0: result[controlled_id] = true
	for roster: Dictionary in site_rosters:
		var units: Array = roster.get("units", [])
		var marked := {}
		var formal := int(roster.get("formal_commander", -1))
		if formal >= 0 and formal < units.size(): marked[formal] = true
		for field: String in ["officers", "officer_service"]:
			for entry: Variant in roster.get(field, []):
				var at := int(entry)
				if at >= 0 and at < units.size(): marked[at] = true
		var holders := {}
		var offices: Variant = roster.get("offices", {})
		if offices is Dictionary:
			for seat: Variant in offices.get("positions", []):
				if seat is Dictionary and not bool(seat.get("head", false)) and int(seat.get("holder", 0)) > 0: holders[int(seat.holder)] = true
		var members := {}
		for at in range(units.size()):
			var row: Dictionary = units[at]
			var identity := int(row.get("person_id", 0))
			if identity <= 0: continue
			members[identity] = true
			if marked.has(at) or holders.has(identity) or no_atlas.has(identity) or str(row.get("military_role", "")) == "officer": result[identity] = true
		if native != null and roster.has("crowd_formation") and native.has_method("formation_refs"):
			var refs: PackedInt64Array = native.formation_refs(int(roster.crowd_formation))
			for at in range(refs.size()):
				if at == 3: continue # target_person is a target, not a commander.
				if members.has(int(refs[at])): result[int(refs[at])] = true
	return result


## S2: a valid foot look the soldier atlas cannot draw (a created face, hair or civilian clothes). Such a person is bodied
## and native draws nothing at its index (kit -1), never a substitute atlas look. Riders keep the mounted atlas rules.
## Nekki 2026-11-11 (A): a headless run treats a foot look the crowd atlas cannot admit (for example a person with no gear
## at all, whose look is never published in a headless run's own appdata) as mechanics-only, as the 10/27 captive rule does:
## the person keeps a body (kit -1, as an unatlased created look) and nothing is drawn. A visual run is unchanged: an
## unadmitted look still refuses the kits. `appearances` is index-aligned with `ids`; refused entries become null.
func _headless_unadmitted_bodied(appearances: Array, ids: PackedInt64Array) -> void:
	if DisplayServer.get_name() != "headless": return
	var required: Array = []
	var at: Array[int] = []
	for index: int in appearances.size():
		var appearance: Variant = appearances[index]
		if appearance == null or bool(appearance.get("mounted", false)): continue
		required.append(appearance)
		at.append(index)
	if required.is_empty(): return
	var admitted: Dictionary = Atlas.admit_crowd_appearances(required, [])
	for failed: Variant in admitted.get("required_failed", []):
		var index := at[int(failed)]
		_no_atlas[int(ids[index])] = true
		appearances[index] = null


static func atlas_cannot_draw(appearance: Dictionary) -> bool:
	return not appearance.is_empty() and not bool(appearance.get("mounted", false)) \
		and HumanCharacter3DEditor.valid_appearance(appearance) and not Atlas.supports(appearance)


func unatlased_people() -> Array[int]:
	var result: Array[int] = []
	for identity: int in _no_atlas: result.append(identity)
	return result


## Cheap per-frame change detector for what has no hook: native commander refs, new teams, riders, control.
func _body_signature() -> PackedInt64Array:
	var sig := PackedInt64Array([_body_controlled_id(), rosters.size(), _index_by_id.size()])
	sig.append_array(PackedInt64Array(_rider_ids))
	if crowd == null or not crowd.has_method("formation_refs"): return sig
	for roster: Dictionary in rosters:
		if not roster.has("crowd_formation"): continue
		var refs: PackedInt64Array = crowd.formation_refs(int(roster.crowd_formation))
		sig.append(-1)
		sig.append_array(refs.slice(0, 3))
		if refs.size() > 4: sig.append_array(refs.slice(4))
	return sig


func _body_controlled_id() -> int:
	# Unit fixtures may host a CrowdSite on a bare lab without control.
	return int(lab.controlled_person_id()) if is_instance_valid(lab) and lab.has_method("controlled_person_id") else 0


## Bodies exist only where a presenter can draw; headless keeps the bookkeeping and the atlas.
static func bodies_display() -> bool:
	return DisplayServer.get_name() != "headless"


## Diffs bodied_ids against the live bodies. Gains create a presenter and overlay kit -1; losses free it, and the atlas
## kit (always kept current in _kit_ids) draws the person again. Beyond BODY_BUDGET, or when a presenter cannot be
## prepared, the person keeps the atlas. Riders keep the mounted atlas in S1. Never fails, never touches truth.
func _refresh_bodies(controlled: int = 0) -> void:
	if not active or crowd == null or not is_instance_valid(lab): return
	if controlled <= 0: controlled = _body_controlled_id()
	_body_sig = _body_signature()
	_body_pending = false
	var wanted := {}
	_body_overflow.clear()
	for identity: int in bodied_ids(rosters, controlled, crowd, _no_atlas):
		if not _index_by_id.has(identity) or _actors.has(identity) or _rider_ids.has(identity): continue
		if wanted.size() >= BODY_BUDGET:
			_body_overflow.append(identity)
			continue
		wanted[identity] = true
	_body_set = wanted
	for identity: int in _bodies.keys():
		if not wanted.has(identity): _drop_body(identity)
	for identity: int in _body_failed.keys():
		if not wanted.has(identity): _body_failed.erase(identity)
	if not bodies_display(): return
	var gained := 0
	for identity: int in wanted:
		if _bodies.has(identity) or _body_failed.has(identity): continue
		if gained >= BODY_GAINS_PER_REFRESH:
			_body_pending = true # render continues next frame; the atlas draws the person meanwhile.
			break
		gained += 1
		if not _gain_body(identity): _body_failed[identity] = true


func _gain_body(identity: int) -> bool:
	var appearance := _appearance(identity)
	if appearance.is_empty() or bool(appearance.get("mounted", false)): return false
	var body := TerrainTestCharacter.new()
	body.name = "CrowdBody_%d" % identity
	body.person_id = identity # Pose lookups only (siege work); a body is never registered as a person.
	body.data = lab.terrain
	body.combat_driven_by_lab = true # No advance_combat: the presenter never simulates.
	body.exchange_enabled = true # The exchange presenter seeks one pose per rendered frame, as actors under crowd.
	lab.add_child(body)
	if not body.prepare_contact_visual(appearance):
		lab.remove_child(body)
		body.free()
		return false
	body._saved_appearance = appearance.duplicate(true)
	body.set_process(true)
	_bodies[identity] = body
	_body_slots.erase(identity)
	_body_kits_dirty = true
	return true


func _drop_body(identity: int) -> void:
	var body: Variant = _bodies.get(identity)
	_bodies.erase(identity)
	_body_slots.erase(identity)
	_body_kits_dirty = crowd != null
	_free_body_node(body)


## equipment_changed for a bodied person: the presenter is re-dressed from the projected look.
func _redress_body(identity: int, appearance: Dictionary) -> void:
	_body_failed.erase(identity) # A new look may prepare; the next refresh retries.
	if not _bodies.has(identity):
		if _body_set.has(identity): _body_pending = true
		return
	var body: TerrainTestCharacter = _bodies[identity]
	if bool(appearance.get("mounted", false)) or not is_instance_valid(body) or body.editor == null:
		_drop_body(identity)
		return
	body._saved_appearance = appearance.duplicate(true)
	if not body.editor.restore_appearance(appearance):
		_drop_body(identity)
		_body_failed[identity] = true
		return
	_body_slots.erase(identity)


## A dropped presenter gives up its CrowdBody_<id> name at once: a queued node would keep it until the frame ends, and
## a body created meanwhile for the same person (a load re-creates every body in activate_loaded) would be renamed.
## It stays in the tree until freed, because the editor's deferred _open_when_run_as_scene needs get_tree().
static func _free_body_node(body: Variant, release_name: bool = true) -> void:
	if not is_instance_valid(body): return
	if release_name: body.name = "CrowdBodyFreed_%d" % body.get_instance_id()
	body.queue_free()


func _clear_bodies(release_names: bool = true) -> void:
	var had := not _bodies.is_empty()
	for body: Variant in _bodies.values(): _free_body_node(body, release_names)
	_bodies.clear()
	_body_set.clear()
	_body_overflow.clear()
	_body_failed.clear()
	_body_slots.clear()
	_body_sig = PackedInt64Array()
	_body_pending = false
	_body_kits_dirty = had and crowd != null


## D5 helper fragment. Pure prepare, native append/import, then one commit.
## Copy these methods into CrowdSite, or keep as a script helper with host argument.
const D5Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const D5Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")
const D5Timings = preload("res://scripts/terrain_lab/character_combat_timings.gd")

static func d5_prepare_existing(crowd_site: Variant) -> Dictionary:
	var siege_guard: Dictionary = crowd_site.siege_admission_guard()
	if not siege_guard.ok: return siege_guard
	var scene_lab: Variant = crowd_site.lab
	var plans: Array[Dictionary] = []
	var seen := {}
	var team_ids := {}
	var action_guard: Dictionary = scene_lab.site_controller.person_actions.save_guard()
	if not action_guard.ok:
		return action_guard
	var controlled := int(scene_lab.controlled_person_id())
	for actor: TerrainTestCharacter in scene_lab.combat_actors:
		var handoff: Variant = actor.get_meta(&"crowd_handoff", {})
		if actor.person_id != controlled and (not handoff is Dictionary or not handoff.has("solo_formation")): continue
		if not actor.projectiles.is_empty() or actor._rescue_left > 0.0:
			return D5Runtime.fail("BUSY", "原 actor 的彈體或救助尚未收束")
	for source: TerrainArmy in scene_lab.combat_armies:
		if not source.combat_enabled or not source.has_army():
			continue
		if not source.projectiles.is_empty() or not source._unit_rescues.is_empty():
			return D5Runtime.fail("BUSY", "原隊伍的飛行彈體或救助尚未收束，未切換模擬")
		if not source.pending_cadre().is_empty(): # v2 plan 3.5: unrepaired legacy cadre stay out of Crowd.
			return D5Runtime.fail("MIGRATION_REQUIRED", "隊伍 #%d 仍有待分職幹部（舊存檔遷移）；請先在職位頁任命或解除，再切換群眾模擬" % source.team_id)
		var snapshot: Dictionary = source.capture_combat_state()
		var exact_handoff := ClearHandoff.decorate_existing(source, snapshot)
		if team_ids.has(int(snapshot.team_id)):
			return D5Runtime.fail("INVALID", "原隊伍 ID 重複")
		team_ids[int(snapshot.team_id)] = true
		var units: Array[Dictionary] = []
		var centre := Vector2.ZERO
		for index in range(source.combat_units.size()):
			var body: Dictionary = source.combat_units[index]
			var saved: Dictionary = snapshot.units[index]
			var identity := int(saved.person_id)
			if seen.has(identity):
				return D5Runtime.fail("INVALID", "原人物 ID 重複")
			# G5 S2: a detached row (member=false) or an off-map row (site_exited) is imported as a native soldier and
			# made absent by d5_absent_existing. Departed and captive-pending rows stay refused; a surrender-pending row imports as the native flag (G5 S4).
			var absent_kind := d5_absent_kind(saved)
			if bool(saved.get("departed", false)) \
				or (absent_kind != 0 and bool(saved.get("captive", false))) or (not bool(saved.get("member", true)) and bool(saved.get("site_exited", false))):
				return D5Runtime.fail("UNSUPPORTED", "原名冊含離隊、離圖或待俘人物；尚不能無損交接群眾")
			if not saved.get("work_task", {}).is_empty():
				return D5Runtime.fail("BUSY", "原人物工作尚未收束，未切換模擬")
			if not body.get("item_state") is Dictionary or not body.get("cargo") is Dictionary:
				return D5Runtime.fail("INVALID", "原人物沒有完整實物持有人或行囊")
			var appearance := D5Runtime.equipment_appearance(scene_lab.terrain, body.item_state, body.appearance)
			if appearance.is_empty():
				return D5Runtime.fail("INVALID", "原人物實裝無法投影；未重新配發")
			var position: Vector2 = source.combat_ground(index) / 64.0
			if exact_handoff and saved.get("crowd_position") is Array:
				position = Vector2(float(saved.crowd_position[0]), float(saved.crowd_position[1]))
			var facing: Vector2 = Vector2(source.facing[index])
			var abilities: Dictionary = source.command_abilities.get(index, {})
			units.append({"index": index, "person_id": identity, "body": body,
				"saved": saved, "appearance": appearance, "position": position,
				"face": facing.angle(), "abilities": abilities, "actor": null})
			centre += position
			seen[identity] = true
		if is_instance_valid(source.player_member):
			var actor: TerrainTestCharacter = source.player_member
			if seen.has(actor.person_id):
				return D5Runtime.fail("INVALID", "原 actor 隊員重複入隊")
			if not actor.projectiles.is_empty() or actor._rescue_left > 0.0:
				return D5Runtime.fail("BUSY", "原 actor 的彈體或救助尚未收束")
			var saved: Dictionary = actor.capture_state()
			saved.exchange_stagger = actor.exchange_stagger
			saved.exchange_cooldown = actor.exchange_cooldown
			saved.ranged_cooldown = actor.ranged_cooldown
			saved.exchange_skill_cooldown = actor.exchange_skill_cooldown
			var appearance := D5Runtime.equipment_appearance(scene_lab.terrain, actor.item_state, saved.appearance)
			if appearance.is_empty():
				return D5Runtime.fail("INVALID", "原 actor 實装不完整")
			var position: Vector2 = actor.position / 64.0
			var cargo: Dictionary = scene_lab.terrain.site.manual.cargo if actor == scene_lab.character else scene_lab.terrain.site.worker.cargo
			units.append({"index": TerrainArmy.PLAYER_MEMBER, "person_id": actor.person_id,
				"body": actor, "saved": saved, "appearance": appearance, "position": position,
				"face": Vector2(actor.facing).angle(), "abilities": actor.command_abilities,
				"actor": actor, "cargo": cargo})
			centre += position
			seen[actor.person_id] = true
		if units.is_empty():
			continue
		centre /= units.size()
		var forward := Vector2.DOWN
		var commander := int(snapshot.current_commander)
		if commander == TerrainArmy.PLAYER_MEMBER and is_instance_valid(source.player_member):
			forward = Vector2(source.player_member.facing)
		elif commander >= 0 and commander < source.facing.size():
			forward = Vector2(source.facing[commander])
		var goal_face: Array = snapshot.get("combat_deployment_plan", {}).get("final_facing", [])
		var goal_facing := Vector2(float(goal_face[0]), float(goal_face[1])).angle() if goal_face.size() == 2 else forward.angle()
		var supply: Dictionary = scene_lab.terrain.site.get("team_supply", {}).get(str(source.team_id), {}).get("sustain", {})
		plans.append({"source": source, "snapshot": snapshot, "units": units,
			"centre": centre, "facing": forward.angle(), "goal_facing": goal_facing,
			"width": maxi(1, source.formation_width()), "supply": supply.duplicate(true),
			"was_visible": source.visible, "was_processing": source.is_processing(),
			"formation": -1})
	var person: Dictionary = scene_lab.site_controller.person_actions._person(controlled)
	# A cold owner of a Site its controlled person is not on (an NPC arrival destination) converts with no player
	# soldier, as every off-screen crowd Site runs (found 2026-11-08: an NPC sea arrival stayed grid and its cold step
	# reached the retired grid simulation). A live Site keeps the strict controlled-person rule.
	var no_player: bool = person.is_empty() and bool(scene_lab.restore_only)
	if person.is_empty() and not no_player:
		return D5Runtime.fail("INVALID", "受控原人物／實物不存在")
	if not no_player and int(person.unit) >= 0 and not seen.has(controlled):
		return D5Runtime.fail("INVALID", "受控名冊人物沒有可交接的原隊伍")
	return D5Runtime.ok("", {"plans": plans, "person_ids": seen, "controlled": person, "no_player": no_player})

static func d5_append_existing(crowd_site: Variant, plans: Array) -> Dictionary:
	var siege_guard: Dictionary = crowd_site.siege_admission_guard()
	if not siege_guard.ok: return siege_guard
	for plan: Dictionary in plans:
		var snapshot: Dictionary = plan.snapshot
		var initial_family: int = crowd_site._packed_equip(plan.units[0].appearance) & 255
		var initial_troop := 1 if initial_family == 7 else 2 if initial_family == 8 else 0
		var native_faction: int = crowd_site._native_faction(int(snapshot.faction_id))
		if native_faction < 0: return D5Runtime.fail("NO_SPACE", "群眾原生陣營槽已滿")
		var formation: int = crowd_site.crowd.add_formation(native_faction, plan.centre.x, plan.centre.y,
			float(plan.facing), int(plan.width), 1.0, initial_troop, float(snapshot.training))
		if formation < 0:
			return D5Runtime.fail("INVALID", "原隊伍無法加入群眾")
		if not bool(crowd_site.crowd.set_garrisoned(formation, int(not str(snapshot.get("garrison_feature_id", "")).is_empty()))):
			return D5Runtime.fail("INVALID_GARRISON", "原駐營歸屬匯入失敗")
		plan.formation = formation
		var ids := PackedInt64Array()
		var equip := PackedInt32Array()
		var roles := PackedByteArray()
		var ammo := PackedInt32Array()
		var starts := PackedFloat32Array()
		var troop := -1
		for entry: Dictionary in plan.units:
			var identity := int(entry.person_id)
			var packed: int = crowd_site._packed_equip(entry.appearance)
			var family := packed & 255
			var person_troop := 1 if family == 7 else 2 if family == 8 else 0
			if troop < 0:
				troop = person_troop
			ids.append(identity)
			equip.append(packed)
			roles.append(d5_role(snapshot, int(entry.index)))
			var cargo: Dictionary = entry.cargo if entry.actor != null else entry.body.cargo
			ammo.append(int(cargo.get("arrow" if person_troop == 1 else "bolt", 0)) if person_troop != 0 else 0)
			starts.append_array(PackedFloat32Array([entry.position.x, entry.position.y]))
			if entry.actor != null:
				crowd_site._actors[identity] = entry.actor
			else:
				crowd_site._records[identity] = entry.body
		var first: int = crowd_site.crowd.add_soldiers(formation, ids, equip, roles, ammo)
		if first < 0:
			return D5Runtime.fail("INVALID", "原隊伍人物匯入失敗")
		var post_holders := d5_post_holders(snapshot)
		for offset in range(plan.units.size()):
			var entry: Dictionary = plan.units[offset]
			var military: String = entry.actor.military_role if entry.actor != null else str(entry.saved.get("military_role", "soldier"))
			if not bool(crowd_site.crowd.set_military_role(first + offset, military_role_code(military))) \
				or not bool(crowd_site.crowd.set_post_holder(first + offset, int(post_holders.has(int(entry.person_id))))):
				return D5Runtime.fail("INVALID_ROLE", "原人物軍官資格匯入失敗")
		crowd_site.crowd.set_start_positions(first, starts)
		# The team's carried morale state (a team back from the Region, or a crowd team cleared to GD) continues natively;
		# written after its soldiers join, which re-derive the formation's fresh values.
		if not apply_team_morale(crowd_site.crowd, formation, snapshot.get("team_morale", {})):
			return D5Runtime.fail("INVALID", "原隊伍士氣狀態匯入失敗")
		# Each person's troop is derived from actual gear by the native equip setter;
		# the formation's class remains the original first member's weapon class.
		var roster: Dictionary = snapshot.duplicate()
		roster["crowd"] = true
		roster["roster_version"] = 1
		roster["crowd_formation"] = formation
		plan.roster = roster
		crowd_site.rosters.append(roster)
		crowd_site.teams.append({"slot": crowd_site.teams.size(), "team_id": int(snapshot.team_id),
			"formation": formation, "faction": int(snapshot.faction_id), "native_faction": native_faction,
			"troop": maxi(0, troop), "person_ids": Array(ids), "solo": false})
	return D5Runtime.ok()

static func d5_role(snapshot: Dictionary, index: int) -> int:
	if index == int(snapshot.get("formal_commander", -1)):
		return 1
	return 2 if index in snapshot.get("officer_service", []) or index in snapshot.get("officers", []) else 0

static func d5_person_id(snapshot: Dictionary, index: int) -> int:
	if index == TerrainArmy.PLAYER_MEMBER:
		return int(snapshot.get("player_member", {}).get("id", -1))
	var rows: Array = snapshot.get("units", [])
	return int(rows[index].person_id) if index >= 0 and index < rows.size() else -1

static func d5_row_hot(entry: Dictionary, snapshot: Dictionary, captivity: Dictionary) -> Dictionary:
	var row: Dictionary = entry.saved
	if entry.actor != null:
		var hot := _actor_native_fields(entry.actor, captivity, entry.appearance, entry.cargo)
		# Joined actors retain their original team role; solo actors use their metadata.
		hot.role = d5_role(snapshot, int(entry.index))
		return hot
	var abilities: Dictionary = entry.abilities
	var age := float(row.get("age", 0.0))
	var frozen := snapshot.has("crowd_state")
	var getup := float(row.get("getup", 0.0)) if frozen else (maxf(0.0, float(D5Timings.POSE_SECONDS[&"get_up"]) - age) if str(row.get("pose", "")) == "get_up" else 0.0)
	var relation: Dictionary = captivity.get(str(int(entry.person_id)), {})
	var packed_cargo: Dictionary = entry.cargo if entry.actor != null else entry.body.cargo
	var weapon := str(entry.appearance.parts.get("weapon", "none"))
	var arrow := weapon.begins_with("bow_") or weapon.contains("_bow_")
	var bolt := weapon.begins_with("crossbow_") or weapon.contains("_crossbow_")
	return {"hp": float(row.hp), "hit_revision": int(row.get("hit_revision", 0)), "stun": float(row.get("stun", 0.0)), "grace": float(row.get("grace", 0.0)),
		"ko": float(row.get("ko", 0.0)), "getup": getup, "stagger": float(row.get("exchange_stagger", 0.0)),
		"captive": bool(row.get("captive", false)), "captor_person": int(relation.get("guard_id", -1)),
		"prison_id": int(relation.get("prison_id", "0")),
		"bandaged": bool(row.get("bandaged", false)), "escape_t": float(row.get("escape_t", 0.0)),
		"ammo": int(packed_cargo.get("arrow" if arrow else "bolt", 0)) if arrow or bolt else 0,
		"tactics": int(abilities.get("tactics", -1)), "leadership": int(abilities.get("leadership", 0)), "coach": int(abilities.get("coach", 0)),
		"role": int(row.get("role", d5_role(snapshot, int(entry.index)))), "px": entry.position.x, "py": entry.position.y, "face": float(row.get("face", entry.face)) if frozen else entry.face,
		"exch_cd": float(row.get("exchange_cooldown", row.get("exch_cd", 0.0))),
		"ranged_cd": float(row.get("ranged_cooldown", row.get("ranged_cd", 0.0))),
		"skill_cd": float(row.get("exchange_skill_cooldown", row.get("skill_cd", 0.0))),
		"knock_t": float(row.get("knock_t", 0.0)), "act_t": float(row.get("act_t", 0.0))}

static func d5_import_existing_hot(crowd_site: Variant, plans: Array) -> Dictionary:
	# Must follow finalize(), _bind_people() and all _import_actor calls.
	# Actor members do not make their entire original formation host-centred.
	var orders := {TerrainArmy.CombatOrder.HOLD: 0, TerrainArmy.CombatOrder.ATTACK: 2,
		TerrainArmy.CombatOrder.MOVE: 1, TerrainArmy.CombatOrder.RETREAT: 4,
		TerrainArmy.CombatOrder.PURSUE: 3, TerrainArmy.CombatOrder.RETURN: 5,
		TerrainArmy.CombatOrder.CHARGE: 6, TerrainArmy.CombatOrder.RALLY: 7}
	var desired := {"people": {}, "formations": {}}
	for plan: Dictionary in plans:
		var snapshot: Dictionary = plan.snapshot
		var count := 0
		for entry: Dictionary in plan.units:
			var index := int(crowd_site._index_by_id[int(entry.person_id)])
			if not crowd_site.crowd.set_soldier_equip(index, crowd_site._packed_equip(entry.appearance)):
				return D5Runtime.fail("INVALID", "原實裝兵種匯入失敗")
			var hot := d5_row_hot(entry, snapshot, crowd_site.lab.terrain.site.get("captivity", {}))
			# D11: preserve the original Site guard; a non-simulated guard is -1 here.
			if not crowd_site._index_by_id.has(int(hot.captor_person)):
				hot.captor_person = -1
			desired.people[int(entry.person_id)] = hot.duplicate()
			if not crowd_site.set_soldier_fields(index, hot):
				return D5Runtime.fail("INVALID", "原人物熱狀態匯入失敗")
			count += int(float(hot.hp) > 0.0)
		var officers: Array[int] = []
		for old_index: int in snapshot.get("officers", []):
			var identity := d5_person_id(snapshot, old_index)
			if identity > 0:
				officers.append(identity)
		var fatigue: Dictionary = snapshot.get("team_fatigue", {})
		var supply: Dictionary = plan.supply
		var goal: Array = snapshot.get("goal", [-1, -1])
		var valid_goal := goal.size() == 2 and int(goal[0]) >= 0 and int(goal[1]) >= 0
		var idle_goal: Vector2 = plan.centre
		if not valid_goal and not crowd_site.lab.terrain.is_walkable(Vector2i(idle_goal.floor())):
			var actor_state: Dictionary = {}
			for entry: Dictionary in plan.units:
				if entry.actor != null: actor_state = entry.saved
			var anchor := TerrainArmy._handoff_route_anchor(snapshot, crowd_site.lab.terrain, actor_state)
			if not crowd_site.lab.terrain.is_walkable(anchor): return D5Runtime.fail("UNSUPPORTED", "原隊伍沒有合法的待命錨點")
			idle_goal = Vector2(anchor) + Vector2.ONE * 0.5
		var origin: Array = snapshot.get("origin", [plan.centre.x, plan.centre.y])
		var reference: Array = snapshot.get("reference", [plan.centre.x, plan.centre.y])
		var state := {"garrisoned": not str(snapshot.get("garrison_feature_id", "")).is_empty(), "morale": float(supply.get("morale", 100.0)),
			"rally_rest": float(supply.get("regroup_seconds", 0.0)), "routed": bool(supply.get("routed", false)),
			"fatigue": float(fatigue.get("fatigue", 0.0)), "fatigue_rest": float(fatigue.get("fatigue_rest", 0.0)), "fatigue_count": count,
			"training": float(snapshot.get("training", 0.0)), "needs_attack_order": bool(snapshot.get("needs_attack_order", false)),
			"formal_person": d5_person_id(snapshot, int(snapshot.get("formal_commander", -1))),
			"acting_person": d5_person_id(snapshot, int(snapshot.get("acting_commander", -1))),
			"current_person": d5_person_id(snapshot, int(snapshot.get("current_commander", -1))), "officer_persons": officers,
			"commander_present": false if not str(snapshot.get("garrison_feature_id", "")).is_empty() else bool(supply.get("commander_present", int(snapshot.get("current_commander", -1)) >= 0)),
			"order": int(orders.get(int(snapshot.get("combat_order", 0)), 0)),
			"target_person": int(snapshot.get("pursuit_target", -1)),
			"goal_x": float(goal[0]) + 0.5 if valid_goal else idle_goal.x,
			"goal_y": float(goal[1]) + 0.5 if valid_goal else idle_goal.y, "goal_facing": plan.goal_facing,
			"cx": plan.centre.x, "cy": plan.centre.y, "facing": plan.facing,
			"pursuit_left": float(snapshot.get("pursuit_left", 0.0)), "origin_x": float(origin[0]), "origin_y": float(origin[1]),
			"ref_x": float(reference[0]), "ref_y": float(reference[1]), "ref_valid": bool(snapshot.get("command_reference_valid", false)),
			"order_delay": float(snapshot.get("_order_delay", 0.0)), "attacking": bool(snapshot.get("combat_attacking", false)),
			"resupplying": false, "ai_enabled": bool(snapshot.get("tactical_ai", {}).get("enabled", false)), "no_orders": false, "host_center": false}
		state = _formation_handoff_fields(snapshot, state)
		desired.formations[int(plan.formation)] = state.duplicate(true)
		if not crowd_site.set_formation_fields(int(plan.formation), state):
			return D5Runtime.fail("INVALID", "原隊伍軍令／指揮／供養匯入失敗")
		# ORDSERIAL: the native formation continues the original team's issued-order counters, so a stale Region
		# command signed against the original team is still refused as superseded after the crowd takes the team over.
		if crowd_site.crowd.has_method("set_order_serials"):
			var source: Variant = plan.get("source")
			var order_serial := clampi(int(source.get_order_serial()) if source is TerrainArmy else int(snapshot.get("combat_order_serial", 1)), 1, 2147483647)
			var ranged_serial := clampi(int(source.ranged_order_serial) if source is TerrainArmy else 0, 0, 2147483647)
			if not bool(crowd_site.crowd.set_order_serials(int(plan.formation), order_serial, ranged_serial)):
				return D5Runtime.fail("INVALID", "原隊伍軍令序號匯入失敗")
	return D5Runtime.ok("", desired)

static func d5_commit_existing(crowd_site: Variant, plans: Array) -> void:
	# Invoke only after every native import and kit admission succeeded.
	# A snapshot is the transfer envelope; cold authority stays in each original row.
	for plan: Dictionary in plans:
		var source: TerrainArmy = plan.source
		var roster: Dictionary = plan.roster
		var rows: Array = []
		for entry: Dictionary in plan.units:
			if entry.actor != null:
				continue
			var row: Dictionary = entry.body
			for key: String in entry.saved:
				if key not in ["item_state", "cargo", "appearance", "command_abilities"]:
					row[key] = entry.saved[key]
			row.erase("_fatigue_pool")
			rows.append(row)
		roster["units"] = rows
		source._release_combat_hot_store(false)
		source.combat_enabled = false
		source.set_process(false)
		source.hide()
	# Replace old snapshots by team ID, never append a second same-ID roster.
	var imported := {}
	for plan: Dictionary in plans:
		imported[int(plan.snapshot.team_id)] = true
	var retained: Array = []
	for old: Dictionary in crowd_site.lab.terrain.site.get("armies", []):
		if not imported.has(int(old.get("team_id", -1))):
			retained.append(old)
	crowd_site.lab.terrain.site["armies"] = retained


static func build_siege_navigation(data: TerrainData, ground_cells: PackedInt64Array) -> Dictionary:
	var blocked := {}
	var exits := PackedInt64Array()
	if data == null or ground_cells.size() % 3 != 0: return SiteRuntime.fail("INVALID", "原人物格位投影不完整")
	for vehicle: Dictionary in data.site.get("vehicles", {}).values():
		# A driven wagon about to anchor its convoy (operator named, convoy not yet created) is not a static body either:
		# its own anchor must be open ground for add_convoy (2026-11-11, N08 remount at a crowd destination).
		if SiteVehicleTransport.is_convoy(vehicle) and (int(vehicle.get("convoy_id", 0)) > 0 or int(vehicle.get("operator_id", 0)) > 0): continue # a convoy anchor steps inside its own cell; its body blocks through the native convoy body owner instead
		var physical: Array[Vector2i] = SiteVehicleTransport.footprint(data, vehicle)
		var geometry: Dictionary = SiteRuntime.siege_tower_geometry(data, vehicle) if str(vehicle.get("kind", "")) == "siege_tower" else {}
		if not geometry.is_empty(): physical.assign(geometry.physical)
		for cell: Vector2i in physical:
			if not data.contains(cell): return SiteRuntime.fail("INVALID", "原車體占地超出 Site")
			if geometry.is_empty() or not bool(geometry.active) or not geometry.heights.has(data.index(cell)): blocked[data.index(cell)] = true
		for value: int in vehicle.get("move", {}).get("sweep", []): blocked[value] = true
		if str(vehicle.get("action", {}).get("stage", "")) == "rotate":
			for value: int in vehicle.action.get("sweep", []): blocked[value] = true
		if geometry.is_empty() or bool(geometry.active) or vehicle.get("deployed_pose", {}).is_empty(): continue
		if float(vehicle.hp) > 0.0 and str(vehicle.phase) != "disabled" and bool(geometry.support_valid): continue
		for offset: int in range(0, ground_cells.size(), 3):
			var index := int(ground_cells[offset])
			var identity := int(ground_cells[offset + 1])
			var source := data.cell_from_index(int(ground_cells[offset + 2]))
			if not physical.has(source): continue
			for cell: Vector2i in physical: exits.append_array(PackedInt64Array([index, identity, data.index(cell)]))
	return SiteRuntime.ok("", {"blocked": PackedInt32Array(blocked.keys()), "wreck_exit": exits})

func siege_native_supported() -> bool:
	for method: String in SIEGE_NATIVE_METHODS:
		if not (crowd.has_method(method) if crowd != null else ClassDB.class_has_method(&"ArmyCrowd", method)): return false
	return true

func convoy_native_supported() -> bool:
	for method: String in CONVOY_NATIVE_METHODS:
		if not (crowd.has_method(method) if crowd != null else ClassDB.class_has_method(&"ArmyCrowd", method)): return false
	return true

func ship_native_supported() -> bool:
	for method: String in SHIP_NATIVE_METHODS:
		if not (crowd.has_method(method) if crowd != null else ClassDB.class_has_method(&"ArmyCrowd", method)): return false
	return true

func siege_team_owner(team_id: int) -> Variant:
	for owner_ref: Variant in owners:
		if int(owner_ref.team_id) == team_id and owner_ref.has_army(): return owner_ref
	return null

func siege_original_person(identity: int) -> Dictionary:
	var owner_ref: Variant = person_owner(identity)
	if owner_ref == null: return {}
	var index := int(_index_by_id.get(identity, -1))
	var result: Dictionary = owner_ref.person(index, false)
	if result.is_empty(): return {}
	result["id"] = identity
	# Only the original metadata row is exposed. Native hot fields keep their owner.
	result["row"] = owner_ref.records.get(index, {})
	return result

var _siege_cell_masks: Dictionary = {}

func siege_people_mask(ignored: Array = []) -> PackedByteArray:
	if not siege_native_supported(): return PackedByteArray()
	var sorted: Array = ignored.duplicate()
	sorted.sort()
	var key := str(sorted)
	if not _siege_cell_masks.has(key): _siege_cell_masks[key] = crowd.siege_occupancy_mask(PackedInt64Array(sorted))
	return _siege_cell_masks[key]

func siege_people_block(cell: Vector2i, ignored: Array = []) -> bool:
	if not lab.terrain.contains(cell): return true
	var mask := siege_people_mask(ignored)
	var index: int = lab.terrain.index(cell)
	return mask.size() != lab.terrain.size.x * lab.terrain.size.y or mask[index] != 0

func siege_approach_step(identity: int, goal: Vector2i, maximum_fire_risk: float = -1.0) -> bool:
	if not is_finite(maximum_fire_risk) or maximum_fire_risk < -1.0 or not active or not siege_native_supported() or not lab.terrain.is_walkable(goal): return false
	var person := siege_original_person(identity)
	if person.is_empty() or not person.owner.combat_can_act(int(person.unit)): return false
	if person.cell == goal:
		# The original controlled step also holds an arrived worker. A body
		# drifting within this cell must finish its native return to its centre.
		var held := bool(crowd.order_siege_step(int(person.unit), lab.terrain.index(goal)))
		if held: _siege_cell_masks.clear()
		return held
	if bool(person.moving): return false
	var occupied := func(cell: Vector2i) -> bool:
		return lab.site_controller.vehicles._siege_people_except(cell, {identity: true}) \
			or maximum_fire_risk >= 0.0 and SiteRuntime.fire_hazard_at(lab.terrain, cell) > maximum_fire_risk
	var edge_blocked := func(from: Vector2i, to: Vector2i) -> bool:
		return lab.site_controller.vehicles.blocks_person_step(identity, person.cell, from, to, goal)
	# Original path_between excludes the source; path[0] is the first real edge.
	# The same synchronous occupied goal cannot be enqueued by the original path search.
	if bool(occupied.call(goal)): return false
	var path: Array[Vector2i] = lab.terrain.path_between(person.cell, goal, occupied, edge_blocked)
	if path.is_empty(): return false
	var accepted := bool(crowd.order_siege_step(int(person.unit), lab.terrain.index(path[0])))
	if accepted: _siege_cell_masks.clear()
	return accepted

func siege_begin_group(plan: Dictionary) -> int:
	if not active or not siege_native_supported(): return 0
	var vehicle: Dictionary = lab.terrain.site.vehicles.get(str(plan.get("vehicle_id", "")), {})
	if vehicle.is_empty(): return 0
	var members := PackedInt64Array()
	var person_cells := {}
	for movement: Dictionary in plan.get("participants", []):
		var identity := int(movement.person_id)
		var index := int(_index_by_id.get(identity, -1))
		if index < 0: return 0
		members.append_array(PackedInt64Array([index, identity, int(movement.from), int(movement.to)]))
		person_cells[int(movement.from)] = true
		person_cells[int(movement.to)] = true
	var source := PackedInt32Array()
	var target := PackedInt32Array()
	for cell: Vector2i in SiteRuntime.siege_cells(lab.terrain, vehicle): source.append(lab.terrain.index(cell))
	var next: Dictionary = vehicle.duplicate(true)
	next["cell"] = int(plan.cell)
	next["facing"] = plan.facing.duplicate()
	for cell: Vector2i in SiteRuntime.siege_cells(lab.terrain, next): target.append(lab.terrain.index(cell))
	var sweep := PackedInt32Array()
	for value: int in plan.sweep:
		if not person_cells.has(value) or source.has(value) or target.has(value): sweep.append(value)
	var token := int(crowd.begin_siege_compound(members, source, target, sweep, float(plan.duration)))
	if token > 0: _siege_cell_masks.clear()
	return token

func siege_group_state(token: int) -> Dictionary:
	if not siege_native_supported() or token <= 0: return {}
	var values: PackedFloat64Array = crowd.siege_compound_state(token)
	if values.size() != 5: return {}
	return {"elapsed": values[0], "duration": values[1], "cancelled": bool(values[2]), "complete": bool(values[3]), "aborted": bool(values[4])}

func siege_cancel_group(token: int) -> bool:
	return siege_native_supported() and bool(crowd.cancel_siege_compound(token))

func siege_settle_group(token: int) -> bool:
	if not siege_native_supported() or not bool(crowd.settle_siege_compound(token)): return false
	_occupancy_cache.clear()
	_siege_cell_masks.clear()
	return true

# Pure input projection shared by live handoff and isolated candidate World load.
# ground_cells contains original native [index, person_id, current_cell] triples.
# This function owns no saved state and never rewrites native queues or clocks.

func sync_siege_inputs() -> Dictionary:
	if not siege_native_supported():
		return SiteRuntime.fail("CROWD_BUILD_MISMATCH", "群眾模組缺少攻城原人物／複合步介面") if SiteStore.has_siege_vehicles(lab.terrain.site) else SiteRuntime.ok()
	var assigned := {}
	var data: TerrainData = lab.terrain
	for vehicle: Dictionary in data.site.get("vehicles", {}).values():
		for identity: int in vehicle.get("crew_slots", {}).values():
			if assigned.has(identity) or not contains_person(identity) or int(person_owner(identity).team_id) != int(vehicle.team_id): return SiteRuntime.fail("INVALID", "原攻城操作班引用重複或不屬原隊")
			assigned[identity] = true
	var inputs := build_siege_navigation(data, crowd.siege_ground_cells())
	if not inputs.ok: return inputs
	var crew := PackedInt32Array()
	for identity: int in assigned: crew.append(int(_index_by_id[identity]))
	if not crowd.set_siege_crew_members(crew): return SiteRuntime.fail("BUSY", "原攻城操作班引用／承諾步不允許此交接")
	if not crowd.set_siege_navigation(inputs.blocked, inputs.wreck_exit): return SiteRuntime.fail("INVALID", "原攻城車體／塔面用途投影不合法")
	return SiteRuntime.ok()

const CONVOY_NATIVE_METHODS := ["add_convoy", "convoy_set_crew", "convoy_order_goal", "convoy_set_body", "convoy_state", "convoy_crew", "convoy_body", "convoy_remove", "convoy_attach_formation", "convoy_formation", "convoy_goal"]
const SHIP_NATIVE_METHODS := ["site_person_board", "site_person_land", "site_person_set_deck", "site_person_retarget_aboard", "site_person_aboard"]
const SIEGE_NATIVE_METHODS := ["set_siege_crew","set_siege_crew_members", "siege_ground_cells", "begin_siege_compound", "siege_compound_state", "siege_person_state", "cancel_siege_compound", "settle_siege_compound", "siege_busy", "set_siege_navigation", "siege_occupancy_mask", "order_siege_step", "cancel_siege_step", "charge_siege_round", "charge_siege_work", "contact_pose_state", "apply_siege_contact"]

func settle_external_contacts() -> void:
	# Same native slice, after the original siege/person contact batch and before save/death settlement.
	if not active or crowd == null: return
	var mark: float = crowd.combat_mark()
	if mark > 0.0 and lab.terrain != null: lab._region_mark_native_work_combat(mark)
	_occupancy_cache.clear()
	if not work_fatigue_point_active():
		if not _consume_events(): return
		settle_events()

# Borrowed views for ONE original shared interval. Never saved or bound to rows.
var _work_fatigue_snapshots: Dictionary = {}
var _work_fatigue_tick := -1
var _work_fatigue_packet := PackedFloat64Array()
var _work_fatigue_action_seconds := 0.0
var _work_fatigue_game_seconds := 0.0
var _work_fatigue_ready := false

func clear_work_fatigue_interval() -> void:
	if work_fatigue_point_active(): return
	_work_fatigue_point_armed = false
	_work_fatigue_point_plan = {}
	_work_fatigue_snapshots.clear()
	_work_fatigue_tick = -1
	_work_fatigue_packet.clear()
	_work_fatigue_action_seconds = 0.0
	_work_fatigue_game_seconds = 0.0
	_work_fatigue_ready = false

func begin_work_fatigue_interval() -> Dictionary:
	if work_fatigue_point_active(): return SiteRuntime.fail("CLOCK_NOT_READY")
	if not active or crowd == null: return SiteRuntime.fail("NO_NATIVE_OWNER")
	if _work_fatigue_tick >= 0: return SiteRuntime.fail("SHARED_WORK_PENDING")
	if not crowd.has_method("validate_step_clock_work_plan"): return SiteRuntime.fail("CLOCK_NOT_READY")
	for owner_ref: CrowdPersonOwner in owners:
		var snapshot := owner_ref.work_fatigue_snapshot()
		if not snapshot.ok:
			clear_work_fatigue_interval()
			return snapshot
		if _work_fatigue_tick < 0: _work_fatigue_tick = int(snapshot.tick)
		if int(snapshot.tick) != _work_fatigue_tick or _work_fatigue_snapshots.has(int(snapshot.formation)):
			clear_work_fatigue_interval()
			return SiteRuntime.fail("STALE_NATIVE_WORK_PLAN")
		_work_fatigue_snapshots[int(snapshot.formation)] = snapshot
	if _work_fatigue_tick < 0: return SiteRuntime.fail("NO_NATIVE_OWNER")
	return SiteRuntime.ok()

func work_fatigue_work_start_ready(identity: int) -> bool:
	# Native current RUN belongs to the previous actual World movement phase.
	# New original host input already applies in THIS action interval and must
	# stop work even while the last hot vx/running and Actor presenter are idle.
	if not active or crowd == null or not contains_person(identity): return false
	var unit: int = int(_index_by_id[identity])
	if unit == player_index and (wish != Vector2.ZERO or engage): return false
	return true # The original provider still checks its actual physical context.

func work_fatigue_participant(identity: int, rest_limited: bool = true, rate: float = PersonFatigue.WORK_RATE) -> Dictionary:
	var owner_ref: Variant = person_owner(identity)
	if not owner_ref is CrowdPersonOwner or not is_finite(rate) or rate <= 0.0: return {}
	if rate == PersonFatigue.WORK_RATE and not work_fatigue_work_start_ready(identity): return {}
	var snapshot: Dictionary = _work_fatigue_snapshots.get(int(owner_ref.formation_index), {})
	if snapshot.is_empty() or int(snapshot.pool.count) <= 0: return {}
	var source: Dictionary = owner_ref.work_fatigue_projection(snapshot, identity)
	if source.is_empty(): return {}
	return {"person_id": identity, "body": source.body, "effort_rate": PersonFatigue.effort_rate(source.body, rate),
		"rest_limited": rest_limited, "original_body": source.original_body, "native_owner": owner_ref,
		"native_snapshot": snapshot, "unit": int(source.unit), "native_effort_kind": "run" if rate == PersonFatigue.RUN_RATE else "work"}

func work_fatigue_snapshot_for_owner(owner_ref: CrowdPersonOwner) -> Dictionary:
	var snapshot: Dictionary = _work_fatigue_snapshots.get(int(owner_ref.formation_index), {})
	return snapshot if snapshot.get("owner") == owner_ref else {}

func is_work_fatigue_pool(pool: Dictionary) -> bool:
	for snapshot: Dictionary in _work_fatigue_snapshots.values():
		if is_same(snapshot.pool, pool): return true
	return false

## True when the native World lists this person as a runner in the current shared work interval.
func work_fatigue_runner(identity: int) -> bool:
	for snapshot: Dictionary in _work_fatigue_snapshots.values():
		for source: Dictionary in snapshot.runners:
			if int(source.person_id) == identity: return true
	return false

func work_fatigue_run_requests(seconds: float, held_requests: Array) -> Dictionary:
	var assigned := {}
	for request: Dictionary in held_requests:
		for participant: Dictionary in request.participants: assigned[int(participant.person_id)] = str(request.get("provider", "")) + ":" + str(request.get("key", ""))
	var requests: Array[Dictionary] = []
	for snapshot: Dictionary in _work_fatigue_snapshots.values():
		for source: Dictionary in snapshot.runners:
			var identity := int(source.person_id)
			if assigned.has(identity):
				var refused := SiteRuntime.fail("DUPLICATE_NATIVE_ACTIVITY", "原 RUN 人物不能同段再列工作／授課")
				refused.merge({"person_id": identity, "held_request": assigned[identity]})
				return refused
			var participant := work_fatigue_participant(identity, false, PersonFatigue.RUN_RATE)
			if participant.is_empty(): return SiteRuntime.fail("STALE_NATIVE_WORK_PLAN")
			requests.append({"provider": "native_run", "key": str(identity), "participants": [participant], "remaining": seconds,
				"productive_kind": "raw", "progress_multiplier": 1.0, "max_game_seconds": seconds})
	return SiteRuntime.ok("", {"requests": requests})

func prepare_work_fatigue_plan(planned: Dictionary, requests: Array, action_seconds: float, game_seconds: float, combat_left: float) -> Dictionary:
	if work_fatigue_point_active(): return SiteRuntime.fail("CLOCK_NOT_READY")
	_work_fatigue_ready = false
	_work_fatigue_packet.clear()
	if _work_fatigue_tick < 0 or planned.get("ok") != true:
		return SiteRuntime.fail("CLOCK_NOT_READY", "CLOCK_NOT_READY：工作疲勞計畫未就緒（tick=%d plan=%s %s）" % [_work_fatigue_tick, str(planned.get("code", "")), str(planned.get("message", ""))])
	var totals := {}
	for request: Dictionary in requests:
		var allocation: Dictionary = planned.jobs.get(str(request.provider), {}).get(str(request.key), {})
		for participant: Dictionary in request.participants:
			if not participant.has("native_snapshot"): continue
			var snapshot: Dictionary = participant.native_snapshot
			var formation := int(snapshot.formation)
			if not is_same(_work_fatigue_snapshots.get(formation, {}), snapshot): return SiteRuntime.fail("STALE_NATIVE_WORK_PLAN")
			var actual := float(allocation.get("participant_seconds", {}).get(int(participant.person_id), 0.0))
			if not is_finite(actual) or actual < 0.0 or actual > game_seconds + PersonFatigue.WORK_PLAN_EPS: return SiteRuntime.fail("INVALID_NATIVE_EFFORT")
			if not totals.has(formation): totals[formation] = {"work": 0.0, "run": 0.0}
			var kind := str(participant.native_effort_kind)
			totals[formation][kind] = float(totals[formation][kind]) + actual
	var formations: Array = totals.keys()
	formations.sort()
	for formation: int in formations:
		var total: Dictionary = totals[formation]
		if float(total.work) + float(total.run) <= 0.0: continue # Original World owns idle recovery.
		var snapshot: Dictionary = _work_fatigue_snapshots[formation]
		var result: Dictionary = {}
		for group: Dictionary in planned.pools:
			if is_same(group.original_pool, snapshot.pool): result = group; break
		if result.is_empty(): return SiteRuntime.fail("MISSING_NATIVE_POOL")
		var packet: PackedFloat64Array = snapshot.owner.work_fatigue_packet(snapshot, result, float(total.work), float(total.run))
		if packet.size() != 8: return SiteRuntime.fail("STALE_NATIVE_WORK_PLAN")
		_work_fatigue_packet.append_array(packet)
	if not bool(crowd.validate_step_clock_work_plan(action_seconds, game_seconds, combat_left, _work_fatigue_tick, _work_fatigue_packet)):
		return SiteRuntime.fail("STALE_NATIVE_WORK_PLAN", "原 World 全池起點預檢拒絕，未消費工作／材料")
	_work_fatigue_action_seconds = action_seconds
	_work_fatigue_game_seconds = game_seconds
	_work_fatigue_ready = true
	return SiteRuntime.ok()

func work_fatigue_forecast_hp(identity: int) -> float:
	if not contains_person(identity): return 0.0
	var before := float(soldier_state(int(_index_by_id[identity])).hp)
	if not lab._region_deferring_endpoint(): return before
	for event: Dictionary in lab._region_point_contacts:
		if str(event.kind) == "native_environment" and int(event.person_id) == identity:
			before = maxf(0.0, before - float(event.packet.loss))
	return before

func validate_prepared_work_fatigue_plan(action_seconds: float, game_seconds: float, combat_left: float) -> Dictionary:
	if work_fatigue_point_active():
		return SiteRuntime.ok("原同點已接受起點／prefix") if work_fatigue_point_prefix_ready(action_seconds, game_seconds) else SiteRuntime.fail("CLOCK_NOT_READY")
	if not _work_fatigue_ready or _work_fatigue_tick < 0 or absf(action_seconds - _work_fatigue_action_seconds) > PersonFatigue.WORK_PLAN_EPS or absf(game_seconds - _work_fatigue_game_seconds) > PersonFatigue.WORK_PLAN_EPS:
		return SiteRuntime.fail("CLOCK_NOT_READY")
	if not bool(crowd.validate_step_clock_work_plan(action_seconds, game_seconds, combat_left, _work_fatigue_tick, _work_fatigue_packet)):
		return SiteRuntime.fail("STALE_NATIVE_WORK_PLAN", "原 World 全池消費前預檢拒絕")
	return SiteRuntime.ok()

func prepare_work_fatigue_recovery_inputs() -> Dictionary:
	# Reuse the original one-step setters. They change no clock/body/work and
	# the original step rechecks them before consuming; never predict recovery.
	for roster: Dictionary in rosters:
		var multiplier: float = Site.Garrison.recovery_multiplier(lab, str(roster.get("garrison_feature_id", "")), int(roster.faction_id), roster.units)
		if not bool(crowd.set_recovery_input(int(roster.crowd_formation), multiplier)): return SiteRuntime.fail("INVALID_GARRISON")
	for attendance: Dictionary in Site.Housing.attendance_input(lab):
		if not bool(crowd.set_housing_attendance_input(int(attendance.unit), int(attendance.cell))): return SiteRuntime.fail("INVALID_HOUSING")
	for roster: Dictionary in rosters:
		if not bool(crowd.set_housing_recovery_input(int(roster.crowd_formation), Site.Housing.recovery_multiplier(lab, roster.units))): return SiteRuntime.fail("INVALID_HOUSING")
	# The original fatigue housing guard reads the actual host wish. Publish
	# the same original input before its read-only endpoint query, as step does.
	var housing_busy: bool = lab.site_controller.person_actions.job_for(int(lab.controlled_person_id())).get("kind", "") == "housing_return"
	crowd.host_input(player_index, 0.0 if housing_busy else wish.x, 0.0 if housing_busy else wish.y, false if housing_busy else running, false if housing_busy else engage)
	var fire_snapshot: Dictionary = SiteRuntime.fire_hazard_snapshot(lab.terrain) if _host_fire_active and SiteRuntime.fire_active(lab.terrain) else {}
	for owner_ref: CrowdPersonOwner in owners:
		var safe: bool = owner_ref.fire_safe_rest_input(fire_snapshot) if _host_fire_active else false
		if not bool(crowd.set_fire_safe_rest_input(owner_ref.formation_index, safe)): return SiteRuntime.fail("CROWD_BUILD_MISMATCH")
	return SiteRuntime.ok()

func work_fatigue_idle_limit(maximum: float, planned: Dictionary, combat_left: float) -> float:
	var limit := maximum
	for snapshot: Dictionary in _work_fatigue_snapshots.values():
		var worked := false
		for group: Dictionary in planned.get("pools", []):
			if is_same(group.original_pool, snapshot.pool) and float(group.effort_seconds) > 0.0: worked = true; break
		if worked: continue
		var target := 0.0
		var owner_ref: CrowdPersonOwner = snapshot.owner
		for unit: int in owner_ref.combat_units:
			if bool(owner_ref.combat_hot_get(unit, &"work_resting", false)) and float(snapshot.pool.fatigue) > 50.0: target = 50.0; break
		var endpoint := float(crowd.work_fatigue_rest_limit(int(snapshot.formation), target, maximum, combat_left))
		if not is_finite(endpoint) or endpoint <= 0.0: return NAN
		limit = minf(limit, endpoint)
	return limit


func work_fatigue_point_active() -> bool:
	if crowd == null or not crowd.has_method("work_point_state"): return false
	var state: PackedFloat64Array = crowd.work_point_state()
	return state.size() == 5 and state[0] == 1.0

func work_training_start_ready(owner_ref: CrowdPersonOwner, combat_left: float) -> bool:
	return active and crowd != null and crowd.has_method("work_training_start_ready") and owner_ref != null and owners.has(owner_ref) and crowd.work_training_start_ready(int(owner_ref.formation_index), combat_left)

var _work_fatigue_point_armed := false

var _work_fatigue_point_plan: Dictionary = {}
var _audio_mounted_rows := PackedByteArray() # Derived admitted appearance; never saved.

func prepare_native_begin_work_point(planned: Dictionary, requests: Array, action_seconds: float, game_seconds: float,
		combat_left: float, releases: PackedInt64Array, preview: PackedFloat64Array, projection: Dictionary) -> Dictionary:
	# Pure gate over the actual original snapshot plus its exact regenerated
	# BEGIN wire. Projection pools supply numbers only, never native identities.
	if not active or crowd == null or _work_fatigue_tick < 0 or _work_fatigue_ready or _work_fatigue_point_armed \
		or work_fatigue_point_active() or planned.get("ok") != true or preview.size() % 10 != 0:
		return SiteRuntime.fail("CLOCK_NOT_READY")
	for method: String in ["validate_step_clock_work_plan_after_host_ranged", "step_clock_work_point", "validate_work_point_finish",
		"prepare_work_point_finish", "publish_work_point_finish", "work_point_state", "work_fatigue_run_upper", "work_point_runners"]:
		if not crowd.has_method(method): return SiteRuntime.fail("CLOCK_NOT_READY")
	var after_begin: Dictionary = {}
	for offset: int in range(0, preview.size(), 10):
		after_begin[int(preview[offset + 1])] = [float(preview[offset + 6]), float(preview[offset + 7])]
	var totals: Dictionary = {}
	var projected_pools: Dictionary = {}
	for request: Dictionary in requests:
		var allocation: Dictionary = planned.jobs.get(str(request.provider), {}).get(str(request.key), {})
		for participant: Dictionary in request.participants:
			if not participant.has("native_snapshot"): continue
			var snapshot: Dictionary = participant.native_snapshot
			var formation: int = int(snapshot.formation)
			if not is_same(_work_fatigue_snapshots.get(formation, {}), snapshot): return SiteRuntime.fail("STALE_NATIVE_WORK_PLAN")
			var identity: int = int(participant.person_id)
			var actual: float = float(allocation.get("participant_seconds", {}).get(identity, 0.0))
			var kind: String = str(participant.native_effort_kind)
			if kind not in ["work", "run"] or not is_finite(actual) or actual < 0.0 or actual > game_seconds + PersonFatigue.WORK_PLAN_EPS:
				return SiteRuntime.fail("INVALID_NATIVE_EFFORT")
			if not totals.has(formation): totals[formation] = {"work": 0.0, "run": 0.0}
			totals[formation][kind] += actual
			var scalar: Dictionary = projection.get(identity, participant)
			projected_pools[formation] = scalar.body._fatigue_pool
	var packet := PackedFloat64Array()
	var formations: Array = totals.keys()
	formations.sort()
	for formation: int in formations:
		var total: Dictionary = totals[formation]
		if float(total.work) <= 0.0: continue # original NO WORK RUN/recovery stays in World.
		var snapshot: Dictionary = _work_fatigue_snapshots[formation]
		var result: Dictionary = {}
		for pool: Dictionary in planned.pools:
			if is_same(pool.original_pool, projected_pools[formation]): result = pool; break
		if result.is_empty(): return SiteRuntime.fail("MISSING_NATIVE_POOL")
		var source: Array = after_begin.get(formation, [float(snapshot.pool.fatigue), float(snapshot.pool.fatigue_rest)])
		packet.append_array(PackedFloat64Array([formation, source[0], source[1], int(snapshot.pool.count),
			float(total.work), float(total.run), float(result.fatigue), float(result.fatigue_rest)]))
	if not bool(crowd.validate_step_clock_work_plan_after_host_ranged(action_seconds, game_seconds, combat_left,
		_work_fatigue_tick, packet, releases, preview)):
		return SiteRuntime.fail("STALE_NATIVE_BEGIN_WORK_PLAN", "原BEGIN與整段body預檢拒絕；未扣彈／工作物資")
	return SiteRuntime.ok("原World同BEGIN/body全源只讀預檢", {"owner": self, "tick": _work_fatigue_tick,
		"packet": packet, "planned": planned, "requests": requests, "projection": projection,
		"action_seconds": action_seconds, "game_seconds": game_seconds, "combat_left": combat_left})

func publish_native_begin_work_point(prepared: Dictionary) -> void:
	# Called immediately after the already checked synchronous original pulse
	# tail. Every method/source/body guard was checked before the first debit.
	# These are fresh actual World reads, not preview pool writes or a second CAS.
	for snapshot: Dictionary in _work_fatigue_snapshots.values():
		var actual: Dictionary = snapshot.owner.work_fatigue_snapshot()
		snapshot.pool.clear()
		snapshot.pool.merge(actual.pool)
		snapshot.runners = actual.runners
	for pool: Dictionary in prepared.planned.pools:
		for request: Dictionary in prepared.requests:
			for participant: Dictionary in request.participants:
				if not participant.has("native_snapshot"): continue
				var scalar: Dictionary = prepared.projection.get(int(participant.person_id), participant)
				if is_same(pool.original_pool, scalar.body._fatigue_pool):
					pool.original_pool = participant.native_snapshot.pool
					pool.body = participant.body
	_work_fatigue_packet = prepared.packet
	_work_fatigue_action_seconds = float(prepared.action_seconds)
	_work_fatigue_game_seconds = float(prepared.game_seconds)
	_work_fatigue_ready = true
	_work_fatigue_point_armed = true

func prepare_work_fatigue_point_finish(planned: Dictionary, requests: Array, action_seconds: float, game_seconds: float) -> Dictionary:
	# Call ONLY after every real materials, pending-fire and held-consumer final
	# validation; all copying/allocation and possible failure precedes real costs.
	if not work_fatigue_point_active() or not _work_fatigue_point_plan.is_empty() or _work_fatigue_tick < 0 \
		or absf(action_seconds - _work_fatigue_action_seconds) > PersonFatigue.WORK_PLAN_EPS \
		or absf(game_seconds - _work_fatigue_game_seconds) > PersonFatigue.WORK_PLAN_EPS: return SiteRuntime.fail("STALE_NATIVE_WORK_POINT")
	var packed: Dictionary = _work_fatigue_point_packet(planned, requests, game_seconds)
	if not packed.ok: return packed
	if not bool(crowd.validate_work_point_finish(_work_fatigue_tick, packed.packet)): return SiteRuntime.fail("STALE_NATIVE_WORK_POINT")
	if not bool(crowd.prepare_work_point_finish(_work_fatigue_tick, packed.packet)): return SiteRuntime.fail("STALE_NATIVE_WORK_POINT")
	_work_fatigue_packet = packed.packet
	_work_fatigue_point_plan = planned # SAME admitted result; no source/proxy writes.
	return SiteRuntime.ok()

func publish_work_fatigue_point() -> void:
	# Original no-failure point tail: no new packet, CAS, sources, allocation,
	# clock, lifecycle/contact callbacks or charge/recovery calls in this tail.
	crowd.publish_work_point_finish()
	_work_fatigue_point_plan = {}
	_work_fatigue_point_armed = false
	clear_work_fatigue_interval()

func work_fatigue_run_bound_requests(seconds: float, held_requests: Array) -> Dictionary:
	if crowd == null or not crowd.has_method("work_fatigue_run_upper") or work_fatigue_point_active(): return SiteRuntime.fail("CLOCK_NOT_READY")
	return _work_fatigue_point_run_ref_requests(crowd.work_fatigue_run_upper(), seconds, held_requests, true)

func finish_work_fatigue_point_events() -> bool:
	# AFTER all real prefix/cost/fatigue publication. True hot HP/captive state
	# was already available to post-contact P5 classification. ORIGINAL events
	# now carry the final accepted prefix and each death's own preceding pulses.
	if work_fatigue_point_active():
		last_event_error = SiteRuntime.fail("CLOCK_NOT_READY")
		return false
	if not _consume_events(): return false
	settle_events()
	return true

# EXACT insertions to existing methods, do not replace unrelated methods:
#
# 1) In step(), replace the existing shared-plan Native invocation + clear:
#
#     var accepted: bool = bool(crowd.step_clock_work_point(elapsed, game_seconds,
#         combat_left, _work_fatigue_tick, _work_fatigue_packet)) if _work_fatigue_point_armed \
#         else bool(crowd.step_clock_work_plan(elapsed, game_seconds,
#             combat_left, _work_fatigue_tick, _work_fatigue_packet))
#     if not accepted:
#         last_event_error = SiteRuntime.fail("STALE_NATIVE_WORK_PLAN")
#         return false
#     if not _work_fatigue_point_armed: clear_work_fatigue_interval()
#
# Keep the rest of ORIGINAL step() contacts/events/presenters. Never recapture
# the start snapshot after contacts or rebuild its pool from ending count.
#
# 2) At START of validate_prepared_work_fatigue_plan():
#
#     if work_fatigue_point_active():
#         return SiteRuntime.ok("原同點已接受起點／prefix") if work_fatigue_point_prefix_ready(action_seconds, game_seconds) \
#             else SiteRuntime.fail("CLOCK_NOT_READY")
#
# 3) At START of clear_work_fatigue_interval():
#
#     if work_fatigue_point_active(): return # unfinished original World cannot be discarded/saved
#     _work_fatigue_point_armed = false
#     _work_fatigue_point_plan = {}
#
# 4) prepare_work_fatigue_plan()/begin_work_fatigue_interval() must reject an
#    active point BEFORE resetting readiness/packet/snapshot. Final point API
#    above is the only allowed second plan for that already completed World.
#
# 5) Original training uses its true Native apply_training_only(...worked=0)
#    under admitted point; no native charge when allocation missing. Original
#    ranged release/round pulse occurs after publish, before next snapshot.
#
# 6) At original step() event block, replace ONLY the consume/settle pair:
#
#     if not work_fatigue_point_active():
#         if not _consume_events(): return false
#         settle_events()
#
#    In settle_external_contacts(), defer its original consume/settle while
#    work_fatigue_point_active() as well. It must still apply true Native HP
#    contacts at their original point; only event drain/handoff is deferred.
#    Guard _consume_events() itself BEFORE queue reads:
#        if work_fatigue_point_active(): return true
#    This leaves Native event queue untouched; GDExt drain also refuses early.
#    After publish_work_fatigue_point call finish_work_fatigue_point_events().
#    Only then original _person_died/family/captivity/presenter callbacks run.
#    Preserve _advance_dead_person_fatigue's PREVIOUS deaths pass once before
#    new _death_notified handoffs; do not grant newly killed people idle time.

# APPEND to ORIGINAL CrowdSite (P5 point package already merged first).

func prepare_work_training_point(checked: Array) -> Dictionary:
	# BEFORE prepare_work_fatigue_point_finish; both are original World point
	# candidates, no real fatigue/training/material/progress publish here.
	if not work_fatigue_point_active() or crowd == null or not crowd.has_method("prepare_work_point_training_plan"): return SiteRuntime.fail("CLOCK_NOT_READY")
	var packet := PackedFloat64Array()
	var ordered: Array[Dictionary] = []
	for item: Dictionary in checked:
		if item.get("ok") != true or not item.get("packet") is PackedFloat64Array: return SiteRuntime.fail("INVALID_TRAINING")
		if item.packet.is_empty(): continue
		if item.packet.size() != 5: return SiteRuntime.fail("INVALID_TRAINING")
		ordered.append(item)
	ordered.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return int(left.packet[0]) < int(right.packet[0]))
	var previous := -1
	for item: Dictionary in ordered:
		var formation: int = int(item.packet[0])
		if formation <= previous or not _work_fatigue_snapshots.has(formation) or not is_same(item.held.snapshot, _work_fatigue_snapshots[formation]): return SiteRuntime.fail("STALE_NATIVE_WORK_PLAN")
		previous = formation
		packet.append_array(item.packet)
	if not crowd.validate_work_point_training_plan(_work_fatigue_tick, packet) or not crowd.prepare_work_point_training_plan(_work_fatigue_tick, packet): return SiteRuntime.fail("STALE_NATIVE_TRAINING_PLAN")
	return SiteRuntime.ok("原World训练候选已与疲劳共同点绑定")

func work_fatigue_point_run_requests(seconds: float, held_requests: Array) -> Dictionary:
	if not work_fatigue_point_active() or not crowd.has_method("work_point_runners"): return SiteRuntime.fail("CLOCK_NOT_READY")
	return _work_fatigue_point_run_ref_requests(crowd.work_point_runners(), seconds, held_requests, false)

func _work_fatigue_point_packet(planned: Dictionary, requests: Array, game_seconds: float) -> Dictionary:
	if planned.get("ok") != true or not is_finite(game_seconds) or game_seconds <= 0.0: return SiteRuntime.fail("INVALID_WORK")
	var totals := {}
	for request: Dictionary in requests:
		var allocation: Dictionary = planned.jobs.get(str(request.provider), {}).get(str(request.key), {})
		for participant: Dictionary in request.participants:
			if not participant.has("native_snapshot"): continue
			var snapshot: Dictionary = participant.native_snapshot
			var formation: int = int(snapshot.formation)
			if not is_same(_work_fatigue_snapshots.get(formation, {}), snapshot): return SiteRuntime.fail("STALE_NATIVE_WORK_PLAN")
			var actual: float = float(allocation.get("participant_seconds", {}).get(int(participant.person_id), 0.0))
			if not is_finite(actual) or actual < 0.0 or actual > game_seconds + PersonFatigue.WORK_PLAN_EPS: return SiteRuntime.fail("INVALID_NATIVE_EFFORT")
			var kind: String = str(participant.native_effort_kind)
			if kind not in ["work", "run"]: return SiteRuntime.fail("INVALID_NATIVE_EFFORT")
			if not totals.has(formation): totals[formation] = {"work": 0.0, "run": 0.0}
			totals[formation][kind] = float(totals[formation][kind]) + actual
	var packet := PackedFloat64Array()
	var formations: Array = totals.keys()
	formations.sort()
	for formation: int in formations:
		var total: Dictionary = totals[formation]
		if float(total.work) <= 0.0: continue # NO WORK: original World owns RUN/recovery without manual replacement.
		var snapshot: Dictionary = _work_fatigue_snapshots[formation]
		var result: Dictionary = {}
		for group: Dictionary in planned.pools:
			if is_same(group.original_pool, snapshot.pool): result = group; break
		if result.is_empty(): return SiteRuntime.fail("MISSING_NATIVE_POOL")
		var local: PackedFloat64Array = snapshot.owner.work_fatigue_packet(snapshot, result, float(total.work), float(total.run))
		if local.size() != 8: return SiteRuntime.fail("STALE_NATIVE_WORK_PLAN")
		packet.append_array(local)
	return SiteRuntime.ok("原同點真起點全池packet", {"packet": packet})

func work_fatigue_point_prefix_ready(action_seconds: float, game_seconds: float) -> bool:
	if _work_fatigue_point_plan.is_empty() or not work_fatigue_point_active() \
		or absf(action_seconds - _work_fatigue_action_seconds) > PersonFatigue.WORK_PLAN_EPS \
		or absf(game_seconds - _work_fatigue_game_seconds) > PersonFatigue.WORK_PLAN_EPS: return false
	var state: PackedFloat64Array = crowd.work_point_state()
	return state[1] == 1.0 and int(state[2]) == _work_fatigue_tick and int(state[3]) == _work_fatigue_tick + 1 \
		and absf(state[4] - game_seconds) <= PersonFatigue.WORK_PLAN_EPS

func _work_fatigue_point_run_ref_requests(refs: PackedInt64Array, seconds: float, held_requests: Array, upper: bool) -> Dictionary:
	if refs.size() % 3 != 0 or not is_finite(seconds) or seconds <= 0.0: return SiteRuntime.fail("STALE_NATIVE_WORK_PLAN")
	var assigned := {}
	for request: Dictionary in held_requests:
		for participant: Dictionary in request.participants: assigned[int(participant.person_id)] = str(request.get("provider", "")) + ":" + str(request.get("key", ""))
	var seen := {}
	var requests: Array[Dictionary] = []
	for offset: int in range(0, refs.size(), 3):
		var formation: int = int(refs[offset])
		var unit: int = int(refs[offset + 1])
		var identity: int = int(refs[offset + 2])
		if seen.has(identity): return SiteRuntime.fail("DUPLICATE_NATIVE_ACTIVITY", "native run refs repeat person %d" % identity)
		seen[identity] = true
		if assigned.has(identity):
			if upper: continue # Bound excludes existing held activity; never new permission.
			var refused := SiteRuntime.fail("DUPLICATE_NATIVE_ACTIVITY", "同原人不能既RUN又本段工作")
			refused.merge({"person_id": identity, "held_request": assigned[identity], "upper": upper})
			return refused
		var owner_ref: Variant = person_owner(identity)
		if not owner_ref is CrowdPersonOwner or owner_ref.formation_index != formation or owner_ref.index_for_identity(identity) != unit:
			return SiteRuntime.fail("STALE_NATIVE_WORK_PLAN")
		# A runner that dies at this endpoint keeps its true accepted prefix.
		# The snapshot factory checks original refs, not fabricated living HP.
		var participant: Dictionary = work_fatigue_participant(identity, false, PersonFatigue.RUN_RATE)
		if participant.is_empty(): return SiteRuntime.fail("STALE_NATIVE_WORK_PLAN")
		requests.append({"provider": "native_run_bound" if upper else "native_run", "key": str(identity),
			"participants": [participant], "remaining": seconds, "productive_kind": "raw", "progress_multiplier": 1.0, "max_game_seconds": seconds})
	return SiteRuntime.ok("原Native具名RUN refs", {"requests": requests})

func _consume_events_original() -> bool:
	if work_fatigue_point_active(): return true
	# Both getters inspect the same queue synchronously. Validate every event
	# before draining it or writing any original body, counter or captivity task.
	var events: PackedInt64Array = crowd.peek_events()
	var fatigue: PackedFloat64Array = crowd.event_fatigue()
	var valid_packet: bool = events.size() % 4 == 0 and fatigue.size() == (events.size() >> 1)
	var deaths := {}
	if valid_packet:
		for offset in range(0, events.size(), 4):
			var kind := int(events[offset])
			var identity := int(events[offset + 1])
			var at: int = offset >> 1
			var value: float = fatigue[at]
			var rested: float = fatigue[at + 1]
			if (kind < 0 or kind > 10 or not is_finite(value) or value < 0.0 or value > 100.0
					or not is_finite(rested) or rested < 0.0 or rested > 30.0):
				valid_packet = false
				break
			if kind != 0:
				if value != 0.0 or rested != 0.0:
					valid_packet = false
					break
				continue
			var source: Variant = person_owner(identity)
			if (identity <= 0 or deaths.has(identity) or source == null
					or not _index_by_id.has(identity) or (not _actors.has(identity) and not _records.has(identity))
					or int(events[offset + 3]) != int(source.formation_index)):
				valid_packet = false
				break
			var state: Dictionary = soldier_state(int(_index_by_id[identity]))
			if float(state.hp) > 0.0:
				valid_packet = false
				break
			deaths[identity] = true
	if (not valid_packet or crowd.peek_events() != events or crowd.event_fatigue() != fatigue):
		last_event_error = SiteRuntime.fail("INVALID_CROWD", "原生死亡事件與原人物疲勞交接封包不符")
		return false
	# No await, step, callback or native writer occurred between the reads and drain.
	crowd.drain_events()
	for offset in range(0, events.size(), 4):
		var kind := int(events[offset])
		var identity := int(events[offset + 1])
		var other := int(events[offset + 2])
		event_counts[kind] = int(event_counts.get(kind, 0)) + 1
		if kind in [0, 1, 4]: _battle_event(kind, identity, other)
		if kind in [4, 5]:
			pending_captivity.append({"kind": kind, "person": identity, "other": other, "ammo_synced": false})
		elif kind == 0:
			# P1c: the grid stamps battle deaths on the row (TA unit "combat_death_minute"). Crowd rows get the same stamp.
			# Environmental deaths (hunger, fire) are not separated here; the grid excludes them by its packet flag.
			if _records.has(identity) and _records[identity] is Dictionary:
				_records[identity]["combat_death_minute"] = int(lab.terrain.site.get("minute", 0))
			_freeze_dead_person_fatigue(identity, fatigue[offset >> 1], fatigue[(offset >> 1) + 1])
			if not _death_notified.has(identity):
				_death_notified[identity] = true
				lab.site_controller._person_died(identity)
		elif kind == 10 and identity > 0 and not has_pending_capture(identity): _sync_ammo(identity)
	if not events.is_empty(): events_received.emit(events)
	return true

func _audio_native_prepare() -> void:
	if not active or crowd == null or not crowd.has_method("configure_audio_projection"): return
	var view: SiteAudioView = lab.audio_view
	if view == null: return
	var stats := view.stats_snapshot()
	var enabled: bool = bool(stats.active) and bool(stats.batch_open) and not bool(stats.muted) and float(stats.volume) > 0.0 and not lab.restore_only
	var bases := PackedInt32Array()
	for kind: StringName in [&"step_grass_walk", &"contact", &"shield", &"hurt", &"bow", &"crossbow", &"impact_ground", &"down", &"hoof_walk"]:
		bases.append(int(view.call("_priority", kind, -1))) # Exact base catalog ranking, including before first player gate.
	crowd.configure_audio_projection(enabled, Engine.get_process_frames(), int(stats.epoch), player_index,
		int(lab.controlled_person_id()), bases, view.native_step_watch_ids())

func _audio_native_snapshot() -> Dictionary:
	if not active or crowd == null or not crowd.has_method("audio_metadata") or not crowd.has_method("audio_geometry") or not crowd.has_method("audio_step_invalidations"): return {}
	var view: SiteAudioView = lab.audio_view
	if view == null: return {}
	var stats := view.stats_snapshot()
	if not bool(stats.batch_open): return {} # capture_save/cold candidate remains silent.
	# Pure bounded reads BEFORE original drain. Only deliver AFTER its success.
	var meta: PackedInt64Array = crowd.audio_metadata()
	var geometry: PackedFloat64Array = crowd.audio_geometry()
	var invalidations: PackedInt64Array = crowd.audio_step_invalidations()
	if meta.size() % 8 != 0 or meta.size() > 64 * 8 or geometry.size() != (meta.size() >> 1) or invalidations.size() % 3 != 0 or invalidations.size() > 64 * 3: return {}
	for value: float in geometry:
		if not is_finite(value): return {}
	for at in range(0, meta.size(), 8):
		if meta[at] < 0 or meta[at] >= 8 or meta[at + 4] < 0 or meta[at + 5] <= 0: return {}
		if meta[at] != 1 and meta[at + 1] <= 0: return {}
		if meta[at] == 0 and (meta[at + 6] not in [1, 3, 5, 7] or geometry[(at >> 1) + 3] <= 0.0): return {}
	for at in range(0, invalidations.size(), 3):
		if invalidations[at] <= 0 or invalidations[at + 1] < 0 or invalidations[at + 2] <= 0: return {}
	return {"meta": meta, "geometry": geometry, "invalidations": invalidations,
		"frame": Engine.get_process_frames(), "epoch": int(stats.epoch), "native": crowd, "view": view}

func _audio_native_deliver(snapshot: Dictionary) -> void:
	if snapshot.is_empty() or not active or crowd == null or not is_same(snapshot.native, crowd) or lab.audio_view == null or not is_same(snapshot.view, lab.audio_view): return
	var view: SiteAudioView = lab.audio_view
	var stats := view.stats_snapshot()
	if int(snapshot.frame) != Engine.get_process_frames() or int(snapshot.epoch) != int(stats.epoch) or not bool(stats.batch_open): return
	var invalidations: PackedInt64Array = snapshot.invalidations
	for at in range(0, invalidations.size(), 3): view.invalidate_step_candidate(int(invalidations[at]))
	var meta: PackedInt64Array = snapshot.meta
	var geometry: PackedFloat64Array = snapshot.geometry
	var kinds: Array[StringName] = [&"step_grass_walk", &"contact", &"shield", &"hurt", &"bow", &"crossbow", &"impact_ground", &"down"]
	for at in range(0, meta.size(), 8):
		var kind := int(meta[at])
		var identity := int(meta[at + 1])
		var ground := Vector2(geometry[at >> 1], geometry[(at >> 1) + 1]) * TerrainRenderer.CELL_PIXELS
		var key := "native:%d:%d:%d:%d:%d" % [int(snapshot.frame), int(meta[at + 4]), kind, int(meta[at + 3]), int(meta[at + 5])]
		if kind == 0:
			# Historical mounted bit came from the original admitted appearance input.
			lab._audio_step_completed(identity, ground, geometry[(at >> 1) + 3], bool(int(meta[at + 6]) & 2), bool(int(meta[at + 6]) & 4), true)
		else:
			view.offer(kinds[kind], ground, key, identity)
	# offer only forms batch candidates. Original outer sameTerrain/active/
	# completed/noPENDING/noFault/noPause guard alone commits them.

# ---------------------------------------------------------------- CAV-2 mounted riders
# A rider is a person whose GD appearance says mounted (the same flag the riding kit and audio read). Deploy imports every
# living rider as the native mounted flag. The native flag is saved with the crowd; the GD rider list is derived from it.
# A native dismount (a lost charge, 4.4 / 4.6) is written back to the row and the kit after each step.

func rider_identities() -> Array[int]:
	return _rider_ids.duplicate()

func _is_rider_row(identity: int) -> bool:
	if _actors.has(identity):
		var actor: TerrainTestCharacter = _actors[identity]
		return bool(actor._saved_appearance.get("mounted", false))
	# CAV-3a: an ordinary person rides only while its mount slot holds a horse (appearance.mounted is derived from the slot).
	return bool(_appearance(identity).get("mounted", false))

func _set_row_mounted(identity: int, on: bool) -> void:
	# Actors only. An Actor's riding state is its visual_state (toggle_mount / clip); the saved appearance follows it.
	# Ordinary persons are mounted only through the mount slot (_apply_row_mount); no second writer exists for them.
	if not _actors.has(identity): return
	var actor: TerrainTestCharacter = _actors[identity]
	actor._saved_appearance["mounted"] = on
	actor.visual_state.mounted = on
	if actor.editor != null: actor.editor.set_mount_enabled(on)

# CAV-3a: the only writer of an ordinary person's riding state. on=true draws a horse from goods, on=false returns it to goods,
# lost=true (dismount in a charge, or death) removes the horse without returning it. Refusals change nothing.
func _apply_row_mount(identity: int, on: bool, lost: bool = false) -> Dictionary:
	if _actors.has(identity):
		_set_row_mounted(identity, on)
		return SiteRuntime.ok()
	var body: Dictionary = _records[identity]
	if on == (not SiteRuntime.mount_item_id(body["item_state"]).is_empty()): return SiteRuntime.ok()
	var data: TerrainData = _staged_data if _staged_data != null else lab.terrain
	var holder: Dictionary = body.item_state
	var version := int(holder.get("version", -1))
	if on: return SiteRuntime.equip_mount(data, holder, body.cargo, identity, version)
	if lost: return SiteRuntime.lose_mount(data, holder, version)
	return SiteRuntime.unequip_mount(data, holder, body.cargo, version)

# Deploy import: living riders take the native flag. A refused rider fails the whole import (as the surrender import does).
func import_mounted_riders() -> Dictionary:
	for identity: int in crowd.person_ids():
		if not _is_rider_row(identity): continue
		var index := int(_index_by_id.get(identity, -1))
		if index < 0 or float(soldier_state(index).hp) <= 0.0: continue
		if not _actors.has(identity) and not SiteMountedSoldierAtlas.available(_appearance(identity)):
			return SiteRuntime.fail("MISSING_ASSET", "騎乘圖集未備妥；隊伍未交接")
		if not bool(crowd.set_soldier_mounted(index, true)):
			return SiteRuntime.fail("NATIVE_REFUSED", "原生群眾拒絕騎乘人物；原隊伍未交接")
	_rebuild_rider_ids()
	return SiteRuntime.ok()

func _rebuild_rider_ids() -> void:
	_rider_ids.clear()
	if crowd == null: return
	for identity: int in crowd.person_ids():
		var index := int(_index_by_id.get(identity, -1))
		if index >= 0 and bool(crowd.soldier_mounted(index)): _rider_ids.append(identity)

# Sets a GD person riding (or not) and mirrors it natively. Refused when the riding visuals or native cannot hold it; then
# nothing changes. Actors are not wired here.
func set_rider(identity: int, on: bool) -> Dictionary:
	if not _index_by_id.has(identity): return SiteRuntime.fail("INVALID", "原人物不在群眾中")
	if _actors.has(identity): return SiteRuntime.fail("UNSUPPORTED", "受控 actor 騎乘尚未接線")
	var index := int(_index_by_id[identity])
	var before := _is_rider_row(identity)
	if on == before and bool(crowd.soldier_mounted(index)) == on: return SiteRuntime.ok()
	# CAV-3a: the mount slot (horse from goods) is applied first; the atlas admits the ride, else the slot is rolled back.
	var applied := _apply_row_mount(identity, on)
	if not applied.ok: return applied
	if on and not SiteMountedSoldierAtlas.available(_appearance(identity)):
		_apply_row_mount(identity, false)
		return SiteRuntime.fail("MISSING_ASSET", "騎乘圖集未備妥；原人物未變更")
	if not bool(crowd.set_soldier_mounted(index, on)):
		_apply_row_mount(identity, before)
		return SiteRuntime.fail("NATIVE_REFUSED", "原生群眾拒絕騎乘狀態；原人物未變更")
	_rebuild_rider_ids()
	_update_kit(index, _appearance(identity))
	_refresh_bodies() # S1: a rider is drawn by the mounted atlas, so a bodied rider returns to it.
	return SiteRuntime.ok()

# Write-back of native dismounts and deaths. A native dismount or a death empties the mount slot and the horse is lost
# (not returned to goods). A dead rider keeps its appearance except for the lost horse.
func sync_rider_dismounts() -> void:
	if _rider_ids.is_empty() or crowd == null: return
	var kept: Array[int] = []
	for identity: int in _rider_ids:
		var index := int(_index_by_id.get(identity, -1))
		if index < 0: continue
		var alive := float(soldier_state(index).hp) > 0.0
		if bool(crowd.soldier_mounted(index)) and alive:
			kept.append(identity)
		elif _actors.has(identity):
			# An Actor rider loses its horse like an ordinary one: the worn horse item (if any) is lost, not returned,
			# and its live riding state ends, on a native dismount or on death.
			var actor: TerrainTestCharacter = _actors[identity]
			if not SiteRuntime.mount_item_id(actor.item_state).is_empty():
				var data: TerrainData = _staged_data if _staged_data != null else lab.terrain
				var lost := SiteRuntime.lose_mount(data, actor.item_state, int(actor.item_state.get("version", -1)))
				if not lost.ok: last_event_error = lost
			_set_row_mounted(identity, false)
			_audio_mount_update(index, false) # an actor keeps its live presentation
		else:
			var lost := _apply_row_mount(identity, false, true)
			if not lost.ok: last_event_error = lost
			_update_kit(index, _appearance(identity)) # A dead rider lies on its foot kit; the horse is gone.
	_rider_ids = kept

func _audio_mount_install(rows: PackedByteArray) -> void:
	if crowd == null or rows.size() != int(crowd.soldier_count()): return
	if crowd.has_method("set_audio_mounted_rows") and not bool(crowd.set_audio_mounted_rows(rows)): return
	_audio_mounted_rows = rows.duplicate()

func _audio_mount_update(index: int, mounted: bool) -> void:
	if crowd == null or index < 0 or index >= int(crowd.soldier_count()): return
	if crowd.has_method("set_audio_mounted") and not bool(crowd.set_audio_mounted(index, mounted)): return
	_audio_mounted_rows.resize(int(crowd.soldier_count()))
	_audio_mounted_rows[index] = 1 if mounted else 0
