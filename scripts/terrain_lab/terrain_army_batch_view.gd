extends Node2D
## Read-only presentation columns. Original Army rows own every gameplay value.
const Atlas = preload("res://scripts/terrain_lab/terrain_army_equipment_atlas.gd")
const DyeAtlas = preload("res://scripts/terrain_lab/terrain_army_dye_atlas.gd")
const GpuBufferWriter = preload("res://scripts/terrain_lab/terrain_army_gpu_buffer_writer.gd")
const SHADER := """
shader_type canvas_item;
uniform sampler2D sequence_data : filter_nearest, repeat_disable;
uniform sampler2D palette_data : filter_nearest, repeat_disable;
uniform sampler2D dye_map : filter_nearest, repeat_disable;
varying flat int palette_row;
varying flat vec4 frame_clip;
varying vec4 instance_tint;
void vertex() {
    int sequence = int(INSTANCE_CUSTOM.x);
    int frame = int(INSTANCE_CUSTOM.y);
    vec4 rect = texelFetch(sequence_data, ivec2(1 + frame * 2, sequence), 0);
    vec4 source_rect = texelFetch(sequence_data, ivec2(2 + frame * 2, sequence), 0);
    VERTEX = vec2(-0.5) * rect.zw + UV * rect.zw;
    UV = source_rect.xy + source_rect.zw * UV;
    // Match Godot's original AtlasTexture clip bounds, including Canvas RD's
    // half-float varying representation, rather than sampling adjacent frames.
    frame_clip = vec4(unpackHalf2x16(packHalf2x16(source_rect.xy)), unpackHalf2x16(packHalf2x16(source_rect.zw)));
    instance_tint = COLOR;
    palette_row = int(INSTANCE_CUSTOM.z);
}
void fragment() {
    vec2 half_pixel = TEXTURE_PIXEL_SIZE * 0.5;
    vec2 sample_uv = clamp(UV, frame_clip.xy + half_pixel, frame_clip.xy + abs(frame_clip.zw) - half_pixel);
    vec4 original = instance_tint * texture(TEXTURE, sample_uv);
    vec3 mask = texture(dye_map, sample_uv).rgb;
    int slot = int(round(mask.r * 255.0));
    if (slot >= 1 && slot <= 5) {
        vec4 dye = texelFetch(palette_data, ivec2(slot - 1, palette_row), 0);
        original.rgb = mix(original.rgb, dye.rgb * mask.g, dye.a * mask.b);
    }
    COLOR = original;
}
"""

var _army: Node2D
var _pages: Array[Dictionary] = []
var _page_keys := {}
var _appearances: Array[Dictionary] = []
var _descriptors: Array[Dictionary] = []
var _positions := PackedVector2Array()
var _sequence := PackedInt32Array()
var _frames := PackedInt32Array()
var _page := PackedInt32Array()
var _palette := PackedInt32Array()
var _rows := {}
var _original_sprites := {}
var _batches := {}
var _palette_keys := {}
var _palette_image: Image
var _palette_texture: ImageTexture
var _palette_dirty := false
var _shader: Shader
var _mesh: ArrayMesh
var _sampled_frames := {}
# Consecutive identical samples share only immutable atlas results, never a
# person's clock, appearance or ground. Reset at each presentation submission.
var _last_page := -1
var _last_clip := ""
var _last_direction := ""
var _last_time := -1.0
var _last_sequence := 0
var _last_frame := 0
var _last_anchor := Vector2.ZERO
var rendered_count := 0
var active_batches := 0
var _idle_samples: Array = [] # Immutable atlas projection, never person state.
var _idle_and_unconscious_samples: Array = []
var _native_mask := PackedByteArray()
var _native_rows := PackedInt32Array()
var native_prepared_count := 0
var native_unconscious_enabled := true # A/B switch; false retains the original idle-only native packet.
var native_buffer_enabled := true
var native_buffer_instances := 0
var native_grouping_enabled := true
var native_grouped_count := 0
var gpu_compute_enabled := false # Opt-in P1 presentation path; gameplay remains on Army.
var gpu_fallback_count := 0
var gpu_prime_count := 0
var gpu_dispatch_count: int:
	get: return _gpu_writer.completed_count() if _gpu_writer != null else 0
var gpu_last_error: String:
	get: return _gpu_writer.last_error() if _gpu_writer != null else ""
var _gpu_writer
var _gpu_primed := {} # Run key -> instance count; only CPU initialization touches MultiMesh.buffer.
var _gpu_last_compact := {} # Unchanged runs retain their GPU instance contents.
var _gpu_active_keys: Array[Vector2i] = []
var _gpu_retained_keys: Array[Vector2i] = []
var _group_spans := PackedInt32Array() # Current frame only: row/run/start/stop/page.
var _groups_ready := false
var retained_enabled := false
var mechanism_enabled := false
var _retained_ready := false
var _retained_mode := false
var _retained_gpu_mode := false
var _grounds := PackedVector2Array()
var _ground_ready := PackedByteArray()
var _authored_durations := PackedFloat64Array()
var _index_row := PackedInt32Array()
var _index_run := PackedInt32Array()
var _row_spans := {} # row -> ordered {page, members} runs from the last flush.
var _changed_rows := {}
var _changed_runs := {}
var _mechanism := {}

