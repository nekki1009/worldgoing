#include "../src/crowd_core.hpp"
#include <algorithm>
#include <cstdio>
#include <limits>

using namespace wg;
static int checks=0, failures=0;
static const char *test_case="setup";
#define REQUIRE(c) do { ++checks; if (!(c)) { ++failures; std::fprintf(stderr,"FAIL %s line %d: %s\n",test_case,__LINE__,#c); } } while(false)
static int cell(int x,int y) { return y*40+x; }
static void close(double a,double b) { REQUIRE(std::abs(a-b)<1e-6); }
static void place(World &w,int i,int x,int y) { auto s=w.get_soldier_state(i); s.x=x+.5f;s.y=y+.5f;w.set_soldier_state(i,s); }
static void setup(World &w,int level=0) {
	w.terrain.allocate(40,40);
	std::fill(w.terrain.height.begin(),w.terrain.height.end(),(uint8_t)level);
	w.terrain.base_height=w.terrain.height;
	w.cfg.ai=false;w.cfg.auto_capture=false;w.cfg.rescue_seek_cells=0;w.cfg.bleed_per_game_hour=0;
	int f=w.add_formation(0,10.5f,10.5f,0,2,1,T_MELEE,0);
	int other=w.add_formation(0,30.5f,30.5f,0,1,1,T_MELEE,0);
	rules::Equip e;e.family=rules::F_LONGSWORD;e.material=rules::M_IRON;
	w.add_soldier(f,e,R_CAPTAIN,1001);w.add_soldier(f,e,R_REGULAR,1002);w.add_soldier(other,e,R_CAPTAIN,2001);
	w.finalize();for(auto &formation:w.formations)formation.ai_enabled=false;
	place(w,0,9,10);place(w,1,12,10);place(w,2,30,30);
	REQUIRE(w.set_siege_crew(0,true));REQUIRE(w.set_siege_crew(1,true));w.events.clear();
}
static std::vector<World::SiegeMember> members() { return {{0,1001,cell(9,10),cell(9,11)},{1,1002,cell(12,10),cell(12,11)}}; }
static std::vector<int> body() { return {cell(10,10),cell(11,10),cell(10,11),cell(11,11)}; }
static std::vector<int> target() { return {cell(10,11),cell(11,11),cell(10,12),cell(11,12)}; }
static std::vector<int> sweep() { auto out=body();out.push_back(cell(10,12));out.push_back(cell(11,12));return out; }
static int64_t begin(World &w,double duration=1) { return w.begin_siege_compound(members(),body(),target(),sweep(),duration); }
static void step(World &w,float dt=.25f) { REQUIRE(w.step_clock(dt,0,0)); }

static void admission_atomicity() {
	test_case="atomic preflight rejects stale person, missing sweep, collision, bad duration";
	World w(1);setup(w);const auto before=w.state_hash();
	auto bad=members();bad[1].person=9999;REQUIRE(!w.begin_siege_compound(bad,body(),target(),sweep(),1));REQUIRE(w.state_hash()==before);
	auto missing=sweep();missing.pop_back();REQUIRE(!w.begin_siege_compound(members(),body(),target(),missing,1));REQUIRE(w.state_hash()==before);
	REQUIRE(!begin(w,std::numeric_limits<double>::quiet_NaN()));REQUIRE(w.state_hash()==before);
	bad=members();bad[1].to=bad[0].to;REQUIRE(!w.begin_siege_compound(bad,body(),target(),sweep(),1));REQUIRE(w.state_hash()==before);
	place(w,2,10,12);auto dead=w.get_soldier_state(2);dead.hp=0;w.set_soldier_state(2,dead);const auto blocked=w.state_hash();
	REQUIRE(!begin(w));REQUIRE(w.state_hash()==blocked);
	place(w,2,30,30);REQUIRE(begin(w)>0);const auto committed=w.state_hash();REQUIRE(!begin(w));REQUIRE(w.state_hash()==committed);
}

static void phase_barrier_and_save() {
	test_case="one native clock, same progress, pending claims, complete acknowledgement";
	World w(1);setup(w);const auto ids=w.person_id;const auto token=begin(w,2);REQUIRE(token>0);REQUIRE(w.save().empty());
	REQUIRE(!w.settle_siege_compound(token));REQUIRE(!w.set_siege_crew(0,false));
	step(w);close(w.py[0],10.625);close(w.py[1],10.625);close(w.siege_compound_state(token)->elapsed,.25);
	REQUIRE(w.siege_claims_cell(cell(10,12)));auto occupancy=w.occupancy_mask({});REQUIRE(occupancy[cell(10,12)]==1);
	// A legacy state setter cannot overwrite a committed original position.
	auto stale=w.get_soldier_state(0);stale.x=20.5f;stale.y=20.5f;w.set_soldier_state(0,stale);close(w.px[0],9.5);close(w.py[0],10.625);
	for(int i=0;i<7;++i)step(w);
	REQUIRE(w.siege_compound_state(token)->complete);close(w.py[0],11.5);close(w.py[1],11.5);REQUIRE(w.save().empty());
	REQUIRE(w.siege_claims_cell(cell(10,10)));REQUIRE(w.settle_siege_compound(token));REQUIRE(!w.siege_compound_state(token));REQUIRE(!w.siege_claims_cell(cell(10,10)));REQUIRE(w.person_id==ids);
	REQUIRE(w.set_siege_crew(0,false));REQUIRE(w.set_siege_crew(1,false));
	auto blob=w.save();REQUIRE(!blob.empty());World loaded(1);REQUIRE(loaded.load(blob));REQUIRE(loaded.person_id==ids);close(loaded.py[0],11.5);REQUIRE(loaded.state_hash()==w.state_hash());
}

static void hit_death_cancel_finish() {
	test_case="KO, death and explicit cancellation finish the entire committed step";
	for(int mode=0;mode<3;++mode) {
		World w(1);setup(w);const auto token=begin(w);REQUIRE(token>0);step(w);
		if(mode==0)w.apply_contact(0,1,100);else if(mode==1)w.apply_contact(0,200,0);else REQUIRE(w.cancel_siege_compound(token));
		for(int i=0;i<3;++i)step(w);
		const auto *g=w.siege_compound_state(token);REQUIRE(g && g->complete && g->cancelled && !g->aborted);close(w.py[0],11.5);close(w.py[1],11.5);
		REQUIRE(w.person_id[0]==1001);if(mode==0)REQUIRE(w.ko[0]>0);if(mode==1)close(w.hp[0],0);
		REQUIRE(w.settle_siege_compound(token));REQUIRE(w.escort_goal[0]==-1 && w.escort_goal[1]==-1);
	}
}

