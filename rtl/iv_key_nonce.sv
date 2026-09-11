// Ascon-AEAD128 (NIST SP 800-232) initial state loader.
//
// Bus convention: key/nonce are {word0, word1} with word0 in bits [127:64],
// where word0 = little-endian load of the first 8 key/nonce bytes (= K0/N0 in
// the spec) and word1 = little-endian load of the last 8 bytes (K1/N1).
module iv_key_nonce(
    input [127:0] key, nonce,
    output [63:0] s0,s1,s2,s3,s4
    );
    // IV = version(1) || 0 || (b<<4|a)=0x8c || taglen=128 (LE 16b) || rate=16 || 0 || 0
    // loaded little-endian into one 64-bit word:
    localparam [63:0] ascon_iv = 64'h00001000808c0001;
    assign s0 = ascon_iv;
    assign s1 = key[127:64];   // K0
    assign s2 = key[63:0];     // K1
    assign s3 = nonce[127:64]; // N0
    assign s4 = nonce[63:0];   // N1

endmodule
