class_name RegionData
extends RefCounted

const Grid = preload("res://scripts/region_lab/region_grid.gd")
const Adapter = preload("res://scripts/region_lab/region_terrain_adapter.gd")
const DEFAULT_MANIFEST := "res://assets/region_lab/earth_tw_tm2_121_v1_r4/manifest.json"
const RESOURCE_MANIFEST := "res://assets/region_lab/earth_tw_resources_v1/manifest.json"
const RESOURCE_GEOGRAPHY_SHA := "e3108aad1cbfd5118af08fd699ac03bf64d19b5bc9d186154dc9a5fea279f7b8"
const RESOURCE_TILE_BYTES := 1000000
const MAX_SUMMARY_BYTES := 16 * 1024 * 1024
const MAX_CACHE_BYTES := 64 * 1024 * 1024
const MAX_CACHE_TILES := 9
const FINE_MASK_BYTES := 100 * 100 * 4
const MAX_FINE_MASKS := 9
const CLASS_NAMES := ["missing_data", "sea", "land", "inland_water", "mixed"]

var manifest: Dictionary = {}
var manifest_hash := ""
var resource_manifest_hash := ""
var resource_rule_revision := ""
var _resource_manifest: Dictionary = {}
var _resource_region := ""
var _resource_cover := PackedByteArray() # One 20 km region, within the existing source-cache budget.
var _folder := ""
var _summary := PackedByteArray()
var _content_scope := PackedByteArray()
var _source_quality := PackedByteArray()
var _water_bodies: Dictionary = {}
var _water_body_kinds := PackedByteArray()
var _water_body_sources := PackedStringArray()
var _water_body_names := PackedStringArray()
var _fine_masks: Dictionary = {}
var _fine_lru: Array[Vector2i] = []
var _sample_spacing_m := 0
var _tiles: Dictionary = {}
var _tile_index: Dictionary = {}
var _lru: Array[String] = []
var _cache_bytes := 0
var peak_cache_bytes := 0
var _author_pin: Dictionary = {}
var _author_document: Dictionary = {}
## 示範劇本 (reports: 示範劇本 A 開墾之地): the package's scenario document, {} when it has none (author_scenario_valid).
var _author_scenario: Dictionary = {}

const AUTHOR_MANIFEST_BYTES := 256 * 1024
## 示範劇本 A (46 Sites, an initial and a static file each, plus the scenario): raised from 64.
const AUTHOR_MAX_FILES := 128
const AUTHOR_FILE_BYTES := 32 * 1024 * 1024
const AUTHOR_PACKAGE_BYTES := 64 * 1024 * 1024
const AUTHOR_DEPENDENCY_BYTES := 64 * 1024 * 1024
const AUTHOR_DEPENDENCIES_BYTES := 512 * 1024 * 1024

func author_identity() -> Dictionary:
	return _author_pin.duplicate(true)

func author_identity_matches(value: Variant) -> bool:
	return Adapter.same_author_identity(_author_pin, value)

func author_document() -> Dictionary:
	return _author_document.duplicate(true)

func author_scenario() -> Dictionary:
	return _author_scenario.duplicate(true)

## 示範劇本: one optional "scenario" file per package (kind "scenario", site = the start Site):
##   {format: 1, factions: [faction], teams?: [team]} with at most MAX_SCENARIO_FACTIONS factions (ids unique) and at
##   most MAX_SCENARIO_TEAMS teams;
##   team (step 2): {site: [x, y], faction_id (a scenario faction), cell: [x, y] (where it stands), members: [{name,
##     role "officer" | "soldier"}] (1..MAX_TEAM_MEMBERS, the first an officer: the captain)}; a bandit faction's
##     first team captain is its chief;
##   offices? (step 3): [{site: [x, y], head: resident name, duties: {duty_id: resident name}}], one per Site: the
##     settlement's head seat and the seats of those duties take those residents of that Site; a head is his faction's leader;
##   stock? (step 3): [{site: [x, y], feature: feature key, items: {resource: 1..1000000}}]: a warehouse's opening stock;
##   faction: {id (1..MAX_ID, never the neutral 255), name (1–32 characters), kind "npc" | "bandit",
##     bandit (only for kind bandit): {lair: {site: [x, y], cell: [x, y]}, heat 0..100, raid_ai bool, hoard {item: 1..100000000}}}.
## The ids are the faction ids the package's Sites use (settlement owner_faction, residents' faction_id); a new world
## names and types those factions after its birth (SiteController.apply_scenario_factions).
const MAX_SCENARIO_FACTIONS := 32 # 示範劇本 A: 15 village factions and 15 bands
const MAX_SCENARIO_TEAMS := 64 # 30 militia teams and the bands' teams
const MAX_TEAM_MEMBERS := 20
const MAX_SCENARIO_OFFICES := 64 # one per settlement Site
static func author_scenario_valid(document: Variant) -> bool:
	if not document is Dictionary or not Adapter.author_integer(document.get("format"), 1, 1) or not document.get("factions") is Array: return false
	for key: Variant in document:
		if not str(key) in ["format", "factions", "teams", "offices", "stock", "livelihood"]: return false
	if not _scenario_offices_valid(document.get("offices", [])) or not _scenario_stock_valid(document.get("stock", [])) or not _scenario_livelihood_valid(document.get("livelihood", [])): return false
	if document.factions.size() > MAX_SCENARIO_FACTIONS: return false
	var ids := {}
	for faction: Variant in document.factions:
		if not faction is Dictionary or not Adapter.author_integer(faction.get("id"), 1, RegionFactionQuery.MAX_ID) or int(faction.id) == RegionFactionQuery.NEUTRAL_FACTION_ID: return false
		if ids.has(int(faction.id)): return false
		ids[int(faction.id)] = true
		if not _author_text_valid(faction.get("name"), 32, true) or faction.get("kind") not in ["npc", "bandit"]: return false
		var allowed := ["id", "name", "kind"] + (["bandit"] if faction.kind == "bandit" else [])
		for key: Variant in faction:
			if not str(key) in allowed: return false
		if faction.kind != "bandit": continue
		var band: Variant = faction.get("bandit")
		if not band is Dictionary or not band.get("lair") is Dictionary or not Adapter.author_pair_valid(band.lair.get("site"), -10000000, 10000000) \
			or not Adapter.author_pair_valid(band.lair.get("cell"), 0, Adapter.SIDE - 1) or band.lair.size() != 2: return false
		if not Adapter.author_integer(band.get("heat"), 0, 100) or not band.get("raid_ai") is bool or not band.get("hoard") is Dictionary or band.hoard.size() > 64: return false
		for key: Variant in band:
			if not str(key) in ["lair", "heat", "raid_ai", "hoard"]: return false
		for item: Variant in band.hoard:
			if not item is String or str(item).is_empty() or not Adapter.author_integer(band.hoard[item], 1, 100000000): return false
	if not document.has("teams"):
		return not _scenario_bandits(document).values().has(false)
	if not document.teams is Array or document.teams.size() > MAX_SCENARIO_TEAMS: return false
	for team: Variant in document.teams:
		if not team is Dictionary or team.size() != 4 or not Adapter.author_pair_valid(team.get("site"), -10000000, 10000000) or not Adapter.author_pair_valid(team.get("cell"), 0, Adapter.SIDE - 1): return false
		if not Adapter.author_integer(team.get("faction_id"), 1, RegionFactionQuery.MAX_ID) or not ids.has(int(team.faction_id)): return false
		if not team.get("members") is Array or team.members.is_empty() or team.members.size() > MAX_TEAM_MEMBERS: return false
		for at: int in range(team.members.size()):
			var member: Variant = team.members[at]
			if not member is Dictionary or member.size() != 2 or not _author_text_valid(member.get("name"), 16, true) or member.get("role") not in ["officer", "soldier"]: return false
			if at == 0 and member.role != "officer": return false
	return not _scenario_bandits(document).values().has(false)

static func _scenario_offices_valid(rows: Variant) -> bool:
	if not rows is Array or rows.size() > MAX_SCENARIO_OFFICES: return false
	var sites := {}
	for row: Variant in rows:
		if not row is Dictionary or row.size() != 3 or not Adapter.author_pair_valid(row.get("site"), -10000000, 10000000) or not _author_text_valid(row.get("head"), 16, true) or not row.get("duties") is Dictionary: return false
		var key := "%d:%d" % [int(row.site[0]), int(row.site[1])]
		if sites.has(key) or row.duties.size() > 16: return false
		sites[key] = true
		for duty: Variant in row.duties:
			if not duty is String or not SiteOffices.duty_ids("settlement").has(str(duty)) or not _author_text_valid(row.duties[duty], 16, true): return false
	return true

static func _scenario_stock_valid(rows: Variant) -> bool:
	if not rows is Array or rows.size() > 64: return false
	for row: Variant in rows:
		if not row is Dictionary or row.size() != 3 or not Adapter.author_pair_valid(row.get("site"), -10000000, 10000000) or not _author_text_valid(row.get("feature"), 64, true) or not row.get("items") is Dictionary: return false
		if row.items.is_empty() or row.items.size() > 32: return false
		for item: Variant in row.items:
			if not item is String or str(item).is_empty() or not Adapter.author_integer(row.items[item], 1, 1000000): return false
	return true

## 居民吃飯 L1: the settlements whose people are fed and farm: {site, farms [feature key], camp {item: n}}, one row a Site.
static func _scenario_livelihood_valid(rows: Variant) -> bool:
	if not rows is Array or rows.size() > MAX_SCENARIO_OFFICES: return false
	var sites := {}
	for row: Variant in rows:
		if not row is Dictionary or row.size() != 3 or not Adapter.author_pair_valid(row.get("site"), -10000000, 10000000) or not row.get("farms") is Array or not row.get("camp") is Dictionary: return false
		var key := "%d:%d" % [int(row.site[0]), int(row.site[1])]
		if sites.has(key) or row.farms.size() > 16 or row.camp.size() > 16: return false
		sites[key] = true
		for farm: Variant in row.farms:
			if not _author_text_valid(farm, 64, true): return false
		for item: Variant in row.camp:
			if not item is String or str(item).is_empty() or not Adapter.author_integer(row.camp[item], 1, 1000000): return false
	return true

## Every bandit faction of a scenario: {id: has a team (its chief)}.
static func _scenario_bandits(document: Dictionary) -> Dictionary:
	var result := {}
	for faction: Dictionary in document.get("factions", []):
		if faction.get("kind") == "bandit": result[int(faction.id)] = false
	for team: Variant in document.get("teams", []):
		if team is Dictionary and result.has(int(team.get("faction_id", 0))): result[int(team.faction_id)] = true
	return result

static func _author_path_valid(path: Variant) -> bool:
	if not path is String or path.is_empty() or path.length() > 512 or path.is_absolute_path() or path.contains(":") or path.contains("\\"): return false
	for part: String in path.split("/"):
		if part in ["", ".", ".."] or not part.is_valid_filename() or part != part.strip_edges() or part.ends_with("."): return false
	return true

static func _author_dependency_path_valid(path: Variant) -> bool:
	return path is String and (path.begins_with("res://") or path.begins_with("user://")) and _author_path_valid(path.substr(path.find("://") + 3))

