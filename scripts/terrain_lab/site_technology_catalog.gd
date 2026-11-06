class_name SiteTechnologyCatalog
extends RefCounted
## Pure design catalog. No owner, jobs, inventory, save, elapsed time or commit state.
## All entries stay disabled until their original operation and named validation ship.
## Non-F07 values are implementation proposals, not approved balance or runtime proof.
const VERSION := 1
const NODE_IDS := ["F01","F02","F03","F04","F05","F06","F07","F08","F09","F10","F11","F12","F13","F14","F15","S01","S02","S03","S04","S05","S06","S07","S08","S09","S10","S11","S12","S13","N01","N02","N03","N04","N05","N06","N07","N08","N09","N10","N11","N12"]
const POLICY_CATEGORIES := ["F04", "F06", "F11", "F12"]
const MATERIAL_IDS := ["wood","stone","clay","iron_ore","brine","salt","wild_food","herb","fish","meat","hide","tools","seeds","grain","fiber","fodder","charcoal","pottery","steel","rope","brick","iron","cloth","leather","wool","sheep","horse","arrow","fire_arrow","bolt","siege_bolt","siege_stone","camp_tent","fire_pot","ballista_spares"]
const ITEM_PRODUCTS := ["weapon:bow_01", "weapon:crossbow_01", "armor:armor_light_leather_01", "armor:armor_iron_01"]
const RESEARCH_RULES := {
	"clock": "original World/Region/Site clock; original job work and fatigue exactly once",
	"person": "exact original Site/person reference, qualified and physically at the original station",
	"family_credit": "same trial executor completes every required personal stage; no shared-progress or last-worker credit",
	"authority": "current original duty, original team.work consent and named finite material source; no implied Site ownership",
	"transaction": "successful original material/product commit and purpose/person/attempt receipt together, never UI rewards",
	"trial_exception": "only bound purpose/person/job/recipe and finite attempt count; original nonknowledge guards remain",
	"gate_policy": "fixed original world policy, only shipped categories; never backfill old worlds",
	"preserve": "trade, loot, stock, equipment, existing six ships and basic repair retain original admission",
	"state": "original family, site.settlement, equipment_nations, original feature/order and original person cold packet",
	"seconds": "baseline effective game seconds; feature minute terms ×60 before original water/area/fatigue; 0 event phase awaits true original receipt"
}
const _BINDINGS := {
	"farm_grain": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"_feature_work","recipe":"","host":"farm","existing":true,"extension":""},
	"farm_fiber": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"_feature_work","recipe":"","host":"fiber_farm","existing":true,"extension":""},
	"charcoal": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"_feature_work","recipe":"","host":"charcoal","existing":true,"extension":""},
	"iron": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"_feature_work","recipe":"","host":"smelter","existing":true,"extension":""},
	"steel": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"_feature_work","recipe":"steel","host":"smelter","existing":true,"extension":""},
	"tools": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"_feature_work","recipe":"","host":"smithy","existing":true,"extension":""},
	"steel_tools": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"_feature_work","recipe":"steel_tools","host":"smithy","existing":true,"extension":""},
	"plant_cloth": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"_feature_work","recipe":"","host":"weaver","existing":true,"extension":""},
	"rope": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"_feature_work","recipe":"rope","host":"weaver","existing":true,"extension":""},
	"wool_cloth": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"_feature_work","recipe":"wool_cloth","host":"weaver","existing":true,"extension":""},
	"leather": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"_feature_work","recipe":"","host":"tannery","existing":true,"extension":""},
	"bow": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"ranged_craft","recipe":"bow","host":"camp","existing":true,"extension":""},
	"crossbow": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"ranged_craft","recipe":"crossbow","host":"camp","existing":true,"extension":""},
	"fire_arrow": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"ranged_craft","recipe":"fire_arrow","host":"camp","existing":true,"extension":""},
	"stone_shot": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"ranged_craft","recipe":"siege_stone","host":"camp","existing":true,"extension":""},
	"ballista_build": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"begin_siege_build","recipe":"ballista","host":"original_siege_work_slots","existing":true,"extension":""},
	"traction_build": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"begin_siege_build","recipe":"traction_trebuchet","host":"original_siege_work_slots","existing":true,"extension":""},
	"tower_build": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"begin_siege_build","recipe":"siege_tower","host":"original_siege_work_slots","existing":true,"extension":""},
	"counterweight_build": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"begin_siege_build","recipe":"counterweight_trebuchet","host":"original_siege_work_slots","existing":true,"extension":""},
	"ferry_build": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"begin_ship_build","recipe":"ferry","host":"shipyard","existing":true,"extension":""},
	"house_build": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"request_build","recipe":"house","host":"original_legal_building_cells","existing":true,"extension":""},
	"road_build": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"request_build","recipe":"road","host":"original_legal_building_cells","existing":true,"extension":""},
	"wall_build": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"request_build","recipe":"stone_wall","host":"original_legal_building_cells","existing":true,"extension":""},
	"stairs_build": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"request_build","recipe":"wall_stairs","host":"original_legal_building_cells","existing":true,"extension":""},
	"intake_build": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"request_build","recipe":"intake","host":"original_legal_building_cells","existing":true,"extension":""},
	"transfer": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"transfer_items","recipe":"","host":"original_holders","existing":true,"extension":""},
	"issue_bow": {"file":"res://scripts/terrain_lab/site_person_actions.gd","anchor":"begin_equipment","recipe":"","host":"original_person_holder","existing":true,"extension":""},
	"siege_order": {"file":"res://scripts/terrain_lab/site_vehicle_transport.gd","anchor":"order_siege","recipe":"","host":"original_siege_vehicle","existing":true,"extension":""},
	"ship_order": {"file":"res://scripts/terrain_lab/site_vehicle_transport.gd","anchor":"ship_order","recipe":"","host":"original_ship","existing":true,"extension":""},
	"farm_protocol": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"_feature_work","recipe":"trial_protocol","host":"farm","existing":false,"extension":"request_farm_trial_protocol"},
	"retain_seed": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"request_feature_recipe","recipe":"retain_seed","host":"farm","existing":false,"extension":"FEATURE_RECIPES.farm.retain_seed"},
	"fiber_process": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"request_feature_recipe","recipe":"prepared_rope","host":"weaver","existing":false,"extension":"FEATURE_RECIPES.weaver.prepared_rope"},
	"survey": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"request_build","recipe":"survey_stakes","host":"original_legal_building_cells","existing":false,"extension":"request_survey_plan / FEATURES.survey_stakes"},
	"construction_method": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"_feature_work","recipe":"measured_joinery","host":"original_civil_or_defensive_feature","existing":false,"extension":"request_construction_method"},
	"charcoal_method": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"_feature_work","recipe":"controlled_fire","host":"charcoal","existing":false,"extension":"request_charcoal_method"},
	"crossbow_method": {"file":"res://scripts/terrain_lab/site_person_actions.gd","anchor":"begin_ranged_craft","recipe":"crossbow","host":"camp","existing":false,"extension":"begin_improved_crossbow_craft"},
	"leather_method": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"request_feature_recipe","recipe":"careful_tan","host":"tannery","existing":false,"extension":"FEATURE_RECIPES.tannery.careful_tan"},
	"siege_method": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"advance_siege_work","recipe":"","host":"original_siege_work_slots","existing":false,"extension":"request_siege_joinery_method"},
	"ship_method": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"_ship_feature_work","recipe":"","host":"shipyard","existing":false,"extension":"request_ship_joinery_method"},
	"fire_pot": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"ranged_craft","recipe":"fire_pot","host":"camp","existing":false,"extension":"RANGED_RECIPES.fire_pot / finite stack fire_pot"},
	"fire_pot_shot": {"file":"res://scripts/terrain_lab/site_vehicle_transport.gd","anchor":"order_siege","recipe":"fire_pot","host":"traction_trebuchet","existing":false,"extension":"order_siege ammunition selection / fire-pot contact"},
	"water_priority": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"allocate_water","recipe":"","host":"original_water_links","existing":false,"extension":"request_water_priority"},
	"irrigation": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"request_build","recipe":"irrigation_channel","host":"connected_intake_or_well","existing":false,"extension":"FEATURES.irrigation_channel / rebuild_water service graph"},
	"charcoal_adoption": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"request_feature_recipe","recipe":"controlled_fire_order","host":"charcoal","existing":false,"extension":"request_feature_batch_order"},
	"metal_chain": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"_deliver_feature_batch","recipe":"","host":"smelter_and_smithy","existing":false,"extension":"request_metal_chain_order"},
	"textile_order": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"_deliver_feature_batch","recipe":"","host":"weaver","existing":false,"extension":"request_textile_batch_order"},
	"food_order": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"transfer_items","recipe":"","host":"warehouse","existing":false,"extension":"request_warehouse_food_order"},
	"workshop_bow": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"_deliver_feature_batch","recipe":"bow","host":"smithy","existing":false,"extension":"FEATURE_RECIPES.smithy.bow / output_items atomic delivery"},
	"spares": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"ranged_craft","recipe":"ballista_spares","host":"camp","existing":false,"extension":"RANGED_RECIPES.ballista_spares / finite stack ballista_spares"},
	"spare_repair": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"advance_siege_work","recipe":"ballista_spares","host":"damaged_live_ballista","existing":false,"extension":"begin_siege_spare_repair"},
	"blueprint": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"request_build","recipe":"","host":"original_legal_building_cells","existing":false,"extension":"save_building_plan / request_building_plan"},
	"defense_order": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"request_repair","recipe":"","host":"original_defensive_feature_parts","existing":false,"extension":"request_defense_work_order"},
	"procurement": {"file":"res://scripts/terrain_lab/site_equipment_orders.gd","anchor":"set_standard","recipe":"","host":"original_nation","existing":false,"extension":"publish_procurement_spec / accept_procurement_delivery"},
	"labor_register": {"file":"res://scripts/terrain_lab/site_settlement.gd","anchor":"residents","recipe":"","host":"original_settlement_and_nation","existing":false,"extension":"register_nation_labor / authorize_labor_task"},
	"aid_order": {"file":"res://scripts/terrain_lab/site_equipment_orders.gd","anchor":"nation_duty_resolve","recipe":"","host":"original_nation_and_authorized_warehouse","existing":false,"extension":"request_aid_order"},
	"workshop_certificate": {"file":"res://scripts/terrain_lab/site_equipment_orders.gd","anchor":"nation_duty_resolve","recipe":"","host":"qualified_original_workshop","existing":false,"extension":"certify_workshop / revoke_workshop_certificate"},
	"military_order": {"file":"res://scripts/terrain_lab/site_equipment_orders.gd","anchor":"begin_issue","recipe":"","host":"certified_smithy","existing":false,"extension":"request_military_production_order"},
	"public_works": {"file":"res://scripts/terrain_lab/site_settlement.gd","anchor":"duty_resolve","recipe":"","host":"original_settlement_and_nation","existing":false,"extension":"request_public_work_order"},
	"lesson": {"file":"res://scripts/terrain_lab/site_person_actions.gd","anchor":"advance","recipe":"selected_family_skill","host":"original_teacher_and_student","existing":false,"extension":"begin_technology_lesson / generalized family skill admission"},
	"funded_course": {"file":"res://scripts/terrain_lab/site_equipment_orders.gd","anchor":"nation_duty_resolve","recipe":"","host":"original_nation_and_family","existing":false,"extension":"request_funded_course / real seat and stipend quotas"},
	"public_route": {"file":"res://scripts/terrain_lab/site_controller.gd","anchor":"begin_ship_journey","recipe":"","host":"original_route_and_vehicles","existing":false,"extension":"authorize_public_transport_route"},
	"tax": {"file":"res://scripts/terrain_lab/site_equipment_orders.gd","anchor":"nation_duty_resolve","recipe":"","host":"consenting_original_holder_and_nation","existing":false,"extension":"declare_tax_source / assess_tax / collect_tax / authorize_expenditure"},
	"mandate": {"file":"res://scripts/terrain_lab/site_settlement.gd","anchor":"duty_resolve","recipe":"","host":"original_settlement_and_nation","existing":false,"extension":"grant_settlement_mandate / revoke_settlement_mandate"},
	"siege_yard": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"siege_work_slots","recipe":"","host":"original_siege_work_slots","existing":false,"extension":"adopt_siege_yard / 6 bounded real construction slots"},
	"ship_order_plan": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"_ship_feature_work","recipe":"","host":"shipyard","existing":false,"extension":"request_shipyard_order / real work and transport seats"},
	"leather_armor": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"_deliver_feature_batch","recipe":"leather_armor","host":"tannery","existing":false,"extension":"FEATURE_RECIPES.tannery.leather_armor / output_items"},
	"iron_armor": {"file":"res://scripts/terrain_lab/site_runtime.gd","anchor":"_deliver_feature_batch","recipe":"iron_armor","host":"smithy","existing":false,"extension":"FEATURE_RECIPES.smithy.iron_armor / output_items"},
	"arsenal": {"file":"res://scripts/terrain_lab/site_equipment_orders.gd","anchor":"nation_duty_resolve","recipe":"","host":"certified_original_siege_yard_or_armor_workshop","existing":false,"extension":"request_arsenal_order / certify_arsenal_item / nation.arsenal"},
	"fleet": {"file":"res://scripts/terrain_lab/site_vehicle_transport.gd","anchor":"ship_order","recipe":"","host":"original_ships_and_corps","existing":false,"extension":"assign_ship_corps / issue_fleet_order"},
}
const _NODES := [
	{
		"id": "F01", "name": "農事記錄", "scope": "family",
		"enabled": false, "status": "candidate", "tuning_confirmed": false,
		"prerequisites": {"all":[],"any":[],"conditions":["legal_farm_trial_plots"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"control_harvest","binding":"farm_grain","repeat":1,"materials":{"seeds":1},"seconds":28800,"outputs":{"grain":8},"items":[],"policy_exception":"","worker":"same_named_original_trial_executor","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
				{"id":"bounded_comparison_harvest","binding":"farm_grain","repeat":1,"materials":{"seeds":1},"seconds":28800,"outputs":{"grain":8},"items":[],"policy_exception":"","worker":"same_named_original_trial_executor","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"farm_trial_protocol","binding":"farm_protocol","effect":{"type":"bounded_real_farm_batches","parameters":{"plots":2,"batches_per_plot":1,"record":["soil","water","inputs","actual_yield"],"changes":"指定原作物／服務格和批次上限後停止實際試驗，不是只有文字報告"}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_runtime.gd:_feature_work",
			"res://scripts/terrain_lab/site_runtime.gd:_deliver_feature_batch",
			"res://scripts/terrain_lab/site_runtime.gd:feature_work_slots",
			"res://scripts/terrain_lab/site_work_team.gd:assign",
		],
		"merge_into": "F02", "notes": "保留原種子投入、真收穫及水／肥力公式；若最後只呈現報告而無獨立試驗命令，併入F02。",
	},
	{
		"id": "F02", "name": "適地留種", "scope": "family",
		"enabled": false, "status": "candidate", "tuning_confirmed": false,
		"prerequisites": {"all":["F01"],"any":[],"conditions":["legal_farm_and_local_conditions"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"grain_baseline","binding":"farm_grain","repeat":1,"materials":{"seeds":1},"seconds":28800,"outputs":{"grain":8},"items":[],"policy_exception":"","worker":"same_named_original_trial_executor","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
				{"id":"retained_seed_trial","binding":"retain_seed","repeat":1,"materials":{"seeds":1},"seconds":28800,"outputs":{"grain":6,"seeds":2},"items":[],"policy_exception":"","worker":"same_named_original_trial_executor","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"retain_seed_plan","binding":"retain_seed","effect":{"type":"new_feature_recipe","parameters":{"input":{"seeds":1},"output":{"grain":6,"seeds":2},"cycle_minutes":480,"conditions":"原適地／供水／肥力計算，留種從同次8單位收穫內分出2，不追加水或肥力"}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_runtime.gd:FEATURE_RECIPES",
			"res://scripts/terrain_lab/site_runtime.gd:request_feature_recipe",
			"res://scripts/terrain_lab/site_runtime.gd:_feature_work",
			"res://scripts/terrain_lab/site_runtime.gd:_deliver_feature_batch",
		],
		"merge_into": "", "notes": "僅提案新配方；普通grain8收穫照舊。",
	},
	{
		"id": "F03", "name": "炭化控火", "scope": "family",
		"enabled": true, "status": "implemented", "tuning_confirmed": true,
		"prerequisites": {"all":[],"any":[],"conditions":["usable_charcoal_kiln"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"original_charcoal_trials","binding":"charcoal","repeat":3,"materials":{"wood":4},"seconds":600,"outputs":{"charcoal":2},"items":[],"policy_exception":"","worker":"same_named_original_trial_executor","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"controlled_fire","binding":"charcoal_method","effect":{"type":"personal_work_method","parameters":{"time_multiplier":0.9,"input":{"wood":4},"output":{"charcoal":2},"baseline_seconds":600,"new_seconds":540,"stack_group":"charcoal_work_time"}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_runtime.gd:_feature_work",
			"res://scripts/terrain_lab/site_runtime.gd:pay_feature_inputs",
			"res://scripts/terrain_lab/site_runtime.gd:_deliver_feature_batch",
		],
		"merge_into": "", "notes": "候選10%工時改善；只在合格本人新工作段生效，S03不得再乘一次。",
	},
	{
		"id": "F04", "name": "冶煉鍛打", "scope": "family",
		"enabled": true, "status": "implemented", "tuning_confirmed": true,
		"prerequisites": {"all":["F03"],"any":[],"conditions":["usable_smelter_and_smithy","water_and_tool_access"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"iron_from_ore","binding":"iron","repeat":1,"materials":{"iron_ore":3,"charcoal":2},"seconds":900,"outputs":{"iron":2},"items":[],"policy_exception":"","worker":"same_named_original_trial_executor","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
				{"id":"first_steel","binding":"steel","repeat":1,"materials":{"iron":2,"charcoal":2},"seconds":1200,"outputs":{"steel":1},"items":[],"policy_exception":"F04","worker":"same_named_original_trial_executor","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
				{"id":"first_steel_tools","binding":"steel_tools","repeat":1,"materials":{"steel":1,"charcoal":1,"wood":1},"seconds":720,"outputs":{"tools":2},"items":[],"policy_exception":"F04","worker":"same_named_original_trial_executor","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"steel_and_steel_tools","binding":"steel","effect":{"type":"fixed_world_recipe_gate","parameters":{"world_category":"F04","routes":["smelter:steel","smithy:steel_tools"],"actual_operator_learned":true,"old_or_unlisted_policy":"原准入／原工時，不加效果","never_gate_outputs":["iron","tools","steel"]}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_runtime.gd:request_feature_recipe",
			"res://scripts/terrain_lab/site_runtime.gd:_feature_work",
			"res://scripts/terrain_lab/site_runtime.gd:pay_feature_inputs",
			"res://scripts/terrain_lab/site_runtime.gd:_deliver_feature_batch",
		],
		"merge_into": "", "notes": "零鋼起步；具名且次數有限的原試作只豁免本F04門檻。舊世界只保留知識，不能給隱藏加成。",
	},
	{
		"id": "F05", "name": "纖維處理", "scope": "family",
		"enabled": true, "status": "implemented", "tuning_confirmed": true,
		"prerequisites": {"all":[],"any":[],"conditions":["usable_weaver"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"rope_baseline","binding":"rope","repeat":1,"materials":{"fiber":2},"seconds":480,"outputs":{"rope":2},"items":[],"policy_exception":"","worker":"same_named_original_trial_executor","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
				{"id":"fiber_preparation_trial","binding":"fiber_process","repeat":1,"materials":{"fiber":2},"seconds":384,"outputs":{"rope":2},"items":[],"policy_exception":"","worker":"same_named_original_trial_executor","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"prepared_rope","binding":"fiber_process","effect":{"type":"new_feature_recipe","parameters":{"input":{"fiber":2},"output":{"rope":2},"cycle_minutes":6.4,"baseline_recipe":"rope","baseline_cycle_minutes":8,"normal_cloth_unchanged":true}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_runtime.gd:FEATURE_RECIPES",
			"res://scripts/terrain_lab/site_runtime.gd:request_feature_recipe",
			"res://scripts/terrain_lab/site_runtime.gd:_feature_work",
		],
		"merge_into": "F06", "notes": "選擇可區分的纖維前處理繩索工序；若無實際配方差异，併F06。",
	},
	{
		"id": "F06", "name": "毛紡織造", "scope": "family",
		"enabled": true, "status": "implemented", "tuning_confirmed": true,
		"prerequisites": {"all":["F05"],"any":[],"conditions":["usable_weaver","water_and_tool_access"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"plant_cloth_baseline","binding":"plant_cloth","repeat":1,"materials":{"fiber":3},"seconds":720,"outputs":{"cloth":2},"items":[],"policy_exception":"","worker":"same_named_original_trial_executor","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
				{"id":"wool_cloth_trials","binding":"wool_cloth","repeat":3,"materials":{"wool":3},"seconds":900,"outputs":{"cloth":2},"items":[],"policy_exception":"F06","worker":"same_named_original_trial_executor","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"wool_cloth","binding":"wool_cloth","effect":{"type":"fixed_world_recipe_gate","parameters":{"world_category":"F06","routes":["weaver:wool_cloth"],"actual_operator_learned":true,"never_gate_outputs":["cloth","rope"],"old_or_unlisted_policy":"原准入／原工時"}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_runtime.gd:request_feature_recipe",
			"res://scripts/terrain_lab/site_runtime.gd:_feature_work",
			"res://scripts/terrain_lab/site_runtime.gd:_deliver_feature_batch",
		],
		"merge_into": "", "notes": "通用cloth真產物；原植物纖維布與繩索不鎖。",
	},
	{
		"id": "F07", "name": "弓作工法", "scope": "family",
		"enabled": true, "status": "implemented", "tuning_confirmed": true,
		"prerequisites": {"all":[],"any":[],"conditions":["registered_family_and_research_duty","original_camp_source_budget"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"three_true_bows","binding":"bow","repeat":3,"materials":{"wood":4,"fiber":2},"seconds":120,"outputs":{},"items":["weapon:bow_01"],"policy_exception":"","worker":"same_named_original_trial_executor","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"improved_new_bow","binding":"bow","effect":{"type":"personal_new_job_duration","parameters":{"recipe":"bow","baseline_seconds":120,"new_seconds":108,"multiplier":0.9,"old_job_unchanged":true,"cost":{"wood":4,"fiber":2},"product":"weapon:bow_01"}}},
			{"id":"family_teaching","binding":"lesson","effect":{"type":"two_original_people_lesson","parameters":{"effective_seconds":300,"materials":{},"teacher_learned":true,"student_unlearned":true,"no_bow_product":true}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_person_actions.gd:begin_ranged_craft",
			"res://scripts/terrain_lab/site_person_actions.gd:_commit",
			"res://scripts/terrain_lab/site_person_actions.gd:settle_after_contacts",
			"res://scripts/terrain_lab/site_runtime.gd:ranged_craft",
		],
		"merge_into": "", "notes": "已確認首包：三份同一人的成功收據，木材12纖維6／三把真弓，同次家族已知及本人學會；授課300，新bow108，無D10門檻。",
	},
	{
		"id": "F08", "name": "弩機裝配", "scope": "family",
		"enabled": true, "status": "implemented", "tuning_confirmed": true,
		"prerequisites": {"all":["F07"],"any":[],"conditions":["original_camp_source_budget"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"crossbow_trials","binding":"crossbow","repeat":3,"materials":{"wood":4,"iron":2,"fiber":1},"seconds":180,"outputs":{},"items":["weapon:crossbow_01"],"policy_exception":"","worker":"same_named_original_trial_executor","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"improved_crossbow","binding":"crossbow_method","effect":{"type":"personal_new_job_duration","parameters":{"baseline_seconds":180,"new_seconds":162,"cost":{"wood":4,"iron":2,"fiber":1},"product":"weapon:crossbow_01","basic_crossbow_unlocked":true}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_person_actions.gd:begin_ranged_craft",
			"res://scripts/terrain_lab/site_runtime.gd:ranged_craft",
		],
		"merge_into": "", "notes": "候選10%弩工時改善；基本製弩及S07 bow不需F08。",
	},
	{
		"id": "F09", "name": "丈量放樣", "scope": "family",
		"enabled": true, "status": "implemented", "tuning_confirmed": true,
		"prerequisites": {"all":[],"any":[],"conditions":["legal_building_site"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"place_two_real_stakes","binding":"survey","repeat":1,"materials":{"wood":2},"seconds":120,"outputs":{},"items":[],"policy_exception":"","worker":"same_named_original_trial_executor","evidence":"原測量方案、兩個真標記與重驗幾何的成功收據；不改地圖尺度或導航","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"survey_plan","binding":"survey","effect":{"type":"physical_layout_plan","parameters":{"stakes":2,"cost":{"wood":2},"seconds":120,"geometry":"原request_build完整preview+精確占地引用","map_scale_unchanged":true}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_runtime.gd:request_build",
			"res://scripts/terrain_lab/site_runtime.gd:validate_feature_layout",
			"res://scripts/terrain_lab/site_resource_view.gd:_draw_row_features",
		],
		"merge_into": "F10", "notes": "需新survey_stakes原feature布局/呈現/validator；如僅文字準備而無放樣操作，併F10。",
	},
	{
		"id": "F10", "name": "木石營造", "scope": "family",
		"enabled": true, "status": "implemented", "tuning_confirmed": true,
		"prerequisites": {"all":["F09"],"any":[],"conditions":["legal_civil_and_wall_worksites"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"house_trial","binding":"house_build","repeat":1,"materials":{"wood":8,"stone":4},"seconds":900,"outputs":{},"items":[],"policy_exception":"","worker":"same_named_original_trial_executor","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
				{"id":"stone_wall_trial","binding":"wall_build","repeat":1,"materials":{"stone":6},"seconds":720,"outputs":{},"items":[],"policy_exception":"","worker":"same_named_original_trial_executor","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"measured_joinery","binding":"construction_method","effect":{"type":"personal_new_construction_method","parameters":{"time_multiplier":0.9,"kinds":["house","stone_wall","gate","wall_stairs","siege_ladder","bridge"],"original_geometry_and_grade_caps":true,"basic_repair_unchanged":true}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_runtime.gd:request_build",
			"res://scripts/terrain_lab/site_runtime.gd:_building_work",
			"res://scripts/terrain_lab/site_runtime.gd:_feature_work",
		],
		"merge_into": "", "notes": "改良選擇鎖定新施工工時；不重新鎖已有建物／牆門梯橋。",
	},
	{
		"id": "F11", "name": "器械木作", "scope": "family",
		"enabled": true, "status": "implemented", "tuning_confirmed": true,
		"prerequisites": {"all":["F09"],"any":[],"conditions":["legal_siege_slots_and_qualified_trial_worker"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"ballista_trial","binding":"ballista_build","repeat":1,"materials":{"wood":24,"iron":12,"fiber":10},"seconds":5400,"outputs":{},"items":[],"policy_exception":"","worker":"same_named_original_trial_executor","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
				{"id":"tower_trial","binding":"tower_build","repeat":1,"materials":{"wood":120,"iron":24,"fiber":24,"cloth":20},"seconds":28800,"outputs":{},"items":[],"policy_exception":"F11","worker":"same_named_original_trial_executor","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"siege_tower","binding":"tower_build","effect":{"type":"fixed_world_master_gate","parameters":{"world_category":"F11","kind":"siege_tower","master_required_before_payment":true,"master_must_work_at_this_vehicle":true,"assistants_stop_without_master":true}}},
			{"id":"wood_joinery","binding":"siege_method","effect":{"type":"personal_siege_work_method","parameters":{"kinds":["ballista","ram","traction_trebuchet"],"time_multiplier":0.9,"basic_build_unlocked":true,"stack_group":"siege_personal_work"}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_runtime.gd:begin_siege_build",
			"res://scripts/terrain_lab/site_runtime.gd:advance_siege_work",
			"res://scripts/terrain_lab/site_runtime.gd:siege_work_slots",
		],
		"merge_into": "", "notes": "真器械完成前同次個人工作證據；共享build或他人收尾不可授技藝。",
	},
	{
		"id": "F12", "name": "配重機構", "scope": "family",
		"enabled": true, "status": "implemented", "tuning_confirmed": true,
		"prerequisites": {"all":["F11"],"any":[],"conditions":["family_original_traction_build_receipt","legal_counterweight_trial"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"counterweight_trial","binding":"counterweight_build","repeat":1,"materials":{"wood":100,"iron":24,"fiber":30,"stone":80},"seconds":21600,"outputs":{},"items":[],"policy_exception":"F12","worker":"same_named_original_trial_executor","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"counterweight_trebuchet","binding":"counterweight_build","effect":{"type":"fixed_world_master_gate","parameters":{"world_category":"F12","kind":"counterweight_trebuchet","master_required_before_payment":true,"master_must_work_at_this_vehicle":true,"assistants_stop_without_master":true}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_runtime.gd:begin_siege_build",
			"res://scripts/terrain_lab/site_runtime.gd:advance_siege_work",
			"res://scripts/terrain_lab/site_family_continuity.gd:validate_family",
		],
		"merge_into": "", "notes": "原族牽引投石機實績是必要真收據；分析/繳獲不代替此條件。基本操作與修理不鎖。",
	},
	{
		"id": "F13", "name": "舟楫工法", "scope": "family",
		"enabled": true, "status": "implemented", "tuning_confirmed": true,
		"prerequisites": {"all":["F09"],"any":[],"conditions":["usable_shipyard_and_original_team"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"original_ferry_trial","binding":"ferry_build","repeat":1,"materials":{"wood":40,"fiber":8,"iron":2},"seconds":600,"outputs":{},"items":[],"policy_exception":"","worker":"same_named_original_trial_executor","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"ship_joinery","binding":"ship_method","effect":{"type":"personal_new_ship_build_method","parameters":{"time_multiplier":0.9,"ship_kinds":["ferry","river","coastal","troop","patrol","tower"],"existing_six_ship_build_rights_unchanged":true}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_runtime.gd:begin_ship_build",
			"res://scripts/terrain_lab/site_runtime.gd:_ship_feature_work",
			"res://scripts/terrain_lab/site_runtime.gd:_launch_ship_build",
		],
		"merge_into": "", "notes": "候選工時改善，不能將原六型船當新增解鎖。",
	},
	{
		"id": "F14", "name": "鞣革", "scope": "family",
		"enabled": true, "status": "implemented", "tuning_confirmed": true,
		"prerequisites": {"all":[],"any":[],"conditions":["usable_tannery_and_water"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"original_tan_trials","binding":"leather","repeat":2,"materials":{"hide":2},"seconds":900,"outputs":{"leather":2},"items":[],"policy_exception":"","worker":"same_named_original_trial_executor","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"careful_tan","binding":"leather_method","effect":{"type":"new_feature_recipe","parameters":{"input":{"hide":2},"output":{"leather":2},"cycle_minutes":13.5,"baseline_cycle_minutes":15,"water":0.02}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_runtime.gd:FEATURE_RECIPES",
			"res://scripts/terrain_lab/site_runtime.gd:request_feature_recipe",
			"res://scripts/terrain_lab/site_runtime.gd:_feature_work",
		],
		"merge_into": "", "notes": "同原leather堆疊與供水；新工序為候選10%改良。",
	},
	{
		"id": "F15", "name": "引火配方", "scope": "family",
		"enabled": true, "status": "implemented", "tuning_confirmed": true,
		"prerequisites": {"all":["F03"],"any":[],"conditions":["usable_original_traction_trebuchet","safe_original_firing_target"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"fire_arrow_baseline","binding":"fire_arrow","repeat":1,"materials":{"arrow":5,"cloth":1,"charcoal":1},"seconds":60,"outputs":{"fire_arrow":5},"items":[],"policy_exception":"","worker":"same_named_original_trial_executor","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
				{"id":"two_fire_pots","binding":"fire_pot","repeat":2,"materials":{"pottery":1,"cloth":1,"charcoal":1},"seconds":90,"outputs":{"fire_pot":1},"items":[],"policy_exception":"","worker":"same_named_original_trial_executor","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
				{"id":"one_real_fire_pot_shot","binding":"fire_pot_shot","repeat":1,"materials":{"fire_pot":1},"seconds":0,"outputs":{},"items":[],"policy_exception":"","worker":"same_named_original_trial_executor","evidence":"原火罐消耗／彈道／命中或落地燃燒的接觸後成功收據","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"fire_pot_ammunition","binding":"fire_pot","effect":{"type":"new_ranged_recipe_and_payload","parameters":{"input":{"pottery":1,"cloth":1,"charcoal":1},"output":{"fire_pot":1},"seconds":90,"launchers":["traction_trebuchet","counterweight_trebuchet"],"fire_arrow_unlocked":true}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_runtime.gd:RANGED_RECIPES",
			"res://scripts/terrain_lab/site_runtime.gd:release_siege_ammo",
			"res://scripts/terrain_lab/site_vehicle_transport.gd:order_siege",
			"res://scripts/terrain_lab/site_combat_rules.gd:fire_contact_result",
		],
		"merge_into": "", "notes": "須新增有限fire_pot堆疊、實際裝彈/消耗、彈道及原fire contact，不能拿火箭技能旗標替代。",
	},
	{
		"id": "S01", "name": "供水排程", "scope": "settlement",
		"enabled": true, "status": "implemented", "tuning_confirmed": true,
		"prerequisites": {"all":[],"any":[],"conditions":["active_settlement_jurisdiction","working_original_water_sources"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"priority_change_and_allocate","binding":"water_priority","repeat":1,"materials":{},"seconds":300,"outputs":{},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"兩次原供水分配的真需求/供給/優先序收據，來源總量守恆","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"water_use_priority","binding":"water_priority","effect":{"type":"water_allocation_order","parameters":{"categories":["house","farm","workshop"],"camp_baseline_preserved":true,"source_capacity_unchanged":true}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_runtime.gd:allocate_water",
			"res://scripts/terrain_lab/site_runtime.gd:rebuild_water",
			"res://scripts/terrain_lab/site_settlement.gd:duty_resolve",
		],
		"merge_into": "", "notes": "沿原水源預算，只改明示用途次序，不新增水量。",
	},
	{
		"id": "S02", "name": "灌排工程", "scope": "settlement",
		"enabled": false, "status": "candidate", "tuning_confirmed": false,
		"prerequisites": {"all":["S01","F09"],"any":[],"conditions":["active_settlement_jurisdiction","connected_channel_site"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"four_cell_channel_trial","binding":"irrigation","repeat":1,"materials":{"wood":4,"stone":8},"seconds":1200,"outputs":{},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"irrigation_channel","binding":"irrigation","effect":{"type":"new_original_feature_geometry","parameters":{"per_cell_cost":{"wood":1,"stone":2},"per_cell_seconds":300,"trial_cells":4,"source_must_connect":true,"service_cells_bounded":true,"water_budget_unchanged":true}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_runtime.gd:FEATURES",
			"res://scripts/terrain_lab/site_runtime.gd:request_build",
			"res://scripts/terrain_lab/site_runtime.gd:validate_feature_layout",
			"res://scripts/terrain_lab/site_runtime.gd:rebuild_water",
			"res://scripts/terrain_lab/site_runtime.gd:allocate_water",
		],
		"merge_into": "", "notes": "須真渠道布局與服務連線；不以全圖農業加成取代工程。",
	},
	{
		"id": "S03", "name": "炭窯工序", "scope": "settlement",
		"enabled": false, "status": "candidate", "tuning_confirmed": false,
		"prerequisites": {"all":["F03"],"any":[],"conditions":["active_settlement_jurisdiction","usable_charcoal_kiln","learned_F03_operator"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"three_adopted_charcoal_batches","binding":"charcoal","repeat":3,"materials":{"wood":4},"seconds":540,"outputs":{"charcoal":2},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":["F03"],"duration_tech":"F03"},
			]},
		]},
		"operations": [
			{"id":"bounded_charcoal_order","binding":"charcoal_adoption","effect":{"type":"feature_adoption_and_batch_quota","parameters":{"feature":"charcoal","max_batches":3,"operator_skill":"F03","time_effect_from":"F03","extra_time_multiplier":1,"authorized_local_supply":true}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_runtime.gd:request_feature_recipe",
			"res://scripts/terrain_lab/site_runtime.gd:_feature_work",
			"res://scripts/terrain_lab/site_runtime.gd:_deliver_feature_batch",
		],
		"merge_into": "", "notes": "新增指定原窯/操作員/批次與供料額度的可撤銷工單；只採F03一次工時效果。",
	},
	{
		"id": "S04", "name": "冶鐵作坊協作", "scope": "settlement",
		"enabled": false, "status": "candidate", "tuning_confirmed": false,
		"prerequisites": {"all":["F04"],"any":[],"conditions":["active_settlement_jurisdiction","usable_smelter_and_smithy","legal_real_carrier"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"iron_batch","binding":"iron","repeat":1,"materials":{"iron_ore":3,"charcoal":2},"seconds":900,"outputs":{"iron":2},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
				{"id":"physical_iron_handoff","binding":"transfer","repeat":1,"materials":{"iron":2},"seconds":0,"outputs":{"iron":2},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原人從smelter領取並實際送到smithy原holder的轉移收據","required_skills":[],"duration_tech":""},
				{"id":"tools_batch","binding":"tools","repeat":1,"materials":{"iron":2,"charcoal":1,"wood":1},"seconds":720,"outputs":{"tools":1},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"metal_chain_order","binding":"metal_chain","effect":{"type":"bounded_real_process_chain","parameters":{"links":["smelter","original_carrier","smithy"],"final_product":{"tools":1},"no_virtual_material_transfer":true,"requires_S03":false}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_runtime.gd:_deliver_feature_batch",
			"res://scripts/terrain_lab/site_runtime.gd:transfer_items",
			"res://scripts/terrain_lab/site_runtime.gd:pay_feature_inputs",
			"res://scripts/terrain_lab/site_work_team.gd:assign",
		],
		"merge_into": "", "notes": "燃料可以合法外來；輸出/運輸/再加工各走原交易，無第二份製造時計。",
	},
	{
		"id": "S05", "name": "紡織工序", "scope": "settlement",
		"enabled": false, "status": "candidate", "tuning_confirmed": false,
		"prerequisites": {"all":["F06"],"any":[],"conditions":["active_settlement_jurisdiction","usable_weaver","learned_F06_operator"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"two_true_wool_batches","binding":"wool_cloth","repeat":2,"materials":{"wool":3},"seconds":900,"outputs":{"cloth":2},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":["F06"],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"textile_batch_order","binding":"textile_order","effect":{"type":"feature_adoption_and_batch_quota","parameters":{"recipe":"wool_cloth","max_batches":2,"operator_skill":"F06","extra_time_multiplier":1,"output":{"cloth":2}}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_runtime.gd:request_feature_recipe",
			"res://scripts/terrain_lab/site_runtime.gd:_feature_work",
			"res://scripts/terrain_lab/site_runtime.gd:_deliver_feature_batch",
		],
		"merge_into": "", "notes": "新增指定批次/人員/供料與停止界線；不與個人工時改良連乘。",
	},
	{
		"id": "S06", "name": "糧食乾燥與倉儲", "scope": "settlement",
		"enabled": false, "status": "candidate", "tuning_confirmed": false,
		"prerequisites": {"all":[],"any":[],"conditions":["active_settlement_jurisdiction","usable_authorized_warehouse","legal_real_carrier"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"bounded_food_replenishment","binding":"food_order","repeat":1,"materials":{"grain":8},"seconds":300,"outputs":{},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原來源到指定warehouse真轉移8糧、補貨額度/停止條件收據","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"warehouse_food_dispatch","binding":"food_order","effect":{"type":"warehouse_replenishment_and_dispatch_order","parameters":{"minimum":4,"target":8,"max_source_spend":8,"resource":"grain","explicit_source":true,"physical_delivery_required":true,"existing_food_spoilage_unchanged":true,"manual_stock_rules_unchanged":true}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_runtime.gd:transfer_items",
			"res://scripts/terrain_lab/site_runtime.gd:feature_input_inventory",
			"res://scripts/terrain_lab/site_work_team.gd:assign",
			"res://scripts/terrain_lab/site_settlement.gd:duty_resolve",
		],
		"merge_into": "", "notes": "選擇明確的新糧儲補貨/發運規則；不新增既有grain腐敗或泛國庫物權。",
	},
	{
		"id": "S07", "name": "弓弩作坊", "scope": "settlement",
		"enabled": true, "status": "implemented", "tuning_confirmed": true,
		"prerequisites": {"all":["F07"],"any":[],"conditions":["active_settlement_jurisdiction","usable_smithy","learned_F07_operator"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"two_true_workshop_bows","binding":"workshop_bow","repeat":2,"materials":{"wood":4,"fiber":2},"seconds":108,"outputs":{},"items":["weapon:bow_01"],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":["F07"],"duration_tech":"F07"},
			]},
		]},
		"operations": [
			{"id":"workshop_bow_order","binding":"workshop_bow","effect":{"type":"one_real_workshop_seat","parameters":{"host":"smithy","seats":1,"input":{"wood":4,"fiber":2},"output_item":"weapon:bow_01","baseline_seconds":120,"learned_F07_seconds":108,"crossbow_improvement_requires":"F08","basic_crossbow_unlocked":true}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_runtime.gd:FEATURE_RECIPES",
			"res://scripts/terrain_lab/site_runtime.gd:_feature_work",
			"res://scripts/terrain_lab/site_runtime.gd:_deliver_feature_batch",
			"res://scripts/terrain_lab/site_runtime.gd:create_equipment",
		],
		"merge_into": "", "notes": "需output_items及原唯一實物建立的原子尾段；原smithy本身不等於已支持軍需批量。",
	},
	{
		"id": "S08", "name": "修造與備件", "scope": "settlement",
		"enabled": false, "status": "candidate", "tuning_confirmed": false,
		"prerequisites": {"all":["S07"],"any":[],"conditions":["active_settlement_jurisdiction","damaged_live_original_ballista","original_repair_geometry_and_clearance"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"one_true_spare_kit","binding":"spares","repeat":1,"materials":{"wood":3,"iron":1,"fiber":1},"seconds":120,"outputs":{"ballista_spares":1},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
				{"id":"use_one_spare_kit","binding":"spare_repair","repeat":1,"materials":{"ballista_spares":1},"seconds":300,"outputs":{},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"ballista_spare_repair","binding":"spare_repair","effect":{"type":"optional_real_hp_repair","parameters":{"kit":"ballista_spares","kit_recipe":{"wood":3,"iron":1,"fiber":1},"kit_seconds":120,"repair_seconds":300,"max_repaired_hp":20,"target_kind":"ballista","hp_zero_refused":true,"basic_repair_unchanged":true,"personal_equipment_durability_added":false}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_runtime.gd:request_siege_repair",
			"res://scripts/terrain_lab/site_runtime.gd:advance_siege_work",
			"res://scripts/terrain_lab/site_runtime.gd:RANGED_RECIPES",
			"res://scripts/terrain_lab/site_store.gd:_validate_siege_vehicle",
		],
		"merge_into": "", "notes": "候選有限ballista_spares堆疊/製作/消耗。原建物、船舶及器械基本維修保持可用；不能修殘骸重建。",
	},
	{
		"id": "S09", "name": "工程標準化", "scope": "settlement",
		"enabled": false, "status": "candidate", "tuning_confirmed": false,
		"prerequisites": {"all":["F10"],"any":[],"conditions":["active_settlement_jurisdiction","legal_building_site"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"build_from_original_plan","binding":"house_build","repeat":1,"materials":{"wood":8,"stone":4},"seconds":900,"outputs":{},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"reusable_building_plan","binding":"blueprint","effect":{"type":"save_and_revalidate_original_geometry","parameters":{"trial_kind":"house","stores_paid_progress":false,"each_use_revalidates":["footprint","authority","workers","materials","grade_cap","navigation"]}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_runtime.gd:request_build",
			"res://scripts/terrain_lab/site_runtime.gd:validate_feature_layout",
			"res://scripts/terrain_lab/site_runtime.gd:settlement_grade_cap",
		],
		"merge_into": "S10", "notes": "藍圖只是原建築幾何候選，不搬人、不複製feature身分；如無重用命令，併S10。",
	},
	{
		"id": "S10", "name": "防禦工務", "scope": "settlement",
		"enabled": false, "status": "candidate", "tuning_confirmed": false,
		"prerequisites": {"all":["S09"],"any":[],"conditions":["active_settlement_jurisdiction","legal_wall_and_stair_geometry"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"one_wall_section","binding":"wall_build","repeat":1,"materials":{"stone":6},"seconds":720,"outputs":{},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
				{"id":"one_access_stair","binding":"stairs_build","repeat":1,"materials":{"wood":8},"seconds":720,"outputs":{},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"defense_work_plan","binding":"defense_order","effect":{"type":"bounded_defense_construction_and_maintenance","parameters":{"parts":["stone_wall","gate","wall_stairs","siege_ladder"],"real_original_workers":true,"basic_build_and_repair_unchanged":true}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_runtime.gd:request_build",
			"res://scripts/terrain_lab/site_runtime.gd:request_repair",
			"res://scripts/terrain_lab/site_work_team.gd:assign",
		],
		"merge_into": "", "notes": "新增有次序/人員/材料上限的原工程清單；已有牆門梯與損傷流程照舊。",
	},
	{
		"id": "S11", "name": "器械場", "scope": "settlement",
		"enabled": false, "status": "candidate", "tuning_confirmed": false,
		"prerequisites": {"all":["F11"],"any":[],"conditions":["settlement_level_3","active_settlement_jurisdiction","legal_siege_yard_geometry","learned_F11_master"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"one_real_ballista_yard_build","binding":"ballista_build","repeat":1,"materials":{"wood":24,"iron":12,"fiber":10},"seconds":5400,"outputs":{},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":["F11"],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"six_real_siege_slots","binding":"siege_yard","effect":{"type":"bounded_original_work_slot_expansion","parameters":{"baseline_slots":4,"new_slots":6,"every_slot_one_original_person":true,"original_task_exclusivity":true,"master_rule_preserved":true}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_runtime.gd:siege_work_slots",
			"res://scripts/terrain_lab/site_runtime.gd:begin_siege_build",
			"res://scripts/terrain_lab/site_runtime.gd:advance_siege_work",
			"res://scripts/terrain_lab/site_work_team.gd:assign",
		],
		"merge_into": "", "notes": "須原工位/預留/validator一致擴充，不造多出的人或平行建造进度。",
	},
	{
		"id": "S12", "name": "船塢工序", "scope": "settlement",
		"enabled": true, "status": "implemented", "tuning_confirmed": true,
		"prerequisites": {"all":["F13"],"any":[],"conditions":["settlement_level_2","active_settlement_jurisdiction","usable_shipyard","original_ship_workers_and_carrier","learned_F13_build_worker"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"bounded_ferry_order","binding":"ferry_build","repeat":1,"materials":{"wood":40,"fiber":8,"iron":2},"seconds":540,"outputs":{},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":["F13"],"duration_tech":"F13"},
			]},
		]},
		"operations": [
			{"id":"shipyard_supply_and_work_order","binding":"ship_order_plan","effect":{"type":"bounded_shipyard_cooperation_order","parameters":{"real_build_seats":2,"real_supply_carriers":1,"time_effect_from":"F13","extra_time_multiplier":1,"existing_six_ship_build_rights_unchanged":true,"new_ship_types":[]}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_runtime.gd:begin_ship_build",
			"res://scripts/terrain_lab/site_runtime.gd:_ship_feature_work",
			"res://scripts/terrain_lab/site_runtime.gd:_launch_ship_build",
			"res://scripts/terrain_lab/site_work_team.gd:assign",
		],
		"merge_into": "", "notes": "可見新操作為指定造船/供料協作席位、批次/材料上限與交貨，不把既有船型當收益。",
	},
	{
		"id": "S13", "name": "甲冑作坊", "scope": "settlement",
		"enabled": false, "status": "candidate", "tuning_confirmed": false,
		"prerequisites": {"all":["F14","F04"],"any":[],"conditions":["settlement_level_3","active_settlement_jurisdiction","usable_tannery_and_smithy","learned_F14_and_F04_operators"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"one_leather_armor","binding":"leather_armor","repeat":1,"materials":{"leather":4,"fiber":2},"seconds":600,"outputs":{},"items":["armor:armor_light_leather_01"],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":["F14"],"duration_tech":""},
				{"id":"one_iron_armor","binding":"iron_armor","repeat":1,"materials":{"iron":4,"leather":2,"charcoal":2},"seconds":900,"outputs":{},"items":["armor:armor_iron_01"],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":["F04"],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"leather_and_iron_armor_recipes","binding":"iron_armor","effect":{"type":"new_equipment_feature_recipes","parameters":{"leather_recipe":{"input":{"leather":4,"fiber":2},"seconds":600,"asset":"armor_light_leather_01"},"iron_recipe":{"input":{"iron":4,"leather":2,"charcoal":2},"seconds":900,"asset":"armor_iron_01"},"slot":"armor","uses_original_item_create":true}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_runtime.gd:FEATURE_RECIPES",
			"res://scripts/terrain_lab/site_runtime.gd:create_equipment",
			"res://scripts/terrain_lab/site_runtime.gd:_deliver_feature_batch",
			"res://scripts/ui/human_character_3d_editor.gd:PART_SLOTS",
		],
		"merge_into": "", "notes": "兩種原甲冑素材存在，但製作配方/實物產出/圖集准入仍須補；配裝不是造物來源。",
	},
	{
		"id": "N01", "name": "度量衡制度", "scope": "nation",
		"enabled": true, "status": "implemented", "tuning_confirmed": true,
		"prerequisites": {"all":[],"any":[],"conditions":["original_nation_and_source_authorization"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"accept_two_named_procurement_deliveries","binding":"procurement","repeat":1,"materials":{"wood":2,"grain":2},"seconds":300,"outputs":{},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"public_procurement_spec","binding":"procurement","effect":{"type":"bounded_procurement_specification","parameters":{"batch_limits":{"wood":2,"grain":2},"acceptable_original_definitions":true,"alternatives_explicit":true,"real_supplier_holder_required":true,"existing_equipment_standard_unchanged":true}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_equipment_orders.gd:nation_duty_resolve",
			"res://scripts/terrain_lab/site_equipment_orders.gd:set_standard",
			"res://scripts/terrain_lab/site_runtime.gd:transfer_items",
		],
		"merge_into": "", "notes": "發布/接受真採購規格，與原配裝標準分開；沒有獨立命令則不得收中間研究費。",
	},
	{
		"id": "N02", "name": "戶籍與勞役登記", "scope": "nation",
		"enabled": false, "status": "candidate", "tuning_confirmed": false,
		"prerequisites": {"all":[],"any":[],"conditions":["original_nation","active_settlement_jurisdiction","consenting_original_labor_person"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"register_real_labor_and_consent","binding":"labor_register","repeat":1,"materials":{},"seconds":300,"outputs":{},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原居民/國家本次勞役引用與真team.work同意正式接受收據","required_skills":[],"duration_tech":""},
				{"id":"one_registered_labor_road_cell","binding":"road_build","repeat":1,"materials":{"stone":1},"seconds":180,"outputs":{},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"register_and_dispatch_original_labor","binding":"labor_register","effect":{"type":"authorized_original_person_registry_and_task","parameters":{"people_must_exist":true,"team_work_consent_required":true,"trial_kind":"road","generates_people":false}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_settlement.gd:residents",
			"res://scripts/terrain_lab/site_settlement.gd:duty_resolve",
			"res://scripts/terrain_lab/site_work_team.gd:assign",
			"res://scripts/terrain_lab/site_runtime.gd:request_build",
		],
		"merge_into": "", "notes": "只登錄引用與國家本次勞役授權，不複製居民名冊或增加人口。",
	},
	{
		"id": "N03", "name": "糧儲與賑濟制度", "scope": "nation",
		"enabled": false, "status": "candidate", "tuning_confirmed": false,
		"prerequisites": {"all":["N01","S06"],"any":[],"conditions":["original_nation","authorized_real_food_reserve","two_original_recipients"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"deliver_two_two_grain_aid_shares","binding":"aid_order","repeat":1,"materials":{"grain":4},"seconds":300,"outputs":{},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"bounded_aid_distribution","binding":"aid_order","effect":{"type":"named_reserve_and_recipients_order","parameters":{"resource":"grain","recipient_count":2,"amount_each":2,"total_cap":4,"physical_transfer_required":true,"national_ownership_not_inferred":true}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_equipment_orders.gd:nation_duty_resolve",
			"res://scripts/terrain_lab/site_runtime.gd:transfer_items",
			"res://scripts/terrain_lab/site_sustain.gd:resupply",
		],
		"merge_into": "", "notes": "原真糧與供養端接入；預算不是國有庫存宣告。",
	},
	{
		"id": "N04", "name": "工坊驗收制度", "scope": "nation",
		"enabled": true, "status": "implemented", "tuning_confirmed": true,
		"prerequisites": {"all":["N01"],"any":["S04","S05","S07"],"conditions":["original_nation_and_workshop_inspector"]},
		"research": {"version": 1, "routes": [
			{"id": "metal", "requires_all": ["S04"], "phases": [
				{"id":"metal_product_receipt","binding":"tools","repeat":1,"materials":{"iron":2,"charcoal":1,"wood":1},"seconds":720,"outputs":{"tools":1},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
				{"id":"metal_host_inspection","binding":"workshop_certificate","repeat":1,"materials":{},"seconds":300,"outputs":{},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
			{"id": "textile", "requires_all": ["S05"], "phases": [
				{"id":"textile_product_receipt","binding":"wool_cloth","repeat":1,"materials":{"wool":3},"seconds":900,"outputs":{"cloth":2},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":["F06"],"duration_tech":""},
				{"id":"textile_host_inspection","binding":"workshop_certificate","repeat":1,"materials":{},"seconds":300,"outputs":{},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
			{"id": "bow", "requires_all": ["S07"], "phases": [
				{"id":"bow_product_receipt","binding":"workshop_bow","repeat":1,"materials":{"wood":4,"fiber":2},"seconds":108,"outputs":{},"items":["weapon:bow_01"],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":["F07"],"duration_tech":"F07"},
				{"id":"bow_host_inspection","binding":"workshop_certificate","repeat":1,"materials":{},"seconds":300,"outputs":{},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"certify_named_workshop","binding":"workshop_certificate","effect":{"type":"revisable_original_host_certificate","parameters":{"requires_one_industry":true,"not_all_three":true,"checks":["actual_host","true_product","capacity","worker","material_source","jurisdiction"],"revocation_reason":true}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_equipment_orders.gd:nation_duty_resolve",
			"res://scripts/terrain_lab/site_runtime.gd:_deliver_feature_batch",
			"res://scripts/terrain_lab/site_settlement.gd:feature_in_jurisdiction",
		],
		"merge_into": "", "notes": "只驗原作坊合格範圍；不能從名字或純技能旗標造出作坊。",
	},
	{
		"id": "N05", "name": "軍需規格制度", "scope": "nation",
		"enabled": false, "status": "candidate", "tuning_confirmed": false,
		"prerequisites": {"all":["N04","S07"],"any":[],"conditions":["original_nation_standard","certified_original_smithy","original_equipment_recipient"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"one_standard_bow_order","binding":"workshop_bow","repeat":1,"materials":{"wood":4,"fiber":2},"seconds":108,"outputs":{},"items":["weapon:bow_01"],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":["F07"],"duration_tech":"F07"},
				{"id":"original_bow_issue","binding":"issue_bow","repeat":1,"materials":{},"seconds":5,"outputs":{},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"按既有標準用原begin_equipment→原holder提交的5秒領裝收據","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"military_production_and_issue","binding":"military_order","effect":{"type":"standard_bound_finite_production_order","parameters":{"batch":1,"original_standard_reference":true,"source_cap":{"wood":4,"fiber":2},"product":"weapon:bow_01","delivery":"原begin_issue/commit","setting_existing_standard_unlocked":true}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_equipment_orders.gd:set_standard",
			"res://scripts/terrain_lab/site_equipment_orders.gd:begin_issue",
			"res://scripts/terrain_lab/site_equipment_orders.gd:commit",
			"res://scripts/terrain_lab/site_runtime.gd:_deliver_feature_batch",
		],
		"merge_into": "", "notes": "新增有配額的真生產/交付訂單，不把原設定標準功能改成要研究。",
	},
	{
		"id": "N06", "name": "公共工程編制", "scope": "nation",
		"enabled": false, "status": "candidate", "tuning_confirmed": false,
		"prerequisites": {"all":["N02","S09"],"any":[],"conditions":["original_nation","active_settlement_jurisdiction","registered_labor_and_source_budget"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"one_public_house_plan","binding":"house_build","repeat":1,"materials":{"wood":8,"stone":4},"seconds":900,"outputs":{},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"public_building_order","binding":"public_works","effect":{"type":"authorized_plan_people_and_material_order","parameters":{"plan":"S09原藍圖","real_people":true,"source_cap":{"wood":8,"stone":4},"no_global_speed_bonus":true}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_settlement.gd:duty_resolve",
			"res://scripts/terrain_lab/site_runtime.gd:request_build",
			"res://scripts/terrain_lab/site_work_team.gd:assign",
		],
		"merge_into": "", "notes": "組織原工人到原工位，保留原時計/疲勞與占地准入。",
	},
	{
		"id": "N07", "name": "技藝傳習制度", "scope": "nation",
		"enabled": false, "status": "candidate", "tuning_confirmed": false,
		"prerequisites": {"all":[],"any":["F01","F02","F03","F04","F05","F06","F07","F08","F09","F10","F11","F12","F13","F14","F15"],"conditions":["original_nation","real_master_of_selected_family_skill","registered_original_student","authorized_stipend_source"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"one_real_funded_course","binding":"funded_course","repeat":1,"materials":{"grain":2},"seconds":300,"outputs":{},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"實際同族師徒完成selected技能原課程，原糧2交教師原holder且本人學會收據；F07按300秒，其餘課程另接同規則","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"funded_real_teaching_seats","binding":"funded_course","effect":{"type":"funded_original_teacher_student_order","parameters":{"seats":2,"simultaneous_teacher_slots":1,"stipend_per_completed_course":{"grain":2},"lesson":"原SitePersonActions一师一徒","basic_family_teaching_unlocked":true}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_person_actions.gd:advance",
			"res://scripts/terrain_lab/site_person_actions.gd:settle_after_contacts",
			"res://scripts/terrain_lab/site_equipment_orders.gd:nation_duty_resolve",
			"res://scripts/terrain_lab/site_runtime.gd:transfer_items",
		],
		"merge_into": "", "notes": "國家名額及真資助與基本授徒不同；非F07教師/課程需先擴原個人技藝及課程提交，不接受技能旗標自動完成。",
	},
	{
		"id": "N08", "name": "道路驛運制度", "scope": "nation",
		"enabled": false, "status": "candidate", "tuning_confirmed": false,
		"prerequisites": {"all":["N06"],"any":[],"conditions":["original_nation","legal_original_route","original_transport_and_driver","authorized_source_and_destination"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"one_real_four_grain_route_delivery","binding":"public_route","repeat":1,"materials":{"grain":4},"seconds":0,"outputs":{},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原車船/Region行程合法到達、原時間和目的holder真收4糧收據；0表示沒有額外研究Timer，不代表瞬移","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"authorized_public_transport_route","binding":"public_route","effect":{"type":"original_route_and_delivery_order","parameters":{"resource":"grain","amount":4,"existing_speed_unchanged":true,"arrival_receipt_required":true,"travel_clock":"原World/Region/Site共同時間"}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_controller.gd:begin_ship_journey",
			"res://scripts/terrain_lab/site_vehicle_transport.gd:ship_order",
			"res://scripts/region_lab/region_travel.gd:extract",
			"res://scripts/region_lab/region_travel.gd:insert",
			"res://scripts/terrain_lab/site_runtime.gd:transfer_items",
		],
		"merge_into": "", "notes": "沿原路線/車船/旅行，制度不自動加速道路或離線研究。",
	},
	{
		"id": "N09", "name": "稅籍與財政制度", "scope": "nation",
		"enabled": false, "status": "candidate", "tuning_confirmed": false,
		"prerequisites": {"all":["N01","N02"],"any":[],"conditions":["original_nation","explicit_original_property_source_consent","authorized_recipient_holder"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"one_consented_tax_and_spending_receipt","binding":"tax","repeat":1,"materials":{"grain":1},"seconds":300,"outputs":{},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"physical_tax_and_expenditure","binding":"tax","effect":{"type":"consented_property_assessment_and_transfer","parameters":{"resource":"grain","trial_tax_cap":1,"requires_named_property_source":true,"actual_collect_and_spend_receipts":true,"all_site_inventory_not_national":true}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_equipment_orders.gd:nation_duty_resolve",
			"res://scripts/terrain_lab/site_runtime.gd:transfer_items",
			"res://scripts/terrain_lab/site_store.gd:_validate_items",
		],
		"merge_into": "", "notes": "現行營地/holder不是財政職位；正式財產/來源授權與徵收/支出命令未接入前停用，不用姓名或國籍推物權。",
	},
	{
		"id": "N10", "name": "地方行政制度", "scope": "nation",
		"enabled": false, "status": "candidate", "tuning_confirmed": false,
		"prerequisites": {"all":["N02","N09"],"any":[],"conditions":["original_nation","active_original_settlement","legal_current_local_exerciser"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"grant_limited_original_settlement_mandate","binding":"mandate","repeat":1,"materials":{},"seconds":300,"outputs":{},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原國家/聚落範圍的具名委任接受收據，再按此本次委任施工；撤銷不准重放","required_skills":[],"duration_tech":""},
				{"id":"one_delegated_local_road_cell","binding":"road_build","repeat":1,"materials":{"stone":1},"seconds":180,"outputs":{},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"limited_settlement_mandate","binding":"mandate","effect":{"type":"revocable_original_settlement_delegation","parameters":{"scope":"本Site原聚落","rights":["specified_local_road_task"],"expiry_and_revocation":true,"cross_site_requires":"N08","new_map_owner":false}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_settlement.gd:duty_resolve",
			"res://scripts/terrain_lab/site_settlement.gd:apply_office_plan",
			"res://scripts/terrain_lab/site_runtime.gd:request_build",
		],
		"merge_into": "", "notes": "本地委任不重建聚落/元首/職位；跨地版須另接原Region移交與N08。",
	},
	{
		"id": "N11", "name": "軍器監", "scope": "nation",
		"enabled": false, "status": "candidate", "tuning_confirmed": false,
		"prerequisites": {"all":["N04"],"any":["S11","S13"],"conditions":["original_nation_and_arsenal_duty"]},
		"research": {"version": 1, "routes": [
			{"id": "siege", "requires_all": ["S11"], "phases": [
				{"id":"one_real_ballista_order","binding":"ballista_build","repeat":1,"materials":{"wood":24,"iron":12,"fiber":10},"seconds":5400,"outputs":{},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
				{"id":"siege_acceptance","binding":"arsenal","repeat":1,"materials":{},"seconds":300,"outputs":{},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
			{"id": "armor", "requires_all": ["S13"], "phases": [
				{"id":"one_real_iron_armor_order","binding":"iron_armor","repeat":1,"materials":{"iron":4,"leather":2,"charcoal":2},"seconds":900,"outputs":{},"items":["armor:armor_iron_01"],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":["F04"],"duration_tech":""},
				{"id":"armor_acceptance","binding":"arsenal","repeat":1,"materials":{},"seconds":300,"outputs":{},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原 owner 成功交易／完成收據；項目＋原人＋嘗試鍵一次提交","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"arsenal_acceptance_and_order","binding":"arsenal","effect":{"type":"bounded_real_siege_or_armor_order","parameters":{"duty":"nation.arsenal","alternatives":["certified_siege_yard","certified_armor_workshop"],"true_product_required":true,"source_and_quantity_caps":true}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_equipment_orders.gd:nation_duty_resolve",
			"res://scripts/terrain_lab/site_runtime.gd:begin_siege_build",
			"res://scripts/terrain_lab/site_runtime.gd:create_equipment",
		],
		"merge_into": "", "notes": "任一器械場或甲冑作坊即可，原有國家職位不能假裝已具新軍器命令。",
	},
	{
		"id": "N12", "name": "水師編制", "scope": "nation",
		"enabled": false, "status": "candidate", "tuning_confirmed": false,
		"prerequisites": {"all":["N05","S12"],"any":[],"conditions":["original_nation_and_corps","two_original_ships","original_legal_helm_crews"]},
		"research": {"version": 1, "routes": [
			{"id": "default", "requires_all": [], "phases": [
				{"id":"register_and_order_two_original_ships","binding":"fleet","repeat":1,"materials":{},"seconds":300,"outputs":{},"items":[],"policy_exception":"","worker":"qualified_original_workers_bound_per_phase","evidence":"原兩船/國家軍團唯一編制引用及逐船合法命令、真舵手執行與停止收據","required_skills":[],"duration_tech":""},
			]},
		]},
		"operations": [
			{"id":"fleet_corps_order","binding":"fleet","effect":{"type":"original_ship_corps_membership_and_command","parameters":{"minimum_existing_ships":2,"original_person_crew_only":true,"original_ship_orders_and_sweeps":true,"existing_six_ship_operations_unlocked":true,"new_ship_types":[]}}},
		],
		"required_hooks": [
			"res://scripts/terrain_lab/site_vehicle_transport.gd:ship_order",
			"res://scripts/terrain_lab/site_vehicle_transport.gd:ship_action_query",
			"res://scripts/terrain_lab/site_equipment_orders.gd:nation_duty_resolve",
			"res://scripts/terrain_lab/terrain_army.gd:issue_corps_reposition",
		],
		"merge_into": "", "notes": "新增船編入原國家軍團及指揮；不是解鎖巡邏船/樓船，不造第二份船或船員。",
	},
]

static func ids() -> Array[String]:
	var result: Array[String] = []
	for identity: String in NODE_IDS: result.append(identity)
	return result

static func all() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _NODES: result.append(entry.duplicate(true))
	return result

static func get_node(identity: String) -> Dictionary:
	for entry: Dictionary in _NODES:
		if str(entry.id) == identity: return entry.duplicate(true)
	return {}

static func binding(identity: String) -> Dictionary:
	return _BINDINGS[identity].duplicate(true) if _BINDINGS.has(identity) else {}

static func needed_extensions(identity: String) -> Array[Dictionary]:
	var entry := get_node(identity)
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	if entry.is_empty(): return result
	for route: Dictionary in entry.research.routes:
		for phase: Dictionary in route.phases: seen[str(phase.binding)] = true
	for operation: Dictionary in entry.operations: seen[str(operation.binding)] = true
	for key: String in seen:
		var original := binding(key)
		if not bool(original.existing): result.append(original)
	return result

static func prerequisites_met(identity: String, known: Array, facts: Dictionary = {}, route_id: String = "") -> bool:
	var entry := get_node(identity)
	if entry.is_empty(): return false
	for required: String in entry.prerequisites.all:
		if not known.has(required): return false
	if not entry.prerequisites.any.is_empty():
		var found := false
		for alternative: String in entry.prerequisites.any:
			if known.has(alternative): found = true
		if not found: return false
	for condition: String in entry.prerequisites.conditions:
		if not facts.get(condition) is bool or not bool(facts[condition]): return false
	if not route_id.is_empty():
		var selected: Dictionary = {}
		for route: Dictionary in entry.research.routes:
			if str(route.id) == route_id: selected = route
		if selected.is_empty(): return false
		for required: String in selected.requires_all:
			if not known.has(required): return false
	return true

static func research_budget(identity: String, route_id: String = "default") -> Dictionary:
	var entry := get_node(identity)
	if entry.is_empty(): return {}
	var selected: Dictionary = {}
	for route: Dictionary in entry.research.routes:
		if str(route.id) == route_id: selected = route
	if selected.is_empty(): return {} # OR routes require an explicit selection.
	var external: Dictionary = {}
	var transaction_inputs: Dictionary = {}
	var available: Dictionary = {}
	var seconds := 0.0
	var receipts := 0
	for phase: Dictionary in selected.phases:
		for _attempt: int in range(int(phase.repeat)):
			for material: String in phase.materials:
				var required := int(phase.materials[material])
				transaction_inputs[material] = int(transaction_inputs.get(material, 0)) + required
				var consumed := mini(required, int(available.get(material, 0)))
				available[material] = int(available.get(material, 0)) - consumed
				if required > consumed: external[material] = int(external.get(material, 0)) + required - consumed
			for material: String in phase.outputs:
				available[material] = int(available.get(material, 0)) + int(phase.outputs[material])
			seconds += float(phase.seconds)
			receipts += 1
	for material: String in available.keys():
		if int(available[material]) == 0: available.erase(material)
	return {"route": route_id, "external_materials": external, "transaction_inputs": transaction_inputs,
		"remaining_trial_outputs": available, "seconds": seconds, "receipts_required": receipts}

static func _integer(raw: Variant, lower: int, upper: int) -> bool:
	return (raw is int or raw is float) and is_finite(float(raw)) and float(raw) == floorf(float(raw)) and float(raw) >= lower and float(raw) <= upper

static func _strings(raw: Variant, allowed: Array = [], unique: bool = true) -> bool:
	if not raw is Array: return false
	var seen: Dictionary = {}
	for value: Variant in raw:
		if not value is String or str(value).is_empty() or str(value).length() > 1024: return false
		if not allowed.is_empty() and not allowed.has(value): return false
		if unique and seen.has(value): return false
		seen[value] = true
	return true

static func _stack(raw: Variant) -> bool:
	if not raw is Dictionary: return false
	for key: Variant in raw:
		if not key is String or not MATERIAL_IDS.has(key) or not _integer(raw[key], 1, 2147483646): return false
	return true

static func _valid_phase(phase: Variant, identity: String) -> bool:
	if not phase is Dictionary or not phase.get("id") is String or str(phase.id).is_empty() \
		or not phase.get("binding") is String or not _BINDINGS.has(phase.binding) \
		or not _integer(phase.get("repeat"), 1, 16) or not _stack(phase.get("materials")) or not _stack(phase.get("outputs")) \
		or not _strings(phase.get("items"), ITEM_PRODUCTS, false) or not _strings(phase.get("required_skills"), NODE_IDS):
		return false
	if not (phase.get("seconds") is int or phase.get("seconds") is float) or not is_finite(float(phase.seconds)) or float(phase.seconds) < 0.0 or float(phase.seconds) > 100000000.0: return false
	if phase.get("worker") not in ["same_named_original_trial_executor", "qualified_original_workers_bound_per_phase"] or not phase.get("evidence") is String or str(phase.evidence).is_empty(): return false
	var required_worker := "same_named_original_trial_executor" if identity.begins_with("F") else "qualified_original_workers_bound_per_phase"
	if phase.worker != required_worker: return false
	if not phase.get("policy_exception") is String or not phase.get("duration_tech") is String: return false
	if not str(phase.policy_exception).is_empty() and (str(phase.policy_exception) != identity or not POLICY_CATEGORIES.has(identity)): return false
	if not str(phase.duration_tech).is_empty() and not phase.required_skills.has(phase.duration_tech): return false
	return true

static func validate_catalog(raw: Variant) -> bool:
	if not raw is Array or raw.size() != NODE_IDS.size(): return false
	var seen: Dictionary = {}
	for entry: Variant in raw:
		if not entry is Dictionary or not entry.get("id") is String or not NODE_IDS.has(entry.id) or seen.has(entry.id): return false
		seen[entry.id] = true
		if not entry.get("name") is String or str(entry.name).is_empty() or not entry.get("enabled") is bool or not entry.get("tuning_confirmed") is bool: return false
		var scope := "family" if str(entry.id).begins_with("F") else ("settlement" if str(entry.id).begins_with("S") else "nation")
		if entry.get("scope") != scope or entry.get("status") not in ["candidate", "p1_integration", "implemented"]: return false
		# A node opens only once accepted (status implemented); Nekki 2026-11-06 "好，驗": node-by-node acceptance from F03.
		if bool(entry.enabled) and entry.status != "implemented": return false
		# Values confirmed by Nekki: F07 (2026-10), F03 and F04 (2026-11-06 "好"); from 2026-11-06 07:02Z every accepted
		# node takes the plan's proposed values ("先照建議，之後有問題再調"), so confirmed == accepted.
		if bool(entry.tuning_confirmed) != (entry.id == "F07" or bool(entry.enabled)): return false
		if not entry.get("prerequisites") is Dictionary or not _strings(entry.prerequisites.get("all"), NODE_IDS) or not _strings(entry.prerequisites.get("any"), NODE_IDS) or not _strings(entry.prerequisites.get("conditions")): return false
		if entry.prerequisites.all.has(entry.id) or entry.prerequisites.any.has(entry.id): return false
		if not entry.get("research") is Dictionary or not _integer(entry.research.get("version"), VERSION, VERSION) or not entry.research.get("routes") is Array or entry.research.routes.is_empty(): return false
		var routes_seen: Dictionary = {}
		for route: Variant in entry.research.routes:
			if not route is Dictionary or not route.get("id") is String or str(route.id).is_empty() or routes_seen.has(route.id) or not _strings(route.get("requires_all"), NODE_IDS): return false
			routes_seen[route.id] = true
			if route.requires_all.has(entry.id) or not route.get("phases") is Array or route.phases.is_empty(): return false
			var phases_seen: Dictionary = {}
			for phase: Variant in route.phases:
				if not _valid_phase(phase, str(entry.id)) or phases_seen.has(phase.id): return false
				phases_seen[phase.id] = true
		if not entry.get("operations") is Array or entry.operations.is_empty(): return false
		var operations_seen: Dictionary = {}
		for operation: Variant in entry.operations:
			if not operation is Dictionary or not operation.get("id") is String or str(operation.id).is_empty() or operations_seen.has(operation.id) \
				or not operation.get("binding") is String or not _BINDINGS.has(operation.binding) or not operation.get("effect") is Dictionary \
				or not operation.effect.get("type") is String or str(operation.effect.type).is_empty() or not operation.effect.get("parameters") is Dictionary:
				return false
			operations_seen[operation.id] = true
		if not _strings(entry.get("required_hooks")) or entry.required_hooks.is_empty() or not entry.get("notes") is String or not entry.get("merge_into") is String: return false
		if not str(entry.merge_into).is_empty() and (not NODE_IDS.has(entry.merge_into) or entry.merge_into == entry.id): return false
	return _acyclic(raw)

static func _acyclic(raw: Array) -> bool:
	var remaining: Dictionary = {}
	for entry: Dictionary in raw:
		var dependencies: Dictionary = {}
		for required: String in entry.prerequisites.all + entry.prerequisites.any: dependencies[required] = true
		for route: Dictionary in entry.research.routes:
			for required: String in route.requires_all: dependencies[required] = true
			for phase: Dictionary in route.phases:
				for required: String in phase.required_skills: dependencies[required] = true
		remaining[str(entry.id)] = dependencies
	while not remaining.is_empty():
		var resolved: Array[String] = []
		for identity: String in remaining:
			if remaining[identity].is_empty(): resolved.append(identity)
		if resolved.is_empty(): return false
		for identity: String in resolved: remaining.erase(identity)
		for dependencies: Dictionary in remaining.values():
			for identity: String in resolved: dependencies.erase(identity)
	return true

