extends "res://scripts/tests/helpers/crowd_host_profile_controller.gd"
## Test-only exact source transcription. Only marked timer lines may differ.
const SOURCE_PATH := "res://scripts/terrain_lab/site_controller.gd"
const COPY_PATH := "res://scripts/tests/helpers/crowd_supply_subphase_controller.gd"
const PINNED_SOURCE_SHA := "c9c9d198f257573a546d6f05eab5b77acc2eb226ca13a4a05f35631c791ce93b"
const PHASE_NAMES := ["supply.phase1_snapshot_and_feeding", "supply.phase2_members_and_owner_setup",
	"supply.phase3_slice_and_sustain", "supply.phase4_commit_and_checkpoints"]
var use_original_sustain := false
var supply_phase_steps: Array[Dictionary] = []

static func _function_text(source: String, function_name: String) -> String:
	var text := "\n" + source.replace("\r\n", "\n")
	var begin := text.find("\nfunc " + function_name + "(")
	if begin < 0: return ""
	var end := text.find("\nfunc ", begin + 1)
	return text.substr(begin + 1, end - begin - 1 if end >= 0 else -1).strip_edges()

static func source_pin() -> Dictionary:
	var original := _function_text(FileAccess.get_file_as_string(SOURCE_PATH), "advance_crowd_sustain")
	var copied := _function_text(FileAccess.get_file_as_string(COPY_PATH), "_profiled_advance_crowd_sustain")
	var clean := PackedStringArray()
	for line: String in copied.split("\n"):
		if not line.contains("# SUPPLY_SUBPHASE_TIMER"): clean.append(line)
	var restored := "\n".join(clean).replace("func _profiled_advance_crowd_sustain(", "func advance_crowd_sustain(").strip_edges()
	var actual := FileAccess.get_sha256(SOURCE_PATH)
	return {"ok": not original.is_empty() and original == restored and actual == PINNED_SOURCE_SHA,
		"expected_source_sha256": PINNED_SOURCE_SHA, "actual_source_sha256": actual,
		"original_function_sha256": original.sha256_text(), "restored_function_sha256": restored.sha256_text()}

func advance_crowd_sustain(seconds: float) -> void:
	if use_original_sustain:
		super.advance_crowd_sustain(seconds)
		return
	var token: Dictionary = profiler.begin("host.crowd_supply")
	_profiled_advance_crowd_sustain(seconds)
	profiler.end(token)

