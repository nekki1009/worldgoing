extends "res://scripts/tests/site_t5_captive_production_test.gd"
## Canonical visual source candidate, NOT_RUN. Warm original mechanics fixture,
## not cold/Native/fullG06. Explicit recovery fields in inherited real capture
## setup remain that older fixture's documented initial physical boundary.

func _initialize() -> void:
	deadline=Time.get_ticks_msec()+180000
	_run.call_deferred()

func _learn_original_npc(actual_lab: TerrainLab) -> void:
	var data: TerrainData = actual_lab.terrain
	var controller: SiteController = actual_lab.site_controller
	var actions: SitePersonActions = controller.person_actions
	data.site.depot_cell = data.index(Vector2i(9,10))
	assert(actual_lab.character.place(Vector2i(8,10),true) and actual_lab.npc.place(Vector2i(9,9),true))
	var refs: Array = []
	for actor: TerrainTestCharacter in [actual_lab.character,actual_lab.npc]:
		refs.append({"site_id":str(data.site.id),"person_id":actor.person_id,"path":"","label":"原人#%d"%actor.person_id,"age_years":-1})
	assert(controller.family_continuity.register_members(refs,true,actual_lab.character.person_id).ok)
	assert(controller.family_continuity.appoint_head(actual_lab.character.person_id,actual_lab.character.person_id).ok)
	assert(actions.prepare_technology(actual_lab.character.person_id,actual_lab.npc.person_id).ok)
	assert(actions.request_technology_consent(actual_lab.character.person_id,actual_lab.npc.person_id).ok)
	assert(actions.grant_technology_budget(actual_lab.character.person_id,{"wood":12,"fiber":6}).ok)
	var bows: int = _bows(data)
	var stock: Dictionary = data.site.inventory.duplicate(true)
	for trial: int in range(3):
		assert(actions.begin_technology_trial(actual_lab.character.person_id,actual_lab.npc.person_id).ok)
		var points: int = 0
		while actions.is_busy(actual_lab.npc.person_id):
			assert(Time.get_ticks_msec()<deadline and points<5000)
			var point: Dictionary = actual_lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
			assert(point.ok and float(point.get("game_seconds",0.0))>0.0,str(point))
			points += 1
		assert(_bows(data)==bows+trial+1 and int(data.site.inventory.get("wood",0))==int(stock.wood)-4*(trial+1) and int(data.site.inventory.get("fiber",0))==int(stock.fiber)-2*(trial+1))
	assert(Technology.learned(actual_lab.npc.technology,"F07") and data.site.family.technology.known.has("F07"))
	assert(data.site.family.technology.projects[0].receipts.size()==3 and data.site.family.technology.projects[0].closed)

