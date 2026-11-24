// Fixed-pivot coarse depth grouping for Gaussian-wise rendering. Records are
// collected into ordered banks, then drained near-to-far while preserving
// arrival order within each bank. A full bank sets sticky overflow; the frame
// must be replayed through a slower path and must not be committed silently.
module depth_group_buffer #(
    parameter int unsigned GROUPS=4,
    parameter int unsigned CAPACITY=8,
    parameter int unsigned DEPTH_W=27,
    parameter int unsigned GID_W=32,
    parameter int unsigned SEQ_W=32,
    parameter int unsigned PAYLOAD_W=32,
    parameter int unsigned GROUP_W=GROUPS<=2?1:$clog2(GROUPS),
    parameter int unsigned COUNT_W=$clog2(CAPACITY+1)
) (
    input logic clk_i,input logic rst_ni,input logic clear_overflow_i,
    input logic s_valid_i,output logic s_ready_o,
    input logic signed[DEPTH_W-1:0]s_depth_i,
    input logic[GID_W-1:0]s_gid_i,input logic[SEQ_W-1:0]s_seq_i,
    input logic[PAYLOAD_W-1:0]s_payload_i,input logic frame_end_i,
    input logic frame_abort_i,
    input logic signed[DEPTH_W-1:0]cfg_pivot0_i,cfg_pivot1_i,cfg_pivot2_i,
    output logic m_valid_o,input logic m_ready_i,
    output logic signed[DEPTH_W-1:0]m_depth_o,
    output logic[GID_W-1:0]m_gid_o,output logic[SEQ_W-1:0]m_seq_o,
    output logic[PAYLOAD_W-1:0]m_payload_o,output logic[GROUP_W-1:0]m_group_o,
    output logic m_group_first_o,m_group_last_o,
    output logic frame_done_pulse_o,output logic overflow_o,output logic busy_o
);
    typedef enum logic{COLLECT,DRAIN}state_t;state_t state_q;
    logic signed[DEPTH_W-1:0]depth_mem[0:GROUPS-1][0:CAPACITY-1];
    logic[GID_W-1:0]gid_mem[0:GROUPS-1][0:CAPACITY-1];
    logic[SEQ_W-1:0]seq_mem[0:GROUPS-1][0:CAPACITY-1];
    logic[PAYLOAD_W-1:0]payload_mem[0:GROUPS-1][0:CAPACITY-1];
    logic[COUNT_W-1:0]count_q[0:GROUPS-1];
    logic[GROUP_W-1:0]write_group,read_group_q;
    logic[COUNT_W-1:0]read_index_q;
    logic accept,emit,last_record,last_group;
    integer scan_group_index,update_group_index;logic any_count;

    always_comb begin
        if(s_depth_i<cfg_pivot0_i)write_group=0;
        else if(s_depth_i<cfg_pivot1_i)write_group=1;
        else if(s_depth_i<cfg_pivot2_i)write_group=2;
        else write_group=GROUPS-1;
    end
    assign s_ready_o=state_q==COLLECT;
    assign accept=s_valid_i&&s_ready_o;
    assign m_valid_o=state_q==DRAIN&&count_q[read_group_q]!=0;
    assign m_depth_o=depth_mem[read_group_q][read_index_q];
    assign m_gid_o=gid_mem[read_group_q][read_index_q];
    assign m_seq_o=seq_mem[read_group_q][read_index_q];
    assign m_payload_o=payload_mem[read_group_q][read_index_q];
    assign m_group_o=read_group_q;
    assign m_group_first_o=read_index_q==0;
    assign m_group_last_o=read_index_q+1==count_q[read_group_q];
    assign emit=m_valid_o&&m_ready_i;
    assign last_record=m_group_last_o;
    assign last_group=read_group_q==GROUPS-1;
    always_comb begin
      any_count=1'b0;
      for(scan_group_index=0;scan_group_index<GROUPS;scan_group_index=scan_group_index+1)
        any_count=any_count||(count_q[scan_group_index]!=0);
    end
    assign busy_o=state_q!=COLLECT||any_count;

    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        state_q<=COLLECT;read_group_q<='0;read_index_q<='0;overflow_o<=0;
        frame_done_pulse_o<=0;
        for(update_group_index=0;update_group_index<GROUPS;update_group_index=update_group_index+1)count_q[update_group_index]<='0;
      end else begin
        frame_done_pulse_o<=0;
        if(clear_overflow_i)overflow_o<=0;
        if(state_q==COLLECT)begin
          if(accept)begin
            if(count_q[write_group]<CAPACITY)begin
              depth_mem[write_group][count_q[write_group]]<=s_depth_i;
              gid_mem[write_group][count_q[write_group]]<=s_gid_i;
              seq_mem[write_group][count_q[write_group]]<=s_seq_i;
              payload_mem[write_group][count_q[write_group]]<=s_payload_i;
              count_q[write_group]<=count_q[write_group]+1'b1;
            end else overflow_o<=1'b1;
          end
          if(frame_end_i||frame_abort_i)begin state_q<=DRAIN;read_group_q<='0;read_index_q<='0;end
        end else begin
          if(count_q[read_group_q]==0)begin
            if(last_group)begin
              state_q<=COLLECT;frame_done_pulse_o<=1;
               for(update_group_index=0;update_group_index<GROUPS;update_group_index=update_group_index+1)count_q[update_group_index]<='0;
            end else begin read_group_q<=read_group_q+1'b1;read_index_q<='0;end
          end else if(emit)begin
            if(last_record)begin
              if(last_group)begin
                state_q<=COLLECT;frame_done_pulse_o<=1;
                 for(update_group_index=0;update_group_index<GROUPS;update_group_index=update_group_index+1)count_q[update_group_index]<='0;
              end else begin read_group_q<=read_group_q+1'b1;read_index_q<='0;end
            end else read_index_q<=read_index_q+1'b1;
          end
        end
      end
    end
endmodule
