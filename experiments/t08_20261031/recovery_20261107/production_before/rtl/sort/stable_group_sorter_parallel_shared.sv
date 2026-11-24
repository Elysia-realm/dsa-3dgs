// Bounded odd-even transposition network. Each disjoint-pair batch uses one
// shared G comparator plus up to COMPARE_LANES-1 dedicated local comparators.
// This is a hybrid candidate, not a fully shared PE array or a per-tile sort.
module stable_group_sorter_parallel_shared #(
    parameter int unsigned CAPACITY=8, DEPTH_W=27, GID_W=32, SEQ_W=32,
    parameter int unsigned GROUP_W=2, PAYLOAD_W=32, PE_DATA_W=32,
    parameter int unsigned COMPARE_LANES=4,
    parameter bit ENABLE_SERIAL_FALLBACK=1'b1,
    parameter bit ENABLE_BATCH_FORWARDING=1'b1,
    parameter bit ENABLE_PHASE_FORWARDING=1'b1,
    parameter bit ENABLE_MONOTONIC_FASTPATH=1'b1,
    parameter bit ENABLE_STABLE_RUN_FASTPATH=1'b1,
    parameter int unsigned COUNT_W=$clog2(CAPACITY+1),
    parameter int unsigned LANE_W=$clog2(COMPARE_LANES+1)
) (
    input logic clk_i,rst_ni,clear_overflow_i,
    input logic[LANE_W-1:0]cfg_active_lanes_i,
    input logic s_valid_i,output logic s_ready_o,
    input logic signed[DEPTH_W-1:0]s_depth_i,input logic[GID_W-1:0]s_gid_i,
    input logic[SEQ_W-1:0]s_seq_i,input logic[GROUP_W-1:0]s_group_i,
    input logic[PAYLOAD_W-1:0]s_payload_i,input logic s_group_last_i,
    output logic m_valid_o,input logic m_ready_i,
    output logic signed[DEPTH_W-1:0]m_depth_o,output logic[GID_W-1:0]m_gid_o,
    output logic[SEQ_W-1:0]m_seq_o,output logic[GROUP_W-1:0]m_group_o,
    output logic[PAYLOAD_W-1:0]m_payload_o,output logic m_group_first_o,m_group_last_o,
    output logic overflow_o,busy_o,
    output logic pe_req_valid_o,input logic pe_req_ready_i,
    output logic signed[PE_DATA_W-1:0]pe_lhs_o,pe_rhs_o,
    output logic[GID_W-1:0]pe_lhs_gid_o,pe_rhs_gid_o,
    output logic[SEQ_W-1:0]pe_lhs_seq_o,pe_rhs_seq_o,
    input logic pe_rsp_valid_i,output logic pe_rsp_ready_o,input logic pe_less_i,
    // Wrapping totals, reset with the sorter; system snapshots use modular deltas.
    output logic[31:0]perf_shared_compares_o,perf_local_compares_o,perf_swaps_o,
    output logic[31:0]perf_phases_o,perf_groups_o,perf_fallback_groups_o,
    output logic[31:0]perf_phase_grants_o,perf_phase_stalls_o,
    output logic[31:0]perf_shifts_o,perf_collect_compares_o,perf_fast_groups_o,perf_reverse_groups_o
);
    localparam int unsigned ADDR_W=CAPACITY<=1?1:$clog2(CAPACITY);
    typedef enum logic[3:0]{COLLECT,COMPARE_REQ,COMPARE_WAIT,EMIT,SERIAL_REQ,SERIAL_WAIT,SERIAL_INSERT,TAIL_REQ,TAIL_WAIT}state_t;
    state_t state_q;
    logic signed[DEPTH_W-1:0]depth_q[CAPACITY];
    logic[GID_W-1:0]gid_q[CAPACITY];logic[SEQ_W-1:0]seq_q[CAPACITY];
    logic[PAYLOAD_W-1:0]payload_q[CAPACITY];logic[GROUP_W-1:0]group_q;
    logic[COUNT_W-1:0]count_q,phase_q,base_q,emit_q;
    logic[LANE_W-1:0]lanes_q;
    logic[COMPARE_LANES-1:0]swap_q,valid_pair_q;
    logic[COMPARE_LANES-1:0]batch_swap;
    logic phase_swapped_q,previous_no_swap_q,batch_any_swap;
    logic[ADDR_W-1:0]pair_left[COMPARE_LANES],pair_right[COMPARE_LANES];
    logic[ADDR_W-1:0]base_addr,right_addr,emit_addr,write_addr;
    logic serial_q,in_last_q;
    logic signed[DEPTH_W-1:0]in_depth_q;logic[GID_W-1:0]in_gid_q;
    logic[SEQ_W-1:0]in_seq_q;logic[PAYLOAD_W-1:0]in_payload_q;
    logic[COUNT_W-1:0]search_q,insert_q,request_base,serial_index;
    logic[ADDR_W-1:0]serial_addr,insert_addr,request_left[COMPARE_LANES],request_right[COMPARE_LANES];
    logic batch_chain,phase_chain,serial_chain,serial_request,more_batch,phase_done;
    logic signed[DEPTH_W-1:0]request_l_depth[COMPARE_LANES],request_r_depth[COMPARE_LANES];
    logic[GID_W-1:0]request_l_gid[COMPARE_LANES],request_r_gid[COMPARE_LANES];
    logic[SEQ_W-1:0]request_l_seq[COMPARE_LANES],request_r_seq[COMPARE_LANES];
    logic[ADDR_W-1:0]request_l_source[COMPARE_LANES],request_r_source[COMPARE_LANES];
    logic[31:0]local_issue_count,swap_retire_count;
    logic fast_eligible_q,ascending_q,descending_q,reverse_emit_q,fast_emit_q;
    logic collect_compare_fire,collect_less,ascending_ok,descending_ok;
    logic[ADDR_W-1:0]previous_addr;
    logic[COMPARE_LANES-1:0]local_less;
    // Address metadata only; Gaussian key/payload storage is not duplicated.
    logic[ADDR_W-1:0]run_start_q[CAPACITY];
    logic[ADDR_W-1:0]run_cursor_q,run_end_q,incoming_run_start,next_run_end;
    logic collect_equal;
    logic tail_request,tail_emit_q;
    logic tail_probe_first_q;
    logic[COUNT_W-1:0]tail_lo_q,tail_hi_q,tail_mid,tail_next_lo,tail_next_hi,tail_slot_q;
    integer lane;

    function automatic logic key_less(input logic signed[DEPTH_W-1:0]a,b,
      input logic[GID_W-1:0]ag,bg,input logic[SEQ_W-1:0]asq,bsq);
      key_less=a<b||(a==b&&(ag<bg||(ag==bg&&asq<bsq)));
    endfunction

    assign base_addr=base_q[ADDR_W-1:0];
    assign right_addr=ADDR_W'(base_q+1'b1);
    assign emit_addr=tail_emit_q&&emit_q==tail_slot_q?ADDR_W'(count_q-1'b1):
      reverse_emit_q?(ENABLE_STABLE_RUN_FASTPATH?run_cursor_q:
      ADDR_W'(count_q-1'b1-emit_q)):emit_q[ADDR_W-1:0];
    assign write_addr=count_q[ADDR_W-1:0];
    assign previous_addr=ADDR_W'(count_q-1'b1);
    assign collect_compare_fire=state_q==COLLECT&&s_valid_i&&s_ready_o&&fast_eligible_q&&
      count_q>0&&count_q<COUNT_W'(CAPACITY)&&
      (!ENABLE_STABLE_RUN_FASTPATH||ascending_q||descending_q);
    assign collect_equal=s_depth_i==depth_q[previous_addr]&&s_gid_i==gid_q[previous_addr]&&s_seq_i==seq_q[previous_addr];
    assign ascending_ok=ascending_q&&(!collect_compare_fire||!collect_less);
    assign descending_ok=descending_q&&(!collect_compare_fire||collect_less||
      (ENABLE_STABLE_RUN_FASTPATH&&collect_equal));
    assign incoming_run_start=count_q==0?ADDR_W'(0):
      collect_equal?run_start_q[previous_addr]:write_addr;
    assign next_run_end=ADDR_W'(run_start_q[run_end_q]-1'b1);
    assign s_ready_o=state_q==COLLECT;
    assign busy_o=state_q!=COLLECT||count_q!=0;
    assign m_valid_o=state_q==EMIT&&emit_q<count_q;
    assign m_depth_o=depth_q[emit_addr];assign m_gid_o=gid_q[emit_addr];assign m_seq_o=seq_q[emit_addr];
    assign m_payload_o=payload_q[emit_addr];assign m_group_o=group_q;
    assign m_group_first_o=emit_q==0;assign m_group_last_o=emit_q+1'b1==count_q;
    assign more_batch=int'(base_q)+2*int'(lanes_q)+1<int'(count_q);
    assign phase_done=phase_q+1'b1>=count_q||(!(phase_swapped_q||batch_any_swap)&&previous_no_swap_q);
    assign batch_chain=ENABLE_BATCH_FORWARDING&&state_q==COMPARE_WAIT&&pe_rsp_valid_i&&more_batch;
    assign phase_chain=ENABLE_PHASE_FORWARDING&&state_q==COMPARE_WAIT&&pe_rsp_valid_i&&!more_batch&&!phase_done&&
      int'(!phase_q[0])+1<int'(count_q);
    assign request_base=batch_chain?COUNT_W'(int'(base_q)+2*int'(lanes_q)):
      phase_chain?COUNT_W'(!phase_q[0]):base_q;
    assign serial_chain=state_q==SERIAL_WAIT&&pe_rsp_valid_i&&!pe_less_i&&search_q+1'b1<count_q;
    assign serial_index=serial_chain?search_q+1'b1:search_q;
    assign tail_request=state_q==TAIL_REQ||state_q==TAIL_WAIT;
    assign tail_mid=tail_lo_q+((tail_hi_q-tail_lo_q)>>1);
    assign tail_next_lo=pe_less_i?tail_mid+1'b1:tail_lo_q;
    assign tail_next_hi=pe_less_i?tail_hi_q:tail_mid;
    assign serial_addr=tail_request?(tail_probe_first_q?ADDR_W'(0):ADDR_W'(tail_mid)):
      serial_index[ADDR_W-1:0];assign insert_addr=insert_q[ADDR_W-1:0];
    assign serial_request=state_q==SERIAL_REQ||state_q==SERIAL_WAIT||tail_request;
    assign pe_req_valid_o=(state_q==COMPARE_REQ&&base_q+1'b1<count_q)||batch_chain||phase_chain||state_q==SERIAL_REQ||serial_chain||state_q==TAIL_REQ;
    assign pe_rsp_ready_o=state_q==COMPARE_WAIT||state_q==SERIAL_WAIT||state_q==TAIL_WAIT;
    // Compare right < left: strict equality never swaps, retaining arrival
    // order even when all three key fields are identical.
    assign pe_lhs_o=serial_request?{{(PE_DATA_W-DEPTH_W){in_depth_q[DEPTH_W-1]}},in_depth_q}:
      {{(PE_DATA_W-DEPTH_W){request_r_depth[0][DEPTH_W-1]}},request_r_depth[0]};
    assign pe_rhs_o=serial_request?{{(PE_DATA_W-DEPTH_W){depth_q[serial_addr][DEPTH_W-1]}},depth_q[serial_addr]}:
      {{(PE_DATA_W-DEPTH_W){request_l_depth[0][DEPTH_W-1]}},request_l_depth[0]};
    assign pe_lhs_gid_o=serial_request?in_gid_q:request_r_gid[0];
    assign pe_rhs_gid_o=serial_request?gid_q[serial_addr]:request_l_gid[0];
    assign pe_lhs_seq_o=serial_request?in_seq_q:request_r_seq[0];
    assign pe_rhs_seq_o=serial_request?seq_q[serial_addr]:request_l_seq[0];

    // Only lanes 1..N-1 synthesize local key comparators. Lane zero is always
    // the externally arbitrated shared PE, so G/P competition stays real.
    for(genvar k=0;k<COMPARE_LANES;k=k+1)begin:g_pair
      assign pair_left[k]=ADDR_W'(base_q+COUNT_W'(2*k));
      assign pair_right[k]=ADDR_W'(base_q+COUNT_W'(2*k+1));
      assign request_left[k]=ADDR_W'(request_base+COUNT_W'(2*k));
      assign request_right[k]=ADDR_W'(request_base+COUNT_W'(2*k+1));
      // Post-swap source selection is required at an overlapping phase boundary.
      // No additional key comparator: use the retiring batch's latched decisions.
      always_comb begin
        request_l_source[k]=request_left[k];request_r_source[k]=request_right[k];
        for(integer j=0;j<COMPARE_LANES;j=j+1)if(phase_chain&&batch_swap[j])begin
          if(request_left[k]==pair_left[j])request_l_source[k]=pair_right[j];
          if(request_left[k]==pair_right[j])request_l_source[k]=pair_left[j];
          if(request_right[k]==pair_left[j])request_r_source[k]=pair_right[j];
          if(request_right[k]==pair_right[j])request_r_source[k]=pair_left[j];
        end
      end
      assign request_l_depth[k]=depth_q[request_l_source[k]];assign request_r_depth[k]=depth_q[request_r_source[k]];
      assign request_l_gid[k]=gid_q[request_l_source[k]];assign request_r_gid[k]=gid_q[request_r_source[k]];
      assign request_l_seq[k]=seq_q[request_l_source[k]];assign request_r_seq[k]=seq_q[request_r_source[k]];
      if(k==0)assign batch_swap[k]=valid_pair_q[k]&&pe_less_i;
      else assign batch_swap[k]=valid_pair_q[k]&&swap_q[k];
      if(k==0)assign local_less[k]=1'b0;
      else if(k==1)begin:g_collect_mux
        // One existing local key comparator is time-multiplexed with COLLECT.
        // Strict comparison plus full-key equality identifies equal-key runs.
        // Reverse emission reverses runs, never records inside a run.
        assign local_less[k]=key_less(collect_compare_fire?s_depth_i:request_r_depth[k],
          collect_compare_fire?depth_q[previous_addr]:request_l_depth[k],
          collect_compare_fire?s_gid_i:request_r_gid[k],collect_compare_fire?gid_q[previous_addr]:request_l_gid[k],
          collect_compare_fire?s_seq_i:request_r_seq[k],collect_compare_fire?seq_q[previous_addr]:request_l_seq[k]);
      end else assign local_less[k]=key_less(request_r_depth[k],request_l_depth[k],
        request_r_gid[k],request_l_gid[k],request_r_seq[k],request_l_seq[k]);
    end
    generate if(COMPARE_LANES>1)assign collect_less=local_less[1];
      else assign collect_less=1'b0;endgenerate
    assign batch_any_swap=|batch_swap;

    always_comb begin
      local_issue_count=0;swap_retire_count=0;
      for(integer j=0;j<COMPARE_LANES;j=j+1)begin
        if(j>0&&j<int'(lanes_q)&&int'(request_base)+2*j+1<int'(count_q))local_issue_count=local_issue_count+1;
        if(batch_swap[j])swap_retire_count=swap_retire_count+1;
      end
    end
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        perf_shared_compares_o<=0;perf_local_compares_o<=0;perf_swaps_o<=0;perf_phases_o<=0;
        perf_groups_o<=0;perf_fallback_groups_o<=0;perf_phase_grants_o<=0;perf_phase_stalls_o<=0;
        perf_shifts_o<=0;perf_collect_compares_o<=0;perf_fast_groups_o<=0;perf_reverse_groups_o<=0;
      end else begin
        if(pe_req_valid_o&&pe_req_ready_i)begin
          perf_shared_compares_o<=perf_shared_compares_o+1'b1;
          if(!serial_request)perf_local_compares_o<=perf_local_compares_o+local_issue_count;
        end
        if(state_q==COMPARE_WAIT&&pe_rsp_valid_i)begin
          perf_swaps_o<=perf_swaps_o+swap_retire_count;
          if(!more_batch)perf_phases_o<=perf_phases_o+1'b1;
        end
        // A singleton has a vacuous first phase, no comparisons.
        if(state_q==COMPARE_REQ&&base_q+1'b1>=count_q)perf_phases_o<=perf_phases_o+1'b1;
        if(m_valid_o&&m_ready_i&&m_group_last_o)perf_groups_o<=perf_groups_o+1'b1;
        if(s_valid_i&&s_ready_o&&count_q==0&&ENABLE_SERIAL_FALLBACK&&cfg_active_lanes_i<=1)
          perf_fallback_groups_o<=perf_fallback_groups_o+1'b1;
        if(phase_chain&&pe_req_ready_i)perf_phase_grants_o<=perf_phase_grants_o+1'b1;
        if(phase_chain&&!pe_req_ready_i)perf_phase_stalls_o<=perf_phase_stalls_o+1'b1;
        if(collect_compare_fire)begin
          perf_local_compares_o<=perf_local_compares_o+1'b1;
          perf_collect_compares_o<=perf_collect_compares_o+1'b1;
        end
        if(state_q==SERIAL_INSERT)perf_shifts_o<=perf_shifts_o+32'(count_q-insert_q);
        if(m_valid_o&&m_ready_i&&m_group_last_o)begin
          if(fast_emit_q)perf_fast_groups_o<=perf_fast_groups_o+1'b1;
          if(reverse_emit_q)perf_reverse_groups_o<=perf_reverse_groups_o+1'b1;
        end
      end
    end

    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        state_q<=COLLECT;count_q<='0;phase_q<='0;base_q<='0;emit_q<='0;
        lanes_q<=LANE_W'(1);swap_q<='0;valid_pair_q<='0;group_q<='0;overflow_o<=0;
        phase_swapped_q<=0;previous_no_swap_q<=0;
        serial_q<=0;in_last_q<=0;in_depth_q<='0;in_gid_q<='0;in_seq_q<='0;in_payload_q<='0;
        search_q<='0;insert_q<='0;
        fast_eligible_q<=0;ascending_q<=0;descending_q<=0;reverse_emit_q<=0;fast_emit_q<=0;
        run_cursor_q<=0;run_end_q<=0;
        tail_emit_q<=0;
        tail_probe_first_q<=0;tail_lo_q<=0;tail_hi_q<=0;tail_slot_q<=0;
      end else begin
        if(clear_overflow_i)overflow_o<=0;
        case(state_q)
          COLLECT:if(s_valid_i&&s_ready_o)begin
            // Snapshot the budget at the FIRST accepted record so streaming
            // serial fallback can start before group_last. No duplicate RAM.
            if(count_q==0)begin
              fast_eligible_q<=ENABLE_MONOTONIC_FASTPATH&&COMPARE_LANES>1&&cfg_active_lanes_i>1;
              ascending_q<=1;descending_q<=1;reverse_emit_q<=0;fast_emit_q<=0;
              tail_emit_q<=0;
              serial_q<=ENABLE_SERIAL_FALLBACK&&cfg_active_lanes_i<=1;
              if(cfg_active_lanes_i==0)lanes_q<=LANE_W'(1);
              else if(cfg_active_lanes_i>LANE_W'(COMPARE_LANES))lanes_q<=LANE_W'(COMPARE_LANES);
              else lanes_q<=cfg_active_lanes_i;
            end
            if((count_q==0?ENABLE_SERIAL_FALLBACK&&cfg_active_lanes_i<=1:serial_q))begin
              if(count_q<COUNT_W'(CAPACITY))begin
                in_depth_q<=s_depth_i;in_gid_q<=s_gid_i;in_seq_q<=s_seq_i;in_payload_q<=s_payload_i;
                in_last_q<=s_group_last_i;group_q<=s_group_i;search_q<=0;
                if(count_q==0)begin insert_q<=0;state_q<=SERIAL_INSERT;end
                else state_q<=SERIAL_REQ;
              end else begin
                overflow_o<=1;
                if(s_group_last_i)begin emit_q<=0;state_q<=EMIT;end
              end
            end else begin
            if(collect_compare_fire)begin ascending_q<=ascending_ok;descending_q<=descending_ok;end
            if(count_q<COUNT_W'(CAPACITY))begin
              depth_q[write_addr]<=s_depth_i;gid_q[write_addr]<=s_gid_i;
              seq_q[write_addr]<=s_seq_i;payload_q[write_addr]<=s_payload_i;group_q<=s_group_i;
              count_q<=count_q+1'b1;
              if(ENABLE_STABLE_RUN_FASTPATH)run_start_q[write_addr]<=incoming_run_start;
            end else overflow_o<=1;
            if(s_group_last_i)begin
              phase_q<=0;base_q<=0;emit_q<=0;
              phase_swapped_q<=0;previous_no_swap_q<=0;
              if(count_q==0)begin
                state_q<=EMIT;
                fast_emit_q<=ENABLE_MONOTONIC_FASTPATH&&COMPARE_LANES>1&&cfg_active_lanes_i>1;
              end else if(fast_eligible_q&&(ascending_ok||descending_ok))begin
                state_q<=EMIT;fast_emit_q<=1;reverse_emit_q<=descending_ok&&!ascending_ok;
                if(ENABLE_STABLE_RUN_FASTPATH)begin
                  run_end_q<=ADDR_W'(count_q<COUNT_W'(CAPACITY)?count_q:count_q-1'b1);
                  run_cursor_q<=count_q<COUNT_W'(CAPACITY)?incoming_run_start:run_start_q[previous_addr];
                end
              end else if(ENABLE_STABLE_RUN_FASTPATH&&fast_eligible_q&&descending_q&&
                count_q<COUNT_W'(CAPACITY)&&collect_compare_fire&&!descending_ok)begin
                // Only a retained final record breaks a nonincreasing prefix.
                // Shared PE verifies tail >= prefix maximum before bypassing.
                in_depth_q<=s_depth_i;in_gid_q<=s_gid_i;in_seq_q<=s_seq_i;
                run_end_q<=previous_addr;run_cursor_q<=run_start_q[previous_addr];
                tail_probe_first_q<=1;
                state_q<=TAIL_REQ;
              end else begin state_q<=COMPARE_REQ;fast_emit_q<=0;reverse_emit_q<=0;end
            end
            end
          end
          COMPARE_REQ:begin
            if(base_q+1'b1>=count_q)begin
              if(phase_q+1'b1>=count_q||(!phase_swapped_q&&previous_no_swap_q))state_q<=EMIT;
              else begin
                phase_q<=phase_q+1'b1;base_q<=COUNT_W'(!phase_q[0]);
                previous_no_swap_q<=!phase_swapped_q;phase_swapped_q<=0;
              end
            end else if(pe_req_valid_o&&pe_req_ready_i)begin
              state_q<=COMPARE_WAIT;
            end
          end
          COMPARE_WAIT:if(pe_rsp_valid_i&&pe_rsp_ready_o)begin
            for(lane=0;lane<COMPARE_LANES;lane=lane+1)begin
              if(valid_pair_q[lane]&&(lane==0?pe_less_i:swap_q[lane]))begin
                depth_q[pair_left[lane]]<=depth_q[pair_right[lane]];depth_q[pair_right[lane]]<=depth_q[pair_left[lane]];
                gid_q[pair_left[lane]]<=gid_q[pair_right[lane]];gid_q[pair_right[lane]]<=gid_q[pair_left[lane]];
                seq_q[pair_left[lane]]<=seq_q[pair_right[lane]];seq_q[pair_right[lane]]<=seq_q[pair_left[lane]];
                payload_q[pair_left[lane]]<=payload_q[pair_right[lane]];payload_q[pair_right[lane]]<=payload_q[pair_left[lane]];
              end
            end
            if(int'(base_q)+2*int'(lanes_q)+1<int'(count_q))begin
              base_q<=COUNT_W'(int'(base_q)+2*int'(lanes_q));
              phase_swapped_q<=phase_swapped_q||batch_any_swap;
              state_q<=(batch_chain&&pe_req_ready_i)?COMPARE_WAIT:COMPARE_REQ;
            end else if(phase_q+1'b1>=count_q||(!(phase_swapped_q||batch_any_swap)&&previous_no_swap_q))state_q<=EMIT;
            else begin
              phase_q<=phase_q+1'b1;base_q<=COUNT_W'(!phase_q[0]);
              state_q<=(phase_chain&&pe_req_ready_i)?COMPARE_WAIT:COMPARE_REQ;
              // Two complete opposite-parity phases with no swap prove all
              // adjacent pairs ordered. Never terminate on one phase alone.
              previous_no_swap_q<=!(phase_swapped_q||batch_any_swap);phase_swapped_q<=0;
            end
          end
          SERIAL_REQ:if(pe_req_valid_o&&pe_req_ready_i)state_q<=SERIAL_WAIT;
          TAIL_REQ:if(pe_req_valid_o&&pe_req_ready_i)state_q<=TAIL_WAIT;
          TAIL_WAIT:if(pe_rsp_valid_i&&pe_rsp_ready_o)begin
            if(tail_probe_first_q)begin
              if(!pe_less_i)begin
                state_q<=EMIT;fast_emit_q<=1;reverse_emit_q<=1;tail_emit_q<=1;tail_slot_q<=count_q-1'b1;
              end else begin
                // Nonincreasing prefix: lower-bound the first key <= tail.
                // Equal prefix keys retire BEFORE the later arriving tail.
                tail_probe_first_q<=0;tail_lo_q<=COUNT_W'(1);tail_hi_q<=count_q-1'b1;
                state_q<=TAIL_REQ;
              end
            end else if(tail_next_lo==tail_next_hi)begin
              tail_slot_q<=count_q-1'b1-tail_next_lo;
              state_q<=EMIT;fast_emit_q<=1;reverse_emit_q<=1;tail_emit_q<=1;
            end else begin tail_lo_q<=tail_next_lo;tail_hi_q<=tail_next_hi;state_q<=TAIL_REQ;end
          end
          SERIAL_WAIT:if(pe_rsp_valid_i&&pe_rsp_ready_o)begin
            if(pe_less_i)begin insert_q<=search_q;state_q<=SERIAL_INSERT;end
            else if(search_q+1'b1>=count_q)begin insert_q<=count_q;state_q<=SERIAL_INSERT;end
            else begin search_q<=search_q+1'b1;state_q<=pe_req_ready_i?SERIAL_WAIT:SERIAL_REQ;end
          end
          SERIAL_INSERT:begin
            for(lane=CAPACITY-1;lane>0;lane=lane-1)if(lane>int'(insert_q)&&lane<=int'(count_q))begin
              depth_q[lane]<=depth_q[lane-1];gid_q[lane]<=gid_q[lane-1];seq_q[lane]<=seq_q[lane-1];payload_q[lane]<=payload_q[lane-1];
            end
            depth_q[insert_addr]<=in_depth_q;gid_q[insert_addr]<=in_gid_q;seq_q[insert_addr]<=in_seq_q;payload_q[insert_addr]<=in_payload_q;
            count_q<=count_q+1'b1;
            if(in_last_q)begin emit_q<=0;state_q<=EMIT;end else state_q<=COLLECT;
          end
          EMIT:if(m_valid_o&&m_ready_i)begin
            if(m_group_last_o)begin state_q<=COLLECT;count_q<=0;emit_q<=0;end
            else begin
              emit_q<=emit_q+1'b1;
              if(ENABLE_STABLE_RUN_FASTPATH&&reverse_emit_q&&
                !(tail_emit_q&&emit_q==tail_slot_q))begin
                if(run_cursor_q==run_end_q)begin run_end_q<=next_run_end;run_cursor_q<=run_start_q[next_run_end];end
                else run_cursor_q<=run_cursor_q+1'b1;
              end
            end
          end
          default:state_q<=COLLECT;
        endcase
        // Response writes use OLD batch addresses/flags; forwarded requests
        // sample NEW disjoint addresses, or post-swap sources at a phase boundary.
        if(pe_req_valid_o&&pe_req_ready_i&&!serial_request)begin
          for(lane=0;lane<COMPARE_LANES;lane=lane+1)
            valid_pair_q[lane]<=lane<int'(lanes_q)&&int'(request_base)+2*lane+1<int'(count_q);
          for(lane=1;lane<COMPARE_LANES;lane=lane+1)begin
            if(lane<int'(lanes_q)&&int'(request_base)+2*lane+1<int'(count_q))
              swap_q[lane]<=local_less[lane];
            else swap_q[lane]<=0;
          end
        end
      end
    end
`ifndef SYNTHESIS
    initial begin assert(CAPACITY>=1&&COMPARE_LANES>=1&&PE_DATA_W>=DEPTH_W);end
    assert property(@(posedge clk_i)disable iff(!rst_ni)m_valid_o&&!m_ready_i
      |=>$stable({m_depth_o,m_gid_o,m_seq_o,m_payload_o,m_group_o,m_group_first_o,m_group_last_o}));
`endif
endmodule