static func _author_file_shape(raw: Variant, limit: int) -> bool:
	return raw is Dictionary and raw.get("path") is String and Adapter.author_digest_valid(raw.get("sha256")) and Adapter.author_integer(raw.get("bytes"), 1, limit)

static func _author_text_valid(value: Variant, limit: int, name: bool = false) -> bool:
	if not value is String or value.length() > limit: return false
	if name and (value.is_empty() or value != value.strip_edges()): return false
	for i: int in range(value.length()):
		var code: int = value.unicode_at(i)
		if code < 32 and (name or code not in [9, 10, 13]): return false
		if code == 127: return false
	return true

static func _author_manifest_shape(raw: Variant) -> bool:
	const KEYS := ["format", "source_kind", "scenario_id", "revision", "name", "description", "atlas_id", "grid_contract_version", "natural_source", "dependencies", "files", "start", "package_digest"]
	if not raw is Dictionary or raw.size() != KEYS.size(): return false
	for key: String in KEYS:
		if not raw.has(key): return false
	if not Adapter.author_integer(raw.format, 1, 1) or raw.source_kind != "fixed_tw_author" or raw.atlas_id != Grid.ATLAS_ID or not Adapter.author_integer(raw.grid_contract_version, Grid.CONTRACT_VERSION, Grid.CONTRACT_VERSION): return false
	if not Adapter.author_id_valid(raw.scenario_id) or not Adapter.author_integer(raw.revision, 1, 2147483647) or not Adapter.author_digest_valid(raw.package_digest) or not Adapter.author_start_valid(raw.start): return false
	if not _author_text_valid(raw.name, 64, true) or not _author_text_valid(raw.description, 4096): return false
	if not Adapter.author_id_valid(raw.natural_source) or not raw.dependencies is Array or raw.dependencies.is_empty() or raw.dependencies.size() > 32 or not raw.files is Array or raw.files.size() > AUTHOR_MAX_FILES: return false
	var ids := {}
	var paths := {}
	var total := 0
	for entry: Variant in raw.dependencies:
		if not _author_file_shape(entry, AUTHOR_DEPENDENCY_BYTES) or entry.size() != 4 or not Adapter.author_id_valid(entry.get("id")) or not _author_dependency_path_valid(entry.path): return false
		if ids.has(entry.id) or paths.has(str(entry.path).to_lower()): return false
		ids[entry.id] = true; paths[str(entry.path).to_lower()] = true
		total += int(entry.bytes)
	if not ids.has(raw.natural_source) or total > AUTHOR_DEPENDENCIES_BYTES: return false
	paths.clear()
	var roles := {}
	total = 0
	for entry: Variant in raw.files:
		if not _author_file_shape(entry, AUTHOR_FILE_BYTES) or entry.size() != 5 or entry.get("kind") not in ["static", "initial", "scenario"] or not _author_path_valid(entry.path) or not Adapter.author_pair_valid(entry.get("site"), -10000000, 10000000): return false
		var role := "%s:%d:%d" % [entry.kind, int(entry.site[0]), int(entry.site[1])]
		if paths.has(str(entry.path).to_lower()) or roles.has(role): return false
		paths[str(entry.path).to_lower()] = true; roles[role] = true
		total += int(entry.bytes)
	return total <= AUTHOR_PACKAGE_BYTES

static func author_package_digest(raw: Variant) -> String:
	if not _author_manifest_shape(raw): return ""
	var payload: Dictionary = raw.duplicate(true)
	payload.erase("package_digest")
	payload.format = int(payload.format); payload.revision = int(payload.revision)
	payload.grid_contract_version = int(payload.grid_contract_version)
	for entry: Dictionary in payload.dependencies: entry.bytes = int(entry.bytes)
	for entry: Dictionary in payload.files:
		entry.bytes = int(entry.bytes)
		entry.site = [int(entry.site[0]), int(entry.site[1])]
	payload.start.site = [int(payload.start.site[0]), int(payload.start.site[1])]
	payload.start.cell = [int(payload.start.cell[0]), int(payload.start.cell[1])]
	if payload.start.has("person_id"): payload.start.person_id = int(payload.start.person_id)
	return JSON.stringify(payload, "", true, true).sha256_text()

static func _author_no_links(folder: String, relative: String) -> bool:
	var directory := DirAccess.open(folder)
	if directory == null: return false
	var parts := relative.split("/")
	for i: int in range(parts.size()):
		if directory.is_link(parts[i]): return false
		if i + 1 < parts.size() and directory.change_dir(parts[i]) != OK: return false
	return true

static func _read_author_file(path: String, record: Dictionary, limit: int) -> Dictionary:
	var root := path.get_base_dir()
	var relative := path.get_file()
	if path.begins_with("res://") or path.begins_with("user://"):
		var split := path.find("://") + 3
		root = path.substr(0, split); relative = path.substr(split)
	if not _author_no_links(root, relative): return fail("AUTHOR_UNSAFE_PATH", path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return fail("MISSING_AUTHOR_DEPENDENCY", path)
	var size := file.get_length()
	if size > limit or size != int(record.bytes): return fail("AUTHOR_FILE_SIZE", path)
	var bytes := file.get_buffer(size)
	file.close()
	if bytes.size() != size: return fail("AUTHOR_FILE_SIZE", path)
	var pointer := "version https://git-lfs.github.com/spec/v1".to_utf8_buffer()
	if bytes.slice(0, pointer.size()) == pointer: return fail("AUTHOR_LFS_POINTER", path)
	var hash := HashingContext.new()
	var started := hash.start(HashingContext.HASH_SHA256)
	if started != OK: return fail("AUTHOR_HASH_ERROR", path)
	hash.update(bytes)
	if hash.finish().hex_encode() != record.sha256: return fail("AUTHOR_HASH_MISMATCH", path)
	return {"ok": true, "bytes": bytes}

func load_author_package(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return fail("MISSING_AUTHOR_PACKAGE", path)
	if file.get_length() > AUTHOR_MANIFEST_BYTES: return fail("AUTHOR_MANIFEST_SIZE", path)
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not _author_manifest_shape(parsed): return fail("INVALID_AUTHOR_PACKAGE", "作者格式／路徑／尺寸非法")
	if author_package_digest(parsed) != parsed.package_digest: return fail("AUTHOR_HASH_MISMATCH", "作者包摘要不同")
	var natural: Dictionary = {}
	var records: Array[Dictionary] = []
	for entry: Dictionary in parsed.dependencies:
		var checked := _read_author_file(str(entry.path), entry, AUTHOR_DEPENDENCY_BYTES)
		if not checked.ok: return checked
		if entry.id == parsed.natural_source: natural = entry
	for entry: Dictionary in parsed.files:
		if not _author_no_links(path.get_base_dir(), str(entry.path)): return fail("AUTHOR_UNSAFE_PATH", str(entry.path))
		var checked := _read_author_file(path.get_base_dir().path_join(str(entry.path)), entry, AUTHOR_FILE_BYTES)
		if not checked.ok: return checked
		var content: Variant = JSON.parse_string(checked.bytes.get_string_from_utf8())
		if not content is Dictionary: return fail("INVALID_AUTHOR_FILE", str(entry.path))
		records.append({"entry": entry, "content": content})
	var candidate := RegionData.new()
	var natural_document: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(natural.path)))
	if not natural_document is Dictionary or natural_document.get("source_kind") == "fixed_tw_author": return fail("INVALID_AUTHOR_DEPENDENCY", "作者依賴必須是自然來源")
	var loaded := candidate.load_manifest(str(natural.path))
	if not loaded.ok: return loaded
	if candidate.manifest_hash != natural.sha256: return fail("AUTHOR_HASH_MISMATCH", "自然來源與作者依賴不同")
	if not candidate.resource_manifest_hash.is_empty():
		var paired := false
		for entry: Dictionary in parsed.dependencies:
			paired = paired or entry.path == candidate.RESOURCE_SOURCE_PAIRS[candidate.manifest_hash].path and entry.sha256 == candidate.resource_manifest_hash
		if not paired: return fail("MISSING_RESOURCE_PAIR", "作者包未列出原配對資源依賴")
	var bodies := {}
	var body_ids := {}
	for record: Dictionary in records:
		var entry: Dictionary = record.entry
		var key: String = "%d:%d" % [int(entry.site[0]), int(entry.site[1])]
		var content: Dictionary = record.content
		if entry.kind == "static":
			if not candidate.author_static_valid(content):
				if Adapter.author_integer(content.get("format"), 1, 1) and content.get("terrain") is Dictionary and content.get("resources") is Dictionary and (not content.terrain.is_empty() or not content.resources.is_empty()): return fail("AUTHOR_STATIC_UNSUPPORTED", "舊format1不准入覆寫；P2A須使用format2")
				return fail("INVALID_AUTHOR_STATIC", "離散地形／水／土地格式非法")
			for identity: String in content.get("water_bodies", {}):
				var body: Dictionary = content.water_bodies[identity]
				if bodies.has(identity) and bodies[identity] != body or body_ids.has(body.id) and body_ids[body.id] != identity: return fail("AUTHOR_WATER_ID_CONFLICT", "跨Site水體映射不同")
				bodies[identity] = body; body_ids[body.id] = identity
			candidate._author_static[key] = author_static_normalized(content)
		elif entry.kind == "scenario":
			if not candidate._author_scenario.is_empty() or not author_scenario_valid(content): return fail("INVALID_AUTHOR_SCENARIO", "劇本資料格式非法")
			candidate._author_scenario = content.duplicate(true)
		else: candidate._author_initial[key] = content.duplicate(true)
	candidate._author_pin = {"scenario_id": str(parsed.scenario_id), "scenario_revision": int(parsed.revision), "scenario_package_sha256": str(parsed.package_digest)}
	candidate._author_document = parsed.duplicate(true)
	for key: String in candidate._author_static:
		var pair: PackedStringArray = key.split(":")
		var built: Dictionary = candidate.make_terrain_data(int(pair[0]), int(pair[1]))
		if not bool(built.get("ok", false)): return built
	# Stage on the same owner, then replace only script state after every check.
	for property: Dictionary in candidate.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			set(str(property.name), candidate.get(str(property.name)))
	return {"ok": true, "code": "OK", "initial_admitted": true}

static func fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}

