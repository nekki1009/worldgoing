// G4 logistics convoy contract: anchor movement, crew steering, turns, crew loss, removal, save / load and refusals.
#include "../src/crowd_core.hpp"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <limits>
#include <string>
#include <vector>

using namespace wg;
static int checks = 0, failures = 0;
static const char *test_case = "setup";
#define REQUIRE(c) do { ++checks; if (!(c)) { ++failures; std::fprintf(stderr, "FAIL %s line %d: %s\n", test_case, __LINE__, #c); } } while (false)

static const float DT = 1.f / 30.f;
static int cell(int x, int y) { return y * 40 + x; }
static void close_to(double a, double b, double tol) { REQUIRE(std::fabs(a - b) <= tol); }
static void step(World &w) { REQUIRE(w.step_clock(DT, 0, 0)); }
static void place(World &w, int i, float x, float y) {
	auto s = w.get_soldier_state(i);
	s.x = x; s.y = y;
	w.set_soldier_state(i, s);
}

// Flat 40 x 40 ground; wall_x >= 0 makes that whole column unwalkable. One formation far from the routes below
// holds three soldiers (ids 0, 1, 2); soldiers 0 and 1 are the convoy crew in the tests that use one.
static void setup(World &w, int wall_x = -1, int size = 40) {
	w.terrain.allocate(size, size);
	if (wall_x >= 0) for (int y = 0; y < size; ++y) w.terrain.flags[w.terrain.idx(wall_x, y)] = 0;
	w.terrain.base_height = w.terrain.height;
	w.cfg.ai = false; w.cfg.auto_capture = false; w.cfg.rescue_seek_cells = 0; w.cfg.bleed_per_game_hour = 0;
	const int f = w.add_formation(0, 30.5f, 30.5f, 0, 3, 1, T_MELEE, 0);
	rules::Equip e; e.family = rules::F_LONGSWORD; e.material = rules::M_IRON;
	w.add_soldier(f, e, R_CAPTAIN, 1001);
	w.add_soldier(f, e, R_REGULAR, 1002);
	w.add_soldier(f, e, R_REGULAR, 1003);
	w.finalize();
	for (auto &formation : w.formations) formation.ai_enabled = false;
}

// Anchor at (5.5, 5.5) facing +x; crew 0 one cell behind it, crew 1 two cells behind, both already on their slots.
static int straight_convoy(World &w) {
	const int id = w.add_convoy(5.5f, 5.5f, 0.f);
	REQUIRE(id > 0);
	REQUIRE(w.convoy_set_crew(id, 0, -1, 0, true));
	REQUIRE(w.convoy_set_crew(id, 1, -2, 0, true));
	place(w, 0, 4.5f, 5.5f);
	place(w, 1, 3.5f, 5.5f);
	return id;
}

static void straight_line_five_cells() {
	test_case = "straight line of five cells: the convoy completes and every crew member arrives on its slot";
	World w(1); setup(w);
	const int id = straight_convoy(w);
	REQUIRE(w.convoy_order_goal(id, 10.5f, 5.5f, 0.f));
	ConvoyState st{};
	bool done = false;
	for (int t = 0; t < 2400 && !done; ++t) {
		step(w);
		REQUIRE(w.convoy_state(id, st));
		done = st.complete != 0;
	}
	REQUIRE(done);
	REQUIRE(st.stalled == 0);
	for (int t = 0; t < 60; ++t) step(w); // two seconds: the crew close the last gap to their slots
	REQUIRE(w.convoy_state(id, st));
	close_to(st.x, 10.5, 1e-4); close_to(st.y, 5.5, 1e-4); close_to(st.facing, 0.0, 1e-3);
	REQUIRE(st.complete == 1 && st.moving == 0 && st.stalled == 0);
	close_to(w.px[0], 9.5, 0.05); close_to(w.py[0], 5.5, 0.05);
	close_to(w.px[1], 8.5, 0.05); close_to(w.py[1], 5.5, 0.05);
	REQUIRE(w.validate());
}

static void ninety_degree_turn() {
	test_case = "ninety-degree route: the facing turns onto the route and finishes on the goal facing";
	World w(1); setup(w);
	const int id = straight_convoy(w);
	const float goal_facing = 0.5f * kPi;
	REQUIRE(w.convoy_order_goal(id, 5.5f, 10.5f, goal_facing));
	ConvoyState st{};
	double max_facing = 0;
	bool done = false;
	for (int t = 0; t < 2400 && !done; ++t) {
		step(w);
		REQUIRE(w.convoy_state(id, st));
		max_facing = std::max(max_facing, st.facing);
		done = st.complete != 0;
	}
	REQUIRE(done);
	REQUIRE(max_facing > 1.0); // the anchor turned about ninety degrees onto its southward heading
	for (int t = 0; t < 60; ++t) step(w);
	REQUIRE(w.convoy_state(id, st));
	close_to(st.x, 5.5, 1e-4); close_to(st.y, 10.5, 1e-4); close_to(st.facing, goal_facing, 1e-3);
	// crew stand at anchor + offset rotated by the facing: behind a southward anchor is north of it
	close_to(w.px[0], 5.5, 0.05); close_to(w.py[0], 9.5, 0.05);
	close_to(w.px[1], 5.5, 0.05); close_to(w.py[1], 8.5, 0.05);
	REQUIRE(w.validate());
}

static void crew_down_stalls_the_anchor() {
	test_case = "a crew member knocked out mid-route stalls the anchor and the convoy reports it";
	World w(1); setup(w);
	const int id = straight_convoy(w);
	REQUIRE(w.convoy_order_goal(id, 10.5f, 5.5f, 0.f));
	for (int t = 0; t < 20; ++t) step(w);
	ConvoyState st{};
	REQUIRE(w.convoy_state(id, st) && st.stalled == 0 && st.x > 5.6);
	auto down = w.get_soldier_state(0);
	down.ko = 30.0; // game-time knockout; the steps here pass no game time
	w.set_soldier_state(0, down);
	REQUIRE(!w.can_act(0));
	step(w);
	REQUIRE(w.convoy_state(id, st) && st.stalled == 1 && st.complete == 0 && st.moving == 0);
	const double stop_x = st.x, stop_y = st.y;
	const float crew_x = w.px[0], crew_y = w.py[0];
	for (int t = 0; t < 120; ++t) step(w);
	REQUIRE(w.convoy_state(id, st) && st.stalled == 1);
	REQUIRE(st.x == stop_x && st.y == stop_y); // the anchor does not move while crew is down
	REQUIRE(w.px[0] == crew_x && w.py[0] == crew_y); // the downed member stays where it fell
	REQUIRE(w.validate());
}

static void removal_returns_crew_to_ordinary_behaviour() {
	test_case = "convoy_remove releases its crew to ordinary formation behaviour";
	World w(1); setup(w);
	const int id = straight_convoy(w);
	REQUIRE(w.convoy_order_goal(id, 10.5f, 5.5f, 0.f));
	for (int t = 0; t < 10; ++t) step(w);
	REQUIRE(w.is_convoy_crew(0) && w.is_crewed(0));
	REQUIRE(w.convoy_remove(id));
	REQUIRE(!w.is_convoy_crew(0) && !w.is_convoy_crew(1) && !w.is_crewed(0));
	ConvoyState st{};
	REQUIRE(!w.convoy_state(id, st));
	REQUIRE(!w.convoy_remove(id));
	const float x0 = w.px[0], y0 = w.py[0];
	// The formation holds its centre at (30.5, 30.5), far from the crew: as an ordinary member crew 0 walks to its slot.
	for (int t = 0; t < 90; ++t) step(w);
	REQUIRE(std::hypot(w.px[0] - x0, w.py[0] - y0) > 1.0);
	REQUIRE(w.validate());
}

static void crew_ignore_ordinary_orders() {
	test_case = "crew stay on convoy slots while the formation is ordered elsewhere";
	World w(1); setup(w);
	straight_convoy(w); // no goal: the convoy holds
	w.order_move(0, 30.5f, 10.5f, 0.f);
	for (int t = 0; t < 60; ++t) step(w);
	close_to(w.px[0], 4.5, 0.02); close_to(w.py[0], 5.5, 0.02);
	close_to(w.px[1], 3.5, 0.02); close_to(w.py[1], 5.5, 0.02);
	REQUIRE(w.py[2] < 29.0); // a non-crew member follows the formation order north
	REQUIRE(w.validate());
}

static void save_load_mid_route_matches() {
	test_case = "save and load mid-route: identical hash, then identical steps";
	World w(1); setup(w);
	const int id = straight_convoy(w);
	REQUIRE(w.convoy_order_goal(id, 10.5f, 5.5f, 0.f));
	for (int t = 0; t < 25; ++t) step(w);
	ConvoyState before{};
	REQUIRE(w.convoy_state(id, before) && before.moving == 1);
	const std::vector<uint8_t> blob = w.save();
	REQUIRE(!blob.empty());
	World loaded(1);
	REQUIRE(loaded.load(blob));
	REQUIRE(loaded.state_hash() == w.state_hash());
	REQUIRE(loaded.save() == blob); // byte-identical round trip
	ConvoyState restored{};
	REQUIRE(loaded.convoy_state(id, restored) && restored.x == before.x && restored.y == before.y && restored.facing == before.facing);
	for (int t = 0; t < 60; ++t) {
		step(w);
		step(loaded);
		REQUIRE(loaded.state_hash() == w.state_hash());
	}
	REQUIRE(w.validate() && loaded.validate());
}

