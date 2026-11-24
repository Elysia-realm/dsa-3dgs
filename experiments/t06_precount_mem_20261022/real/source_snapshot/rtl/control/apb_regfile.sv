// Minimal APB4-compatible control/status register file. Configuration writes
// target shadow registers; mode becomes active only through cfg_epoch_ctrl.
module apb_regfile #(
    parameter int unsigned ADDR_W = 12,
    parameter int unsigned MODE_W = 2
) (
    input  logic                 pclk_i,
    input  logic                 preset_ni,
    input  logic                 psel_i,
    input  logic                 penable_i,
    input  logic                 pwrite_i,
    input  logic [ADDR_W-1:0]    paddr_i,
    input  logic [31:0]          pwdata_i,
    input  logic [3:0]           pstrb_i,
    output logic [31:0]          prdata_o,
    output logic                 pready_o,
    output logic                 pslverr_o,
    output logic                 start_pulse_o,
    output logic                 continue_pulse_o,
    output logic                 more_batches_pulse_o,
    output logic                 soft_reset_pulse_o,
    output logic                 status_clear_pulse_o,
    output logic [MODE_W-1:0]    shadow_mode_o,
    output logic                 mode_shadow_we_o,
    output logic                 mode_commit_pulse_o,
    output logic [63:0]          gaussian_base_o,
    output logic [63:0]          camera_base_o,
    output logic [63:0]          output_base_o,
    output logic [63:0]          attribute_base_o,
    output logic [15:0]          image_width_o,
    output logic [15:0]          image_height_o,
    output logic [31:0]          gaussian_count_o,
    output logic [1:0]           irq_enable_o,
    output logic                 auto_mode_enable_o,
    input  logic                 busy_i,
    input  logic                 done_i,
    input  logic                 error_i,
    input  logic [31:0]          error_status_i,
    input  logic [1:0]           irq_pending_i,
    input  logic                 irq_i,
    input  logic [MODE_W-1:0]    active_mode_i,
    input  logic [15:0]          epoch_id_i,
    input  logic                 commit_pending_i,
    input  logic                 commit_overrun_i,
    input  logic                 frame_open_i,
    input  logic                 advisor_recommendation_valid_i,
    input  logic [MODE_W-1:0]    advisor_recommendation_mode_i,
    input  logic [MODE_W-1:0]    advisor_window_winner_i,
    input  logic                 advisor_request_outstanding_i,
    input  logic [31:0]          advisor_window_index_i,
    input  logic [31:0]          advisor_window_group_i,
    input  logic [31:0]          advisor_window_sort_i,
    input  logic [31:0]          advisor_window_projection_i,
    input  logic [31:0]          advisor_window_raster_i,
    input  logic [31:0]          advisor_window_block_i,
    input  logic [31:0]          advisor_window_skip_i,
    input  logic [31:0]          shared_pe_group_grant_count_i,
    input  logic [31:0]          shared_pe_projection_grant_count_i,
    input  logic [31:0]          shared_pe_raster_grant_count_i,
    input  logic [31:0]          shared_pe_group_stall_count_i,
    input  logic [31:0]          shared_pe_projection_stall_count_i,
    input  logic [31:0]          shared_pe_raster_stall_count_i,
    input  logic [31:0]          shared_pe_utilization_count_i,
    input logic[383:0]sort_work_snapshot_i,
    input logic[31:0]sort_capabilities_i,sort_snapshot_sequence_i,
    output logic sort_snapshot_pulse_o,sort_clear_pulse_o,
    output logic qsu_enable_o,output logic [63:0] qsu_base_o,output logic [31:0] qsu_capacity_o,
    input logic [31:0] qsu_capabilities_i,input logic [223:0] qsu_stats_i
);
    localparam logic [ADDR_W-1:0] A_CONTROL = 12'h000;
    localparam logic [ADDR_W-1:0] A_STATUS = 12'h004;
    localparam logic [ADDR_W-1:0] A_MODE = 12'h008;
    localparam logic [ADDR_W-1:0] A_GAUSS_LO = 12'h010;
    localparam logic [ADDR_W-1:0] A_GAUSS_HI = 12'h014;
    localparam logic [ADDR_W-1:0] A_CAMERA_LO = 12'h018;
    localparam logic [ADDR_W-1:0] A_CAMERA_HI = 12'h01c;
    localparam logic [ADDR_W-1:0] A_OUTPUT_LO = 12'h020;
    localparam logic [ADDR_W-1:0] A_OUTPUT_HI = 12'h024;
    localparam logic [ADDR_W-1:0] A_IMAGE_SIZE = 12'h028;
    localparam logic [ADDR_W-1:0] A_IRQ_ENABLE = 12'h02c;
    localparam logic [ADDR_W-1:0] A_ERROR_STATUS = 12'h030;
    localparam logic [ADDR_W-1:0] A_IRQ_STATUS = 12'h034;
    localparam logic [ADDR_W-1:0] A_GAUSSIAN_COUNT = 12'h038;
    localparam logic [ADDR_W-1:0] A_ATTRIBUTE_LO = 12'h03c;
    localparam logic [ADDR_W-1:0] A_ATTRIBUTE_HI = 12'h040;
    localparam logic [ADDR_W-1:0] A_AUTO_MODE = 12'h044;
    localparam logic [ADDR_W-1:0] A_ADVISOR_WINDOW_INDEX = 12'h048;
    localparam logic [ADDR_W-1:0] A_ADVISOR_GROUP = 12'h04c;
    localparam logic [ADDR_W-1:0] A_ADVISOR_SORT = 12'h050;
    localparam logic [ADDR_W-1:0] A_ADVISOR_PROJECTION = 12'h054;
    localparam logic [ADDR_W-1:0] A_ADVISOR_RASTER = 12'h058;
    localparam logic [ADDR_W-1:0] A_ADVISOR_BLOCK = 12'h05c;
    localparam logic [ADDR_W-1:0] A_ADVISOR_SKIP = 12'h060;
    localparam logic [ADDR_W-1:0] A_SHARED_G_GRANT = 12'h064;
    localparam logic [ADDR_W-1:0] A_SHARED_P_GRANT = 12'h068;
    localparam logic [ADDR_W-1:0] A_SHARED_R_GRANT = 12'h06c;
    localparam logic [ADDR_W-1:0] A_SHARED_G_STALL = 12'h070;
    localparam logic [ADDR_W-1:0] A_SHARED_P_STALL = 12'h074;
    localparam logic [ADDR_W-1:0] A_SHARED_R_STALL = 12'h078;
    localparam logic [ADDR_W-1:0] A_SHARED_UTIL = 12'h07c;
    localparam logic [ADDR_W-1:0] A_SORT_SNAPSHOT = 12'h080;
    localparam logic [ADDR_W-1:0] A_SORT_CAPS = 12'h084;
    localparam logic [ADDR_W-1:0] A_SORT_WORK0 = 12'h088;
    localparam logic [ADDR_W-1:0] A_SORT_WORK_LAST = 12'h0b4;
    logic sort_work_address;
    wire qsu_address=paddr_i>=12'h0c0&&paddr_i<=12'h0ec&&paddr_i[1:0]==0;
    assign sort_work_address=paddr_i>=A_SORT_WORK0&&paddr_i<=A_SORT_WORK_LAST&&paddr_i[1:0]==0;
    logic transfer;

    assign transfer = psel_i && penable_i;
    assign pready_o = 1'b1;
    // Use explicit comparisons instead of the SystemVerilog "inside" operator.
    // This is equivalent for these scalar addresses and is accepted by Icarus
    // Verilog 12 as well as synthesis tools.
    assign pslverr_o = transfer &&
        (paddr_i != A_CONTROL) && (paddr_i != A_STATUS) &&
        (paddr_i != A_MODE) && (paddr_i != A_GAUSS_LO) &&
        (paddr_i != A_GAUSS_HI) && (paddr_i != A_CAMERA_LO) &&
        (paddr_i != A_CAMERA_HI) && (paddr_i != A_OUTPUT_LO) &&
        (paddr_i != A_OUTPUT_HI) && (paddr_i != A_IMAGE_SIZE) &&
        (paddr_i != A_IRQ_ENABLE) && (paddr_i != A_ERROR_STATUS) &&
        (paddr_i != A_IRQ_STATUS) && (paddr_i != A_GAUSSIAN_COUNT) &&
        (paddr_i != A_ATTRIBUTE_LO) && (paddr_i != A_ATTRIBUTE_HI) &&
        (paddr_i != A_AUTO_MODE) && (paddr_i != A_ADVISOR_WINDOW_INDEX) &&
        (paddr_i != A_ADVISOR_GROUP) && (paddr_i != A_ADVISOR_SORT) &&
        (paddr_i != A_ADVISOR_PROJECTION) && (paddr_i != A_ADVISOR_RASTER) &&
        (paddr_i != A_ADVISOR_BLOCK) && (paddr_i != A_ADVISOR_SKIP) &&
        (paddr_i != A_SHARED_G_GRANT) && (paddr_i != A_SHARED_P_GRANT) &&
        (paddr_i != A_SHARED_R_GRANT) && (paddr_i != A_SHARED_G_STALL) &&
        (paddr_i != A_SHARED_P_STALL) && (paddr_i != A_SHARED_R_STALL) &&
        (paddr_i != A_SHARED_UTIL) && (paddr_i != A_SORT_SNAPSHOT) &&
        (paddr_i != A_SORT_CAPS) && !sort_work_address && !qsu_address;

    always_comb begin
        prdata_o = 32'h0;
        unique case (paddr_i)
            A_STATUS: prdata_o = {epoch_id_i, 9'h0, frame_open_i, irq_i, error_i,
                                  commit_overrun_i, commit_pending_i, done_i, busy_i};
            A_MODE: prdata_o = {{(32-MODE_W){1'b0}}, active_mode_i};
            A_GAUSS_LO: prdata_o = gaussian_base_o[31:0];
            A_GAUSS_HI: prdata_o = gaussian_base_o[63:32];
            A_CAMERA_LO: prdata_o = camera_base_o[31:0];
            A_CAMERA_HI: prdata_o = camera_base_o[63:32];
            A_OUTPUT_LO: prdata_o = output_base_o[31:0];
            A_OUTPUT_HI: prdata_o = output_base_o[63:32];
            A_IMAGE_SIZE: prdata_o = {image_height_o, image_width_o};
            A_IRQ_ENABLE: prdata_o = {30'h0,irq_enable_o};
            A_ERROR_STATUS: prdata_o = error_status_i;
            A_IRQ_STATUS: prdata_o = {30'h0,irq_pending_i};
            A_GAUSSIAN_COUNT: prdata_o = gaussian_count_o;
            A_ATTRIBUTE_LO: prdata_o = attribute_base_o[31:0];
            A_ATTRIBUTE_HI: prdata_o = attribute_base_o[63:32];
            A_AUTO_MODE: prdata_o = {24'h0,commit_pending_i,advisor_request_outstanding_i,
                                     advisor_window_winner_i,advisor_recommendation_mode_i,
                                     advisor_recommendation_valid_i,auto_mode_enable_o};
            A_ADVISOR_WINDOW_INDEX: prdata_o = advisor_window_index_i;
            A_ADVISOR_GROUP: prdata_o = advisor_window_group_i;
            A_ADVISOR_SORT: prdata_o = advisor_window_sort_i;
            A_ADVISOR_PROJECTION: prdata_o = advisor_window_projection_i;
            A_ADVISOR_RASTER: prdata_o = advisor_window_raster_i;
            A_ADVISOR_BLOCK: prdata_o = advisor_window_block_i;
            A_ADVISOR_SKIP: prdata_o = advisor_window_skip_i;
            A_SHARED_G_GRANT: prdata_o = shared_pe_group_grant_count_i;
            A_SHARED_P_GRANT: prdata_o = shared_pe_projection_grant_count_i;
            A_SHARED_R_GRANT: prdata_o = shared_pe_raster_grant_count_i;
            A_SHARED_G_STALL: prdata_o = shared_pe_group_stall_count_i;
            A_SHARED_P_STALL: prdata_o = shared_pe_projection_stall_count_i;
            A_SHARED_R_STALL: prdata_o = shared_pe_raster_stall_count_i;
            A_SHARED_UTIL: prdata_o = shared_pe_utilization_count_i;
            A_SORT_SNAPSHOT: prdata_o = sort_snapshot_sequence_i;
            A_SORT_CAPS: prdata_o = sort_capabilities_i;
            12'h0c0: prdata_o={31'd0,qsu_enable_o};
            12'h0c4: prdata_o=qsu_base_o[31:0];
            12'h0c8: prdata_o=qsu_base_o[63:32];
            12'h0cc: prdata_o=qsu_capacity_o;
            12'h0d0: prdata_o=qsu_capabilities_i;
            default: if(sort_work_address)
              prdata_o=sort_work_snapshot_i[32*((int'(paddr_i)-int'(A_SORT_WORK0))>>2)+:32];
              else if(paddr_i>=12'h0d4&&paddr_i<=12'h0ec&&paddr_i[1:0]==0)
                prdata_o=qsu_stats_i[32*((int'(paddr_i)-12'h0d4)>>2)+:32];
        endcase
    end

    always_ff @(posedge pclk_i or negedge preset_ni) begin
        if (!preset_ni) begin
            start_pulse_o<=1'b0;continue_pulse_o<=1'b0;more_batches_pulse_o<=1'b0;
            soft_reset_pulse_o <= 1'b0;status_clear_pulse_o<=1'b0;
            mode_shadow_we_o <= 1'b0; mode_commit_pulse_o <= 1'b0;
            shadow_mode_o <= '0; gaussian_base_o <= '0; camera_base_o <= '0;
            output_base_o <= '0; attribute_base_o <= '0;image_width_o <= '0; image_height_o <= '0;
            gaussian_count_o <= '0;irq_enable_o<='0;auto_mode_enable_o<=1'b0;
            sort_snapshot_pulse_o<=0;sort_clear_pulse_o<=0;
            qsu_enable_o<=0;qsu_base_o<=0;qsu_capacity_o<=0;
        end else begin
            start_pulse_o<=1'b0;continue_pulse_o<=1'b0;more_batches_pulse_o<=1'b0;
            soft_reset_pulse_o <= 1'b0;status_clear_pulse_o<=1'b0;
            mode_shadow_we_o <= 1'b0; mode_commit_pulse_o <= 1'b0;
            sort_snapshot_pulse_o<=0;sort_clear_pulse_o<=0;
            if (transfer && pwrite_i && !pslverr_o) begin
                unique case (paddr_i)
                    A_CONTROL: if (pstrb_i[0]) begin
                        start_pulse_o <= pwdata_i[0];
                        continue_pulse_o <= pwdata_i[0] && pwdata_i[3];
                        more_batches_pulse_o <= pwdata_i[0] && pwdata_i[4];
                        soft_reset_pulse_o <= pwdata_i[1];
                        status_clear_pulse_o <= pwdata_i[2];
                    end
                    A_MODE: if (pstrb_i[0]) begin
                        shadow_mode_o <= pwdata_i[MODE_W-1:0];
                        mode_shadow_we_o <= 1'b1;
                        mode_commit_pulse_o <= pwdata_i[8];
                    end
                    A_GAUSS_LO: if (&pstrb_i) gaussian_base_o[31:0] <= pwdata_i;
                    A_GAUSS_HI: if (&pstrb_i) gaussian_base_o[63:32] <= pwdata_i;
                    A_CAMERA_LO: if (&pstrb_i) camera_base_o[31:0] <= pwdata_i;
                    A_CAMERA_HI: if (&pstrb_i) camera_base_o[63:32] <= pwdata_i;
                    A_OUTPUT_LO: if (&pstrb_i) output_base_o[31:0] <= pwdata_i;
                    A_OUTPUT_HI: if (&pstrb_i) output_base_o[63:32] <= pwdata_i;
                    A_IMAGE_SIZE: if (&pstrb_i) begin
                        image_width_o <= pwdata_i[15:0];
                        image_height_o <= pwdata_i[31:16];
                    end
                    A_IRQ_ENABLE: if(pstrb_i[0])irq_enable_o<=pwdata_i[1:0];
                    A_GAUSSIAN_COUNT: if (&pstrb_i) gaussian_count_o <= pwdata_i;
                    A_ATTRIBUTE_LO: if (&pstrb_i) attribute_base_o[31:0] <= pwdata_i;
                    A_ATTRIBUTE_HI: if (&pstrb_i) attribute_base_o[63:32] <= pwdata_i;
                    A_AUTO_MODE: if (pstrb_i[0]) auto_mode_enable_o <= pwdata_i[0];
                    12'h0c0: if(pstrb_i[0])qsu_enable_o<=pwdata_i[0];
                    12'h0c4: if(&pstrb_i)qsu_base_o[31:0]<=pwdata_i;
                    12'h0c8: if(&pstrb_i)qsu_base_o[63:32]<=pwdata_i;
                    12'h0cc: if(&pstrb_i)qsu_capacity_o<=pwdata_i;
                    A_SORT_SNAPSHOT: if(pstrb_i[0])begin
                      sort_snapshot_pulse_o<=pwdata_i[0];sort_clear_pulse_o<=pwdata_i[1];
                    end
                    default: begin end
                endcase
            end
        end
    end
endmodule
