extends RefCounted
## CIV-A3 step 3 (平民 C1c): residents on a crowd Site show the civilian work clips through the native presentation
## override (World::render_set_activity, CIV-A0). Presentation only: no simulation, save or clock state is read back or
## written. The native side applies an activity only while the person's own slot is idle or walk; reactions, KO, rescue
## and running always win. The host supplies the age, so ages are refreshed every UPDATE_SECONDS of host time.
##   meal / evening, at home      -> civilian_sit (plays once, then holds the last pose)
##   wake (05:00–06:00), outdoors -> civilian_fetch_water (repeats, with a pause)
##   work, walking                -> civilian_carry (1.0 s loop)
##   work, standing               -> civilian_lift up and back down (reverse), repeated
## Sleep and anything else: no activity (the original idle / walk).
const Schedule = preload("res://scripts/terrain_lab/site_resident_schedule.gd")
const Housing = preload("res://scripts/terrain_lab/site_housing.gd")
const Work = preload("res://scripts/terrain_lab/civilian_work_clips.gd")
const DIRS := ["up", "right", "down", "left"] # crowd_site.DIRS order, the native track order of one activity row
const UPDATE_SECONDS := 0.1
const DECIDE_SECONDS := 1.0
const CIVILIAN_ROLE := 2
const FETCH_CYCLE := 4.0
const LIFT_CYCLE := 4.0 # 1.6 s up, 0.4 s hold, 1.6 s down, 0.4 s rest
const MOVING_SPEED := 0.05

var _tracks := {} # kit id -> {clip: PackedInt32Array(4)}
var _choice := {} # person id -> {"clip": String, "since": float}
var _clock := 0.0
var _since_update := INF
var _since_decide := INF
var _rejected := false

func clear() -> void:
	_tracks.clear()
	_choice.clear()
	_since_update = INF
	_since_decide = INF

## Called when a civilian kit is built from its admitted page: one native track per work clip and direction.
func register_kit(crowd: RefCounted, page: Dictionary, kit: int) -> bool:
	var tracks := {}
	for clip: String in Work.IDS:
		var row := PackedInt32Array()
		for dir: String in DIRS:
			var key := clip + "|" + dir
			if not page.sequences.has(key): return false
			var seq: int = int(page.sequences[key])
			var frames: Array = page.samples[seq]
			var times := PackedFloat32Array()
			var anchors := PackedFloat32Array()
			for f: Dictionary in frames:
				times.append(float(f.sample_time))
				anchors.append(float(f.anchor_offset.x) * float(page.scale))
				anchors.append(float(f.anchor_offset.y) * float(page.scale))
			var loop := clip == "civilian_carry"
			# The carry page samples one 1.0 s cycle with one-shot spacing (last sample 0.875 s): play it as that loop.
			var duration := float(Work.DURATIONS[clip]) if loop else float(frames[0].duration)
			var track: int = crowd.render_add_track(seq, duration, loop, times, anchors, PackedFloat32Array(), 1.0 / 60.0)
			if track < 0: return false
			row.append(track)
		tracks[clip] = row
	_tracks[kit] = tracks
	return true

func has_kits() -> bool:
	return not _tracks.is_empty()

## Every host frame; pushes a fresh activity set at most every UPDATE_SECONDS.
func update(site: Variant, frame_dt: float) -> void:
	_clock += maxf(frame_dt, 0.0)
	_since_update += maxf(frame_dt, 0.0)
	_since_decide += maxf(frame_dt, 0.0)
	if _tracks.is_empty() or _since_update < UPDATE_SECONDS: return
	_since_update = 0.0
	var crowd: RefCounted = site.crowd
	if _since_decide >= DECIDE_SECONDS:
		_since_decide = 0.0
		_decide(site)
	var indices := PackedInt32Array()
	var rows := {}
	for identity: int in _choice:
		var index := int(site._index_by_id.get(identity, -1))
		if index < 0 or index >= site._kit_ids.size(): continue
		var kit := int(site._kit_ids[index])
		if not _tracks.has(kit): continue
		var choice: Dictionary = _choice[identity]
		rows[index] = [_tracks[kit][choice.clip], _age(choice, identity)]
		indices.append(index)
	indices.sort()
	var tracks := PackedInt32Array()
	var ages := PackedFloat32Array()
	var valid := PackedByteArray()
	for index: int in indices:
		tracks.append_array(rows[index][0])
		ages.append(float(rows[index][1]))
		valid.append(1)
	if bool(crowd.render_set_activity(indices, tracks, ages, valid)): return
	# One row the native side will not take (a militia draft, a released or absent person) rejects the whole set;
	# drop it from the choices so the rest keep playing, and say so once.
	if not _rejected: printerr("crowd10k: civilian activity set refused; dropping the refused people")
	_rejected = true
	crowd.render_set_activity(PackedInt32Array(), PackedInt32Array(), PackedFloat32Array(), PackedByteArray())
	for identity: int in _choice.keys():
		var index := int(site._index_by_id.get(identity, -1))
		var row: Array = rows.get(index, [])
		if row.is_empty() or not bool(crowd.render_set_activity(PackedInt32Array([index]), row[0], PackedFloat32Array([float(row[1])]), PackedByteArray([1]))):
			_choice.erase(identity)
	crowd.render_set_activity(PackedInt32Array(), PackedInt32Array(), PackedFloat32Array(), PackedByteArray())