static void invalid_requests_change_nothing() {
	test_case = "invalid ids and arguments are refused with no state change";
	World w(1); setup(w, 20);
	const float nan = std::numeric_limits<float>::quiet_NaN();
	const uint64_t empty = w.state_hash();
	REQUIRE(w.add_convoy(nan, 5.5f, 0.f) == 0);
	REQUIRE(w.add_convoy(5.5f, nan, 0.f) == 0);
	REQUIRE(w.add_convoy(5.5f, 5.5f, nan) == 0);
	REQUIRE(w.add_convoy(-1.f, 5.5f, 0.f) == 0);
	REQUIRE(w.add_convoy(40.5f, 5.5f, 0.f) == 0);
	REQUIRE(w.add_convoy(20.5f, 5.5f, 0.f) == 0); // the wall column is not walkable
	REQUIRE(w.state_hash() == empty);
	World unfinished(1);
	REQUIRE(unfinished.add_convoy(5.5f, 5.5f, 0.f) == 0); // refused before finalize

	const int id = w.add_convoy(5.5f, 5.5f, 0.f);
	REQUIRE(id == 1);
	REQUIRE(w.state_hash() != empty);
	const uint64_t with_convoy = w.state_hash();
	REQUIRE(!w.convoy_set_crew(id + 1, 0, -1, 0, true)); // unknown convoy
	REQUIRE(!w.convoy_set_crew(id, 99, -1, 0, true));    // no such soldier
	REQUIRE(!w.convoy_set_crew(id, -1, -1, 0, true));
	REQUIRE(!w.convoy_set_crew(id, 0, 9, 0, true));      // offset outside the crew window
	REQUIRE(!w.convoy_set_crew(id, 0, 0, 0, false));     // not crew yet
	REQUIRE(w.state_hash() == with_convoy);
	REQUIRE(w.convoy_set_crew(id, 0, -1, 0, true));
	REQUIRE(w.convoy_set_crew(id, 1, -2, 0, true));
	const int other = w.add_convoy(5.5f, 8.5f, 0.f);
	REQUIRE(other == 2);
	const uint64_t crewed = w.state_hash();
	REQUIRE(!w.convoy_set_crew(other, 0, -1, 0, true)); // already crew of convoy 1
	REQUIRE(w.state_hash() == crewed);
	REQUIRE(w.set_siege_crew(2, true));
	const uint64_t siege = w.state_hash();
	REQUIRE(!w.convoy_set_crew(id, 2, -1, 0, true)); // siege crew cannot also be convoy crew
	REQUIRE(!w.set_siege_crew(0, true));             // convoy crew cannot also be siege crew
	REQUIRE(w.state_hash() == siege);
	REQUIRE(w.set_siege_crew(2, false));
	REQUIRE(w.state_hash() == crewed);

	const uint64_t before_goal = w.state_hash();
	REQUIRE(!w.convoy_order_goal(id, nan, 5.5f, 0.f));
	REQUIRE(!w.convoy_order_goal(id, 10.5f, 5.5f, nan));
	REQUIRE(!w.convoy_order_goal(id, 41.5f, 5.5f, 0.f));
	REQUIRE(!w.convoy_order_goal(id, 25.5f, 5.5f, 0.f)); // behind the wall: no route, so the anchor could not reach it
	REQUIRE(!w.convoy_order_goal(id + 5, 10.5f, 5.5f, 0.f));
	REQUIRE(w.state_hash() == before_goal);

	REQUIRE(!w.convoy_set_body(id, {cell(20, 5)}));           // wall cell
	REQUIRE(!w.convoy_set_body(id, {cell(5, 5), cell(5, 5)})); // duplicate cell
	REQUIRE(!w.convoy_set_body(id, {-1}));
	std::vector<int> too_many;
	for (int k = 0; k < 65; ++k) too_many.push_back(cell(k % 10, k / 10));
	REQUIRE(!w.convoy_set_body(id, too_many));
	REQUIRE(w.state_hash() == before_goal);
	REQUIRE(w.convoy_set_body(id, {cell(5, 5), cell(5, 6)}));  // a valid footprint is stored
	REQUIRE(w.state_hash() != before_goal);

	ConvoyState st{};
	REQUIRE(!w.convoy_state(id + 5, st));
	REQUIRE(!w.convoy_state(0, st));
	REQUIRE(!w.convoy_remove(0));
	REQUIRE(!w.convoy_remove(id + 5));
	REQUIRE(w.validate());
}

// G4 S2 bodies: the footprint of a convoy at its current pose (sorted absolute cells).
static std::vector<int> body_of(const World &w, int id) {
	std::vector<int> cells;
	REQUIRE(w.convoy_body_at(id, cells));
	return cells;
}
static int cell_of(const World &w, int i) { return w.terrain.idx((int)std::floor(w.px[i]), (int)std::floor(w.py[i])); }

static void non_crew_detours_around_body() {
	test_case = "a non-crew soldier ordered through a convoy body detours and never stands inside it";
	World w(1); setup(w);
	// no crew and no goal: the convoy holds and its body stands across the formation's straight route west
	const int id = w.add_convoy(20.5f, 30.5f, 0.f);
	REQUIRE(id > 0);
	REQUIRE(w.convoy_set_body(id, {cell(20, 29), cell(20, 30), cell(20, 31)}));
	const std::vector<int> body = body_of(w, id);
	REQUIRE(body == std::vector<int>({cell(20, 29), cell(20, 30), cell(20, 31)}));
	w.order_move(0, 10.5f, 30.5f, 0.f); // soldiers 0, 1 and 2 are all non-crew
	for (int t = 0; t < 900; ++t) {
		step(w);
		for (int i = 0; i < 3; ++i) REQUIRE(!std::binary_search(body.begin(), body.end(), cell_of(w, i)));
	}
	REQUIRE(w.px[2] < 19.0f); // the rear member got past the body: it went around, it did not stop at it
	REQUIRE(body_of(w, id) == body); // the held convoy did not move
	REQUIRE(w.validate());
}

static void crew_stand_on_their_own_body() {
	test_case = "crew are not blocked by their own convoy body, and the body moves with the anchor";
	World w(1); setup(w);
	const int id = straight_convoy(w);
	// the body covers the anchor and both crew slots: offsets (0, 0), (-1, 0), (-2, 0)
	REQUIRE(w.convoy_set_body(id, {cell(5, 5), cell(4, 5), cell(3, 5)}));
	REQUIRE(w.convoy_order_goal(id, 10.5f, 5.5f, 0.f));
	ConvoyState st{};
	bool done = false;
	for (int t = 0; t < 2400 && !done; ++t) {
		step(w);
		REQUIRE(w.convoy_state(id, st));
		done = st.complete != 0;
	}
	REQUIRE(done);
	REQUIRE(st.stalled == 0);
	for (int t = 0; t < 60; ++t) step(w);
	close_to(w.px[0], 9.5, 0.05); close_to(w.py[0], 5.5, 0.05);
	close_to(w.px[1], 8.5, 0.05); close_to(w.py[1], 5.5, 0.05);
	REQUIRE(body_of(w, id) == std::vector<int>({cell(8, 5), cell(9, 5), cell(10, 5)}));
	REQUIRE(w.validate());
}

static void convoys_do_not_interpenetrate() {
	test_case = "two convoys do not interpenetrate: the anchor refuses to advance into another body and reports stalled";
	World w(1); setup(w);
	const int a = straight_convoy(w);
	REQUIRE(w.convoy_set_body(a, {cell(5, 4), cell(5, 5), cell(5, 6)}));
	const int b = w.add_convoy(8.5f, 5.5f, 0.f); // no crew, no goal: it holds, its body stands on A's route
	REQUIRE(b == a + 1);
	REQUIRE(w.convoy_set_body(b, {cell(8, 4), cell(8, 5), cell(8, 6)}));
	REQUIRE(w.convoy_order_goal(a, 10.5f, 5.5f, 0.f));
	ConvoyState st{};
	for (int t = 0; t < 900; ++t) {
		step(w);
		REQUIRE(w.convoy_state(a, st));
		const std::vector<int> ca = body_of(w, a), cb = body_of(w, b);
		for (int c : ca) REQUIRE(!std::binary_search(cb.begin(), cb.end(), c));
	}
	REQUIRE(w.convoy_state(a, st));
	REQUIRE(st.stalled == 1 && st.complete == 0 && st.moving == 0);
	REQUIRE(st.x >= 7.0 && st.x < 8.0); // its body reaches column 8 only when the anchor would pass x = 8
	REQUIRE(w.validate());
}

static void save_load_mid_route_with_body() {
	test_case = "save and load mid-route with a body: identical hash, body cells and steps";
	World w(1); setup(w);
	const int id = straight_convoy(w);
	REQUIRE(w.convoy_set_body(id, {cell(5, 5), cell(4, 5), cell(3, 5)}));
	REQUIRE(w.convoy_order_goal(id, 10.5f, 5.5f, 0.f));
	for (int t = 0; t < 40; ++t) step(w);
	ConvoyState before{};
	REQUIRE(w.convoy_state(id, before) && before.moving == 1);
	const std::vector<uint8_t> blob = w.save();
	REQUIRE(!blob.empty());
	World loaded(1);
	REQUIRE(loaded.load(blob));
	REQUIRE(loaded.state_hash() == w.state_hash());
	REQUIRE(loaded.save() == blob);
	REQUIRE(body_of(loaded, id) == body_of(w, id)); // rebuilt from the saved offsets, anchor and facing
	for (int t = 0; t < 120; ++t) {
		step(w);
		step(loaded);
		REQUIRE(loaded.state_hash() == w.state_hash());
	}
	REQUIRE(w.validate() && loaded.validate());
}

#define REQUIRE_AT(c, msg) do { ++checks; if (!(c)) { ++failures; std::fprintf(stderr, "FAIL %s line %d setup: %s\n", test_case, __LINE__, msg); } } while (false)

