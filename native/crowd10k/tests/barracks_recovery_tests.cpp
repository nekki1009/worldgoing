// Barracks recovery regression: actual World API and the original fatigue stage.
// Link this file with crowd_core/combat/command/ai/crowd_c_api/state/render objects
// from one build_c2_c3.ps1 run, using that run's compiler and flags.
#include "../src/crowd_core.hpp"
#include "../src/crowd_c_api.h"
#include <cstdio>
#include <limits>

using namespace wg;
static int checks = 0, failures = 0;
static const char *test_case = "setup";
#define REQUIRE(c) do { ++checks; if (!(c)) { ++failures; std::fprintf(stderr, "FAIL %s line %d: %s\n", test_case, __LINE__, #c); } } while (false)

static constexpr int barracks = 0, member = 1, other = 3;
static constexpr double initial_fatigue = 60.0, game_seconds = 60.0;
static constexpr float action_seconds = 1.f / 30.f;
static constexpr double ordinary_recovery = 1.0 / 3.0; // 20 per game hour, over one game minute.
static constexpr double chinese_recovery = 5.0 / 12.0; // 25 per game hour, over one game minute.

static void close(double actual, double expected) {
    REQUIRE(std::abs(actual - expected) < 1e-9);
}

static void valid(const World &w) {
    std::string error;
    const bool ok = w.validate(&error);
    if (!ok) std::fprintf(stderr, "INVALID %s: %s\n", test_case, error.c_str());
    REQUIRE(ok);
}

static void set_fatigue(World &w, double rest = 30.0) {
    auto f = w.get_formation_state(barracks);
    f.fatigue = initial_fatigue;
    f.fatigue_rest = rest;
    w.set_formation_state(barracks, f);
}

static void setup(World &w) {
    w.terrain.allocate(48, 48);
    w.cfg.ai = false;
    w.cfg.auto_capture = false;
    w.cfg.rescue_seek_cells = 0;
    w.cfg.bleed_per_game_hour = 0;
    const int f = w.add_formation(0, 10.5f, 10.5f, 0, 3, 1, T_MELEE, 0);
    const int g = w.add_formation(2, 40.5f, 40.5f, kPi, 1, 1, T_MELEE, 0);
    rules::Equip equipment;
    equipment.family = rules::F_LONGSWORD;
    equipment.material = rules::M_IRON;
    for (int i = 0; i < 3; ++i) w.add_soldier(f, equipment, i == 0 ? R_CAPTAIN : R_REGULAR, 1001 + i);
    w.add_soldier(g, equipment, R_CAPTAIN, 2001);
    w.finalize();
    for (auto &formation : w.formations) formation.ai_enabled = false;
    REQUIRE(w.set_garrisoned(barracks, true));
    set_fatigue(w);
    w.events.clear();
    valid(w);
}

static double advance(World &w, double seconds = game_seconds, double combat = 0) {
    const double before = w.formations[barracks].fatigue;
    REQUIRE(w.step_clock(action_seconds, seconds, combat));
    valid(w);
    close(w.formations[barracks].recovery_multiplier, 1.0);
    return before - w.formations[barracks].fatigue;
}

static void eligible_recovery_and_consumption() {
    test_case = "eligible 1 vs 1.25 and next-step default";
    World ordinary(1), chinese(1);
    setup(ordinary); setup(chinese);
    REQUIRE(ordinary.set_recovery_input(barracks, 1.0));
    REQUIRE(chinese.set_recovery_input(barracks, 1.25));
    const double normal = advance(ordinary), boosted = advance(chinese);
    close(normal, ordinary_recovery);
    close(boosted, chinese_recovery);
    close(boosted / normal, 1.25);
    // The host supplies no recovery input for this next step.
    close(advance(ordinary), ordinary_recovery);
    close(advance(chinese), ordinary_recovery);
    std::printf("RECOVERY_RATE ordinary=%.12f chinese=%.12f next_step=1\n", normal, boosted);

    test_case = "original rest delay and zero-fatigue clamp";
    World delay(1), floor(1);
    setup(delay); setup(floor);
    set_fatigue(delay, 0);
    REQUIRE(delay.set_recovery_input(barracks, 1.25));
    close(advance(delay, 20), 0);
    close(delay.formations[barracks].fatigue_rest, 20);
    REQUIRE(delay.set_recovery_input(barracks, 1.25));
    close(advance(delay, 20), 25.0 / 3600.0 * 10.0);
    auto f = floor.get_formation_state(barracks);
    f.fatigue = 0.01;
    floor.set_formation_state(barracks, f);
    REQUIRE(floor.set_recovery_input(barracks, 1.25));
    close(advance(floor), 0.01);
    close(floor.formations[barracks].fatigue, 0);
}

