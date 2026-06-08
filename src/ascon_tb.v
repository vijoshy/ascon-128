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
        nonce        = 128'h101112131415161718191A1B1C1D1E1F;
        data_in      = 64'h0000000000000000;

        // release reset on a clock edge
        repeat(4) @(posedge clk);
        rst = 0;
        @(posedge clk);

// --- PHASE 1: start with flags set ---
        $display("[%0t] Starting ASCON-128 (Count 37)", $time);
        
        has_ad       = 1; 
        has_pt       = 1; 
        ad_last      = 1; 
        pt_last      = 1; 
        
        key          = 128'h000102030405060708090A0B0C0D0E0F;
        nonce        = 128'h101112131415161718191A1B1C1D1E1F;
        
        start_cipher = 1;
        @(posedge clk);
        start_cipher = 0;

        // --- PHASE 2: load AD ---
        wait(uut.controller.start_ad == 1'b1);
        $display("[%0t] Loading AD block...", $time);
        
        // PADDED AD: 303132 + 8000000000
        data_in = 64'h3031328000000000; 

        // --- PHASE 3: load plaintext ---
        wait(uut.controller.start_pt == 1'b1);
        $display("[%0t] Loading PT block...", $time);
        
        // PADDED PT: 20 + 80000000000000
        data_in = 64'h2080000000000000; 
        
        // Sample the ciphertext after XOR settles
        #1; 
        $display("[%0t] Ciphertext Block : %h", $time, ciphertext_out);

        // --- PHASE 4: wait for completion ---
        wait(cipher_done == 1'b1);
        @(posedge clk); 

        $display("[%0t] Final Tag        : %h", $time, tag_out);
        $display("[%0t] ASCON-128 done", $time);

        #20;
        $finish;
    end

endmodule