static void terrain_abort_one_fall() {
	test_case="source support loss cancels group before single original fall";
	World w(1);setup(w,1);const auto token=begin(w);REQUIRE(token>0);step(w,.75f);close(w.py[0],11.25);
	Terrain next=w.terrain;next.height[cell(9,10)]=0;next.base_height[cell(9,10)]=0;
	REQUIRE(w.update_terrain(next));const auto *g=w.siege_compound_state(token);REQUIRE(g && g->aborted && g->complete && g->cancelled);
	close(w.py[0],10.5);close(w.py[1],10.5);close(w.hp[0],85);close(w.hp[1],100);REQUIRE(w.ko[0]>0);REQUIRE(w.contact_revision[0]==1);
	REQUIRE(w.update_terrain(next));close(w.hp[0],85);REQUIRE(w.contact_revision[0]==1);REQUIRE(w.settle_siege_compound(token));
	// Invalid new terrain must fail before cancelling any group or changing health.
	World unchanged(1);setup(unchanged);const auto keep=begin(unchanged);step(unchanged);Terrain invalid=unchanged.terrain;invalid.height[cell(30,30)]=1;
	const auto hash=unchanged.state_hash();REQUIRE(!unchanged.update_terrain(invalid));REQUIRE(unchanged.state_hash()==hash);REQUIRE(!unchanged.siege_compound_state(keep)->complete);
}

static void crew_exclusion_and_thread_determinism() {
	test_case="same original native personal-action owner and thread determinism";
	World one(1),four(4);setup(one);setup(four);REQUIRE(!one.exchange_ready(0));REQUIRE(!one.initiates(0,true));
	REQUIRE(!one.order_housing_step(0,cell(9,11)));REQUIRE(begin(one)>0);REQUIRE(begin(four)>0);
	for(int i=0;i<4;++i) { step(one);step(four);REQUIRE(one.state_hash()==four.state_hash()); }
	REQUIRE(one.person_id.size()==3 && four.person_id.size()==3);
}

static void approach_source_and_wreck_navigation() {
	test_case="single native approach retains original source before support loss";
	World approach(1);setup(approach,1);REQUIRE(approach.order_siege_step(0,cell(9,11)));REQUIRE(!approach.set_siege_crew(0,false));step(approach,.2f);
	REQUIRE(approach.siege_step_source[0]==cell(9,10));REQUIRE(approach.py[0]>11);
	Terrain lowered=approach.terrain;lowered.height[cell(9,10)]=0;lowered.base_height[cell(9,10)]=0;
	REQUIRE(approach.update_terrain(lowered));close(approach.py[0],10.5);close(approach.hp[0],85);REQUIRE(approach.escort_goal[0]<0);
	test_case="native body purpose blocks outsiders but allows multi-cell original wreck exit";
	World w(1);setup(w);REQUIRE(w.set_siege_crew(0,false));REQUIRE(w.set_siege_crew(1,false));place(w,0,11,12);place(w,1,28,28);
	std::vector<int> blocked;std::vector<int64_t> exits;
	for(int y=10;y<=14;++y)for(int x=10;x<=12;++x){blocked.push_back(cell(x,y));exits.insert(exits.end(),{0,1001,cell(x,y)});}
	REQUIRE(w.set_siege_navigation(blocked,exits));REQUIRE(w.siege_person_cell(0,cell(11,12),cell(11,13)));REQUIRE(!w.siege_person_cell(2,cell(11,9),cell(11,10)));
	const auto before=w.state_hash();auto wrong=exits;wrong[1]=9999;REQUIRE(!w.set_siege_navigation(blocked,wrong));REQUIRE(w.state_hash()==before);
	w.set_host_control(0,true);w.host_input(0,0,2.63f,false,false);
	for(int i=0;i<20;++i)step(w,.1f);
	REQUIRE(w.py[0]>15.3f);const float outside=w.py[0];w.host_input(0,0,-2.63f,false,false);
	for(int i=0;i<20;++i)step(w,.1f);
	REQUIRE(w.py[0]<outside && w.py[0]>=15.3f-1e-6f);
	REQUIRE(w.set_siege_navigation(blocked,{}));REQUIRE(!w.siege_person_cell(0,cell(11,15),cell(11,14)));
	World outsider(1);setup(outsider);REQUIRE(outsider.set_siege_crew(0,false));place(outsider,0,11,9);REQUIRE(outsider.set_siege_navigation(blocked,{}));outsider.set_host_control(0,true);outsider.host_input(0,0,2.63f,false,false);
	for(int i=0;i<10;++i)step(outsider,.1f);REQUIRE(outsider.py[0]<10.f);
}

static void original_orders_are_preserved() {
	test_case="siege commitments preserve the existing non-retreat team order";
	for(auto order:{Order::MOVE,Order::ATTACK,Order::PURSUE,Order::RETURN}) {
		World w(1);setup(w);auto &f=w.formations[0];f.order=order;f.arrived=false;f.goal_x=f.goal_y=30.5f;f.origin_x=f.origin_y=20.5f;f.pursuit_left=30;f.target_person=2;
		const auto token=begin(w);REQUIRE(token>0);for(int k=0;k<4;++k)step(w);
		REQUIRE(w.formations[0].order==order);REQUIRE(w.siege_compound_state(token)->complete);REQUIRE(w.settle_siege_compound(token));
	}
	World walk(1);setup(walk);walk.formations[0].order=Order::MOVE;REQUIRE(walk.order_siege_step(0,cell(9,11)));REQUIRE(walk.formations[0].order==Order::MOVE);
	World housing(1);setup(housing);REQUIRE(housing.set_siege_crew(0,false));housing.formations[0].order=Order::MOVE;REQUIRE(!housing.order_housing_step(0,cell(9,11)));
	World retreat(1);setup(retreat);retreat.formations[0].order=Order::RETREAT;REQUIRE(!begin(retreat));REQUIRE(!retreat.order_siege_step(0,cell(9,11)));
}


