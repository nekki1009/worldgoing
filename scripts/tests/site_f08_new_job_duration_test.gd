extends "res://scripts/tests/site_f07_research_test.gd"
## Initial learned fields are fixture authorship, not earned research proof.
## The test uses the original PA shared request/collector and actual camp craft.

func run() -> void:
	var fixture := Fixture.new()
	var actions: SitePersonActions = fixture.actions
	_check(is_equal_approx(actions.ranged_craft_seconds(1, "crossbow"), 180.0), "Original basic crossbow remains legal at 180s")
	var first := actions.begin_ranged_craft(1, "crossbow")
	_check(first.ok and is_equal_approx(float(first.seconds), 180.0), "Actual unlearned original craft starts without F08")
	fixture.character.technology = Technology.learned_candidate({}, "F08")
	_check(is_equal_approx(float(actions._jobs["1"].duration), 180.0), "Learning cannot change an already-created original job")
	actions.cancel(1)
	var inventory: Dictionary = fixture.terrain.site.inventory
	var before := inventory.duplicate()
	var made := actions.begin_ranged_craft(1, "crossbow")
	_check(made.ok and is_equal_approx(float(made.seconds), 162.0), "The actual newly created learned F08 job selects 162s")
	fixture.character.technology = {} # Original new-job decision remains fixed.
	fixture.step(162.0)
	var committed := actions.settle_after_contacts()
	_check(committed.size() == 1 and committed[0].ok, "True original collector work commits one actual crossbow")
	var crossbows := 0
	for record: Dictionary in fixture.terrain.site.item_records.values():
		if record.definition == "weapon:crossbow_01": crossbows += 1
	_check(crossbows == 1 and int(inventory.wood) == int(before.wood) - 4 and int(inventory.iron) == int(before.iron) - 2 \
		and int(inventory.fiber) == int(before.fiber) - 1 and int(inventory.tools) == int(before.tools), "One actual item, original 4/2/1 materials, tools retained")
	_check(is_equal_approx(actions.ranged_craft_seconds(1, "crossbow"), 180.0), "The next unlearned job returns to the basic duration")
	fixture.character.technology = Technology.learned_candidate({}, "F07")
	_check(is_equal_approx(actions.ranged_craft_seconds(1, "bow"), 108.0), "Existing F07 bow duration remains 108s")
	_check(is_equal_approx(actions.ranged_craft_seconds(1, "crossbow"), 180.0), "F07 does not secretly improve crossbow")
	fixture.close()
	print("F08_NEW_ORIGINAL_CRAFT_DURATION_PASS: basic180/newlearned162/oldjobfixed/realcampitemandcost; earned research/UI/Native excluded")
	quit(0)
