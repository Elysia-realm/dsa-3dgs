// Candidate whole-descriptor test before block enumeration. The residual
// l00*dx+l10*dy is monotone on each axis. Endpoints include the pixel
// expander's rounding and saturation; the second squared axis is >= 0.
module gaussian_bbox_axis0_reject #(
    parameter int SCREEN_W=27, PIXEL_W=16
) (
    input logic [PIXEL_W-1:0] x0_i,y0_i,x1_i,y1_i,
    input logic signed [SCREEN_W-1:0] mean_x_i,mean_y_i,
    input logic [14:0] l00_i,input logic signed [15:0] l10_i,
    input logic signed [5:0] coord_i,factor_i,input logic [12:0] opacity_i,
    output logic reject_o
);
    function automatic logic signed [15:0] delta(
        input logic [PIXEL_W-1:0] pixel,input logic signed [SCREEN_W-1:0] center,
        input logic [4:0] shift
    );
        logic signed [63:0] value,rounded;
        begin
            value=(($signed({1'b0, pixel})*64'sd256)-64'($signed(center)))*64'sd4;
            rounded=value;
            if(shift!=0)begin
                rounded=((value<0?-value:value)+(64'sd1<<<(shift-1)))>>>shift;
                if(value<0)rounded=-rounded;
            end
            if(rounded>32767)delta=16'sd32767;
            else if(rounded< -32768)delta=16'sh8000;
            else delta=rounded[15:0];
        end
    endfunction
    logic signed [15:0] xl,xh,yl,yh;
    logic signed [31:0] pxl,pxh,pyl,pyh;
    logic signed [32:0] lo,hi;
    logic signed [6:0] shift_sum;
    logic [12:0] threshold;
    logic [32:0] nearest;
    logic [63:0] rounded;
    integer right_shift;
    always_comb begin
        xl=delta(x0_i,mean_x_i,coord_i[4:0]);
        xh=delta(x1_i-1'b1,mean_x_i,coord_i[4:0]);
        yl=delta(y0_i,mean_y_i,coord_i[4:0]);
        yh=delta(y1_i-1'b1,mean_y_i,coord_i[4:0]);
        pxl=$signed({1'b0,l00_i})*xl;pxh=$signed({1'b0,l00_i})*xh;
        pyl=l10_i*(l10_i<0?yh:yl);pyh=l10_i*(l10_i<0?yl:yh);
        lo=33'($signed(pxl))+33'($signed(pyl));
        hi=33'($signed(pxh))+33'($signed(pyh));
        nearest=(lo>0)?$unsigned(lo):((hi<0)?$unsigned(-hi):33'd0);
        shift_sum=7'($signed(coord_i))+7'($signed(factor_i));
        right_shift=12-int'($signed(shift_sum));
        rounded='0;
        if(right_shift<=0 && right_shift>=-21)rounded=64'(nearest)<<(-right_shift);
        else if(right_shift>0 && right_shift<63)rounded=(64'(nearest)+(64'd1<<(right_shift-1)))>>right_shift;
        threshold=opacity_i<=512?2703:opacity_i<=1024?2959:opacity_i<=2048?3214:opacity_i<=4096?3413:3637;
        // The largest threshold is below either signed Q4.10 saturation limit.
        reject_o=x0_i<x1_i && y0_i<y1_i && coord_i>=0 && shift_sum<=33 &&
                 (opacity_i==0 || rounded>=threshold);
    end
endmodule