// G4 S4f repro: the GD straight run from the cart's native state. Anchor (2.5, 49.5) facing east, one crew at (-1, 0)
// already in slot, body = the cart cell, goal anchor (2.5, 44.5) facing north, on a 60 x 60 flat map (the GD cell
// row 49 is outside the 40-row map used by the other cases). Every setup call asserts its own result. Expected within
// 300 steps: the anchor faces north and advances at least 3 cells, or it reports stalled with a nonzero reason.
static void north_turn_from_cart_anchor(bool bystander) {
	test_case = bystander ? "cart north turn with a same-team bystander south-west of the body" : "cart north turn without a bystander";
	World w(1);
	const int failures_before = failures;
	setup(w, -1, 60);
	REQUIRE_AT(w.soldier_count() == 3, "soldiers: the setup formation holds three soldiers");
	REQUIRE_AT(w.terrain.walkable(2, 49) && w.terrain.walkable(2, 48) && w.terrain.walkable(2, 44), "terrain: cart cell (2,49) and the north column (2,44..48) are walkable");
	REQUIRE_AT(w.terrain.walkable(1, 49) && w.terrain.walkable(1, 50), "terrain: crew slot (1,49) and its neighbour are walkable");
	place(w, 0, 1.5f, 49.5f);
	REQUIRE_AT(w.get_soldier_state(0).x == 1.5f && w.get_soldier_state(0).y == 49.5f, "soldiers: soldier 0 placed on the crew slot (1.5, 49.5)");
	const int id = w.add_convoy(2.5f, 49.5f, 0.f);
	REQUIRE_AT(id > 0, "add_convoy: anchor (2.5, 49.5) facing 0 refused (walkable route cell, finalized world)");
	if (id <= 0) return;
	REQUIRE_AT(w.convoy_set_crew(id, 0, -1, 0, true), "set_crew: soldier 0 at offset (-1, 0) refused");
	REQUIRE_AT(w.convoy_set_body(id, {w.terrain.idx(2, 49)}), "set_body: cart cell (2,49) refused at the current pose");
	if (bystander) {
		place(w, 1, 1.3f, 50.3f);
		REQUIRE_AT(w.get_soldier_state(1).x == 1.3f, "soldiers: bystander soldier 1 placed at (1.3, 50.3)");
	}
	const float north = std::atan2(-1.f, 0.f);
	REQUIRE_AT(w.convoy_order_goal(id, 2.5f, 44.5f, north), "order_goal: goal (2.5, 44.5) facing north refused (reachable from the anchor)");
	ConvoyState st{};
	REQUIRE_AT(w.convoy_state(id, st), "convoy_state: the convoy id is not readable after setup");
	if (failures != failures_before) return;
	const double y0 = st.y;
	const double tau = 6.283185307179586;
	std::vector<ConvoyState> trace;
	bool advanced = false;
	for (int t = 1; t <= 300 && !advanced; ++t) {
		step(w);
		REQUIRE(w.convoy_state(id, st));
		if (t % 30 == 0) trace.push_back(st);
		advanced = y0 - st.y >= 3.0 && std::fabs(std::remainder(st.facing - north, tau)) < 0.2;
	}
	const bool ok = advanced || (st.stalled == 1 && st.reason != 0);
	if (!ok) {
		std::fprintf(stderr, "REPRO FAILED %s: start y=%.3f\n", test_case, y0);
		for (size_t k = 0; k < trace.size(); ++k)
			std::fprintf(stderr, "REPRO step %3zu anchor=(%.3f,%.3f) facing=%.3f moving=%d complete=%d stalled=%d reason=%d\n",
				(k + 1) * 30, trace[k].x, trace[k].y, trace[k].facing, trace[k].moving, trace[k].complete, trace[k].stalled, trace[k].reason);
	}
	REQUIRE(ok);
}

// ---------------------------------------------------------------- G4 vehicles in a formation (OPUS)
// The GD crowd deploy at small scale: a connected blob of cells (TerrainLab._trial_connected_formation, directions up,
// right, down, left), carts and wagons planned next to their operators exactly as SiteVehicleTransport.plan_team does
// (first blob index and direction that fit; cart anchor = operator + d, wagon anchor = operator - 2d, body along d),
// the formation centred on the blob, facing the enemy, cols = ceil(sqrt(count)), people starting on their blob cells.
// Each convoy is created as _convoy_create does (rider: cart (-1, 0), wagon (2, 0)) and attached to the formation.
namespace wg { struct WorldTestAccess {
	static float stx(const World &w, int i) { return w.slot_tx_[i]; }
	static float sty(const World &w, int i) { return w.slot_ty_[i]; }
	static float clip(const World &w, int i) { return w.slot_clip_[i]; }
	static int los(const World &w, int i) { return w.los(w.px[i], w.py[i], w.slot_tx_[i], w.slot_ty_[i]) ? 1 : 0; }
}; }
static bool formation_control = false;
// D acceptance terrain (run 20261029_142014_245, the test's own 25 x 25 map around the centre, origin (43, 36)):
// height levels, '#' not walkable, no ramps; the rest of the 100 x 100 map is level 4.
static const char *D_MAP[25] = {
	"4444#44444444444444444333", "4444445555444444444444333", "4444455555555544444444333", "4444555555555554444444433",
	"44445555555#5555444444433", "4444555555555555544444433", "444455555#555555544444433", "4444455555555555544444443",
	"444445555555555#444444444", "4444455555555555444444444", "4444555555555555554444444", "4555555555555555#55554444",
	"5555555555555555555555444", "5555555555555555555555544", "5555555555555555555555554", "5555555555555555555555554",
	"5555555555555555555555554", "5555555555555555555555544", "444555555555444444555#444", "444444444444444444#444444",
	"4444444444444444444444444", "4444444444444444444444444", "4444444444444444444444444", "4444444444444444444444444",
	"333444444444#444333333333"};
static bool formation_d_map = false; // build_formation_scene paints D_MAP (size must be 100)
static void paint_d_map(World &w) {
	for (int y = 0; y < w.terrain.h; ++y) for (int x = 0; x < w.terrain.w; ++x) w.terrain.height[w.terrain.idx(x, y)] = 4;
	for (int r = 0; r < 25; ++r) for (int c = 0; c < 25; ++c) {
		const int v = w.terrain.idx(43 + c, 36 + r);
		if (D_MAP[r][c] == '#') w.terrain.flags[v] = 0; else w.terrain.height[v] = (uint8_t)(D_MAP[r][c] - '0');
	}
	// row y = 35 from the p12 dump (run 20261029_144535_155)
	const char *row35 = "#444444444444444444443333";
	for (int c = 0; c < 25; ++c) {
		const int v = w.terrain.idx(43 + c, 35);
		if (row35[c] == '#') w.terrain.flags[v] = 0; else w.terrain.height[v] = (uint8_t)(row35[c] - '0');
	}
}
// The Site player (host-controlled, its own one-person formation of the same faction) standing on this cell, or -1.
// D p12 (run 20261029_144535_155): the player stood in front of a cart; the cart waited on it for ever.
static int formation_player_x = -1, formation_player_y = -1;
static float formation_face_bias = 0.35f; // deploy facing offset from the enemy direction (stress varies it)
static bool formation_quiet = false;
static int formation_worst = 0; // largest MOVE + settle ticks seen // --control: also run the scene without vehicles (diagnostics)
struct FormationScene {
	int formation = -1, enemy = -1;
	std::vector<int> convoys, operators, rider_ox;
};
static const int GDX[4] = {0, 1, 0, -1}, GDY[4] = {-1, 0, 1, 0}; // TerrainData.DIRECTIONS: up, right, down, left

