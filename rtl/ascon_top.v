`timescale 1ns / 1ps

module ascon_top (
    input  wire clk,
    input  wire rst,
    
    input  wire start_init,
    input  wire start_ad,
    input  wire start_pt,
    input  wire start_final,
    input  wire is_6_round,
    input  wire en_domain_sep,      
    input  wire en_post_init_xor, // FIXED: Added new control wire
    
    input  wire [127:0] key,
    input  wire [127:0] nonce,
    input  wire [63:0]  data_in, 
    
    output wire [63:0]  ciphertext_out,
    output wire [127:0] tag_out,
    output wire perm_done
);

    wire [63:0] init_s0, init_s1, init_s2, init_s3, init_s4;
    wire [63:0] perm_s0, perm_s1, perm_s2, perm_s3, perm_s4;
    reg  [63:0] mux_s0, mux_s1, mux_s2, mux_s3, mux_s4;
    wire perm_start;

    iv_key_nonce loader (
        .key(key),
        .nonce(nonce),
        .s0(init_s0),
        .s1(init_s1),
        .s2(init_s2),
        .s3(init_s3),
        .s4(init_s4)
    );

    // -------------------------------------------------------
    // FIXED: The Combinational Post-Init Key XOR Routing
    // -------------------------------------------------------
    wire [63:0] s3_routed = en_post_init_xor ? (perm_s3 ^ key[127:64]) : perm_s3;
    wire [63:0] s4_routed = en_post_init_xor ? (perm_s4 ^ key[63:0])   : perm_s4;

    always @(*) begin
        if (start_init) begin
            mux_s0 = init_s0;
            mux_s1 = init_s1;
            mux_s2 = init_s2;
            mux_s3 = init_s3;
            mux_s4 = init_s4;
        end 
        else if (start_ad) begin
            mux_s0 = perm_s0 ^ data_in;
            mux_s1 = perm_s1;
            mux_s2 = perm_s2;
            mux_s3 = s3_routed; // FIXED: Uses safe routed wire
            mux_s4 = s4_routed; // FIXED: Uses safe routed wire
        end
        else if (start_pt) begin
            mux_s0 = perm_s0 ^ data_in;
            mux_s1 = perm_s1;
            mux_s2 = perm_s2;
            mux_s3 = s3_routed; // FIXED: Uses safe routed wire
            
            // Domain separation applies to the safely routed wire
            mux_s4 = en_domain_sep ? (s4_routed ^ 64'd1) : s4_routed;
        end
        else if (start_final) begin
            mux_s0 = perm_s0;
            mux_s1 = perm_s1 ^ key[127:64];
            mux_s2 = perm_s2 ^ key[63:0];
            mux_s3 = s3_routed; // FIXED: Uses safe routed wire
            
            mux_s4 = en_domain_sep ? (s4_routed ^ 64'd1) : s4_routed;
        end
        else begin
            mux_s0 = perm_s0;
            mux_s1 = perm_s1;
            mux_s2 = perm_s2;
            mux_s3 = perm_s3;
            mux_s4 = perm_s4;
        end
    end

    assign perm_start = start_init | start_ad | start_pt | start_final;

    permutation_12 engine (
        .clk(clk),
        .rst(rst),
        .start(perm_start),
        .is_6_round(is_6_round), 
        .s0(mux_s0),
        .s1(mux_s1),
        .s2(mux_s2),
        .s3(mux_s3),
        .s4(mux_s4),
        .s0_out(perm_s0),
        .s1_out(perm_s1),
        .s2_out(perm_s2),
        .s3_out(perm_s3),
        .s4_out(perm_s4),
        .done(perm_done)
    );

    assign ciphertext_out = (start_pt) ? (perm_s0 ^ data_in) : 64'd0; 
    assign tag_out = {perm_s3 ^ key[127:64], perm_s4 ^ key[63:0]};

endmodule
