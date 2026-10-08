extends "res://scripts/tests/site_building_ui_test.gd"
## Family offices (OFFICE_POSITIONS_AND_DUTIES_PLAN P3, 6.3, D7, D15): an
## unestablished registry keeps today's behavior; the first explicit head founds
## offices; the registry becomes the head's manual-only duty; an unfit head lets
## the controlled member name a new one; saves, AI and the position page agree.

const DutyAI = preload("res://scripts/terrain_lab/site_duty_ai.gd")
const FamilyContinuity = preload("res://scripts/terrain_lab/site_family_continuity.gd")

func _ref(data: TerrainData, identity: int, label: String) -> Dictionary:
	return {"site_id": str(data.site.id), "person_id": identity, "path": "", "label": label, "age_years": -1}

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	var data := _building_fixture()
	var lab := _building_lab(data)
	var team: TerrainArmy = lab.army
	team.roster_size = 4
	team.faction_id = 1
	assert(team.deploy_at(data, lab.character, lab.npc, [Vector2i(23, 26), Vector2i(24, 26), Vector2i(25, 26), Vector2i(26, 26)]))
	assert(team.enable_combat(false))
	team.set_process(false)
	team.settle_combat_command()
	var family: FamilyContinuity = lab.site_controller.family_continuity
	var player: int = lab.controlled_person_id()
	var elder := team.combat_identity(team.current_commander)
	var cousin := team.combat_identity(3)
	var members := [_ref(data, player, "本人"), _ref(data, elder, "伯父"), _ref(data, cousin, "堂兄")]

	# Unestablished: registry works exactly as before; no offices exist.
	assert(family.register_members(members, true).ok, "Legacy registration path unchanged")
	assert(int(data.site.family.version) == 1 and not data.site.family.has("offices"))
	assert(str(family.duty_resolve("family.roster").code) == "UNESTABLISHED")
	assert(DutyAI.review_family_personnel(family, data.site.family, player).is_empty())

	# Founding: only the controlled member names a registered, living head.
	assert(str(family.appoint_head(elder, elder).code) == "NO_AUTHORITY", "An NPC cannot crown itself")
	assert(str(family.appoint_head(player, team.combat_identity(1)).code) == "NO_AUTHORITY", "Head must be a registered member")
	var founded := family.appoint_head(player, elder)
	assert(founded.ok, str(founded))
	assert(int(data.site.family.version) == 2 and FamilyContinuity.validate_family(data.site.family, str(data.site.id)))
	var offices: Dictionary = data.site.family.offices
	assert(int(SiteOffices.head_position(offices).holder) == elder and bool(offices.duty_ai), "NPC-headed new family defaults duty AI on (D17)")
	assert(int(family.duty_resolve("family.roster").decider) == elder)
	assert(str(family.appoint_head(player, player).code) == "NO_AUTHORITY", "A fit head is not replaced by others")

	# Registry is now the head's duty; the player is refused with the seat name.
	var refused := family.register_members(members, true, player)
	assert(str(refused.code) == "NO_AUTHORITY" and str(refused.message).contains("家主"), str(refused))

	# Head-only plans; the held head cannot give away its only duty.
	assert(str(family.apply_office_plan(player, int(offices.revision), [{"op": "add", "name": "族老"}]).code) == "NO_AUTHORITY")
	var orphan := family.apply_office_plan(elder, int(offices.revision), [{"op": "add", "name": "族老", "ref": "n"}, {"op": "assign", "duty_id": "family.roster", "position_id": "n"}])
	assert(str(orphan.code) == "EMPTY_POSITION", str(orphan))
	assert(family.apply_office_plan(elder, int(offices.revision), [{"op": "add", "name": "族老"}, {"op": "rename", "position_id": str(SiteOffices.head_position(offices).id), "name": "宗主"}]).ok)
	offices = data.site.family.offices
	assert(SiteOffices.head_position(offices).name == "宗主" and offices.positions.size() == 2)
	assert(DutyAI.review_family_personnel(family, data.site.family, player).is_empty(), "No vacant duty seat: AI seats nobody and never edits the registry")

	# Unfit head: duty paused; the controlled member names a new head (D7).
	team.apply_unit_contact(team.current_commander, {"result": {"hp": 1.0, "stun": 110.0, "guard_break": false}, "shield": false})
	team.settle_combat_command()
	assert(str(family.duty_resolve("family.roster").code) == "OFFICE_PAUSED")
	assert(str(family.register_members(members, true, player).code) == "OFFICE_PAUSED")
	assert(family.appoint_head(player, player).ok)
	assert(int(family.duty_resolve("family.roster").decider) == player)

	# Re-registration by the head keeps offices (one duty only, so no other seat can be held).
	offices = data.site.family.offices
	var spare := ""
	for seat: Dictionary in offices.positions:
		if not bool(seat.head): spare = str(seat.id)
	assert(family.apply_office_plan(player, int(offices.revision), [{"op": "appoint", "position_id": spare, "person_id": cousin},
		{"op": "add", "name": "管家", "ref": "m"}]).ok == false, "Held seat with no duty is rejected")
	var kept := family.register_members([_ref(data, player, "本人"), _ref(data, elder, "伯父")], true, player)
	assert(kept.ok and int(data.site.family.version) == 2 and FamilyContinuity.validate_family(data.site.family, str(data.site.id)), str(kept))
	assert(int(SiteOffices.head_position(data.site.family.offices).holder) == player)

	# Saves: JSON round trip, legacy v1, corrupt holder.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(data.site.family))
	assert(FamilyContinuity.validate_family(saved, str(data.site.id)))
	SiteOffices.normalize_numbers(saved.offices)
	var corrupt := saved.duplicate(true)
	SiteOffices.head_position(corrupt.offices).holder = cousin
	assert(not FamilyContinuity.validate_family(corrupt, str(data.site.id)), "Holder must be a registered member")
	assert(FamilyContinuity.validate_family({"version": 1, "complete": true, "members": [_ref(data, player, "本人")]}, str(data.site.id)))

	# Position page shows the family tab with the claim action.
	lab.site_controller.open_window("team")
	var button := lab.site_controller.formal_windows.team.find_child("OfficesPage", true, false) as Button
	button.pressed.emit()
	var dialog := lab.get_node_or_null("SiteUI/OfficesDialog") as Window
	assert(dialog != null)
	var org := dialog.find_child("OfficeOrg", true, false) as OptionButton
	var found := -1
	for index: int in range(org.item_count):
		if org.get_item_text(index).begins_with("家族"): found = index
	assert(found >= 0, "Family tab listed")
	org.select(found)
	org.item_selected.emit(found)
	var seats := dialog.find_child("OfficePositions", true, false) as ItemList
	assert(seats.get_item_text(0).begins_with("宗主 ★ · 文官 · #%d" % player), seats.get_item_text(0))
	assert((dialog.find_child("OfficeClaimHead", true, false) as Button).visible)
	dialog.queue_free()
	await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_FAMILY_OFFICES_PASS: legacy unchanged, explicit founding, registry duty, head-only plans, unfit head claim, re-registration keeps offices, saves, AI, position page")
	quit(0)