static bool build_formation_scene(World &w, FormationScene &s, int people, int carts, int wagons, int size, int seed_x, int seed_y, const std::vector<int> &walls) {
	w.terrain.allocate(size, size);
	if (formation_d_map) paint_d_map(w);
	for (int v : walls) { if (v >= 0) w.terrain.flags[v] = 0; else w.terrain.height[-v - 1] = 1; } // negative: a raised cell (a step without ramp)
	w.terrain.base_height = w.terrain.height;
	w.cfg.ai = false; w.cfg.auto_capture = false; w.cfg.rescue_seek_cells = 0; w.cfg.bleed_per_game_hour = 0;
	w.terrain.build_edges();
	std::vector<uint8_t> claimed((size_t)size * size, 0);
	std::vector<std::pair<int, int>> blob{{seed_x, seed_y}};
	claimed[w.terrain.idx(seed_x, seed_y)] = 1;
	for (size_t k = 0; k < blob.size() && (int)blob.size() < people; ++k)
		for (int d = 0; d < 4 && (int)blob.size() < people; ++d) {
			const int x = blob[k].first + GDX[d], y = blob[k].second + GDY[d];
			if (!w.terrain.contains(x, y) || !w.terrain.walkable(x, y) || claimed[w.terrain.idx(x, y)]) continue;
			if (!w.terrain.edge(blob[k].first, blob[k].second, d)) continue; // TerrainLab: can_step(current, next)
			claimed[w.terrain.idx(x, y)] = 1;
			blob.push_back({x, y});
		}
	if ((int)blob.size() != people) return false;
	struct Plan { bool wagon; int ax, ay, d, op; };
	std::vector<Plan> plan;
	std::vector<uint8_t> operator_used(people, 0);
	for (int ordinal = 0; ordinal < carts + wagons; ++ordinal) {
		const bool wagon = ordinal >= carts;
		const int length = wagon ? 3 : 1;
		bool chosen = false;
		for (int index = 0; index < people && !chosen; ++index) {
			if (operator_used[index]) continue;
			for (int d = 0; d < 4 && !chosen; ++d) {
				const int ox = blob[index].first, oy = blob[index].second;
				const int ax = wagon ? ox - 2 * GDX[d] : ox + GDX[d], ay = wagon ? oy - 2 * GDY[d] : oy + GDY[d];
				bool fits = true;
				for (int k = 0; k < length && fits; ++k) {
					const int x = ax + GDX[d] * k, y = ay + GDY[d] * k;
					if (!w.terrain.contains(x, y) || !w.terrain.walkable(x, y)) { fits = false; break; }
					if (claimed[w.terrain.idx(x, y)] && !(wagon && x == ox && y == oy)) fits = false;
					if (k > 0 && !w.terrain.edge(x - GDX[d], y - GDY[d], d)) fits = false; // plan_team: consecutive cells step legally
				}
				if (fits && !wagon && !w.terrain.edge(ox, oy, d)) fits = false; // a cart is one legal step ahead of its operator
				if (!fits) continue;
				plan.push_back({wagon, ax, ay, d, index});
				operator_used[index] = 1;
				for (int k = 0; k < length; ++k) claimed[w.terrain.idx(ax + GDX[d] * k, ay + GDY[d] * k)] = 1;
				chosen = true;
			}
		}
		if (!chosen) return false;
	}
	float cx = 0, cy = 0;
	for (const auto &b : blob) { cx += (float)b.first + 0.5f; cy += (float)b.second + 0.5f; }
	cx /= (float)people; cy /= (float)people;
	const float ex = (float)std::min(size - 3, seed_x + 22) + 0.5f, ey = cy;
	const float face = std::atan2(ey - cy, ex - cx) + formation_face_bias; // a non-quarter deploy facing, as toward a real enemy
	const int cols = std::max(1, (int)std::ceil(std::sqrt((double)people)));
	s.formation = w.add_formation(0, cx, cy, face, cols, 1.f, T_MELEE, 0);
	rules::Equip e; e.family = rules::F_LONGSWORD; e.material = rules::M_IRON;
	for (int k = 0; k < people; ++k) w.add_soldier(s.formation, e, k == 0 ? R_CAPTAIN : (k <= 2 ? R_OFFICER : R_REGULAR), 5000 + k);
	s.enemy = w.add_formation(1, ex, ey, kPi, 1, 1.f, T_MELEE, 0);
	w.add_soldier(s.enemy, e, R_CAPTAIN, 9000);
	int player = -1;
	if (formation_player_x >= 0) {
		if (claimed[w.terrain.idx(formation_player_x, formation_player_y)]) return false;
		const int pf = w.add_formation(0, (float)formation_player_x + 0.5f, (float)formation_player_y + 0.5f, 0.f, 1, 1.f, T_MELEE, 0);
		player = w.add_soldier(pf, e, R_CAPTAIN, 9100);
		w.start_x[player] = (float)formation_player_x + 0.5f; w.start_y[player] = (float)formation_player_y + 0.5f;
	}
	for (int k = 0; k < people; ++k) { w.start_x[k] = (float)blob[k].first + 0.5f; w.start_y[k] = (float)blob[k].second + 0.5f; }
	w.finalize();
	if (player >= 0) w.set_host_control(player, true);
	for (auto &f : w.formations) f.ai_enabled = false;
	for (const auto &p : plan) {
		const int id = w.add_convoy((float)p.ax + 0.5f, (float)p.ay + 0.5f, std::atan2((float)GDY[p.d], (float)GDX[p.d]));
		const int rider = p.wagon ? 2 : -1;
		std::vector<int> body;
		for (int k = 0; k < (p.wagon ? 3 : 1); ++k) body.push_back(w.terrain.idx(p.ax + GDX[p.d] * k, p.ay + GDY[p.d] * k));
		if (id <= 0 || !w.convoy_set_crew(id, p.op, rider, 0, true) || !w.convoy_set_body(id, body) || !w.convoy_attach_formation(id, s.formation)) return false;
		s.convoys.push_back(id); s.operators.push_back(p.op); s.rider_ox.push_back(rider);
	}
	return true;
}

static std::vector<int> scene_body_union_check(const World &w, const FormationScene &s, bool &overlap) {
	std::vector<int> all;
	overlap = false;
	for (int id : s.convoys) {
		std::vector<int> cells;
		w.convoy_body_at(id, cells);
		for (int v : cells) { if (std::find(all.begin(), all.end(), v) != all.end()) overlap = true; all.push_back(v); }
	}
	std::sort(all.begin(), all.end());
	return all;
}

struct PhaseReport {
	int move_ticks = -1, settle_ticks = -1, max_stall = 0, max_wait = 0; bool overlap = false, soldier_in_body = false; float spread = 0;
	int done_at[8] = {-1, -1, -1, -1, -1, -1, -1, -1}; int reasons[8][10] = {}; int soldiers_done = -1; int ticks = 0;
};

// One test phase as the GD acceptance runs it: MOVE from the formation reference, run to HOLD, explicit HOLD, settle.
static bool run_phase(World &w, const FormationScene &s, int dx, int dy, PhaseReport &rep, int save_at = -1, std::vector<uint8_t> *blob = nullptr) {
	Formation &f = w.formations[s.formation];
	const float rx = f.ref_valid ? f.ref_x : f.cx, ry = f.ref_valid ? f.ref_y : f.cy;
	const int gx = (int)std::floor(rx) + dx, gy = (int)std::floor(ry) + dy;
	if (w.host_order(s.formation, 1, (float)gx + 0.5f, (float)gy + 0.5f, std::atan2((float)dy, (float)dx)) != OK) { rep.move_ticks = -2; return false; }
	std::vector<int> stall(s.convoys.size(), 0), wait(s.convoys.size(), 0);
	const auto watch = [&]() {
		bool overlap = false;
		const std::vector<int> bodies = scene_body_union_check(w, s, overlap);
		rep.overlap = rep.overlap || overlap;
		for (int i = 0; i < w.soldier_count(); ++i) {
			if (!w.alive(i) || w.is_convoy_crew(i)) continue;
			const int c = w.terrain.idx((int)std::floor(w.px[i]), (int)std::floor(w.py[i]));
			if (std::binary_search(bodies.begin(), bodies.end(), c)) rep.soldier_in_body = true;
		}
		for (size_t k = 0; k < s.convoys.size(); ++k) {
			ConvoyState st{};
			w.convoy_state(s.convoys[k], st);
			stall[k] = st.stalled ? stall[k] + 1 : 0;
			wait[k] = (!st.complete && !st.moving) || st.reason != CONVOY_OK ? wait[k] + 1 : 0;
			rep.max_stall = std::max(rep.max_stall, stall[k]);
			rep.max_wait = std::max(rep.max_wait, wait[k]);
			if (k < 8) {
				if (st.complete && rep.done_at[k] < 0) rep.done_at[k] = rep.ticks;
				if (!st.complete) rep.done_at[k] = -1;
				if (st.reason >= 0 && st.reason < 10 && !st.complete) rep.reasons[k][st.reason]++;
			}
		}
		++rep.ticks;
		{
			bool all = true;
			for (int i : w.formations[s.formation].members) {
				if (!w.alive(i) || w.is_convoy_crew(i)) continue;
				const float v2 = w.vx[i] * w.vx[i] + w.vy[i] * w.vy[i];
				if (w.state[i] != S_SLOT || v2 > 0.0025f) all = false;
			}
			if (all && rep.soldiers_done < 0) rep.soldiers_done = rep.ticks;
			if (!all) rep.soldiers_done = -1;
		}
	};
	int t = 0;
	for (; t < 1800 && w.formations[s.formation].order != Order::HOLD; ++t) {
		if (t == save_at && blob) *blob = w.save();
		if (!w.step_clock(DT, 0, 0)) return false;
		watch();
		if (t == 0 && formation_control) for (const auto &c : w.convoys) {
			const int ax = (int)std::floor(c.x), ay = (int)std::floor(c.y);
			const bool in = !c.plan_cost.empty() && ax >= c.plan_x0 && ay >= c.plan_y0 && ax < c.plan_x0 + c.plan_w && ay < c.plan_y0 + c.plan_h;
			const unsigned cost = in ? c.plan_cost[(size_t)(ay - c.plan_y0) * c.plan_w + (ax - c.plan_x0)] : 0u;
			std::printf("  plan convoy %d from (%.1f,%.1f,%.2f) to (%.1f,%.1f,%.2f) straight=%.1f route_cost=%u\n", c.id, c.x, c.y, c.facing, c.gx, c.gy, c.gfacing, std::hypot(c.gx - c.x, c.gy - c.y), cost);
		}
	}
	rep.move_ticks = t;
	if (w.formations[s.formation].order != Order::HOLD) return false;
	if (w.host_order(s.formation, 0, f.cx, f.cy, 0.0) != OK) return false;
	for (int k = 0; k < 1800 - rep.move_ticks; ++k) { // the acceptance budget: MOVE plus settle within 1800 ticks
		if (!w.step_clock(DT, 0, 0)) return false;
		watch();
		bool settled = true;
		for (int i : w.formations[s.formation].members) {
			if (!w.alive(i)) continue;
			const float v2 = w.vx[i] * w.vx[i] + w.vy[i] * w.vy[i];
			if (w.state[i] != S_SLOT || v2 > 0.0025f) settled = false; // the acceptance rest rule: |v| < 0.05 cells / s
		}
		for (size_t c = 0; c < s.convoys.size() && settled; ++c) {
			ConvoyState st{};
			if (!w.convoy_state(s.convoys[c], st) || !st.complete || st.moving || st.stalled) { settled = false; break; }
			const float fx = std::cos((float)st.facing), fy = std::sin((float)st.facing);
			const int op = s.operators[c];
			const int rx2 = (int)std::floor((float)st.x + (float)s.rider_ox[c] * fx), ry2 = (int)std::floor((float)st.y + (float)s.rider_ox[c] * fy);
			if ((int)std::floor(w.px[op]) != rx2 || (int)std::floor(w.py[op]) != ry2) settled = false;
		}
		if (settled) { rep.settle_ticks = k + 1; break; }
	}
	rep.spread = 0;
	for (int i : w.formations[s.formation].members) if (w.alive(i) && !w.is_convoy_crew(i)) {
		const float d = std::hypot(w.px[i] - w.formations[s.formation].cx, w.py[i] - w.formations[s.formation].cy);
		if (d > 8.f) {
			int si = -1; float tx = 0, ty = 0, clip = 1;
			w.slot_target(i, si, tx, ty, clip);
			std::fprintf(stderr, "FAR member %d pos=(%.2f,%.2f) slot=%d target=(%.2f,%.2f) clip=%.2f hold=%d\n", i, w.px[i], w.py[i], si, tx, ty, clip, (int)w.rest_hold[i]);
		}
		rep.spread = std::max(rep.spread, d);
	}
	return rep.settle_ticks > 0;
}