func load_manifest(path: String = DEFAULT_MANIFEST) -> Dictionary:
	if not FileAccess.file_exists(path):
		return fail("MISSING_MANIFEST", "固定地理來源清冊不存在")
	var text := FileAccess.get_file_as_string(path)
	if text.to_utf8_buffer().size() > 8 * 1024 * 1024:
		return fail("INVALID_MANIFEST", "來源清冊過大")
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return fail("INVALID_MANIFEST", "來源清冊格式錯誤")
	if parsed.get("source_kind") == "fixed_tw_author": return load_author_package(path)
	var checked := _validate_manifest(parsed)
	if not checked.ok:
		return checked
	var summary: Dictionary = parsed.summary
	var loaded := _read_verified(path.get_base_dir(), summary, MAX_SUMMARY_BYTES)
	if not loaded.ok:
		return loaded
	var bytes: PackedByteArray = loaded.bytes
	if bytes.size() != int(summary.size[0]) * int(summary.size[1]):
		return fail("INVALID_SUMMARY", "地理摘要長度與格網不符")
	for value: int in bytes:
		if value < 0 or value >= CLASS_NAMES.size():
			return fail("INVALID_SUMMARY", "地理摘要含未知分類")
	var scope_bytes := PackedByteArray()
	if parsed.has("content_scope"):
		var scope_result := _read_verified(path.get_base_dir(), parsed.content_scope, MAX_SUMMARY_BYTES)
		if not scope_result.ok:
			return scope_result
		scope_bytes = scope_result.bytes
		if scope_bytes.size() != bytes.size():
			return fail("INVALID_SCOPE", "內容範圍長度與地理摘要不同")
		for value: int in scope_bytes:
			if value > 5:
				return fail("INVALID_SCOPE", "內容範圍包含未知分類")
	var quality_bytes := PackedByteArray()
	if parsed.has("source_quality"):
		var quality_result := _read_verified(path.get_base_dir(), parsed.source_quality, MAX_SUMMARY_BYTES)
		if not quality_result.ok:
			return quality_result
		quality_bytes = quality_result.bytes
		if quality_bytes.size() != bytes.size():
			return fail("INVALID_QUALITY", "來源品質長度與地理摘要不同")
		for value: int in quality_bytes:
			if value > 4:
				return fail("INVALID_QUALITY", "來源品質包含未知分類")
	var resource_layer := _read_resource_manifest(text.sha256_text())
	if not resource_layer.ok:
		return resource_layer
	# A declared official land rule may not silently lose its resource layer.
	# Explicit synthetic owner fixtures retain their original geography-only contract.
	if parsed.has("land_condition_rule") and parsed.get("synthetic_fixture") != true and resource_layer.get("manifest", {}).is_empty():
		return fail("MISSING_RESOURCE_PAIR", "Declared fixed land source has no released geography/resource pair")
	# Validate a candidate completely before replacing the currently viewed atlas.
	manifest = parsed
	manifest_hash = text.sha256_text()
	_resource_manifest = resource_layer.get("manifest", {})
	resource_manifest_hash = str(resource_layer.get("sha256", ""))
	resource_rule_revision = str(_resource_manifest.get("placement_rule", ""))
	_folder = path.get_base_dir()
	_summary = bytes
	_content_scope = scope_bytes
	_source_quality = quality_bytes
	_water_bodies.clear()
	_water_body_kinds.clear()
	_water_body_sources.clear()
	_water_body_names.clear()
	for body: Dictionary in manifest.get("water_bodies", []):
		_water_bodies[int(body.id)] = _water_body_kinds.size()
		_water_body_kinds.append(int(body.kind))
		_water_body_sources.append(str(body.source_id))
		_water_body_names.append(str(body.get("name", "")))
	# Keep the verified registry in compact columns rather than tens of thousands
	# of nested Dictionaries. The complete source manifest and hash stay on disk;
	# callers query an individual body without materializing the entire registry.
	manifest.erase("water_bodies")
	_sample_spacing_m = int(manifest.elevation_tiles[0].spacing_m) if not manifest.get("elevation_tiles", []).is_empty() else 0
	clear_cache()
	_tile_index.clear()
	for tile: Dictionary in manifest.get("elevation_tiles", []):
		var spacing := int(tile.spacing_m)
		var first := Vector2i(Grid.floor_div(int(tile.origin[0]), 20000), Grid.floor_div(int(tile.origin[1]), 20000))
		var last := Vector2i(Grid.floor_div(int(tile.origin[0]) + int(tile.size[0]) * spacing - 1, 20000), Grid.floor_div(int(tile.origin[1]) + int(tile.size[1]) * spacing - 1, 20000))
		for y: int in range(first.y, last.y + 1):
			for x: int in range(first.x, last.x + 1):
				var key := Vector2i(x, y)
				if not _tile_index.has(key):
					_tile_index[key] = []
				_tile_index[key].append(tile)
	_author_pin = {}
	_author_document = {}
	_author_scenario = {}
	_author_static = {}
	_author_initial = {}
	_author_neighbour_bodies = {}
	return {"ok": true, "code": "OK", "message": "固定地理資料已載入"}

func _read_resource_manifest(geography_hash: String) -> Dictionary:
	var pair: Dictionary = RESOURCE_SOURCE_PAIRS.get(geography_hash, {})
	if pair.is_empty():
		return {"ok": true} # Older and synthetic geography keeps its original resource contract.
	var file := FileAccess.open(str(pair.path), FileAccess.READ)
	if file == null or file.get_length() > 2 * 1024 * 1024:
		return fail("MISSING_RESOURCE_LAYER", "固定地圖資源來源清冊無法讀取")
	var text := file.get_as_text()
	if text.sha256_text() != str(pair.sha256):
		return fail("HASH_MISMATCH", "Paired resource manifest checksum differs; original source retained")
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary or parsed.get("format") != 1 \
			or parsed.get("geography_manifest_sha256") != geography_hash \
			or parsed.get("placement_rule") != SiteEnvironment.FIXED_RESOURCE_RULE \
			or parsed.get("crs") != "EPSG:3826" or parsed.get("cell_size_m") != 20 \
			or parsed.get("region_size_m") != 20000 or not _pair(parsed.get("tile_size"), 1000, 1000) \
			or parsed.get("encoding") != "u8_zlib" or parsed.get("row_order") != "north_to_south" \
			or not parsed.get("tiles") is Dictionary or parsed.tiles.is_empty() or parsed.tiles.size() > 2048:
		return fail("INVALID_RESOURCE_LAYER", "資源來源版本或格網不相容")
	for key: Variant in parsed.tiles:
		var parts := str(key).split(",")
		var record: Variant = parsed.tiles[key]
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int() \
				or not record is Dictionary or not _valid_file_record(record) or record.get("raw_bytes") != RESOURCE_TILE_BYTES \
				or not _integer(record.get("bytes"), 1, RESOURCE_TILE_BYTES + 65536):
			return fail("INVALID_RESOURCE_LAYER", "資源區塊來源記錄非法")
	return {"ok": true, "manifest": parsed, "sha256": text.sha256_text()}

func site_resource_cover(site: Vector2i) -> Dictionary:
	if _resource_manifest.is_empty():
		return {"ok": true, "enabled": false}
	var region := Grid.region_of(site)
	var key := "%d,%d" % [region.x, region.y]
	var cells := PackedByteArray()
	cells.resize(100)
	if not _resource_manifest.tiles.has(key):
		var summary := get_site_summary(site.x, site.y)
		if not summary.ok or summary.class_id != 1:
			return fail("MISSING_RESOURCE_TILE", "此陸地缺少固定資源地類區塊")
		return {"ok": true, "enabled": true, "cover": cells}
	if _resource_region != key:
		var record: Dictionary = _resource_manifest.tiles[key]
		# Drop the previous derived tile before loading the next one.
		_resource_region = ""
		_resource_cover = PackedByteArray()
		var loaded := _read_verified(RESOURCE_MANIFEST.get_base_dir(), record, RESOURCE_TILE_BYTES + 65536)
		if not loaded.ok:
			return loaded
		if loaded.bytes.size() != int(record.bytes):
			return fail("INVALID_RESOURCE_TILE", "資源區塊壓縮長度不符")
		var bytes: PackedByteArray = loaded.bytes.decompress(RESOURCE_TILE_BYTES, FileAccess.COMPRESSION_DEFLATE)
		if bytes.size() != RESOURCE_TILE_BYTES:
			return fail("INVALID_RESOURCE_TILE", "資源地類區塊長度不符")
		for value: int in bytes:
			if value > 7:
				return fail("INVALID_RESOURCE_TILE", "資源地類區塊含未知分類")
		_resource_cover = bytes
		_resource_region = key
		peak_cache_bytes = maxi(peak_cache_bytes, _cache_bytes + _fine_masks.size() * FINE_MASK_BYTES + _resource_cover.size())
	var left := posmod(site.x, 100) * 10
	var top := (99 - posmod(site.y, 100)) * 10
	for row: int in range(10):
		for column: int in range(10):
			cells[row * 10 + column] = _resource_cover[(top + row) * 1000 + left + column]
	return {"ok": true, "enabled": true, "cover": cells}

func get_water_body(identity: int) -> Dictionary:
	if not _water_bodies.has(identity):
		for raw: Dictionary in _author_static.values():
			var body: Dictionary = raw.get("water_bodies", {}).get(str(identity), {})
			if not body.is_empty(): return {"id": identity, "kind": int(body.kind), "source_id": "author:" + str(body.id), "name": str(body.id)}
		return {}
	var index: int = _water_bodies[identity]
	return {"id": identity, "kind": int(_water_body_kinds[index]),
		"source_id": _water_body_sources[index], "name": _water_body_names[index]}