static void living_roster_eligibility() {
    const char *names[] = {"awake/free", "KO", "get-up", "captive", "dead excluded"};
    for (int condition = 0; condition < 5; ++condition) {
        test_case = names[condition];
        World ordinary(1), chinese(1);
        setup(ordinary); setup(chinese);
        for (World *w : {&ordinary, &chinese}) {
            auto s = w->get_soldier_state(member);
            if (condition == 1) s.ko = 10000;
            if (condition == 2) s.getup = 1;
            if (condition == 3) { s.captive = 1; s.captor_person = 2001; s.prison_id = 1; }
            if (condition == 4) s.hp = 0;
            w->set_soldier_state(member, s);
            REQUIRE(w->hp[member] > 0 ? w->can_act(member) == (condition == 0) : !w->can_act(member));
            REQUIRE(w->set_recovery_input(barracks, w == &ordinary ? 1.0 : 1.25));
        }
        const double normal = advance(ordinary), boosted = advance(chinese);
        if (condition == 0 || condition == 4) {
            close(normal, ordinary_recovery); close(boosted, chinese_recovery);
        } else if (condition == 2) {
            close(normal, 0); close(boosted, 0); // Existing get-up gate blocks ordinary recovery too.
        } else {
            close(normal, ordinary_recovery); close(boosted, ordinary_recovery);
        }
        REQUIRE(chinese.formations[barracks].fatigue_count == (condition == 4 ? 2 : 3));
        std::printf("RECOVERY_ELIGIBILITY %s ordinary=%.12f requested_1.25=%.12f\n", names[condition], normal, boosted);
    }

    // Eligibility is re-read when consumed, even if the host supplied the bonus before the person changed.
    test_case = "KO after host input";
    World changed(1); setup(changed);
    REQUIRE(changed.set_recovery_input(barracks, 1.25));
    auto s = changed.get_soldier_state(member); s.ko = 10000;
    changed.set_soldier_state(member, s);
    close(advance(changed), ordinary_recovery);
}

static void existing_safety_gates() {
    const char *names[] = {"live hostile within eight cells", "melee", "engage", "encircle", "ranged", "moving", "running", "combat clock", "charged"};
    const SState busy_states[] = {S_FIGHT, S_ENGAGE, S_ENCIRCLE, S_RANGED};
    for (int condition = 0; condition < 9; ++condition) {
        test_case = names[condition];
        World w(1); setup(w);
        double combat = 0;
        if (condition == 0) {
            auto s = w.get_soldier_state(other);
            s.x = 16.5f; s.y = 10.5f;
            w.set_soldier_state(other, s); // Actual hostile person, not a synthetic threat flag.
        }
        // These public hot fields are the previous step's actual activity inputs to fatigue_stage.
        if (condition >= 1 && condition <= 4) w.state[member] = busy_states[condition - 1];
        if (condition == 5) w.vx[member] = 0.5f;
        if (condition == 6) w.running[member] = 1;
        if (condition == 7) combat = 1;
        if (condition == 8) w.formations[barracks].charged_this_step = true;
        REQUIRE(w.set_recovery_input(barracks, 1.25));
        const double recovered = advance(w, game_seconds, combat);
        close(recovered, condition == 6 ? -2.0 : 0.0); // Original run cost: six per minute / three living people.
        close(w.formations[barracks].fatigue_rest, 0);
        std::printf("RECOVERY_GATE %s recovered=%.12f consumed=1\n", names[condition], recovered);
    }

    test_case = "garrison rejects movement and attack orders";
    World w(1); setup(w);
    w.order_move(barracks, 15.5f, 10.5f, 0);
    REQUIRE(w.formations[barracks].order == Order::HOLD);
    w.order_attack(barracks, other);
    REQUIRE(w.formations[barracks].order == Order::HOLD && !w.formations[barracks].attacking);
    REQUIRE(w.set_recovery_input(barracks, 1.25));
    close(advance(w), chinese_recovery);
}