func mechanism_stats() -> Dictionary:
	return _mechanism.duplicate()

func _reset_mechanism() -> void:
	_mechanism = {"static_observations": 0, "ground_projections": 0, "animation_samples": 0,
		"changed_outputs": 0, "row_rebuilds": 0, "run_rebuilds": 0,
		"packed_instances": 0, "packed_bytes": 0, "multimesh_setters": 0,
		"multimesh_bytes": 0, "gpu_dispatches": 0}

func setup(army: Node2D, count: int) -> void:
	_army = army
	_appearances.resize(count)
	_descriptors.resize(count)
	_positions.resize(count)
	_sequence.resize(count)
	_frames.resize(count)
	_page.resize(count)
	_palette.resize(count)
	_grounds.resize(count)
	_ground_ready.resize(count)
	_authored_durations.resize(count)
	_authored_durations.fill(-1.0)
	_index_row.resize(count)
	_index_row.fill(-1)
	_index_run.resize(count)
	_index_run.fill(-1)
	_reset_mechanism()
	_palette_image = Image.create(5, maxi(1, count), false, Image.FORMAT_RGBAF)
	_palette_texture = ImageTexture.create_from_image(_palette_image)
	_shader = Shader.new()
	_shader.code = SHADER
	# One shared native mesh, with the original Canvas rectangle's diagonal.
	_mesh = ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2.ZERO, Vector2.DOWN, Vector2.ONE, Vector2.RIGHT])
	arrays[Mesh.ARRAY_TEX_UV] = arrays[Mesh.ARRAY_VERTEX]
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

func begin() -> void:
	_retained_mode = false
	_retained_ready = false
	_native_mask = PackedByteArray()
	_rows.clear()
	_row_spans.clear()
	_changed_rows.clear()
	_changed_runs.clear()
	_ground_ready.fill(0)
	_authored_durations.fill(-1.0)
	_index_row.fill(-1)
	_index_run.fill(-1)
	_original_sprites.clear()
	_sampled_frames.clear()
	_last_page = -1
	rendered_count = 0
	active_batches = 0
	native_prepared_count = 0
	native_buffer_instances = 0
	native_grouped_count = 0
	_group_spans = PackedInt32Array()
	_groups_ready = false
	_reset_mechanism()

func begin_retained() -> bool:
	if not retained_enabled or not _retained_ready or _retained_mode or gpu_compute_enabled != _retained_gpu_mode:
		return false
	_retained_mode = true
	_changed_rows.clear()
	_changed_runs.clear()
	_sampled_frames.clear()
	_last_page = -1
	_groups_ready = false
	_reset_mechanism()
	return true

func _exit_tree() -> void:
	if _gpu_writer != null: _gpu_writer.dispose()

func _on_gpu_writer_failed(_message: String) -> void:
	if not is_inside_tree() or not gpu_compute_enabled: return
	gpu_compute_enabled = false
	_gpu_last_compact.clear()
	gpu_fallback_count += 1
	flush() # Repack the retained rows even if the battle is paused and no new visual tick arrives.

func prepare_idle() -> void:
	if not _army._soldier_baked_ready or not _army.equipment_appearance_batch_query.is_valid(): return
	# The shipped library's Vector2 storage is float32. Keep other builds on GD.
	if PackedVector2Array([Vector2.ZERO]).to_byte_array().size() != 8: return
	var kernel: RefCounted = _army._combat_hot_store if _army.combat_hot_active() else TerrainArmy._get_idle_kernel()
	if kernel == null or not kernel.has_method("render_idle"): return
	var publications: Dictionary = _army.equipment_appearance_batch_query.call(_army.equipment_appearance_query)
	if publications.is_empty(): return
	if mechanism_enabled:
		_mechanism.static_observations += _army.combat_units.size()
		_mechanism.ground_projections += _army.combat_units.size()
		_mechanism.animation_samples += _army.combat_units.size()
	var packet: Array = kernel.call("render_idle", _army.combat_units, _army.cells, _army.moving_to,
		_army.facing, publications, _appearances, _descriptors,
		_idle_and_unconscious_samples if native_unconscious_enabled else _idle_samples,
		_army._sprites, TerrainRenderer.CELL_PIXELS)
	if packet.is_empty(): return
	_native_mask = packet[0]
	_positions = packet[1]
	_sequence = packet[2]
	_frames = packet[3]
	_page = packet[4]
	_palette = packet[5]
	_native_rows = packet[6]
	# These original people use the rider-only companion on their own Sprite.
	# Do not let native idle batching also draw a second standing copy.
	if _army.vehicle_transport != null:
		for vehicle: Dictionary in _army.vehicle_transport.records().values():
			if str(vehicle.kind) != "wagon" or int(vehicle.team_id) != _army.team_id or int(vehicle.operator_id) <= 0: continue
			var index: int = _army.index_for_identity(int(vehicle.operator_id))
			if index >= 0 and not _army._vehicle_rider_state(index).is_empty(): _native_mask[index] = 0

