extends SceneTree
## P4 S1 schema: version 4 family identity, settlement nation_id reference and
## the optional nation display name. Pure static validators and a JSON round trip
## (floats normalized the way SiteStore.normalize does); no site fixture.

const FamilyContinuity = preload("res://scripts/terrain_lab/site_family_continuity.gd")

const SITE := "p4_schema_site"

func _ref(identity: int) -> Dictionary:
	return {"site_id": SITE, "person_id": identity, "path": "", "label": "本人", "age_years": -1}

func _v4(display_name: Variant, lineage: Variant) -> Dictionary:
	return {"version": 4, "complete": true, "members": [_ref(1)], "offices": SiteOffices.default_offices("family", -1, false), "name": display_name, "lineage_id": lineage}

func _initialize() -> void:
	_run()
	print("MAP_EDITOR_P4_SCHEMA_PASS: v4 family name and lineage id, settlement nation_id reference, nation name")
	quit(0)

func _run() -> void:
	var v1 := {"version": 1, "complete": true, "members": [_ref(1)]}
	assert(FamilyContinuity.validate_family(v1, SITE), "Version 1 family stays valid")
	assert(FamilyContinuity.validate_family(_v4("甲族", 7), SITE), "Version 4 with name and lineage id is valid")
	assert(FamilyContinuity.validate_family(_v4("", 7), SITE), "Version 4 may have an empty display name")
	assert(not FamilyContinuity.validate_family(_v4("壹".repeat(33), 7), SITE), "Family name longer than 32 characters is refused")
	assert(not FamilyContinuity.validate_family(_v4(12, 7), SITE), "Non-String family name is refused")
	assert(not FamilyContinuity.validate_family(_v4("甲族", 0), SITE), "Lineage id 0 is refused")
	assert(not FamilyContinuity.validate_family(_v4("甲族", 7.5), SITE), "Fractional lineage id is refused")
	assert(not FamilyContinuity.validate_family(_v4("甲族", 2147483647), SITE), "Lineage id above the maximum is refused")
	var extra := _v4("甲族", 7)
	extra.family_id = "0123456789abcdef0123456789abcdef"
	assert(not FamilyContinuity.validate_family(extra, SITE), "Version 4 cannot carry the technology family_id")
	var no_offices := _v4("甲族", 7)
	no_offices.erase("offices")
	assert(not FamilyContinuity.validate_family(no_offices, SITE), "Version 4 requires offices")

	# JSON round trip: loaded numbers are floats; SiteStore.normalize converts the lineage id to int.
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(_v4("甲族", 7)))
	assert(parsed.lineage_id is float, "JSON loads the lineage id as a float")
	parsed.lineage_id = int(parsed.lineage_id)
	SiteOffices.normalize_numbers(parsed.offices)
	parsed.version = int(parsed.version)
	assert(FamilyContinuity.validate_family(parsed, SITE), "Round-tripped version 4 family is valid")
	assert(parsed.name == "甲族" and int(parsed.lineage_id) == 7, "Round trip keeps name and lineage id")

	# Settlement nation_id: a String equipment-nation key, null, never a trial nation.
	var nations := {"equipment_nations": {"n1": {}, "trial_team_x": {}}}
	assert(SiteSettlement.valid_nation_reference(null, {}), "Null nation_id means no nation")
	assert(SiteSettlement.valid_nation_reference("n1", nations), "Existing nation key is a valid reference")
	assert(not SiteSettlement.valid_nation_reference("n2", nations), "Unknown nation key is refused")
	assert(not SiteSettlement.valid_nation_reference("trial_team_x", nations), "Trial nation is never referenced by a settlement")
	assert(not SiteSettlement.valid_nation_reference("", nations), "Empty nation key is refused")
	assert(not SiteSettlement.valid_nation_reference(3, nations), "Integer nation_id is refused")
	assert(SiteSettlement.FIELDS_V3.has("nation_id") and not SiteSettlement.FIELDS.has("nation_id"), "Only version 3 settlement fields carry nation_id")

	# Nation display name: optional String of 1..32 characters.
	assert(SiteEquipmentOrders.valid_nation_name("甲國"), "Nation name is a valid display name")
	assert(not SiteEquipmentOrders.valid_nation_name(""), "Empty nation name is refused")
	assert(not SiteEquipmentOrders.valid_nation_name("壹".repeat(33)), "Nation name longer than 32 characters is refused")
	assert(not SiteEquipmentOrders.valid_nation_name(5), "Non-String nation name is refused")
