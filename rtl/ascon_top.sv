`timescale 1ns / 1ps
// Ascon-AEAD128 datapath (NIST SP 800-232).
//
// 128-bit rate: data is absorbed into state words s0 (bits [127:64] of the bus)
// and s1 (bits [63:0]). See iv_key_nonce.v for the key/nonce bus convention.
//
// HARDWARE PADDING (added 2026-09-10):
//   The last AD block (start_ad & ad_last) and the last PT block
//   (start_pt & pt_last) are 10*-padded in hardware using `data_bytes`, the
//   number of real message bytes in that final block (0..15). Byte `data_bytes`
//   is forced to 0x01 and every byte above it to 0x00. Non-final blocks ignore
//   `data_bytes` and absorb all 16 bytes. For a message whose length is an
//   exact multiple of 16 (including 0), the caller feeds one extra final block
//   with data_bytes = 0 -> hardware emits 0x01,00..00. Callers no longer pad.
//   Ciphertext of a partial final PT block is masked to `data_bytes` bytes.
module ascon_top (
    input  wire clk,
    input  wire rst,

    input  wire start_init,
    input  wire start_ad,
    input  wire start_pt,
    input  wire start_final,
    input  wire rounds_8,           // 1 = P8 (AD / non-last PT), 0 = P12 (init / final / last PT)
    input  wire en_domain_sep,
    input  wire en_post_init_xor,

    input  wire        ad_last,     // this AD block is the final one -> 10* pad it
    input  wire        pt_last,     // this PT block is the final one -> 10* pad it
    input  wire [4:0]  data_bytes,  // real message bytes in the final block (0..15)

    input  wire [127:0] key,
    input  wire [127:0] nonce,
    input  wire [127:0] data_in,    // {block_word0[127:64], block_word1[63:0]}, UNPADDED

    output wire [127:0] ciphertext_out,
    output wire [127:0] tag_out,
    output wire perm_done
);
    // SP 800-232 domain-separation constant: S[4] ^= 1<<63
    localparam [63:0] DSEP = 64'h8000000000000000;

    wire [63:0] K0 = key[127:64];
    wire [63:0] K1 = key[63:0];

    // ---------------------------------------------------------------
    // 10* padding of the final block.
    //   busbyte j (j = 0..15) lives at bit 64+8j of word0 for j<8,
    //   and at bit 8(j-8) of word1 for j>=8 (little-endian word load).
    // ---------------------------------------------------------------
    function [127:0] ascon_pad10;
        input [127:0] blk;
        input [4:0]   nbytes;
        integer j;
        reg [127:0] r;
        begin
            r = 128'd0;
            for (j = 0; j < 16; j = j + 1) begin
                if (j < 8)
                    r[64 + 8*j +: 8] = (j <  nbytes) ? blk[64 + 8*j +: 8] :
                                       (j == nbytes) ? 8'h01 : 8'h00;
                else
                    r[8*(j-8) +: 8]  = (j <  nbytes) ? blk[8*(j-8) +: 8] :
                                       (j == nbytes) ? 8'h01 : 8'h00;
            end
            ascon_pad10 = r;
        end
    endfunction

    // keep only the low `nbytes` message bytes, zero the rest
    function [127:0] ascon_mask;
        input [127:0] v;
        input [4:0]   nbytes;
        integer j;
        reg [127:0] r;
        begin
            r = 128'd0;
            for (j = 0; j < 16; j = j + 1) begin
                if (j < 8) r[64 + 8*j +: 8] = (j < nbytes) ? v[64 + 8*j +: 8] : 8'h00;
                else       r[8*(j-8) +: 8]  = (j < nbytes) ? v[8*(j-8) +: 8] : 8'h00;
            end
            ascon_mask = r;
        end
    endfunction

    wire        pad_now   = (start_ad & ad_last) | (start_pt & pt_last);
    wire [4:0]  eff_bytes = pad_now ? data_bytes : 5'd16;
    wire [127:0] blk_eff  = pad_now ? ascon_pad10(data_in, data_bytes) : data_in;
    wire [63:0] d0 = blk_eff[127:64];
    wire [63:0] d1 = blk_eff[63:0];

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

    // Post-initialization key XOR (s3 ^= K0, s4 ^= K1), applied once on the
    // first absorb after P12 regardless of whether that is an AD or PT block.
    wire [63:0] s3_routed = en_post_init_xor ? (perm_s3 ^ K0) : perm_s3;
    wire [63:0] s4_routed = en_post_init_xor ? (perm_s4 ^ K1) : perm_s4;

    always @(*) begin
        if (start_init) begin
            mux_s0 = init_s0;
            mux_s1 = init_s1;
            mux_s2 = init_s2;
            mux_s3 = init_s3;
            mux_s4 = init_s4;
        end
        else if (start_ad) begin
            mux_s0 = perm_s0 ^ d0;
            mux_s1 = perm_s1 ^ d1;
            mux_s2 = perm_s2;
            mux_s3 = s3_routed;
            mux_s4 = s4_routed;
        end
        else if (start_pt) begin
            mux_s0 = perm_s0 ^ d0;
            mux_s1 = perm_s1 ^ d1;
            mux_s4 = en_domain_sep ? (s4_routed ^ DSEP) : s4_routed;

            if (!rounds_8) begin
                // LAST plaintext block: absorb, then fold in the finalization
                // pre-P12 key XOR (S[2] ^= K0, S[3] ^= K1) and run P12.
                mux_s2 = perm_s2   ^ K0;
                mux_s3 = s3_routed ^ K1;
            end else begin
                mux_s2 = perm_s2;
                mux_s3 = s3_routed;
            end
        end
        else if (start_final) begin
            // Unused in the current FSM (plaintext phase always runs, even for
            // empty PT, so finalization is fused into the last-PT-block path).
            // Kept spec-correct for completeness.
            mux_s0 = perm_s0;
            mux_s1 = perm_s1;
            mux_s2 = perm_s2   ^ K0;
            mux_s3 = s3_routed ^ K1;
            mux_s4 = en_domain_sep ? (s4_routed ^ DSEP) : s4_routed;
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
        .rounds_8(rounds_8),
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

    // Ciphertext block = (state XOR plaintext) captured at absorb time, masked
    // to the real byte count for a partial final block.
    // Bus layout matches data_in: word0 in [127:64], word1 in [63:0].
    reg [127:0] ciphertext_reg;
    always @(posedge clk or posedge rst) begin
        if (rst)
            ciphertext_reg <= 128'd0;
        else if (start_pt)
            ciphertext_reg <= ascon_mask({perm_s0 ^ d0, perm_s1 ^ d1}, eff_bytes);
    end

    assign ciphertext_out = ciphertext_reg;

    // Tag = S[3] ^ K0 || S[4] ^ K1  (post final P12)
    assign tag_out = {perm_s3 ^ K0, perm_s4 ^ K1};
endmodule