// Original RAM-sized 3-by-2 footprint, with both true crew behind its tail.
// Initial fixture positions are set before admission; all movement uses World.
struct TailCase {
    std::vector<World::SiegeMember> members;
    std::vector<int> source, target, swept;
    int dx = 0, dy = 0;
};
static void full_sweep(TailCase &c) {
    int minx=40,miny=40,maxx=-1,maxy=-1;
    for(const auto *body:{&c.source,&c.target})for(int p:*body) {
        minx=std::min(minx,p%40);miny=std::min(miny,p/40);maxx=std::max(maxx,p%40);maxy=std::max(maxy,p/40);
    }
    c.swept.clear();
    for(int y=miny;y<=maxy;++y)for(int x=minx;x<=maxx;++x)c.swept.push_back(cell(x,y));
    c.swept.push_back(cell(6,6)); // A retained historical claim, outside both body endpoints.
}
static TailCase tail_case(World &w,int facing,int sign=1) {
    setup(w);
    TailCase c;c.dx=DX[facing]*sign;c.dy=DY[facing]*sign;
    const int sx=-DY[facing],sy=DX[facing];
    for(int depth=0;depth<3;++depth)for(int width=0;width<2;++width) {
        const int x=10+DX[facing]*depth+sx*width,y=10+DY[facing]*depth+sy*width;
        c.source.push_back(cell(x,y));c.target.push_back(cell(x+c.dx,y+c.dy));
    }
    for(int i=0;i<2;++i) {
        const int x=10-DX[facing]+sx*i,y=10-DY[facing]+sy*i;
        place(w,i,x,y);c.members.push_back({i,1001+i,cell(x,y),cell(x+c.dx,y+c.dy)});
    }
    full_sweep(c);return c;
}
static int64_t begin_tail(World &w,const TailCase &c,double duration=1) {
    return w.begin_siege_compound(c.members,c.source,c.target,c.swept,duration);
}
static void reject_tail(World &w,const TailCase &c,double duration=1) {
    const auto hash=w.state_hash();const auto serial=w.siege_serial;const auto saved=w.save();
    const auto ids=w.person_id;const auto x=w.px,y=w.py;const auto modes=w.escort_mode;
    const auto goals=w.escort_goal,groups=w.siege_member_group;const auto count=w.siege_compounds.size();
    REQUIRE(begin_tail(w,c,duration)==0);REQUIRE(w.state_hash()==hash);REQUIRE(w.siege_serial==serial);
    REQUIRE(w.save()==saved && w.siege_compounds.size()==count && w.person_id==ids);
    REQUIRE(w.px==x && w.py==y && w.escort_mode==modes && w.escort_goal==goals && w.siege_member_group==groups);
}
static void check_tail_progress(World &w,const TailCase &c,int64_t token,double p) {
    const auto *g=w.siege_compound_state(token);REQUIRE(g!=nullptr);if(!g)return;
    close(g->elapsed/g->duration,p);REQUIRE(g->complete==(p==1));REQUIRE(!g->cancelled && !g->aborted);
    REQUIRE(w.save().empty());
    for(int claimed:c.swept)REQUIRE(w.siege_claims_cell(claimed));
    const auto occupancy=w.occupancy_mask({});for(int claimed:c.swept)REQUIRE(occupancy[claimed]==1);
    for(size_t k=0;k<c.members.size();++k) {
        const auto &m=c.members[k];const int i=m.soldier;
        REQUIRE(g->members[k].from==m.from && g->members[k].to==m.to && g->members[k].person==m.person);
        close(w.px[i],m.from%40+.5+c.dx*p);close(w.py[i],m.from/40+.5+c.dy*p);
        REQUIRE(w.person_id[i]==m.person && w.hp[i]==100 && w.ko[i]==0);
        REQUIRE(w.siege_claims_cell(m.from) && w.siege_claims_cell(m.to));
        // Compare the real continuously moved person with every body cell at
        // the SAME progress, not with the body's union of past/future cells.
        for(int b:c.source)REQUIRE(std::abs(w.px[i]-(b%40+.5+c.dx*p))>=1-1e-6 || std::abs(w.py[i]-(b/40+.5+c.dy*p))>=1-1e-6);
    }
}
static void true_tail_four_directions() {
    test_case="four directions forward vacated tail and reverse future body; full claims and real continuous barrier";
    for(int direction=0;direction<4;++direction)for(int sign:{1,-1}) {
        World one(1),four(4);auto c=tail_case(one,direction,sign);auto d=tail_case(four,direction,sign);
        // Body arrays are sets; their iteration order must not become a new contract.
        std::reverse(c.target.begin(),c.target.end());std::rotate(d.source.begin(),d.source.begin()+2,d.source.end());
        for(const auto &m:c.members) {
            REQUIRE(std::find(c.source.begin(),c.source.end(),m.from)==c.source.end());
            REQUIRE(std::find(c.target.begin(),c.target.end(),m.to)==c.target.end());
            REQUIRE(sign==1 ? std::find(c.source.begin(),c.source.end(),m.to)!=c.source.end() : std::find(c.target.begin(),c.target.end(),m.from)!=c.target.end());
        }
        const auto a=begin_tail(one,c),b=begin_tail(four,d);REQUIRE(a>0 && b>0);if(a<=0 || b<=0)continue;
        REQUIRE(!one.settle_siege_compound(a) && !four.settle_siege_compound(b));
        for(int tick=1;tick<=4;++tick) {
            step(one);step(four);check_tail_progress(one,c,a,tick*.25);check_tail_progress(four,d,b,tick*.25);
            REQUIRE(one.state_hash()==four.state_hash());std::string error;REQUIRE(one.validate(&error,true));REQUIRE(four.validate(&error,true));
        }
        REQUIRE(one.settle_siege_compound(a) && four.settle_siege_compound(b));
        REQUIRE(one.state_hash()==four.state_hash());
        for(int claimed:c.swept)REQUIRE(!one.siege_claims_cell(claimed));
        REQUIRE(one.set_siege_crew(0,false) && one.set_siege_crew(1,false));
        const auto saved=one.save();REQUIRE(!saved.empty());World loaded(1);REQUIRE(loaded.load(saved));REQUIRE(loaded.state_hash()==one.state_hash());
    }
}
static void tail_rejections() {
    for(int direction=0;direction<4;++direction) {
        { test_case="moving body requires every original crew to share its exact delta, including a stationary mismatch";
          World w(1);auto c=tail_case(w,direction);c.members[0].to=c.members[0].from;reject_tail(w,c); }
        { test_case="opposite crew delta cannot borrow a vacated-tail exception";
          World w(1);auto c=tail_case(w,direction);c.members[0].to=c.members[0].from-c.dx-c.dy*40;reject_tail(w,c); }
        { test_case="a crew initially in the body remains a real same-progress overlap";
          World w(1);auto c=tail_case(w,direction);const int p=c.source[0];place(w,0,p%40,p/40);c.members[0].from=p;c.members[0].to=p+c.dx+c.dy*40;reject_tail(w,c); }
        { test_case="body terrain blocking still rejects the entire translated group";
          World w(1);auto c=tail_case(w,direction);w.terrain.static_blocked[c.source[0]]=1;w.terrain.build_edges();reject_tail(w,c); }
        { test_case="historical-only source sweep cannot be removed for moving crew";
          World w(1);auto c=tail_case(w,direction);c.swept.push_back(c.members[0].from);reject_tail(w,c); }
        { test_case="same-count changed body shape cannot pass as an exact rigid translation";
          World w(1);auto c=tail_case(w,direction);c.target.back()+=-DY[direction]+DX[direction]*40;full_sweep(c);reject_tail(w,c); }
    }
    { test_case="historical-only destination remains blocked outside both body endpoints";
      World w(1);auto c=tail_case(w,E);place(w,0,7,10);c.members[0].from=cell(7,10);c.members[0].to=cell(8,10);c.swept.push_back(cell(8,10));reject_tail(w,c); }
    { test_case="noncardinal body movement is rejected even when every crew matches it";
      World w(1);auto c=tail_case(w,E);for(int &p:c.target)p+=40;for(auto &m:c.members)m.to+=40;full_sweep(c);reject_tail(w,c); }
    { test_case="two-cell rigid translation is not an original adjacent edge";
      World w(1);auto c=tail_case(w,E);for(int &p:c.target)++p;for(auto &m:c.members)++m.to;full_sweep(c);reject_tail(w,c); }
    { test_case="moving crew cannot borrow a stationary unchanged body";
      World w(1);auto c=tail_case(w,E);c.target=c.source;full_sweep(c);reject_tail(w,c); }
    { test_case="body height mismatch is rejected before commitment";
      World w(1);auto c=tail_case(w,E);w.terrain.height[c.target.back()]=w.terrain.base_height[c.target.back()]=1;w.terrain.build_edges();reject_tail(w,c); }
    { test_case="crew edge still needs the original reciprocal terrain legality";
      World w(1);auto c=tail_case(w,E);const int p=c.members[0].from;w.terrain.height[p]=w.terrain.base_height[p]=1;w.terrain.build_edges();reject_tail(w,c); }
    for(int condition=0;condition<3;++condition) {
        test_case="living, knocked-out and dead outsiders retain the complete body claims";
        World w(1);auto c=tail_case(w,E);place(w,2,10,10);
        if(condition==1) { w.apply_contact(2,1,100);REQUIRE(w.ko[2]>0); }
        if(condition==2) { w.apply_contact(2,200,0);REQUIRE(w.hp[2]==0); }
        reject_tail(w,c);
    }
    { test_case="another original committed goal inside the future body blocks admission";
      World w(1);auto c=tail_case(w,E);place(w,2,14,10);REQUIRE(w.order_housing_step(2,cell(13,10)));reject_tail(w,c); }
    for(int input=0;input<12;++input) {
        test_case="malformed original compound parameters remain atomic";
        World w(1);auto c=tail_case(w,E);double seconds=1;
        if(input==0)c.members.clear();if(input==1)c.source.clear();if(input==2)c.target.pop_back();
        if(input==3)c.swept.clear();if(input==4)c.swept.push_back(c.swept[0]);
        if(input==5)c.source.back()=c.source[0];if(input==6)c.target.back()=c.target[0];
        if(input==7)c.members[0].from=-1;if(input==8)c.members[0].to=1600;
        if(input==9)seconds=0;if(input==10)seconds=3601;if(input==11)seconds=std::numeric_limits<double>::infinity();
        reject_tail(w,c,seconds);
    }
}
static void stationary_rotation_keeps_full_sweep() {
    test_case="stationary rotation retains the original conservative sweep for square and nonsquare bodies";
    for(int square=0;square<2;++square) {
        World w(1);auto c=tail_case(w,E);place(w,0,7,7);place(w,1,8,7);
        c.members={{0,1001,cell(7,7),cell(7,7)},{1,1002,cell(8,7),cell(8,7)}};c.source.clear();c.target.clear();
        for(int depth=0;depth<(square?2:3);++depth)for(int width=0;width<2;++width) {
            c.source.push_back(cell(10+depth,10+width));c.target.push_back(cell(10-width,10+depth));
        }
        full_sweep(c);const auto token=begin_tail(w,c);REQUIRE(token>0);if(token<=0)continue;
        for(int tick=0;tick<4;++tick)step(w);close(w.px[0],7.5);close(w.py[0],7.5);close(w.px[1],8.5);close(w.py[1],7.5);
        REQUIRE(w.siege_compound_state(token)->complete);REQUIRE(w.siege_claims_cell(cell(6,6)));REQUIRE(w.settle_siege_compound(token));
    }
    { test_case="stationary rotation never borrows the translated-tail exception";
      World w(1);auto c=tail_case(w,E);for(auto &m:c.members)m.to=m.from;
      place(w,0,10,10);c.members[0].from=c.members[0].to=cell(10,10);reject_tail(w,c); }
    { test_case="rotation rejects a stationary crew in historical-only sweep";
      World w(1);auto c=tail_case(w,E);for(auto &m:c.members)m.to=m.from;
      c.swept.push_back(c.members[0].from);reject_tail(w,c); }
}
static void tail_interruptions_finish_original_barrier() {
    test_case="true translated tail keeps original KO, death and stop completion before acknowledgement";
    for(int reason=0;reason<3;++reason) {
        World w(1);auto c=tail_case(w,E);const auto token=begin_tail(w,c);REQUIRE(token>0);if(token<=0)continue;
        step(w);if(reason==0)w.apply_contact(0,1,100);else if(reason==1)w.apply_contact(0,200,0);else REQUIRE(w.cancel_siege_compound(token));
        REQUIRE(!w.settle_siege_compound(token));REQUIRE(w.save().empty());
        for(int tick=0;tick<3;++tick)step(w);
        const auto *g=w.siege_compound_state(token);REQUIRE(g && g->complete && g->cancelled && !g->aborted);if(!g)continue;
        for(const auto &m:c.members) { close(w.px[m.soldier],m.to%40+.5);close(w.py[m.soldier],m.to/40+.5);REQUIRE(w.person_id[m.soldier]==m.person); }
        for(int claimed:c.swept)REQUIRE(w.siege_claims_cell(claimed));
        REQUIRE(reason!=0 || w.ko[0]>0);REQUIRE(reason!=1 || w.hp[0]==0);REQUIRE(w.settle_siege_compound(token));
        REQUIRE(w.escort_goal[0]==-1 && w.escort_goal[1]==-1 && w.siege_group(0)<0 && w.siege_group(1)<0);
    }
}


