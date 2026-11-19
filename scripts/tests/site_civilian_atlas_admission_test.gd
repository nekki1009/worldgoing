extends SceneTree
## CIV-A0 native sampling, not new-art admission or GPU visual acceptance.
const Profile = preload("res://scripts/terrain_lab/terrain_army_civilian_atlas.gd")
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const DIRS := ["up", "right", "down", "left"]
const SLOTS := ["combat_idle", "combat_walk", "combat_run", "walk_slash", "attack_jump_heavy", "guard", "hit", "knockback", "attack_bow", "down", "unconscious", "get_up", "rescue"]
var failed: bool = false
var finished: bool = false
var started: bool = false
var checks: int = 0
var output: String = ""
var tracks: Dictionary = {}
var sequences: Dictionary = {}
var samples: Array[Dictionary] = []
var cases: Array[String] = []
var manifest: Dictionary = {}

func _initialize() -> void:
	if "--ca03" in OS.get_cmdline_user_args():
		set_script(load("res://scripts/tests/civilian_atlas_ca03.gd"))
		call_deferred("_run")
		return
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if started and not finished and not failed: _need(false, "synchronous body interrupted")
	return false

func _need(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failed = true
		push_error("CIV_A0_FAIL " + label)
		quit(1)
	return ok

func _hash(bytes: PackedByteArray) -> String:
	var h: HashingContext = HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()

func _write(path: String, bytes: PackedByteArray) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if not _need(file != null, "fresh proof output opens"): return false
	file.store_buffer(bytes)
	file.close()
	return true

func _fixture() -> RefCounted:
	var c: RefCounted = ClassDB.instantiate(&"ArmyCrowd")
	if not _need(c != null and c.setup(1, 197), "original ArmyCrowd setup"): return null
	var flat: PackedByteArray = PackedByteArray()
	flat.resize(32 * 32)
	var walkable: PackedByteArray = flat.duplicate()
	walkable.fill(1) # Native Terrain::WALKABLE; height/ramp/block/facility remain zero.
	if not _need(c.set_terrain(32, 32, flat, walkable, flat, flat, flat), "original walkable flat native terrain"): return null
	c.set_ai(false)
	var formation: int = c.add_formation(0, 8.5, 8.5, 0.0, 3, 1.0, 0, 30.0)
	var ids: PackedInt64Array = PackedInt64Array([100, 101, 102, 103, 104, 105])
	var equipment: PackedInt32Array = PackedInt32Array()
	var roles: PackedByteArray = PackedByteArray([0, 0, 0, 0, 0, 1])
	var ammo: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])
	for _i: int in 6: equipment.append(1 | (2 << 8) | (2 << 16) | (1 << 24))
	if not _need(c.add_soldiers(formation, ids, equipment, roles, ammo) == 0 and c.finalize(), "six original native people"): return null
	if not _need(c.set_military_role(0, 2), "original civilian role; same native identity"): return null
	for i: int in 6:
		var state: PackedFloat64Array = c.get_soldier_state(i)
		state[14] = 4.5 + i
		state[15] = 3.5 + 2.0 * i
		if not _need(c.set_soldier_state(i, state, c.soldier_refs(i)), "place native fixture through original state boundary"): return null
	if not _register(c): return null
	c.render_set_filter(false)
	c.render_set_bands(4)
	c.render_set_actors(PackedFloat32Array([320.0, 240.0]))
	return c

func _register(c: RefCounted) -> bool:
	tracks.clear()
	sequences.clear()
	c.render_clear()
	var seq: int = 0
	for clip: Dictionary in manifest.clips:
		for direction: String in DIRS:
			var times: PackedFloat32Array = PackedFloat32Array()
			var anchors: PackedFloat32Array = PackedFloat32Array()
			var duration: float = 0.0
			for frame: Dictionary in manifest.frames:
				if str(frame.clip) != str(clip.id) or str(frame.direction) != direction: continue
				times.append(float(frame.sample_time))
				anchors.append(float(frame.anchor_offset.x) * float(manifest.map_scale))
				anchors.append(float(frame.anchor_offset.y) * float(manifest.map_scale))
				duration = float(frame.duration)
			if not _need(not times.is_empty(), "original admitted page sequence exists"): return false
			var key: String = str(clip.id) + "|" + direction
			tracks[key] = c.render_add_track(seq, duration, float(times[-1]) < duration - 0.000001, times, anchors, PackedFloat32Array(), 1.0 / 60.0)
			sequences[key] = seq
			if not _need(int(tracks[key]) >= 0, "original native track registration"): return false
			seq += 1
	var table: PackedInt32Array = PackedInt32Array()
	for clip: String in SLOTS:
		for direction: String in DIRS: table.append(int(tracks[clip + "|" + direction]))
	# Two page bindings to the SAME admitted source page exercise page/actor sorting, not two invented artworks.
	if not _need(c.render_add_kit(0, 0, float(manifest.map_scale), table) == 0 and c.render_add_kit(1, 1, float(manifest.map_scale), table) == 1, "original page/kit bindings"): return false
	return _need(c.render_set_kits(PackedInt32Array([0, 1, 0, 1, 0, 1])), "same real atlas on six original indices")