func can_group_prepared() -> bool:
	if _retained_mode or not native_grouping_enabled or _native_mask.is_empty() or _native_mask.size() != _page.size() or _native_rows.size() != _page.size(): return false
	var kernel: RefCounted = TerrainArmy._get_idle_kernel()
	return kernel != null and kernel.has_method("group_render_rows")

func prepared_exceptions() -> PackedInt32Array:
	# PackedArray.find scans in native code; only original exceptions enter GD.
	var indices := PackedInt32Array()
	var index := 0
	while index < _native_mask.size():
		index = _native_mask.find(0, index)
		if index < 0: break
		indices.append(index)
		index += 1
	return indices

func finish_prepared_groups() -> void:
	var kernel: RefCounted = TerrainArmy._get_idle_kernel()
	var packet: Array = kernel.call("group_render_rows", _native_mask, _native_rows, _rows.keys(), _rows.values(), _page) if kernel != null and native_grouping_enabled and kernel.has_method("group_render_rows") else []
	if packet.size() == 3:
		_rows = packet[0]
		_group_spans = packet[1]
		native_grouped_count = int(packet[2])
		native_prepared_count += native_grouped_count
		rendered_count += native_grouped_count
		_groups_ready = true
		return
	# Rebuild the same original ordinal row insertion without replaying callbacks.
	var fallback_rows := {}
	for row: int in _rows:
		for index: int in _rows[row]: fallback_rows[index] = row
	_rows = {}
	for index in range(_native_mask.size()):
		if submit_prepared(index): continue
		if fallback_rows.has(index):
			var row: int = fallback_rows[index]
			if not _rows.has(row): _rows[row] = []
			_rows[row].append(index)

func submit_prepared(index: int) -> bool:
	if _retained_mode or _native_mask.is_empty() or _native_mask[index] == 0: return false
	_groups_ready = false
	var row := _native_rows[index]
	if not _rows.has(row): _rows[row] = []
	_rows[row].append(index) # Same ordinal insertion and Sprite/page run splitting.
	rendered_count += 1
	native_prepared_count += 1
	return true

func _retain_assign(index: int, row: int, previous_page: int, next_page: int, output_changed: bool) -> void:
	var previous_row := _index_row[index]
	if previous_row >= 0 and (previous_row != row or previous_page != next_page):
		_rows[previous_row].erase(index)
		if _rows[previous_row].is_empty(): _rows.erase(previous_row)
		_changed_rows[previous_row] = true
		_index_run[index] = -1
	if previous_row < 0 or previous_row != row or previous_page != next_page:
		if not _rows.has(row): _rows[row] = []
		_rows[row].append(index)
		_changed_rows[row] = true
		_index_row[index] = row
	elif output_changed:
		_changed_runs[Vector2i(row, _index_run[index])] = true
	if previous_row < 0 or previous_page < 0:
		if next_page >= 0: rendered_count += 1
	elif next_page < 0:
		rendered_count -= 1
	if output_changed and mechanism_enabled: _mechanism.changed_outputs += 1

func submit(index: int, ground: Vector2, appearance: Dictionary, clip: String, direction: String, sample_time: float, authored_duration: float = -1.0) -> bool:
	if index < 0 or index >= _positions.size() or not is_finite(sample_time) or sample_time < 0.0: return false
	if mechanism_enabled:
		_mechanism.static_observations += 1
		_mechanism.ground_projections += 1
		_mechanism.animation_samples += 1
	if _descriptors[index].is_empty() or (not is_same(_appearances[index], appearance) and _appearances[index] != appearance):
		# Immutable owner publications can be compared by identity. Arbitrary
		# mutable callbacks retain a deep snapshot, detecting in-place dye edits.
		_appearances[index] = appearance if _deep_read_only(appearance) else appearance.duplicate(true)
		_descriptors[index] = _describe(appearance)
	var descriptor: Dictionary = _descriptors[index]
	if descriptor.is_empty(): return false # Original Sprite admission/failure path remains available.
	var page_index := int(descriptor.page)
	if _last_page != page_index or _last_clip != clip or _last_direction != direction or _last_time != sample_time:
		var page: Dictionary = _pages[page_index]
		var normalized := Atlas.normalized_clip(clip)
		# The standard base has its own polearm sequences. Preserve them;
		# only the compact weapon recipes need the Army's polearm aliases mapped.
		if (clip == "guard_spear" or clip.begins_with("guard_polearm")) and page.sequences.has(clip + "|" + direction): normalized = clip
		var key := normalized + "|" + direction
		if not page.sequences.has(key): return false
		var sequence := int(page.sequences[key])
		# Keep the original double-precision clock and CPU Sprite transform order;
		# shader float32 would shift nearest-filtered edge pixels.
		var samples: Array = page.samples[sequence]
		var sample_key := Vector2i(page_index, sequence)
		if not _sampled_frames.has(sample_key): _sampled_frames[sample_key] = {}
		var times: Dictionary = _sampled_frames[sample_key]
		var low := int(times.get(sample_time, -1))
		if low < 0:
			var first: Dictionary = samples[0]
			var elapsed := fposmod(sample_time, float(first.duration)) if float(samples.back().sample_time) < float(first.duration) - 0.000001 else minf(sample_time, float(first.duration))
			low = 0
			var high := samples.size()
			while low + 1 < high:
				var middle := low + ((high - low) >> 1)
				if float(samples[middle].sample_time) <= elapsed + 0.000000001: low = middle
				else: high = middle
			times[sample_time] = low # Exact double key, without time quantization.
		var frame: Dictionary = samples[low]
		_last_anchor = Vector2(float(frame.anchor_offset.x), float(frame.anchor_offset.y)) * float(page.scale)
		_last_sequence = sequence
		_last_frame = low
		_last_page = page_index
		_last_clip = clip
		_last_direction = direction
		_last_time = sample_time
	var previous_row := _index_row[index]
	var previous_page := _page[index]
	var previous_position := _positions[index]
	var previous_sequence := _sequence[index]
	var previous_frame := _frames[index]
	var previous_palette := _palette[index]
	_groups_ready = false
	_sequence[index] = _last_sequence
	_frames[index] = _last_frame
	_positions[index] = ground - _last_anchor
	_page[index] = int(descriptor.page)
	_palette[index] = int(descriptor.palette)
	if retained_enabled:
		_grounds[index] = ground
		_ground_ready[index] = 1
		_authored_durations[index] = authored_duration
	var row := 10 + int(ground.y / TerrainRenderer.CELL_PIXELS)
	if _retained_mode:
		var old_sprite: Sprite2D = _original_sprites.get(index)
		if old_sprite != null: old_sprite.visible = false
		_original_sprites.erase(index)
		_retain_assign(index, row, previous_page, _page[index], previous_row < 0 or previous_position != _positions[index] or previous_sequence != _sequence[index] or previous_frame != _frames[index] or previous_palette != _palette[index])
	else:
		if not _rows.has(row): _rows[row] = []
		_rows[row].append(index)
		rendered_count += 1
		if mechanism_enabled: _mechanism.changed_outputs += 1
	return true