func _run() -> void:
	var data: TerrainData=_building_fixture()
	var actual_lab: TerrainLab=_building_lab(data)
	_learn_original_npc(actual_lab) # Three actual original F07 paid bow trials.
	_capture_original(actual_lab) # Original custody/captivity supply callback.
	var actions: SitePersonActions=actual_lab.site_controller.person_actions
	var captive: int=actual_lab.npc.person_id
	var supervisor: int=actual_lab.character.person_id
	var technology_before: PackedByteArray=_technology_bytes(actual_lab)
	var relation_before: Dictionary=data.site.captivity[str(captive)].duplicate(true)
	var stock_before: Dictionary=data.site.inventory.duplicate(true)
	var bows_before: int=_bows(data)
	var version: int=int(data.site.depot_items.version)
	var next_item: int=int(data.site.next_item)
	var guardian_fatigue: float=actual_lab.character.fatigue
	var captive_fatigue: float=actual_lab.npc.fatigue
	assert(_begin(actual_lab).ok and not actual_lab.npc.can_act())
	var job: Dictionary=actions._jobs[str(captive)]
	var before: PackedByteArray=var_to_bytes(data.site)
	assert(not actions._commit_captive_craft(job).ok and var_to_bytes(data.site)==before,"A true held source does not authorize a prospective108-second product")
	var points: int=0
	var game_seconds: float=0.0
	var source_seen: bool=false
	while actions.is_busy(captive):
		assert(Time.get_ticks_msec()<deadline and points<5000)
		var window: float=Runtime.game_seconds(TerrainLab.ACTION_STEP,float(data.site.get("combat_left",0.0)))*actual_lab.simulation_speed
		if float(job.duration)-float(job.elapsed)<=window+Fatigue.WORK_PLAN_EPS:
			var requests: Array[Dictionary]=actions.work_requests(window)
			var state_before: PackedByteArray=var_to_bytes([data.site,actual_lab.character.capture_state(),actual_lab.npc.capture_state()])
			var captured: Dictionary=actions.prepare_gd_contact_job_prefix(requests,window)
			assert(captured.ok and Runtime.validate_prepared_ranged_source(captured.prepared.held[str(captive)].ranged_source))
			assert(actions.gd_contact_job_person_ready(captive) and actions.gd_contact_job_person_ready(supervisor) and not actual_lab.npc.can_act(),"Only true SAME captive job is work-ready; original can_act remains false")
			assert(var_to_bytes([data.site,actual_lab.character.capture_state(),actual_lab.npc.capture_state()])==state_before)
			actions.finish_gd_contact_job_prefix()
			source_seen=true
		var point: Dictionary=actual_lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
		assert(point.ok and float(point.get("game_seconds",0.0))>0.0,str(point))
		game_seconds+=float(point.game_seconds)
		points+=1
	assert(source_seen and game_seconds>=108.0-0.0001 and points>1 and not actions.is_busy(supervisor))
	assert(_bows(data)==bows_before+1 and int(data.site.next_item)==next_item+1 and int(data.site.depot_items.version)==version+1)
	assert(int(data.site.inventory.wood)==int(stock_before.wood)-4 and int(data.site.inventory.fiber)==int(stock_before.fiber)-2)
	assert(data.site.item_records[str(next_item)].original_owner==captive and data.site.item_records[str(next_item)].definition=="weapon:bow_01")
	assert(actual_lab.character.fatigue>guardian_fatigue and actual_lab.npc.fatigue>captive_fatigue,"Actual joint original pools bill full worker and supervisor effort once")
	assert(data.site.captivity[str(captive)]==relation_before and actual_lab.npc.captive and not actual_lab.npc.can_act())
	assert(_technology_bytes(actual_lab)==technology_before,"T5 makes no research/teaching/analysis/learning evidence")
	before=var_to_bytes(data.site)
	assert(actions.settle_after_contacts().is_empty() and var_to_bytes(data.site)==before)
	assert(_begin(actual_lab).ok)
	var current: Dictionary=actions._jobs[str(captive)]
	var source: Dictionary=Runtime.prepare_ranged_craft(data,"bow",captive,{},false,true)
	assert(source.ok)
	var holder: Dictionary=actual_lab.npc.item_state
	actual_lab.npc.item_state=holder.duplicate(true)
	before=var_to_bytes(data.site)
	assert(not actions._captive_craft_job_context(current).ok and var_to_bytes(data.site)==before,"Equal replacement holder cannot impersonate the original captive")
	actual_lab.npc.item_state=holder
	assert(actions.stop_captive_craft(supervisor,captive).ok)
	assert(not actions.is_busy(supervisor) and not actions.is_busy(captive) and _technology_bytes(actual_lab)==technology_before)
	assert(not actions.begin_ranged_craft(captive,"bow").ok,"Typed captive work does not relax ordinary can_act/manual craft")
	actual_lab.free()
	print("T5_CAPTIVE_TRUE_POINT_TERMINAL_PASS original F07 paid learning/capture setup; true NoCombat ACTION_STEP joint worker+supervisor effort plus pure genuine held terminal-source component; finite source/factory/no-fail item batch and no research; warm GD component, Native/cold/FULL40 NOT_RUN")
	quit(0)