func _packet(c: RefCounted) -> Dictionary:
	var before: PackedByteArray = c.save_state()
	var hash_before: int = c.state_hash()
	var rows: PackedFloat32Array = c.pack_frame(64.0, 1.0 / 60.0)
	var result: Dictionary = {"rows": rows, "spans": c.row_spans(), "bounds": c.row_bounds(), "grounds": c.row_grounds()}
	_need(before == c.save_state() and hash_before == c.state_hash(), "packing never changes native save bytes/hash")
	return result

func _snapshot(c: RefCounted, name: String) -> void:
	var state: PackedByteArray = c.save_state()
	var packet: PackedByteArray = var_to_bytes(_packet(c))
	if not _need(state.decode_u32(0) == 0x3132574b, "KW21 native version unchanged"): return
	if not _write(output + "/" + name + ".save.bin", state): return
	if not _write(output + "/" + name + ".packet.bin", packet): return
	samples.append({"name": name, "save_sha256": _hash(state), "packet_sha256": _hash(packet), "native_state_hash": str(c.state_hash())})

func _activity(c: RefCounted, clip: String, age: float = 0.0, index: int = 0) -> bool:
	var selected: PackedInt32Array = PackedInt32Array()
	for direction: String in DIRS: selected.append(int(tracks[clip + "|" + direction]))
	return bool(c.call("render_set_activity", PackedInt32Array([index]), selected, PackedFloat32Array([age]), PackedByteArray([1])))

func _clear(c: RefCounted) -> bool:
	return bool(c.call("render_set_activity", PackedInt32Array(), PackedInt32Array(), PackedFloat32Array(), PackedByteArray()))

func _chosen(c: RefCounted, packet: Dictionary, index: int = 0) -> int:
	var state: PackedFloat64Array = c.get_soldier_state(index)
	for at: int in range(0, packet.spans.size(), 6):
		if int(packet.spans[at + 1]) < 0: continue
		for offset: int in int(packet.spans[at + 3]):
			var slot: int = int(packet.spans[at + 2]) + offset
			if absf(float(packet.grounds[slot * 2]) - float(state[14]) * 64.0) < 0.0001 and absf(float(packet.grounds[slot * 2 + 1]) - float(state[15]) * 64.0) < 0.0001:
				return int(packet.rows[slot * 12 + 8])
	return -1

func _others(c: RefCounted, packet: Dictionary) -> PackedByteArray:
	var state: PackedFloat64Array = c.get_soldier_state(0)
	var rows: Array = []
	for at: int in range(0, packet.spans.size(), 6):
		if int(packet.spans[at + 1]) < 0:
			rows.append(packet.spans.slice(at, at + 6))
			continue
		for offset: int in int(packet.spans[at + 3]):
			var slot: int = int(packet.spans[at + 2]) + offset
			var ground: Vector2 = Vector2(packet.grounds[slot * 2], packet.grounds[slot * 2 + 1])
			if ground.distance_to(Vector2(state[14], state[15]) * 64.0) < 0.0001: continue
			rows.append([packet.spans.slice(at, at + 2), packet.spans[at + 5], ground, packet.rows.slice(slot * 12, slot * 12 + 12)])
	return var_to_bytes(rows)

