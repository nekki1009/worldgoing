extends "res://scripts/region_lab/region_data.gd"

# Test-only source injection before RegionLab._ready; production default is unchanged.
static var selected_manifest := DEFAULT_MANIFEST

func load_manifest(_path: String = DEFAULT_MANIFEST) -> Dictionary:
	return super.load_manifest(selected_manifest)
