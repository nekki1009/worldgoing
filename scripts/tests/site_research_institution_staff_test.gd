extends SceneTree
## Research institutions stage 2 (pure owner logic): seats, daily grain, preparation accrual only
## for a paid, ready researcher beside the door, the one-researcher-day threshold, and strict
## save validation. The institution is a fixture record because formal art is still missing.

const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Institutions = preload("res://scripts/terrain_lab/site_research_institutions.gd")

var checks := 0

class FakeActions extends RefCounted:
	var people := {}
	var busy := {}
	func _person(identity: int, _require_items: bool = true) -> Dictionary:
		return people.get(identity, {})
	func _ready(person: Dictionary) -> bool:
		return not person.is_empty() and bool(person.get("ready", true))
	func is_busy(identity: int) -> bool:
		return bool(busy.get(identity, false))

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error("SITE_RESEARCH_INSTITUTION_STAFF_FAIL: " + message)
		quit(1)

func _initialize() -> void:
	var data := TerrainData.new()
	data.allocate(Vector2i(32, 32))
	SiteEnvironment.initialize(data, "research-institution-staff")
	data.site.inventory["grain"] = 3
	data.site["minute"] = 0
	data.site["family"] = {"family_id": "fam1", "technology": {"version": 2, "known": [], "holder_site_id": str(data.site.id), "epoch": 1, "next_project": 2, "active": 1,
		"projects": [{"id": 1, "epoch": 1, "tech_id": "F01", "closed": false}]}}
	data.site.features["7"] = {"kind": "craft_room", "stage": "complete", "entrance": data.index(Vector2i(10, 10)), "cells": [data.index(Vector2i(10, 9))]}
	var actions := FakeActions.new()
	actions.people = {11: {"person_id": 11, "cell": Vector2i(10, 11)}, 12: {"person_id": 12, "cell": Vector2i(10, 11)}}
	check(Institutions.set_researcher(data, "7", 11, true).ok, "first researcher takes the craft room's one seat")
	check(Institutions.set_researcher(data, "7", 12, true).code == "LIMIT", "the craft room has one seat only")
	var project: Dictionary = data.site.family.technology.projects[0]
	Institutions.advance(data, actions, 3600.0)
	check(int(data.site.inventory.grain) == 2, "day 0 pays exactly 1 grain")
	check(is_equal_approx(Institutions.preparation(data, "family", "fam1", project), 3600.0), "a paid ready researcher beside the door prepares")
	Institutions.advance(data, actions, 3600.0)
	check(int(data.site.inventory.grain) == 2, "the same day is not paid twice")
	actions.people[11].cell = Vector2i(20, 20)
	Institutions.advance(data, actions, 3600.0)
	check(is_equal_approx(Institutions.preparation(data, "family", "fam1", project), 7200.0), "away from the door nothing accrues")
	actions.people[11].cell = Vector2i(10, 11)
	actions.busy[11] = true
	Institutions.advance(data, actions, 3600.0)
	check(is_equal_approx(Institutions.preparation(data, "family", "fam1", project), 7200.0), "a busy researcher prepares nothing")
	actions.busy[11] = false
	Institutions.advance(data, actions, 79200.0)
	check(Institutions.prepared(data, "family", "fam1", project), "one researcher-day reaches the halving threshold")
	data.site.inventory["grain"] = 0
	data.site["minute"] = Institutions.DAY_MINUTES
	var before := Institutions.preparation(data, "family", "fam1", project)
	Institutions.advance(data, actions, 3600.0)
	check(is_equal_approx(Institutions.preparation(data, "family", "fam1", project), before), "an unpaid day prepares nothing")
	var people := {11: true, 12: true}
	check(Institutions.validate(data.site, people).ok, "the live record validates")
	var loaded: Dictionary = JSON.parse_string(JSON.stringify(data.site))
	Institutions.normalize(loaded)
	check(Institutions.validate(loaded, people).ok and loaded.research_institutions["7"].researchers == [11], "JSON round trip normalizes and validates")
	var broken: Dictionary = loaded.duplicate(true)
	broken.research_institutions["7"].researchers.append(12)
	check(not Institutions.validate(broken, people).ok, "more researchers than seats is refused")
	check(Institutions.set_researcher(data, "7", 11, false).ok and not Institutions.is_researcher(data, 11), "unseating frees the seat")
	print("SITE_RESEARCH_INSTITUTION_STAFF_PASS: checks=", checks, "; seats, daily grain, door presence, threshold, strict save")
	quit(0)
