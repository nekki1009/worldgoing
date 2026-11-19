// Original World actual-contact point with post-contact accepted P5 effort.
// No duplicate World, copied cold people, clock advance or modeled cost owner.
#include "../src/crowd_core.hpp"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <limits>
using namespace wg;
static int checks=0, failures=0;
#define CHECK(c,msg) do { ++checks; if(!(c)){++failures;std::fprintf(stderr,"FAIL %d: %s\n",__LINE__,msg);} } while(false)
static void near(double a,double b,const char *m) { CHECK(std::isfinite(a)&&std::abs(a-b)<1e-8,m); }
static constexpr float action=1.f/30.f;
struct Fixture {
	World w{1};
	Fixture(double fatigue=40) {
		w.terrain.allocate(30,30);w.cfg.ai=false;w.cfg.auto_capture=false;w.cfg.rescue_seek_cells=0;w.cfg.bleed_per_game_hour=0;
		rules::Equip bow;bow.family=rules::F_BOW;bow.material=rules::M_IRON;
		rules::Equip sword;sword.family=rules::F_LONGSWORD;sword.material=rules::M_IRON;
		const int fi=w.add_formation(0,10.5f,10.5f,0,4,1,T_BOW,0);
		w.add_soldier(fi,bow,R_CAPTAIN,101,3);w.add_soldier(fi,sword,R_REGULAR,102,0);
		w.add_soldier(fi,sword,R_REGULAR,103,0);w.add_soldier(fi,sword,R_REGULAR,104,0);
		w.finalize();w.formations[fi].ai_enabled=false;w.order_hold(fi);
		w.px[0]=w.nx[0]=10.5f;w.py[0]=w.ny[0]=10.5f;
		w.formations[fi].fatigue=fatigue;w.formations[fi].fatigue_rest=12;
		CHECK(w.set_host_ranged_delegate(true),"true original fire host selected");
	}
};
static World::WorkFatigueState packet(const World &w,double work,double run) {
	const auto &f=w.formations[0];World::WorkFatigueState p;
	p.formation=0;p.before_count=f.fatigue_count;p.before_fatigue=f.fatigue;p.before_rest=f.fatigue_rest;
	p.work_seconds=work;p.run_seconds=run;p.rest=0;
	p.fatigue=std::min(rules::FATIGUE_LIMIT,f.fatigue+(work*(10.0/3600.0)+run*rules::FATIGUE_RUN_RATE)/f.fatigue_count);
	return p;
}
static void success_and_actual_fraction() {
	Fixture f;auto &w=f.w;w.running[3]=1;
	const auto base=packet(w,120,60),full=packet(w,150,60);const auto tick=w.tick;
	CHECK(w.step_clock_work_point(action,60,0,tick,{base}),"two workers and original RUN advance one real World step");
	const double time=w.time;
	CHECK(w.tick==tick+1&&w.work_point_state()[0]==1,"one actual point belongs to the original completed tick");
	CHECK(w.save().empty(),"unfinished original point cannot be serialized as complete");
	CHECK(!w.step_clock(action,60,0)&&!w.step_clock_work_plan(action,60,0,w.tick,{full})&&w.time==time,"another clock step cannot overtake unfinished point");
	const double before=w.formations[0].fatigue;
	CHECK(w.validate_work_point_finish(tick,{full})&&w.validate_work_point_finish(tick,{full}),"successful fraction effort joins same start pool in readonly final validation");
	near(w.formations[0].fatigue,before,"readonly classification does not publish provisional P5 fatigue");
	CHECK(w.prepare_work_point_finish(tick,{full}),"all allocation and copy work finishes BEFORE original holder/material costs");
	const int ammo=w.ammo[0];rules::RangedShooter receipt;
	CHECK(!w.commit_host_ranged(0,ammo,0,1,16,10,false,receipt)&&w.ammo[0]==ammo,"prepared nofail tail refuses a late native pulse before its cost");
	CHECK(!w.charge_siege_work(1,30),"common accepted work cannot secretly use legacy native charge in tail");
	w.publish_work_point_finish();
	near(w.formations[0].fatigue,full.fatigue,"actual fractional accepted effort and work/RUN publish once");
	near(w.formations[0].fatigue_rest,0,"successful actual effort has no idle recovery");
	CHECK(w.time==time&&w.tick==tick+1&&w.work_point_state()[0]==0,"point publication has zero action/game clock cost");
	w.publish_work_point_finish();near(w.formations[0].fatigue,full.fatigue,"publisher re-entry cannot replay fatigue");
	CHECK(!w.prepare_work_point_finish(tick,{full}),"same old point cannot stage effort twice");
	CHECK(!w.save().empty(),"completed point returns to original save contract");
}
static void failed_suppress_and_real_death_denominator() {
	Fixture f;auto &w=f.w;w.running[3]=1;
	const auto base=packet(w,120,60);const auto tick=w.tick;
	CHECK(w.step_clock_work_point(action,60,0,tick,{base}),"true accepted prefix precedes contact failure");
	CHECK(w.apply_fire_exposure_damage(2,100)&&w.hp[2]<=0&&w.formations[0].fatigue_count==3,"original contacts truly kill the P5 executor");
	// PA final context fails: no fire request. Other two workers and RUN keep
	// their real prefix; continuous denominator is the original FOUR people.
	CHECK(w.prepare_work_point_finish(tick,{base}),"failed suppress contributes zero effort without swallowing other workers");
	w.publish_work_point_finish();near(w.formations[0].fatigue,base.fatigue,"original start count remains authoritative through point death");
	const auto next=packet(w,60,0);
	CHECK(next.before_count==3,"next original interval uses actual remaining living roster");
	CHECK(w.step_clock_work_point(action,60,0,w.tick,{next}),"next real World step retains new original denominator");
	CHECK(w.prepare_work_point_finish(w.tick-1,{next}),"next point admits three-person source");
	w.publish_work_point_finish();near(w.formations[0].fatigue,next.fatigue,"no stale cold four-person count is used next time");
}
static void native_discrete_charges_and_atomic_rejections() {
	Fixture f;auto &w=f.w;w.running[3]=1;
	const auto base=packet(w,120,60),full=packet(w,150,60);const auto tick=w.tick;
	CHECK(w.step_clock_work_point(action,60,0,tick,{base}),"contact point opens on true source");
	rules::RangedShooter shot;
	CHECK(w.commit_host_ranged(0,3,0,1,16,10,false,shot),"actual discrete native cost during original point is recorded");
	const double charged=w.formations[0].fatigue;
	auto bad=full;bad.before_count=3;
	CHECK(!w.prepare_work_point_finish(tick,{bad}),"wrong original denominator rejects before any new cost");
	bad=full;bad.run_seconds=0;CHECK(!w.prepare_work_point_finish(tick,{bad}),"ending hot RUN cannot replace original start RUN");
	bad=full;bad.work_seconds=300;CHECK(!w.prepare_work_point_finish(tick,{bad}),"duplicate activity beyond original people is rejected");
	bad=full;bad.fatigue=std::numeric_limits<double>::infinity();CHECK(!w.prepare_work_point_finish(tick,{bad}),"nonfinite final integral is rejected");
	CHECK(!w.prepare_work_point_finish(tick+1,{full})&&!w.prepare_work_point_finish(tick,{full,full}),"wrong point and duplicate pool reject");
	CHECK(w.work_point_state()[1]==0&&w.formations[0].fatigue==charged,"failed final validation does not approve or change hot fatigue");
	CHECK(w.prepare_work_point_finish(tick,{full}),"valid final candidate can follow pure rejection");
	w.publish_work_point_finish();near(w.formations[0].fatigue,full.fatigue+1.0/4.0,"native true discrete pulse is retained once alongside accepted P5 effort");
	CHECK(w.ammo[0]==2&&w.stats.shots==1,"continuous finalization never duplicates native ammo or shot");
}
static double work_integral(double start,double seconds,double rate) {
	// Independent closed oracle for one smooth piece, using ORIGINAL fatigue
	// efficiency below/above30. This checks actual point partition accounting.
	if(seconds<=0)return 0;
	if(rate==0)return seconds/(1+std::max(0.0,start-30)/50);
	double work=0;
	if(start<30){const double easy=std::min(seconds,(30-start)/rate);work+=easy;seconds-=easy;start+=easy*rate;}
	if(seconds>0)work+=50/rate*std::log((50+start-30+rate*seconds)/(50+start-30));
	return work;
}
static void true_death_queue_prefix_receipts() {
	Fixture f;auto &w=f.w;
	w.siege_crew[2]=1; // Explicit original crew fixture; genuine round-charge API.
	const auto base=packet(w,60,0),full=packet(w,90,0);const auto tick=w.tick;
	CHECK(w.step_clock_work_point(action,60,0,tick,{base}),"real death receipt point opens with one worker and idle fire candidate");
	rules::RangedShooter shot;
	CHECK(w.commit_host_ranged(0,3,0,1,16,10,false,shot),"first true native pulse costs original four-person denominator");
	CHECK(w.apply_fire_exposure_damage(1,100),"actual contact kills original prefix worker after first pulse");
	CHECK(w.charge_siege_round({2},1.0),"true original crew round pulse costs new three-person denominator");
	CHECK(w.apply_fire_exposure_damage(0,100),"actual contact kills original shooter after second pulse");
	size_t first=w.events.size(),second=w.events.size();
	for(size_t i=0;i<w.events.size();++i)if(w.events[i].kind==EV_DEATH){if(w.events[i].person==102)first=i;if(w.events[i].person==101)second=i;}
	CHECK(first<w.events.size()&&second<w.events.size(),"same original event queue retains both actual death identities");
	if(first==w.events.size()||second==w.events.size())return;
	near(w.events[first].fatigue,base.fatigue+1.0/4,"first queued death initially records real base prefix and preceding native pulse");
	const auto before=w.events[first].fatigue;
	CHECK(w.validate_work_point_finish(tick,{full})&&w.events[first].fatigue==before,"readonly finish cannot publish death fatigue early");
	CHECK(w.prepare_work_point_finish(tick,{full}),"all original death receipt values prepared before any actual new material/job cost");
	w.publish_work_point_finish();
	near(w.events[first].fatigue,full.fatigue+1.0/4,"first death receives accepted common prefix but no later native pulse");
	near(w.events[second].fatigue,full.fatigue+1.0/4+1.0/3,"second death receives actual earlier pulses with contemporaneous denominators");
	near(w.formations[0].fatigue,full.fatigue+1.0/4+1.0/3,"living original pool publishes all actual native point pulses once");
	CHECK(w.formations[0].fatigue_count==2&&w.events[first].fatigue_rest==0&&w.events[second].fatigue_rest==0,"original live count and death fatigue REST receipts remain consistent");
	Fixture corrupt;auto &c=corrupt.w;const auto only=packet(c,60,0);const auto ct=c.tick;
	CHECK(c.step_clock_work_point(action,60,0,ct,{only})&&c.apply_fire_exposure_damage(1,100),"true queue guard fixture creates original death");
	c.events.clear();
	CHECK(!c.prepare_work_point_finish(ct,{only}),"premature original queue drain rejects BEFORE new point costs");
}
static bool has_runner(const World &w,int soldier) {
	const auto ids=w.work_point_runners();
	int matches=0;
	for(size_t k=0;k<ids.size();k+=3)if(ids[k+1]==soldier){CHECK(ids[k]==w.form[soldier]&&ids[k+2]==w.person_id[soldier],"true point runner retains actual original formation/unit/person identity");++matches;}
	CHECK(matches<=1,"true old/new RUN union cannot repeat a person");return matches==1;
}
static void true_run_warmup(World &w) {
	w.px[0]=w.nx[0]=3.5f;w.py[0]=w.ny[0]=3.5f;
	w.set_host_control(0,true);w.host_input(0,0,w.cfg.run_speed,true,false);
	// ORIGINAL velocity blend needs two low-speed motion samples before it
	// crosses RUN threshold. No direct velocity/running writes or physics bypass.
	CHECK(w.step_clock(action,60,0)&&w.step_clock(action,60,0)&&!w.running[0]&&w.vy[0]>0,"true original host acceleration precedes first actual RUN flag");
}
static void fresh_wasd_actual_run_and_original_no_work() {
	Fixture f;auto &w=f.w;true_run_warmup(w);
	CHECK(!w.running[0]&&w.work_fatigue_runners(0).empty(),"fresh true host input arrives before original hot RUN is written");
	const auto upper=w.work_fatigue_run_upper();
	CHECK(upper.size()==12,"pure Native upper returns four true original can-act refs, no invented future RUN");
	const auto base=packet(w,60,0),full=packet(w,90,60);const auto tick=w.tick;
	CHECK(w.step_clock_work_point(action,60,0,tick,{base})&&w.running[0],"original World movement truly starts fresh WASD RUN while other NPC works");
	CHECK(has_runner(w,0),"post-motion original point cache exposes the actual new runner");
	CHECK(!w.prepare_work_point_finish(tick,{base}),"old RUN=false final packet cannot erase actual newly moving runner");
	CHECK(w.prepare_work_point_finish(tick,{full}),"true new RUN and accepted finite P5 effort share original NPC work pool");
	w.publish_work_point_finish();near(w.formations[0].fatigue,full.fatigue,"fresh WASD charges once together with other NPC work/P5 using true start count");
	w.host_input(0,0,0,false,false);
	const auto stopped=packet(w,60,60);const auto stop_tick=w.tick;
	CHECK(w.step_clock_work_point(action,60,0,stop_tick,{stopped})&&!w.running[0],"original movement truly stops RUN at this endpoint");
	CHECK(has_runner(w,0)&&w.prepare_work_point_finish(stop_tick,{stopped}),"already-metered original RUN prefix is retained once when motion stops");
	w.publish_work_point_finish();near(w.formations[0].fatigue,stopped.fatigue,"stop endpoint neither duplicates nor retrospectively erases charged RUN");
	CHECK(w.work_fatigue_runners(0).empty(),"next true start snapshot observes stopped original runner");
	Fixture point_only,normal;
	for(World *x:{&point_only.w,&normal.w}){x->px[0]=x->nx[0]=3.5f;x->py[0]=x->ny[0]=3.5f;x->set_host_control(0,true);x->host_input(0,0,x->cfg.run_speed,true,false);}
	for(int part=0;part<4;++part){
		const auto begin=point_only.w.tick;
		CHECK(point_only.w.step_clock_work_point(action,60,0,begin,{})&&normal.w.step_clock(action,60,0),"no-work actual World executes fresh/ongoing RUN with its original rules");
		CHECK(point_only.w.prepare_work_point_finish(begin,{}),"no-work point needs no manually rebuilt RUN allocation");
		point_only.w.publish_work_point_finish();
		CHECK(point_only.w.state_hash()==normal.w.state_hash(),"no WORK pool preserves byte-equivalent original World RUN/recovery behaviour");
	}
	Fixture death;auto &d=death.w;true_run_warmup(d);
	const auto dbase=packet(d,60,0),dfull=packet(d,90,60);const auto dtick=d.tick;
	CHECK(d.step_clock_work_point(action,60,0,dtick,{dbase})&&d.running[0]&&d.apply_fire_exposure_damage(0,100),"true fresh runner moves then dies in original contact point");
	CHECK(has_runner(d,0)&&d.prepare_work_point_finish(dtick,{dfull}),"actual RUN prefix survives endpoint death and accepted WORK/P5 still uses start count");
	d.publish_work_point_finish();
	for(const auto &e:d.events)if(e.kind==EV_DEATH&&e.person==101)near(e.fatigue,dfull.fatigue,"same original death receipt includes true new RUN and final accepted prefix");
	CHECK(d.formations[0].fatigue_count==3&&d.work_fatigue_runners(0).empty(),"next actual roster excludes dead runner with no stale cached effort");
}
static double point(Fixture &f,double seconds,double fire_seconds,float dt=action) {
	auto &w=f.w;w.running[3]=1;const auto tick=w.tick;
	const auto base=packet(w,2*seconds,seconds),full=packet(w,2*seconds+fire_seconds,seconds);
	const double rate0=(3*(10.0/3600.0)+rules::FATIGUE_RUN_RATE)/4;
	const double rate1=(2*(10.0/3600.0)+rules::FATIGUE_RUN_RATE)/4;
	const double work=work_integral(full.before_fatigue,fire_seconds,rate0)+
		work_integral(full.before_fatigue+rate0*fire_seconds,seconds-fire_seconds,rate1);
	CHECK(w.step_clock_work_point(dt,seconds,0,tick,{base})&&w.prepare_work_point_finish(tick,{full}),"partition executes actual original World+accepted point");
	w.publish_work_point_finish();return work;
}
static void long_and_partition_cross30_and_rest80() {
	Fixture longframe(29.8),partition(29.8);
	const double long_work=point(longframe,60,30);
	const double partition_work=point(partition,30,30,action/2)+point(partition,30,0,action/2);
	near(longframe.w.time,partition.w.time,"actual long and partition action clocks have the same endpoint");
	near(longframe.w.formations[0].fatigue,partition.w.formations[0].fatigue,"full point and actual partition have identical continuous work/RUN fatigue");
	near(long_work,partition_work,"same-pool third fire-worker ending inside interval preserves exact productive work");
	Fixture rest(79.9);const double rate=(3*(10.0/3600.0)+rules::FATIGUE_RUN_RATE)/4;
	point(rest,(80-79.9)/rate,(80-79.9)/rate);
	near(rest.w.formations[0].fatigue,80,"preclipped maximum-fire original point reaches true REST80 endpoint");
	Fixture capped(99.9);point(capped,60,30);near(capped.w.formations[0].fatigue,100,"original fatigue cap remains finite at mixed point");
}
int main(){success_and_actual_fraction();failed_suppress_and_real_death_denominator();native_discrete_charges_and_atomic_rejections();long_and_partition_cross30_and_rest80();true_death_queue_prefix_receipts();fresh_wasd_actual_run_and_original_no_work();
	std::printf("NATIVE_P5_POINT_%s checks=%d failures=%d; World owner+point only, PA/Runtime/Lab merge still required\n",failures?"FAIL":"PASS",checks,failures);return failures?1:0;}