static void original_contact_revision_import() {
    test_case="original int64 contact revision imports without a new contact or clock";
    World w(1);setup(w);
    REQUIRE(w.set_siege_crew(0,false));REQUIRE(w.set_siege_crew(1,false));
    step(w,.125f); // Nonzero original clock makes unintended advancement observable.
    const auto baseline=w.save();REQUIRE(!baseline.empty());if(baseline.empty())return;
    const auto ids=w.person_id;
    const auto tick=w.tick;const auto round=w.exchange_round;const auto shots=w.shot_serial;
    const double time=w.time,game_dt=w.game_dt,combat_left=w.combat_left,combat_mark=w.combat_mark;
    const bool external_clock=w.external_clock;
    std::vector<uint64_t> rng;for(const auto &f:w.formations)rng.push_back(f.rng);
    auto same_clock_rng=[&]() {
        REQUIRE(w.tick==tick && w.exchange_round==round && w.shot_serial==shots);
        REQUIRE(w.time==time && w.game_dt==game_dt && w.combat_left==combat_left && w.combat_mark==combat_mark && w.external_clock==external_clock);
        REQUIRE(w.formations.size()==rng.size());
        for(size_t i=0;i<rng.size() && i<w.formations.size();++i)REQUIRE(w.formations[i].rng==rng[i]);
    };
    // The expected World differs only in the already serialized original vector.
    // This is an import of a prior GD revision, not a simulated hit.
    constexpr int64_t prior=(int64_t(1)<<40)+37;
    World expected(1);const bool reference_loaded=expected.load(baseline);
    REQUIRE(reference_loaded);if(!reference_loaded)return;
    expected.contact_revision[0]=prior;
    REQUIRE(w.set_contact_revision(0,prior));
    REQUIRE(w.contact_revision[0]==prior && w.person_id==ids);
    REQUIRE(w.contact_revision[1]==0 && w.contact_revision[2]==0);
    REQUIRE(w.state_hash()==expected.state_hash() && w.save()==expected.save());same_clock_rng();
    const auto imported=w.save();const auto imported_hash=w.state_hash();
    auto unchanged=[&]() {
        REQUIRE(w.state_hash()==imported_hash && w.save()==imported);
        REQUIRE(w.contact_revision[0]==prior && w.person_id==ids);same_clock_rng();
    };
    REQUIRE(w.set_contact_revision(0,prior));unchanged();
    REQUIRE(!w.set_contact_revision(-1,7));unchanged();
    REQUIRE(!w.set_contact_revision(w.soldier_count(),7));unchanged();
    REQUIRE(!w.set_contact_revision(std::numeric_limits<int>::max(),7));unchanged();
    REQUIRE(!w.set_contact_revision(0,-1));unchanged();
    REQUIRE(!w.set_contact_revision(0,std::numeric_limits<int64_t>::min()));unchanged();
    // The existing save contract accepts the whole nonnegative int64 range.
    REQUIRE(w.set_contact_revision(1,std::numeric_limits<int64_t>::max()));
    REQUIRE(w.contact_revision[1]==std::numeric_limits<int64_t>::max());same_clock_rng();
    REQUIRE(w.set_contact_revision(1,0));unchanged();
    World empty(1);const auto empty_hash=empty.state_hash();
    REQUIRE(!empty.set_contact_revision(0,0));REQUIRE(empty.state_hash()==empty_hash);

    test_case="a real original incoming siege hit increments the imported revision once and survives save/load";
    const double hp=w.hp[0],stun=w.stun[0];
    REQUIRE(w.apply_siege_contact(0,3.0,2.0,.35));
    REQUIRE(w.contact_revision[0]==prior+1);close(w.hp[0],hp-3.0);close(w.stun[0],stun+2.0);
    REQUIRE(w.stagger[0]>=.35 && w.person_id==ids);
    REQUIRE(w.contact_revision[1]==0 && w.contact_revision[2]==0);
    const auto saved=w.save();REQUIRE(!saved.empty());if(saved.empty())return;
    World loaded(1);const bool roundtrip_loaded=loaded.load(saved);
    REQUIRE(roundtrip_loaded);if(!roundtrip_loaded)return;
    REQUIRE(loaded.contact_revision==w.contact_revision && loaded.person_id==ids);
    REQUIRE(loaded.state_hash()==w.state_hash() && loaded.save()==saved);
    REQUIRE(loaded.apply_siege_contact(0,1.0,0.0,.35));
    REQUIRE(loaded.contact_revision[0]==prior+2);close(loaded.hp[0],hp-4.0);
}

