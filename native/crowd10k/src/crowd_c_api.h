/* worldgoing crowd10k - plain C ABI for the Godot binding (v2: full exchange-mode battle rules).
 *
 * Integration: compile crowd_core.cpp, combat.cpp, command.cpp, ai.cpp, state.cpp and crowd_c_api.cpp into the
 * native/army_idle DLL (or a sibling) and expose these as methods of one extension class ("ArmyCrowd"),
 * passing Packed arrays by pointer. No Dictionary / Variant per soldier. All calls from the owning thread;
 * step() uses internal worker threads and never calls back into Godot.
 */
#ifndef WG_CROWD_C_API_H
#define WG_CROWD_C_API_H
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct wg_crowd wg_crowd;
enum wg_order_result { WG_OK=0, WG_NOT_OWNER=1, WG_BAD_FORMATION=2, WG_BAD_ARGS=3, WG_NO_TARGET=4, WG_BLOCKED=5, WG_NOT_ROUTED=6, WG_ROUTED=7, WG_NO_ORDERS=8 };
int wg_crowd_host_order(wg_crowd *c, int f, int kind, float gx, float gy, double x);
int wg_crowd_validate(const wg_crowd *c);
int wg_crowd_set_sustain_input(wg_crowd *c, int f, int fully_fed, double delta);
/* One-step Site-derived fatigue recovery input (1..1.25); consumed even when game time is zero, not saved. */
int wg_crowd_set_recovery_input(wg_crowd *c, int f, double multiplier);
int wg_crowd_set_housing_recovery_input(wg_crowd *c, int f, double multiplier);
int wg_crowd_order_controlled_step(wg_crowd *c, int person, int destination, int kind);
void wg_crowd_cancel_controlled_step(wg_crowd *c, int person, int kind);
int wg_crowd_apply_environment_damage(wg_crowd *c, int i, double amount);
int wg_crowd_apply_melee_contact(wg_crowd *c, int i, double hp_loss, double stun_add);
int wg_crowd_charge_exchange_fatigue(wg_crowd *c, int i, double amount);
/* G4 logistics convoys. Ids start at 1; 0 / 0 result = refused with no state change. Crew stand at anchor + (ox, oy)
 * rotated by facing; the anchor advances only while every crew member is able to act and on its slot. */
int wg_crowd_add_convoy(wg_crowd *c, float ax, float ay, float facing);
int wg_crowd_convoy_set_crew(wg_crowd *c, int id, int soldier, int ox, int oy, int assigned);
int wg_crowd_convoy_order_goal(wg_crowd *c, int id, float gx, float gy, float gfacing);
int wg_crowd_convoy_set_body(wg_crowd *c, int id, const int32_t *cells, int count);
/* out[7] = anchor x, y, facing, moving, complete, stalled, reason (ConvoyReason). Returns 1 when the convoy exists. */
int wg_crowd_convoy_state(const wg_crowd *c, int id, double *out);
int wg_crowd_convoy_remove(wg_crowd *c, int id);
/* G4 formation following: attach to a formation whose members are the whole crew (1 ok), detach, and the attached
   formation (-1 detached, -2 unknown convoy). An explicit goal order detaches. */
int wg_crowd_convoy_attach_formation(wg_crowd *c, int id, int formation);
int wg_crowd_convoy_detach_formation(wg_crowd *c, int id);
int wg_crowd_convoy_formation(const wg_crowd *c, int id);
/* G6.4 site exit: 1 when the soldier may leave the Site (conscious, free, in a formation, not in melee, no committed step). */
int wg_crowd_site_person_exit_ready(const wg_crowd *c, int i);
/* Releases a ready soldier from the live pool and formation. out[8] = {hp, fatigue, fatigue_rest, ammo, cell_x, cell_y, x, y}
 * (fatigue = formation pool). Returns 1 on release; 0 refuses and writes nothing. */
int wg_crowd_site_person_release(wg_crowd *c, int i, double *out);
/* G1 S1 aboard: board / land / set_deck / retarget_aboard return 1 on success, 0 refused with no change.
 * site_person_aboard writes out[2] = {aboard, vehicle} and returns 1, or 0 for an unknown soldier. */
