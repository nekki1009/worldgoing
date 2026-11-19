// Link against the same original World objects as the paired native build.
// Initial imported positions are fixture setup; the fall, rescue progress,
// obstacle resolution and continuation all use original World APIs/steps.
#include "../src/crowd_core.hpp"
#include <algorithm>
#include <cmath>
#include <cstdio>

using namespace wg;
static int checks = 0, failures = 0;
static const char *case_name = "setup";
#define CHECK(c) do { ++checks; if (!(c)) { ++failures; std::fprintf(stderr, "FAIL %s:%d %s: %s\n", __FILE__, __LINE__, case_name, #c); } } while (false)
static constexpr float DT = 1.f / 120.f;
static constexpr int RESCUER = 0, PATIENT = 1;
static constexpr int64_t RESCUER_ID = 8101, PATIENT_ID = 8102;

static void validate(const World &w) {
    std::string reason;
    const bool valid = w.validate(&reason);
    if (!valid) std::fprintf(stderr, "INVALID %s: %s\n", case_name, reason.c_str());
    CHECK(valid);
}

static void step(World &w) {
    CHECK(w.step_clock(DT, DT, 30.0));
    validate(w);
}

struct Fixture {
    World w{1};
    std::vector<int> blocked;
    std::vector<int64_t> exits;
    int formation = 0;
    int patient_formation = 0;

    // Mode 1 has an enemy patient; mode 2 a same-faction different formation.
    explicit Fixture(int mode = 0, float patient_y = 41.05f, bool siege = true,
                     bool static_wall = false, bool different_level = false,
                     bool other_wreck = false, bool own_domain = true) {
        w.terrain.allocate(72, 72);
        w.terrain.base_height.assign(w.terrain.height.size(), 0);
        w.cfg.ai = false;
        w.cfg.auto_capture = false;
        w.cfg.rescue_seek_cells = 8.f;
        formation = w.add_formation(0, 41.5f, 39.7f, 0.f, 1, 1.f, T_MELEE, 0.0);
        wg::rules::Equip equipment;
        equipment.family = wg::rules::F_LONGSWORD;
        equipment.material = wg::rules::M_IRON;
        w.add_soldier(formation, equipment, R_CAPTAIN, RESCUER_ID);
        patient_formation = mode == 0 ? formation : w.add_formation(mode == 1 ? 1 : 0, 41.5f, patient_y, 0.f, 1, 1.f, T_MELEE, 0.0);
        w.add_soldier(patient_formation, equipment, mode == 0 ? R_REGULAR : R_CAPTAIN, PATIENT_ID);
        const int far = w.add_formation(2, 65.5f, 65.5f, 0.f, 1, 1.f, T_MELEE, 0.0);
        w.add_soldier(far, equipment, R_CAPTAIN, 8201);
        for (int y = 40; y <= 42; ++y) for (int x = 40; x <= 44; ++x) {
            const int cell = w.terrain.idx(x, y);
            w.terrain.height[cell] = 2;
            if (siege) blocked.push_back(cell);
        }
        w.finalize();
        auto r = w.get_soldier_state(RESCUER);
        r.x = 41.5f; r.y = 39.7f;
        w.set_soldier_state(RESCUER, r);
        auto p = w.get_soldier_state(PATIENT);
        p.x = 41.5f; p.y = patient_y;
        w.set_soldier_state(PATIENT, p);
        for (int f = 0; f < (int)w.formations.size(); ++f) w.order_hold(f);

        // The original two-level surface removal creates the real 30 HP fall
        // and four-hour KO. No HP/KO/bandaged setter creates the positive case.
        Terrain fallen = w.terrain;
        for (int y = 40; y <= 42; ++y) for (int x = 40; x <= 44; ++x) fallen.height[fallen.idx(x, y)] = 0;
        if (different_level) fallen.height[fallen.idx(41, 41)] = 1;
        if (static_wall) fallen.static_blocked[fallen.idx(41, 40)] = 1;
        CHECK(w.update_terrain(fallen));
        CHECK(w.cell[PATIENT] == w.terrain.idx(41, 41));
        CHECK(w.ko[PATIENT] > 3600.0 && w.contact_revision[PATIENT] == 1);
        CHECK(std::abs(w.hp[PATIENT] - (different_level ? 85.0 : 70.0)) < 1e-9);
        if (siege && own_domain) {
            for (int c : blocked) {
                if (other_wreck && c != w.cell[PATIENT]) continue;
                exits.insert(exits.end(), {PATIENT, PATIENT_ID, c});
            }
        }
        CHECK(w.set_siege_navigation(blocked, exits));
        w.events.clear();
        validate(w);
    }

    float distance() const { return std::hypot(w.px[PATIENT] - w.px[RESCUER], w.py[PATIENT] - w.py[RESCUER]); }
};

