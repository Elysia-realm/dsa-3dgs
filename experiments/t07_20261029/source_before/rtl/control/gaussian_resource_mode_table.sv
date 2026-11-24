// Static resource policy for the four epoch-programmable operating modes.
// Counts only enable/clock-gate already instantiated physical lanes; changing
// mode never changes the physical resource or SRAM capacity ceiling.
module gaussian_resource_mode_table #(
    parameter int unsigned GROUP_LANES=4,
    parameter int unsigned PROJECTION_LANES=4,
    parameter int unsigned SH_LANES=4,
    parameter int unsigned RASTER_LANES=4,
    parameter int unsigned GROUP_COUNT_W=GROUP_LANES<1?1:$clog2(GROUP_LANES+1),
    parameter int unsigned PROJECTION_COUNT_W=PROJECTION_LANES<1?1:$clog2(PROJECTION_LANES+1),
    parameter int unsigned SH_COUNT_W=SH_LANES<1?1:$clog2(SH_LANES+1),
    parameter int unsigned RASTER_COUNT_W=RASTER_LANES<1?1:$clog2(RASTER_LANES+1)
) (
    input  logic [1:0] active_mode_i,
    output logic [GROUP_COUNT_W-1:0] group_active_lanes_o,
    output logic [PROJECTION_COUNT_W-1:0] projection_active_lanes_o,
    output logic [SH_COUNT_W-1:0] sh_active_lanes_o,
    output logic [RASTER_COUNT_W-1:0] raster_active_lanes_o,
    output logic [2:0] group_weight_o,
    output logic [2:0] projection_weight_o,
    output logic [2:0] raster_weight_o,
    output logic [1:0] shared_math_owner_o,
    output logic aggressive_clock_gate_o
);
    localparam logic [1:0] MODE_G=2'd0,MODE_P=2'd1,MODE_R=2'd2,MODE_E=2'd3;
    localparam int unsigned GROUP_HALF=(GROUP_LANES+1)/2;
    localparam int unsigned PROJECTION_HALF=(PROJECTION_LANES+1)/2;
    localparam int unsigned SH_HALF=(SH_LANES+1)/2;
    localparam int unsigned RASTER_HALF=(RASTER_LANES+1)/2;
    // Convert elaboration-time integer parameters once at the declared count
    // width.  Legal configurations retain the same mode policy without
    // relying on implicit 32-bit-to-lane-count truncation in every branch.
    localparam logic [GROUP_COUNT_W-1:0] GROUP_ALL_COUNT=GROUP_COUNT_W'(GROUP_LANES);
    localparam logic [GROUP_COUNT_W-1:0] GROUP_HALF_COUNT=GROUP_COUNT_W'(GROUP_HALF);
    localparam logic [PROJECTION_COUNT_W-1:0] PROJECTION_ALL_COUNT=PROJECTION_COUNT_W'(PROJECTION_LANES);
    localparam logic [PROJECTION_COUNT_W-1:0] PROJECTION_HALF_COUNT=PROJECTION_COUNT_W'(PROJECTION_HALF);
    localparam logic [SH_COUNT_W-1:0] SH_ALL_COUNT=SH_COUNT_W'(SH_LANES);
    localparam logic [SH_COUNT_W-1:0] SH_HALF_COUNT=SH_COUNT_W'(SH_HALF);
    localparam logic [RASTER_COUNT_W-1:0] RASTER_ALL_COUNT=RASTER_COUNT_W'(RASTER_LANES);
    localparam logic [RASTER_COUNT_W-1:0] RASTER_HALF_COUNT=RASTER_COUNT_W'(RASTER_HALF);
    always_comb begin
      group_active_lanes_o=GROUP_ALL_COUNT;
      projection_active_lanes_o=PROJECTION_ALL_COUNT;
      sh_active_lanes_o=SH_ALL_COUNT;
      raster_active_lanes_o=RASTER_ALL_COUNT;
      group_weight_o=3'd1;projection_weight_o=3'd1;raster_weight_o=3'd1;
      shared_math_owner_o=MODE_G;aggressive_clock_gate_o=1'b0;
      case(active_mode_i)
        MODE_G:begin
          group_active_lanes_o=GROUP_ALL_COUNT;
          projection_active_lanes_o=PROJECTION_HALF_COUNT;
          sh_active_lanes_o=SH_HALF_COUNT;raster_active_lanes_o=RASTER_HALF_COUNT;
          group_weight_o=3'd4;projection_weight_o=3'd2;raster_weight_o=3'd1;
          shared_math_owner_o=MODE_G;
        end
        MODE_P:begin
          group_active_lanes_o=GROUP_HALF_COUNT;
          projection_active_lanes_o=PROJECTION_ALL_COUNT;
          sh_active_lanes_o=SH_ALL_COUNT;raster_active_lanes_o=RASTER_HALF_COUNT;
          group_weight_o=3'd1;projection_weight_o=3'd4;raster_weight_o=3'd2;
          shared_math_owner_o=MODE_P;
        end
        MODE_R:begin
          group_active_lanes_o=GROUP_HALF_COUNT;
          projection_active_lanes_o=PROJECTION_HALF_COUNT;
          sh_active_lanes_o=SH_HALF_COUNT;raster_active_lanes_o=RASTER_ALL_COUNT;
          group_weight_o=3'd1;projection_weight_o=3'd2;raster_weight_o=3'd4;
          shared_math_owner_o=MODE_R;
        end
        MODE_E:begin
          group_active_lanes_o={{(GROUP_COUNT_W-1){1'b0}},1'b1};
          projection_active_lanes_o={{(PROJECTION_COUNT_W-1){1'b0}},1'b1};
          sh_active_lanes_o={{(SH_COUNT_W-1){1'b0}},1'b1};
          raster_active_lanes_o={{(RASTER_COUNT_W-1){1'b0}},1'b1};
          group_weight_o=3'd1;projection_weight_o=3'd1;raster_weight_o=3'd1;
          shared_math_owner_o=MODE_E;aggressive_clock_gate_o=1'b1;
        end
        default:begin end
      endcase
    end
`ifndef SYNTHESIS
    // Illegal elaboration parameters must fail loudly instead of silently
    // truncating an active-lane count and disabling physical hardware.
    initial begin
      assert(GROUP_LANES>=1&&PROJECTION_LANES>=1&&SH_LANES>=1&&RASTER_LANES>=1)
        else $fatal(1,"all physical lane counts must be positive");
      assert(GROUP_COUNT_W>=$clog2(GROUP_LANES+1)&&
        PROJECTION_COUNT_W>=$clog2(PROJECTION_LANES+1)&&
        SH_COUNT_W>=$clog2(SH_LANES+1)&&RASTER_COUNT_W>=$clog2(RASTER_LANES+1))
        else $fatal(1,"active-lane count width cannot represent the physical lane count");
    end
`endif
endmodule