// SIEGE-YIELD fixture: a stationary 2x2 turn sweep (x 9..11, y 10..11 plus a historical cell) with crew at (7,7),(8,7).
// Soldier 2 (team 0, not crew) stands at (11,11) inside the sweep unless a test moves it.
static void yield_turn(World &w, int64_t &token, double duration = 2) {
	auto c = tail_case(w, E);
	place(w, 0, 7, 7); place(w, 1, 8, 7);
	c.members = {{0, 1001, cell(7, 7), cell(7, 7)}, {1, 1002, cell(8, 7), cell(8, 7)}};
	c.source.clear(); c.target.clear();
	for (int depth = 0; depth < 2; ++depth) for (int width = 0; width < 2; ++width) {
		c.source.push_back(cell(10 + depth, 10 + width));
		c.target.push_back(cell(10 - width, 10 + depth));
	}
	full_sweep(c);
	place(w, 2, 11, 11);
	token = w.begin_siege_compound(c.members, c.source, c.target, c.swept, duration);
}
static bool outside_sweep(const World &w, int i) {
	const int c = w.terrain.idx((int)std::floor(w.px[i]), (int)std::floor(w.py[i]));
	return !w.siege_claims_cell(c, -1);
}

static void own_team_yields_and_turn_completes() {
	test_case = "SIEGE-YIELD: an own-team non-crew soldier in a turn sweep is admitted, steps out, the turn completes and the crew stays";
	World one(1), four(4);
	int64_t a = 0, b = 0;
	yield_turn(one, a); yield_turn(four, b);
	REQUIRE(a > 0 && b > 0);
	if (a <= 0 || b <= 0) return;
	REQUIRE(one.siege_claims_cell(cell(11, 11)) && one.siege_claims_cell(cell(9, 10)));
	REQUIRE(one.save().empty()); // a pending compound refuses save, as before: no mid-yield save exists
	for (int tick = 1; tick <= 12; ++tick) {
		step(one); step(four);
		REQUIRE(one.state_hash() == four.state_hash());
		std::string error;
		REQUIRE(one.validate(&error, true) && four.validate(&error, true));
		close(one.px[0], 7.5); close(one.py[0], 7.5); close(one.px[1], 8.5); close(one.py[1], 7.5);
	}
	// After 3 s the own-team soldier has walked out of every claimed cell and is still standing (not KO, no damage).
	REQUIRE(outside_sweep(one, 2) && outside_sweep(four, 2));
	REQUIRE(one.person_id[2] == 2001 && one.hp[2] == 100 && one.ko[2] == 0);
	REQUIRE(one.px[2] == four.px[2] && one.py[2] == four.py[2]);
	const auto *g = one.siege_compound_state(a);
	REQUIRE(g && g->complete && !g->cancelled && !g->aborted);
	REQUIRE(one.settle_siege_compound(a) && four.settle_siege_compound(b));
	REQUIRE(!one.siege_claims_cell(cell(10, 10)) && !four.siege_claims_cell(cell(10, 10)));
	// The yielded soldier may now return into the old sweep: the claims are gone.
	REQUIRE(one.set_siege_crew(0, false) && one.set_siege_crew(1, false));
	REQUIRE(four.set_siege_crew(0, false) && four.set_siege_crew(1, false));
	auto blob = one.save();
	REQUIRE(!blob.empty());
	World loaded(1);
	REQUIRE(loaded.load(blob));
	REQUIRE(loaded.state_hash() == one.state_hash());
}

