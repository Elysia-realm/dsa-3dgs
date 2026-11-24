// Capacity-safe hierarchical 7-pivot QSU. External memory holds two N-record
// ping-pong banks; only a bounded DFS descriptor stack lives on chip.
// Stable scatter and near-to-far DFS establish GLOBAL order between leaves.
// A leaf is NOT internally sorted: it must traverse the production T05 BSU.
module autonomous_qsu #(
    parameter int DEPTH_W=27, GID_W=32, SEQ_W=32, GROUP_W=3,
    parameter int CAPACITY=16,
    parameter int LOCAL_RECORDS=0,
    parameter bit PRECOUNT_CHILDREN=0,
    parameter int KEY_W=DEPTH_W+GID_W+SEQ_W,
    parameter int STACK_DEPTH=7*((KEY_W+2)/3)+1
) (
    input logic clk_i,rst_ni,start_i,
    input logic [31:0] capacity_i,
    input logic s_valid_i,output logic s_ready_o,
    input logic signed [DEPTH_W-1:0] s_depth_i,
    input logic [GID_W-1:0] s_gid_i,input logic [SEQ_W-1:0] s_seq_i,
    input logic end_i,
    output logic m_valid_o,input logic m_ready_i,
    output logic signed [DEPTH_W-1:0] m_depth_o,
    output logic [GID_W-1:0] m_gid_o,output logic [SEQ_W-1:0] m_seq_o,
    output logic [GROUP_W-1:0] m_group_o,
    output logic m_first_o,m_last_o,
    output logic busy_o,done_o,error_o,
    // Addresses are RECORD indices, not byte addresses. Bank is independent.
    output logic rd_valid_o,input logic rd_ready_i,
    output logic rd_bank_o,output logic [31:0] rd_offset_o,rd_count_o,
    input logic r_valid_i,output logic r_ready_o,
    input logic [127:0] r_data_i,input logic r_last_i,rd_busy_i,
    output logic wr_valid_o,input logic wr_ready_i,
    output logic wr_bank_o,output logic [31:0] wr_offset_o,
    output logic [127:0] wr_data_o,input logic wr_busy_i,mem_error_i,
    output logic [31:0] perf_input_o,perf_partitions_o,perf_leaves_o,
    output logic [31:0] perf_read_o,perf_write_o,perf_stall_o,perf_peak_stack_o
);
    typedef enum logic [4:0] {IDLE,COLLECT,COLLECT_FENCE,VISIT,COUNT_REQ,COUNT_DATA,
        OFFSETS,SCATTER_REQ,SCATTER_DATA,WRITE_FENCE,PUSH,POP,LEAF_REQ,LEAF_DATA,FAIL_DRAIN,
        LOCAL_LOAD_REQ,LOCAL_LOAD_DATA} state_t;
    state_t state_q;
    logic [31:0] capacity_q,base_q,count_q,total_q;
    logic bank_q;
    logic [KEY_W-1:0] min_q,max_q;
    logic [31:0] stack_base[STACK_DEPTH],stack_count[STACK_DEPTH];
    logic stack_bank[STACK_DEPTH];
    logic [KEY_W-1:0] stack_min[STACK_DEPTH],stack_max[STACK_DEPTH];
    localparam int SP_W=$clog2(STACK_DEPTH+1);
    logic [SP_W-1:0] sp_q;
    localparam int LOCAL_SIZE=LOCAL_RECORDS>0?LOCAL_RECORDS:1;
    logic [KEY_W-1:0] local_mem[0:2*LOCAL_SIZE-1];
    logic local_active_q;
    logic [SP_W-1:0] local_exit_sp_q;
    logic [31:0] local_base_q,local_index_q,local_left_q,local_load_q;
    logic stream_valid,stream_ready,stream_last,write_ready;
    logic [127:0] stream_data;
    logic [KEY_W-1:0] local_read_data;
    logic [31:0] counts[8],offsets[8],writes[8];
    logic [KEY_W-1:0] mins[8],maxs[8],pivots[7];
    // Scatter simultaneously prepares each child's exact next histogram.
    // Bounded DFS storage, never proportional to the input model size.
    localparam int HIST_N=PRECOUNT_CHILDREN?64:1;
    localparam int STACK_HIST_N=PRECOUNT_CHILDREN?STACK_DEPTH*8:1;
    logic [31:0] child_counts[HIST_N],saved_counts[STACK_HIST_N];
    logic [KEY_W-1:0] child_mins[HIST_N],child_maxs[HIST_N];
    logic [KEY_W-1:0] saved_mins[STACK_HIST_N],saved_maxs[STACK_HIST_N];
    logic histogram_ready_q;
    integer child_shift[8];
    logic [2:0] child_bucket;
    logic [5:0] child_slot;
    logic [KEY_W-1:0] input_key,read_key,difference,prefix;
    logic [2:0] bucket,push_q;
    logic [$clog2(CAPACITY+1)-1:0] leaf_pos_q;
    // Atomic leaf commit: a read error must NEVER strand a half-group inside
    // the BSU. Two banks decouple next-leaf prefetch from prior-leaf emission.
    logic [KEY_W-1:0] leaf_mem[2][CAPACITY];
    logic [1:0] leaf_full_q;
    logic leaf_write_bank_q,leaf_read_bank_q;
    logic [$clog2(CAPACITY+1)-1:0] leaf_count_q[2],leaf_emit_pos_q;
    logic [GROUP_W-1:0] group_q;
    integer shift_bits;
    logic collect_fire,read_fire;
    function automatic logic [KEY_W-1:0] order_key(input logic [KEY_W-1:0] raw);
        order_key=raw ^ ({{(KEY_W-1){1'b0}},1'b1} << (KEY_W-1));
    endfunction
    assign input_key=order_key({s_depth_i,s_gid_i,s_seq_i});
    assign stream_valid=local_active_q ? local_left_q!=0 : r_valid_i;
    assign local_read_data=local_mem[(bank_q?LOCAL_SIZE:0)+local_index_q];
    assign stream_data=local_active_q ? {{(128-KEY_W){1'b0}},local_read_data} : r_data_i;
    assign stream_last=local_active_q ? local_left_q==1 : r_last_i;
    assign write_ready=local_active_q ? 1'b1 : wr_ready_i;
    assign read_key=order_key(stream_data[KEY_W-1:0]);
    // Common-prefix compression prevents repeatedly scanning an all-in-one
    // bucket. Each nontrivial pass removes up to three significant key bits.
    always_comb begin
        difference=min_q^max_q;shift_bits=0;
        for(integer j=0;j<KEY_W;j=j+1) if(difference[j]) shift_bits=(j>2)?j-2:0;
        prefix=(min_q >> shift_bits) >> 3;
        prefix=(prefix << 3) << shift_bits;
        for(integer j=0;j<7;j=j+1) pivots[j]=prefix | (KEY_W'(j+1)<<shift_bits);
        bucket=0;
        for(integer j=0;j<7;j=j+1) if(read_key>=pivots[j]) bucket=bucket+1'b1;
    end
    // Prefixes are registered once before scatter; no priority encoder lies
    // on the per-record histogram update path. Bucket is the next three bits.
    always_comb begin
        child_bucket=0;
        if(PRECOUNT_CHILDREN)
            child_bucket=3'(read_key>>child_shift[bucket]);
        child_slot={bucket,child_bucket};
    end
    assign busy_o=state_q!=IDLE||(|leaf_full_q);
    assign s_ready_o=state_q==COLLECT && (error_o||mem_error_i||total_q>=capacity_q||wr_ready_i);
    assign collect_fire=s_valid_i&&s_ready_o;
    assign rd_valid_o=!local_active_q&&(state_q==COUNT_REQ||state_q==SCATTER_REQ||state_q==LEAF_REQ||state_q==LOCAL_LOAD_REQ);
    assign rd_bank_o=bank_q;assign rd_offset_o=base_q;assign rd_count_o=count_q;
    // Previously committed banks finish even on a later DMA fault. Partial
    // uncommitted banks are discarded. Error status prevents RGB completion.
    assign m_valid_o=leaf_full_q[leaf_read_bank_q];
    assign m_depth_o=leaf_mem[leaf_read_bank_q][leaf_emit_pos_q][SEQ_W+GID_W+:DEPTH_W];
    assign m_gid_o=leaf_mem[leaf_read_bank_q][leaf_emit_pos_q][SEQ_W+:GID_W];
    assign m_seq_o=leaf_mem[leaf_read_bank_q][leaf_emit_pos_q][0+:SEQ_W];
    assign m_group_o=group_q;assign m_first_o=leaf_emit_pos_q==0;
    assign m_last_o=leaf_emit_pos_q+1'b1==leaf_count_q[leaf_read_bank_q];
    assign stream_ready=state_q==FAIL_DRAIN || state_q==COUNT_DATA ||state_q==LOCAL_LOAD_DATA||
        (state_q==SCATTER_DATA&&write_ready) || (state_q==LEAF_DATA&&!leaf_full_q[leaf_write_bank_q]);
    assign r_ready_o=state_q==FAIL_DRAIN||(!local_active_q&&stream_ready);
    assign read_fire=stream_valid&&stream_ready;
    assign wr_valid_o=!local_active_q&&!error_o&&!mem_error_i &&
        ((state_q==COLLECT&&s_valid_i&&total_q<capacity_q) ||
         (state_q==SCATTER_DATA&&r_valid_i));
    assign wr_bank_o=state_q==COLLECT?1'b0:!bank_q;
    assign wr_offset_o=state_q==COLLECT?total_q:offsets[bucket]+writes[bucket];
    assign wr_data_o=state_q==COLLECT?128'({s_depth_i,s_gid_i,s_seq_i}):r_data_i;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni) begin
            state_q<=IDLE;capacity_q<=0;base_q<=0;count_q<=0;total_q<=0;bank_q<=0;
            min_q<='1;max_q<=0;sp_q<=0;push_q<=0;leaf_pos_q<=0;group_q<=0;
            histogram_ready_q<=0;
            local_active_q<=0;local_exit_sp_q<=0;local_base_q<=0;local_index_q<=0;local_left_q<=0;local_load_q<=0;
            leaf_full_q<=0;leaf_write_bank_q<=0;leaf_read_bank_q<=0;leaf_emit_pos_q<=0;leaf_count_q[0]<=0;leaf_count_q[1]<=0;
            error_o<=0;done_o<=0;perf_input_o<=0;perf_partitions_o<=0;perf_leaves_o<=0;
            perf_read_o<=0;perf_write_o<=0;perf_stall_o<=0;perf_peak_stack_o<=0;
            for(integer j=0;j<8;j=j+1)begin counts[j]<=0;offsets[j]<=0;writes[j]<=0;mins[j]<='1;maxs[j]<=0;end
        end else begin
            done_o<=0;
            if(wr_valid_o&&wr_ready_i)perf_write_o<=perf_write_o+1;
            if(r_valid_i&&r_ready_o)perf_read_o<=perf_read_o+1;
            if(local_active_q&&read_fire)begin local_index_q<=local_index_q+1;local_left_q<=local_left_q-1;end
            if(local_active_q&&state_q==SCATTER_DATA&&read_fire&&!mem_error_i)
                local_mem[(!bank_q?LOCAL_SIZE:0)+offsets[bucket]+writes[bucket]-local_base_q]<=stream_data[KEY_W-1:0];
            if((m_valid_o&&!m_ready_i)||(wr_valid_o&&!wr_ready_i))perf_stall_o<=perf_stall_o+1;
            if(sp_q>perf_peak_stack_o)perf_peak_stack_o<=32'(sp_q);
            if(m_valid_o&&m_ready_i)begin
                if(m_last_o)begin
                    leaf_full_q[leaf_read_bank_q]<=0;leaf_read_bank_q<=!leaf_read_bank_q;
                    leaf_emit_pos_q<=0;group_q<=group_q+1'b1;perf_leaves_o<=perf_leaves_o+1;
                end else leaf_emit_pos_q<=leaf_emit_pos_q+1'b1;
            end
            case(state_q)
                IDLE:if(start_i)begin
                    state_q<=COLLECT;capacity_q<=capacity_i;total_q<=0;sp_q<=0;
                    min_q<='1;max_q<=0;error_o<=0;group_q<=0;leaf_pos_q<=0;
                    histogram_ready_q<=0;
                    local_active_q<=0;local_left_q<=0;local_load_q<=0;
                    leaf_full_q<=0;leaf_write_bank_q<=0;leaf_read_bank_q<=0;leaf_emit_pos_q<=0;
                    perf_input_o<=0;perf_partitions_o<=0;perf_leaves_o<=0;
                    perf_read_o<=0;perf_write_o<=0;perf_stall_o<=0;perf_peak_stack_o<=0;
                end
                COLLECT:begin
                    if(collect_fire)begin
                        if(total_q>=capacity_q)error_o<=1;
                        else if(!error_o&&!mem_error_i)begin
                            total_q<=total_q+1;perf_input_o<=perf_input_o+1;
                            if(input_key<min_q)min_q<=input_key;
                            if(input_key>max_q)max_q<=input_key;
                        end
                    end
                    if(end_i)state_q<=COLLECT_FENCE;
                end
                COLLECT_FENCE:if(!wr_busy_i)begin
                    base_q<=0;count_q<=total_q;bank_q<=0;
                    if(error_o||mem_error_i)state_q<=FAIL_DRAIN;
                    else if(total_q==0)begin state_q<=IDLE;done_o<=1;end
                    else state_q<=VISIT;
                end
                VISIT:begin
                    if(count_q<=CAPACITY||min_q==max_q)begin
                        state_q<=LEAF_REQ;leaf_pos_q<=0;
                    end else if(PRECOUNT_CHILDREN&&histogram_ready_q)begin
                        for(integer j=0;j<8;j=j+1)writes[j]<=0;
                        state_q<=OFFSETS;perf_partitions_o<=perf_partitions_o+1;
                    end else if(LOCAL_RECORDS>CAPACITY&&!local_active_q&&count_q<=LOCAL_RECORDS)begin
                        local_base_q<=base_q;local_exit_sp_q<=sp_q;local_load_q<=0;state_q<=LOCAL_LOAD_REQ;
                        for(integer j=0;j<8;j=j+1)begin counts[j]<=0;writes[j]<=0;mins[j]<='1;maxs[j]<=0;end
                        perf_partitions_o<=perf_partitions_o+1;
                    end else begin
                        for(integer j=0;j<8;j=j+1)begin counts[j]<=0;writes[j]<=0;mins[j]<='1;maxs[j]<=0;end
                        state_q<=COUNT_REQ;perf_partitions_o<=perf_partitions_o+1;
                    end
                end
                LOCAL_LOAD_REQ:if(rd_ready_i)state_q<=LOCAL_LOAD_DATA;
                LOCAL_LOAD_DATA:if(read_fire)begin
                    local_mem[(bank_q?LOCAL_SIZE:0)+local_load_q]<=r_data_i[KEY_W-1:0];local_load_q<=local_load_q+1;
                    // The load is already the first count pass; do not scan it twice.
                    counts[bucket]<=counts[bucket]+1;
                    if(read_key<mins[bucket])mins[bucket]<=read_key;
                    if(read_key>maxs[bucket])maxs[bucket]<=read_key;
                    if(r_last_i)begin local_active_q<=1;local_left_q<=0;state_q<=OFFSETS;end
                end
                COUNT_REQ:if(local_active_q||rd_ready_i)begin
                    if(local_active_q)begin local_index_q<=base_q-local_base_q;local_left_q<=count_q;end
                    state_q<=COUNT_DATA;
                end
                COUNT_DATA:if(read_fire)begin
                    counts[bucket]<=counts[bucket]+1;
                    if(read_key<mins[bucket])mins[bucket]<=read_key;
                    if(read_key>maxs[bucket])maxs[bucket]<=read_key;
                    if(stream_last)state_q<=OFFSETS;
                end
                OFFSETS:begin
                    if(PRECOUNT_CHILDREN)begin
                        for(integer j=0;j<64;j=j+1)begin
                            child_counts[j]<=0;child_mins[j]<='1;child_maxs[j]<=0;
                        end
                        for(integer j=0;j<8;j=j+1)begin : child_pivot_prepare
                            integer sh;
                            logic [KEY_W-1:0] diff;
                            diff=mins[j]^maxs[j];sh=0;
                            for(integer k=0;k<KEY_W;k=k+1)if(diff[k])sh=(k>2)?k-2:0;
                            child_shift[j]<=sh;
                        end
                    end
                    offsets[0]<=base_q;
                    for(integer j=1;j<8;j=j+1)begin
                        offsets[j]<=base_q;
                        // Fixed-size parallel prefix expression; no RAM-sized combinational scan.
                        begin : prefix_sum
                            logic [31:0] acc;
                            acc=base_q;
                            for(integer k=0;k<8;k=k+1)if(k<j)acc=acc+counts[k];
                            offsets[j]<=acc;
                        end
                    end
                    state_q<=SCATTER_REQ;
                end
                SCATTER_REQ:if(local_active_q||rd_ready_i)begin
                    if(local_active_q)begin local_index_q<=base_q-local_base_q;local_left_q<=count_q;end
                    state_q<=SCATTER_DATA;
                end
                SCATTER_DATA:if(read_fire)begin
                    if(PRECOUNT_CHILDREN)begin
                        child_counts[child_slot]<=child_counts[child_slot]+1;
                        if(read_key<child_mins[child_slot])child_mins[child_slot]<=read_key;
                        if(read_key>child_maxs[child_slot])child_maxs[child_slot]<=read_key;
                    end
                    writes[bucket]<=writes[bucket]+1;
                    if(stream_last)state_q<=WRITE_FENCE;
                end
                WRITE_FENCE:if(local_active_q||!wr_busy_i)begin push_q<=7;state_q<=PUSH;end
                PUSH:begin
                    if(counts[push_q]!=0)begin
                        if(sp_q==STACK_DEPTH)begin error_o<=1;state_q<=FAIL_DRAIN;end
                        else begin
                            stack_base[sp_q]<=offsets[push_q];stack_count[sp_q]<=counts[push_q];
                            stack_bank[sp_q]<=!bank_q;stack_min[sp_q]<=mins[push_q];stack_max[sp_q]<=maxs[push_q];
                            if(PRECOUNT_CHILDREN)for(integer j=0;j<8;j=j+1)begin
                                saved_counts[32'(sp_q)*8+j]<=child_counts[32'(push_q)*8+j];
                                saved_mins[32'(sp_q)*8+j]<=child_mins[32'(push_q)*8+j];
                                saved_maxs[32'(sp_q)*8+j]<=child_maxs[32'(push_q)*8+j];
                            end
                            sp_q<=sp_q+1'b1;
                        end
                    end
                    if(!(counts[push_q]!=0&&sp_q==STACK_DEPTH))begin
                        if(push_q==0)state_q<=POP;else push_q<=push_q-1'b1;
                    end
                end
                POP:begin
                    if(local_active_q&&sp_q==local_exit_sp_q)begin local_active_q<=0;local_left_q<=0;end
                    if(sp_q==0)begin state_q<=IDLE;done_o<=1;end
                    else begin
                        base_q<=stack_base[sp_q-1'b1];count_q<=stack_count[sp_q-1'b1];
                        bank_q<=stack_bank[sp_q-1'b1];min_q<=stack_min[sp_q-1'b1];max_q<=stack_max[sp_q-1'b1];
                        if(PRECOUNT_CHILDREN)begin
                            histogram_ready_q<=1;
                            for(integer j=0;j<8;j=j+1)begin
                                counts[j]<=saved_counts[(32'(sp_q)-1)*8+j];
                                mins[j]<=saved_mins[(32'(sp_q)-1)*8+j];
                                maxs[j]<=saved_maxs[(32'(sp_q)-1)*8+j];
                            end
                        end
                        sp_q<=sp_q-1'b1;state_q<=VISIT;
                    end
                end
                LEAF_REQ:if(local_active_q||rd_ready_i)begin
                    if(local_active_q)begin local_index_q<=base_q-local_base_q;local_left_q<=count_q;end
                    state_q<=LEAF_DATA;
                end
                LEAF_DATA:if(read_fire)begin
                    leaf_mem[leaf_write_bank_q][leaf_pos_q]<=stream_data[KEY_W-1:0];
                    if(leaf_pos_q==CAPACITY-1||stream_last)begin
                        leaf_full_q[leaf_write_bank_q]<=1;leaf_count_q[leaf_write_bank_q]<=leaf_pos_q+1'b1;
                        leaf_write_bank_q<=!leaf_write_bank_q;leaf_pos_q<=0;
                    end
                    else leaf_pos_q<=leaf_pos_q+1'b1;
                    if(stream_last)state_q<=POP;
                end
                FAIL_DRAIN:if(!rd_busy_i&&!wr_busy_i&&!(|leaf_full_q))begin state_q<=IDLE;done_o<=1;end
                default:state_q<=IDLE;
            endcase
            // Keep accepting/closing the input on error; don't strand prepass
            // P responses. Once collection closes, drain outstanding DMA only.
            if(mem_error_i&&state_q!=IDLE)begin
                error_o<=1;
                if(state_q!=COLLECT&&state_q!=FAIL_DRAIN)state_q<=FAIL_DRAIN;
            end
        end
    end
`ifndef SYNTHESIS
    initial begin assert(KEY_W<=128);assert(CAPACITY>=2);end
    initial assert(LOCAL_RECORDS==0||LOCAL_RECORDS>=CAPACITY);
    initial assert(!PRECOUNT_CHILDREN||LOCAL_RECORDS==0);
    assert property(@(posedge clk_i) disable iff(!rst_ni)
        local_active_q&&read_fire |-> local_index_q<LOCAL_RECORDS);
    assert property(@(posedge clk_i) disable iff(!rst_ni) m_valid_o&&!m_ready_i&&!mem_error_i
        |=>mem_error_i||$stable({m_valid_o,m_depth_o,m_gid_o,m_seq_o,m_group_o,m_first_o,m_last_o}));
`endif
endmodule