static void dump_scene(const World &w, const FormationScene &s, const char *label) {
	const Formation &f = w.formations[s.formation];
	std::fprintf(stderr, "SCENE %s order=%d centre=(%.2f,%.2f) goal=(%.2f,%.2f) facing=%.3f goal_facing=%.3f slots=%d\n", label, (int)f.order, f.cx, f.cy, f.goal_x, f.goal_y, f.facing, f.goal_facing, f.slot_count);
	for (size_t k = 0; k < s.convoys.size(); ++k) {
		ConvoyState st{};
		w.convoy_state(s.convoys[k], st);
		const Convoy *c = nullptr;
		for (const auto &o : w.convoys) if (o.id == s.convoys[k]) c = &o;
		std::fprintf(stderr, "  convoy %d pose=(%.3f,%.3f,%.3f) goal=(%.2f,%.2f,%.3f) slot=%d reason=%d moving=%d complete=%d stalled=%d blocked=%d op=(%.2f,%.2f)\n", s.convoys[k], st.x, st.y, st.facing,
			c ? c->gx : 0, c ? c->gy : 0, c ? c->gfacing : 0, c ? c->slot_index : -9, st.reason, st.moving, st.complete, st.stalled, c ? c->blocked : -1, w.px[s.operators[k]], w.py[s.operators[k]]);
	}
	int shown = 0;
	for (int i : f.members) {
		if (!w.alive(i) || shown >= 12) continue;
		const float v2 = w.vx[i] * w.vx[i] + w.vy[i] * w.vy[i];
		if (w.state[i] == S_SLOT && v2 <= 0.0025f) continue;
		float sx = 0, sy = 0;
		if (w.slot[i] >= 0) w.slot_world(f, w.slot[i], f.slot_count, sx, sy);
		std::fprintf(stderr, "  unsettled soldier %d pos=(%.2f,%.2f) v=(%.3f,%.3f) state=%d slot=%d target=(%.2f,%.2f) slot_t=(%.2f,%.2f) clip=%.2f los=%d/%d enc=%d tick=%u\n", i, w.px[i], w.py[i], w.vx[i], w.vy[i], (int)w.state[i], w.slot[i], sx, sy,
			wg::WorldTestAccess::stx(w, i), wg::WorldTestAccess::sty(w, i), wg::WorldTestAccess::clip(w, i), (int)w.los_ok[i], wg::WorldTestAccess::los(w, i), w.enc_target[i], w.tick);
		++shown;
	}
	for (size_t v = 0; v < w.convoy_claim_owner.size(); ++v) if (w.convoy_claim_owner[v]) std::fprintf(stderr, "    claim (%d,%d) by %d\n", (int)v % w.terrain.w, (int)v / w.terrain.w, w.convoy_claim_owner[v]);
	for (size_t v = 0; v < w.convoy_body_owner.size(); ++v) if (w.convoy_body_owner[v]) std::fprintf(stderr, "    body (%d,%d) of %d\n", (int)v % w.terrain.w, (int)v / w.terrain.w, w.convoy_body_owner[v]);
}

static uint64_t formation_sequence(int people, int threads, int seed_x, int seed_y, const std::vector<int> &walls, const char *label, int vehicles = 2) {
	World w(threads);
	FormationScene s;
	const bool built = build_formation_scene(w, s, people, vehicles, vehicles, formation_d_map ? 100 : 64, seed_x, seed_y, walls);
	REQUIRE(built);
	if (!built) return 0;
	for (int i : s.operators) REQUIRE(w.slot[i] == -1); // crew hold vehicle slots, not soldier slots
	REQUIRE(w.formations[s.formation].slot_count == people - 2 * vehicles);
	const int moves[3][2] = {{5, 0}, {0, 4}, {-3, 0}};
	for (int m = 0; m < 3; ++m) {
		PhaseReport rep;
		const bool ok = run_phase(w, s, moves[m][0], moves[m][1], rep);
		formation_worst = std::max(formation_worst, rep.settle_ticks > 0 ? rep.move_ticks + rep.settle_ticks : 9999);
		if (!formation_quiet || !ok) std::printf("FORMATION_PHASE %s people=%d threads=%d move=(%d,%d) move_ticks=%d settle_ticks=%d max_stall=%d max_wait=%d spread=%.2f overlap=%d soldier_in_body=%d\n",
			label, people, threads, moves[m][0], moves[m][1], rep.move_ticks, rep.settle_ticks, rep.max_stall, rep.max_wait, rep.spread, (int)rep.overlap, (int)rep.soldier_in_body);
		if (!formation_quiet || !ok) {
			std::printf("  soldiers_settled_at=%d", rep.soldiers_done);
			for (size_t k = 0; k < s.convoys.size() && k < 8; ++k) {
				std::printf(" | convoy %d done_at=%d", s.convoys[k], rep.done_at[k]);
				for (int r = 0; r < 10; ++r) if (rep.reasons[k][r]) std::printf(" r%d:%d", r, rep.reasons[k][r]);
			}
			std::printf("\n");
		}
		if (rep.move_ticks == -2 && formation_quiet) { std::printf("SKIP %s: the order goal is a rock\n", label); return 0; }
		REQUIRE(ok);
		REQUIRE(rep.move_ticks < 1800);
		REQUIRE(!rep.overlap);
		REQUIRE(!rep.soldier_in_body);
		REQUIRE(rep.max_stall <= 150);
		REQUIRE(rep.spread <= 8.f);
		if (!ok || rep.overlap || rep.soldier_in_body || rep.max_stall > 150 || rep.spread > 8.f) {
			dump_scene(w, s, label);
			return 0;
		}
	}
	REQUIRE(w.validate());
	return w.state_hash();
}

static void formation_vehicles_follow_moves_and_turns() {
	test_case = "vehicles in a formation: MOVE +5x, +4y with a 90-degree turn, -3x; settle, complete, no overlap, no long stall";
	const std::vector<int> none;
	if (formation_control) { formation_sequence(96, 1, 20, 30, none, "control96", 0); formation_sequence(30, 1, 20, 30, none, "control30", 0); }
	const uint64_t a = formation_sequence(30, 1, 20, 30, none, "p30");
	const uint64_t b = formation_sequence(30, 4, 20, 30, none, "p30");
	REQUIRE(a != 0 && a == b); // 1 and 4 threads give the same state
	formation_sequence(96, 1, 20, 30, none, "p96");
	formation_sequence(8, 1, 20, 30, none, "p8");
	// a rock where the vehicle rank lands after the first move, and a wall north of the blob: slots move to free
	// places, routes go around
	std::vector<int> wall;
	for (int x = 10; x < 34; ++x) wall.push_back(64 * 22 + x);
	for (int y = 29; y <= 32; ++y) for (int x = 17; x <= 20; ++x) wall.push_back(64 * y + x);
	formation_sequence(30, 1, 23, 30, wall, "p30_rock");
	formation_sequence(96, 1, 23, 30, wall, "p96_rock");
	// the blob against the west map edge: no room behind the block at first
	formation_sequence(30, 1, 3, 30, none, "p30_edge");
	// D-like: a building just north of the deployment (wagons start between it and the block) and a wall on the line
	// of the front row after the first move (a slot on a blocked cell boundary must be clipped, not left on the wall)
	std::vector<int> camp;
	for (int y = 17; y <= 21; ++y) for (int x = 15; x <= 26; ++x) camp.push_back(64 * y + x);
	for (int y = 25; y <= 36; ++y) camp.push_back(64 * y + 30);
	formation_sequence(96, 1, 20, 30, camp, "p96_camp");
	formation_sequence(30, 1, 20, 26, camp, "p30_camp");
	// scattered one-cell steps without ramps (D-like height changes): turns must not carry a body or crew point across
	// an illegal edge, and people asked to step out find their way round the steps
	std::vector<int> steps;
	for (int y = 12; y < 50; ++y) for (int x = 8; x < 46; ++x)
		if ((x * 7 + y * 13) % 17 == 0 && std::abs(x - 20) + std::abs(y - 30) > 7) steps.push_back(-(64 * y + x) - 1);
	formation_sequence(30, 1, 20, 30, steps, "p30_steps");
	formation_sequence(96, 1, 20, 30, steps, "p96_steps");
	// D +4y: a terrace (one step up, no ramp) under the front rows after the turn. Slots beyond it are unreachable;
	// clipped to the edge they would pile three rows onto one line and never settle
	std::vector<int> terrace;
	for (int y = 36; y <= 44; ++y) for (int x = 12; x <= 38; ++x) terrace.push_back(-(64 * y + x) - 1);
	formation_sequence(96, 1, 20, 30, terrace, "p96_terrace");
	formation_sequence(30, 1, 20, 30, terrace, "p30_terrace");
	// the D acceptance terrain itself, with the vehicles, from deployments around the D blob
	formation_d_map = true;
	formation_sequence(96, 1, 50, 48, {}, "p96_dmap");
	formation_sequence(96, 1, 51, 47, {}, "p96_dmap_b");
	formation_sequence(8, 1, 50, 48, {}, "p8_dmap");
	// D p12: the same cart pose as the D run (cart 2 at (49.5, 49.5) facing +x) with the player standing on its way
	formation_player_x = 50; formation_player_y = 49;
	formation_sequence(8, 1, 48, 48, {}, "p8_dmap_player");
	formation_player_x = -1; formation_player_y = -1;
	formation_d_map = false;
}

