// Conservative opacity-aware support multiplier for alpha_threshold=1/255.
// Output is sigma radius in unsigned Q2.2, rounded upward to quarter-sigma.
// Thresholds are floor(16*exp(radius^2/2)); choosing a radius when opacity is
// above that floor cannot undershoot sqrt(2*ln(opacity/threshold)).
module opacity_radius_bound (
    input  logic [12:0] opacity_q12_i,
    output logic [3:0]  radius_q2_o
);
    always_comb begin
        if      (opacity_q12_i <= 13'd16)  radius_q2_o = 4'd0;
        else if (opacity_q12_i <= 13'd18)  radius_q2_o = 4'd2;
        else if (opacity_q12_i <= 13'd21)  radius_q2_o = 4'd3;
        else if (opacity_q12_i <= 13'd26)  radius_q2_o = 4'd4;
        else if (opacity_q12_i <= 13'd34)  radius_q2_o = 4'd5;
        else if (opacity_q12_i <= 13'd49)  radius_q2_o = 4'd6;
        else if (opacity_q12_i <= 13'd73)  radius_q2_o = 4'd7;
        else if (opacity_q12_i <= 13'd118) radius_q2_o = 4'd8;
        else if (opacity_q12_i <= 13'd201) radius_q2_o = 4'd9;
        else if (opacity_q12_i <= 13'd364) radius_q2_o = 4'd10;
        else if (opacity_q12_i <= 13'd701) radius_q2_o = 4'd11;
        else                               radius_q2_o = 4'd12;
    end
endmodule