func _validate_manifest(value: Dictionary) -> Dictionary:
	if value.get("format") != 1 or value.get("atlas_id") != Grid.ATLAS_ID or value.get("grid_contract_version") != Grid.CONTRACT_VERSION or value.get("crs") != "EPSG:3826":
		return fail("INCOMPATIBLE_MANIFEST", "地理分區或格網版本不相容")
	if not value.get("base_revision") is String or str(value.base_revision).is_empty() or not value.get("sources") is Array:
		return fail("INVALID_MANIFEST", "來源清冊缺少固定版次／来源")
	# Optional explicit game rule is part of this already checksum-pinned source.
	if value.has("land_condition_rule") and (not value.land_condition_rule is String or value.land_condition_rule != "terrain_mapped_potential_v1"):
		return fail("INVALID_LAND_CONDITION_RULE", "Unknown fixed source land-condition rule")
	var grid: Variant = value.get("grid")
	if not grid is Dictionary or not _pair(grid.get("origin"), 0, 0) or grid.get("cell_m") != 2 or grid.get("site_cells") != 100 or grid.get("region_sites") != 100:
		return fail("INCOMPATIBLE_GRID", "格網必須固定於原點，每格2m、每Site100格、每Region100個Site")
	var summary: Variant = value.get("summary")
	if not summary is Dictionary or not _valid_file_record(summary) or not _pair(summary.get("size"), 1, 16000) or not _pair(summary.get("site_origin"), -1000000, 1000000) or summary.get("encoding") != "u8" or summary.get("row_order") != "north_to_south" or summary.get("nodata") != 0:
		return fail("INVALID_SUMMARY", "地理摘要契約錯誤")
	if int(summary.size[0]) * int(summary.size[1]) > MAX_SUMMARY_BYTES:
		return fail("INVALID_SUMMARY", "地理摘要超過記憶體上限")
	if not value.has("content_scope") and value.get("synthetic_fixture") != true:
		return fail("MISSING_SCOPE", "正式固定地圖缺少已開放內容範圍")
	if value.has("content_scope"):
		var scope: Variant = value.content_scope
		if not scope is Dictionary or not _valid_file_record(scope) or not _pair(scope.get("size"), 1, 16000) or not _pair(scope.get("site_origin"), -1000000, 1000000) or scope.get("encoding") != "u8" or scope.get("row_order") != "north_to_south":
			return fail("INVALID_SCOPE", "內容範圍契約錯誤")
		for axis: int in range(2):
			if int(scope.size[axis]) != int(summary.size[axis]) or int(scope.site_origin[axis]) != int(summary.site_origin[axis]):
				return fail("INVALID_SCOPE", "內容範圍必須與地理摘要使用相同格網")
	if value.has("source_quality"):
		var quality: Variant = value.source_quality
		if not quality is Dictionary or not _valid_file_record(quality) or not _pair(quality.get("size"), 1, 16000) or not _pair(quality.get("site_origin"), -1000000, 1000000) or quality.get("encoding") != "u8" or quality.get("row_order") != "north_to_south":
			return fail("INVALID_QUALITY", "來源品質格網契約錯誤")
		for axis: int in range(2):
			if int(quality.size[axis]) != int(summary.size[axis]) or int(quality.site_origin[axis]) != int(summary.site_origin[axis]):
				return fail("INVALID_QUALITY", "來源品質必須與地理摘要使用相同格網")
	var water_bodies: Variant = value.get("water_bodies", [])
	if not water_bodies is Array:
		return fail("INVALID_WATER_ID", "固定水體清冊格式錯誤")
	var body_ids: Dictionary = {}
	var body_sources: Dictionary = {}
	for body: Variant in water_bodies:
		if not body is Dictionary or not _integer(body.get("id"), 2, 2147483647) or not _integer(body.get("kind"), 1, 4) or int(body.kind) not in [1, 3, 4] or not body.get("source_id") is String or str(body.source_id).is_empty() or body_ids.has(int(body.id)) or body_sources.has(str(body.source_id)):
			return fail("INVALID_WATER_ID", "固定水體必須有唯一來源身分及分類")
		body_ids[int(body.id)] = true
		body_sources[str(body.source_id)] = true
	if not value.get("elevation_tiles", []) is Array:
		return fail("INVALID_TILES", "高程區塊清冊錯誤")
	var identities: Dictionary = {}
	var common_spacing := 0
	var tile_bounds: Array[Rect2] = []
	for tile: Variant in value.get("elevation_tiles", []):
		if not tile is Dictionary or not tile.get("id") is String or str(tile.id).is_empty() or identities.has(tile.id) or not _valid_file_record(tile) or not _pair(tile.get("size"), 2, 4096) or not _pair(tile.get("origin"), -10000000, 10000000):
			return fail("INVALID_TILES", "高程區塊身分、位置或檔案契約錯誤")
		if not _integer(tile.get("spacing_m"), 1, 200) or int(tile.origin[0]) % int(tile.spacing_m) != 0 or int(tile.origin[1]) % int(tile.spacing_m) != 0 or tile.get("encoding") not in ["float32_le", "int16_le", "int16_le_zlib"] or tile.get("row_order") != "north_to_south" or not _number(tile.get("nodata")):
			return fail("INVALID_TILES", "高程格網必須對齊固定原點、使用北到南float32取樣")
		if common_spacing != 0 and common_spacing != int(tile.spacing_m):
			return fail("INVALID_TILES", "相鄰固定高程區塊必須共用取樣間距")
		common_spacing = int(tile.spacing_m)
		var bounds := Rect2(float(tile.origin[0]), float(tile.origin[1]), int(tile.size[0]) * float(tile.spacing_m), int(tile.size[1]) * float(tile.spacing_m))
		for previous: Rect2 in tile_bounds:
			if previous.intersects(bounds):
				return fail("INVALID_TILES", "高程區塊重疊；須先離線決定唯一來源")
		tile_bounds.append(bounds)
		if int(tile.size[0]) * int(tile.size[1]) * 6 > MAX_CACHE_BYTES:
			return fail("INVALID_TILES", "單一高程區塊超過快取上限")
		if tile.has("derived"):
			var derived: Variant = tile.derived
			if not derived is Dictionary or not _valid_file_record({"path": derived.get("levels_path"), "sha256": derived.get("levels_sha256")}) or not _valid_file_record({"path": derived.get("water_path"), "sha256": derived.get("water_sha256")}) or derived.get("encoding") not in ["u8", "u8_zlib"]:
				return fail("INVALID_TILES", "固定遊戲地形衍生資料契約錯誤")
			if (value.has("source_quality") or derived.has("quality_path")) and not _valid_file_record({"path": derived.get("quality_path"), "sha256": derived.get("quality_sha256")}):
				return fail("INVALID_QUALITY", "固定地形缺少可驗證的品質資料")
			if derived.has("water_body_path") and (not _valid_file_record({"path": derived.get("water_body_path"), "sha256": derived.get("water_body_sha256")}) or derived.get("water_body_encoding") != "u32_le_zlib"):
				return fail("INVALID_WATER_ID", "固定水體格網契約錯誤")
			if derived.has("water_detail"):
				var detail: Variant = derived.water_detail
				if not detail is Dictionary or not _valid_file_record({"path": detail.get("index_path"), "sha256": detail.get("index_sha256")}) or not _valid_file_record({"path": detail.get("data_path"), "sha256": detail.get("data_sha256")}) or detail.get("encoding") != "u32_le_zlib_segments" or not _pair(detail.get("site_size"), 100, 100) or detail.get("site_order") != "north_to_south" or not _integer(detail.get("index_bytes"), 2, 2 * 1024 * 1024) or not _integer(detail.get("data_bytes"), 1, MAX_CACHE_BYTES):
					return fail("INVALID_WATER_DETAIL", "細格岸線封包契約錯誤")
				if int(tile.size[0]) * int(tile.spacing_m) != 20000 or int(tile.size[1]) * int(tile.spacing_m) != 20000 or int(tile.origin[0]) % 20000 != 0 or int(tile.origin[1]) % 20000 != 0:
					return fail("INVALID_WATER_DETAIL", "細格岸線必須對齊完整 Region")
		identities[tile.id] = true
	return {"ok": true}

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _integer(value: Variant, low: int, high: int) -> bool:
	return _number(value) and float(value) == floor(float(value)) and float(value) >= low and float(value) <= high

static func _pair(value: Variant, low: int, high: int) -> bool:
	return value is Array and value.size() == 2 and _integer(value[0], low, high) and _integer(value[1], low, high)

static func _valid_file_record(value: Dictionary) -> bool:
	if not value.get("path") is String or not value.get("sha256") is String:
		return false
	var path: String = value.path
	var digest: String = value.sha256
	return not path.is_empty() and not path.is_absolute_path() and not path.contains(":") and not path.contains("\\") and not path.split("/").has("..") and digest.length() == 64 and digest.is_valid_hex_number(false)

static func _read_verified(folder: String, record: Dictionary, limit: int) -> Dictionary:
	var path := folder.path_join(str(record.path))
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return fail("MISSING_DATA", "固定來源缺檔：" + str(record.path))
	if file.get_length() > limit:
		return fail("DATA_TOO_LARGE", "來源超過快取配額：" + str(record.path))
	var bytes := file.get_buffer(file.get_length())
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(bytes)
	if hasher.finish().hex_encode() != str(record.sha256).to_lower():
		return fail("HASH_MISMATCH", "來源校驗失敗：" + str(record.path))
	return {"ok": true, "bytes": bytes}

func get_overview() -> Dictionary:
	if manifest.is_empty():
		return fail("NOT_LOADED", "尚未載入固定地理")
	var summary: Dictionary = manifest.summary
	var width := int(summary.size[0])
	var height := int(summary.size[1])
	var west := int(summary.site_origin[0]) * 200
	var south := int(summary.site_origin[1]) * 200
	return {"ok": true, "width": width, "height": height, "classes": _summary,
		"content_scope": _content_scope, "bounds_m": [west, south, west + width * 200, south + height * 200]}

func get_site_summary(site_x: int, site_y: int) -> Dictionary:
	if manifest.is_empty():
		return fail("NOT_LOADED", "尚未載入固定地理")
	var summary: Dictionary = manifest.summary
	var x := site_x - int(summary.site_origin[0])
	var y := int(summary.size[1]) - 1 - (site_y - int(summary.site_origin[1]))
	if x < 0 or y < 0 or x >= int(summary.size[0]) or y >= int(summary.size[1]):
		return fail("OUTSIDE_CONTENT", "此位置超出目前內容範圍")
	var kind := int(_summary[y * int(summary.size[0]) + x])
	var scope := int(_content_scope[y * int(summary.size[0]) + x]) if not _content_scope.is_empty() else -1
	var site := Vector2i(site_x, site_y)
	var has_elevation := false
	var has_terrain := false
	var bounds := Rect2(site_x * 200.0, site_y * 200.0, 200.0, 200.0)
	for tile: Dictionary in _tile_index.get(Grid.region_of(site), []):
		var tile_bounds := Rect2(float(tile.origin[0]), float(tile.origin[1]), int(tile.size[0]) * float(tile.spacing_m), int(tile.size[1]) * float(tile.spacing_m))
		if bounds.intersects(tile_bounds):
			has_elevation = true
			has_terrain = has_terrain or tile.has("derived")
	has_terrain = has_terrain or kind == 1 and _has_sea_rule()
	if scope == 0:
		has_terrain = false
	return {"ok": true, "site_id": Grid.site_id(str(manifest.atlas_id), site), "site": site,
		"region": Grid.region_of(site), "class_id": kind, "geography_status": CLASS_NAMES[kind],
		"status": "outside_content" if scope == 0 else CLASS_NAMES[kind], "content_scope": scope,
		"has_elevation": has_elevation, "has_terrain": has_terrain,
		"source_quality_code": int(_source_quality[y * int(summary.size[0]) + x]) if not _source_quality.is_empty() else -1,
		"quality": str(manifest.get("quality", "source_limited"))}

func _has_sea_rule() -> bool:
	var rule: Variant = manifest.get("sea_surface_rule")
	return rule is Dictionary and rule.get("summary_class") == 1 and rule.get("gameplay_level") == 0 and rule.get("whole_site_verified") == true and rule.get("source") is String and not str(rule.source).is_empty()

func _sea_sample(easting: float, northing: float) -> Dictionary:
	if _has_sea_rule():
		var site := Grid.site_from_meters(easting, northing)
		var summary := get_site_summary(site.x, site.y)
		if summary.ok and summary.class_id == 1:
			return {"ok": true, "elevation_m": 0.0, "elevation_valid": false, "level": 0, "water_kind": 2, "water_id": "ocean", "water_body": 1, "source_quality_code": 0}
	return fail("MISSING_DATA", "高程／跨界鄰域來源尚未備妥")

func _tile_at(easting: float, northing: float) -> Dictionary:
	var key := Vector2i(floori(easting / 20000.0), floori(northing / 20000.0))
	for tile: Dictionary in _tile_index.get(key, []):
		var spacing := float(tile.spacing_m)
		if easting >= float(tile.origin[0]) and northing >= float(tile.origin[1]) and easting < float(tile.origin[0]) + int(tile.size[0]) * spacing and northing < float(tile.origin[1]) + int(tile.size[1]) * spacing:
			return tile
	return {}

