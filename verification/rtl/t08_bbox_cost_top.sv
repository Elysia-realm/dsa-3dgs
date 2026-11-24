// Timing fixture for one whole-box predicate between a launch and capture register.
module t08_bbox_cost_top(
    input logic clk_i,
    input logic [173:0] descriptor_i,
    output logic reject_o
);
    // 64 bbox + 54 mean + 31 factors + 12 shifts + 13 opacity = 174 bits.
    logic [173:0] launch_q;
    logic reject;
    always_ff @(posedge clk_i) begin
        launch_q <= descriptor_i;
        reject_o <= reject;
    end
    gaussian_bbox_axis0_reject predicate(
        .x0_i(launch_q[173:158]),.y0_i(launch_q[157:142]),
        .x1_i(launch_q[141:126]),.y1_i(launch_q[125:110]),
        .mean_x_i(launch_q[109:83]),.mean_y_i(launch_q[82:56]),
        .l00_i(launch_q[55:41]),.l10_i(launch_q[40:25]),
        .coord_i(launch_q[24:19]),.factor_i(launch_q[18:13]),
        .opacity_i(launch_q[12:0]),.reject_o(reject)
    );
endmodule
