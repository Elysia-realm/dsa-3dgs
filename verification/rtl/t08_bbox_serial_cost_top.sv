// Registered, elastic descriptor source and capture endpoint for local STA.
module t08_bbox_serial_cost_top(
    input logic clk_i,rst_ni,input logic input_valid_i,keep_i,downstream_ready_i,
    input logic [173:0] descriptor_i,output logic input_ready_o,valid_o,reject_o
);
    logic [173:0] launch_q;
    logic keep_q,launch_valid,source_ready,result_valid,result_reject;
    wire capture_ready=!valid_o||downstream_ready_i;
    assign input_ready_o=!launch_valid||source_ready;
    always_ff @(posedge clk_i or negedge rst_ni)begin
        if(!rst_ni)begin launch_valid<=0;valid_o<=0;end
        else begin
            if(input_ready_o)launch_valid<=input_valid_i;
            if(capture_ready)valid_o<=result_valid;
        end
    end
    always_ff @(posedge clk_i)begin
        if(input_ready_o&&input_valid_i)begin launch_q<=descriptor_i;keep_q<=keep_i;end
        if(capture_ready&&result_valid)reject_o<=result_reject;
    end
    gaussian_bbox_axis0_serial predicate(.clk_i(clk_i),.rst_ni(rst_ni),
        .valid_i(launch_valid),.keep_i(keep_q),.ready_i(capture_ready),
        .ready_o(source_ready),.valid_o(result_valid),.reject_o(result_reject),
        .x0_i(launch_q[173:158]),.y0_i(launch_q[157:142]),.x1_i(launch_q[141:126]),.y1_i(launch_q[125:110]),
        .mean_x_i(launch_q[109:83]),.mean_y_i(launch_q[82:56]),.l00_i(launch_q[55:41]),.l10_i(launch_q[40:25]),
        .coord_i(launch_q[24:19]),.factor_i(launch_q[18:13]),.opacity_i(launch_q[12:0])
    );
endmodule
