extends "res://scripts/tests/site_technology_nation_material_test.gd"
## Natural-source true Lab/body/PA point plus original Army owner components.
## Initial ordinary stock is explicit; this is not earned production or GPU proof.

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 180000
	_run.call_deferred()


func _exchange_item(lab: TerrainLab, holder: Dictionary, asset: String, owner_id: int, worn: bool = false) -> String:
	# Bodies now start with an original equipped weapon; that real item is the worn exchange source.
	if worn and holder.get("equipped", {}).has("weapon"): return str(holder.equipped.weapon)
	var made: Dictionary = Runtime.create_equipment(lab.terrain, holder, "weapon:" + asset,
		{"slot": "weapon", "asset": asset, "tint": [1.0,1.0,1.0,1.0]}, owner_id, "weapon" if worn else "")
	assert(made.ok,str(made))
	return str(made.item_id)


func _exchange_fixture(with_team: bool = false) -> Dictionary:
	var data: TerrainData = _material_natural_data()
	data.site.inventory = {"grain":100}
	data.site.capacity = 128 # Bodies now carry their original starting kit; the team return must fit the depot.
	var actual_lab: TerrainLab = _material_natural_lab(data)
	var controller: SiteController = actual_lab.site_controller
	var actions: SitePersonActions = controller.person_actions
	var orders: SiteEquipmentOrders = controller.equipment_orders
	var identity: int = int(actual_lab.controlled_person_id())
	var holder: Dictionary = actions._person(identity).holder
	var old_item: String = _exchange_item(actual_lab,holder,"longsword_01",identity,true)
	var loose_item: String = _exchange_item(actual_lab,holder,"spear_01",identity)
	var f: Dictionary = {"data":data,"lab":actual_lab,"controller":controller,"actions":actions,"orders":orders,
		"identity":identity,"old":old_item,"loose":loose_item,"team":null}
	if with_team:
		var team: TerrainArmy = _material_army(actual_lab,3)
		f.team=team
		# Named initial physical positions only, not navigation or movement proof.
		var camp: Vector2i = data.cell_from_index(int(data.site.depot_cell))
		var used: Array[Vector2i] = [actual_lab.character.terrain_cell,actual_lab.npc.terrain_cell]
		for index: int in team.combat_units.size():
			var chosen := Vector2i(-1,-1)
			for radius: int in range(1,8):
				for y: int in range(-radius,radius+1):
					for x: int in range(-radius,radius+1):
						if absi(x)+absi(y)!=radius:continue
						var cell: Vector2i=camp+Vector2i(x,y)
						if data.contains(cell) and data.is_walkable(cell) and not used.has(cell) and (index!=0 or absi(x)+absi(y)==1 and data.can_step(camp,cell)):
							chosen=cell
							break
					if chosen.x>=0:break
				if chosen.x>=0:break
			assert(chosen.x>=0)
			used.append(chosen)
			team.cells[index]=chosen
			team.combat_slots[index]=chosen
			_exchange_item(actual_lab,team.combat_units[index].item_state,"longsword_01",team.combat_identity(index),true)
			_exchange_item(actual_lab,data.site.depot_items,"spear_01",identity)
		team._rebuild_ground_cell_owners()
		var head: int=team.combat_identity(team.formal_commander)
		var controlled_head: Dictionary = controller._control_family_person(null,head)
		assert(controlled_head.ok,str(controlled_head))
		team.settle_combat_command()
		var held_order: Dictionary = team.issue_combat_order(team.current_commander,TerrainArmy.CombatOrder.HOLD) # Orders take the commander index.
		assert(held_order.ok,str(held_order))
		team.settle_combat_command()
		var members: Array=[]
		for index: int in team.combat_units.size():members.append(team.combat_identity(index))
		data.site.equipment_nations={"ordinary_exchange":{"offices":SiteOffices.default_offices("nation",head),"members":members,"standards":{}}}
		assert(orders.set_nation_culture(head,"ordinary_exchange","western").ok)
		assert(orders.set_standard(head,"ordinary_exchange","line","Original finite spear stock",{"weapon":{"definition":"weapon:spear_01"}}).ok)
		# Bounded original asset-query component. No atlas/GPU readiness claim;
		# final troop/cape/physical/current-duty guards remain the original owner.
		orders.equipment_team_apply_guard=func(person_id: int,planned: Dictionary) -> Dictionary:
			var person: Dictionary=actions._person(person_id)
			assert(not person.is_empty())
			var appearance: Dictionary=person.body.appearance.duplicate(true)
			for slot: String in Runtime.EQUIPMENT_SLOTS:appearance.parts[slot]="none"
			for slot: String in planned:
				appearance.parts[slot]=data.site.item_definitions[data.site.item_records[planned[slot]].definition].asset
			return Runtime.ok("Actual fixture asset query, not renderer admission",{"appearance":appearance})
		f.identity=head
	return f


