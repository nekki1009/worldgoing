#include "../src/crowd_core.hpp"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <limits>
using namespace wg;
static int checks=0,failures=0;
#define CHECK(c,msg) do{++checks;if(!(c)){++failures;std::fprintf(stderr,"FAIL %d: %s\n",__LINE__,msg);}}while(false)
static void near(double a,double b,const char *msg){CHECK(std::isfinite(a)&&std::abs(a-b)<1e-8,msg);}
static constexpr float action=1.f/30.f;
struct Fixture{
    World w{1};
    Fixture(double fatigue=40){
        w.terrain.allocate(30,30);w.cfg.ai=false;w.cfg.auto_capture=false;w.cfg.rescue_seek_cells=0;w.cfg.bleed_per_game_hour=0;
        rules::Equip sword;sword.family=rules::F_LONGSWORD;sword.material=rules::M_IRON;
        const int fi=w.add_formation(0,10.5f,10.5f,0,4,1,T_MELEE,10);
        for(int i=0;i<4;++i)w.add_soldier(fi,sword,i==0?R_CAPTAIN:R_REGULAR,101+i);
        w.finalize();w.formations[0].ai_enabled=false;w.order_hold(0);
        for(int i=0;i<4;++i){w.set_host_control(i,true);w.host_input(i,0,0,false,false);}
        CHECK(w.set_host_ranged_delegate(true),"actual original environmental fire contact host enabled");w.formations[0].fatigue=fatigue;w.formations[0].fatigue_rest=12;
    }
};
static World::WorkFatigueState fatigue_plan(const World &w,double effort){
    const auto &f=w.formations[0];World::WorkFatigueState p;
    p.formation=0;p.before_count=f.fatigue_count;p.before_fatigue=f.fatigue;p.before_rest=f.fatigue_rest;
    p.work_seconds=effort;p.fatigue=std::min(100.0,f.fatigue+effort*(10.0/3600.0)/f.fatigue_count);p.rest=0;
    return p;
}
static World::WorkTrainingState training_plan(const World &w,double effort,double productive){
    World::WorkTrainingState t;t.formation=0;t.before_training=w.formations[0].training;
    t.training=std::min(1000.0,t.before_training+productive/3600/w.formations[0].fatigue_count);
    t.effort_seconds=effort;t.productive_seconds=productive;return t;
}
static void death_preserves_real_start_prefix(){
    Fixture f;auto &w=f.w;CHECK(w.work_training_start_ready(0,0),"actual original commander/food/stopped formation qualifies at start");
    const auto p=fatigue_plan(w,120);const auto t=training_plan(w,60,40);const auto begin=w.tick;
    CHECK(w.step_clock_work_point(action,60,0,begin,{p}),"ordinary worker plus one trainee share original World point");
    CHECK(w.apply_fire_exposure_damage(0,w.hp[0])&&w.hp[0]<=0&&w.formations[0].fatigue_count==3,"actual endpoint kills true original commander");
    const double before=w.formations[0].training;
    CHECK(!w.apply_training_state(0,before,w.formations[0].fatigue,w.formations[0].fatigue_rest,t.training,w.formations[0].fatigue,w.formations[0].fatigue_rest,false),"legacy current-life setter cannot bypass point admission");
    CHECK(w.validate_work_point_training_plan(begin,{t})&&w.formations[0].training==before,"true cached start qualifies positive prefix despite endpoint commander death, readonly");
    CHECK(w.prepare_work_point_training_plan(begin,{t})&&w.formations[0].training==before,"training copies/allocations prepared before material costs");
    CHECK(w.prepare_work_point_finish(begin,{p}),"joint fatigue/training all admitted before first original costs");
    CHECK(!w.prepare_work_point_training_plan(begin,{t}),"ready nofail tail cannot accept late replacement");
    w.publish_work_point_finish();near(w.formations[0].training,t.training,"same original publisher preserves training prefix once");
    near(w.formations[0].fatigue,p.fatigue,"training adds no second fatigue charge, original four-person denominator");
    w.publish_work_point_finish();near(w.formations[0].training,t.training,"publisher replay has no training effect");
    CHECK(!w.validate_work_point_training_plan(begin,{t}),"completed old point cannot replay a training candidate");
}
static void true_fresh_input_and_invalid_candidates(){
    Fixture f;auto &w=f.w;
    w.set_host_control(1,true);w.host_input(1,1,0,true,false);CHECK(!w.work_training_start_ready(0,0),"fresh original WASD disqualifies whole formation before movement/RUN writes");
    w.host_input(1,0,0,false,true);CHECK(!w.work_training_start_ready(0,0),"fresh original engage also disqualifies original training start");
    w.host_input(1,0,0,false,false);CHECK(w.work_training_start_ready(0,0),"original input release restores true start qualification");
    CHECK(!w.work_training_start_ready(0,1)&&!w.work_training_start_ready(-1,0)&&!w.work_training_start_ready(0,std::numeric_limits<double>::infinity()),"combat/identity/nonfinite pure readiness rejects");
    const auto p=fatigue_plan(w,60);const auto good=training_plan(w,60,40);const auto begin=w.tick;
    CHECK(w.step_clock_work_point(action,60,0,begin,{p}),"real positive work interval opens");
    auto bad=good;bad.before_training+=1;CHECK(!w.prepare_work_point_training_plan(begin,{bad}),"stale original training source rejects");
    bad=good;bad.training=1001;CHECK(!w.prepare_work_point_training_plan(begin,{bad}),"original training cap rejects");
    bad=good;bad.effort_seconds=61;CHECK(!w.prepare_work_point_training_plan(begin,{bad}),"training cannot borrow P5/future effort beyond true accepted base");
    bad=good;bad.productive_seconds=61;CHECK(!w.prepare_work_point_training_plan(begin,{bad}),"productive cannot exceed its actual original effort");
    bad=good;bad.effort_seconds=0;CHECK(!w.prepare_work_point_training_plan(begin,{bad}),"no positive allocation grants no training prefix");
    bad=good;bad.training=std::numeric_limits<double>::quiet_NaN();CHECK(!w.prepare_work_point_training_plan(begin,{bad}),"nonfinite training rejects before cost");
    CHECK(!w.prepare_work_point_training_plan(begin+1,{good})&&!w.prepare_work_point_training_plan(begin,{good,good}),"wrong tick and duplicate formation reject");
    near(w.formations[0].training,good.before_training,"all rejections leave original training unchanged");
    CHECK(w.prepare_work_point_training_plan(begin,{good})&&w.prepare_work_point_finish(begin,{p}),"valid original candidate can follow pure failures");
    w.publish_work_point_finish();near(w.formations[0].training,good.training,"valid original training publishes after all gates");
}
static void invalid_start_cannot_be_repaired_at_endpoint(){
    Fixture f;auto &w=f.w;w.formations[0].fully_fed=false;
    const auto p=fatigue_plan(w,60);const auto t=training_plan(w,60,40);const auto begin=w.tick;
    CHECK(!w.work_training_start_ready(0,0)&&w.step_clock_work_point(action,60,0,begin,{p}),"real unfed start caches no training qualification");
    CHECK(w.set_sustain_input(0,true,0),"true original later food state can recover at endpoint");
    CHECK(!w.prepare_work_point_training_plan(begin,{t}),"later feeding cannot retroactively invent trained prefix");
    CHECK(w.prepare_work_point_finish(begin,{p}),"unrelated original work still publishes");w.publish_work_point_finish();near(w.formations[0].training,10,"unqualified start training stays unchanged");
}
static void long_partition_and_rest_cap(){
    Fixture whole(0),split(0);
    const auto p=fatigue_plan(whole.w,120);const auto t=training_plan(whole.w,60,60);const auto begin=whole.w.tick;
    CHECK(whole.w.step_clock_work_point(action,60,0,begin,{p})&&whole.w.prepare_work_point_training_plan(begin,{t})&&whole.w.prepare_work_point_finish(begin,{p}),"actual long interval prepared with exact below30 productive work");whole.w.publish_work_point_finish();
    for(int k=0;k<2;++k){const auto q=fatigue_plan(split.w,60);const auto u=training_plan(split.w,30,30);const auto start=split.w.tick;
        CHECK(split.w.step_clock_work_point(action,30,0,start,{q})&&split.w.prepare_work_point_training_plan(start,{u})&&split.w.prepare_work_point_finish(start,{q}),"actual partition retains original held qualification and next snapshot");split.w.publish_work_point_finish();}
    near(whole.w.formations[0].training,split.w.formations[0].training,"actual World long/partition training is equal with original productive inputs");
    near(whole.w.formations[0].fatigue,split.w.formations[0].fatigue,"training never adds a duplicate shared fatigue charge");
    Fixture rest(79.999);auto &w=rest.w;const double seconds=(80-w.formations[0].fatigue)*4/(2*(10.0/3600.0));
    auto edge=fatigue_plan(w,2*seconds);auto trained=training_plan(w,seconds,seconds*.5);const auto start=w.tick;
    CHECK(w.step_clock_work_point(action,seconds,0,start,{edge})&&w.prepare_work_point_training_plan(start,{trained})&&w.prepare_work_point_finish(start,{edge}),"genuine final positive prefix reaching REST80 remains consumable");w.publish_work_point_finish();near(w.formations[0].fatigue,80,"REST endpoint fatigue exact");near(w.formations[0].training,trained.training,"REST endpoint retains genuine trained prefix");
    Fixture capped;auto &c=capped.w;c.formations[0].training=1000;const auto cp=fatigue_plan(c,60);const auto ct=training_plan(c,60,40);const auto tick=c.tick;
    CHECK(c.step_clock_work_point(action,60,0,tick,{cp})&&c.prepare_work_point_training_plan(tick,{ct})&&c.prepare_work_point_finish(tick,{cp}),"cap stops training growth, not actual accepted effort");c.publish_work_point_finish();near(c.formations[0].training,1000,"original cap kept");near(c.formations[0].fatigue,cp.fatigue,"capped actual training still costs effort once");
}
int main(){death_preserves_real_start_prefix();true_fresh_input_and_invalid_candidates();invalid_start_cannot_be_repaired_at_endpoint();long_partition_and_rest_cap();
    std::printf("NATIVE_TRAINING_PREFIX_%s checks=%d failures=%d; true World start qualification, original point publisher, no GD/wholecaller claim\n",failures?"FAIL":"PASS",checks,failures);return failures?1:0;}
