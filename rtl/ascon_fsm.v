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

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= ST_IDLE;
            prev_state <= ST_IDLE;
        end else begin
            state      <= next_state;
            prev_state <= state; // FIXED: Record previous state
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
        
        // FIXED: Asserts exactly 1 cycle after INIT_WAIT finishes
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
                    if (!ad_last) next_state = ST_AD_LOAD;
                    else if (has_pt) next_state = ST_PT_LOAD;
                    else next_state = ST_FINAL_LOAD;
                end
            end

            ST_PT_LOAD: begin
                start_pt   = 1'b1;
                is_6_round = 1'b1; 
                en_domain_sep = (ad_last || !has_ad);
                next_state = ST_PT_WAIT;
            end

            ST_PT_WAIT: begin
                is_6_round = 1'b1;
                if (perm_done) begin
                    if (!pt_last) next_state = ST_PT_LOAD;
                    else next_state = ST_FINAL_LOAD;
                end
            end

            ST_FINAL_LOAD: begin
                start_final = 1'b1;
                is_6_round  = 1'b0; 
                if (!has_pt) en_domain_sep = 1'b1;
                next_state = ST_FINAL_WAIT;
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
