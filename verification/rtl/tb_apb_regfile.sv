`timescale 1ns/1ps

module tb_apb_regfile;
    logic qsu_enable_o;logic [63:0] qsu_base_o;logic [31:0] qsu_capacity_o;
    logic [31:0] qsu_capabilities_i=0;logic [223:0] qsu_stats_i=0;
    logic pclk_i = 1'b0;
    logic preset_ni = 1'b0;
    logic psel_i = 1'b0;
    logic penable_i = 1'b0;
    logic pwrite_i = 1'b0;
    logic [11:0] paddr_i = '0;
    logic [31:0] pwdata_i = '0;
    logic [3:0] pstrb_i = '0;
    logic [31:0] prdata_o;
    logic pready_o, pslverr_o;
    logic start_pulse_o,continue_pulse_o,more_batches_pulse_o;
    logic soft_reset_pulse_o,status_clear_pulse_o;
    logic [1:0] shadow_mode_o;
    logic mode_shadow_we_o, mode_commit_pulse_o;
    logic [63:0] gaussian_base_o, camera_base_o, output_base_o;
    logic [15:0] image_width_o, image_height_o;
    logic[31:0]gaussian_count_o;
    logic[63:0]attribute_base_o;
    logic[1:0]attribute_format_o;
    logic[1:0]irq_enable_o;
    logic auto_mode_enable_o;
    logic busy_i = 1'b0;
    logic done_i = 1'b0;
    logic error_i=1'b0;logic[31:0]error_status_i='0;logic[1:0]irq_pending_i='0;logic irq_i=1'b0;
    logic [1:0] active_mode_i = 2'b00;
    logic [15:0] epoch_id_i = 16'h0000;
    logic commit_pending_i = 1'b0;
    logic commit_overrun_i = 1'b0;
    logic frame_open_i = 1'b0;
    logic advisor_recommendation_valid_i=1'b0;
    logic[1:0]advisor_recommendation_mode_i=2'b0,advisor_window_winner_i=2'b0;
    logic advisor_request_outstanding_i=1'b0;
    logic[31:0]advisor_window_index_i=0,advisor_window_group_i=0,advisor_window_sort_i=0;
    logic[31:0]advisor_window_projection_i=0,advisor_window_raster_i=0;
    logic[31:0]advisor_window_block_i=0,advisor_window_skip_i=0;
    logic[31:0]shared_pe_group_grant_count_i=11,shared_pe_projection_grant_count_i=12;
    logic[31:0]shared_pe_raster_grant_count_i=13,shared_pe_group_stall_count_i=14;
    logic[31:0]shared_pe_projection_stall_count_i=15,shared_pe_raster_stall_count_i=16;
    logic[31:0]shared_pe_utilization_count_i=36;
    logic[383:0]sort_work_snapshot_i=0;
    logic[31:0]sort_capabilities_i=7,sort_snapshot_sequence_i=8;
    logic sort_snapshot_pulse_o,sort_clear_pulse_o;

    always #5 pclk_i = ~pclk_i;

    apb_regfile dut (.*);

    task automatic tick;
        begin @(posedge pclk_i); #1; end
    endtask

    task automatic apb_write(
        input logic [11:0] address,
        input logic [31:0] data,
        input logic [3:0] strobes
    );
        begin
            paddr_i = address;
            pwdata_i = data;
            pstrb_i = strobes;
            pwrite_i = 1'b1;
            psel_i = 1'b1;
            penable_i = 1'b1;
            tick();
            psel_i = 1'b0;
            penable_i = 1'b0;
            pwrite_i = 1'b0;
            pstrb_i = '0;
        end
    endtask

    task automatic check_read(
        input logic [11:0] address,
        input logic [31:0] expected
    );
        begin
            paddr_i = address;
            pwrite_i = 1'b0;
            psel_i = 1'b1;
            penable_i = 1'b1;
            #1;
            if (!pready_o || pslverr_o || prdata_o !== expected)
                $fatal(1, "APB read mismatch addr=%h got=%h expected=%h",
                       address, prdata_o, expected);
            psel_i = 1'b0;
            penable_i = 1'b0;
            #1;
        end
    endtask

    initial begin
        repeat (2) tick();
        preset_ni = 1'b1;
        tick();

        if (!pready_o || gaussian_base_o !== 64'd0 || camera_base_o !== 64'd0 ||
            output_base_o !== 64'd0 || image_width_o !== 16'd0 ||
            image_height_o !== 16'd0)
            $fatal(1, "APB reset state mismatch");

        check_read(12'h0f0,0);
        apb_write(12'h0f0,1,4'h1);check_read(12'h0f0,1);
        apb_write(12'h0f0,2,4'h2);check_read(12'h0f0,1);
        apb_write(12'h0f0,2,4'h1);check_read(12'h0f0,2);
        apb_write(12'h0f0,0,4'h1);check_read(12'h0f0,0);
        apb_write(12'h010, 32'h89abcdef, 4'hf);
        apb_write(12'h014, 32'h01234567, 4'hf);
        apb_write(12'h018, 32'h76543210, 4'hf);
        apb_write(12'h01c, 32'hfedcba98, 4'hf);
        apb_write(12'h020, 32'h0badcafe, 4'hf);
        apb_write(12'h024, 32'hc001d00d, 4'hf);
        apb_write(12'h028, {16'd1080, 16'd1920}, 4'hf);
        apb_write(12'h038, 32'd123456, 4'hf);
        apb_write(12'h03c,32'h13579bdf,4'hf);apb_write(12'h040,32'h2468ace0,4'hf);
        if (gaussian_base_o !== 64'h01234567_89abcdef ||
            camera_base_o !== 64'hfedcba98_76543210 ||
            output_base_o !== 64'hc001d00d_0badcafe ||
            image_width_o !== 16'd1920 || image_height_o !== 16'd1080 ||
            gaussian_count_o !== 32'd123456||attribute_base_o!==64'h2468ace0_13579bdf)
            $fatal(1, "configuration write mismatch");

        check_read(12'h010, 32'h89abcdef);
        check_read(12'h014, 32'h01234567);
        check_read(12'h028, {16'd1080, 16'd1920});
        check_read(12'h038, 32'd123456);
        check_read(12'h03c,32'h13579bdf);check_read(12'h040,32'h2468ace0);

        apb_write(12'h044,32'h1,4'b0001);
        if(!auto_mode_enable_o)$fatal(1,"automatic mode enable write failed");
        advisor_recommendation_valid_i=1;advisor_recommendation_mode_i=2;
        advisor_window_winner_i=3;advisor_request_outstanding_i=1;commit_pending_i=1;
        check_read(12'h044,32'h000000fb);
        advisor_window_index_i=32'h1001;advisor_window_group_i=32'h2002;
        advisor_window_sort_i=32'h3003;advisor_window_projection_i=32'h4004;
        advisor_window_raster_i=32'h5005;advisor_window_block_i=32'h6006;
        advisor_window_skip_i=32'h7007;
        check_read(12'h048,32'h1001);check_read(12'h04c,32'h2002);
        check_read(12'h050,32'h3003);check_read(12'h054,32'h4004);
        check_read(12'h058,32'h5005);check_read(12'h05c,32'h6006);
        check_read(12'h060,32'h7007);
        check_read(12'h064,32'd11);check_read(12'h068,32'd12);check_read(12'h06c,32'd13);
        check_read(12'h070,32'd14);check_read(12'h074,32'd15);check_read(12'h078,32'd16);
        check_read(12'h07c,32'd36);
        check_read(12'h080,32'd8);check_read(12'h084,32'd7);
        for(integer j=0;j<12;j=j+1)begin
          sort_work_snapshot_i[32*j+:32]=32'(51+j);
          check_read(12'(12'h088+4*j),32'(51+j));
        end
        apb_write(12'h080,32'h3,4'b0010);
        if(sort_snapshot_pulse_o||sort_clear_pulse_o)$fatal(1,"snapshot ignored strobes violated");
        apb_write(12'h080,32'h3,4'b0001);
        if(!sort_snapshot_pulse_o||!sort_clear_pulse_o)$fatal(1,"snapshot control pulse missing");
        tick();if(sort_snapshot_pulse_o||sort_clear_pulse_o)$fatal(1,"snapshot pulses persisted");
        apb_write(12'h088,32'hffff,4'hf);check_read(12'h088,32'd51);
        advisor_recommendation_valid_i=0;advisor_request_outstanding_i=0;commit_pending_i=0;
        apb_write(12'h044,32'h0,4'b0001);
        if(auto_mode_enable_o)$fatal(1,"automatic mode disable write failed");

        // Full-word registers reject partial strobes and retain old data.
        apb_write(12'h010, 32'hffffffff, 4'b0011);
        if (gaussian_base_o !== 64'h01234567_89abcdef)
            $fatal(1, "partial full-word write was not rejected");

        apb_write(12'h008, 32'h00000102, 4'b0001);
        if (shadow_mode_o !== 2'b10 || !mode_shadow_we_o || !mode_commit_pulse_o)
            $fatal(1, "mode write/commit pulse mismatch");
        tick();
        if (mode_shadow_we_o || mode_commit_pulse_o)
            $fatal(1, "mode pulses lasted longer than one cycle");

        apb_write(12'h000, 32'h00000007, 4'b0001);
        if (!start_pulse_o || !soft_reset_pulse_o||!status_clear_pulse_o)
            $fatal(1, "control pulses missing");
        tick();
        if (start_pulse_o || soft_reset_pulse_o||status_clear_pulse_o)
            $fatal(1, "control pulses lasted longer than one cycle");

        apb_write(12'h000,32'h00000019,4'b0001);
        if(!start_pulse_o||!continue_pulse_o||!more_batches_pulse_o)
            $fatal(1,"batch continuation control pulses missing");
        tick();
        if(start_pulse_o||continue_pulse_o||more_batches_pulse_o)
            $fatal(1,"batch continuation pulses lasted longer than one cycle");

        busy_i = 1'b1;
        done_i = 1'b1;
        commit_pending_i = 1'b1;
        commit_overrun_i = 1'b1;
        active_mode_i = 2'b01;
        epoch_id_i = 16'ha55a;
        check_read(12'h004, 32'ha55a000f);
        check_read(12'h008, 32'h00000001);
        frame_open_i=1'b1;check_read(12'h004,32'ha55a004f);frame_open_i=1'b0;

        apb_write(12'h02c,32'h3,4'b0001);
        if(irq_enable_o!==2'b11)$fatal(1,"IRQ enable write mismatch");
        error_i=1;error_status_i=32'h1234aaa5;irq_pending_i=2'b10;irq_i=1;
        check_read(12'h004,32'ha55a003f);
        check_read(12'h02c,32'h3);check_read(12'h030,error_status_i);check_read(12'h034,32'h2);

        paddr_i = 12'h00c;
        psel_i = 1'b1;
        penable_i = 1'b1;
        #1;
        if (!pslverr_o || prdata_o !== 32'd0)
            $fatal(1, "unknown address did not raise PSLVERR");
        psel_i = 1'b0;
        penable_i = 1'b0;

        $display("PASS: tb_apb_regfile");
        $finish;
    end
endmodule
