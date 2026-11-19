extends "res://scripts/terrain_lab/terrain_army_atlas_capture.gd"
## Keep the original projection, sampling, material mask and lossless checks.
func _capture(plan: Dictionary, output: String, sources: Dictionary, dye_sources: Dictionary) -> bool:
 if plan != preload("res://scripts/terrain_lab/terrain_army_civilian_atlas.gd").plan(plan.appearance): return _reject("Not an exact phase-one civilian plan")
 if not await super._capture(plan, output, sources, dye_sources): return false
 var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output + "/manifest.json"))
 manifest["kind"] = "terrain_army_civilian_recipe"
 if not _write_json(output + "/manifest.json", manifest): return false
 var dye: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output + "/dye.json"))
 dye["source_manifest_md5"] = FileAccess.get_md5(output + "/manifest.json")
 return _write_json(output + "/dye.json", dye)
