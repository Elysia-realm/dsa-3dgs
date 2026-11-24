// Long-window G/P/R/E mode advisor. It never changes active hardware directly:
// a recommendation is handed to the shadow/epoch commit controller. Hysteresis,
// minimum residence and one-outstanding-request rules prevent mode thrashing.
module gaussian_mode_advisor #(
    parameter int unsigned WINDOW_CYCLES=256,
    parameter int unsigned EVENT_W=32,
    parameter int unsigned HYSTERESIS_WINDOWS=2,
    parameter int unsigned MIN_RESIDENCE_WINDOWS=4,
    parameter int unsigned SCORE_MARGIN=8,
    parameter int unsigned WINDOW_W=WINDOW_CYCLES<=2?1:$clog2(WINDOW_CYCLES),
    parameter int unsigned STREAK_W=HYSTERESIS_WINDOWS<=1?1:$clog2(HYSTERESIS_WINDOWS+1),
    parameter int unsigned RESIDENCE_W=MIN_RESIDENCE_WINDOWS<=1?1:$clog2(MIN_RESIDENCE_WINDOWS+1)
) (
    input logic clk_i,input logic rst_ni,input logic enable_i,input logic sample_enable_i,
    input logic[1:0]active_mode_i,input logic mode_commit_pulse_i,
    input logic group_pressure_i,input logic sort_busy_i,input logic projection_busy_i,
    input logic raster_busy_i,input logic block_candidate_i,input logic block_terminated_skip_i,
    output logic recommendation_valid_o,input logic recommendation_ready_i,
    output logic[1:0]recommendation_mode_o,output logic window_done_pulse_o,
    output logic[1:0]window_winner_o,output logic request_outstanding_o,
    // Atomic snapshot of the most recently completed observation window.
    // Software may read window_index before and after the six counters and
    // retry if it changed, avoiding a torn multi-register sample.
    output logic[31:0]window_index_o,
    output logic[EVENT_W-1:0]window_group_count_o,window_sort_count_o,
    output logic[EVENT_W-1:0]window_projection_count_o,window_raster_count_o,
    output logic[EVENT_W-1:0]window_block_count_o,window_skip_count_o
);
    localparam logic[1:0]MODE_G=2'd0,MODE_P=2'd1,MODE_R=2'd2,MODE_E=2'd3;
    logic[WINDOW_W-1:0]cycle_q;
    logic[EVENT_W-1:0]group_q,sort_q,projection_q,raster_q,block_q,skip_q;
    logic[EVENT_W-1:0]group_n,sort_n,projection_n,raster_n,block_n,skip_n;
    logic[EVENT_W:0]score_g,score_p,score_r,active_score,winner_score;
    logic[1:0]winner,candidate_q;logic[STREAK_W-1:0]streak_q;
    logic[RESIDENCE_W-1:0]residence_q;logic request_q;logic[1:0]request_mode_q;
    logic window_end,energy_condition,margin_ok,residence_ok;
    function automatic logic[EVENT_W-1:0]sat_inc(input logic[EVENT_W-1:0]v,input logic event_i);
      begin sat_inc=event_i&&(&v)==0?v+1'b1:v;end
    endfunction
    assign group_n=sat_inc(group_q,group_pressure_i);assign sort_n=sat_inc(sort_q,sort_busy_i);
    assign projection_n=sat_inc(projection_q,projection_busy_i);assign raster_n=sat_inc(raster_q,raster_busy_i);
    assign block_n=sat_inc(block_q,block_candidate_i);assign skip_n=sat_inc(skip_q,block_terminated_skip_i);
    assign score_g={1'b0,group_n}+{1'b0,sort_n};assign score_p={1'b0,projection_n};
    assign score_r={1'b0,raster_n}+{1'b0,block_n};
    assign energy_condition=(block_n>=8)&&(({1'b0,skip_n}<<2)>=({1'b0,block_n}+({1'b0,block_n}<<1)));
    always_comb begin
      winner=MODE_G;winner_score=score_g;
      if(score_p>winner_score)begin winner=MODE_P;winner_score=score_p;end
      if(score_r>winner_score)begin winner=MODE_R;winner_score=score_r;end
      if(energy_condition)begin winner=MODE_E;winner_score={1'b0,skip_n};end
      case(active_mode_i)
        MODE_G:active_score=score_g;MODE_P:active_score=score_p;MODE_R:active_score=score_r;
        default:active_score={1'b0,skip_n};
      endcase
    end
    assign window_end=cycle_q==WINDOW_CYCLES-1;
    assign margin_ok=winner_score>=active_score+SCORE_MARGIN;
    assign residence_ok=residence_q>=MIN_RESIDENCE_WINDOWS;
    assign recommendation_valid_o=request_q;assign recommendation_mode_o=request_mode_q;
    assign request_outstanding_o=request_q;
    always_ff@(posedge clk_i or negedge rst_ni)begin
      if(!rst_ni)begin
        cycle_q<='0;group_q<='0;sort_q<='0;projection_q<='0;raster_q<='0;block_q<='0;skip_q<='0;
        candidate_q<=MODE_G;streak_q<='0;residence_q<='0;request_q<=0;request_mode_q<=MODE_G;
        window_done_pulse_o<=0;window_winner_o<=MODE_G;
        window_index_o<='0;window_group_count_o<='0;window_sort_count_o<='0;
        window_projection_count_o<='0;window_raster_count_o<='0;
        window_block_count_o<='0;window_skip_count_o<='0;
      end else begin
        window_done_pulse_o<=0;
        if(mode_commit_pulse_i)begin residence_q<='0;request_q<=0;streak_q<='0;end
        if(request_q&&recommendation_ready_i)request_q<=0;
        if(!enable_i)begin
          cycle_q<='0;group_q<='0;sort_q<='0;projection_q<='0;raster_q<='0;block_q<='0;skip_q<='0;
          candidate_q<=active_mode_i;streak_q<='0;residence_q<='0;request_q<=0;
          request_mode_q<=active_mode_i;window_winner_o<=active_mode_i;
        end else if(!sample_enable_i)begin
          // Preserve an outstanding recommendation across idle gaps, but do
          // not let idle cycles satisfy the observation window or residence.
        end else if(window_end)begin
          cycle_q<='0;group_q<='0;sort_q<='0;projection_q<='0;raster_q<='0;block_q<='0;skip_q<='0;
          window_done_pulse_o<=1;window_winner_o<=winner;
          window_index_o<=window_index_o+1'b1;
          window_group_count_o<=group_n;window_sort_count_o<=sort_n;
          window_projection_count_o<=projection_n;window_raster_count_o<=raster_n;
          window_block_count_o<=block_n;window_skip_count_o<=skip_n;
          if(!mode_commit_pulse_i&&residence_q<MIN_RESIDENCE_WINDOWS)residence_q<=residence_q+1'b1;
          if(winner==active_mode_i||!margin_ok)begin candidate_q<=winner;streak_q<='0;end
          else if(winner!=candidate_q)begin candidate_q<=winner;streak_q<=1;end
          else if(streak_q<HYSTERESIS_WINDOWS)streak_q<=streak_q+1'b1;
          if(!request_q&&winner!=active_mode_i&&margin_ok&&residence_ok&&
             winner==candidate_q&&streak_q+1>=HYSTERESIS_WINDOWS)begin
            request_q<=1;request_mode_q<=winner;streak_q<='0;
          end
        end else begin
          cycle_q<=cycle_q+1'b1;group_q<=group_n;sort_q<=sort_n;projection_q<=projection_n;
          raster_q<=raster_n;block_q<=block_n;skip_q<=skip_n;
        end
      end
    end
endmodule
