extends RefCounted
## 示範劇本 builder: authored Site states built on the Taiwan natural source without the map editor's window. Each Site is
## a work record in the editor's own format 4 ({format, site, terrain_static, initial_state, resource_highwater,
## feature_highwater, revision}); prepare() runs the editor's own preparation steps (map_editor.gd _prepare_work: the author
## draft, the captured empty state, the resource state, the building check, the resident check) without its preview-site
## gate, and place() places one building through SiteRuntime.prepare_author_building as the editor's edit_building does.
## A builder places a building only where SiteRuntime.building_cells admits it, after giving its footprint full foundation.
const Data = preload("res://scripts/region_lab/region_data.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const ResidentRoster = preload("res://scripts/terrain_lab/site_resident_roster.gd")
const SIDE := 100

static func empty_static() -> Dictionary:
	return {"format": 2, "terrain": {}, "resources": {}, "water_bodies": {}, "water_permissions": {"cells": [], "bodies": []}}

## A work record as the editor's draft (map_editor.gd new_work), raised to format 4.
static func new_work(source: RegionData, site: Vector2i) -> Dictionary:
	return {"format": 4, "kind": "fixed_tw_editor_draft", "name": "示範劇本", "manifest": Data.DEFAULT_MANIFEST, "source_sha256": source.manifest_hash,
		"site": [site.x, site.y], "terrain_static": empty_static(), "initial_state": {}, "resource_highwater": 0, "feature_highwater": 0, "revision": 1}

## The editor's _prepare_work steps. {ok, draft, terrain} or {ok false, stage}.
static func prepare(source: RegionData, work: Dictionary) -> Dictionary:
	var site := Vector2i(int(work.site[0]), int(work.site[1]))
	var result: Dictionary = source.make_author_draft(site, work.terrain_static, int(work.revision))
	if not bool(result.get("ok", false)) or not result.get("data") is TerrainData: return {"ok": false, "stage": "draft " + str(result.get("code", ""))}
	var candidate: TerrainData = result.data
	if not candidate.site.is_empty(): return {"ok": false, "stage": "draft not empty"}
	var value: Dictionary = work.duplicate(true)
	value.terrain_static = Data.author_static_normalized(value.terrain_static)
	var state: Dictionary = value.initial_state
	if state.is_empty():
		Env.initialize(candidate, str(result.base.site_id))
		if candidate.site.is_empty(): return {"ok": false, "stage": "initialize"}
		candidate.site.world_pin = Data.author_projection_pin(result.base)
		var captured: Dictionary = SiteStore.save(candidate, "", null, false, {}, true)
		candidate.site.erase("world_pin")
		if not bool(captured.get("ok", false)): return {"ok": false, "stage": "capture " + str(captured.get("code", ""))}
		state = captured.state
		state.erase("world_pin")
	if state.get("id") != str(result.base.site_id): return {"ok": false, "stage": "site id"}
	state.next_feature = maxi(int(state.get("next_feature", 1)), int(value.feature_highwater) + 1)
	var prepared: Dictionary = Env.prepare_author_resource_state(candidate, state)
	if not bool(prepared.get("ok", false)): return {"ok": false, "stage": "resources " + str(prepared.get("code", ""))}
	candidate = prepared.data
	value.initial_state = prepared.state
	var buildings: Dictionary = SiteRuntime.validate_author_buildings(candidate)
	if not buildings.ok: return {"ok": false, "stage": "buildings " + str(buildings.get("code", ""))}
	var residents: Dictionary = ResidentRoster.draft_refusal(candidate, value.initial_state)
	if not residents.ok: return {"ok": false, "stage": "residents " + str(residents.get("code", ""))}
	return {"ok": true, "draft": value, "terrain": candidate}

## The authored land row `land` (default: full foundation) under `rect` (a building's footprint) in the work's static
## layer (RegionData.AUTHOR_LAND_FIELDS: a well also needs groundwater).
static func foundation(work: Dictionary, rect: Rect2i, land: Dictionary = {"foundation": 100}) -> void:
	for y: int in range(maxi(0, rect.position.y), mini(SIDE, rect.end.y)):
		for x: int in range(maxi(0, rect.position.x), mini(SIDE, rect.end.x)):
			work.terrain_static.terrain[str(y * SIDE + x)] = land.duplicate()

## Places one building of `kind` at the first admitted origin of `origins` (each tried with `footprint` given full
## foundation first). {ok, feature, origin} with `work` updated, or {ok false, stage}; `work` is unchanged on a refusal.
static func place(source: RegionData, work: Dictionary, kind: String, origins: Array, footprint: Vector2i, size: Vector2i, options: Dictionary, land: Dictionary = {"foundation": 100}) -> Dictionary:
	var last := ""
	for origin: Vector2i in origins:
		var trial: Dictionary = work.duplicate(true)
		foundation(trial, Rect2i(origin, footprint), land)
		trial.revision = int(trial.revision) + 1
		var prepared := prepare(source, trial)
		if not prepared.ok:
			last = str(prepared.stage)
			continue
		var layout: Dictionary = SiteRuntime.building_cells(prepared.terrain, kind, origin, size, options)
		if not layout.ok:
			last = "layout " + str(layout.get("code", ""))
			continue
		var cells: Array[int] = []
		cells.assign(layout.cells)
		var placed: Dictionary = SiteRuntime.prepare_author_building(prepared.terrain, prepared.draft, "place", "", kind, cells, options, {})
		if not placed.ok:
			last = "place " + str(placed.get("code", ""))
			continue
		work.terrain_static = prepared.draft.terrain_static
		work.initial_state = placed.state
		work.feature_highwater = maxi(int(work.feature_highwater), int(placed.state.get("next_feature", 1)) - 1)
		work.revision = int(trial.revision)
		return {"ok": true, "feature": str(placed.feature), "origin": origin}
	return {"ok": false, "stage": kind + ": " + last}

## Origins in a square spiral from `center`, `step` cells apart, inside the Site with `margin` cells to spare.
static func spiral(center: Vector2i, step: int, rings: int, margin: int = 6) -> Array:
	var result: Array = [center]
	for ring: int in range(1, rings + 1):
		for dy: int in range(-ring, ring + 1):
			for dx: int in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring: continue
				var origin := center + Vector2i(dx, dy) * step
				if origin.x >= margin and origin.y >= margin and origin.x < SIDE - margin and origin.y < SIDE - margin: result.append(origin)
	return result

## The authored state of a work, ready for export: the residents set, the birth-only fields removed.
static func export_state(work: Dictionary, residents: Array) -> Dictionary:
	var state: Dictionary = work.initial_state.duplicate(true)
	if not residents.is_empty(): state["residents"] = residents.duplicate(true)
	for field: String in ["world_pin", "fire_settlement", "region_snapshot", "initial_scenario", "crowd"]: state.erase(field)
	if not state.has("terrain_changes"): state["terrain_changes"] = {}
	return state
