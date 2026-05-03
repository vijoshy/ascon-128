module permutation_12(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [63:0] s0, s1, s2, s3, s4,
    output reg  [63:0] s0_out, s1_out, s2_out, s3_out, s4_out,
    output reg         done
);

    localparam [7:0] RC [0:11] = '{
        8'hf0, 8'he1, 8'hd2, 8'hc3,
        8'hb4, 8'ha5, 8'h96, 8'h87,
        8'h78, 8'h69, 8'h5a, 8'h4b
    };

    reg [63:0] x0, x1, x2, x3, x4;
    reg [3:0]  round;
    reg        active;

    wire [63:0] x2_next = x2 ^ {56'd0, RC[round]};

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            x0     <= 64'd0;
            x1     <= 64'd0;
            x2     <= 64'd0;
            x3     <= 64'd0;
            x4     <= 64'd0;
            round  <= 4'd0;
            active <= 1'b0;
            done   <= 1'b0;
            s0_out <= 64'd0;
            s1_out <= 64'd0;
            s2_out <= 64'd0;
            s3_out <= 64'd0;
            s4_out <= 64'd0;
        end
        else begin
            done <= 1'b0;

            if (start && !active) begin
                x0     <= s0;
                x1     <= s1;
                x2     <= s2;
                x3     <= s3;
                x4     <= s4;
                round  <= 4'd0;
                active <= 1'b1;
            end
            else if (active) begin
                x2    <= x2_next;
                round <= round + 4'd1;

                //have to add p_s and p_l later
                
                if (round == 4'd11) begin
                    s0_out <= x0;       
                    s1_out <= x1;
                    s2_out <= x2_next;  
                    s3_out <= x3;
                    s4_out <= x4;
                    active <= 1'b0;
                    done   <= 1'b1;
                end
            end
        end
    end

endmodule
