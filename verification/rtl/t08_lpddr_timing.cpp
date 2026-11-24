// DPI timing model for a single in-order line requester. Write acknowledgment
// is controller admission; reads wait for Ramulator's completion callback.
#include <cstdint>
#include "Config.h"
#include "Controller.h"
#include "LPDDR4.h"
#include "Memory.h"
#include "Request.h"
#include <cstdlib>
#include <cstdio>
#include <vector>

using namespace ramulator;
bool ramulator::warmup_complete = false;
namespace {
using Model = Memory<LPDDR4, Controller>;
Model* memory = nullptr;
bool awaiting = false;
bool data_ready = false;
unsigned long long dram_cycles = 0;
void require(bool ok) {
    if (!ok) { std::fprintf(stderr, "T08 Ramulator interface contract failed\n"); std::abort(); }
}
void step() {
    memory->tick();
    ++Stats::curTick;
    ++dram_cycles;
}
}
extern "C" void t08_mem_init(const char* cfg, const char* output) {
    require(memory == nullptr);
    Config config(cfg);
    require(config["standard"] == "LPDDR4" && config["speed"] == "LPDDR4_2400");
    config.add("trace_type", "DRAM");
    config.add("mapping", "defaultmapping");
    config.set_core_num(1);
    Stats::statlist.output(output);
    auto* spec = new LPDDR4(config["org"],config["speed"]);
    spec->set_channel_number(config.get_channels());
    spec->set_rank_number(config.get_ranks());
    require(config.get_channels()==2 && spec->prefetch_size*spec->channel_width==512);
    std::vector<Controller<LPDDR4>*> ctrls;
    for(int c=0;c<config.get_channels();++c) {
        auto* channel = new DRAM<LPDDR4>(spec,LPDDR4::Level::Channel);
        channel->id=c;
        channel->regStats("");
        ctrls.push_back(new Controller<LPDDR4>(config,channel));
    }
    memory=new Model(config,ctrls);
}
extern "C" void t08_mem_tick() {
    for(int i=0;i<6;++i) step(); // 1200 MHz DRAM, 200 MHz requester
}
extern "C" int t08_mem_send(unsigned long long addr, int write) {
    require(!awaiting && (addr&63)==0);
    Request req(static_cast<long>(addr),write ? Request::Type::WRITE : Request::Type::READ,
                [](Request&){ data_ready=true; });
    if (!memory->send(req)) return 0;
    awaiting=true;
    data_ready=write!=0;
    return 1;
}
extern "C" int t08_mem_take() {
    if (!awaiting || !data_ready) return 0;
    awaiting=false;
    data_ready=false;
    return 1;
}
extern "C" unsigned long long t08_mem_finish() {
    require(!awaiting);
    memory->set_high_writeq_watermark(0.0f);
    while(memory->pending_requests()) step();
    memory->finish();
    Stats::statlist.printall();
    return dram_cycles;
}
