`timescale 1ns / 1ps

module ascon_fsm (
    input  wire clk,
    input  wire rst,
    
    input  wire start_cipher,
    input  wire has_ad,    
    input  wire has_pt,    
    input  wire ad_last,     
    input  wire pt_last,      
    
    input  wire perm_done,
    
    output reg  start_init,
    output reg  start_ad,
    output reg  start_pt,
    output reg  start_final,
    output reg  is_6_round,
    output reg  en_domain_sep,
    output reg  en_post_init_xor, // FIXED: Added output port
    output reg  cipher_done
);

    localparam [3:0] 
        ST_IDLE       = 4'd0,
        ST_INIT_LOAD  = 4'd1,
        ST_INIT_WAIT  = 4'd2,
        ST_AD_LOAD    = 4'd3,
        ST_AD_WAIT    = 4'd4,
        ST_PT_LOAD    = 4'd5,
        ST_PT_WAIT    = 4'd6,
        ST_FINAL_LOAD = 4'd7,
        ST_FINAL_WAIT = 4'd8,
        ST_DONE       = 4'd9;

    reg [3:0] state, next_state;
    reg [3:0] prev_state; // FIXED: Added history tracking
    // FIXED: latches ad_last as it was when the current AD block was loaded.
    // ST_AD_WAIT decides "was that block the last one" only after the block's
    // P6 rounds finish, several cycles later - by then the caller has already
    // moved ad_last/data_in on to the next block (see ascon_tb.v's own
    // "pre-load onto the wire NOW" pattern), so reading the live signal there
    // would sample the wrong block's flag.
    reg       ad_last_latched;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state           <= ST_IDLE;
            prev_state      <= ST_IDLE;
            ad_last_latched <= 1'b0;
        end else begin
            state      <= next_state;
            prev_state <= state;
            if (state == ST_AD_LOAD) ad_last_latched <= ad_last;
        end
    end

    always @(*) begin
        next_state       = state;
        start_init       = 1'b0;
        start_ad         = 1'b0;
        start_pt         = 1'b0;
        start_final      = 1'b0;
        is_6_round       = 1'b0;
        en_domain_sep    = 1'b0;
        cipher_done      = 1'b0;
        
        en_post_init_xor = (prev_state == ST_INIT_WAIT); 

        case (state)
            ST_IDLE: begin
                if (start_cipher) next_state = ST_INIT_LOAD;
            end

            ST_INIT_LOAD: begin
                start_init = 1'b1;
                is_6_round = 1'b0; 
                next_state = ST_INIT_WAIT;
            end

            ST_INIT_WAIT: begin
                if (perm_done) begin
                    if (has_ad) next_state = ST_AD_LOAD;
                    else if (has_pt) next_state = ST_PT_LOAD;
                    else next_state = ST_FINAL_LOAD;
                end
            end

            ST_AD_LOAD: begin
                start_ad   = 1'b1;
                is_6_round = 1'b1; 
                next_state = ST_AD_WAIT;
            end

            ST_AD_WAIT: begin
                is_6_round = 1'b1;
                if (perm_done) begin
                    if (!ad_last_latched) next_state = ST_AD_LOAD;
                    else if (has_pt) next_state = ST_PT_LOAD;
                    else next_state = ST_FINAL_LOAD;
                end
            end
            ST_PT_LOAD: begin
                start_pt   = 1'b1;
                // FIXED: domain separation must fire exactly once, on the
                // first entry into the PT phase, not on every PT block.
                en_domain_sep = (prev_state == ST_INIT_WAIT) || (prev_state == ST_AD_WAIT);

                if (pt_last) begin
                    is_6_round = 1'b0; // Force 12-rounds for finalization
                    next_state = ST_FINAL_WAIT; // Jump straight to finalization
                end else begin
                    is_6_round = 1'b1; // Standard 6-round PT phase
                    next_state = ST_PT_WAIT;
                end
            end
            
            ST_PT_WAIT: begin
                is_6_round = 1'b1;

                // FIXED: the block just completed here is never the last one
                // (ST_PT_LOAD already diverts straight to ST_FINAL_WAIT for
                // the last block). The next block - whether or not it's the
                // final one - must still go through ST_PT_LOAD to be
                // absorbed; ST_PT_LOAD itself handles the pt_last case.
                if (perm_done)
                    next_state = ST_PT_LOAD;
            end
            ST_FINAL_LOAD: begin
                start_final = 1'b1;
                is_6_round  = 1'b0; // 12 rounds for finalization
                if (!has_pt) begin
                   en_domain_sep = 1'b1;
                end

                 next_state = ST_FINAL_WAIT; // FIXED: was self-looping and never advancing
                 end

            ST_FINAL_WAIT: begin
                if (perm_done) next_state = ST_DONE;
            end

            ST_DONE: begin
                cipher_done = 1'b1;
                if (!start_cipher) next_state = ST_IDLE;
            end

            default: next_state = ST_IDLE;
        endcase
    end
endmodule
