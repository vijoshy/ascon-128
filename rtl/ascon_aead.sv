`timescale 1ns / 1ps

module ascon_aead (
    input  wire clk,
    input  wire rst,
    output wire debug_out
);

    wire [127:0] ciphertext_out;
    wire [127:0] tag_out;
    wire         cipher_done;

    // Ascon inputs
    reg         start_cipher;
    reg         has_ad;
    reg         has_pt;
    reg         ad_last;
    reg         pt_last;

    reg [127:0] key;
    reg [127:0] nonce;
    reg [127:0] data_in;
    reg [4:0]   data_bytes;

    // Internal result registers
    reg [127:0] ciphertext_reg;
    reg [127:0] tag_reg;
    reg         done_reg;

    always @(posedge clk) begin
        if (rst) begin
            ciphertext_reg <= 128'd0;
            tag_reg        <= 128'd0;
            done_reg       <= 1'b0;
        end
        else begin
            ciphertext_reg <= ciphertext_out;
            tag_reg        <= tag_out;
            done_reg       <= cipher_done;
        end
    end

    // Make the design externally observable
    assign debug_out = done_reg;

    // Temporary stimulus
    always @(posedge clk) begin
        if (rst) begin
            start_cipher <= 1'b0;
            has_ad       <= 1'b0;
            has_pt       <= 1'b1;
            ad_last      <= 1'b1;
            pt_last      <= 1'b1;

            key        <= 128'h000102030405060708090A0B0C0D0E0F;
            nonce      <= 128'h101112131415161718191A1B1C1D1E1F;
            data_in    <= 128'h00000000000000000000000000000000;
            data_bytes <= 5'd16;
        end
        else begin
            start_cipher <= 1'b1;
        end
    end

    ascon_core u_ascon (
        .clk(clk),
        .rst(rst),

        .start_cipher(start_cipher),
        .has_ad(has_ad),
        .has_pt(has_pt),
        .ad_last(ad_last),
        .pt_last(pt_last),

        .key(key),
        .nonce(nonce),
        .data_in(data_in),
        .data_bytes(data_bytes),

        .ciphertext_out(ciphertext_out),
        .tag_out(tag_out),
        .cipher_done(cipher_done)
    );

endmodule