static void formation_vehicles_save_load_mid_turn() {
	test_case = "vehicles in a formation: save and load mid-move and mid-turn (claims, routes, rotations), identical hash and continuation";
	const int points[4] = {3, 20, 40, 90};
	for (int p = 0; p < 4; ++p) {
		World w(1);
		FormationScene s;
		REQUIRE(build_formation_scene(w, s, 30, 2, 2, 64, 20, 30, {}));
		PhaseReport first;
		REQUIRE(run_phase(w, s, 5, 0, first));
		Formation &f = w.formations[s.formation];
		const float rx = f.ref_valid ? f.ref_x : f.cx, ry = f.ref_valid ? f.ref_y : f.cy;
		REQUIRE(w.host_order(s.formation, 1, std::floor(rx) + 0.5f, std::floor(ry) + 4.5f, 0.5f * kPi) == OK);
		for (int t = 0; t < points[p]; ++t) step(w);
		bool moving = false;
		for (int id : s.convoys) { ConvoyState st{}; w.convoy_state(id, st); moving = moving || !st.complete; }
		REQUIRE(moving);
		const std::vector<uint8_t> blob = w.save();
		REQUIRE(!blob.empty());
		World loaded(1);
		REQUIRE(loaded.load(blob));
		REQUIRE(loaded.state_hash() == w.state_hash());
		REQUIRE(loaded.save() == blob);
		const auto claims = [](const World &x) { std::vector<std::pair<size_t, int>> out; for (size_t v = 0; v < x.convoy_claim_owner.size(); ++v) if (x.convoy_claim_owner[v]) out.push_back({v, x.convoy_claim_owner[v]}); return out; };
		REQUIRE(claims(loaded) == claims(w)); // the claim owner map is rebuilt from the saved claims
		for (int id : s.convoys) REQUIRE(loaded.convoy_formation(id) == s.formation);
		for (int t = 0; t < 300; ++t) {
			step(w);
			step(loaded);
			if (loaded.state_hash() != w.state_hash()) { REQUIRE(false); break; }
		}
		REQUIRE(w.validate() && loaded.validate());
	}
}

// site_crowd_convoy_test's wagon step at small scale: an 8-person logistics team with one cart and one wagon deployed
// against a map edge, people settled in their slots; the wagon is ordered to turn ninety degrees in place (goal anchor
// = its anchor, facing turned left). It must complete; own soldiers standing in the swept cells step out.
static void explicit_wagon_turn_among_own_soldiers() {
	test_case = "explicit wagon turn in place next to its own settled team completes";
	const int seeds[4][2] = {{3, 30}, {20, 30}, {3, 10}, {40, 52}};
	for (const auto &seed : seeds) {
		World w(1);
		FormationScene s;
		const bool built = build_formation_scene(w, s, 8, 1, 1, 64, seed[0], seed[1], {});
		REQUIRE(built);
		if (!built) continue;
		for (int t = 0; t < 150; ++t) step(w); // the team settles into its slots around the parked vehicles
		const int wagon = s.convoys[1];
		ConvoyState st{};
		REQUIRE(w.convoy_state(wagon, st));
		const float turned = (float)st.facing + 0.5f * kPi;
		REQUIRE(w.convoy_order_goal(wagon, (float)st.x, (float)st.y, turned));
		REQUIRE(w.convoy_formation(wagon) == -1);
		bool done = false;
		int t = 0;
		for (; t < 900 && !done; ++t) { step(w); REQUIRE(w.convoy_state(wagon, st)); done = st.complete != 0; }
		if (!done) std::fprintf(stderr, "WAGON TURN seed=(%d,%d) pose=(%.2f,%.2f,%.3f) reason=%d\n", seed[0], seed[1], st.x, st.y, st.facing, st.reason);
		REQUIRE(done);
		for (int i = 0; i < w.soldier_count(); ++i) {
			if (!w.alive(i) || w.is_convoy_crew(i)) continue;
			std::vector<int> body;
			w.convoy_body_at(wagon, body);
			REQUIRE(!std::binary_search(body.begin(), body.end(), w.terrain.idx((int)std::floor(w.px[i]), (int)std::floor(w.py[i]))));
		}
	}
}

// D site_crowd_convoy_test step 301 (run 20261029_131832_022): at the west map edge a wagon at (0, 51) faces north
// (body (0, 49..51)), its team's slots fill the cells beside it; ordered to turn east in place, the rear-pivot sweep
// crosses cells where own soldiers stand. They must step out (claims) and the turn must complete.
static void explicit_wagon_turn_at_map_edge() {
	test_case = "explicit wagon turn at the map edge with own soldiers in the sweep";
	World w(1);
	w.terrain.allocate(64, 64);
	w.terrain.base_height = w.terrain.height;
	w.cfg.ai = false; w.cfg.auto_capture = false; w.cfg.rescue_seek_cells = 0; w.cfg.bleed_per_game_hour = 0;
	const int f = w.add_formation(0, 1.5f, 49.0f, -0.5f * kPi, 3, 1.f, T_MELEE, 0);
	rules::Equip e; e.family = rules::F_LONGSWORD; e.material = rules::M_IRON;
	const float start[8][2] = {{1.5f, 50.5f}, {0.5f, 48.5f}, {1.5f, 47.5f}, {0.5f, 47.5f}, {1.5f, 48.5f}, {1.5f, 46.5f}, {2.5f, 50.5f}, {0.5f, 49.5f}};
	for (int k = 0; k < 8; ++k) w.add_soldier(f, e, k == 0 ? R_CAPTAIN : R_REGULAR, 7000 + k);
	const int enemy = w.add_formation(1, 50.5f, 49.5f, kPi, 1, 1.f, T_MELEE, 0);
	w.add_soldier(enemy, e, R_CAPTAIN, 7999);
	for (int k = 0; k < 8; ++k) { w.start_x[k] = start[k][0]; w.start_y[k] = start[k][1]; }
	w.finalize();
	for (auto &fm : w.formations) fm.ai_enabled = false;
	const float north = -0.5f * kPi;
	const int cart = w.add_convoy(2.5f, 49.5f, north);
	REQUIRE(cart > 0 && w.convoy_set_crew(cart, 6, -1, 0, true) && w.convoy_set_body(cart, {w.terrain.idx(2, 49)}) && w.convoy_attach_formation(cart, f));
	const int wagon = w.add_convoy(0.5f, 51.5f, north);
	REQUIRE(wagon > 0 && w.convoy_set_crew(wagon, 7, 2, 0, true));
	REQUIRE(w.convoy_set_body(wagon, {w.terrain.idx(0, 51), w.terrain.idx(0, 50), w.terrain.idx(0, 49)}) && w.convoy_attach_formation(wagon, f));
	for (int t = 0; t < 150; ++t) step(w); // the team settles into its slots beside the parked vehicles
	REQUIRE(w.convoy_order_goal(wagon, 0.5f, 51.5f, 0.f));
	ConvoyState st{};
	bool done = false;
	for (int t = 0; t < 900 && !done; ++t) { step(w); REQUIRE(w.convoy_state(wagon, st)); done = st.complete != 0; }
	if (!done) std::fprintf(stderr, "EDGE WAGON pose=(%.2f,%.2f,%.3f) reason=%d\n", st.x, st.y, st.facing, st.reason);
	REQUIRE(done);
	std::vector<int> body;
	REQUIRE(w.convoy_body_at(wagon, body) && body == std::vector<int>({w.terrain.idx(0, 51), w.terrain.idx(1, 51), w.terrain.idx(2, 51)}));
	REQUIRE(w.validate());
}

// D round 4 (HEAD has it too): a 92-man block without vehicles moves +5x to (55.5, 48.5) on the D terrain; front
// slots lie behind a step and an unwalkable cell, several clipped targets meet on one spot. HEAD: 6 of 18 starts never
// settle. Rest rule: everyone settles.
static void rest_rule_on_d_steps() {
	test_case = "rest rule: a block whose front slots lie behind steps settles (D terrain, no vehicles)";
	int bad = 0;
	for (float sx : {49.5f, 50.5f, 51.5f}) for (float sy : {47.5f, 48.5f, 49.5f}) {
		World w(1);
		w.terrain.allocate(100, 100);
		paint_d_map(w);
		w.terrain.base_height = w.terrain.height;
		w.cfg.ai = false; w.cfg.auto_capture = false; w.cfg.rescue_seek_cells = 0; w.cfg.bleed_per_game_hour = 0;
		const int f = w.add_formation(0, sx, sy, 0.f, 10, 1.f, T_MELEE, 0);
		rules::Equip e; e.family = rules::F_LONGSWORD; e.material = rules::M_IRON;
		for (int k = 0; k < 92; ++k) w.add_soldier(f, e, k == 0 ? R_CAPTAIN : R_REGULAR, 100 + k);
		const int en = w.add_formation(1, 90.5f, 48.5f, kPi, 1, 1.f, T_MELEE, 0);
		w.add_soldier(en, e, R_CAPTAIN, 999);
		w.finalize();
		for (auto &fm : w.formations) fm.ai_enabled = false;
		for (int t = 0; t < 120; ++t) step(w);
		REQUIRE(w.host_order(f, 1, 55.5f, 48.5f, 0.f) == OK);
		int t = 0;
		for (; t < 1800 && w.formations[f].order != Order::HOLD; ++t) step(w);
		REQUIRE(w.host_order(f, 0, w.formations[f].cx, w.formations[f].cy, 0.0) == OK);
		bool settled = false;
		for (int k = 0; k < 1800 - t && !settled; ++k) {
			step(w);
			settled = true;
			for (int i : w.formations[f].members) if (w.alive(i) && (w.state[i] != S_SLOT || w.vx[i] * w.vx[i] + w.vy[i] * w.vy[i] > 0.0025f)) settled = false;
		}
		if (!settled) { ++bad; std::fprintf(stderr, "REST start=(%.1f,%.1f) did not settle\n", sx, sy); }
		REQUIRE(w.validate());
	}
	REQUIRE(bad == 0);
}

