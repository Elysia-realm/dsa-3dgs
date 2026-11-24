module t08_rounding_cost #(parameter bit ENABLE_Q24=0)(
      input logic clk_i,mode_i,input logic [6*58-1:0] world_i,input logic [3*111-1:0] screen_i,
      input logic [34:0] regularizer_i,output logic [6*41-1:0] world_o,
      output logic [3*35-1:0] screen_o,output logic world_overflow_o,screen_overflow_o);
      localparam CACC_W=58,COV_W=41,COV_SHIFT=20,COV_ACC_W=111,COV2_W=35,COV_TO_Q8_SHIFT=44;
      logic cfg_cov_q24_i;
      logic [6*58-1:0] world_q;
      logic [3*111-1:0] screen_q;
      logic [34:0] reg_q;
      logic [5:0] world_ov;
      logic [2:0] screen_ov;
      always_ff @(posedge clk_i) begin
        cfg_cov_q24_i<=ENABLE_Q24 && mode_i;
        world_q<=world_i;screen_q<=screen_i;reg_q<=regularizer_i;
        world_overflow_o<=|world_ov;screen_overflow_o<=|screen_ov;
      end
    function automatic logic signed [CACC_W-1:0] round_cov_value_q20(
        input logic signed [CACC_W-1:0] value
    );
        logic signed [CACC_W-1:0] magnitude;
        logic signed [CACC_W-1:0] bias;
        begin
            bias={{(CACC_W-COV_SHIFT){1'b0}},1'b1,{(COV_SHIFT-1){1'b0}}};
            if(value>=0)round_cov_value_q20=(value+bias)>>>COV_SHIFT;
            else begin magnitude=-value;round_cov_value_q20=-((magnitude+bias)>>>COV_SHIFT);end
        end
    endfunction
    function automatic logic signed [CACC_W-1:0] round_cov_value_q24(
        input logic signed [CACC_W-1:0] value
    );
        logic signed [CACC_W-1:0] magnitude;
        logic signed [CACC_W-1:0] bias;
        begin
            bias={{(CACC_W-(COV_SHIFT-4)){1'b0}},1'b1,{((COV_SHIFT-4)-1){1'b0}}};
            if(value>=0)round_cov_value_q24=(value+bias)>>>(COV_SHIFT-4);
            else begin magnitude=-value;round_cov_value_q24=-((magnitude+bias)>>>(COV_SHIFT-4));end
        end
    endfunction
    function automatic logic signed [CACC_W-1:0] round_cov_value(
        input logic signed [CACC_W-1:0] value
    );
        round_cov_value = cfg_cov_q24_i ? round_cov_value_q24(value) : round_cov_value_q20(value);
    endfunction
    function automatic logic signed [COV_W-1:0] cov_q40_to_q16(
        input logic signed [CACC_W-1:0] value
    );
        begin cov_q40_to_q16=COV_W'(round_cov_value(value));end
    endfunction
    function automatic logic cov_ov(input logic signed [CACC_W-1:0] value);
        logic signed [CACC_W-1:0] rounded,maxv,minv;
        begin rounded=round_cov_value(value);maxv=({{(CACC_W-1){1'b0}},1'b1}<<<(COV_W-1))-1;
        minv=-({{(CACC_W-1){1'b0}},1'b1}<<<(COV_W-1));cov_ov=rounded>maxv||rounded<minv;end
    endfunction
    function automatic logic signed [COV_ACC_W-1:0] round_cov_to_q8_q20(
        input logic signed [COV_ACC_W-1:0] value
    );
        logic signed [COV_ACC_W-1:0] magnitude;
        begin
            if (value >= 0)
                round_cov_to_q8_q20 = (value
                    + ({{(COV_ACC_W-1){1'b0}},1'b1}
                       <<< (COV_TO_Q8_SHIFT-1))) >>> COV_TO_Q8_SHIFT;
            else begin
                magnitude = -value;
                round_cov_to_q8_q20 = -((magnitude
                    + ({{(COV_ACC_W-1){1'b0}},1'b1}
                       <<< (COV_TO_Q8_SHIFT-1))) >>> COV_TO_Q8_SHIFT);
            end
        end
    endfunction
    function automatic logic signed [COV_ACC_W-1:0] round_cov_to_q8_q24(
        input logic signed [COV_ACC_W-1:0] value
    );
        logic signed [COV_ACC_W-1:0] magnitude;
        begin
            if (value >= 0)
                round_cov_to_q8_q24 = (value
                    + ({{(COV_ACC_W-1){1'b0}},1'b1}
                       <<< ((COV_TO_Q8_SHIFT+4)-1))) >>> (COV_TO_Q8_SHIFT+4);
            else begin
                magnitude = -value;
                round_cov_to_q8_q24 = -((magnitude
                    + ({{(COV_ACC_W-1){1'b0}},1'b1}
                       <<< ((COV_TO_Q8_SHIFT+4)-1))) >>> (COV_TO_Q8_SHIFT+4));
            end
        end
    endfunction
    function automatic logic signed [COV_ACC_W-1:0] round_cov_to_q8(
        input logic signed [COV_ACC_W-1:0] value
    );
        round_cov_to_q8 = cfg_cov_q24_i ? round_cov_to_q8_q24(value) : round_cov_to_q8_q20(value);
    endfunction
    function automatic logic unsigned_overflow(
        input logic signed [COV_ACC_W-1:0] value
    );
        logic signed [COV_ACC_W-1:0] maximum;
        begin
            maximum = ({{(COV_ACC_W-1){1'b0}},1'b1} <<< COV2_W) - 1;
            unsigned_overflow = value < 0 || value > maximum;
        end
    endfunction
    function automatic logic signed_overflow(
        input logic signed [COV_ACC_W-1:0] value
    );
        logic signed [COV_ACC_W-1:0] maximum, minimum;
        begin
            maximum = ({{(COV_ACC_W-1){1'b0}},1'b1} <<< (COV2_W-1)) - 1;
            minimum = -({{(COV_ACC_W-1){1'b0}},1'b1} <<< (COV2_W-1));
            signed_overflow = value > maximum || value < minimum;
        end
    endfunction
    function automatic logic [COV2_W-1:0] saturate_unsigned(
        input logic signed [COV_ACC_W-1:0] value
    );
        begin
            if (value <= 0)
                saturate_unsigned = '0;
            else if (unsigned_overflow(value))
                saturate_unsigned = {COV2_W{1'b1}};
            else
                saturate_unsigned = value[COV2_W-1:0];
        end
    endfunction
    function automatic logic signed [COV2_W-1:0] saturate_signed(
        input logic signed [COV_ACC_W-1:0] value
    );
        begin
            if (!signed_overflow(value))
                saturate_signed = value[COV2_W-1:0];
            else if (value < 0)
                saturate_signed = {1'b1, {(COV2_W-1){1'b0}}};
            else
                saturate_signed = {1'b0, {(COV2_W-1){1'b1}}};
        end
    endfunction
      for(genvar i=0;i<6;i++)begin:g_world
        wire signed [CACC_W-1:0] value=world_q[i*CACC_W+:CACC_W];
        assign world_ov[i]=cov_ov(value);
        always_ff @(posedge clk_i)world_o[i*COV_W+:COV_W]<=cov_q40_to_q16(value);
      end
      for(genvar i=0;i<3;i++)begin:g_screen
        wire signed [COV_ACC_W-1:0] rounded=round_cov_to_q8($signed(screen_q[i*COV_ACC_W+:COV_ACC_W]));
        if(i==1)begin
          assign screen_ov[i]=signed_overflow(rounded);
          always_ff @(posedge clk_i)screen_o[i*COV2_W+:COV2_W]<=saturate_signed(rounded);
        end else begin
          wire signed [COV_ACC_W-1:0] regularized=rounded+$signed({{(COV_ACC_W-COV2_W){1'b0}},reg_q});
          assign screen_ov[i]=unsigned_overflow(regularized);
          always_ff @(posedge clk_i)screen_o[i*COV2_W+:COV2_W]<=saturate_unsigned(regularized);
        end
      end
    endmodule