func _profiled_advance_crowd_sustain(elapsed_game_seconds: float) -> void:
	if not _crowd_active() or elapsed_game_seconds <= 0.0 or get_tree().paused or bool(lab.terrain.site.paused): return
	var _phase_us := PackedInt64Array([0, 0, 0, 0]) # SUPPLY_SUBPHASE_TIMER
	var _phase_started := Time.get_ticks_usec() # SUPPLY_SUBPHASE_TIMER
	var _phase1_token: Dictionary = profiler.begin(PHASE_NAMES[0]) # SUPPLY_SUBPHASE_TIMER
	# Same-call projection only. With observers, retain each first-read sample
	# across damage callbacks; people not read yet must then sample current native state.
	var life := PackedFloat64Array()
	if lab.crowd_site.crowd.has_method("get_life_states"):
		life = lab.crowd_site.crowd.get_life_states()
		if life.size() != int(lab.crowd_site.crowd.soldier_count()) * 3: life = PackedFloat64Array()
	# Closures share this box; an unobserved call keeps its existing allocation-free reads.
	var bulk_window: Variant = {"open": true} if not lab.crowd_site.get_signal_connection_list("events_received").is_empty() else null
	var samples := {}
	var feeding: Dictionary = captivity_supply.feeding_index()
	_phase_us[0] += profiler.end(_phase1_token) # SUPPLY_SUBPHASE_TIMER
	for team_owner: RefCounted in lab.crowd_site.person_owners():
		var entry := _supply_entry(team_owner)
		if entry.is_empty(): continue
		var _phase2_token: Dictionary = profiler.begin(PHASE_NAMES[1]) # SUPPLY_SUBPHASE_TIMER
		var originals := {}
		for index: int in team_owner.records:
			originals[team_owner.combat_identity(index)] = team_owner.records[index]
		for index: int in team_owner.actors:
			originals[team_owner.combat_identity(index)] = _actor_supply_adapter(team_owner.actors[index])
		var members: Dictionary = captivity_supply.team_members(team_owner, originals, feeding, lab.crowd_site._records)
		var hot_read := func(identity: int, field: StringName) -> Variant:
			if field == &"hp" or field == &"ko" or field == &"captive":
				# Same-call samples survive mapping edits; use their original index/value.
				var cached: Variant = samples.get(identity)
				if cached is int:
					if field == &"hp": return life[cached * 3]
					if field == &"ko": return life[cached * 3 + 1]
					return bool(life[cached * 3 + 2])
				if cached is PackedFloat64Array and not cached.is_empty():
					if field == &"hp": return cached[0]
					if field == &"ko": return cached[3]
					return bool(cached[6])
				var index := int(lab.crowd_site._index_by_id.get(identity, -1))
				if not life.is_empty():
					var bulk_index := index
					if samples.has(identity):
						bulk_index = int(samples[identity]) if samples[identity] is int else -1
					elif bulk_window != null:
						if index >= 0 and bool(bulk_window.open): samples[identity] = index
						else: bulk_index = -1
					if bulk_index >= 0:
						if field == &"hp": return life[bulk_index * 3]
						if field == &"ko": return life[bulk_index * 3 + 1]
						return bool(life[bulk_index * 3 + 2])
				if index >= 0:
					if not samples.has(identity) or samples[identity].is_empty():
						samples[identity] = lab.crowd_site.crowd.get_soldier_state(index)
				if samples.has(identity):
					var values: PackedFloat64Array = samples[identity]
					if field == &"hp": return values[0]
					if field == &"ko": return values[3]
					return bool(values[6])
			elif lab.crowd_site.contains_person(identity):
				var person_owner: RefCounted = lab.crowd_site.person_owner(identity)
				return person_owner.combat_hot_get(person_owner.index_for_identity(identity), field, 0.0)
			return members.get(identity, {}).get(field, 0.0)
		var pending_hp := {}
		var old_morale := float(entry.sustain.morale)
		var old_routed := bool(entry.sustain.routed)
		var old_regroup := float(entry.sustain.regroup_seconds)
		var morale_delta := 0.0
		var fully_fed := true
		var left := elapsed_game_seconds
		_phase_us[1] += profiler.end(_phase2_token) # SUPPLY_SUBPHASE_TIMER
		while left > 0.000000001:
			var _phase3_token: Dictionary = profiler.begin(PHASE_NAMES[2]) # SUPPLY_SUBPHASE_TIMER
			# Sustain owns meals/hunger. Its bounded neutral score extracts only
			# meal/shortage delta; native alone owns actual morale/rout/regroup.
			entry.sustain.morale = 50.0
			entry.sustain.routed = false
			entry.sustain.regroup_seconds = 0.0
			var seconds := minf(left, 600.0)
			var at := float(entry.sustain.at)
			# Bound the neutral morale slice without resupplying or reading people
			# twice. advance_to still validates the complete original state first.
			if entry.sustain.get("cohorts") is Array:
				for cohort: Variant in entry.sustain.cohorts:
					if cohort is Dictionary and Sustain._number(cohort.get("meal_until"), 0):
						var until := float(cohort.meal_until)
						if until <= at: until = Sustain._next_meal(at)
						seconds = minf(seconds, until - at)
			var outcome := Sustain.advance_to(entry.sustain, members, entry.inventory, float(entry.sustain.at) + seconds,
				{"safe": false, "stopped": false, "hot_read": hot_read, "pending_hp": pending_hp})
			_phase_us[2] += profiler.end(_phase3_token) # SUPPLY_SUBPHASE_TIMER
			if not outcome.ok:
				_auto_save_blocked = true
				show_result(outcome)
				break
			var _phase4_token: Dictionary = profiler.begin(PHASE_NAMES[3]) # SUPPLY_SUBPHASE_TIMER
			fully_fed = fully_fed and bool(outcome.fully_fed)
			morale_delta += float(entry.sustain.morale) - 50.0
			if float(outcome.consumed_rations) > 0.0: entry.revision = int(entry.revision) + 1
			for identity: Variant in outcome.damage:
				var before := float(hot_read.call(int(identity), &"hp"))
				var loss := before if float(pending_hp[identity]) == 0.0 else float(outcome.damage[identity])
				pending_hp[int(identity)] = _apply_supply_damage(int(identity), loss)
				if bulk_window != null: bulk_window.open = false
				samples[int(identity)] = PackedFloat64Array() # Damage invalidates this person's bulk sample too.
			left -= seconds
			_phase_us[3] += profiler.end(_phase4_token) # SUPPLY_SUBPHASE_TIMER
		var _checkpoint_token: Dictionary = profiler.begin(PHASE_NAMES[3]) # SUPPLY_SUBPHASE_TIMER
		entry.sustain.morale = old_morale
		entry.sustain.routed = old_routed
		entry.sustain.regroup_seconds = old_regroup
		for identity: int in members:
			entry.life_checkpoint[str(identity)] = _life(members[identity], hot_read, pending_hp)
		lab.crowd_site.set_sustain_input(team_owner.formation_index, fully_fed, morale_delta)
		_phase_us[3] += profiler.end(_checkpoint_token) # SUPPLY_SUBPHASE_TIMER
	if profiler.enabled: # SUPPLY_SUBPHASE_TIMER
		supply_phase_steps.append({"before_native_step": lab.crowd_site._steps, "phase_us": Array(_phase_us), "function_us": Time.get_ticks_usec() - _phase_started}) # SUPPLY_SUBPHASE_TIMER
