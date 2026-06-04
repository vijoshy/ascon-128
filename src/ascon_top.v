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
            // Phase 2: Associated Data
            // Absorb AD block into Rate
            mux_s0 = perm_s0 ^ data_in; 
            mux_s1 = perm_s1;
            mux_s2 = perm_s2;
            
            // Phase 1 Post-Permutation Key Injection
            // Mathematically applied exactly as the state loops back
            mux_s3 = perm_s3 ^ key[127:64]; 
            mux_s4 = perm_s4 ^ key[63:0];
        end
        else if (start_pt) begin
            // Phase 3: Plaintext Encryption
            // Absorb Plaintext into Rate (the XOR result is saved back into S0)
            mux_s0 = perm_s0 ^ data_in;
            mux_s1 = perm_s1;
            mux_s2 = perm_s2;
            mux_s3 = perm_s3;
            mux_s4 = perm_s4;
        end
        else if (start_final) begin
            // Phase 4: Finalization
            // Inject Key into the top of the vault BEFORE the final permutation
            mux_s0 = perm_s0;
            mux_s1 = perm_s1 ^ key[127:64];
            mux_s2 = perm_s2 ^ key[63:0];
            mux_s3 = perm_s3;
            mux_s4 = perm_s4;
        end
        else begin
            // Default hold: feed the permutation output right back into itself
            mux_s0 = perm_s0;
            mux_s1 = perm_s1;
            mux_s2 = perm_s2;
            mux_s3 = perm_s3;
            mux_s4 = perm_s4;
        end
    end

    // Trigger permutation engine if any phase starts
    assign perm_start = start_init | start_ad | start_pt | start_final;

    // -------------------------------------------------------
    // 3. The Permutation Engine 
    // -------------------------------------------------------
    permutation_12 engine (
        .clk(clk),
        .rst(rst),
        .start(perm_start),
        // NOTE: Make sure you add 'is_6_round' to your permutation_12.v module
        // to control whether the round counter loops 6 or 12 times.
        // .is_6_round(is_6_round), 
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

    // -------------------------------------------------------
    // 4. Output Extractions
    // -------------------------------------------------------
    // Ciphertext is extracted combinationally during Phase 3
    assign ciphertext_out = (start_pt) ? (perm_s0 ^ data_in) : 64'd0; 
    
    // Tag is extracted at the very end of Phase 4 (after the final 12 rounds)
    // The spec requires XORing the key into S3 and S4 one last time
    assign tag_out = {perm_s3 ^ key[127:64], perm_s4 ^ key[63:0]};


    //next remaining is AD block which i need to finish tomorrow

endmodule