func _load_tile(tile: Dictionary) -> Dictionary:
	var identity := str(tile.id)
	if _tiles.has(identity):
		if _lru.back() != identity:
			_lru.erase(identity)
			_lru.append(identity)
		return _tiles[identity]
	if not tile.has("derived"):
		return fail("MISSING_TERRAIN", "此區尚無固定0–5遊戲地形及水域分類")
	var count := int(tile.size[0]) * int(tile.size[1])
	var stride := 4 if tile.encoding == "float32_le" else 2
	var derived: Dictionary = tile.derived
	var needed := count * (stride + 2 + (1 if derived.has("quality_path") else 0) + (4 if derived.has("water_body_path") else 0))
	var resource_reserve := RESOURCE_TILE_BYTES if not _resource_manifest.is_empty() else 0
	if derived.has("water_detail"):
		needed += int(derived.water_detail.data_bytes) + int(derived.water_detail.index_bytes) * 4
	if needed + FINE_MASK_BYTES * MAX_FINE_MASKS + resource_reserve > MAX_CACHE_BYTES:
		return fail("DATA_TOO_LARGE", "固定地形及來源品質超過快取配額")
	# Evict before reading, so an incoming tile cannot briefly double the budget.
	while not _lru.is_empty() and (_tiles.size() >= MAX_CACHE_TILES or _cache_bytes + needed + FINE_MASK_BYTES * MAX_FINE_MASKS + resource_reserve > MAX_CACHE_BYTES):
		var oldest: String = _lru.pop_front()
		_cache_bytes -= int(_tiles[oldest].bytes_used)
		_tiles.erase(oldest)
	var elevation := _read_verified(_folder, tile, count * stride + 65536)
	if not elevation.ok:
		return elevation
	if tile.encoding == "int16_le_zlib":
		elevation.bytes = elevation.bytes.decompress(count * 2, FileAccess.COMPRESSION_DEFLATE)
	var levels := _read_verified(_folder, {"path": derived.levels_path, "sha256": derived.levels_sha256}, count + 65536)
	if not levels.ok:
		return levels
	var water := _read_verified(_folder, {"path": derived.water_path, "sha256": derived.water_sha256}, count + 65536)
	if not water.ok:
		return water
	if derived.encoding == "u8_zlib":
		levels.bytes = levels.bytes.decompress(count, FileAccess.COMPRESSION_DEFLATE)
		water.bytes = water.bytes.decompress(count, FileAccess.COMPRESSION_DEFLATE)
	if elevation.bytes.size() != count * stride or levels.bytes.size() != count or water.bytes.size() != count:
		return fail("INVALID_TILE", "固定地形資料長度與格網不符")
	var quality := PackedByteArray()
	if derived.has("quality_path"):
		var loaded_quality := _read_verified(_folder, {"path": derived.quality_path, "sha256": derived.quality_sha256}, count + 65536)
		if not loaded_quality.ok:
			return loaded_quality
		quality = loaded_quality.bytes.decompress(count, FileAccess.COMPRESSION_DEFLATE) if derived.encoding == "u8_zlib" else loaded_quality.bytes
		if quality.size() != count:
			return fail("INVALID_QUALITY", "来源品質長度與地形不符")
	var bodies := PackedByteArray()
	if derived.has("water_body_path"):
		var loaded_bodies := _read_verified(_folder, {"path": derived.water_body_path, "sha256": derived.water_body_sha256}, count * 4 + 65536)
		if not loaded_bodies.ok:
			return loaded_bodies
		bodies = loaded_bodies.bytes.decompress(count * 4, FileAccess.COMPRESSION_DEFLATE)
		if bodies.size() != count * 4:
			return fail("INVALID_WATER_ID", "固定水體身分長度與地形不符")
	for i: int in range(count):
		var height: float = elevation.bytes.decode_float(i * 4) if stride == 4 else elevation.bytes.decode_s16(i * 2)
		if not is_finite(height) or int(levels.bytes[i]) > 5 and int(levels.bytes[i]) != 255 or int(water.bytes[i]) > 4 and int(water.bytes[i]) != 255:
			return fail("INVALID_TILE", "固定地形包含非法高程或分類")
		if not quality.is_empty() and (quality[i] > 4 or water.bytes[i] != 2 and water.bytes[i] != 255 and quality[i] == 0):
			return fail("INVALID_QUALITY", "陸地／內陸水域必須標明高程來源品質")
		var body := int(bodies.decode_u32(i * 4)) if not bodies.is_empty() else (1 if water.bytes[i] == 2 else 0)
		if int(water.bytes[i]) in [1, 3, 4]:
			if not _water_bodies.has(body):
				return fail("MISSING_WATER_ID", "內陸水域尚無固定水體識別；不能合併不同河湖")
			if int(_water_body_kinds[_water_bodies[body]]) != int(water.bytes[i]) or height == float(tile.nodata) or int(levels.bytes[i]) > 5:
				return fail("INVALID_WATER_ID", "內陸水域來源分類／高程不一致")
		elif (water.bytes[i] == 0 and body != 0) or (water.bytes[i] == 2 and body != 1):
			return fail("INVALID_WATER_ID", "陸海分類與水體識別不一致")
	var fine_index: Dictionary = {}
	var fine_bank := PackedByteArray()
	if derived.has("water_detail"):
		var detail: Dictionary = derived.water_detail
		var index_read := _read_verified(_folder, {"path": detail.index_path, "sha256": detail.index_sha256}, int(detail.index_bytes))
		if not index_read.ok:
			return index_read
		var bank_read := _read_verified(_folder, {"path": detail.data_path, "sha256": detail.data_sha256}, int(detail.data_bytes))
		if not bank_read.ok:
			return bank_read
		if index_read.bytes.size() != int(detail.index_bytes) or bank_read.bytes.size() != int(detail.data_bytes):
			return fail("INVALID_WATER_DETAIL", "細格岸線封包長度不符")
		var parsed: Variant = JSON.parse_string(index_read.bytes.get_string_from_utf8())
		if not parsed is Dictionary or parsed.size() > 10000:
			return fail("INVALID_WATER_DETAIL", "細格岸線索引格式錯誤")
		var segments: Array[Vector2i] = []
		for key: Variant in parsed:
			var segment: Variant = parsed[key]
			if not key is String or not str(key).is_valid_int() or str(int(key)) != key or int(key) < 0 or int(key) >= 10000 or not segment is Dictionary or not _integer(segment.get("offset"), 0, int(detail.data_bytes)) or not _integer(segment.get("compressed_bytes"), 1, FINE_MASK_BYTES + 65536) or int(segment.offset) + int(segment.compressed_bytes) > int(detail.data_bytes) or not _valid_file_record({"path": "segment", "sha256": segment.get("sha256")}):
				return fail("INVALID_WATER_DETAIL", "細格岸線索引範圍／校驗碼錯誤")
			segments.append(Vector2i(int(segment.offset), int(segment.compressed_bytes)))
		segments.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
		var end := 0
		for segment: Vector2i in segments:
			if segment.x != end:
				return fail("INVALID_WATER_DETAIL", "細格岸線片段重疊或缺段")
			end += segment.y
		if end != int(detail.data_bytes):
			return fail("INVALID_WATER_DETAIL", "細格岸線索引未完整覆蓋封包")
		fine_index = parsed
		fine_bank = bank_read.bytes
	var result := {"ok": true, "elevation": elevation.bytes, "levels": levels.bytes, "water": water.bytes, "quality": quality, "water_bodies": bodies, "fine_index": fine_index, "fine_bank": fine_bank, "stride": stride, "bytes_used": needed}
	_tiles[identity] = result
	_lru.append(identity)
	_cache_bytes += needed
	peak_cache_bytes = maxi(peak_cache_bytes, _cache_bytes + _fine_masks.size() * FINE_MASK_BYTES + _resource_cover.size())
	return result

func _fine_water_at(easting: float, northing: float, tile: Dictionary) -> Dictionary:
	if not tile.get("derived", {}).has("water_detail"):
		return {"ok": true, "available": false}
	var loaded := _load_tile(tile)
	if not loaded.ok:
		return loaded
	var site := Grid.site_from_meters(easting, northing)
	var region := Grid.region_of(site)
	var local_site := site - region * 100
	var key := str((99 - local_site.y) * 100 + local_site.x)
	if not loaded.fine_index.has(key):
		return {"ok": true, "available": false}
	if not _fine_masks.has(site):
		var segment: Dictionary = loaded.fine_index[key]
		var compressed: PackedByteArray = loaded.fine_bank.slice(int(segment.offset), int(segment.offset) + int(segment.compressed_bytes))
		var hasher := HashingContext.new()
		hasher.start(HashingContext.HASH_SHA256)
		hasher.update(compressed)
		if hasher.finish().hex_encode() != str(segment.sha256).to_lower():
			return fail("HASH_MISMATCH", "細格岸線片段校驗失敗")
		var mask := compressed.decompress(FINE_MASK_BYTES, FileAccess.COMPRESSION_DEFLATE)
		if mask.size() != FINE_MASK_BYTES:
			return fail("INVALID_WATER_DETAIL", "細格岸線解壓長度不符")
		for i: int in range(10000):
			var mask_body := int(mask.decode_u32(i * 4))
			if mask_body > 1 and not _water_bodies.has(mask_body):
				return fail("MISSING_WATER_ID", "細格岸線引用未知水體")
		while _fine_lru.size() >= MAX_FINE_MASKS:
			_fine_masks.erase(_fine_lru.pop_front())
		_fine_masks[site] = mask
	else:
		_fine_lru.erase(site)
	_fine_lru.append(site)
	peak_cache_bytes = maxi(peak_cache_bytes, _cache_bytes + _fine_masks.size() * FINE_MASK_BYTES + _resource_cover.size())
	var cell := Grid.local_from_mm(roundi(easting * 1000.0), roundi(northing * 1000.0))
	var body := int(_fine_masks[site].decode_u32((cell.y * 100 + cell.x) * 4))
	return {"ok": true, "available": true, "water_body": body,
		"water_kind": 0 if body == 0 else (2 if body == 1 else int(_water_body_kinds[_water_bodies[body]])),
		"water_id": "" if body == 0 else ("ocean" if body == 1 else _water_body_sources[_water_bodies[body]])}

func _sample_center(easting: float, northing: float) -> Dictionary:
	var tile := _tile_at(easting, northing)
	if tile.is_empty():
		return _sea_sample(easting, northing)
	var loaded := _load_tile(tile)
	if not loaded.ok:
		return loaded
	var x := floori((easting - float(tile.origin[0])) / float(tile.spacing_m))
	var y := int(tile.size[1]) - 1 - floori((northing - float(tile.origin[1])) / float(tile.spacing_m))
	var index := y * int(tile.size[0]) + x
	var elevation: float = loaded.elevation.decode_float(index * 4) if loaded.stride == 4 else loaded.elevation.decode_s16(index * 2)
	var level: int = loaded.levels[index]
	var water: int = loaded.water[index]
	var quality: int = int(loaded.quality[index]) if not loaded.quality.is_empty() else (0 if water == 2 else 1)
	var body: int = int(loaded.water_bodies.decode_u32(index * 4)) if not loaded.water_bodies.is_empty() else (1 if water == 2 else 0)
	if water == 2:
		return {"ok": true, "elevation_m": elevation if elevation != float(tile.nodata) else 0.0,
			"elevation_valid": elevation != float(tile.nodata), "level": level if level != 255 else 0, "water_kind": 2, "water_id": "ocean", "water_body": 1, "source_quality_code": quality}
	if elevation == float(tile.nodata) or level == 255 or water == 255:
		return fail("MISSING_DATA", "來源為NoData；不以零高程或隨機地形替代")
	return {"ok": true, "elevation_m": elevation, "elevation_valid": true, "level": level, "water_kind": water,
		"water_id": _water_body_sources[_water_bodies[body]] if water != 0 else "", "water_body": body, "source_quality_code": quality}

