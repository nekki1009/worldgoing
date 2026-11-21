// Output candidate. Build only against the candidate original crowd_core target.
// Functional owner/packet tests only; this is NOT Lab/P6 acceptance or a benchmark.
#include "../src/crowd_core.hpp"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <limits>

using namespace wg;
using namespace wg::rules;
static int checks=0, failures=0;
#define CHECK(c,msg) do { ++checks; if(!(c)){++failures;std::printf("FAIL line %d: %s\n",__LINE__,msg);} } while(0)

struct Fixture {
	World w{1};
	Fixture() {
		w.terrain.allocate(30,30); w.cfg.ai=false; w.cfg.auto_capture=false; w.cfg.rescue_seek_cells=0;
		w.combat_left=30;
		Equip bow; bow.family=F_BOW; bow.material=M_IRON; bow.armor=A_LEATHER;
		int a=w.add_formation(0,10,10,0,1,1,T_BOW,0);
		int b=w.add_formation(1,16,10,0,1,1,T_MELEE,0);
		w.add_soldier(a,bow,R_CAPTAIN,101,3);
		w.add_soldier(b,bow,R_CAPTAIN,202,0);
		w.finalize();
		w.order_hold(a); w.order_hold(b);
		w.px[0]=w.nx[0]=10.5f; w.py[0]=w.ny[0]=10.5f;
		w.px[1]=w.nx[1]=16.5f; w.py[1]=w.ny[1]=10.5f;
	}
};

static void ownership_and_release() {
	Fixture f; auto &w=f.w; RangedShooter receipt;
	const auto unowned=w.save();
	CHECK(!w.commit_host_ranged(0,3,1,1,16,10,false,receipt) && w.save()==unowned,"guarded before explicit owner selection");
	CHECK(w.set_host_ranged_delegate(true),"select sole host flight owner");
	const auto before=w.save();
	CHECK(!w.commit_host_ranged(0,2,1,1,16,10,true,receipt) && w.save()==before,"stale ammo rejected before skill/fatigue/debit");
	CHECK(!w.commit_host_ranged(0,3,2,1,16,10,true,receipt) && w.save()==before,"unknown fire mode rejected atomically");
	CHECK(!w.commit_host_ranged(0,3,1,1,11,10,true,receipt) && w.save()==before,"adjacent aim rejected atomically");
	// Structure aim points need not be walkable; physical contact remains Lab-owned.
	w.terrain.static_blocked[w.terrain.idx(16,10)]=1;
	CHECK(w.commit_host_ranged(0,3,1,7,16,10,false,receipt),"original bow release accepts a structure aim");
	CHECK(w.ammo[0]==2 && w.stats.shots==1 && w.projectiles.empty() && w.host_last_release_id==7,"one original debit and no second flight pool");
	CHECK(receipt.ability==TROOP_COMBAT_ABILITY && receipt.fatigue < w.formations[0].fatigue && w.ranged_cd[0]>0,"receipt snapshots original precharge shooter");
	const auto paid=w.save();
	CHECK(!w.commit_host_ranged(0,2,1,7,16,10,false,receipt) && w.save()==paid,"same release id cannot charge twice");
	w.terrain.static_blocked[w.terrain.idx(16,10)]=0;
	w.order_move(0,12.f,10.f,0.f);
	const auto shots=w.stats.shots;
	for(int k=0;k<4;++k) {
		const float from_x=w.px[0], from_y=w.py[0];
		CHECK(w.step_clock(1.f/30.f,1.0/30.0,30.0),"original World step");
		const MotionSegment segment=w.motion_segment(0);
		CHECK(segment.from_x==from_x && segment.from_y==from_y && segment.to_x==w.px[0] && segment.to_y==w.py[0],"host receives the exact original completed-step movement segment");
	}
	CHECK(w.projectiles.empty() && w.ammo[0]==2 && w.stats.shots==shots,"later native step never re-fires a host release");
	Fixture legacy; legacy.w.projectiles.emplace_back(); const auto old=legacy.w.save();
	CHECK(!legacy.w.set_host_ranged_delegate(true) && legacy.w.save()==old,"legacy paid flight must settle before switching ownership");
}

static void original_damage_and_casualty() {
	Fixture f; auto &w=f.w; CHECK(w.set_host_ranged_delegate(true),"damage bridge ownership");
	const auto rev=w.contact_revision[1]; const auto before=w.save();
	CHECK(!w.apply_fire_exposure_damage(1,std::numeric_limits<double>::quiet_NaN()) && w.save()==before,"nonfinite exposure rejected atomically");
	CHECK(w.apply_fire_exposure_damage(1,2.5) && w.hp[1]==97.5 && w.contact_revision[1]==rev,"thermal damage uses original HP without effective contact revision");
	w.skill[1]=SK_BRACE;
	CHECK(w.apply_host_projectile_contact(1,3,0,0.2) && w.hp[1]==94.5 && w.contact_revision[1]==rev+1,"physical hit uses original contact owner once");
	CHECK(w.skill[1]==SK_NONE && w.skill_cd[1]==EXCHANGE_SKILL_COOLDOWN,"physical arrow consumes existing brace once");
	const auto deaths=w.stats.deaths; const auto life=w.life_ck[1];
	CHECK(w.apply_fire_exposure_damage(1,200) && w.hp[1]==0 && w.stats.deaths==deaths+1,"fire death uses original death event");
	CHECK(w.life_ck[1]==life,"fire death leaves original combat casualty checkpoint for sustain");
	CHECK(w.apply_fire_exposure_damage(1,200) && w.stats.deaths==deaths+1,"dead body never emits a second death");
	const auto count=std::count_if(w.events.begin(),w.events.end(),[](const Event &e){return e.kind==EV_DEATH;});
	CHECK(count==1,"one original death event to drain at the completed shared boundary");
}