static void rejected_input_and_garrison_loss() {
    test_case = "invalid replacement clears valid target";
    for (double bad : {-1.0, 0.999, 1.250001, std::numeric_limits<double>::quiet_NaN(),
                       std::numeric_limits<double>::infinity(), -std::numeric_limits<double>::infinity()}) {
        World w(1); setup(w);
        REQUIRE(w.set_recovery_input(barracks, 1.25));
        REQUIRE(!w.set_recovery_input(barracks, bad));
        close(w.formations[barracks].recovery_multiplier, 1);
        close(advance(w), ordinary_recovery);
    }

    test_case = "invalid formation cannot change another pending input";
    World indexed(1); setup(indexed);
    REQUIRE(indexed.set_recovery_input(barracks, 1.25));
    const auto hash = indexed.state_hash();
    REQUIRE(!indexed.set_recovery_input(-1, 1.25));
    REQUIRE(!indexed.set_recovery_input(999, 1.25));
    REQUIRE(indexed.state_hash() == hash);
    close(advance(indexed), chinese_recovery);

    for (bool replace : {false, true}) {
        test_case = replace ? "non-garrison replacement rejected and reset" : "garrison lost after host input";
        World w(1); setup(w);
        REQUIRE(w.set_recovery_input(barracks, 1.25));
        REQUIRE(w.set_garrisoned(barracks, false));
        if (replace) {
            REQUIRE(!w.set_recovery_input(barracks, 1.25));
            close(w.formations[barracks].recovery_multiplier, 1);
        }
        close(advance(w), ordinary_recovery);
        REQUIRE(w.set_recovery_input(barracks, 1.0)); // Neutral input remains valid outside barracks.
    }
}

static void zero_game_time_and_rejected_action_time() {
    test_case = "zero game time consumes input";
    World w(1); setup(w);
    REQUIRE(w.set_recovery_input(barracks, 1.25));
    close(advance(w, 0), 0);
    close(advance(w), ordinary_recovery);

    test_case = "zero action time is rejected before consumption";
    REQUIRE(w.set_recovery_input(barracks, 1.25));
    const auto hash = w.state_hash();
    REQUIRE(!w.step_clock(0, game_seconds, 0));
    REQUIRE(w.state_hash() == hash);
    close(w.formations[barracks].recovery_multiplier, 1.25);
    close(advance(w), chinese_recovery);
}

static void kw06_and_c_api() {
    test_case = "Current original KW08 omits pending Site input and reload defaults to one";
    World w(1); setup(w);
    const auto blob = w.save();
    REQUIRE(blob.size() > 4 && blob[0] == 'K' && blob[1] == 'W' && blob[2] == '0' && blob[3] == '8');
    const auto ordinary_hash = w.state_hash();
    REQUIRE(w.set_recovery_input(barracks, 1.25));
    REQUIRE(w.state_hash() != ordinary_hash); // Pending input does affect the next step and its hash.
    REQUIRE(w.save() == blob); // It adds zero bytes or fields to current original KW08.
    World loaded(1); setup(loaded);
    REQUIRE(loaded.set_recovery_input(barracks, 1.25));
    if (!loaded.load(w.save())) { REQUIRE(false); return; }
    close(loaded.formations[barracks].recovery_multiplier, 1);
    REQUIRE(loaded.state_hash() == ordinary_hash);
    REQUIRE(loaded.save() == blob);
    close(advance(loaded), ordinary_recovery);
    close(advance(w), chinese_recovery);

    test_case = "C API runs identical recovery and one-step consumption";
    wg_crowd *c = wg_crowd_create(1, 0);
    REQUIRE(c != nullptr);
    if (!c) return;
    REQUIRE(wg_crowd_load(c, blob.data(), static_cast<int64_t>(blob.size())) == 1);
    REQUIRE(wg_crowd_set_recovery_input(c, barracks, 1.25) == 1);
    REQUIRE(wg_crowd_step_clock(c, action_seconds, game_seconds, 0) == 1);
    wg_formation_state state{};
    wg_crowd_get_formation_state(c, barracks, &state);
    close(initial_fatigue - state.fatigue, chinese_recovery);
    REQUIRE(wg_crowd_step_clock(c, action_seconds, game_seconds, 0) == 1);
    wg_crowd_get_formation_state(c, barracks, &state);
    close(initial_fatigue - state.fatigue, chinese_recovery + ordinary_recovery);
    REQUIRE(wg_crowd_set_recovery_input(c, barracks, 1.25) == 1);
    REQUIRE(wg_crowd_set_recovery_input(c, barracks, 2.0) == 0);
    REQUIRE(wg_crowd_step_clock(c, action_seconds, game_seconds, 0) == 1);
    wg_crowd_get_formation_state(c, barracks, &state);
    close(initial_fatigue - state.fatigue, chinese_recovery + 2 * ordinary_recovery);
    wg_crowd_destroy(c);
}

int main() {
    eligible_recovery_and_consumption();
    living_roster_eligibility();
    existing_safety_gates();
    rejected_input_and_garrison_loss();
    zero_game_time_and_rejected_action_time();
    kw06_and_c_api();
    std::printf("BARRACKS_RECOVERY_NATIVE_%s checks=%d failures=%d\n", failures ? "FAIL" : "PASS", checks, failures);
    return failures ? 1 : 0;
}