int wg_crowd_site_person_board(wg_crowd *c, int i, int vehicle);
int wg_crowd_site_person_land(wg_crowd *c, int i, double x, double y);
int wg_crowd_site_person_set_deck(wg_crowd *c, int i, double x, double y);
int wg_crowd_site_person_retarget_aboard(wg_crowd *c, int i, int vehicle);
int wg_crowd_site_person_aboard(const wg_crowd *c, int i, double *out);
/* G5 S1 absent / return / move. absent(kind 1..4), return(formation, x, y) and move_member(to_formation) return 1 on
 * success, 0 refused with no change. site_person_absent_state writes out[2] = {absent, absent_kind} and returns 1, or 0
 * for an unknown soldier. */
int wg_crowd_site_person_absent(wg_crowd *c, int i, int kind);
int wg_crowd_site_person_return(wg_crowd *c, int i, int formation, double x, double y);
int wg_crowd_move_member(wg_crowd *c, int i, int to_formation);
int wg_crowd_site_person_absent_state(const wg_crowd *c, int i, double *out);
/* G5 S4 surrender. soldier_surrendered writes out[0] = 0/1 and returns 1, or 0 for an unknown soldier.
 * set_soldier_surrendered(i, on) returns 1 on success, 0 refused with no change (on needs a living, uncaptured,
 * unabsent, unaboard soldier outside escort, rescue, capture and siege). off clears it. */
int wg_crowd_soldier_surrendered(const wg_crowd *c, int i, double *out);
int wg_crowd_set_soldier_surrendered(wg_crowd *c, int i, int on);
int wg_crowd_has_projectiles(const wg_crowd *c);

wg_crowd *wg_crowd_create(int threads, int64_t site_seed);
void wg_crowd_destroy(wg_crowd *c);
void wg_crowd_set_ai(wg_crowd *c, int enabled);
/* faction relation by full faction id (0..255); default: any two different factions are hostile */
void wg_crowd_set_hostile(wg_crowd *c, int faction_a, int faction_b, int hostile);
/* rescue walk radius (cells, 0 = adjacent only) and AI auto-capture (2026-09-29 defaults: 8, on, 8) */
void wg_crowd_set_wounded_rules(wg_crowd *c, float rescue_seek_cells, int auto_capture, float capture_seek_cells);

/* TerrainData layout (row-major w*h): height_levels, flags (WALKABLE=1), ramp_edges (N/E/S/W bits),
 * static_blocked (0/1, may be NULL), facility (1 = completed defence position, may be NULL). */
void wg_crowd_set_terrain(wg_crowd *c, int w, int h, const uint8_t *height_levels, const uint8_t *flags,
                          const uint8_t *ramp_edges, const uint8_t *static_blocked, const uint8_t *facility);

/* troop: 0 melee, 1 bow, 2 crossbow. training 0-100 (team shared, D22). */
int wg_crowd_add_formation(wg_crowd *c, int team, float cx, float cy, float facing, int cols, float spacing, int troop,
                           double training);
/* family / material / armor codes: see rules.hpp (Family, Material, Armor). role: 0 regular, 1 captain, 2 officer. */
int wg_crowd_add_soldier(wg_crowd *c, int formation, int64_t person_id, int family, int material, int armor, int shield,
                         int role, int ammo);
void wg_crowd_finalize(wg_crowd *c);

/* Single decision owner per formation. ai_owned = 1: the native tactical AI decides and host orders are
 * refused (return WG_NOT_OWNER); ai_owned = 0: only the host (player / GDScript AI) orders it. Default: AI-owned. */
void wg_crowd_set_order_owner(wg_crowd *c, int formation, int ai_owned);
int wg_crowd_order_move(wg_crowd *c, int formation, float gx, float gy, float gfacing);
int wg_crowd_order_attack(wg_crowd *c, int formation, int target_soldier);
int wg_crowd_order_hold(wg_crowd *c, int formation);
int wg_crowd_order_pursue(wg_crowd *c, int formation, int target_soldier);
int wg_crowd_order_retreat(wg_crowd *c, int formation, float gx, float gy);
int wg_crowd_order_capture(wg_crowd *c, int guard, int target);

