module permutation_12 (
    input  clk,
    input  rst,
    input  start,
    input  [63:0] s0, s1, s2, s3, s4,
    output reg [63:0] s0_out, s1_out, s2_out, s3_out, s4_out,
    output reg        done
);

    // round constants for p_C
    reg [7:0] RC [0:11];
    initial begin
        RC[0]  = 8'hf0; RC[1]  = 8'he1;
        RC[2]  = 8'hd2; RC[3]  = 8'hc3;
        RC[4]  = 8'hb4; RC[5]  = 8'ha5;
        RC[6]  = 8'h96; RC[7]  = 8'h87;
        RC[8]  = 8'h78; RC[9]  = 8'h69;
        RC[10] = 8'h5a; RC[11] = 8'h4b;
    end

    reg [63:0] x0, x1, x2, x3, x4;
    reg [3:0]  round;
    reg        active;

    // -------------------------------------------------------
    // p_C: XOR round constant into LSB byte of x2
    // -------------------------------------------------------
    wire [63:0] pc_x2 = x2 ^ {56'd0, RC[round]};

    // -------------------------------------------------------
    // p_S: substitution layer
    // -------------------------------------------------------
    wire [63:0] ps_a0, ps_a1, ps_a2, ps_a3, ps_a4;
    wire [63:0] ps_t0, ps_t1, ps_t2, ps_t3, ps_t4;
    wire [63:0] ps_b0, ps_b1, ps_b2, ps_b3, ps_b4;
    wire [63:0] s_x0,  s_x1,  s_x2,  s_x3,  s_x4;

    // step 1: initial XORs
    assign ps_a0 = x0    ^ x4;
    assign ps_a1 = x1;
    assign ps_a2 = pc_x2 ^ x1;
    assign ps_a3 = x3;
    assign ps_a4 = x4    ^ x3;

    // step 2: AND-NOT terms
    assign ps_t0 = (~ps_a0) & ps_a1;
    assign ps_t1 = (~ps_a1) & ps_a2;
    assign ps_t2 = (~ps_a2) & ps_a3;
    assign ps_t3 = (~ps_a3) & ps_a4;
    assign ps_t4 = (~ps_a4) & ps_a0;

    // step 3: XOR back
    assign ps_b0 = ps_a0 ^ ps_t1;
    assign ps_b1 = ps_a1 ^ ps_t2;
    assign ps_b2 = ps_a2 ^ ps_t3;
    assign ps_b3 = ps_a3 ^ ps_t4;
    assign ps_b4 = ps_a4 ^ ps_t0;

    // step 4: final XORs + invert x2
    assign s_x0 = ps_b0 ^ ps_b4;
    assign s_x1 = ps_b1 ^ ps_b0;
    assign s_x2 = ~ps_b2;
    assign s_x3 = ps_b3 ^ ps_b2;
    assign s_x4 = ps_b4;

    // -------------------------------------------------------
    // p_L: linear diffusion layer
    // rotr(x, n) = (x >> n) | (x << (64-n))
    // -------------------------------------------------------
    wire [63:0] l_x0, l_x1, l_x2, l_x3, l_x4;

    assign l_x0 = s_x0 ^ ((s_x0 >> 19) | (s_x0 << 45))
                        ^ ((s_x0 >> 28) | (s_x0 << 36));

    assign l_x1 = s_x1 ^ ((s_x1 >> 61) | (s_x1 << 3))
                        ^ ((s_x1 >> 39) | (s_x1 << 25));

    assign l_x2 = s_x2 ^ ((s_x2 >> 1)  | (s_x2 << 63))
                        ^ ((s_x2 >> 6)  | (s_x2 << 58));

    assign l_x3 = s_x3 ^ ((s_x3 >> 10) | (s_x3 << 54))
                        ^ ((s_x3 >> 17) | (s_x3 << 47));

    assign l_x4 = s_x4 ^ ((s_x4 >> 7)  | (s_x4 << 57))
                        ^ ((s_x4 >> 41) | (s_x4 << 23));

    // -------------------------------------------------------
    // Sequential: one full round per clock
    // -------------------------------------------------------
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
                x0    <= l_x0;
                x1    <= l_x1;
                x2    <= l_x2;
                x3    <= l_x3;
                x4    <= l_x4;
                round <= round + 4'd1;

                if (round == 4'd11) begin
                    s0_out <= l_x0;
                    s1_out <= l_x1;
                    s2_out <= l_x2;
                    s3_out <= l_x3;
                    s4_out <= l_x4;
                    active <= 1'b0;
                    done   <= 1'b1;
                end
            end
        end
    end

endmodule
