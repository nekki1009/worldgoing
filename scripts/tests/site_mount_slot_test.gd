extends SceneTree
# CAV-3a grid-only mount slot rules. Uses no assert() side effects: every check is recorded and reported.
# The dismount_loses_horse crowd case needs the visual crowd path and SiteMountedSoldierAtlas; it is printed as SKIP here.

const Orders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func _check(condition: bool, label: String) -> void:
	if not condition: failures.append(label)

func _data() -> TerrainData:
	var data := TerrainData.new()
	data.site = {"inventory": {}, "capacity": 8}
	var initialized := SiteRuntime.initialize_item_storage(data.site)
	_check(initialized.ok, "item storage initialized")
	return data

func _person(data: TerrainData, identity: int, appearance: Dictionary) -> Dictionary:
	var holder := {}
	var seeded := SiteRuntime.seed_person_equipment(data, holder, identity, appearance)
	_check(seeded.ok, "seed person %d" % identity)
	return holder

func _armed(weapon: String) -> Dictionary:
	var appearance := HumanCharacter3DEditor.default_appearance(0)
	appearance.parts["weapon"] = weapon
	return appearance

func run() -> void:
	_check_slot_table()
	_check_equip_consumes_horse()
	_check_unequip_returns_horse()
	_check_no_horse_stock_refused()
	_check_mounted_follows_slot()
	_check_death_loses_horse()
	_check_any_troop_kind_mounts()
	_check_save_load_keeps_slot()
	_check_original_mounted_registers_horse()
	print("SKIP dismount_loses_horse: crowd path needs the visual crowd build and SiteMountedSoldierAtlas (not run in this grid-only test)")
	if failures.is_empty():
		print("SITE MOUNT SLOT TEST PASS: mount slot listed, horse is the only legal mount item, equip draws one horse from goods, unequip returns it, refusals change nothing, mounted derived from the slot, death loses the horse, any melee/bow/crossbow weapon mounts, save/load keeps the slot")
		quit(0)
	else:
		for label: String in failures: print("FAIL " + label)
		quit(1)

func _check_slot_table() -> void:
	_check("mount" in SiteRuntime.EQUIPMENT_SLOTS, "mount slot listed in EQUIPMENT_SLOTS")
	_check(not ("mount" in SiteRuntime.APPEARANCE_EQUIPMENT_SLOTS), "mount is not an appearance part slot")
	_check(Orders.valid_definition("mount:horse_standard_01", SiteRuntime.mount_definition()), "horse is a valid mount definition")
	var wrong_asset := SiteRuntime.mount_definition()
	wrong_asset["asset"] = "longsword_01"
	_check(not Orders.valid_definition("mount:longsword_01", wrong_asset), "only the horse is a legal mount item")
	var horse_as_weapon := {"slot": "weapon", "asset": "horse_standard_01", "tint": [1.0, 1.0, 1.0, 1.0]}
	_check(not Orders.valid_definition("weapon:horse_standard_01", horse_as_weapon), "horse cannot occupy a weapon slot")

func _check_equip_consumes_horse() -> void:
	var data := _data()
	var original := HumanCharacter3DEditor.default_appearance(0)
	var holder := _person(data, 1, original)
	var cargo := {"horse": 2}
	var version := int(holder.version)
	var equipped := SiteRuntime.equip_mount(data, holder, cargo, 1, version)
	_check(equipped.ok, "equip_consumes_horse: equip ok")
	_check(int(cargo.get("horse", 0)) == 1, "equip_consumes_horse: exactly one horse drawn from goods")
	_check(SiteRuntime.mount_item_id(holder) != "", "equip_consumes_horse: mount slot holds the horse item")
	_check(int(holder.version) == version + 1, "equip_consumes_horse: holder version advanced")
	var projected := SiteRuntime.equipment_appearance(data, holder, original)
	_check(bool(projected.get("mounted", false)), "equip_consumes_horse: projection is mounted")
	_check(not bool(original.mounted), "equip_consumes_horse: original appearance untouched")

func _check_unequip_returns_horse() -> void:
	var data := _data()
	var original := HumanCharacter3DEditor.default_appearance(0)
	var holder := _person(data, 1, original)
	var cargo := {"horse": 1}
	var equipped := SiteRuntime.equip_mount(data, holder, cargo, 1, int(holder.version))
	_check(equipped.ok and not cargo.has("horse"), "unequip_returns_horse: setup drew the last horse")
	var item_id := str(equipped.get("item_id", ""))
	var back := SiteRuntime.unequip_mount(data, holder, cargo, int(holder.version))
	_check(back.ok, "unequip_returns_horse: unequip ok")
	_check(int(cargo.get("horse", 0)) == 1, "unequip_returns_horse: horse returned to goods")
	_check(SiteRuntime.mount_item_id(holder) == "" and not holder.item_ids.has(item_id), "unequip_returns_horse: slot and holder cleared")
	_check(not data.site.item_records.has(item_id), "unequip_returns_horse: item record removed")
	_check(not bool(SiteRuntime.equipment_appearance(data, holder, original).mounted), "unequip_returns_horse: projection unmounted")

func _check_no_horse_stock_refused() -> void:
	var data := _data()
	var original := HumanCharacter3DEditor.default_appearance(0)
	var holder := _person(data, 1, original)
	var snapshot: Dictionary = holder.duplicate(true)
	var empty_cargo := {}
	var refused := SiteRuntime.equip_mount(data, holder, empty_cargo, 1, int(holder.version))
	_check(refused.get("code", "") == "MATERIALS", "no_horse_stock_refused: missing goods code")
	_check(holder == snapshot and empty_cargo.is_empty(), "no_horse_stock_refused: holder and goods unchanged")
	var zero_cargo := {"horse": 0}
	var refused_zero := SiteRuntime.equip_mount(data, holder, zero_cargo, 1, int(holder.version))
	_check(not refused_zero.ok and holder == snapshot and int(zero_cargo.horse) == 0, "no_horse_stock_refused: zero goods refused")
	var stale := SiteRuntime.equip_mount(data, holder, {"horse": 1}, 1, int(holder.version) + 1)
	_check(not stale.ok and holder == snapshot, "no_horse_stock_refused: stale version refused")