static void expect_no_rescue(Fixture &f) {
    const auto original = f.w.person_id;
    for (int i = 0; i < 120; ++i) step(f.w);
    CHECK(f.w.stats.rescues_started == 0 && f.w.stats.rescues_done == 0);
    CHECK(f.w.rescue_of[RESCUER] < 0 && !f.w.bandaged[PATIENT]);
    CHECK(f.w.person_id == original && f.w.contact_revision[PATIENT] == 1);
    CHECK(f.w.cell[PATIENT] == f.w.terrain.idx(41, 41));
}

static void positive_and_replay() {
    case_name = "own fallen domain, 1.35 actual distance, four stopped action seconds";
    Fixture f;
    CHECK(f.distance() > 1.3f && f.distance() < 1.5f);
    CHECK(!f.w.siege_route_cell(f.w.terrain.idx(41, 40)));
    const auto ids = f.w.person_id;
    const auto before_order = f.w.state_hash();
    CHECK(!f.w.order_siege_step(RESCUER, f.w.terrain.idx(41, 40)));
    CHECK(f.w.state_hash() == before_order); // Rescue never permits wreck entry.
    for (int i = 0; i < 30 && f.w.stats.rescues_started == 0; ++i) step(f.w);
    CHECK(f.w.stats.rescues_started == 1 && f.w.rescue_of[RESCUER] == PATIENT);
    const double began = f.w.time;
    double stopped_action_seconds = 0.0;
    for (int i = 0; i < 120; ++i) {
        if (f.distance() <= 1.5f && std::abs(f.w.vx[RESCUER]) <= 1e-6f && std::abs(f.w.vy[RESCUER]) <= 1e-6f) stopped_action_seconds += DT;
        step(f.w);
        CHECK(f.w.cell[RESCUER] == f.w.terrain.idx(41, 39));
        CHECK(std::abs(f.w.vx[RESCUER]) <= 1e-6f && std::abs(f.w.vy[RESCUER]) <= 1e-6f);
        CHECK(f.distance() <= 1.5f && !f.w.bandaged[PATIENT]);
    }
    const auto bytes = f.w.save();
    World replay(1);
    CHECK(replay.load(bytes, f.blocked, f.exits));
    CHECK(replay.state_hash() == f.w.state_hash() && replay.person_id == ids);
    for (int i = 0; i < 400 && !f.w.bandaged[PATIENT]; ++i) {
        if (f.distance() <= 1.5f && std::abs(f.w.vx[RESCUER]) <= 1e-6f && std::abs(f.w.vy[RESCUER]) <= 1e-6f) stopped_action_seconds += DT;
        step(f.w); step(replay);
        CHECK(replay.state_hash() == f.w.state_hash());
        CHECK(f.w.cell[RESCUER] == f.w.terrain.idx(41, 39));
        CHECK(f.w.cell[PATIENT] == f.w.terrain.idx(41, 41));
        if (!f.w.bandaged[PATIENT]) CHECK(std::abs(f.w.vx[RESCUER]) <= 1e-6f && std::abs(f.w.vy[RESCUER]) <= 1e-6f);
        if (f.w.time - began < wg::rules::RESCUE_SECONDS - DT) CHECK(!f.w.bandaged[PATIENT]);
    }
    CHECK(f.w.stats.rescues_done == 1 && replay.stats.rescues_done == 1);
    CHECK(f.w.bandaged[PATIENT] && f.w.hp[PATIENT] > 0.0 && f.w.ko[PATIENT] > 0.0 && f.w.ko[PATIENT] <= 3600.0);
    CHECK(f.w.time - began >= wg::rules::RESCUE_SECONDS - DT);
    CHECK(stopped_action_seconds >= wg::rules::RESCUE_SECONDS - DT);
    CHECK(f.w.person_id == ids && f.w.contact_revision[PATIENT] == 1);
    int rescued_events = 0;
    for (const auto &e : f.w.events) if (e.kind == EV_RESCUED) {
        ++rescued_events;
        CHECK(e.person == PATIENT_ID && e.other == RESCUER_ID && e.soldier == PATIENT);
    }
    CHECK(rescued_events == 1);
}