func submit_sprite(index: int, ground: Vector2, sprite: Sprite2D) -> void:
	# Live captains and unadmitted atlas recipes stay on their original Sprite.
	# They split same-row batches at their original index, preserving overlap.
	var row := 10 + int(ground.y / TerrainRenderer.CELL_PIXELS)
	if _retained_mode and _page[index] < 0 and _index_row[index] == row \
			and _original_sprites.get(index) == sprite and sprite.get_parent() == self:
		return # The Sprite node owns its changing pixels/position; the batch row is unchanged.
	_groups_ready = false
	var previous_page := _page[index]
	var previous_sprite: Sprite2D = _original_sprites.get(index)
	_page[index] = -1
	_original_sprites[index] = sprite
	if _retained_mode:
		_positions[index] = Vector2.ZERO
		_sequence[index] = 0
		_frames[index] = 0
		_palette[index] = 0
		_grounds[index] = Vector2.ZERO
		_ground_ready[index] = 0
		_retain_assign(index, row, previous_page, -1, previous_sprite != sprite)
		if previous_sprite != sprite: _changed_rows[row] = true
	else:
		if not _rows.has(row): _rows[row] = []
		_rows[row].append(index)
	if mechanism_enabled: _mechanism.ground_projections += 1
	if sprite.get_parent() != self: sprite.reparent(self, false)

func sample_retained_animations(times: PackedFloat64Array, eligible: PackedByteArray = PackedByteArray()) -> int:
	if not _retained_mode or times.size() != _page.size() or (not eligible.is_empty() and eligible.size() != times.size()): return -1
	var changed := 0
	for index in range(times.size()):
		if not eligible.is_empty() and eligible[index] == 0: continue
		if _index_row[index] < 0 or _page[index] < 0: continue
		var sample_time := times[index]
		if not is_finite(sample_time) or sample_time < 0.0 or _ground_ready[index] == 0:
			_retained_ready = false
			return -1
		var page_index := _page[index]
		var sequence := _sequence[index]
		var page: Dictionary = _pages[page_index]
		var samples: Array = page.samples[sequence]
		if samples.is_empty():
			_retained_ready = false
			return -1
		if mechanism_enabled: _mechanism.animation_samples += 1
		var sample_key := Vector2i(page_index, sequence)
		if not _sampled_frames.has(sample_key): _sampled_frames[sample_key] = {}
		var cached: Dictionary = _sampled_frames[sample_key]
		var low := int(cached.get(sample_time, -1))
		if low < 0:
			var first: Dictionary = samples[0]
			var elapsed := fposmod(sample_time, float(first.duration)) if float(samples.back().sample_time) < float(first.duration) - 0.000001 else minf(sample_time, float(first.duration))
			low = 0
			var high := samples.size()
			while low + 1 < high:
				var middle := low + ((high - low) >> 1)
				if float(samples[middle].sample_time) <= elapsed + 0.000000001: low = middle
				else: high = middle
			cached[sample_time] = low
		if low == _frames[index]: continue
		var frame: Dictionary = samples[low]
		var anchor := Vector2(float(frame.anchor_offset.x), float(frame.anchor_offset.y)) * float(page.scale)
		var position := _grounds[index] - anchor
		_frames[index] = low
		_positions[index] = position
		_changed_runs[Vector2i(_index_row[index], _index_run[index])] = true
		if mechanism_enabled: _mechanism.changed_outputs += 1
		changed += 1
	return changed

