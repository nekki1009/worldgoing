extends "res://scripts/tests/site_actor_cloth_batch_test.gd"
## Unverified GPU candidate, --body=0|1; original 23-second internal / 25-second helper bound.
## Reuse all 18 cases, 54 substep snapshots and 18 native-frame pixel comparisons.
## No clock/collision override, props batching, model replacement or approximation.

func _initialize() -> void:
	output_root = "res://output/site_combat_performance_20260913/actor_visual_lazy_bones"
	result_prefix = "SITE_ACTOR_VISUAL_LAZY_BONES"
	capture_modes = ["full_force", "lazy_getters"]
	candidate_scope = "Original HumanEditor props/scabbard/cloth full-force versus native bone getters only; all three calls remain immediate at original cadence in BOTH passes. Same original actor, 54 exact substep body/weapon/shield/armor/bones/props and 18 post-native-frame cloth/scabbard/props/morph/material/pixel pairs. Not deferred props, FPS, live damage or formal atlas admission."
	super._initialize()

func _configure_candidate(enabled: bool) -> void:
	# Both passes execute all three original methods BEFORE the substep snapshot;
	# otherwise a later collision query could clean the bones before deferred cloth.
	assert(actor.editor.get("lazy_combat_visual_bones_enabled") != null)
	actor.batch_cloth_updates_enabled = false
	actor.editor.lazy_combat_visual_bones_enabled = enabled
	assert(actor.editor.lazy_combat_visual_bones_enabled == enabled and not actor.batch_cloth_updates_enabled)
