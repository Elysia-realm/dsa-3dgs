// Epoch-stable dynamic lane scheduler. Raw Gaussian packets are distributed
// round-robin across the enabled prefix of lanes. Block-task arbitration locks
// to one lane until that Gaussian's last block. A later ordered-retire stage
// must also enforce global depth sequence before blending. Configuration may
// change only while all lanes are idle.
module projection_lane_scheduler #(
    parameter int unsigned LANES   = 4,
    parameter int unsigned INPUT_W = 256,
    parameter int unsigned TASK_W  = 384,
    parameter bit ENABLE_OPERAND_ISOLATION = 1'b0,
    parameter int unsigned COUNT_W = $clog2(LANES+1),
    parameter int unsigned INDEX_W = LANES <= 2 ? 1 : $clog2(LANES)
) (
    input  logic                            clk_i,
    input  logic                            rst_ni,
    input  logic [COUNT_W-1:0]              cfg_active_lanes_i,

    input  logic                            s_valid_i,
    output logic                            s_ready_o,
    input  logic [INPUT_W-1:0]              s_data_i,
    output logic [LANES-1:0]                lane_s_valid_o,
    input  logic [LANES-1:0]                lane_s_ready_i,
    output logic [LANES-1:0][INPUT_W-1:0]   lane_s_data_o,

    input  logic [LANES-1:0]                lane_task_valid_i,
    output logic [LANES-1:0]                lane_task_ready_o,
    input  logic [LANES-1:0][TASK_W-1:0]    lane_task_data_i,
    input  logic [LANES-1:0]                lane_task_first_i,
    input  logic [LANES-1:0]                lane_task_last_i,
    input  logic [LANES-1:0]                lane_culled_pulse_i,
    input  logic [LANES-1:0]                lane_idle_i,

    output logic                            m_valid_o,
    input  logic                            m_ready_i,
    output logic [TASK_W-1:0]               m_data_o,
    output logic                            m_first_o,
    output logic                            m_last_o,
    output logic                            culled_pulse_o,
    output logic [LANES-1:0]                active_mask_o,
    output logic                            all_idle_o
);
    logic [INDEX_W-1:0] dispatch_index_q,arbiter_index_q,selected_task_index;
    logic arbiter_locked_q,task_found;
    logic [COUNT_W-1:0] active_count;
    logic input_accept,task_accept;
    integer lane_index,offset,candidate;

    always_comb begin
        if(cfg_active_lanes_i==0)active_count={{(COUNT_W-1){1'b0}},1'b1};
        else if(cfg_active_lanes_i>LANES)active_count=LANES;
        else active_count=cfg_active_lanes_i;
        for(lane_index=0;lane_index<LANES;lane_index=lane_index+1)begin
            active_mask_o[lane_index]=lane_index<active_count;
            lane_s_valid_o[lane_index]=1'b0;
            lane_s_data_o[lane_index]=ENABLE_OPERAND_ISOLATION?'0:s_data_i;
        end
        lane_s_valid_o[dispatch_index_q]=s_valid_i&&active_mask_o[dispatch_index_q];
        lane_s_data_o[dispatch_index_q]=s_data_i;
        s_ready_o=active_mask_o[dispatch_index_q]&&lane_s_ready_i[dispatch_index_q];
    end
    assign input_accept=s_valid_i&&s_ready_o;

    always_comb begin
        selected_task_index=arbiter_index_q;
        task_found=arbiter_locked_q&&lane_task_valid_i[arbiter_index_q];
        if(!arbiter_locked_q)begin
            task_found=1'b0;
            for(offset=0;offset<LANES;offset=offset+1)begin
                candidate=arbiter_index_q+offset;
                if(candidate>=LANES)candidate=candidate-LANES;
                if(!task_found&&active_mask_o[candidate]&&lane_task_valid_i[candidate])begin
                    selected_task_index=candidate[INDEX_W-1:0];task_found=1'b1;
                end
            end
        end
        lane_task_ready_o='0;
        m_valid_o=task_found;
        m_data_o=lane_task_data_i[selected_task_index];
        m_first_o=lane_task_first_i[selected_task_index];
        m_last_o=lane_task_last_i[selected_task_index];
        if(task_found)lane_task_ready_o[selected_task_index]=m_ready_i;
    end
    assign task_accept=m_valid_o&&m_ready_i;
    assign culled_pulse_o=|(lane_culled_pulse_i&active_mask_o);
    assign all_idle_o=&(lane_idle_i|~active_mask_o);

    always_ff @(posedge clk_i or negedge rst_ni)begin
        if(!rst_ni)begin
            dispatch_index_q<='0;arbiter_index_q<='0;arbiter_locked_q<=1'b0;
        end else begin
            if(input_accept)begin
                if(dispatch_index_q+1>=active_count)dispatch_index_q<='0;
                else dispatch_index_q<=dispatch_index_q+1'b1;
            end else if(dispatch_index_q>=active_count)dispatch_index_q<='0;
            if(task_accept)begin
                if(m_last_o)begin
                    arbiter_locked_q<=1'b0;
                    if(selected_task_index==LANES-1)arbiter_index_q<='0;
                    else arbiter_index_q<=selected_task_index+1'b1;
                end else begin
                    arbiter_locked_q<=1'b1;arbiter_index_q<=selected_task_index;
                end
            end
        end
    end

`ifndef SYNTHESIS
    assert property(@(posedge clk_i)disable iff(!rst_ni)
      $changed(cfg_active_lanes_i)|->$past(all_idle_o));
    assert property(@(posedge clk_i)disable iff(!rst_ni)
      arbiter_locked_q|->selected_task_index==arbiter_index_q);
`endif
endmodule