func sample_meters(easting: float, northing: float) -> Dictionary:
	return _author_sample(_sample_meters(easting, northing, null), easting, northing)

func _sample_site_meters(easting: float, northing: float, centre_cache: Dictionary) -> Dictionary:
	return _author_sample(_sample_meters(easting, northing, centre_cache), easting, northing)

func _sample_point(easting: float, northing: float, centre_cache: Variant) -> Dictionary:
	if centre_cache == null or _sample_spacing_m == 0:
		return _sample_center(easting, northing)
	var key := Vector2i(floori(easting / _sample_spacing_m), floori(northing / _sample_spacing_m))
	if centre_cache.has(key):
		return centre_cache[key]
	# Only source lattice cells are memoized. Summary-only sea keeps its exact
	# position lookup, even if a future source spacing does not divide 200m.
	if _tile_at(easting, northing).is_empty():
		return _sea_sample(easting, northing)
	var sampled := _sample_center(easting, northing)
	if sampled.ok:
		centre_cache[key] = sampled
	return sampled

func _sample_meters(easting: float, northing: float, centre_cache: Variant) -> Dictionary:
	if not is_finite(easting) or not is_finite(northing):
		return fail("INVALID_POSITION", "非有限地理座標")
	var tile := _tile_at(easting, northing)
	if tile.is_empty():
		return _sea_sample(easting, northing)
	var detail := _fine_water_at(easting, northing, tile)
	if not detail.ok:
		return detail
	if detail.available and int(detail.water_kind) == 2:
		return {"ok": true, "elevation_m": 0.0, "elevation_valid": false, "level": 0, "water_kind": 2, "water_id": "ocean", "water_body": 1, "source_quality_code": 0}
	var result := _sample_point(easting, northing, centre_cache)
	if not result.ok:
		return result
	if centre_cache != null:
		result = result.duplicate() # Fine water and interpolation never modify shared source samples.
	if detail.available:
		result.water_kind = detail.water_kind
		result.water_body = detail.water_body
		result.water_id = detail.water_id
	if int(result.water_kind) == 2:
		# Coarse ocean posts can support neighbouring two-metre land; the ocean
		# itself never presents that support as a measured seabed or sea surface.
		result.elevation_m = 0.0
		result.elevation_valid = false
		result.source_quality_code = 0
		result.level = 0
		return result
	if int(result.water_kind) > 0:
		if not bool(result.elevation_valid):
			return fail("MISSING_DATA", "內陸水面缺少有效高程支援")
		return result
	var spacing := float(tile.spacing_m)
	var x := floori(easting / spacing - 0.5)
	var y := floori(northing / spacing - 0.5)
	var west := (x + 0.5) * spacing
	var south := (y + 0.5) * spacing
	var points: Array[Dictionary] = []
	for offset: Vector2i in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
		var point := _sample_point(west + offset.x * spacing, south + offset.y * spacing, centre_cache)
		if not point.ok:
			return point
		points.append(point)
	var fx := (easting - west) / spacing
	var fy := (northing - south) / spacing
	var weights := [(1.0 - fx) * (1.0 - fy), fx * (1.0 - fy), (1.0 - fx) * fy, fx * fy]
	var total := 0.0
	var height := 0.0
	var level := 0.0
	for i: int in range(4):
		# NoData over explicitly mapped sea is not measured zero elevation.
		if bool(points[i].elevation_valid) and (int(points[i].water_kind) == 0 or detail.available):
			total += float(weights[i])
			height += float(points[i].elevation_m) * float(weights[i])
			level += float(points[i].level) * float(weights[i])
			if float(weights[i]) > 0.0:
				result.source_quality_code = maxi(int(result.source_quality_code), int(points[i].source_quality_code))
				if int(points[i].water_kind) != 0:
					# A lake island smaller than the source lattice needs estimated
					# support; never label its surrounding water surface as land DTM.
					result.source_quality_code = 4
	if total <= 0.0:
		return fail("MISSING_DATA", "陸地插值缺少有效高程來源")
	result.elevation_m = height / total
	result.elevation_valid = true
	result.level = level / total
	result.level = clampi(roundi(float(result.level)), 0, 5)
	return result

func make_terrain_data(site_x: int, site_y: int) -> Dictionary:
	var summary := get_site_summary(site_x, site_y)
	if not summary.ok:
		return summary
	if summary.status == "outside_content":
		return fail("OUTSIDE_CONTENT", "此地點保留真實地理背景，目前尚未開放")
	if summary.class_id == 0:
		return fail("MISSING_DATA", "此Site尚無地理來源；保留目前檢視")
	return Adapter.build(self, Vector2i(site_x, site_y))

func refresh_boundary(data: TerrainData, site: Vector2i, neighbour_query: Callable = Callable()) -> Dictionary:
	if data == null or data.size != Vector2i(100, 100):
		return fail("INVALID_SITE", "跨界刷新要求原100×100 TerrainData")
	var patches: Array[Dictionary] = []
	var border: Dictionary = {}
	var visual_halo: Dictionary = {}
	for direction: int in range(4):
		var contacts := PackedInt32Array()
		for offset: int in range(100):
			var cell := Adapter.boundary_cell(direction, offset)
			var outside := cell + TerrainData.DIRECTIONS[direction]
			var easting_mm := int(site.x) * Grid.SITE_MM + outside.x * Grid.CELL_MM + 1000
			var northing_mm := int(site.y) * Grid.SITE_MM + (99 - outside.y) * Grid.CELL_MM + 1000
			var neighbour: Dictionary
			if neighbour_query.is_valid():
				neighbour = neighbour_query.call(Grid.site_from_mm(easting_mm, northing_mm), Grid.local_from_mm(easting_mm, northing_mm))
			else:
				neighbour = sample_meters(easting_mm / 1000.0, northing_mm / 1000.0)
			if not bool(neighbour.get("ok", false)):
				return neighbour
			if not _integer(neighbour.get("level"), 0, 5) or not _integer(neighbour.get("water_kind"), 0, 4):
				return fail("INVALID_NEIGHBOUR", "鄰圖修改後地形資料不合法")
			visual_halo["%d:%d" % [outside.x, outside.y]] = [int(neighbour.level), int(neighbour.water_kind)]
			var index := data.index(cell)
			var difference := int(data.height_levels[index]) - int(neighbour.level)
			var dry := data.surface_types[index] != TerrainData.Surface.WATER
			patches.append({"index": index, "direction": direction, "drop": maxi(difference, 0),
				"ramp": false,
				"shore": dry and int(neighbour.water_kind) > 0})
			contacts.append(Adapter.boundary_contact(int(data.height_levels[index]), 0 if dry else 1, int(neighbour.level), int(neighbour.water_kind)))
			border[cell] = false
		for offset: int in Adapter.boundary_passes(contacts):
			patches[direction * 100 + offset].ramp = true
	# Corner evidence is needed when a parallel slope reaches a Site corner.
	# Use the same delta-aware neighbour query, and commit only after all 404 samples succeed.
	for corner: Vector2i in [Vector2i(-1, -1), Vector2i(100, -1), Vector2i(-1, 100), Vector2i(100, 100)]:
		var easting_mm := int(site.x) * Grid.SITE_MM + corner.x * Grid.CELL_MM + 1000
		var northing_mm := int(site.y) * Grid.SITE_MM + (99 - corner.y) * Grid.CELL_MM + 1000
		var neighbour: Dictionary
		if neighbour_query.is_valid():
			neighbour = neighbour_query.call(Grid.site_from_mm(easting_mm, northing_mm), Grid.local_from_mm(easting_mm, northing_mm))
		else:
			neighbour = sample_meters(easting_mm / 1000.0, northing_mm / 1000.0)
		if not bool(neighbour.get("ok", false)):
			return neighbour
		if not _integer(neighbour.get("level"), 0, 5) or not _integer(neighbour.get("water_kind"), 0, 4):
			return fail("INVALID_NEIGHBOUR", "鄰圖修改後地形資料不合法")
		visual_halo["%d:%d" % [corner.x, corner.y]] = [int(neighbour.level), int(neighbour.water_kind)]
	# Missing or invalid neighbours leave every edge unchanged.
	for patch: Dictionary in patches:
		var index := int(patch.index)
		var direction := int(patch.direction)
		data.cliff_drops[index * 4 + direction] = int(patch.drop)
		data.ramp_edges[index] = (data.ramp_edges[index] & ~(1 << direction)) | ((1 << direction) if bool(patch.ramp) else 0)
		if patch.shore:
			border[data.cell_from_index(index)] = true
	for cell: Vector2i in border:
		var index := data.index(cell)
		data.flags[index] &= ~(TerrainData.Flag.CLIFF | TerrainData.Flag.RAMP | TerrainData.Flag.SHORE)
		var shore: bool = border[cell]
		for direction: int in range(4):
			if data.cliff_drops[index * 4 + direction] > 0:
				data.flags[index] |= TerrainData.Flag.CLIFF
			var adjacent := cell + TerrainData.DIRECTIONS[direction]
			if data.surface_types[index] != TerrainData.Surface.WATER and data.contains(adjacent) and data.surface_types[data.index(adjacent)] == TerrainData.Surface.WATER:
				shore = true
		if data.ramp_edges[index] != 0:
			data.flags[index] |= TerrainData.Flag.RAMP
		if shore:
			data.flags[index] |= TerrainData.Flag.SHORE
	data.parameters["ramp_visual_halo"] = visual_halo
	data.navigation_revision += 1
	return {"ok": true, "code": "OK", "message": "相鄰地形邊界已更新"}

func cache_stats() -> Dictionary:
	return {"tiles": _tiles.size(), "bytes": _cache_bytes + _fine_masks.size() * FINE_MASK_BYTES + _resource_cover.size(), "peak_bytes": peak_cache_bytes,
		"resource_tile_bytes": _resource_cover.size(), "resource_tile_limit_bytes": RESOURCE_TILE_BYTES,
		"fine_masks": _fine_masks.size(), "fine_mask_limit": MAX_FINE_MASKS,
		"limit_tiles": MAX_CACHE_TILES, "limit_bytes": MAX_CACHE_BYTES}

func clear_cache() -> void:
	_resource_region = ""
	_resource_cover = PackedByteArray()
	_tiles.clear()
	_lru.clear()
	_fine_masks.clear()
	_fine_lru.clear()
	_cache_bytes = 0
	peak_cache_bytes = 0

const RESOURCE_SOURCE_PAIRS := {
	"e3108aad1cbfd5118af08fd699ac03bf64d19b5bc9d186154dc9a5fea279f7b8": {"path": RESOURCE_MANIFEST, "sha256": "a6b9c68722c9755f4b99a0704eebd5368b6dd2fe431a7eca78a48e8fd6ee49cf"},
	"cdf59e3247c9db3eb1e5399f7346014f8dec5c2f90bb977fd41ea35bc3444446": {"path": "res://assets/region_lab/earth_tw_resources_v1/manifest.terrain_mapped_potential_v1.json", "sha256": "9acfdc50025eac0c296880102af57cc9d1faef34cc24486eef1594fcc07bd5ef"}
}