func _exchange_bytes(f: Dictionary) -> PackedByteArray:
	var bodies: Array=[]
	if f.team!=null:bodies.append(f.team.capture_combat_state())
	return var_to_bytes([f.data.site,f.lab.character.capture_state(),f.lab.npc.capture_state(),bodies])


func _check_source_only_and_point() -> void:
	var f: Dictionary=_exchange_fixture()
	var started: Dictionary=f.orders.begin_personal(int(f.identity),"weapon",str(f.loose))
	assert(started.ok,str(started))
	var job: Dictionary=f.actions._jobs[str(int(f.identity))]
	var before: PackedByteArray=_exchange_bytes(f)
	var source: Dictionary=f.orders.prepare_equipment_change(job.order,true)
	assert(source.ok and source.source_only and source.phase.is_empty() and f.orders.validate_equipment_change(source,false).ok)
	assert(f.orders.validate_equipment_change(source).code=="SOURCE_ONLY" and _exchange_bytes(f)==before,"Pure source cannot complete a five-second original job")
	var holder: Dictionary=f.actions._person(int(f.identity)).holder
	var version: int=int(holder.version)
	var next_item: int=int(f.data.site.next_item)
	var game_before: float=float(f.data.site.minute)*60.0+float(f.data.site.phase)
	var points: int=0
	while f.actions.is_busy(int(f.identity)):
		assert(Time.get_ticks_msec()<deadline and points<100)
		f.lab._advance_original_shared_step(f.lab.ACTION_STEP)
		points+=1
	assert(holder.equipped.weapon==f.loose and holder.item_ids.has(str(f.old)) and int(holder.version)==version+1)
	assert(float(f.data.site.minute)*60.0+float(f.data.site.phase)>game_before and int(f.data.site.next_item)==next_item)
	assert(not f.orders.validate_equipment_change(source,false).ok and f.actions.settle_after_contacts().is_empty(),"Actual original point completes exactly once; old source is stale")
	f.lab.free()


func _check_callback_and_reference_refusals() -> void:
	for reason: String in ["renderer","holder","records","plan"]:
		var f: Dictionary=_exchange_fixture()
		var planned: Dictionary=f.orders.prepare(int(f.identity),{"mode":"personal","slot":"weapon","item_id":str(f.loose)})
		assert(planned.ok,str(planned))
		var prepared: Dictionary=f.orders.prepare_equipment_change(planned.order)
		assert(prepared.ok and f.orders.validate_equipment_change(prepared).ok)
		var original_holder: Dictionary=f.lab.character.item_state
		var original_records: Dictionary=f.data.site.item_records
		var original_guard: Callable=f.orders.equipment_apply_guard
		match reason:
			"renderer":f.orders.equipment_apply_guard=func(_id: int,_slots: Dictionary) -> Dictionary:return Runtime.fail("TEST_VISUAL_REFUSAL")
			"holder":f.lab.character.item_state=original_holder.duplicate(true)
			"records":f.data.site.item_records=original_records.duplicate(true)
			"plan":prepared.order.planned={}
		var before: PackedByteArray=_exchange_bytes(f)
		assert(not f.orders.validate_equipment_change(prepared).ok and _exchange_bytes(f)==before,reason+": before-cost rejection preserves all original objects and real pieces")
		assert(original_holder.equipped.weapon==f.old and int(original_records[str(f.loose)].original_owner)==int(f.identity))
		f.orders.equipment_apply_guard=original_guard
		f.lab.character.item_state=original_holder
		f.data.site.item_records=original_records
		f.lab.free()
	var f: Dictionary=_exchange_fixture()
	var planned: Dictionary=f.orders.prepare(int(f.identity),{"mode":"personal","slot":"weapon","item_id":str(f.loose)})
	assert(planned.ok)
	var original_holder: Dictionary=f.lab.character.item_state
	var original_guard: Callable=f.orders.equipment_apply_guard
	f.orders.equipment_apply_guard=func(identity: int,slots: Dictionary) -> Dictionary:
		f.lab.character.item_state=original_holder.duplicate(true)
		return original_guard.call(identity,slots)
	var snapshot: Dictionary=original_holder.duplicate(true)
	assert(not f.orders.prepare_equipment_change(planned.order).ok and original_holder==snapshot,"Callback cannot replace an equal held endpoint between source capture and first cost")
	f.orders.equipment_apply_guard=original_guard
	f.lab.character.item_state=original_holder
	f.lab.free()