static void enemy_in_sweep_still_blocks() {
	test_case = "SIEGE-YIELD: an enemy or other-team person in the sweep still refuses the turn and changes nothing";
	World w(1);
	auto c = tail_case(w, E);
	place(w, 0, 7, 7); place(w, 1, 8, 7);
	c.members = {{0, 1001, cell(7, 7), cell(7, 7)}, {1, 1002, cell(8, 7), cell(8, 7)}};
	c.source.clear(); c.target.clear();
	for (int depth = 0; depth < 2; ++depth) for (int width = 0; width < 2; ++width) {
		c.source.push_back(cell(10 + depth, 10 + width));
		c.target.push_back(cell(10 - width, 10 + depth));
	}
	full_sweep(c);
	place(w, 2, 11, 11);
	w.team[2] = 7; // another team: not yielding
	const auto before = w.state_hash();
	REQUIRE(w.begin_siege_compound(c.members, c.source, c.target, c.swept, 2) == 0);
	REQUIRE(w.state_hash() == before);
	REQUIRE(!w.siege_claims_cell(cell(11, 11)));
	// The same enemy is never moved by a claim: its slot target stays where the layout put it.
	float x = 11.5f, y = 11.5f;
	w.siege_slot_clear(2, x, y);
	REQUIRE(x == 11.5f && y == 11.5f);
	// An admitted own-team soldier stops yielding the moment its team changes (enemy inside a live claim).
	World v(1);
	int64_t token = 0;
	yield_turn(v, token);
	REQUIRE(token > 0);
	if (token <= 0) return;
	REQUIRE(v.siege_yields(2, cell(11, 11)));
	v.team[2] = 7;
	REQUIRE(!v.siege_yields(2, cell(11, 11)));
}

static void yield_slot_targets_avoid_claims() {
	test_case = "SIEGE-YIELD: a yielding soldier's slot target inside the claims moves to the nearest free cell; others unchanged";
	World w(1);
	int64_t token = 0;
	yield_turn(w, token);
	REQUIRE(token > 0);
	if (token <= 0) return;
	float x = 10.5f, y = 10.5f;
	w.siege_slot_clear(2, x, y);
	REQUIRE(!w.siege_claims_cell(w.terrain.idx((int)x, (int)y), 2));
	REQUIRE(std::abs(x - 10.5f) <= 6 && std::abs(y - 10.5f) <= 6);
	float cx = 20.5f, cy = 20.5f;
	w.siege_slot_clear(2, cx, cy);
	REQUIRE(cx == 20.5f && cy == 20.5f); // outside every claim: untouched
	float crew_x = 9.5f, crew_y = 10.5f;
	w.siege_slot_clear(0, crew_x, crew_y); // siege crew: never yields
	REQUIRE(crew_x == 9.5f && crew_y == 10.5f);
	REQUIRE(w.settle_siege_compound(token) == false); // still pending: nothing settled
}

// SIEGE-YIELD v4 fixture, mirroring the Site integration turn: the commander (index 0, captain, NOT crew) leads the
// same HOLD formation as the two stationary crew, stands in a turn sweep cell outside both bodies, and Site's person
// navigation blocks the vehicle footprint plus the whole rotating sweep (build_siege_navigation, stage "rotate").
struct YieldSite { std::vector<World::SiegeMember> members; std::vector<int> source, target, sweep, blocked; };
static YieldSite yield_site(World &w) {
	w.terrain.allocate(40,40);
	std::fill(w.terrain.height.begin(),w.terrain.height.end(),(uint8_t)0);
	w.terrain.base_height=w.terrain.height;
	w.cfg.ai=false;w.cfg.auto_capture=false;w.cfg.rescue_seek_cells=0;w.cfg.bleed_per_game_hour=0;
	const int f=w.add_formation(0,13.5f,13.5f,0,3,1,T_MELEE,0);
	const int other=w.add_formation(0,30.5f,30.5f,0,1,1,T_MELEE,0);
	rules::Equip e;e.family=rules::F_LONGSWORD;e.material=rules::M_IRON;
	w.add_soldier(f,e,R_CAPTAIN,1000);w.add_soldier(f,e,R_REGULAR,1001);w.add_soldier(f,e,R_REGULAR,1002);w.add_soldier(other,e,R_CAPTAIN,2001);
	w.finalize();for(auto &formation:w.formations)formation.ai_enabled=false;
	place(w,0,13,12);place(w,1,7,7);place(w,2,8,7);place(w,3,30,30);
	REQUIRE(w.set_siege_crew(1,true));REQUIRE(w.set_siege_crew(2,true));w.events.clear();
	YieldSite s;
	s.members={{1,1001,cell(7,7),cell(7,7)},{2,1002,cell(8,7),cell(8,7)}};
	for(int y=9;y<=11;++y)for(int x=10;x<=11;++x)s.source.push_back(cell(x,y)); // 2 x 3, facing up
	for(int y=10;y<=11;++y)for(int x=10;x<=12;++x)s.target.push_back(cell(x,y)); // 3 x 2, facing right
	for(int y=8;y<=15;++y)for(int x=8;x<=15;++x)s.sweep.push_back(cell(x,y));     // the turn circle (radius 4) square
	s.blocked=s.sweep; // footprint (inside the sweep) plus the rotating sweep
	return s;
}
static bool in_cells(const World &w,int i,const std::vector<int> &cells) {
	const int c=w.terrain.idx((int)std::floor(w.px[i]),(int)std::floor(w.py[i]));
	return std::find(cells.begin(),cells.end(),c)!=cells.end();
}

