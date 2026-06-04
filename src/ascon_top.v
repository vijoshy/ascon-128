`timescale 1ns / 1ps

module ascon_top (
    input  wire clk,
    input  wire rst,
    
    // Control Signals from FSM
    input  wire start_init,
    input  wire start_ad,
    input  wire start_pt,
    input  wire start_final,
    input  wire is_6_round,      // 0 for 12-rounds, 1 for 6-rounds
    
    // Data Inputs
    input  wire [127:0] key,
    input  wire [127:0] nonce,
    input  wire [63:0]  data_in, // Used for AD or Plaintext
    
    // Data Outputs
    output wire [63:0]  ciphertext_out,
    output wire [127:0] tag_out,
    output wire         perm_done
);

    // Internal State Wires
    wire [63:0] init_s0, init_s1, init_s2, init_s3, init_s4;
    wire [63:0] perm_s0, perm_s1, perm_s2, perm_s3, perm_s4;
    
    // MUX Output Wires (What actually goes into the permutation engine)
    reg [63:0] mux_s0, mux_s1, mux_s2, mux_s3, mux_s4;
    wire perm_start;

    // -------------------------------------------------------
    // 1. Initial State Loader
    // -------------------------------------------------------
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
    // 2. The Datapath Front-Door MUX
    // -------------------------------------------------------
    always @(*) begin
        if (start_init) begin
            // Phase 1: Load raw IV, Key, Nonce
            mux_s0 = init_s0;
            mux_s1 = init_s1;
            mux_s2 = init_s2;
            mux_s3 = init_s3;
            mux_s4 = init_s4;
        end 
        else if (start_ad) begin
            // Phase