func _candidate(c: RefCounted) -> bool:
	var before: PackedByteArray = c.save_state()
	var original: Dictionary = _packet(c)
	if not _need(_activity(c, "walk", 0.3), "valid civilian snapshot"): return false
	var shown: Dictionary = _packet(c)
	if not _need(before == c.save_state() and _chosen(c, shown) == int(sequences["walk|right"]), "original native selects admitted activity track, save unchanged"): return false
	if not _need(_others(c, shown) == _others(c, original), "all noncivilian rows and their order remain byte exact with active civilian"): return false
	var valid_packet: PackedByteArray = var_to_bytes(shown)
	var walk: PackedInt32Array = PackedInt32Array()
	for direction: String in DIRS: walk.append(int(tracks["walk|" + direction]))
	var bad: Array = [
		[PackedInt32Array([0]), PackedInt32Array(), PackedFloat32Array([0.0]), PackedByteArray([1])],
		[PackedInt32Array([6]), walk, PackedFloat32Array([0.0]), PackedByteArray([1])],
		[PackedInt32Array([-1]), walk, PackedFloat32Array([0.0]), PackedByteArray([1])],
		[PackedInt32Array([1]), walk, PackedFloat32Array([0.0]), PackedByteArray([1])],
		[PackedInt32Array([0]), PackedInt32Array([-1, -1, -1, -1]), PackedFloat32Array([0.0]), PackedByteArray([1])],
		[PackedInt32Array([0]), PackedInt32Array([99999, 99999, 99999, 99999]), PackedFloat32Array([0.0]), PackedByteArray([1])],
		[PackedInt32Array([0]), walk, PackedFloat32Array([-0.1]), PackedByteArray([1])],
		[PackedInt32Array([0]), walk, PackedFloat32Array([NAN]), PackedByteArray([1])],
		[PackedInt32Array([0]), walk, PackedFloat32Array([INF]), PackedByteArray([1])],
		[PackedInt32Array([0]), walk, PackedFloat32Array([0.0]), PackedByteArray([2])],
		[PackedInt32Array([0]), walk, PackedFloat32Array([0.0]), PackedByteArray([0])],
		[PackedInt32Array([0, 0]), walk + walk, PackedFloat32Array([0.0, 0.0]), PackedByteArray([1, 1])],
		[PackedInt32Array([1, 0]), walk + walk, PackedFloat32Array([0.0, 0.0]), PackedByteArray([0, 1])],
	]
	for row: Array in bad:
		if not _need(not c.call("render_set_activity", row[0], row[1], row[2], row[3]) and before == c.save_state() and var_to_bytes(_packet(c)) == valid_packet, "invalid snapshot rejected atomically"): return false
	cases.append("13 invalid snapshots reject without simulation or presentation mutation")
	if not _need(_clear(c) and var_to_bytes(_packet(c)) == var_to_bytes(original), "empty snapshot clears exactly"): return false
	if not _need(_activity(c, "walk") and c.load_state(before), "successful original load"): return false
	# load resets kit indices; the original kit/page binding is reinstalled, activity must not return.
	if not _need(c.render_set_kits(PackedInt32Array([0, 1, 0, 1, 0, 1])) and var_to_bytes(_packet(c)) == var_to_bytes(original), "load/kit boundary discards derived activity"): return false
	if not _need(_activity(c, "walk"), "activity before refused load"): return false
	valid_packet = var_to_bytes(_packet(c))
	if not _need(not c.load_state(PackedByteArray([1, 2, 3])) and before == c.save_state() and var_to_bytes(_packet(c)) == valid_packet, "refused load keeps existing activity and simulation"): return false
	if not _need(_clear(c), "clear before reaction checks"): return false
	for reaction: Dictionary in [{"field": 0, "value": 0.0, "clip": "down"}, {"field": 3, "value": 2.0, "clip": "unconscious"}, {"field": 4, "value": 0.5, "clip": "get_up"}]:
		if not _need(c.load_state(before) and c.render_set_kits(PackedInt32Array([0, 1, 0, 1, 0, 1])), "fresh reaction fixture"): return false
		var state: PackedFloat64Array = c.get_soldier_state(0)
		state[int(reaction.field)] = float(reaction.value)
		if not _need(c.set_soldier_state(0, state, c.soldier_refs(0)) and _activity(c, "walk"), "original native reaction input"): return false
		if not _need(_chosen(c, _packet(c)) == int(sequences[str(reaction.clip) + "|right"]), "original down/KO/getup outranks activity"): return false
	cases.append("native down, KO and getup outrank activity")
	if not _need(c.load_state(before) and c.render_set_kits(PackedInt32Array([0, 1, 0, 1, 0, 1])), "restore for routing"): return false
	var formation: PackedFloat64Array = c.get_formation_state(0)
	formation[0] = 0.0
	formation[5] = 1.0
	formation[9] = 4.0
	formation[10] = 25.0
	formation[11] = 25.0
	if not _need(c.set_formation_state(0, formation, c.formation_refs(0)), "original routed RETREAT fixture"): return false
	var saw_run: bool = false
	var retreat_rows: Array = []
	for _tick: int in 90:
		if not _need(c.step(1.0 / 30.0) and _activity(c, "idle"), "bounded original retreat step"): return false
		var selected: int = _chosen(c, _packet(c))
		retreat_rows.append({"tick": _tick, "sequence": selected, "native_pose": c.contact_pose_state(0), "person": c.get_soldier_state(0), "formation": c.get_formation_state(0)})
		for direction: String in DIRS:
			if selected == int(sequences["combat_run|" + direction]): saw_run = true
		if saw_run: break
	if not saw_run: _write(output + "/retreat_diagnostic.json", JSON.stringify(retreat_rows, "\t").to_utf8_buffer())
	if not _need(saw_run, "actual native routed run outranks idle activity"): return false
	cases.append("actual original native retreat/run outranks activity")
	return true