static void commander_steps_out_under_site_navigation() {
	test_case="SIEGE-YIELD v4: a formation-leading own-team commander steps out of a Site-blocked turn sweep, then returns";
	World one(1),four(4);
	auto s=yield_site(one);yield_site(four);
	// Before the turn: the commander holds its slot, inside the future sweep but outside both bodies.
	for(int k=0;k<8;++k){step(one);step(four);}
	REQUIRE(in_cells(one,0,s.sweep) && !in_cells(one,0,s.source) && !in_cells(one,0,s.target));
	int slot_index=-1;float home_x=0,home_y=0,clip=0;
	REQUIRE(one.slot_target(0,slot_index,home_x,home_y,clip));
	REQUIRE(slot_index>=0 && in_cells(one,0,{one.terrain.idx((int)home_x,(int)home_y)}));
	const int64_t a=one.begin_siege_compound(s.members,s.source,s.target,s.sweep,3);
	const int64_t b=four.begin_siege_compound(s.members,s.source,s.target,s.sweep,3);
	REQUIRE(a>0 && b>0);
	if(a<=0 || b<=0) return;
	// Site syncs its person navigation after the turn begins: footprint plus the rotating sweep (stage "rotate").
	REQUIRE(one.set_siege_navigation(s.blocked,{}) && four.set_siege_navigation(s.blocked,{}));
	// The mask exemption is the yielder's only: never the current body, never for crew or a person of another team.
	// v5: the future (target-only) body is still empty and passable; the current (source) body never is.
	REQUIRE(one.siege_yield_passable(0,cell(13,13)) && !one.siege_yield_passable(0,cell(11,10)) && one.siege_yield_passable(0,cell(12,11)));
	REQUIRE(!one.siege_person_cell(0,cell(13,12),cell(14,12))); // committed Site steps keep the mask (order_*_step)
	REQUIRE(!one.siege_yield_passable(1,cell(13,13)) && !one.siege_yield_passable(3,cell(15,12))); // crew; own team outside the sweep
	World enemy(1);yield_site(enemy);enemy.team[3]=7;place(enemy,3,16,12);
	REQUIRE(enemy.begin_siege_compound(s.members,s.source,s.target,s.sweep,3)>0);
	REQUIRE(enemy.set_siege_navigation(s.blocked,{}));
	place(enemy,3,13,12);REQUIRE(!enemy.siege_yield_passable(3,cell(13,13)) && !enemy.siege_yields(3,cell(13,12))); // other team inside: no exemption
	bool left=false;
	for(int tick=1;tick<=12;++tick) {
		step(one);step(four);
		REQUIRE(one.state_hash()==four.state_hash());
		std::string error;REQUIRE(one.validate(&error,true) && four.validate(&error,true));
		close(one.px[1],7.5);close(one.py[1],7.5);close(one.px[2],8.5);close(one.py[2],7.5);
		if(!one.siege_compound_state(a)->complete && !in_cells(one,0,s.sweep)) left=true;
		REQUIRE(!in_cells(one,0,s.source) && !in_cells(one,0,s.target)); // never through the turning vehicle's bodies
	}
	REQUIRE(left); // stepped out while the turn was still rotating
	REQUIRE(!in_cells(one,0,s.sweep) && !in_cells(four,0,s.sweep));
	REQUIRE(one.px[0]==four.px[0] && one.py[0]==four.py[0] && one.hp[0]==100 && one.ko[0]==0);
	REQUIRE(one.siege_compound_state(a)->complete && !one.siege_compound_state(a)->cancelled);
	REQUIRE(one.settle_siege_compound(a) && four.settle_siege_compound(b));
	// Site releases the sweep and keeps only the turned footprint.
	REQUIRE(one.set_siege_navigation(s.target,{}) && four.set_siege_navigation(s.target,{}));
	for(int k=0;k<16;++k){step(one);step(four);REQUIRE(one.state_hash()==four.state_hash());}
	REQUIRE(std::abs(one.px[0]-home_x)<0.25f && std::abs(one.py[0]-home_y)<0.25f); // back at its slot
}

// SIEGE-YIELD v5: the Site integration geometry. A traction (3 x 4, radius 5) or counterweight (4 x 6, radius 7)
// trebuchet at anchor (18,20) faces up and turns right; the sweep is the anchor's radius square (siege_turn_sweep). The
// formation-leading commander stands at anchor + (1,1), as (21,42) does at anchor (20,41): inside the FUTURE body, so it
// must cross target-body cells (still empty) and up to 8 sweep cells to step out; the current body stays impassable.
static void commander_in_target_body_steps_out(int size_x, int size_y, int radius, double duration) {
	test_case="SIEGE-YIELD v5: a commander standing in the future body of a Site-blocked turn steps out during the rotation";
	World one(1),four(4);
	std::vector<World::SiegeMember> members;
	std::vector<int> source,target,sweep,blocked;
	for(World *w:{&one,&four}) {
		w->terrain.allocate(40,40);
		std::fill(w->terrain.height.begin(),w->terrain.height.end(),(uint8_t)0);
		w->terrain.base_height=w->terrain.height;
		w->cfg.ai=false;w->cfg.auto_capture=false;w->cfg.rescue_seek_cells=0;w->cfg.bleed_per_game_hour=0;
		const int f=w->add_formation(0,19.5f,22.5f,0,3,1,T_MELEE,0);
		rules::Equip e;e.family=rules::F_LONGSWORD;e.material=rules::M_IRON;
		w->add_soldier(f,e,R_CAPTAIN,1000);w->add_soldier(f,e,R_REGULAR,1001);w->add_soldier(f,e,R_REGULAR,1002);
		w->finalize();for(auto &formation:w->formations)formation.ai_enabled=false;
		place(*w,0,19,21);place(*w,1,10,30);place(*w,2,11,30);
		REQUIRE(w->set_siege_crew(1,true));REQUIRE(w->set_siege_crew(2,true));w->events.clear();
	}
	members={{1,1001,cell(10,30),cell(10,30)},{2,1002,cell(11,30),cell(11,30)}};
	for(int forward=0;forward<size_y;++forward)for(int across=0;across<size_x;++across) {
		source.push_back(cell(18+across,20-forward));   // facing up, side right
		target.push_back(cell(18+forward,20+across));   // facing right, side down
	}
	for(int y=-radius;y<=radius;++y)for(int x=-radius;x<=radius;++x)sweep.push_back(cell(18+x,20+y));
	blocked=sweep;
	REQUIRE(one.set_siege_navigation(source,{}) && four.set_siege_navigation(source,{}));
	for(int k=0;k<8;++k){step(one);step(four);}
	REQUIRE(in_cells(one,0,target) && !in_cells(one,0,source)); // stands where the turned body will be
	const int64_t a=one.begin_siege_compound(members,source,target,sweep,duration);
	const int64_t b=four.begin_siege_compound(members,source,target,sweep,duration);
	REQUIRE(a>0 && b>0);
	if(a<=0 || b<=0) return;
	REQUIRE(one.set_siege_navigation(blocked,{}) && four.set_siege_navigation(blocked,{}));
	REQUIRE(one.siege_yield_passable(0,cell(19,22)) && !one.siege_yield_passable(0,cell(19,20))); // target yes, source no
	bool left=false;
	const int ticks=(int)std::ceil(duration/.25);
	for(int tick=1;tick<=ticks;++tick) {
		step(one);step(four);
		REQUIRE(one.state_hash()==four.state_hash());
		std::string error;REQUIRE(one.validate(&error,true) && four.validate(&error,true));
		close(one.px[1],10.5);close(one.py[1],30.5);close(one.px[2],11.5);close(one.py[2],30.5);
		REQUIRE(!in_cells(one,0,source)); // never through the current body
		if(!one.siege_compound_state(a)->complete && !in_cells(one,0,sweep)) left=true;
	}
	REQUIRE(left);
	REQUIRE(!in_cells(one,0,sweep) && one.px[0]==four.px[0] && one.py[0]==four.py[0] && one.ko[0]==0);
	REQUIRE(one.siege_compound_state(a)->complete && !one.siege_compound_state(a)->cancelled);
	REQUIRE(one.settle_siege_compound(a) && four.settle_siege_compound(b));
	REQUIRE(one.set_siege_navigation(target,{}) && four.set_siege_navigation(target,{}));
	for(int k=0;k<12;++k){step(one);step(four);REQUIRE(one.state_hash()==four.state_hash());REQUIRE(!in_cells(one,0,target));}
}