static void formation_explicit_order_detaches() {
	test_case = "an explicit vehicle order detaches from the formation and completes with single-vehicle steering";
	World w(1);
	FormationScene s;
	REQUIRE(build_formation_scene(w, s, 30, 2, 2, 64, 20, 30, {}));
	const int id = s.convoys[0];
	REQUIRE(w.convoy_formation(id) == s.formation);
	REQUIRE(w.convoy_formation(999) == -2);
	REQUIRE(!w.convoy_attach_formation(id, s.enemy)); // crew are not members of the enemy formation
	REQUIRE(!w.convoy_attach_formation(999, s.formation));
	ConvoyState st{};
	REQUIRE(w.convoy_state(id, st) && st.complete == 1 && st.stalled == 0 && st.moving == 0); // attached and idle: holds its cell
	for (int t = 0; t < 30; ++t) step(w);
	ConvoyState still{};
	REQUIRE(w.convoy_state(id, still) && still.x == st.x && still.y == st.y); // attaching moved nothing
	// the cart goes three cells further out, away from the blob, in its own facing
	const float fx = std::cos((float)st.facing), fy = std::sin((float)st.facing);
	const float gx = std::floor((float)st.x + 3.f * fx) + 0.5f, gy = std::floor((float)st.y + 3.f * fy) + 0.5f;
	ConvoyState others_before[3];
	for (int k = 0; k < 3; ++k) REQUIRE(w.convoy_state(s.convoys[k + 1], others_before[k]));
	REQUIRE(w.convoy_order_goal(id, gx, gy, (float)st.facing));
	REQUIRE(w.convoy_formation(id) == -1);
	for (int t = 0; t < 30; ++t) step(w);
	for (int k = 0; k < 3; ++k) { // a vehicle leaving does not re-lay the others: they keep holding
		ConvoyState now{};
		REQUIRE(w.convoy_state(s.convoys[k + 1], now) && now.x == others_before[k].x && now.y == others_before[k].y && now.complete == 1);
	}
	bool done = false;
	for (int t = 0; t < 900 && !done; ++t) { step(w); REQUIRE(w.convoy_state(id, st)); done = st.complete != 0; }
	REQUIRE(done);
	close_to(st.x, gx, 1e-4); close_to(st.y, gy, 1e-4);
	// the others still follow: a formation order moves them, the detached cart stays at its explicit goal
	Formation &f = w.formations[s.formation];
	REQUIRE(w.host_order(s.formation, 1, std::floor(f.cx) + 5.5f, std::floor(f.cy) + 0.5f, 0.f) == OK);
	for (int t = 0; t < 600; ++t) step(w);
	REQUIRE(w.convoy_state(id, st));
	close_to(st.x, gx, 1e-4); close_to(st.y, gy, 1e-4);
	ConvoyState other{};
	REQUIRE(w.convoy_state(s.convoys[1], other) && other.complete == 1);
	REQUIRE(w.validate());
}

// G1 S1 aboard: a ready soldier boards a vehicle and keeps its place on the roster; it does not move, push, block or
// get targeted while aboard, and it lands back into its formation.
static void board_refusals() {
	test_case = "board refusals: no vehicle, convoy crew, KO, captive, released, already aboard; each changes nothing";
	World w(1); setup(w);
	straight_convoy(w);
	const int roster = w.formations[0].roster, fatigue = w.formations[0].fatigue_count;
	REQUIRE(!w.site_person_board(2, -1));
	REQUIRE(!w.site_person_board(-1, 0) && !w.site_person_board(99, 0));
	REQUIRE(!w.site_person_board(0, 0)); // convoy crew
	REQUIRE(!w.site_person_board(1, 0)); // convoy crew
	w.ko[2] = 30.0;
	REQUIRE(!w.site_person_board(2, 0)); // knocked out
	w.ko[2] = 0.0;
	w.captive[2] = 1;
	REQUIRE(!w.site_person_board(2, 0)); // captive
	w.captive[2] = 0;
	REQUIRE(!w.is_aboard(0) && !w.is_aboard(1) && !w.is_aboard(2));
	REQUIRE(w.formations[0].roster == roster && w.formations[0].fatigue_count == fatigue);
	SitePersonRelease rel{};
	REQUIRE(w.site_person_release(2, rel));
	REQUIRE(!w.site_person_board(2, 0)); // released
	REQUIRE(w.released[2] == 1 && !w.is_aboard(2));
	REQUIRE(w.validate());

	World v(1); setup(v);
	REQUIRE(v.site_person_board(2, 3));
	REQUIRE(!v.site_person_board(2, 4)); // already aboard
	REQUIRE(v.aboard[2] == 1 && v.aboard_vehicle[2] == 3);
	REQUIRE(v.validate());
}

static void board_keeps_roster_fatigue_and_hp() {
	test_case = "board keeps the roster, fatigue count, hp, presence and the soldier's formation; it drops only its slot";
	World w(1); setup(w);
	const int roster = w.formations[0].roster, fatigue = w.formations[0].fatigue_count, slots = w.formations[0].slot_count;
	const double hp = w.hp[2];
	REQUIRE(w.site_person_board(2, 0));
	REQUIRE(w.aboard[2] == 1 && w.aboard_vehicle[2] == 0);
	REQUIRE(w.alive(2) && w.present[2] == 1 && w.form[2] == 0 && w.hp[2] == hp);
	REQUIRE(w.slot[2] == -1 && w.formations[0].slot_count == slots - 1);
	REQUIRE(w.formations[0].roster == roster && w.formations[0].fatigue_count == fatigue);
	REQUIRE(w.site_person_retarget_aboard(2, 4) && w.aboard_vehicle[2] == 4); // ship to ship
	REQUIRE(!w.site_person_retarget_aboard(0, 4)); // not aboard
	REQUIRE(!w.site_person_set_deck(0, 5.5, 5.5)); // not aboard
	REQUIRE(w.validate());
	REQUIRE(w.site_person_land(2, 20.5, 20.5));
	REQUIRE(w.aboard[2] == 0 && w.aboard_vehicle[2] == -1 && w.slot[2] >= 0);
	REQUIRE(w.formations[0].slot_count == slots && w.formations[0].roster == roster && w.formations[0].fatigue_count == fatigue);
	REQUIRE(w.hp[2] == hp);
	REQUIRE(w.validate());
}

static void board_ends_a_held_siege_step() {
	test_case = "board ends an arrived (held) siege step; a pending siege step still refuses and changes nothing";
	World w(1); setup(w);
	w.escort_mode[2] = 5; w.escort_goal[2] = w.cell[2]; // pending: a goal is still set
	REQUIRE(!w.site_person_board(2, 0));
	REQUIRE(w.escort_mode[2] == 5 && w.escort_goal[2] == w.cell[2] && !w.is_aboard(2));
	w.escort_goal[2] = -1; // arrived and held
	REQUIRE(w.site_person_board(2, 0));
	REQUIRE(w.is_aboard(2) && w.escort_mode[2] == 0 && w.escort_goal[2] == -1);
	REQUIRE(w.validate());
	World h(1); setup(h);
	h.escort_mode[2] = 3; h.escort_goal[2] = -1; // a held housing step is not a ship approach
	REQUIRE(!h.site_person_board(2, 0));
	REQUIRE(h.escort_mode[2] == 3 && !h.is_aboard(2));
}

static void aboard_stays_while_formation_passes() {
	test_case = "an aboard soldier does not move while the formation marches through its cell, which the others pass";
	World w(1); setup(w);
	place(w, 2, 30.5f, 27.5f); // straight ahead of the formation's march north
	REQUIRE(w.site_person_board(2, 0));
	const float bx = w.px[2], by = w.py[2];
	const int cx = (int)bx, cy = (int)by;
	w.order_move(0, 30.5f, 20.5f, 0.f);
	bool passed = false;
	for (int t = 0; t < 300; ++t) {
		step(w);
		REQUIRE(w.px[2] == bx && w.py[2] == by && w.nx[2] == bx && w.ny[2] == by);
		for (int j : {0, 1}) if ((int)w.px[j] == cx && (int)w.py[j] == cy) passed = true;
	}
	REQUIRE(passed);
	REQUIRE(w.py[0] < 25.0 && w.py[1] < 25.0); // the formation itself carried on through
	REQUIRE(w.validate());
}

