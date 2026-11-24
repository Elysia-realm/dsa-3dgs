// Pre-enumeration predicate. The upstream elastic encoder holds a descriptor
// valid and stable until the downstream generator accepts the decision.
// A small/invalid rectangle passes directly. Large rectangles pay bounded
// latency and reuse one shift/add multiplier for all four endpoint products.
module gaussian_bbox_axis0_serial #(
    parameter int SCREEN_W=27, PIXEL_W=16, MIN_EXTENT=128
) (
    input logic clk_i,rst_ni,
    input logic valid_i,keep_i,ready_i,output logic ready_o,valid_o,reject_o,
    input logic [PIXEL_W-1:0] x0_i,y0_i,x1_i,y1_i,
    input logic signed [SCREEN_W-1:0] mean_x_i,mean_y_i,
    input logic [14:0] l00_i,input logic signed [15:0] l10_i,
    input logic signed [5:0] coord_i,factor_i,input logic [12:0] opacity_i
);
    typedef enum logic [3:0] {IDLE, DELTA, MAGNITUDE, ALIGN, CLIP, MULTIPLY,
        SIGN_PRODUCT, ADD_AXIS, PICK, SCALE, DONE} phase_t;
    phase_t phase;
    logic large_box, eligible, upper_q, y_q, negative_q, product_negative_q;
    logic [PIXEL_W-1:0] endpoint;
    logic signed [SCREEN_W-1:0] center;
    logic signed [28:0] displacement_q;
    logic [30:0] magnitude_q;
    logic [5:0] shifts_q;
    logic guard_q;
    logic [15:0] multiplier_q, factor_mag;
    logic [31:0] multiplicand_q, accumulator_q;
    logic [4:0] bits_q;
    logic signed [31:0] product_q,x_product_q;
    logic signed [32:0] sum_q;
    logic [32:0] distance_q;
    logic signed [7:0] scale_q;
    logic [12:0] threshold;
    logic proven_q;

    // Ordered extents avoid unsigned wraparound on invalid inputs.
    assign large_box=(x1_i>x0_i && y1_i>y0_i &&
                      x1_i-x0_i>=PIXEL_W'(MIN_EXTENT) && y1_i-y0_i>=PIXEL_W'(MIN_EXTENT));
    wire signed [6:0] total_shift=7'($signed(coord_i))+7'($signed(factor_i));
    assign eligible=keep_i&&large_box&&coord_i>=0&&total_shift<=33;
    assign valid_o=valid_i&&(phase==DONE||(phase==IDLE&&!eligible));
    assign ready_o=ready_i&&(phase==DONE||(phase==IDLE&&!eligible));
    assign reject_o=(phase==DONE)&&proven_q;
    assign endpoint=y_q ? ((upper_q ^ l10_i[15]) ? y1_i-1'b1 : y0_i)
                        : (upper_q ? x1_i-1'b1 : x0_i);
    assign center=y_q?mean_y_i:mean_x_i;
    assign factor_mag=y_q?(l10_i[15]?-$unsigned(l10_i):$unsigned(l10_i)):{1'b0,l00_i};
    assign threshold=opacity_i<=512?2703:opacity_i<=1024?2959:opacity_i<=2048?3214:opacity_i<=4096?3413:3637;

    // Only phase is externally visible without a preceding valid transaction.
    always_ff @(posedge clk_i or negedge rst_ni)begin
        if(!rst_ni)phase<=IDLE;
        else case(phase)
            IDLE:if(valid_i&&eligible)phase<=opacity_i==0?DONE:DELTA;
            DELTA:phase<=MAGNITUDE;
            MAGNITUDE:phase<=coord_i==0?CLIP:ALIGN;
            ALIGN:if(shifts_q==1)phase<=CLIP;
            CLIP:phase<=MULTIPLY;
            MULTIPLY:if(bits_q==1||multiplier_q<=1)phase<=SIGN_PRODUCT;
            SIGN_PRODUCT:phase<=ADD_AXIS;
            ADD_AXIS:phase<=y_q?PICK:DELTA;
            PICK:if(!upper_q&&sum_q<=0)phase<=DELTA;
                 else if(upper_q&&sum_q>=0)phase<=DONE;
                 else phase<=SCALE;
            SCALE:if(scale_q==0||(scale_q<0&&distance_q>=threshold))phase<=DONE;
            DONE:if(valid_i&&ready_i)phase<=IDLE;
            default:phase<=IDLE;
        endcase
    end
    always_ff @(posedge clk_i)begin
        case(phase)
            IDLE:if(valid_i&&eligible)begin
                y_q<=0;upper_q<=0;proven_q<=opacity_i==0;
            end
            DELTA:displacement_q<=$signed({1'b0,endpoint,8'd0})-29'($signed(center));
            MAGNITUDE:begin
                negative_q<=displacement_q<0;guard_q<=0;shifts_q<=$unsigned(coord_i);
                magnitude_q<={((displacement_q<0)?-$unsigned(displacement_q):$unsigned(displacement_q)),2'b00};
            end
            ALIGN:begin
                guard_q<=magnitude_q[0];magnitude_q<=magnitude_q>>1;shifts_q<=shifts_q-1'b1;
            end
            CLIP:begin
                if(magnitude_q>=((negative_q?31'd32768:31'd32767)-guard_q))
                    multiplicand_q<=negative_q?32768:32767;
                else multiplicand_q<=magnitude_q+32'(guard_q);
                multiplier_q<=factor_mag;accumulator_q<=0;bits_q<=16;
                product_negative_q<=negative_q^(y_q&&l10_i[15]);
            end
            MULTIPLY:begin
                if(multiplier_q[0])accumulator_q<=accumulator_q+multiplicand_q;
                multiplier_q<=multiplier_q>>1;multiplicand_q<=multiplicand_q<<1;bits_q<=bits_q-1'b1;
            end
            SIGN_PRODUCT:product_q<=product_negative_q?-$signed(accumulator_q):$signed(accumulator_q);
            ADD_AXIS:if(!y_q)begin x_product_q<=product_q;y_q<=1;end
                     else begin sum_q<=33'($signed(x_product_q))+33'($signed(product_q));y_q<=0;end
            PICK:begin
                upper_q<=1;distance_q<=sum_q<0?-$unsigned(sum_q):$unsigned(sum_q);
                scale_q<=8'sd12-8'($signed(total_shift));guard_q<=0;
            end
            SCALE:if(scale_q>0)begin
                guard_q<=distance_q[0];distance_q<=distance_q>>1;scale_q<=scale_q-1'b1;
            end else if(scale_q<0)begin
                // Saturate early once the threshold has already been reached.
                if(distance_q>=threshold)proven_q<=1;
                else begin distance_q<=distance_q<<1;scale_q<=scale_q+1'b1;end
            end else proven_q<=distance_q>=(33'(threshold)-guard_q);
            default: ;
        endcase
    end
endmodule
