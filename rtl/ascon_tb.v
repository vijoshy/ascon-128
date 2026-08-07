`timescale 1ns / 1ps

module ascon_tb;

    // -------------------------------------------------------
    // 1. Signals
    // -------------------------------------------------------
    reg         clk;
    reg         rst;
    reg         start_cipher;
    reg         has_ad;
    reg         has_pt;
    reg         ad_last;
    reg         pt_last;
    reg  [127:0] key;
    reg  [127:0] nonce;
    reg  [63:0]  data_in;

    wire [63:0]  ciphertext_out;
    wire [127:0] tag_out;
    wire         cipher_done;

    // -------------------------------------------------------
    // 2. DUT
    // -------------------------------------------------------
    ascon_core uut (
        .clk           (clk),
        .rst           (rst),
        .start_cipher  (start_cipher),
        .has_ad        (has_ad),
        .has_pt        (has_pt),
        .ad_last       (ad_last),
        .pt_last       (pt_last),
        .key           (key),
        .nonce         (nonce),
        .data_in       (data_in),
        .ciphertext_out(ciphertext_out),
        .tag_out       (tag_out),
        .cipher_done   (cipher_done)
    );

    // -------------------------------------------------------
    // 3. Clock - 100 MHz
    // -------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------
    // 4. Timeout watchdog
    // -------------------------------------------------------
    initial begin
        #10000;
        $display("ERROR: simulation timed out - FSM likely stuck");
        $finish;
    end

// -------------------------------------------------------
    // 5. Test sequence
    // -------------------------------------------------------
    initial begin
        // init
        rst          = 1;
        start_cipher = 0;
        has_ad       = 0;
        has_pt       = 0;
        ad_last      = 0;
        pt_last      = 0;
        key          = 128'h000102030405060708090A0B0C0D0E0F;
        nonce        = 128'h000102030405060708090A0B0C0D0E0F;
        data_in      = 64'h0000000000000000;

        // release reset on a clock edge
        repeat(4) @(posedge clk);
        rst = 0;
        @(posedge clk);

    // --- PHASE 1: start with flags set ---
        $display("[%0t] Starting ASCON-128 init", $time);
    
        has_ad  = 1;
        has_pt  = 1;
        ad_last = 0;
        pt_last = 1;
    
        // -------------------------------
        // AD BLOCK #1
        // 00 01 02 03 04 05 06 07
        // -------------------------------
        data_in = 64'h0001020304050607;
    
        start_cipher = 1;
        @(posedge clk);
        start_cipher = 0;
    
        wait(uut.controller.start_ad);
        $display("[%0t] AD Block 1", $time);
    
        wait(!uut.controller.start_ad);
    
        // -------------------------------
        // AD BLOCK #2
        // 08 09 0A 0B 0C 0D 0E 0F
        // -------------------------------
        ad_last = 1;
        data_in = 64'h08090A0B0C0D0E0F;
    
        wait(uut.controller.start_ad);
        $display("[%0t] AD Block 2", $time);
    
        wait(!uut.controller.start_ad);
    
        // -------------------------------
        // PLAINTEXT
        // 00 01 02 03
        // -------------------------------
        data_in = 64'h0001020380000000;
    
        wait(uut.controller.start_pt);
        $display("[%0t] PT Block", $time);
    
        #1;
        $display("[%0t] Ciphertext = %h", $time, ciphertext_out);
    
        // -------------------------------
        // FINISH
        // -------------------------------
        wait(cipher_done);
        @(posedge clk);
    
        $display("[%0t] Tag = %h", $time, tag_out);
    
        $display("Expected Ciphertext = 1EE34125");
        $display("Expected Tag        = 0AC282B59324053C701FE5D0CF777784");
    
        #20;
        $finish;
    end
endmodule