func retained_source_duration(index: int) -> float:
	# Army supplies the original contact-clock duration on exact submit. An
	# atlas recipe may have a different duration, so its samples are not enough.
	if (not _retained_mode and not _retained_ready) or index < 0 or index >= _page.size() or _index_row[index] < 0 \
			or _page[index] < 0 or _ground_ready[index] == 0:
		return -1.0
	return _authored_durations[index]

func release_sprites() -> void:
	for sprite: Sprite2D in _army._sprites:
		if sprite != null and sprite.get_parent() == self: sprite.reparent(_army, false)

func flush() -> void:
	_retained_mode = false
	if retained_enabled:
		_row_spans.clear()
		_index_row.fill(-1)
		_index_run.fill(-1)
	_gpu_active_keys.clear()
	if _palette_dirty:
		_palette_texture.update(_palette_image)
		_palette_dirty = false
	for batch: MultiMeshInstance2D in _batches.values(): batch.visible = false
	if _groups_ready:
		for offset in range(0, _group_spans.size(), 5):
			var row := _group_spans[offset]
			var run := _group_spans[offset + 1]
			var start := _group_spans[offset + 2]
			var stop := _group_spans[offset + 3]
			var page_index := _group_spans[offset + 4]
			_flush_run(row, run, _rows[row], start, stop, page_index)
			if retained_enabled: _record_span(row, run, _rows[row], start, stop, page_index)
		if mechanism_enabled: _mechanism.row_rebuilds += _rows.size()
		_retain_active_gpu_keys()
		_finish_full_retained()
		return
	# Original fallback: sort by ordinal, split pages at every intervening Sprite.
	for row: int in _rows:
		var members: Array = _rows[row]
		members.sort()
		var start := 0
		var run := 0
		while start < members.size():
			var page_index := _page[int(members[start])]
			var stop := start + 1
			if page_index >= 0:
				while stop < members.size() and _page[int(members[stop])] == page_index: stop += 1
			_flush_run(row, run, members, start, stop, page_index)
			if retained_enabled: _record_span(row, run, members, start, stop, page_index)
			start = stop
			run += 1
	if mechanism_enabled: _mechanism.row_rebuilds += _rows.size()
	_retain_active_gpu_keys()
	_finish_full_retained()

func _record_span(row: int, run: int, members: Array, start: int, stop: int, page_index: int) -> void:
	if not _row_spans.has(row): _row_spans[row] = []
	var slice: Array = members.slice(start, stop)
	_row_spans[row].append({"page": page_index, "members": slice, "start": start, "stop": stop})
	for index: int in slice:
		_index_row[index] = row
		_index_run[index] = run
	if mechanism_enabled: _mechanism.run_rebuilds += 1