const AUTHOR_BODY_MIN := 1000000000
const AUTHOR_LAND_FIELDS := ["fertility", "moisture", "drainage", "foundation", "groundwater"]
var _author_static: Dictionary = {}
var _author_initial: Dictionary = {}
## 示範劇本 birth speed: an author package's neighbour bodies, built once per package load. project_terrain reads a
## neighbour only for its boundary heights and water (never changes it), and every Site of a birth projects its eight
## neighbours, so a 46-Site birth rebuilt and revalidated the same bodies more than ten times each. The projected Site
## itself is always built fresh (refresh_boundary changes it and the caller keeps it). Failures are not kept.
var _author_neighbour_bodies: Dictionary = {}

static func author_cell_key(value: Variant) -> bool:
	return value is String and value.is_valid_int() and str(int(value)) == value and Adapter.author_integer(int(value), 0, 9999)

func author_static_valid(raw: Variant) -> bool:
	if not raw is Dictionary or not Adapter.author_integer(raw.get("format"), 1, 2): return false
	if int(raw.format) == 1:
		return raw.size() == 3 and raw.get("terrain") is Dictionary and raw.terrain.is_empty() and raw.get("resources") is Dictionary and raw.resources.is_empty()
	if raw.size() != 5 or not raw.get("terrain") is Dictionary or raw.terrain.size() > 10000 or not raw.get("resources") is Dictionary or raw.resources.size() > 10000: return false
	if not raw.get("water_bodies") is Dictionary or raw.water_bodies.size() > 10000 or not raw.get("water_permissions") is Dictionary: return false
	for key: Variant in raw.resources:
		if not SiteEnvironment.resource_key_valid(key): return false
		if raw.resources[key] != null and not SiteEnvironment.resource_definition_shape(raw.resources[key], 10000, true): return false
	var identities := {}
	for key: Variant in raw.water_bodies:
		if not key is String or not key.is_valid_int() or str(int(key)) != key or not Adapter.author_integer(int(key), AUTHOR_BODY_MIN, 2147483646): return false
		if _water_bodies.has(int(key)): return false
		var body: Variant = raw.water_bodies[key]
		if not body is Dictionary or body.size() != 2 or not Adapter.author_id_valid(body.get("id")) or not Adapter.author_integer(body.get("kind"), 1, 4) or identities.has(body.id): return false
		identities[body.id] = int(key)
	for key: Variant in raw.terrain:
		if not author_cell_key(key): return false
		var row: Variant = raw.terrain[key]
		if not row is Dictionary or row.is_empty(): return false
		for field: Variant in row:
			if not field is String: return false
			if field in AUTHOR_LAND_FIELDS:
				if not Adapter.author_integer(row[field], 0, 100): return false
			elif field == "height":
				if not Adapter.author_integer(row[field], 0, 5): return false
			elif field == "surface":
				if not Adapter.author_integer(row[field], 0, 6): return false
			elif field == "water_kind":
				if not Adapter.author_integer(row[field], 0, 4): return false
			elif field == "water_body":
				if not Adapter.author_integer(row[field], -1, 2147483646): return false
			else: return false
		if row.has("water_kind") != row.has("water_body"): return false
		if row.has("surface") and (int(row.surface) == TerrainData.Surface.WATER) != (row.has("water_kind") and int(row.water_kind) > 0): return false
		if row.has("water_kind"):
			var kind: int = int(row.water_kind)
			var body: int = int(row.water_body)
			if (kind == 0) != (body == -1): return false
			if kind > 0:
				if not row.has("surface") or int(row.surface) != TerrainData.Surface.WATER: return false
				var definition: Dictionary = get_water_body(body) if _water_bodies.has(body) or body < AUTHOR_BODY_MIN else raw.water_bodies.get(str(body), {})
				if definition.is_empty() or int(definition.kind) != kind: return false
	var permissions: Dictionary = raw.water_permissions
	if permissions.size() != 2 or not permissions.get("cells") is Array or not permissions.get("bodies") is Array: return false
	for field: String in ["cells", "bodies"]:
		var seen := {}
		if permissions[field].size() > 10000: return false
		for value: Variant in permissions[field]:
			if not Adapter.author_integer(value, 0 if field == "cells" else AUTHOR_BODY_MIN, 9999 if field == "cells" else 2147483646) or seen.has(int(value)): return false
			if field == "bodies" and not raw.water_bodies.has(str(int(value))): return false
			seen[int(value)] = true
	return true

func author_static_for(site: Vector2i) -> Dictionary:
	return _author_static.get("%d:%d" % [site.x, site.y], {}).duplicate(true)

func _author_sample(sample: Dictionary, easting: float, northing: float) -> Dictionary:
	if not bool(sample.get("ok", false)) or _author_static.is_empty(): return sample
	var site: Vector2i = Grid.site_from_meters(easting, northing)
	var cell: Vector2i = Grid.local_from_mm(roundi(easting * 1000.0), roundi(northing * 1000.0))
	var row: Dictionary = _author_static.get("%d:%d" % [site.x, site.y], {}).get("terrain", {}).get(str(cell.y * 100 + cell.x), {})
	if row.is_empty(): return sample
	var result: Dictionary = sample.duplicate(true)
	if row.has("height"): result.level = int(row.height)
	if row.has("water_kind"):
		result.water_kind = int(row.water_kind)
		result.water_body = int(row.water_body)
		result.water_id = "author:%d" % int(row.water_body) if int(row.water_kind) > 0 else ""
	return result

func apply_author_layers(data: TerrainData, site: Vector2i) -> Dictionary:
	var raw: Dictionary = author_static_for(site)
	if raw.is_empty() or int(raw.format) == 1: return {"ok": true}
	if not author_static_valid(raw): return fail("INVALID_AUTHOR_STATIC", "作者離散層非法")
	raw = author_static_normalized(raw)
	var land := {}
	var changed_water: Array[int] = []
	for key: String in raw.terrain:
		var row: Dictionary = raw.terrain[key]
		var i: int = int(key)
		if row.has("surface"):
			data.surface_types[i] = int(row.surface)
		if (data.surface_types[i] == TerrainData.Surface.WATER) != (data.water_kind[i] > 0): return fail("AUTHOR_WATER_CONFLICT", "水體與地表不一致")
		if row.has("water_kind"): changed_water.append(i)
		var values := {}
		for field: String in AUTHOR_LAND_FIELDS:
			if row.has(field): values[field] = int(row[field])
		if not values.is_empty(): land[key] = values
	if not raw.resources.is_empty():
		var resources: Dictionary = SiteEnvironment.prepare_author_resource_source(data, raw.resources)
		if not bool(resources.get("ok", false)): return resources
		data.resource_base = resources.data.resource_base
		SiteEnvironment.rebuild_indexes(data)
	for record: Dictionary in data.resource_base.values():
		for index: int in record.cells:
			var water: bool = data.surface_types[index] == TerrainData.Surface.WATER
			if (int(record.kind) == SiteEnvironment.Kind.FISH and (not water or record.has("water") and int(record.water) != int(data.water_body[index]))) or (bool(record.blocks) and water): return fail("AUTHOR_RESOURCE_CONFLICT", "地形與既有資源足跡衝突")
	for i: Variant in raw.water_permissions.cells:
		if data.water_kind[int(i)] == 0: return fail("AUTHOR_WATER_PERMISSION", "許可必須引用真水格")
	changed_water.sort()
	data.parameters["author_land_cells"] = land
	data.parameters["author_water_bodies"] = raw.water_bodies.duplicate(true)
	data.parameters["author_water_changed_cells"] = changed_water
	data.parameters["author_water_permissions"] = raw.water_permissions.duplicate(true)
	data.parameters["author_water_rule"] = "author_water_rule_v1"
	return {"ok": true}

func make_author_draft(site: Vector2i, raw: Dictionary, revision: int) -> Dictionary:
	if not author_static_valid(raw) or not Adapter.author_integer(revision, 1, 2147483647): return fail("INVALID_AUTHOR_STATIC", "作者草稿離散層非法")
	raw = author_static_normalized(raw)
	var candidate: RegionData = RegionData.new()
	for property: Dictionary in get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0: continue
		var value: Variant = get(str(property.name))
		candidate.set(str(property.name), value.duplicate(true) if value is Dictionary or value is Array else value)
	candidate._author_static = {"%d:%d" % [site.x, site.y]: raw.duplicate(true)}
	candidate._author_initial = {}
	candidate._author_pin = {"scenario_id": "editor_draft", "scenario_revision": revision,
		"scenario_package_sha256": JSON.stringify({"natural": manifest_hash, "resources": resource_manifest_hash, "site": [site.x, site.y], "revision": revision, "static": raw}, "", true, true).sha256_text()}
	return candidate.make_terrain_data(site.x, site.y)

func _initial_body(site: Vector2i) -> Dictionary:
	var built: Dictionary = make_terrain_data(site.x, site.y)
	if not bool(built.get("ok", false)): return built
	var key: String = "%d:%d" % [site.x, site.y]
	var data: TerrainData = built.data
	if not _author_initial.has(key): return built
	var state: Dictionary = _author_initial[key].duplicate(true)
	if not state.get("id") is String or state.id != str(built.base.site_id) or state.has("world_pin") or state.has("region_snapshot") or state.has("initial_scenario") or state.has("crowd"): return fail("INVALID_AUTHOR_INITIAL", "初始投影不得攜帶目的世界或Native引用")
	SiteEnvironment.initialize(data, str(built.base.site_id))
	var delta: Variant = state.get("terrain_changes")
	if not delta is Dictionary: return fail("INVALID_AUTHOR_INITIAL", "初始高度差異非法")
	for cell: Variant in delta:
		if not author_cell_key(cell) or not Adapter.author_integer(delta[cell], 0, 5): return fail("INVALID_AUTHOR_INITIAL", "初始高度必須是0–5整數")
		data.height_levels[int(cell)] = int(delta[cell])
	if not delta.is_empty(): SiteRuntime.rebuild_terrain_edges(data)
	state["world_pin"] = author_projection_pin(built.base)
	var checked: Dictionary = SiteStore._validate_state(data, state)
	if not bool(checked.get("ok", false)):
		state.erase("world_pin")
		return checked
	SiteStore._normalize_state(state)
	for field: String in ["minute", "next_feature", "depot_cell", "capacity"]: state[field] = int(state[field])
	state.erase("world_pin")
	var navigation: TerrainData = SiteEnvironment.navigation_for_state(data, state)
	return {"ok": true, "data": navigation, "base": built.base, "metadata": built.metadata}

## 示範劇本 birth speed: an authored Site body (its state validated by _initial_body), read only and shared, for checks
## that never change it (RegionSaveSlot.open_map's resident-house check). {ok, data, base, metadata} or a refusal.
func author_initial_body(site: Vector2i) -> Dictionary:
	if _author_pin.is_empty(): return fail("INVALID_TERRAIN_MODE", "initial須有作者來源")
	return _initial_neighbour_body(site)