static void shared_fire_safe_rest() {
	Fixture f; auto &w=f.w;
	w.px[1]=w.nx[1]=27.5f; w.py[1]=w.ny[1]=27.5f; w.cell[1]=w.terrain.idx(27,27);
	w.formations[0].fatigue=40.0; w.formations[0].fatigue_rest=30.0;
	CHECK(w.set_fire_safe_rest_input(0,true),"accept one-step all-members-safe fire rest proof");
	CHECK(w.step_clock(1.f/30.f,1.0,30.0),"original shared time advances while fire is active");
	CHECK(w.formations[0].fatigue<40.0,"safe formation recovers despite the fire-raised Site combat clock");
	CHECK(!w.set_fire_safe_rest_input(2,true),"reject an unknown formation rest input");
	Fixture blocked; auto &b=blocked.w;
	b.px[1]=b.nx[1]=27.5f; b.py[1]=b.ny[1]=27.5f; b.cell[1]=b.terrain.idx(27,27);
	b.formations[0].fatigue=40.0; b.formations[0].fatigue_rest=30.0;
	CHECK(b.set_fire_safe_rest_input(0,false),"clear the derived safe-rest proof");
	CHECK(b.step_clock(1.f/30.f,1.0,30.0),"unsafe fire step still advances through the original clock");
	CHECK(b.formations[0].fatigue==40.0,"missing all-members-safe proof keeps the original combat-time rest guard");
	Fixture pending; CHECK(pending.w.set_fire_safe_rest_input(0,true),"set transient rest proof before snapshot");
	World restored(1); CHECK(restored.load(pending.w.save()),"restore original Native state");
	CHECK(!restored.formations[0].host_fire_rest_safe,"safe-rest proof is derived again after hot load");
}

static void persistence_and_existing_visual_channel() {
	Fixture f; auto &w=f.w; RangedShooter receipt;
	CHECK(w.set_host_ranged_delegate(true) && w.commit_host_ranged(0,3,0,9,16,10,false,receipt),"save a paid host release watermark");
	const auto hash=w.state_hash();
	CHECK(w.set_fire_visual_rows({0,1},{1,2}) && w.state_hash()==hash,"derived burn flags do not become simulation authority");
	const auto flags=w.fire_visual;
	CHECK(!w.set_fire_visual_rows({0,0},{1,2}) && w.fire_visual==flags,"duplicate presentation rows rejected without mutation");
	RenderTrack t; t.sequence=0; t.duration=1; t.loop=true; t.times={0}; t.ax={0}; t.ay={0}; w.render_tracks.push_back(t);
	RenderKit kit{}; kit.page=0; kit.palette=0; kit.scale=1;
	for(int s=0;s<V_COUNT;++s) for(int d=0;d<4;++d) kit.track[s][d]=0;
	w.render_kits.push_back(kit); w.kit.assign(2,0);
	std::vector<float> out,bounds; std::vector<int32_t> spans;
	CHECK(w.pack_rows(out,spans,bounds,64)==2,"original atlas packs both real bodies");
	int burn=0,corpse=0;
	for(size_t s=0;s+5<spans.size();s+=World::SPAN_STRIDE) if(spans[s+1]>=0)
		for(int i=0;i<spans[s+3];++i){float flag=out[(spans[s+2]+i)*12+11];burn+=flag==1;corpse+=flag==2;}
	CHECK(burn==1 && corpse==1,"existing 12-float INSTANCE_CUSTOM.w carries both derived fire flags");
	const auto blob=w.save(); World restored(1);
	CHECK(restored.load(blob) && restored.state_hash()==hash && restored.host_last_release_id==9 && restored.host_ranged_delegate,"original atomic native state restores owner and paid watermark");
	CHECK(restored.fire_visual.size()==2 && restored.fire_visual[0]==0 && restored.fire_visual[1]==0,"derived flags rebuild after restore");
	CHECK(restored.action_motion.empty(),"transient movement segments never survive a load boundary");
	auto obsolete=blob; obsolete[3]=0x36; const auto stable=restored.save();
	CHECK(!restored.load(obsolete) && restored.save()==stable,"explicit old KW06 format rejects without partial mutation");
}

int main() {
	ownership_and_release(); original_damage_and_casualty(); shared_fire_safe_rest(); persistence_and_existing_visual_channel();
	std::printf("FIRE_HOST_BRIDGE_%s: checks=%d failures=%d; P6_NOT_CLOSED\n",failures?"FAIL":"PASS",checks,failures);
	return failures?1:0;
}