func _check_forged_source_descriptors() -> void:
	var f: Dictionary=_exchange_fixture()
	var planned: Dictionary=f.orders.prepare(int(f.identity),{"mode":"personal","slot":"weapon","item_id":str(f.loose)})
	assert(planned.ok)
	var actual: Dictionary=f.orders.prepare_equipment_change(planned.order)
	assert(actual.ok and f.orders.validate_equipment_change(actual).ok)
	var foreign: Dictionary=f.actions._person(int(f.lab.npc.person_id))
	assert(not foreign.is_empty() and f.orders._ready(foreign).ok and int(foreign.person_id)!=int(f.identity))
	var before: PackedByteArray=_exchange_bytes(f)
	var forged: Dictionary=actual.duplicate(false)
	forged.source=actual.source.duplicate(false)
	forged.source.people=[{"person_id":int(foreign.person_id),"owner":foreign.owner,"body":foreign.body,"holder":foreign.holder,"cargo":foreign.cargo,
		"cell":foreign.cell,"hit":int(foreign.hit),"holder_before":foreign.holder.duplicate(true),"cargo_before":foreign.cargo.duplicate(true)}]
	assert(not f.orders.validate_equipment_change(forged).ok and _exchange_bytes(f)==before,"A different real ready NPC cannot replace the holder bound to the current Actor order")
	forged=actual.duplicate(false)
	forged.source=actual.source.duplicate(false)
	forged.source.item_refs={}
	forged.source.item_before={}
	forged.source.definition_refs={}
	forged.source.definition_before={}
	assert(not f.orders.validate_equipment_change(forged).ok and _exchange_bytes(f)==before,"Caller cannot omit snapshots for the actual referenced pieces")
	forged=actual.duplicate(false)
	forged.source=actual.source.duplicate(false)
	forged.source.mode="retire_cape"
	assert(not f.orders.validate_equipment_change(forged).ok and _exchange_bytes(f)==before,"Original retirement exception cannot be substituted into another order")
	f.lab.free()


func _check_true_team_component() -> void:
	var f: Dictionary=_exchange_fixture(true)
	var prepared_order: Dictionary=f.orders.prepare_team_issue(f.team,int(f.identity),int(f.identity),"ordinary_exchange","line",true)
	assert(prepared_order.ok,str(prepared_order))
	var order: Dictionary=prepared_order.order
	var before: PackedByteArray=_exchange_bytes(f)
	var source: Dictionary=f.orders.prepare_team_equipment_change(order,true)
	assert(source.ok and f.orders.validate_team_equipment_change(source,false).ok and f.orders.validate_team_equipment_change(source).code=="SOURCE_ONLY" and _exchange_bytes(f)==before)
	var actual: Dictionary=f.orders.prepare_team_equipment_change(order)
	assert(actual.ok and f.orders.validate_team_equipment_change(actual).ok)
	var forged: Dictionary=actual.duplicate(false)
	forged.result=actual.result.duplicate(true)
	forged.result.changed_ids.append(int(f.lab.character.person_id))
	assert(not f.orders.validate_team_equipment_change(forged).ok and _exchange_bytes(f)==before,"Changed-target notifications are derived from the original fixed order")
	var depot: Dictionary=f.data.site.depot_items
	var depot_version: int=int(depot.version)
	var next_item: int=int(f.data.site.next_item)
	var record_count: int=f.data.site.item_records.size()
	var versions: Array=[]
	for row: Dictionary in f.team.combat_units:versions.append(int(row.item_state.version))
	f.orders.publish_team_equipment_change(actual)
	assert(actual.published and int(depot.version)==depot_version+1 and int(f.data.site.next_item)==next_item and f.data.site.item_records.size()==record_count)
	for index: int in f.team.combat_units.size():
		var holder: Dictionary=f.team.combat_units[index].item_state
		assert(int(holder.version)==int(versions[index])+1 and f.data.site.item_records[holder.equipped.weapon].holder==str(holder.holder))
	assert(not f.orders.validate_team_equipment_change(actual).ok and not f.orders.validate_team_equipment_change(source,false).ok,"One whole atomic source/publisher, not two conflicting transfers or replay")
	_cleanup_fixture(f.lab,f.team)


func _run() -> void:
	_check_source_only_and_point()
	_check_callback_and_reference_refusals()
	_check_forged_source_descriptors()
	_check_true_team_component()
	print("EQUIPMENT_ORIGINAL_PREPARED_EXCHANGE_PASS: original natural Lab/body personal5s true shared NoCombat point; pure source-only cannot publish; original stock/items/versions conserved; renderer and equal-ref/plan refusal before cost; actual finite Army team simultaneous exchange source component with original asset query, no GPU or Native/melee/cold claim")
	quit(0)
