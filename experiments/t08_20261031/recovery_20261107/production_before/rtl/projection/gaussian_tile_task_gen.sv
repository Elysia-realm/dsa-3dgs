// Enumerate the inclusive 8x8-block rectangle of one projected Gaussian. This
// is a Gaussian-internal block walker, not a persistent Gaussian-tile KV/bin
// generator. The descriptor is held until every block has been accepted.
module gaussian_tile_task_gen #(
    parameter int unsigned DESC_W = 128,
    parameter int unsigned TILE_W = 12
) (
    input  logic                    clk_i,
    input  logic                    rst_ni,
    input  logic                    s_valid_i,
    output logic                    s_ready_o,
    input  logic [DESC_W-1:0]       s_desc_i,
    input  logic [TILE_W-1:0]       s_tile_x0_i,
    input  logic [TILE_W-1:0]       s_tile_y0_i,
    input  logic [TILE_W-1:0]       s_tile_x1_i,
    input  logic [TILE_W-1:0]       s_tile_y1_i,
    input  logic                    s_keep_i,
    output logic                    m_valid_o,
    input  logic                    m_ready_i,
    output logic [DESC_W-1:0]       m_desc_o,
    output logic [TILE_W-1:0]       m_tile_x_o,
    output logic [TILE_W-1:0]       m_tile_y_o,
    output logic                    m_first_o,
    output logic                    m_last_o,
    output logic                    m_culled_o,
    output logic                    culled_pulse_o
);
    logic active_q,culled_q;
    logic [DESC_W-1:0] desc_q;
    logic [TILE_W-1:0] x_q,y_q,x0_q,y0_q,x1_q,y1_q;
    logic output_fire;
    assign s_ready_o=!active_q;
    assign m_valid_o=active_q;
    assign m_desc_o=desc_q;
    assign m_tile_x_o=x_q;
    assign m_tile_y_o=y_q;
    assign m_first_o=active_q&&(culled_q||(x_q==x0_q&&y_q==y0_q));
    assign m_last_o=active_q&&(culled_q||(x_q==x1_q&&y_q==y1_q));
    assign m_culled_o=active_q&&culled_q;
    assign output_fire=m_valid_o&&m_ready_i;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni) begin
            active_q<=0;culled_q<=0;desc_q<='0;x_q<='0;y_q<='0;x0_q<='0;y0_q<='0;x1_q<='0;y1_q<='0;
            culled_pulse_o<=0;
        end else begin
            culled_pulse_o<=0;
            if(s_valid_i&&s_ready_o) begin
                if(s_keep_i) begin
                    active_q<=1;culled_q<=0;desc_q<=s_desc_i;x_q<=s_tile_x0_i;y_q<=s_tile_y0_i;
                    x0_q<=s_tile_x0_i;y0_q<=s_tile_y0_i;x1_q<=s_tile_x1_i;y1_q<=s_tile_y1_i;
                end else begin
                    // A cull is a tagged, backpressured one-beat retirement
                    // event. This preserves sequence identity across lanes.
                    active_q<=1;culled_q<=1;desc_q<=s_desc_i;
                    x_q<='0;y_q<='0;x0_q<='0;y0_q<='0;x1_q<='0;y1_q<='0;
                end
            end
            if(output_fire) begin
                if(culled_q)culled_pulse_o<=1;
                if(m_last_o)begin active_q<=0;culled_q<=0;end
                else if(x_q==x1_q) begin x_q<=x0_q;y_q<=y_q+1'b1;end
                else x_q<=x_q+1'b1;
            end
        end
    end
endmodule