/* Time. wg_crowd_step runs the Site clock itself (combat_left: 1:1, else 1 s = 60 game s, x speed).
 * wg_crowd_step_clock takes the host clock instead: action seconds, game seconds of this slice and the
 * Site combat_left; afterwards wg_crowd_combat_mark returns the largest combat_event duration raised in
 * that step (0 = none) for SiteRuntime.mark_combat. */
int wg_crowd_step(wg_crowd *c, float dt);
int wg_crowd_step_clock(wg_crowd *c, float action_dt, double game_seconds, double combat_left);
double wg_crowd_combat_mark(const wg_crowd *c);
double wg_crowd_combat_left(const wg_crowd *c);
int wg_crowd_pack_render(wg_crowd *c, float *out, int capacity, float cell_pixels);

/* Events since the last drain, in commit order. kind: 0 death, 1 KO, 2 wake, 3 rescued (other = rescuer),
 * 4 captured (other = captor), 5 escaped, 6 succession (person = new commander, other = previous),
 * 7 command lost (other = previous commander), 8 rout, 9 rally, 10 shot (ammo -1). time = action seconds. */
int wg_crowd_drain_events(wg_crowd *c, int *kind, int64_t *person, int64_t *other, int *formation, double *time, int capacity);

/* SiteStore boundary: import after finalize, export at any time. captor_person / commanders by person id. */
typedef struct wg_soldier_state {
	double hp, stun, grace, ko, getup, stagger;
	int captive; int64_t captor_person; int bandaged; int ammo;
	int tactics, leadership, coach; /* -1 = no command ability yet */
	double escape_t, exch_cd, ranged_cd, skill_cd, knock_t, act_t;
	int role; float x, y, facing;
} wg_soldier_state;
typedef struct wg_formation_state {
	double morale, rally_rest, fatigue, fatigue_rest, training;
	int routed, needs_attack_order, commander_present;
	int64_t formal_person, acting_person;
	int officer_count; int64_t officers[16];
	int64_t current_person, target_person;
	int fatigue_count, order, ai_enabled, no_orders, host_center;
	float goal_x, goal_y, goal_facing, cx, cy, facing, origin_x, origin_y, ref_x, ref_y;
	double pursuit_left, order_delay; int attacking, ref_valid, resupplying;
} wg_formation_state;
void wg_crowd_set_soldier_state(wg_crowd *c, int soldier, const wg_soldier_state *s);
void wg_crowd_get_soldier_state(const wg_crowd *c, int soldier, wg_soldier_state *s);
void wg_crowd_set_formation_state(wg_crowd *c, int formation, const wg_formation_state *s);
void wg_crowd_get_formation_state(const wg_crowd *c, int formation, wg_formation_state *s);
int wg_crowd_get_officers(const wg_crowd *c, int f, int64_t *ids, int capacity);
int wg_crowd_set_officers(wg_crowd *c, int f, const int64_t *ids, int count);
int wg_crowd_set_soldier_equip(wg_crowd *c, int i, int family, int material, int armor, int shield);
int wg_crowd_set_soldier_ammo(wg_crowd *c, int i, int amount);
int wg_crowd_soldier_index(const wg_crowd *c, int64_t person_id);

/* Complete save / load (same build). save: returns the size; writes when out != NULL and capacity fits. */
int64_t wg_crowd_save(const wg_crowd *c, uint8_t *out, int64_t capacity);
int wg_crowd_load(wg_crowd *c, const uint8_t *data, int64_t size);

int wg_crowd_soldier_count(const wg_crowd *c);
/* hp, stun, ko seconds, alive, captive, state (SState), target soldier */
void wg_crowd_get_soldier(const wg_crowd *c, int i, float *x, float *y, double *hp, double *stun, double *ko, int *captive,
                          int *state, int *target);
/* external damage from a non-crowd source (player, live captain): same contact rule */
void wg_crowd_apply_contact(wg_crowd *c, int i, double hp_loss, double stun_add);
/* morale, fatigue, routed, current commander soldier index, order */
void wg_crowd_get_formation(const wg_crowd *c, int f, double *morale, double *fatigue, int *routed, int *commander, int *order);
uint64_t wg_crowd_state_hash(const wg_crowd *c);

#ifdef __cplusplus
}
#endif
#endif
