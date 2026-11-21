extends "res://scripts/region_lab/region_data.gd"

## Inject the separate trial atlas into the unchanged RegionLab scene for verification.
const TRIAL_MANIFEST := "res://assets/region_lab/earth_tw_tm2_121_v1_r3_trial/manifest.json"

func load_manifest(_path: String = TRIAL_MANIFEST) -> Dictionary:
	return super.load_manifest(TRIAL_MANIFEST)