func _finish_full_retained() -> void:
	_retained_ready = false
	if not retained_enabled: return
	for index in range(_page.size()):
		if _index_row[index] < 0 or _page[index] < 0 or _ground_ready[index] != 0: continue
		if index >= _army.cells.size() or index >= _native_mask.size() or _native_mask[index] == 0: return
		_grounds[index] = (Vector2(_army.cells[index]) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
		_ground_ready[index] = 1
	_retained_ready = true
	_retained_gpu_mode = gpu_compute_enabled

func _row_runs(row: int) -> Array:
	var result := []
	if not _rows.has(row): return result
	var members: Array = _rows[row]
	members.sort()
	var start := 0
	while start < members.size():
		var page_index := _page[int(members[start])]
		var stop := start + 1
		if page_index >= 0:
			while stop < members.size() and _page[int(members[stop])] == page_index: stop += 1
		result.append({"page": page_index, "members": members.slice(start, stop), "start": start, "stop": stop})
		start = stop
	return result

func _place_span(row: int, run: int, span: Dictionary) -> void:
	if int(span.page) < 0:
		move_child(_original_sprites[int(span.members[0])], -1)
	else:
		move_child(_batches[Vector2i(row, run)], -1)

func flush_retained() -> void:
	if not _retained_mode: return
	if _palette_dirty:
		_palette_texture.update(_palette_image)
		_palette_dirty = false
	if _changed_rows.is_empty() and _changed_runs.is_empty():
		_retained_mode = false
		return
	for row: int in _changed_rows:
		var old: Array = _row_spans.get(row, [])
		var next := _row_runs(row)
		if mechanism_enabled:
			_mechanism.row_rebuilds += 1
			_mechanism.run_rebuilds += next.size()
		for run in range(next.size()):
			var span: Dictionary = next[run]
			var key := Vector2i(row, run)
			var same: bool = run < old.size() and int(old[run].page) == int(span.page) and old[run].members == span.members
			if not same or _changed_runs.has(key):
				_flush_run(row, run, _rows[row], int(span.start), int(span.stop), int(span.page), false)
				if int(span.page) < 0:
					var replaced: MultiMeshInstance2D = _batches.get(key)
					if replaced != null: replaced.visible = false
					_gpu_last_compact.erase(key)
					_gpu_primed.erase(key)
			for index: int in span.members:
				_index_row[index] = row
				_index_run[index] = run
		for run in range(next.size(), old.size()):
			var stale_key := Vector2i(row, run)
			var stale: MultiMeshInstance2D = _batches.get(stale_key)
			if stale != null: stale.visible = false
			_gpu_last_compact.erase(stale_key)
			_gpu_primed.erase(stale_key)
		if next.is_empty(): _row_spans.erase(row)
		else: _row_spans[row] = next
		for run in range(next.size()): _place_span(row, run, next[run])
	for key: Vector2i in _changed_runs:
		if _changed_rows.has(key.x): continue
		var spans: Array = _row_spans.get(key.x, [])
		if key.y < 0 or key.y >= spans.size(): continue
		var span: Dictionary = spans[key.y]
		if int(span.page) < 0: continue
		_flush_run(key.x, key.y, _rows[key.x], int(span.start), int(span.stop), int(span.page), false)
	if not _changed_rows.is_empty():
		active_batches = 0
		for row: int in _row_spans:
			for span: Dictionary in _row_spans[row]:
				if int(span.page) >= 0: active_batches += 1
	if not _changed_rows.is_empty() and _gpu_writer != null:
		_gpu_active_keys.clear()
		for row: int in _row_spans:
			for run in range(_row_spans[row].size()):
				var key := Vector2i(row, run)
				if int(_row_spans[row][run].page) >= 0 and _gpu_last_compact.has(key): _gpu_active_keys.append(key)
	_retain_active_gpu_keys()
	_retained_mode = false

func _retain_active_gpu_keys() -> void:
	if _gpu_writer == null or _gpu_active_keys == _gpu_retained_keys: return
	var active := {}
	for key: Vector2i in _gpu_active_keys: active[key] = true
	for key: Vector2i in _gpu_retained_keys:
		if not active.has(key): _gpu_last_compact.erase(key)
	_gpu_writer.retain_keys(_gpu_active_keys.duplicate())
	_gpu_retained_keys = _gpu_active_keys.duplicate()

func _flush_run(row: int, run: int, members: Array, start: int, stop: int, page_index: int, reorder: bool = true) -> void:
	if page_index < 0:
		if reorder: move_child(_original_sprites[int(members[start])], -1)
		return
	var key := Vector2i(row, run)
	var batch: MultiMeshInstance2D = _batches.get(key)
	if batch == null:
		batch = MultiMeshInstance2D.new()
		batch.name = "ArmyBatch_%d_%d" % [row, run]
		batch.z_as_relative = false
		batch.z_index = row
		batch.texture_filter = CharacterRenderContract.TEXTURE_FILTER
		batch.multimesh = MultiMesh.new()
		batch.multimesh.transform_format = MultiMesh.TRANSFORM_2D
		batch.multimesh.use_custom_data = true
		batch.multimesh.mesh = _mesh
		add_child(batch)
		_batches[key] = batch
	var page: Dictionary = _pages[page_index]
	if batch.texture != page.texture:
		batch.texture = page.texture
		if mechanism_enabled: _mechanism.multimesh_setters += 1
	if batch.material != page.material:
		batch.material = page.material
		if mechanism_enabled: _mechanism.multimesh_setters += 1
	if batch.multimesh.instance_count != stop - start:
		batch.multimesh.instance_count = stop - start
		if mechanism_enabled: _mechanism.multimesh_setters += 1
		_gpu_primed.erase(key)
		_gpu_last_compact.erase(key)
	var count := stop - start
	var gpu_ready := gpu_compute_enabled and RenderingServer.get_rendering_device() != null
	if gpu_ready and _gpu_writer == null:
		_gpu_writer = GpuBufferWriter.new()
		_gpu_writer.start(_on_gpu_writer_failed)
	var primed: bool = _gpu_primed.get(key, -1) == count
	var use_gpu: bool = gpu_ready and primed and _gpu_writer.ready()
	var bounds: Rect2
	if use_gpu:
		if not _gpu_active_keys.has(key): _gpu_active_keys.append(key)
		bounds = Rect2(_positions[int(members[start])], Vector2.ZERO)
		var compact := PackedFloat32Array()
		compact.resize(count * 5)
		for local_index in count:
			var index := int(members[start + local_index])
			var at := local_index * 5
			compact[at] = _positions[index].x
			compact[at + 1] = _positions[index].y
			compact[at + 2] = float(_sequence[index])
			compact[at + 3] = float(_frames[index])
			compact[at + 4] = float(_palette[index])
			bounds = bounds.expand(_positions[index])
		var previous: Array = _gpu_last_compact.get(key, [])
		if previous.is_empty() or previous[0] != compact or float(previous[1]) != float(page.scale):
			_gpu_writer.write(key, batch.multimesh.get_rid(), compact, count, float(page.scale))
			if mechanism_enabled:
				_mechanism.gpu_dispatches += 1
				_mechanism.packed_instances += count
				_mechanism.packed_bytes += compact.size() * 4
			_gpu_last_compact[key] = [compact, float(page.scale)]
	else:
		var packet := _pack_run(members, start, stop, float(page.scale))
		batch.multimesh.buffer = packet[0]
		if mechanism_enabled:
			_mechanism.multimesh_setters += 1
			var submitted: PackedFloat32Array = packet[0]
			_mechanism.multimesh_bytes += submitted.size() * 4
		_gpu_last_compact.erase(key)
		bounds = packet[1]
		if gpu_compute_enabled:
			if not gpu_ready or not gpu_last_error.is_empty(): gpu_fallback_count += 1
			else: gpu_prime_count += 1
		_gpu_primed[key] = count
	bounds = bounds.grow(float(page.margin))
	var next_aabb := AABB(Vector3(bounds.position.x, bounds.position.y, -1.0), Vector3(bounds.size.x, bounds.size.y, 2.0))
	if batch.multimesh.custom_aabb != next_aabb:
		batch.multimesh.custom_aabb = next_aabb
		if mechanism_enabled: _mechanism.multimesh_setters += 1
	if not batch.visible:
		batch.visible = true
		if mechanism_enabled: _mechanism.multimesh_setters += 1
	if reorder: move_child(batch, -1)
	if reorder: active_batches += 1

func _pack_run(members: Array, start: int, stop: int, map_scale: float) -> Array:
	if native_buffer_enabled and PackedVector2Array([Vector2.ZERO]).to_byte_array().size() == 8:
		var kernel: RefCounted = TerrainArmy._get_idle_kernel()
		if kernel != null and kernel.has_method("pack_instances"):
			var packet: Array = kernel.call("pack_instances", members, start, stop, _positions, _sequence, _frames, _palette, map_scale)
			if packet.size() == 2:
				native_buffer_instances += stop - start
				if mechanism_enabled:
					_mechanism.packed_instances += stop - start
					var native_buffer: PackedFloat32Array = packet[0]
					_mechanism.packed_bytes += native_buffer.size() * 4
				return [packet[0], Rect2(packet[1][0], packet[1][1])]
	var gd_packet := _pack_run_gd(members, start, stop, map_scale)
	if mechanism_enabled:
		_mechanism.packed_instances += stop - start
		var gd_buffer: PackedFloat32Array = gd_packet[0]
		_mechanism.packed_bytes += gd_buffer.size() * 4
	return gd_packet

func _pack_run_gd(members: Array, start: int, stop: int, map_scale: float) -> Array:
	var buffer := PackedFloat32Array()
	buffer.resize((stop - start) * 12)
	var bounds := Rect2(_positions[int(members[start])], Vector2.ZERO)
	for local_index in range(stop - start):
		var index := int(members[start + local_index])
		var offset := local_index * 12
		buffer[offset] = map_scale
		buffer[offset + 3] = _positions[index].x
		buffer[offset + 5] = map_scale
		buffer[offset + 7] = _positions[index].y
		buffer[offset + 8] = float(_sequence[index])
		buffer[offset + 9] = float(_frames[index])
		buffer[offset + 10] = float(_palette[index])
		bounds = bounds.expand(_positions[index])
	return [buffer, bounds]

static func _deep_read_only(value: Variant) -> bool:
	if value is Dictionary:
		if not value.is_read_only(): return false
		for key: Variant in value:
			if not _deep_read_only(key) or not _deep_read_only(value[key]): return false
	elif value is Array:
		if not value.is_read_only(): return false
		for child: Variant in value:
			if not _deep_read_only(child): return false
	return not value is Object

func _describe(appearance: Dictionary) -> Dictionary:
	if not appearance.is_empty() and not HumanCharacter3DEditor.valid_appearance(appearance): return {}
	var geometry := DyeAtlas.Dye.geometry_appearance(appearance)
	var base: Dictionary = _army._combat_bake.manifest
	if appearance.is_empty(): geometry = base.appearance
	var wagon_foot := Atlas.wagon_foot_recipe(appearance)
	var record := Atlas.dye_entry(geometry) if wagon_foot.is_empty() else {}
	if record.is_empty() and wagon_foot.is_empty(): return {}
	var key := str(record.source_manifest if wagon_foot.is_empty() else wagon_foot.source_manifest)
	if not _page_keys.has(key):
		var sequences := {}
		var texture: Texture2D
		if geometry == base.appearance:
			texture = _army._soldier_atlas
			for clip: String in _army._combat_bake.contact_clocks:
				for direction: String in _army._combat_bake.contact_clocks[clip]:
					sequences[clip + "|" + direction] = _army._combat_bake.contact_clocks[clip][direction][3]
		else:
			var recipe := wagon_foot
			if recipe.is_empty(): recipe = Atlas.mixed_recipe(geometry)
			if recipe.is_empty(): recipe = Atlas.female_recipe(geometry) if geometry.body == 1 else Atlas.RangedAtlas.recipe(geometry)
			if recipe.is_empty(): return {}
			sequences = recipe.sequences
			# A future multi-page publication stays on the original page-aware
			# Sprite path until this batch reader explicitly supports that layout.
			var first_page: Dictionary = sequences.values()[0][0]._page
			for frames: Array in sequences.values():
				for frame: Dictionary in frames:
					if frame._page != first_page: return {}
			texture = Atlas._page(sequences.values()[0][0]._page)
		if texture == null or sequences.is_empty(): return {}
		var mask: Image
		if not wagon_foot.is_empty():
			# The two fixed, undyed cloth recipes need no new dye publication.
			mask = Image.create(1, 1, false, Image.FORMAT_RGB8)
			mask.fill(Color.BLACK)
		else:
			var mask_path := str(record.mask_path)
			if ResourceLoader.exists(mask_path):
				var res := ResourceLoader.load(mask_path)
				if res is Texture2D:
					mask = (res as Texture2D).get_image()
				elif res is Image:
					mask = res as Image
			if mask == null:
				mask = Image.load_from_file(mask_path)
			if mask == null or mask.get_width() != int(record.width) or mask.get_height() != int(record.height) or mask.get_width() != texture.get_width() or mask.get_height() != texture.get_height(): return {}
			mask.convert(Image.FORMAT_RGB8)
		var metadata := Image.create(129, sequences.size(), false, Image.FORMAT_RGBAF)
		var pixel_size := Vector2(1.0 / texture.get_width(), 1.0 / texture.get_height())
		var lookup := {}
		var sequence_index := 0
		var margin := 1.0
		for sequence_key: String in sequences:
			var frames: Array = sequences[sequence_key]
			if frames.is_empty() or frames.size() > 64: return {}
			var first: Dictionary = frames[0]
			var loop := float(frames.back().sample_time) < float(first.duration) - 0.000001
			metadata.set_pixel(0, sequence_index, Color(float(frames.size()), float(first.duration), float(loop), float(base.map_scale)))
			for frame_index in range(frames.size()):
				var frame: Dictionary = frames[frame_index]
				metadata.set_pixel(1 + frame_index * 2, sequence_index, Color(float(frame.rect.x), float(frame.rect.y), float(frame.rect.w), float(frame.rect.h)))
				# Match Canvas RD's CPU float32 reciprocal-then-multiply. GPU
				# division can land on the adjacent texel of non-power-of-two pages.
				# This texel was unused by the shader; anchors/clocks stay CPU-owned.
				var source_position := Vector2(frame.rect.x, frame.rect.y) * pixel_size
				var source_size := Vector2(frame.rect.w, frame.rect.h) * pixel_size
				metadata.set_pixel(2 + frame_index * 2, sequence_index, Color(source_position.x, source_position.y, source_size.x, source_size.y))
				margin = maxf(margin, (maxf(float(frame.rect.w), float(frame.rect.h)) + absf(float(frame.anchor_offset.x)) + absf(float(frame.anchor_offset.y))) * float(base.map_scale))
			lookup[sequence_key] = sequence_index
			sequence_index += 1
		var page_material := ShaderMaterial.new()
		page_material.shader = _shader
		page_material.set_shader_parameter("sequence_data", ImageTexture.create_from_image(metadata))
		page_material.set_shader_parameter("palette_data", _palette_texture)
		page_material.set_shader_parameter("dye_map", ImageTexture.create_from_image(mask))
		_page_keys[key] = _pages.size()
		_pages.append({"texture": texture, "material": page_material, "sequences": lookup, "samples": sequences.values(), "scale": float(base.map_scale), "margin": margin})
		var native_samples: Array = []
		for clip: String in ["combat_idle", "unconscious"]:
			for direction: String in ["up", "right", "down", "left"]:
				var sample_key := clip + "|" + direction
				if not lookup.has(sample_key):
					native_samples.append([])
					continue
				var frames: Array = sequences[sample_key]
				var times := PackedFloat64Array()
				var anchors := PackedVector2Array()
				for frame: Dictionary in frames:
					times.append(float(frame.sample_time))
					anchors.append(Vector2(float(frame.anchor_offset.x), float(frame.anchor_offset.y)) * float(base.map_scale))
				native_samples.append([int(lookup[sample_key]), float(frames[0].duration),
					float(frames.back().sample_time) < float(frames[0].duration) - 0.000001, times, anchors])
		_idle_samples.append(native_samples.slice(0, 4))
		_idle_and_unconscious_samples.append(native_samples)
	var colors: Dictionary = appearance.get("equipment_dyes", {})
	var palette_key := str(colors)
	if not _palette_keys.has(palette_key):
		var palette_index := _palette_keys.size()
		if palette_index >= _palette_image.get_height(): return {} # Safe original fallback after many live recolourings.
		for slot_index in range(DyeAtlas.Dye.SLOTS.size()):
			var slot: String = DyeAtlas.Dye.SLOTS[slot_index]
			var color := DyeAtlas.canvas_color(str(colors[slot])) if colors.has(slot) else Vector4.ZERO
			_palette_image.set_pixel(slot_index, palette_index, Color(color.x, color.y, color.z, color.w))
		_palette_keys[palette_key] = palette_index
		_palette_dirty = true
	return {"page": int(_page_keys[key]), "palette": int(_palette_keys[palette_key])}