static void aboard_is_never_a_melee_target() {
	test_case = "an aboard soldier is never a melee target: an adjacent enemy formation ordered onto it takes no hit";
	World w(1); setup(w);
	place(w, 2, 33.5f, 30.5f);
	REQUIRE(w.site_person_board(2, 0));
	const int enemy = w.add_formation(1, 35.5f, 30.5f, 3.14159265f, 1, 1, T_MELEE, 0);
	rules::Equip e; e.family = rules::F_LONGSWORD; e.material = rules::M_IRON;
	const int foe = w.add_soldier(enemy, e, R_REGULAR, 2001);
	w.formations[enemy].ai_enabled = false;
	w.order_attack(enemy, 2);
	const float bx = w.px[2], by = w.py[2];
	const double hp = w.hp[2];
	bool targeted = false;
	for (int t = 0; t < 240; ++t) {
		step(w);
		for (int j = 0; j < w.soldier_count(); ++j) if (w.target[j] == 2 || w.enc_target[j] == 2) targeted = true;
		REQUIRE(w.state[2] != S_FIGHT && w.state[2] != S_ENGAGE && w.state[2] != S_ENCIRCLE);
	}
	REQUIRE(!targeted);
	REQUIRE(w.hp[2] == hp && w.px[2] == bx && w.py[2] == by);
	REQUIRE(w.alive(foe));
	REQUIRE(w.validate());
}

static void land_refusals_and_landing() {
	test_case = "landing: unwalkable, occupied, out of bounds and non-aboard refused; a free cell rejoins and re-settles";
	World w(1); setup(w, 20);
	REQUIRE(w.site_person_board(2, 0));
	REQUIRE(!w.site_person_land(2, 20.5, 5.5)); // unwalkable column
	REQUIRE(!w.site_person_land(2, -1.5, 3.5));  // out of bounds
	REQUIRE(!w.site_person_land(2, std::numeric_limits<double>::quiet_NaN(), 3.5)); // not finite
	REQUIRE(!w.site_person_land(1, 25.5, 25.5)); // not aboard
	REQUIRE(!w.site_person_land(2, std::floor(w.px[0]) + 0.5, std::floor(w.py[0]) + 0.5)); // occupied by soldier 0
	REQUIRE(w.aboard[2] == 1 && w.aboard_vehicle[2] == 0 && w.slot[2] == -1);
	REQUIRE(w.validate());
	REQUIRE(w.site_person_land(2, 25.5, 25.5));
	REQUIRE(w.aboard[2] == 0 && w.slot[2] >= 0 && w.px[2] == 25.5f && w.py[2] == 25.5f);
	for (int t = 0; t < 600; ++t) step(w);
	int slot_index = -1;
	float sx = 0, sy = 0, clip = 0;
	REQUIRE(w.slot_target(2, slot_index, sx, sy, clip) && slot_index == w.slot[2]);
	const double gap = std::hypot(w.px[2] - sx, w.py[2] - sy);
	REQUIRE(gap < 0.6); // back on its slot in the formation
	REQUIRE(w.validate());
}

static void deck_position_moves_only_the_aboard_soldier() {
	test_case = "set_deck moves the aboard soldier's position every tick and changes nothing for anyone else";
	World a(1), b(1);
	setup(a); setup(b);
	place(a, 2, 30.5f, 27.5f); place(b, 2, 30.5f, 27.5f);
	REQUIRE(a.site_person_board(2, 0) && b.site_person_board(2, 0));
	a.order_move(0, 30.5f, 20.5f, 0.f); b.order_move(0, 30.5f, 20.5f, 0.f);
	REQUIRE(!a.site_person_set_deck(2, -1.0, 5.0)); // outside the map
	float dx = 0, dy = 0;
	for (int t = 0; t < 120; ++t) {
		dx = 5.5f + 0.01f * (float)t; dy = 6.5f;
		REQUIRE(a.site_person_set_deck(2, dx, dy));
		step(a); step(b);
		for (int j : {0, 1}) REQUIRE(a.px[j] == b.px[j] && a.py[j] == b.py[j]);
		REQUIRE(a.hp[2] == b.hp[2]);
	}
	REQUIRE(a.px[2] == dx && a.py[2] == dy && b.px[2] == 30.5f && b.py[2] == 27.5f);
	REQUIRE(a.validate());
}

static void save_load_mid_aboard_matches() {
	test_case = "save and load with a soldier aboard: equal hash, identical continuation over 200 steps";
	World w(1); setup(w);
	straight_convoy(w);
	place(w, 2, 30.5f, 27.5f);
	REQUIRE(w.site_person_board(2, 5));
	w.order_move(0, 30.5f, 20.5f, 0.f);
	for (int t = 0; t < 40; ++t) step(w);
	const std::vector<uint8_t> blob = w.save();
	REQUIRE(!blob.empty());
	World loaded(1);
	REQUIRE(loaded.load(blob));
	REQUIRE(loaded.state_hash() == w.state_hash());
	REQUIRE(loaded.save() == blob);
	REQUIRE(loaded.aboard[2] == 1 && loaded.aboard_vehicle[2] == 5 && loaded.slot[2] == -1);
	for (int t = 0; t < 200; ++t) {
		step(w);
		step(loaded);
		REQUIRE(loaded.state_hash() == w.state_hash());
	}
	REQUIRE(w.validate() && loaded.validate());
}

static uint64_t aboard_scenario_hash(int threads) {
	World w(threads); setup(w);
	place(w, 2, 30.5f, 27.5f);
	w.site_person_board(2, 0);
	w.order_move(0, 30.5f, 20.5f, 0.f);
	for (int t = 0; t < 200; ++t) step(w);
	return w.state_hash();
}

static void aboard_hash_matches_across_thread_counts() {
	test_case = "thread counts 1 and 4 give the same hash with a soldier aboard";
	REQUIRE(aboard_scenario_hash(1) == aboard_scenario_hash(4));
}

int main(int argc, char **argv) {
	if (argc > 1 && std::string(argv[1]) == "--formation") {
		formation_control = argc > 2 && std::string(argv[2]) == "--control";
		if (argc > 2 && std::string(argv[2]) == "--stress") {
			const int counts[4] = {8, 30, 60, 96};
			int runs = 0, bad = 0;
			formation_quiet = true;
			uint32_t rng = 12345u;
			for (int c = 0; c < 4; ++c) for (int bias = 0; bias < 8; ++bias) for (int rocks = 0; rocks < 4; ++rocks) {
				const int before = failures;
				formation_face_bias = 0.35f + 0.785f * (float)bias;
				std::vector<int> walls;
				for (int k = 0; k < (rocks == 3 ? 40 : rocks * 25); ++k) {
					rng = rng * 1664525u + 1013904223u;
					const int x = 10 + (int)((rng >> 8) % 34), y = 14 + (int)((rng >> 20) % 34);
					if (std::abs(x - 28) + std::abs(y - 30) > 6) walls.push_back(rocks == 3 ? -(64 * y + x) - 1 : 64 * y + x); // rocks 3: raised steps
				}
				char label[64];
				std::snprintf(label, sizeof(label), "stress_%d_b%d_r%d", counts[c], bias, rocks);
				formation_quiet = !(argc > 3 && std::string(argv[3]) == label);
				formation_sequence(counts[c], 1, 28, 30, walls, label);
				formation_quiet = true;
				++runs;
				if (failures != before) {
					// the same ground without vehicles: does the formation itself settle there?
					const int vehicle_failures = failures;
					char control[64];
					std::snprintf(control, sizeof(control), "control_%d_b%d_r%d", counts[c], bias, rocks);
					formation_sequence(counts[c], 1, 28, 30, walls, control, 0);
					const bool control_fails = failures != vehicle_failures;
					std::printf("STRESS_FAIL %s control_%s\n", label, control_fails ? "fails_too" : "passes");
					if (!control_fails) ++bad;
				}
			}
			std::printf("STRESS worst_move_plus_settle=%d\n", formation_worst);
			std::printf("STRESS runs=%d bad=%d\n", runs, bad);
			return bad ? 1 : 0;
		}
		if (argc > 2 && std::string(argv[2]) == "--control-only") {
			formation_sequence(96, 1, 20, 30, {}, "control96", 0);
			std::printf("CONVOY_FORMATION checks=%d failures=%d\n", checks, failures);
			return failures ? 1 : 0;
		}
		formation_vehicles_follow_moves_and_turns();
		formation_vehicles_save_load_mid_turn();
		formation_explicit_order_detaches();
		rest_rule_on_d_steps();
		explicit_wagon_turn_among_own_soldiers();
		explicit_wagon_turn_at_map_edge();
		std::printf("CONVOY_FORMATION checks=%d failures=%d\n", checks, failures);
		return failures ? 1 : 0;
	}
	straight_line_five_cells();
	ninety_degree_turn();
	crew_down_stalls_the_anchor();
	removal_returns_crew_to_ordinary_behaviour();
	crew_ignore_ordinary_orders();
	save_load_mid_route_matches();
	invalid_requests_change_nothing();
	non_crew_detours_around_body();
	crew_stand_on_their_own_body();
	convoys_do_not_interpenetrate();
	save_load_mid_route_with_body();
	north_turn_from_cart_anchor(false);
	north_turn_from_cart_anchor(true);
	formation_vehicles_follow_moves_and_turns();
	formation_vehicles_save_load_mid_turn();
	formation_explicit_order_detaches();
	rest_rule_on_d_steps();
	explicit_wagon_turn_among_own_soldiers();
	explicit_wagon_turn_at_map_edge();
	board_refusals();
	board_keeps_roster_fatigue_and_hp();
	board_ends_a_held_siege_step();
	aboard_stays_while_formation_passes();
	aboard_is_never_a_melee_target();
	land_refusals_and_landing();
	deck_position_moves_only_the_aboard_soldier();
	save_load_mid_aboard_matches();
	aboard_hash_matches_across_thread_counts();
	std::printf("CONVOY_NATIVE_CONTRACT checks=%d failures=%d\n", checks, failures);
	return failures ? 1 : 0;
}