## A read-only neighbour body for project_terrain, built once per package load (_author_neighbour_bodies).
func _initial_neighbour_body(site: Vector2i) -> Dictionary:
	var key := "%d:%d" % [site.x, site.y]
	if _author_neighbour_bodies.has(key): return _author_neighbour_bodies[key]
	var built: Dictionary = _initial_body(site)
	if bool(built.get("ok", false)): _author_neighbour_bodies[key] = built
	return built

func project_terrain(site: Vector2i, mode: String = "base") -> Dictionary:
	if mode == "base": return make_terrain_data(site.x, site.y)
	if mode != "author_initial" or _author_pin.is_empty(): return fail("INVALID_TERRAIN_MODE", "current必須由原Slot provider提供；initial須有作者來源")
	# Validate all referenced neighbours once in this projection call, before any edge commit.
	var neighbours := {}
	for offset: Vector2i in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN, Vector2i(-1,-1), Vector2i(-1,1), Vector2i(1,-1), Vector2i(1,1)]:
		var coordinate: Vector2i = site + offset
		var built: Dictionary = _initial_body(coordinate) if offset == Vector2i.ZERO else _initial_neighbour_body(coordinate)
		if not bool(built.get("ok", false)): return built
		neighbours[coordinate] = built
	var result: Dictionary = neighbours[site]
	var data: TerrainData = result.data
	var refreshed: Dictionary = refresh_boundary(data, site, func(at: Vector2i, cell: Vector2i) -> Dictionary:
		if not neighbours.has(at): return fail("MISSING_AUTHOR_NEIGHBOUR", "初始鄰圖缺失")
		var other: TerrainData = neighbours[at].data
		return {"ok": true, "level": int(other.height_levels[other.index(cell)]), "water_kind": int(other.water_kind[other.index(cell)])})
	if not refreshed.ok: return refreshed
	if not data.site.is_empty():
		var validation_state: Dictionary = data.site.duplicate(true)
		validation_state["world_pin"] = author_projection_pin(result.base)
		var checked: Dictionary = SiteStore._validate_state(data, validation_state)
		validation_state.erase("world_pin")
		if not bool(checked.get("ok", false)): return checked
	# A Site without an initial template still needs query-ready derived indexes.
	SiteEnvironment.rebuild_indexes(data)
	result["readonly"] = true
	result["projection_mode"] = mode
	result["revision"] = JSON.stringify(_author_pin, "", true, true).sha256_text() + ":initial"
	return result


static func author_projection_pin(base: Dictionary) -> Dictionary:
	# Read-only validation binding, never registered as a world or a gameplay slot.
	var empty: Dictionary = SiteTechnologyPolicy.new_policy()
	var pin: Dictionary = {"format": 3, "world_instance_id": "author_projection", "slot_id": "readonly", "technology_policy": empty.policy}
	for field: String in ["atlas_id", "grid_contract_version", "base_revision", "manifest_sha256", "ramp_rule_revision"]:
		pin[field] = base[field]
	for field: String in Adapter.AUTHOR_FIELDS: pin[field] = base[field]
	for field: String in ["resource_layer_sha256", "resource_rule_revision"]:
		if base.has(field): pin[field] = base[field]
	return pin

func _sample_natural_site_meters(easting: float, northing: float, centre_cache: Dictionary) -> Dictionary:
	return _sample_meters(easting, northing, centre_cache)


static func author_static_normalized(raw: Dictionary) -> Dictionary:
	var normalized: Dictionary = raw.duplicate(true)
	normalized.format = int(normalized.format)
	for key: String in normalized.resources:
		if normalized.resources[key] != null: normalized.resources[key] = SiteEnvironment.normalize_resource_definition(normalized.resources[key])
	for key: String in normalized.terrain:
		for field: String in normalized.terrain[key]: normalized.terrain[key][field] = int(normalized.terrain[key][field])
	if int(normalized.format) == 2:
		for key: String in normalized.water_bodies: normalized.water_bodies[key].kind = int(normalized.water_bodies[key].kind)
		for field: String in ["cells", "bodies"]:
			var values: Array[int] = []
			for value: Variant in normalized.water_permissions[field]: values.append(int(value))
			normalized.water_permissions[field] = values
	return normalized

## P4 S5d (B): pure export of an author package carrying initial entries (the loader's "initial" kind, read at
## load_author_package above). It reads the dependency files and writes the package and its initial files into
## `folder`. The manifest is checked with the loader's own shape check before any file is written, so a written
## package has the shape the loader reads. Admission is unchanged: load_author_package still reports
## Initial world admission is completed by the original Slot transaction, after full state validation.
## `dependencies`: [{path, id}] (res:// or user://); `initial_states`: {"x:y": state} with state.id a String and no
## world_pin, region_snapshot, initial_scenario or crowd (the guards in _initial_body).
## `scenario` (示範劇本): the optional scenario document (author_scenario_valid), written as "scenario.json" on the start Site.
static func export_author_initial_package(folder: String, package_name: String, dependencies: Array, natural_id: String, scenario_id: String, revision: int, name_text: String, description: String, start: Dictionary, initial_states: Dictionary, static_states: Dictionary = {}, scenario: Dictionary = {}) -> Dictionary:
	if not DirAccess.dir_exists_absolute(folder) or not _author_path_valid(package_name): return fail("EXPORT_FOLDER", folder)
	var dependency_rows: Array = []
	for dependency: Variant in dependencies:
		if not dependency is Dictionary or not _author_dependency_path_valid(dependency.get("path")): return fail("INVALID_AUTHOR_DEPENDENCY", str(dependency))
		var handle := FileAccess.open(str(dependency.path), FileAccess.READ)
		if handle == null: return fail("MISSING_AUTHOR_DEPENDENCY", str(dependency.path))
		var dependency_bytes: int = handle.get_length()
		handle.close()
		dependency_rows.append({"path": str(dependency.path), "id": str(dependency.get("id", "")), "bytes": dependency_bytes, "sha256": FileAccess.get_sha256(str(dependency.path))})
	var file_rows: Array = []
	var file_texts: Array = []
	var validator: RegionData = RegionData.new()
	for key: Variant in static_states:
		var pair: PackedStringArray = str(key).split(":")
		if pair.size() != 2 or not pair[0].is_valid_int() or not pair[1].is_valid_int() or not validator.author_static_valid(static_states[key]): return fail("INVALID_AUTHOR_STATIC", str(key))
		var file_name: String = "static_%s_%s.json" % [pair[0], pair[1]]
		var bytes: PackedByteArray = JSON.stringify(author_static_normalized(static_states[key]), "", true, true).to_utf8_buffer()
		var hash: HashingContext = HashingContext.new()
		if hash.start(HashingContext.HASH_SHA256) != OK: return fail("AUTHOR_HASH_ERROR", file_name)
		hash.update(bytes)
		file_rows.append({"path": file_name, "site": [int(pair[0]), int(pair[1])], "kind": "static", "sha256": hash.finish().hex_encode(), "bytes": bytes.size()})
		file_texts.append({"path": file_name, "bytes": bytes})
	for key: Variant in initial_states:
		var pair: PackedStringArray = str(key).split(":")
		var state: Variant = initial_states[key]
		if pair.size() != 2 or not pair[0].is_valid_int() or not pair[1].is_valid_int(): return fail("INVALID_AUTHOR_FILE", str(key))
		if not state is Dictionary or not state.get("id") is String or state.has("world_pin") or state.has("region_snapshot") or state.has("initial_scenario") or state.has("crowd"): return fail("INVALID_AUTHOR_INITIAL", str(key))
		var file_name := "initial_%s_%s.json" % [pair[0], pair[1]]
		var bytes := JSON.stringify(state, "", true, true).to_utf8_buffer()
		var hash := HashingContext.new()
		if hash.start(HashingContext.HASH_SHA256) != OK: return fail("AUTHOR_HASH_ERROR", file_name)
		hash.update(bytes)
		file_rows.append({"path": file_name, "site": [int(pair[0]), int(pair[1])], "kind": "initial", "sha256": hash.finish().hex_encode(), "bytes": bytes.size()})
		file_texts.append({"path": file_name, "bytes": bytes})
	if not scenario.is_empty():
		if not author_scenario_valid(scenario) or not start.get("site") is Array: return fail("INVALID_AUTHOR_SCENARIO", "劇本資料格式非法")
		var scenario_bytes := JSON.stringify(scenario, "", true, true).to_utf8_buffer()
		var scenario_hash := HashingContext.new()
		if scenario_hash.start(HashingContext.HASH_SHA256) != OK: return fail("AUTHOR_HASH_ERROR", "scenario.json")
		scenario_hash.update(scenario_bytes)
		file_rows.append({"path": "scenario.json", "site": [int(start.site[0]), int(start.site[1])], "kind": "scenario", "sha256": scenario_hash.finish().hex_encode(), "bytes": scenario_bytes.size()})
		file_texts.append({"path": "scenario.json", "bytes": scenario_bytes})
	var manifest := {"format": 1, "source_kind": "fixed_tw_author", "scenario_id": scenario_id, "revision": revision,
		"name": name_text, "description": description, "atlas_id": Grid.ATLAS_ID, "grid_contract_version": Grid.CONTRACT_VERSION,
		"natural_source": natural_id, "dependencies": dependency_rows, "files": file_rows, "start": start, "package_digest": "0".repeat(64)}
	if not _author_manifest_shape(manifest): return fail("INVALID_AUTHOR_PACKAGE", "作者格式／路徑／尺寸非法；未寫入")
	var digest := author_package_digest(manifest)
	if digest.is_empty(): return fail("INVALID_AUTHOR_PACKAGE", "作者包摘要無法計算；未寫入")
	manifest.package_digest = digest
	for entry: Dictionary in file_texts:
		var handle := FileAccess.open(folder.path_join(str(entry.path)), FileAccess.WRITE)
		if handle == null: return fail("EXPORT_WRITE", str(entry.path))
		handle.store_buffer(entry.bytes)
		handle.close()
	var package_path := folder.path_join(package_name)
	var package_file := FileAccess.open(package_path, FileAccess.WRITE)
	if package_file == null: return fail("EXPORT_WRITE", package_path)
	package_file.store_string(JSON.stringify(manifest, "", true, true))
	package_file.close()
	return {"ok": true, "code": "OK", "path": package_path, "files": file_rows.size(), "package_digest": digest}

func author_initial_context() -> Dictionary:
	if _author_pin.is_empty(): return {}
	var start: Dictionary = _author_document.start.duplicate(true)
	var sites: Array = []
	var keys: Array = _author_initial.keys()
	keys.sort()
	for key: String in keys:
		var pair: PackedStringArray = key.split(":")
		sites.append([int(pair[0]), int(pair[1])])
	var has_start: bool = false
	for pair: Array in sites: has_start = has_start or int(pair[0]) == int(start.site[0]) and int(pair[1]) == int(start.site[1])
	if not has_start: sites.append(start.site.duplicate())
	return {"version": 2, "mode": "author", "author_identity": author_identity(), "starting_site": start.site.duplicate(), "expected_initial_sites": sites, "start": start}