// SIEGE-YIELD v6: the commander keeps command through the turn. As in the Site fixture, eight crew stand at their
// turning stations behind the body (anchor + 6 or 8 back), the commander stands behind the body inside the sweep, and its
// own formation slot lies north of the vehicle, beyond the presence radius (command.cpp refresh_presence) of the crew
// row. Stepping out it stays with the formation (siege_turn_hold), so it stays present and command-eligible.
static void commander_keeps_command_through_turn(int size_x, int size_y, int radius, int back, double duration) {
	test_case="SIEGE-YIELD v6: a stepping-out commander stays with its turning crew and keeps command";
	World one(1),four(4);
	std::vector<World::SiegeMember> members;
	std::vector<int> source,target,sweep;
	for(int forward=0;forward<size_y;++forward)for(int across=0;across<size_x;++across) {
		source.push_back(cell(18+across,20-forward)); target.push_back(cell(18+forward,20+across));
	}
	for(int y=-radius;y<=radius;++y)for(int x=-radius;x<=radius;++x)sweep.push_back(cell(18+x,20+y));
	for(int k=0;k<8;++k)members.push_back({1+k,(int64_t)(1001+k),cell(16+k,20+back),cell(16+k,20+back)});
	for(World *w:{&one,&four}) {
		w->terrain.allocate(40,40);
		std::fill(w->terrain.height.begin(),w->terrain.height.end(),(uint8_t)0);
		w->terrain.base_height=w->terrain.height;
		w->cfg.ai=false;w->cfg.auto_capture=false;w->cfg.rescue_seek_cells=0;w->cfg.bleed_per_game_hour=0;
		const int f=w->add_formation(0,18.5f,8.5f,0,3,1,T_MELEE,0);
		rules::Equip e;e.family=rules::F_LONGSWORD;e.material=rules::M_IRON;
		w->add_soldier(f,e,R_CAPTAIN,1000);
		for(int k=0;k<8;++k)w->add_soldier(f,e,R_REGULAR,1001+k);
		w->finalize();for(auto &formation:w->formations)formation.ai_enabled=false;
		place(*w,0,19,21);
		for(int k=0;k<8;++k){place(*w,1+k,16+k,20+back);REQUIRE(w->set_siege_crew(1+k,true));}
		w->events.clear();
		REQUIRE(w->set_siege_navigation(source,{}));
		step(*w);
		place(*w,0,19,21); // the commander stands behind the body (Site: stuck there before the turn)
	}
	int slot_index=-1;float sx=0,sy=0,clip=0;
	REQUIRE(one.slot_target(0,slot_index,sx,sy,clip) && sy<20.f-radius); // its own slot lies north, outside the sweep
	REQUIRE(one.command_eligible(0) && one.formations[0].commander_present && in_cells(one,0,sweep) && in_cells(one,0,target));
	const int64_t a=one.begin_siege_compound(members,source,target,sweep,duration);
	const int64_t b=four.begin_siege_compound(members,source,target,sweep,duration);
	REQUIRE(a>0 && b>0);
	if(a<=0 || b<=0) return;
	REQUIRE(one.set_siege_navigation(sweep,{}) && four.set_siege_navigation(sweep,{}));
	REQUIRE(one.siege_turn_hold(0) && !one.siege_turn_hold(1));
	bool left=false;
	const int ticks=(int)std::ceil(duration/.25);
	for(int tick=1;tick<=ticks;++tick) {
		step(one);step(four);
		REQUIRE(one.state_hash()==four.state_hash());
		std::string error;REQUIRE(one.validate(&error,true) && four.validate(&error,true));
		REQUIRE(!in_cells(one,0,source));
		REQUIRE(one.present[0]==1 && one.command_eligible(0) && one.formations[0].commander_present); // never loses command
		if(!one.siege_compound_state(a)->complete && !in_cells(one,0,sweep)) left=true;
	}
	REQUIRE(left);
	REQUIRE(one.siege_compound_state(a)->complete && one.settle_siege_compound(a) && four.settle_siege_compound(b));
	REQUIRE(!one.siege_turn_hold(0)); // settled: the ordinary slot returns
}

int main() {
	admission_atomicity();phase_barrier_and_save();hit_death_cancel_finish();terrain_abort_one_fall();crew_exclusion_and_thread_determinism();approach_source_and_wreck_navigation();original_orders_are_preserved();
	true_tail_four_directions();tail_rejections();stationary_rotation_keeps_full_sweep();tail_interruptions_finish_original_barrier();
	original_contact_revision_import();
	own_team_yields_and_turn_completes();enemy_in_sweep_still_blocks();yield_slot_targets_avoid_claims();
	commander_steps_out_under_site_navigation();
	commander_in_target_body_steps_out(3,4,5,6);commander_in_target_body_steps_out(4,6,7,10);
	commander_keeps_command_through_turn(3,4,5,6,6);commander_keeps_command_through_turn(4,6,7,8,10);
	std::printf("SIEGE_NATIVE_COMPOUND_CONTRACT checks=%d failures=%d\n",checks,failures);return failures?1:0;
}