func _decide(site: Variant) -> void:
	var lab: Variant = site.lab
	var controller: Variant = lab.site_controller
	var housing: Dictionary = lab.terrain.site.get("housing", {})
	var minute := float(lab.terrain.site.get("minute", 0))
	var controlled := int(lab.controlled_person_id())
	var crowd: RefCounted = site.crowd
	var next := {}
	for key: Variant in housing:
		var identity := int(key)
		if identity == controlled: continue
		var index := int(site._index_by_id.get(identity, -1))
		if index < 0 or index >= site._kit_ids.size() or not _tracks.has(int(site._kit_ids[index])): continue
		if int(crowd.get_military_role(index)) != CIVILIAN_ROLE or not bool(crowd.get_soldier_presence(index)): continue
		var person: Dictionary = controller.person_actions._person(identity, false)
		if person.is_empty() or float(person.get("hp", 0.0)) <= 0.0: continue
		var phase := Schedule.phase_at(Schedule.minute_of_day(minute), Schedule.diligence_of(person))
		var at_home: bool = phase in ["meal", "evening"] and Housing._attends(lab, identity)
		var working: bool = phase == "work" and controller.work_team.is_assigned(identity)
		var moving := false
		if working:
			var state: PackedFloat64Array = crowd.get_soldier_state(index)
			moving = state.size() > 23 and Vector2(state[22], state[23]).length() > MOVING_SPEED
		var clip := choose(phase, at_home, working, moving)
		if clip.is_empty(): continue
		var previous: Dictionary = _choice.get(identity, {})
		next[identity] = previous if previous.get("clip", "") == clip else {"clip": clip, "since": _clock}
	_choice = next

## The table in the header, as a pure rule (tested by crowd_civilian_activity_test.gd).
static func choose(phase: String, at_home: bool, working: bool, moving: bool) -> String:
	if phase in ["meal", "evening"] and at_home: return "civilian_sit"
	if phase == "wake": return "civilian_fetch_water"
	if phase == "work" and working: return "civilian_carry" if moving else "civilian_lift"
	return ""

func _age(choice: Dictionary, identity: int) -> float:
	return age_of(str(choice.clip), maxf(0.0, _clock - float(choice.since)), float(identity % 97) * 0.37)

## Source time of `clip` after `elapsed` seconds; `offset` keeps neighbours out of step (not used by sit).
static func age_of(clip: String, elapsed: float, offset: float) -> float:
	match clip:
		"civilian_sit": return minf(elapsed, float(Work.DURATIONS.civilian_sit))
		"civilian_fetch_water": return minf(fmod(elapsed + offset, FETCH_CYCLE), float(Work.DURATIONS.civilian_fetch_water))
		"civilian_carry": return fmod(elapsed + offset, float(Work.DURATIONS.civilian_carry))
		"civilian_lift":
			var up := float(Work.DURATIONS.civilian_lift)
			var t := fmod(elapsed + offset, LIFT_CYCLE)
			if t < up: return t
			if t < LIFT_CYCLE * 0.5: return up
			if t < LIFT_CYCLE * 0.5 + up: return up - (t - LIFT_CYCLE * 0.5) # reverse: put it back down
			return 0.0
	return 0.0
