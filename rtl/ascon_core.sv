`timescale 1ns / 1ps
module ascon_core (
    input  wire clk,
    input  wire rst,

    // System-Level Commands
    input  wire start_cipher,
    input  wire has_ad,
    input  wire has_pt,
    input  wire ad_last,
    input  wire pt_last,

    // Raw Data Inputs
    input  wire [127:0] key,
    input  wire [127:0] nonce,
    input  wire [127:0] data_in,      // UNPADDED block; hardware 10*-pads the last one
    input  wire [4:0]   data_bytes,   // real message bytes in the final AD/PT block (0..15)

    // System-Level Outputs
    output wire [127:0] ciphertext_out,
    output wire [127:0] tag_out,
    output wire         cipher_done
);
    // Internal Interconnect Wires
    wire ctrl_start_init;
    wire ctrl_start_ad;
    wire ctrl_start_pt;
    wire ctrl_start_final;
    wire ctrl_rounds_8;
    wire ctrl_en_domain_sep;
    wire ctrl_en_post_init_xor;
    wire status_perm_done;
    // 1. Control Path
    ascon_fsm controller (
        .clk(clk),
        .rst(rst),
        .start_cipher(start_cipher),
        .has_ad(has_ad),
        .has_pt(has_pt),
        .ad_last(ad_last),
        .pt_last(pt_last),
        .perm_done(status_perm_done), 

        .start_init(ctrl_start_init),
        .start_ad(ctrl_start_ad),
        .start_pt(ctrl_start_pt),
        .start_final(ctrl_start_final),
        .rounds_8(ctrl_rounds_8),
        .en_domain_sep(ctrl_en_domain_sep),
        .en_post_init_xor(ctrl_en_post_init_xor), // FIXED: Port mapped
        .cipher_done(cipher_done)
    );
    // 2. Datapath
    ascon_top datapath (
        .clk(clk),
        .rst(rst),

        .start_init(ctrl_start_init),
        .start_ad(ctrl_start_ad),
        .start_pt(ctrl_start_pt),
        .start_final(ctrl_start_final),
        .rounds_8(ctrl_rounds_8),
        .en_domain_sep(ctrl_en_domain_sep),
        .en_post_init_xor(ctrl_en_post_init_xor), // FIXED: Port mapped

        .ad_last(ad_last),
        .pt_last(pt_last),
        .data_bytes(data_bytes),

        .key(key),
        .nonce(nonce),
        .data_in(data_in),

        .ciphertext_out(ciphertext_out),
        .tag_out(tag_out),
        .perm_done(status_perm_done) 
    );
endmodule