// Side kinds: 0 clear, 1 unrelated wreck, 2 patient's own wreck, 3 static wall.
// The first original tick performs formation 0's real rescue admission before
// movement. Exact pre-tick coordinates prove this is the diagonal DDA branch.
static void diagonal_admission(int x_kind, int y_kind, bool expected) {
    World w(1);
    w.terrain.allocate(72, 72);
    w.terrain.base_height.assign(w.terrain.height.size(), 0);
    w.cfg.ai = false;
    w.cfg.auto_capture = false;
    w.cfg.rescue_seek_cells = 8.f;
    const int f = w.add_formation(0, 39.15f, 39.15f, 0.f, 1, 1.f, T_MELEE, 0.0);
    wg::rules::Equip equipment;
    equipment.family = wg::rules::F_LONGSWORD;
    equipment.material = wg::rules::M_IRON;
    w.add_soldier(f, equipment, R_CAPTAIN, RESCUER_ID);
    w.add_soldier(f, equipment, R_REGULAR, PATIENT_ID);
    const int patient_cell = w.terrain.idx(40, 40);
    const int side_x = w.terrain.idx(40, 39), side_y = w.terrain.idx(39, 40);
    w.terrain.height[patient_cell] = 2;
    w.finalize();
    auto r = w.get_soldier_state(RESCUER);
    r.x = 39.15f; r.y = 39.15f;
    w.set_soldier_state(RESCUER, r);
    auto p = w.get_soldier_state(PATIENT);
    p.x = 40.10f; p.y = 40.10f;
    w.set_soldier_state(PATIENT, p);
    w.order_hold(f);
    Terrain fallen = w.terrain;
    fallen.height[patient_cell] = 0;
    if (x_kind == 3) fallen.static_blocked[side_x] = 1;
    if (y_kind == 3) fallen.static_blocked[side_y] = 1;
    CHECK(w.update_terrain(fallen));
    CHECK(w.ko[PATIENT] > 3600.0 && w.contact_revision[PATIENT] == 1);
    CHECK(std::abs(w.hp[PATIENT] - 70.0) < 1e-9);
    std::vector<int> blocked{patient_cell};
    std::vector<int64_t> exits{PATIENT, PATIENT_ID, patient_cell};
    if (x_kind == 1 || x_kind == 2) blocked.push_back(side_x);
    if (y_kind == 1 || y_kind == 2) blocked.push_back(side_y);
    if (x_kind == 2) exits.insert(exits.end(), {PATIENT, PATIENT_ID, side_x});
    if (y_kind == 2) exits.insert(exits.end(), {PATIENT, PATIENT_ID, side_y});
    CHECK(w.set_siege_navigation(blocked, exits));
    validate(w);
    const float dx = w.px[PATIENT] - w.px[RESCUER], dy = w.py[PATIENT] - w.py[RESCUER];
    CHECK(std::abs(dx - dy) < 1e-7f && dx * dx + dy * dy > 1.3f * 1.3f && dx * dx + dy * dy < 1.5f * 1.5f);
    CHECK(w.tick == 0 && w.cell[PATIENT] == patient_cell && w.cell[RESCUER] == w.terrain.idx(39, 39));
    const auto ids = w.person_id;
    step(w);
    CHECK(w.stats.rescues_started == (expected ? 1 : 0));
    CHECK(w.rescue_of[RESCUER] == (expected ? PATIENT : -1));
    CHECK(w.stats.rescues_done == 0 && !w.bandaged[PATIENT]);
    CHECK(w.person_id == ids && w.cell[PATIENT] == patient_cell && w.contact_revision[PATIENT] == 1);
}

int main() {
    positive_and_replay();
    { case_name = "diagonal own target with clear side cells admits original rescue"; diagonal_admission(0, 0, true); }
    { case_name = "diagonal unrelated east side wreck blocks rescue"; diagonal_admission(1, 0, false); }
    { case_name = "diagonal unrelated south side wreck blocks rescue"; diagonal_admission(0, 1, false); }
    { case_name = "diagonal own side wrecks remain inside the one patient domain"; diagonal_admission(2, 2, true); }
    { case_name = "diagonal original east static wall remains blocking"; diagonal_admission(3, 0, false); }
    { case_name = "diagonal original south static wall remains blocking"; diagonal_admission(0, 3, false); }
    { case_name = "own wreck farther than 1.5 remains LOS-blocked"; Fixture f(0, 41.25f); CHECK(f.distance() > 1.5f); expect_no_rescue(f); }
    { case_name = "original static wall inside own wreck remains blocking"; Fixture f(0, 41.05f, true, true); expect_no_rescue(f); }
    { case_name = "different terrain layer remains blocking"; Fixture f(0, 41.05f, true, false, true); expect_no_rescue(f); }
    { case_name = "unrelated blocked cells outside patient domain remain blocking"; Fixture f(0, 41.05f, true, false, false, true); expect_no_rescue(f); }
    { case_name = "no original allowed exit domain cannot borrow the exception"; Fixture f(0, 41.05f, true, false, false, false, false); expect_no_rescue(f); }
    { case_name = "ordinary non-siege static wall keeps original admission"; Fixture f(0, 41.05f, false, true); expect_no_rescue(f); }
    { case_name = "enemy original patient cannot be rescued"; Fixture f(1); expect_no_rescue(f); }
    { case_name = "same faction different formation keeps original team rule"; Fixture f(2); expect_no_rescue(f); }
    { case_name = "captive original patient cannot be rescued"; Fixture f; auto state = f.w.get_soldier_state(PATIENT); state.captive = 1; state.captor_person = 8201; f.w.set_soldier_state(PATIENT, state); validate(f.w); expect_no_rescue(f); }
    { case_name = "ordinary non-siege clear approach still completes"; Fixture f(0, 41.05f, false); for (int i = 0; i < 720 && !f.w.bandaged[PATIENT]; ++i) step(f.w); CHECK(f.w.stats.rescues_done == 1 && f.w.bandaged[PATIENT]); }
    std::printf("SIEGE_RESCUE_REACH_%s: %d checks, %d failures\n", failures ? "FAIL" : "PASS", checks, failures);
    return failures ? 1 : 0;
}
