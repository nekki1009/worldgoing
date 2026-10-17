extends "res://scripts/tests/site_building_ui_test.gd"
## P4 S1B: the Site counter next_lineage issues a family lineage id once, through the
## formal owner only. Covers allocation, legacy load fill, save/validation refusal of a
## reused id, and the arrival merge (max, never reissues an arriving id).

const FamilyContinuity = preload("res://scripts/terrain_lab/site_family_continuity.gd")

func _ref(site_id: String, identity: int, label: String) -> Dictionary:
	return {"site_id": site_id, "person_id": identity, "path": "", "label": label, "age_years": -1}

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
	var here := str(data.site.id)
	var player: int = lab.controlled_person_id()
	var elder := team.combat_identity(team.current_commander)

	# Version 1 family, no counter yet: the first identity takes number 1 and advances the counter.
	data.site.family = {"version": 1, "complete": true, "members": [_ref(here, player, "本人"), _ref(here, elder, "伯父")]}
	data.site.next_lineage = 1
	var before: Dictionary = data.site.family.duplicate(true)
	var refused: Dictionary = family.establish_identity(elder, "甲族")
	assert(not refused.ok and str(refused.code) == "NO_AUTHORITY", "Only the controlled member may create the family identity")
	assert(data.site.family == before and int(data.site.next_lineage) == 1, "A refusal changes neither the family nor the counter")
	var long_name: Dictionary = family.establish_identity(player, "壹".repeat(33))
	assert(not long_name.ok and str(long_name.code) == "INVALID_FAMILY_NAME", "A 33-character family name is refused")
	assert(data.site.family == before and int(data.site.next_lineage) == 1, "A refused name changes nothing")
	var made: Dictionary = family.establish_identity(player, "甲族")
	assert(made.ok, "The controlled member creates the version 4 identity")
	assert(int(data.site.family.version) == 4 and data.site.family.name == "甲族", "Created family is version 4 with its name")
	assert(int(data.site.family.lineage_id) == 1, "First allocated lineage number is 1")
	assert(int(data.site.next_lineage) == 2, "The counter advances past the issued number")
	assert(FamilyContinuity.validate_family(data.site.family, here), "The created family validates")
	var again: Dictionary = family.establish_identity(player, "乙族")
	assert(not again.ok and str(again.code) == "ALREADY_IDENTIFIED", "A version 4 family is never identified twice")
	assert(int(data.site.next_lineage) == 2 and int(data.site.family.lineage_id) == 1, "No second allocation happened")

	# Save and load: a JSON round trip keeps the counter; a legacy Site without it is filled.
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(data.site.duplicate(true)))
	SiteStore._normalize_state(parsed)
	assert(int(parsed.next_lineage) == 2 and int(parsed.family.lineage_id) == 1, "Round trip keeps the counter and lineage id as ints")
	assert(SiteStore._validate_lineage_allocator(parsed).ok, "Saved counter past the family id validates")
	var legacy: Dictionary = data.site.duplicate(true)
	legacy.erase("next_lineage")
	SiteStore._normalize_state(legacy)
	assert(int(legacy.next_lineage) == 2, "Legacy v4 Site without the counter loads at max lineage plus one")
	var legacy_v1: Dictionary = data.site.duplicate(true)
	legacy_v1.erase("next_lineage")
	legacy_v1.family = before.duplicate(true)
	SiteStore._normalize_state(legacy_v1)
	assert(int(legacy_v1.next_lineage) == 1, "Legacy Site with no version 4 identity loads at 1")
	var reused: Dictionary = data.site.duplicate(true)
	reused.next_lineage = 1
	assert(not SiteStore._validate_lineage_allocator(reused).ok, "A counter that would reissue the family id is refused on save")
	assert(SiteStore._validate_lineage_allocator({}).ok, "A Site without the key is not refused here (load fills it)")

	# Arrival merge: an arriving identity pushes the destination counter past it; never lowers it.
	var destination := {"next_lineage": 1}
	RegionTravel.merge_lineage_counter(destination, {"family": {"lineage_id": 9}})
	assert(int(destination.next_lineage) == 10, "Arriving lineage 9 reserves 10 at the destination")
	RegionTravel.merge_lineage_counter(destination, {"family": {"lineage_id": 3}})
	assert(int(destination.next_lineage) == 10, "A smaller arriving lineage never lowers the counter")
	RegionTravel.merge_lineage_counter(destination, {"family_refs": {"members": []}})
	assert(int(destination.next_lineage) == 10, "A party without a family identity leaves the counter alone")
	var no_counter := {}
	RegionTravel.merge_lineage_counter(no_counter, {"family": {"lineage_id": 4}})
	assert(int(no_counter.next_lineage) == 5, "A destination without the counter starts after the arriving id")

	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_FAMILY_LINEAGE_COUNTER_PASS: allocation once through the formal owner, legacy fill, save refusal of a reused id, arrival merge")
	quit(0)
