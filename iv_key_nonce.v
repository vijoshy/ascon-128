module iv_key_nonce(
    input [127:0] key, nonce,
    output [63:0] s0,s1,s2,s3,s4
    );
    localparam [63:0] ascon_iv = 64'h80400c0600000000; //standard value
    assign s0 = ascon_iv;
    assign s1 = key[127:64]; //Key_hi
    assign s2 = key[63:0]; //Key_lo
    assign s3 = nonce[127:64] ; //Nonce_high
    assign s4 = nonce[63:0] ; //Nonce_low
    
endmodule