func _run() -> void:
	started = true
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var at: int = args.find("--ca01-out")
	if not _need(at >= 0 and at + 1 < args.size(), "explicit fresh output"): return
	output = args[at + 1]
	if not _need(output.begins_with("res://output/") and output == output.simplify_path() and not DirAccess.dir_exists_absolute(output), "output confined and never reused"): return
	if not _need(DirAccess.make_dir_recursive_absolute(output) == OK, "fresh evidence directory"): return
	var contract: Dictionary = Profile.contract()
	if not _need(contract.catalog.size() == 4 and Profile.frames() == 416 and Profile.frames(true) == 256 and Profile.actions().size() == 12 and contract.source_sha256.size() == Profile.SOURCE_PATHS.size(), "frozen four-look / twelve-action / source contract"): return
	var copy: Array[Dictionary] = Profile.catalog()
	copy[0].appearance.parts.boots = "none"
	if not _need(Profile.catalog()[0].appearance.parts.boots == "boots_civilian_straw_01", "callers cannot mutate frozen catalog"): return
	for row: Dictionary in contract.catalog:
		# A0 asserted the straw gear was not yet in the character packs. CIV-A1/A1F (applied 2026-11-19) added it, so every
		# catalog appearance is now a valid editor appearance; its atlas pages are admitted by the --ca03 run.
		if not _need(HumanCharacter3DEditor.valid_appearance(row.appearance), "the straw gear of every catalog row is in the character packs (CIV-A1/A1F)"): return
	manifest = JSON.parse_string(FileAccess.get_file_as_string(Atlas.BASE_MANIFEST))
	var admitted: Dictionary = Atlas.admit_crowd_appearances([manifest.appearance], [])
	if not _need(Atlas.supports(manifest.appearance) and admitted.ok, "existing real appearance passes current original native atlas admission"): return
	var c: RefCounted = _fixture()
	if failed or c == null: return
	var baseline: bool = args.has("--ca01-baseline")
	var reference_path: String = ""
	var seed: PackedByteArray = c.save_state()
	if not baseline:
		var reference_at: int = args.find("--ca01-reference")
		if not _need(reference_at >= 0 and reference_at + 1 < args.size(), "candidate requires original-build baseline"): return
		reference_path = args[reference_at + 1]
		seed = FileAccess.get_file_as_bytes(reference_path.get_base_dir() + "/seed.save.bin")
	# The original serializer writes Stats/Event POD padding. Compare exact bytes from one admitted native save,
	# not unrelated constructor stack contents. No input or output bytes are masked or normalized here.
	if not _need(c.load_state(seed) and _register(c), "same original native serialized starting state"): return
	if not _write(output + "/seed.save.bin", seed): return
	_snapshot(c, "step_000")
	for tick: int in 120:
		if not _need(c.step(1.0 / 30.0), "bounded original native step"): return
		if tick in [0, 14, 59, 119]: _snapshot(c, "step_%03d" % (tick + 1))
	if failed: return
	if not _need(c.has_method("render_set_activity") != baseline, "right baseline/candidate native DLL"): return
	if not baseline:
		var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(reference_path))
		if not _need(reference.get("status") == "PASS" and reference.get("baseline") == true and reference.get("samples", []).size() == 5 and str(reference.get("native_build", "")) != str(c.build_id()), "original-build baseline receipt, never a candidate self-comparison"): return
		if not _need(reference.samples == samples, "original versus modified native state/packets/sorting exact at five checkpoints"): return
		for sample: Dictionary in samples:
			for suffix: String in [".save.bin", ".packet.bin"]:
				if not _need(FileAccess.get_file_as_bytes(output + "/" + sample.name + suffix) == FileAccess.get_file_as_bytes(reference_path.get_base_dir() + "/" + sample.name + suffix), "cross-build full byte readback " + sample.name + suffix): return
		cases.append("five cross-build complete native save and packet byte comparisons")
		c = _fixture()
		if failed or not _candidate(c): return
	var report: Dictionary = {"status": "PASS", "baseline": baseline, "checks": checks, "samples": samples, "cases": cases,
		"profile_contract": contract, "admission": admitted, "native_build": c.build_id(),
		"scope": "CA-01 native headless sampling only; actual admitted source page; no new art, resident owner, GPU or FPS claim"}
	if not _write(output + "/result.json", JSON.stringify(report, "\t").to_utf8_buffer()): return
	finished = true
	print("CIV_A0_CA01_PASS baseline=", baseline, " checks=", checks, " profile_frames=416 phase1=256 native_sampling_only=true")
	quit(0)
