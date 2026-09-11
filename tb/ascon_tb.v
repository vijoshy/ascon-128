`timescale 1ns / 1ps
//============================================================================
// MANUAL testbench for the Ascon-AEAD128 core (NIST SP 800-232).
//
// No KAT file, no $readmemh, no self-check. Fill in ONE vector in the
// "EDIT ME" section, run the sim, read the ciphertext / tag it prints, and
// compare against a reference by hand.
//
// The core does 10* padding in HARDWARE, so you enter RAW message bytes -
// no 0x01 pad byte, no zero-fill math. You give:
//   AD_LEN / PT_LEN : total message length in bytes (0..64)
//   AD[i] / PT[i]   : raw bytes, natural order (MS hex digit = first byte),
//                     block i holds bytes [16*i .. 16*i+15]; leftover = 0.
// Everything is typed in natural byte order; this TB does the little-endian
// word load and prints CT / TAG back in natural order.
//
// Empty AD  -> AD_LEN = 0 (AD phase skipped entirely).
// Empty PT  -> PT_LEN = 0 (still one all-pad block, per the spec).
//============================================================================
module ascon_tb;

    // ----------------------- EDIT ME -----------------------------------
    localparam integer AD_LEN = 1;    // total associated-data bytes (0..64)
    localparam integer PT_LEN = 29;    // total plaintext bytes        (0..64)

    reg [127:0] KEY   = 128'h000102030405060708090A0B0C0D0E0F;
    reg [127:0] NONCE = 128'h101112131415161718191A1B1C1D1E1F;

    reg [127:0] AD [0:3];
    reg [127:0] PT [0:3];
    initial begin
        // KEY=NONCE=0001..0F, AD=0x00070E151C232A31, PT=0x0104070A0D101316
        //   -> expect CT 3e4e7521b8084aff
        //             TAG 5cf090cfcf22b8f8f6a7fb9feb810a5a
        AD[0] = 128'h3000000000_0000000000000000000000;
        AD[1] = 128'h0; AD[2] = 128'h0; AD[3] = 128'h0;

        PT[0] = 128'h202122232425262728292A2B2C2D2E2F; // 8 raw bytes
        PT[1] = 128'h303132333435363738393A3B3C_000000;
        PT[2] = 128'h0; PT[3] = 128'h0;
    end
    // -----------------------------------------------------------------

    // number of 16-byte blocks the DUT processes for a message of `len` bytes
    // (always one more than the full-block count: partial tail block, or the
    // extra all-pad block when len is an exact multiple of 16)
    function integer nblk;
        input integer len;
        nblk = len/16 + 1;
    endfunction
    // real bytes in the final block (0..15)
    function integer lastbytes;
        input integer len;
        lastbytes = len - 16*(nblk(len) - 1);
    endfunction

    function [63:0] rev8;
        input [63:0] w; integer b;
        for (b = 0; b < 8; b = b + 1) rev8[8*b +: 8] = w[8*(7-b) +: 8];
    endfunction
    function [127:0] to_bus;
        input [127:0] v;
        to_bus = {rev8(v[127:64]), rev8(v[63:0])};
    endfunction
    function [7:0] natbyte;                 // stream byte idx of a natural value
        input [127:0] w; input integer idx;
        natbyte = w[8*(15-idx) +: 8];
    endfunction

    // ---------------- DUT I/O ----------------
    reg          clk = 1'b0;
    reg          rst, start_cipher, has_ad, has_pt, ad_last, pt_last;
    reg  [4:0]   data_bytes;
    reg  [127:0] key, nonce, data_in;

    wire [127:0] ciphertext_out, tag_out;
    wire         cipher_done;

    ascon_core uut (
        .clk(clk), .rst(rst), .start_cipher(start_cipher),
        .has_ad(has_ad), .has_pt(has_pt), .ad_last(ad_last), .pt_last(pt_last),
        .key(key), .nonce(nonce), .data_in(data_in), .data_bytes(data_bytes),
        .ciphertext_out(ciphertext_out), .tag_out(tag_out), .cipher_done(cipher_done)
    );

    always #5 clk = ~clk;

    integer  n_ad, n_pt, i;
    reg [127:0] ct_got [0:4];

    function [127:0] adraw; input integer b; adraw = (b < 4) ? AD[b] : 128'd0; endfunction
    function [127:0] ptraw; input integer b; ptraw = (b < 4) ? PT[b] : 128'd0; endfunction

    initial begin
        #500000; $display("ERROR: global timeout - FSM stuck"); $finish;
    end

    initial begin
        n_ad = (AD_LEN > 0) ? nblk(AD_LEN) : 0;
        n_pt = nblk(PT_LEN);

        key = to_bus(KEY); nonce = to_bus(NONCE); data_in = 0; data_bytes = 5'd16;
        start_cipher = 0; has_ad = 0; has_pt = 1; ad_last = 0; pt_last = 0;
        rst = 1'b1;
        repeat (4) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);

        // ---- preload the first absorb block BEFORE start ----
        has_ad = (n_ad > 0);
        has_pt = 1'b1;
        if (n_ad > 0) begin
            data_in    = to_bus(adraw(0));
            ad_last    = (n_ad == 1);
            data_bytes = (n_ad == 1) ? lastbytes(AD_LEN) : 5'd16;
        end else begin
            data_in    = to_bus(ptraw(0));
            pt_last    = (n_pt == 1);
            data_bytes = (n_pt == 1) ? lastbytes(PT_LEN) : 5'd16;
        end

        start_cipher = 1'b1;
        @(posedge clk);
        start_cipher = 1'b0;

        // ---- associated data ----
        for (i = 0; i < n_ad; i = i + 1) begin
            wait (uut.controller.start_ad);
            wait (!uut.controller.start_ad);
            if (i + 1 < n_ad) begin
                data_in    = to_bus(adraw(i + 1));
                ad_last    = (i + 1 == n_ad - 1);
                data_bytes = (i + 1 == n_ad - 1) ? lastbytes(AD_LEN) : 5'd16;
            end else begin
                data_in    = to_bus(ptraw(0));
                pt_last    = (n_pt == 1);
                data_bytes = (n_pt == 1) ? lastbytes(PT_LEN) : 5'd16;
            end
        end

        // ---- plaintext ----
        for (i = 0; i < n_pt; i = i + 1) begin
            wait (uut.controller.start_pt);
            repeat (2) @(posedge clk);
            ct_got[i] = to_bus(ciphertext_out);
            if (i + 1 < n_pt) begin
                wait (!uut.controller.start_pt);
                data_in    = to_bus(ptraw(i + 1));
                pt_last    = (i + 1 == n_pt - 1);
                data_bytes = (i + 1 == n_pt - 1) ? lastbytes(PT_LEN) : 5'd16;
            end
        end

        wait (cipher_done);
        @(posedge clk);

        // ---- report (natural byte order, no checking) ----
        $display("========================================");
        $display("KEY    = %032h", KEY);
        $display("NONCE  = %032h", NONCE);
        $display("AD_LEN = %0d   PT_LEN = %0d", AD_LEN, PT_LEN);
        $write  ("CT     = ");
        for (i = 0; i < PT_LEN; i = i + 1)
            $write("%02h", natbyte(ct_got[i/16], i%16));
        $write("\n");
        $display("TAG    = %032h", to_bus(tag_out));
        $display("========================================");
        $finish;
    end

endmodule