func _check_mounted_follows_slot() -> void:
	var data := _data()
	var original := HumanCharacter3DEditor.default_appearance(0)
	var holder := _person(data, 1, original)
	var stale_original := original.duplicate(true)
	stale_original.mounted = true
	_check(not bool(SiteRuntime.equipment_appearance(data, holder, stale_original).mounted), "mounted_follows_slot: empty slot overrides a stale mounted flag")
	var cargo := {"horse": 2}
	var first := SiteRuntime.equip_mount(data, holder, cargo, 1, int(holder.version))
	_check(first.ok, "mounted_follows_slot: equip")
	var projected := SiteRuntime.equipment_appearance(data, holder, original)
	_check(bool(projected.mounted) and HumanCharacter3DEditor.valid_appearance(projected), "mounted_follows_slot: mounted and valid appearance")
	_check(projected.parts.size() == HumanCharacter3DEditor.PART_SLOTS.size() and not projected.parts.has("mount"), "mounted_follows_slot: mount is not a part")
	var second := SiteRuntime.equip_mount(data, holder, cargo, 1, int(holder.version))
	_check(second.get("code", "") == "OCCUPIED" and int(cargo.horse) == 1, "mounted_follows_slot: occupied slot refuses a second horse")
	var lost := SiteRuntime.lose_mount(data, holder, int(holder.version))
	_check(lost.ok and not bool(SiteRuntime.equipment_appearance(data, holder, original).mounted), "mounted_follows_slot: loss unmounts")

func _check_death_loses_horse() -> void:
	var data := _data()
	var original := HumanCharacter3DEditor.default_appearance(0)
	var holder := _person(data, 1, original)
	var cargo := {"horse": 1}
	var equipped := SiteRuntime.equip_mount(data, holder, cargo, 1, int(holder.version))
	_check(equipped.ok, "death_loses_horse: setup")
	var item_id := str(equipped.get("item_id", ""))
	var dead := SiteRuntime.lose_mount(data, holder, int(holder.version))
	_check(dead.ok, "death_loses_horse: loss ok")
	_check(SiteRuntime.mount_item_id(holder) == "" and not data.site.item_records.has(item_id), "death_loses_horse: slot emptied and horse gone")
	_check(not cargo.has("horse"), "death_loses_horse: horse not returned to goods")
	_check(not bool(SiteRuntime.equipment_appearance(data, holder, original).mounted), "death_loses_horse: unmounted after death")

func _check_any_troop_kind_mounts() -> void:
	# Troop kind is a crowd property; the grid rule is weapon-independent, so melee, bow and crossbow all mount.
	for weapon: String in ["longsword_01", "bow_01", "crossbow_01"]:
		var data := _data()
		var original := _armed(weapon)
		var holder := _person(data, 1, original)
		var cargo := {"horse": 1}
		var equipped := SiteRuntime.equip_mount(data, holder, cargo, 1, int(holder.version))
		_check(equipped.ok, "any_troop_kind_mounts: %s mounts" % weapon)
		var projected := SiteRuntime.equipment_appearance(data, holder, original)
		_check(bool(projected.get("mounted", false)) and str(projected.parts.weapon) == weapon, "any_troop_kind_mounts: %s keeps its weapon while mounted" % weapon)
		_check(HumanCharacter3DEditor.valid_appearance(projected), "any_troop_kind_mounts: %s valid appearance" % weapon)

func _check_save_load_keeps_slot() -> void:
	var data := _data()
	var original := HumanCharacter3DEditor.default_appearance(0)
	var holder := _person(data, 1, original)
	var cargo := {"horse": 1}
	var equipped := SiteRuntime.equip_mount(data, holder, cargo, 1, int(holder.version))
	_check(equipped.ok, "save_load: setup")
	var item_id := str(equipped.get("item_id", ""))
	var saved := JSON.stringify({"site": data.site, "holder": holder, "appearance": original, "cargo": cargo})
	var loaded: Dictionary = JSON.parse_string(saved)
	var loaded_holder: Dictionary = loaded.holder
	loaded_holder["version"] = int(loaded_holder.version) # JSON numbers load as floats; the holder shape needs int.
	var loaded_data := TerrainData.new()
	loaded_data.site = loaded.site
	_check(SiteRuntime.mount_item_id(loaded_holder) == item_id, "save_load: mount slot id survives")
	var projected := SiteRuntime.equipment_appearance(loaded_data, loaded_holder, loaded.appearance)
	_check(bool(projected.get("mounted", false)), "save_load: mounted survives reload")
	var lost := SiteRuntime.lose_mount(loaded_data, loaded_holder, int(loaded_holder.version))
	_check(lost.ok and not bool(SiteRuntime.equipment_appearance(loaded_data, loaded_holder, loaded.appearance).mounted), "save_load: loaded horse can be lost")

func _check_original_mounted_registers_horse() -> void:
	# An original mounted body is registered with its real horse, as its other original gear is (seed_person_equipment).
	var data := _data()
	var original := HumanCharacter3DEditor.default_appearance(0)
	original.mounted = true
	var holder := _person(data, 1, original)
	_check(SiteRuntime.mount_item_id(holder) != "", "original_mounted: seed registers the horse")
	_check(bool(SiteRuntime.equipment_appearance(data, holder, original).get("mounted", false)), "original_mounted: projection stays mounted")
