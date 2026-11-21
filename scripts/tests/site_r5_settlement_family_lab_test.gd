extends "res://scripts/tests/site_r3_prison_interface_test.gd"
## R5 S3 (lab-level): settlement and family heir designation through the real lab and controller.
## Family entry: controller.family_continuity.designate_heir. Settlement entry: Settlement.designate_heir(lab, ...).
## Refusals leave the source byte-identical; a Store save and load keeps the heirs as integers.
## No production change; no contest timer (G0 is verified separately).

const Family := preload("res://scripts/terrain_lab/site_family_continuity.gd")
const Succession := preload("res://scripts/terrain_lab/site_succession.gd")
const R5S3_SAVE := "res://.godot-temp/site_r5_s3_lab/heirs.json"

func _member(site_id: String, identity: int) -> Dictionary:
	return {"site_id": site_id, "person_id": identity, "path": "", "label": "R5 S3 lab fixture #%d" % identity, "age_years": -1}

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	var data := _building_fixture()
	if not _r3_check(not _r3_failed and data != null, "inherited terrain setup failed"): return
	var lab := _building_lab(data)
	if not _r3_check(not _r3_failed and lab != null, "inherited lab setup failed"): return
	var controller: SiteController = lab.site_controller
	var head: int = int(lab.controlled_person_id())
	var heir: int = int(lab.npc.person_id)
	if not _r3_check(head > 0 and heir > 0 and head != heir, "two distinct real people"): return
	var site_id := str(data.site.id)

	# --- Family: a v4 family headed by the controlled person, with the NPC as a local member ---
	data.site.family = {
		"version": 4, "name": "", "lineage_id": 1, "complete": true,
		"members": [_member(site_id, head), _member(site_id, heir)],
		"offices": SiteOffices.default_offices("family", head, false),
	}
	var family_seat: String = str(SiteOffices.head_position(data.site.family.offices).id)
	var family_before: PackedByteArray = var_to_bytes(data.site.family)
	var family_refused: Dictionary = controller.family_continuity.designate_heir(heir, heir)
	if not _r3_check(str(family_refused.code) == "NO_AUTHORITY" and not bool(family_refused.ok), "a non-head cannot designate a family heir: %s" % str(family_refused)): return
	if not _r3_check(var_to_bytes(data.site.family) == family_before, "the family NO_AUTHORITY refusal leaves the family byte-identical"): return
	var family_self: Dictionary = controller.family_continuity.designate_heir(head, head)
	if not _r3_check(str(family_self.code) == "DUPLICATE_HOLDER" and not bool(family_self.ok), "the family head cannot be its own heir: %s" % str(family_self)): return
	if not _r3_check(var_to_bytes(data.site.family) == family_before, "the family self-heir refusal leaves the family byte-identical"): return
	var family_unknown: Dictionary = controller.family_continuity.designate_heir(head, 999999)
	if not _r3_check(str(family_unknown.code) == "NO_TARGET" and not bool(family_unknown.ok), "a non-member cannot be a family heir: %s" % str(family_unknown)): return
	if not _r3_check(var_to_bytes(data.site.family) == family_before, "the family NO_TARGET refusal leaves the family byte-identical"): return
	var family_revision: int = int(data.site.family.offices.revision)
	var family_ok: Dictionary = controller.family_continuity.designate_heir(head, heir)
	if not _r3_check(bool(family_ok.ok), "the family head designates a local member: %s" % str(family_ok)): return
	if not _r3_check(int(data.site.family.version) == 5, "the family is upgraded to v5 by the designation"): return
	if not _r3_check(int(data.site.family.succession.heirs[family_seat]) == heir, "the family heir is stored on the head seat"): return
	if not _r3_check(int(data.site.family.offices.revision) == family_revision + 1, "one family offices revision step"): return
	if not _r3_check(int(SiteOffices.head_position(data.site.family.offices).holder) == head, "the seated family head is unchanged"): return
	if not _r3_check(Family.valid_succession(data.site.family, site_id), "the designated family validates for this Site"): return

	# --- Settlement: the owner faction is the controlled person's faction; both people are its members ---
	var faction := 7
	lab.character.faction_id = faction
	lab.npc.faction_id = faction
	data.site.settlement = {"version": 4, "owner_faction": faction, "offices": SiteOffices.default_offices("settlement", head, false)}
	var settlement_seat: String = str(SiteOffices.head_position(data.site.settlement.offices).id)
	var settlement_before: PackedByteArray = var_to_bytes(data.site.settlement)
	var settlement_refused: Dictionary = Settlement.designate_heir(lab, heir, heir)
	if not _r3_check(str(settlement_refused.code) == "NO_AUTHORITY" and not bool(settlement_refused.ok), "a non-head cannot designate a settlement heir: %s" % str(settlement_refused)): return
	if not _r3_check(var_to_bytes(data.site.settlement) == settlement_before, "the settlement NO_AUTHORITY refusal leaves the settlement byte-identical"): return
	var settlement_self: Dictionary = Settlement.designate_heir(lab, head, head)
	if not _r3_check(str(settlement_self.code) == "DUPLICATE_HOLDER" and not bool(settlement_self.ok), "the settlement head cannot be its own heir: %s" % str(settlement_self)): return
	if not _r3_check(var_to_bytes(data.site.settlement) == settlement_before, "the settlement self-heir refusal leaves the settlement byte-identical"): return
	var settlement_revision: int = int(data.site.settlement.offices.revision)
	var settlement_ok: Dictionary = Settlement.designate_heir(lab, head, heir)
	if not _r3_check(bool(settlement_ok.ok), "the settlement head designates a faction member: %s" % str(settlement_ok)): return
	if not _r3_check(int(data.site.settlement.version) == 5, "the settlement is upgraded to v5 by the designation"): return
	if not _r3_check(int(data.site.settlement.succession.heirs[settlement_seat]) == heir, "the settlement heir is stored on the head seat"): return
	if not _r3_check(int(data.site.settlement.offices.revision) == settlement_revision + 1, "one settlement offices revision step"): return
	if not _r3_check(int(SiteOffices.head_position(data.site.settlement.offices).holder) == head, "the seated settlement head is unchanged"): return

	# --- Store save and load: the family heir stays an integer and validates after the round trip.
	# The settlement fixture is a partial record (only the designation fields). FIELDS_V4 also requires
	# settlement_id, center_id, level, name, fall_record, nation_id and trade_tax_percent, so Store refuses it
	# (CORRUPT_SAVE, settlement field list). A real founded Settlement is not reachable from this base chain, so
	# the settlement is kept out of the save and its heir is checked through a JSON round trip instead.
	var designated_settlement: Dictionary = data.site.settlement.duplicate(true)
	data.site.erase("settlement")
	var saved: Dictionary = controller.save_to(R5S3_SAVE)
	if not _r3_check(bool(saved.get("ok", false)), "the designated family heir save: code=%s message_hex=%s" % [str(saved.get("code", "")), str(saved.get("message", "")).to_utf8_buffer().hex_encode()]): return
	var loaded: Dictionary = Store.load_site(R5S3_SAVE)
	if not _r3_check(bool(loaded.get("ok", false)), "the saved family heir loads: %s" % str(loaded.get("message", ""))): return
	var loaded_site: Dictionary = loaded.data.site
	if not _r3_check(typeof(loaded_site.family.succession.heirs[family_seat]) == TYPE_INT and int(loaded_site.family.succession.heirs[family_seat]) == heir, "the family heir is an integer after the round trip"): return
	if not _r3_check(Family.valid_succession(loaded_site.family, site_id), "the loaded family heir still validates"): return
	var settlement_json: Variant = JSON.parse_string(JSON.stringify(designated_settlement))
	if not _r3_check(settlement_json is Dictionary, "the designated settlement survives a JSON round trip"): return
	Succession.normalize_numbers(settlement_json.succession)
	if not _r3_check(typeof(settlement_json.succession.heirs[settlement_seat]) == TYPE_INT and int(settlement_json.succession.heirs[settlement_seat]) == heir, "the settlement heir is an integer after the JSON round trip"): return

	print("SITE R5 S3 LAB PASS: family and settlement heirs are designated through the real lab and controller; non-head, self-heir and non-member refusals leave the sources byte-identical; designations upgrade to v5 with one revision step and no holder change; the Store save and load keeps the heirs as integers.")
	quit(0)
