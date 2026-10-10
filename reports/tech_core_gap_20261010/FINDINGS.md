# Tech–Core lineage gap (CC-001 blocker), 2026-10-10

## Verdict

The 10-08 12:30 merge-premises snapshot is part of the Tech effect-union line. That line runs from 04:41 to 12:37 on 10-08; its latest Tech candidate is `effect-union-gd-typed-caller/20261008_123728_534766`.

The integrated Core is `region_core_native6_contact_final_source_v1`. It was composed on top of CoreV3 (`region_core_method_merge_source_v3_original_closure_20261008_140100`, 14:01). CoreV3 was built from that same 12:37 Tech candidate, but only as a **selected literal closure** around 340 guard roots. It was not a whole-file merge.

The closure pruned 11 `site_runtime.gd` functions. None of them appears in CoreV3's residual conflicts or exclusions. The final `site_runtime.gd` is byte-identical to Tech 12:37 in 598 of its 638 functions. It differs in the 11 pruned functions, in 13 Region-side audio, ecology and fire-suppression additions, and in an older stop-only `release_technology_operation`.

So "newer" is not the right test. The final contains everything production reachable in Tech. What it lacks is:

| Function | State in Tech 12:37 | Why D needs it |
|---|---|---|
| `prepare_release_technology_operation` / `publish_release_technology_operation` and the `permanent` form of `release_technology_operation` | Used only by `release_technology_operation` | D's own `stop_settlement_ship_order` refuses with `SCOPE_STOP_REQUIRED` while the ship feature holds `tech_trial`. It tells the player to stop or release through the original scope. D's stop-only scope release never suspends or cancels the S12 `ship_cooperation` order, so such an order can't be stopped at all. That is a production dead end. The CC-001 pinned fixture `site_technology_work_credit_test.gd.FAMILY_SCHEMA_CORRECTION.v1` (sha `0CBDEA…`, the same pin in CoreV3's own guards) calls the pair directly. |
| `release_settlement_spare_repair` | No production caller | The CC-001 `site_settlement_spares_test` calls it. Without it the test fails to parse on D. |
| The 8 others: `prepare_settlement_metal_output`, `prepare_settlement_metal_payment`, `settlement_metal_work_context`, `settlement_ship_binding_valid`, `settlement_ship_material_source_candidate`, `settlement_ship_paid_source_candidate`, `settlement_ship_spec`, `survey_stakes_operator_guard` | **Dead**: zero references in Tech 12:37, by call or by name, in production or tests | None. Don't add them. |

Other files: `MISSING_FUNCTIONS.json` lists 13 further functions in other files that Tech defines and D doesn't. These are in `crowd_site`, `site_controller`, `site_person_actions`, `site_resource_view`, `site_technology` and `terrain_lab`.
- Most belong to the native and shared-step paths that the final redesigned. Examples: `arm_work_fatigue_point`, `prepare_native_work_point_base`, `_native_shared_point_window` and `prepare_checked_controlled_prefixes`.
- A few may be features: `scope_survey_work_target`, `_f15_cold_jobs_candidate` / `cold_job_fields`, and `_draw_irrigation_channel`. They need owner review and are **not** in this patch.
- Differing bodies between Tech and D are counted but not classified. Most come from Region and later D changes on the other side.

## Patches (against D HEAD 60e9921)

1. `site_runtime.tech_release_scope.patch` (production; `site_runtime.gd` only):
   - Replaces the stop-only `release_technology_operation(data, token)` with Tech's `release_technology_operation(data, token, permanent := false)`.
   - Adds Tech's `prepare_release_technology_operation` and `publish_release_technology_operation`, and adds `release_settlement_spare_repair`.
   - All bodies are byte-identical to Tech 12:37. All 8 helpers they call exist in D with byte-identical bodies.
   - The existing caller, `site_person_actions.gd:3855` with 2 arguments, is signature-compatible.
   - Behaviour change for that caller: for an S12 order, a non-permanent stop now suspends the order (`status = "suspended"`), stops its operate zones and finishes the named feature. That is what D's `SCOPE_STOP_REQUIRED` message tells the player to do.
2. `site_technology_work_credit_test.typing.patch` (test only): explicit types for five `:=` locals that Godot 4.7.2 can't infer (lines 44, 78, 89, 115, 138). No assertion changes.

## Verification (isolated parsecheck = HEAD 60e9921 + patches, canonical helper)

| Test | HEAD | + patch |
|---|---|---|
| `site_settlement_spares_test` | parse error: `release_settlement_spare_repair` not found | runs; `S08_DISABLED_BOUNDARY_PASS`, exit 2 `S08_NAMED_PRODUCTIVE_CASES_NOT_RUN_ACTIVATION_REQUIRED` (needs the isolated catalog) |
| `site_technology_work_credit_test` | parse error (typing) | runs (with the typing patch); stops at "The original Family validator admits the explicit prerequisite archive", the F11 prerequisite (needs the isolated catalog), before reaching the release calls |
| `site_f07_authority_test` | same failure | same failure (no regression) |
| `site_f07_research_test` | same failure | same failure (no regression) |
| `site_t5_captive_production_test` | same failure | same failure (no regression) |

Runs: `output/d_integration_20261009_024321/runs/PROBE_techgap_*`.

## Catalog question

This one is already settled by the CC-001 work order (`reports/tech-tree-core-verify-task-draft.md`, section on the three stages):
- Rows 23–149 run in the isolated verification project through `verify_isolated_region_v3/v4`.
- Between rows 22 and 23, Godot is released and **Region alone publishes** the `enabled_isolated` catalog with its paired tests. The executor must not flip flags.
- D's formal catalog stays disabled; CoreV3's manifest records `formal_Catalog_remains_disabled: true`.

So rows 23+ should get an isolated-project catalog published by Region. D should not get a catalog switch, and this doesn't wait on tuning sign-off. Tuning sign-off is only needed later, to enable nodes in D's formal (player-facing) catalog.
