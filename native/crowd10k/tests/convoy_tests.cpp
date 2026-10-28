// G4 logistics convoy contract: anchor movement, crew steering, turns, crew loss, removal, save / load and refusals.
#include "../src/crowd_core.hpp"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <limits>
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
static void setup(World &w, int wall_x = -1) {
	w.terrain.allocate(40, 40);
	if (wall_x >= 0) for (int y = 0; y < 40; ++y) w.terrain.flags[w.terrain.idx(wall_x, y)] = 0;
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

int main() {
	straight_line_five_cells();
	ninety_degree_turn();
	crew_down_stalls_the_anchor();
	removal_returns_crew_to_ordinary_behaviour();
	crew_ignore_ordinary_orders();
	save_load_mid_route_matches();
	invalid_requests_change_nothing();
	std::printf("CONVOY_NATIVE_CONTRACT checks=%d failures=%d\n", checks, failures);
	return failures ? 1 : 0;
}
