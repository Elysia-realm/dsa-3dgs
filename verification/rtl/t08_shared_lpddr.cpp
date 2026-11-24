// Simulation-side, unbuffered shared AXI timing bridge. Data remain in the
// checked AXI backing model. All seven ports compete at a common line arbiter.
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <memory>
#include <vector>
#include "Config.h"
#include "Controller.h"
#include "LPDDR4.h"
#include "Memory.h"

using namespace ramulator;
bool ramulator::warmup_complete=false;
namespace {
using Model=Memory<LPDDR4,Controller>;
struct Burst {
    int port,tag,left;
    uint64_t next,last;
};
struct Address { uint64_t addr; int beats; };
struct Port {
    std::deque<std::shared_ptr<Burst>> queue;
    std::deque<Address> aw;
    int wlast=0,accepted=0,completed=0;
};
Port ports[7];
Model* model=nullptr;
uint32_t read_done=0,read_busy=0;
uint64_t dram_ticks=0,issued=0;
int rr=0;
void require(bool ok) {
    if(!ok){std::fprintf(stderr,"invalid shared LPDDR interface sequence\n");std::abort();}
}
bool writing(int p){return p==4||p==6;}
int bit(int p,int tag){return p==5 ? 4+tag : p;}
void enqueue(int p,int tag,uint64_t addr,int beats) {
    require(beats>=1 && beats<=256 && (addr&15)==0 && addr+16ULL*beats<=0x80000000ULL);
    uint64_t first=addr&~63ULL,last=(addr+16ULL*beats-1)&~63ULL;
    ports[p].queue.push_back(std::make_shared<Burst>(Burst{p,tag,int((last-first)/64)+1,first,last}));
    require(ports[p].queue.size()<=64);
}
void completed(const std::shared_ptr<Burst>& req) {
    require(req->left>0);
    if(--req->left!=0)return;
    auto& port=ports[req->port];
    ++port.completed;
    if(!writing(req->port)){
        auto mask=uint32_t(1)<<bit(req->port,req->tag);
        require((read_busy&mask)!=0);
        read_busy&=~mask;read_done|=mask;
    }
}
void join_write_channels(int p) {
    auto& port=ports[p];
    while(port.wlast && !port.aw.empty()){
        auto desc=port.aw.front();port.aw.pop_front();--port.wlast;
        enqueue(p,0,desc.addr,desc.beats);
    }
}
void tick_model(){model->tick();++dram_ticks;++Stats::curTick;}
}
extern "C" void t08_shared_init(const char* cfg,const char* stats) {
    require(model==nullptr);
    Config config(cfg);
    require(config["standard"]=="LPDDR4" && config["speed"]=="LPDDR4_2400");
    config.add("trace_type","DRAM");config.add("mapping","defaultmapping");config.set_core_num(1);
    Stats::statlist.output(stats);
    auto* spec=new LPDDR4(config["org"],config["speed"]);
    spec->set_channel_number(config.get_channels());spec->set_rank_number(config.get_ranks());
    require(config.get_channels()==2 && spec->prefetch_size*spec->channel_width==512);
    std::vector<Controller<LPDDR4>*> ctrls;
    for(int c=0;c<config.get_channels();++c){
        auto* channel=new DRAM<LPDDR4>(spec,LPDDR4::Level::Channel);
        channel->id=c;channel->regStats("");
        ctrls.push_back(new Controller<LPDDR4>(config,channel));
    }
    model=new Model(config,ctrls);
}
extern "C" void t08_shared_addr(int p,int tag,unsigned long long addr,int beats) {
    require(p>=0 && p<7 && tag>=0 && tag<4);
    auto& port=ports[p];++port.accepted;
    if(writing(p)){
        port.aw.push_back({addr,beats});require(port.aw.size()<=64);join_write_channels(p);
    } else {
        auto mask=uint32_t(1)<<bit(p,tag);
        require((read_busy&mask)==0);
        read_done&=~mask;read_busy|=mask;
        enqueue(p,tag,addr,beats);
    }
}
extern "C" void t08_shared_wlast(int p) {
    require(writing(p));++ports[p].wlast;require(ports[p].wlast<=64);join_write_channels(p);
}
extern "C" void t08_shared_step(int* done,int* qsu_writes,int* out_writes) {
    for(int sub=0;sub<6;++sub){
        for(int k=0;k<7;++k){
            int p=(rr+k)%7;
            auto& queue=ports[p].queue;
            if(queue.empty())continue;
            auto b=queue.front();
            Request req(static_cast<long>(b->next),writing(p)?Request::Type::WRITE:Request::Type::READ,
                        [b](Request&){completed(b);});
            if(!model->send(req))continue;
            ++issued;
            if(writing(p))completed(b);
            if(b->next==b->last)queue.pop_front();else b->next+=64;
            rr=(p+1)%7;break;
        }
        tick_model();
    }
    *done=static_cast<int>(read_done);*qsu_writes=ports[4].completed;*out_writes=ports[6].completed;
}
extern "C" void t08_shared_finish(unsigned long long* count,unsigned long long* tail) {
    for(const auto& p:ports)require(p.accepted==p.completed && p.queue.empty() && p.aw.empty() && !p.wlast);
    require(read_busy==0);
    auto start=dram_ticks;
    model->set_high_writeq_watermark(0.0f);
    while(model->pending_requests())tick_model();
    model->finish();Stats::statlist.printall();*count=issued;*tail=dram_ticks-start;
}
