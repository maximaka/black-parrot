/**
 *
 * Name:
 *   bp_be_bypass.v
 * 
 * Description:
 *   Register bypass network for up to 2 source registers and 1 destination register.
 *
 * Notes:
 * 
 */

module bp_be_fp_bypass
 import bp_common_rv64_pkg::*;
 #(parameter fwd_els_p = "inv"

   // Default params
   , parameter enable_p = 1

   // Generated params
   // # Bypasses == Number of forwarded elements + 1 for the dispatched data
   , localparam bypass_els_lp     = fwd_els_p + 1
   , localparam reg_addr_width_lp = rv64_reg_addr_width_gp
   , localparam reg_data_width_lp = rv64_reg_data_width_gp
   )
  (
   // Dispatched instruction operands
   input [reg_addr_width_lp-1:0]                  id_rs1_addr_i
   , input [reg_data_width_lp-1:0]                id_rs1_i

   , input [reg_addr_width_lp-1:0]                id_rs2_addr_i
   , input [reg_data_width_lp-1:0]                id_rs2_i

   , input [reg_addr_width_lp-1:0]                id_rs3_addr_i
   , input [reg_data_width_lp-1:0]                id_rs3_i

   // Completed rd writes in the pipeline
   , input [fwd_els_p-1:0]                        fwd_rd_v_i
   , input [fwd_els_p-1:0][reg_addr_width_lp-1:0] fwd_rd_addr_i
   , input [fwd_els_p-1:0][reg_data_width_lp-1:0] fwd_rd_i

   // The latest valid rs1, rs2, rs3 data
   , output [reg_data_width_lp-1:0]               bypass_rs1_o
   , output [reg_data_width_lp-1:0]               bypass_rs2_o
   , output [reg_data_width_lp-1:0]               bypass_rs3_o
   );

initial begin : parameter_validation
  assert (fwd_els_p > 0 && fwd_els_p != "inv") 
    else $error("fwd_els_p must be positive, else there is nothing to bypass. \
                 Did you remember to set it?"
                );

  assert (enable_p == 1)
    else $warning("Bypassing disabled.");
end

// Intermediate connections
logic [bypass_els_lp-1:0] rs1_match_vector       , rs2_match_vector       , rs3_match_vector;
logic [bypass_els_lp-1:0] rs1_match_vector_onehot, rs2_match_vector_onehot, rs3_match_vector_onehot;
logic [bypass_els_lp-1:0][reg_data_width_lp-1:0] rs1_data_vector, rs2_data_vector, rs3_data_vector;

// Datapath
if (enable_p == 1) 
  begin : bypass
    // Find the youngest valid data to forward
    bsg_priority_encode_one_hot_out 
     #(.width_p(bypass_els_lp)
       ,.lo_to_hi_p(1)
       ) 
     match_one_hot_rs1
      (.i(rs1_match_vector)
       ,.o(rs1_match_vector_onehot)
       );

    bsg_priority_encode_one_hot_out 
     #(.width_p(bypass_els_lp)
       ,.lo_to_hi_p(1)
       ) 
     match_one_hot_rs2
      (.i(rs2_match_vector)
       ,.o(rs2_match_vector_onehot)
       );

    bsg_priority_encode_one_hot_out 
     #(.width_p(bypass_els_lp)
       ,.lo_to_hi_p(1)
       ) 
     match_one_hot_rs3
      (.i(rs3_match_vector)
       ,.o(rs3_match_vector_onehot)
       );

    // Bypass data with a simple crossbar
    bsg_crossbar_o_by_i 
     #(.i_els_p(bypass_els_lp)
       ,.o_els_p(1)
       ,.width_p(reg_data_width_lp)
       ) 
     rs1_crossbar
      (.i(rs1_data_vector)
       ,.sel_oi_one_hot_i(rs1_match_vector_onehot)
       ,.o(bypass_rs1_o)
       );

    bsg_crossbar_o_by_i 
     #(.i_els_p(bypass_els_lp)
       ,.o_els_p(1)
       ,.width_p(reg_data_width_lp)
       ) 
     rs2_crossbar
      (.i(rs2_data_vector)
       ,.sel_oi_one_hot_i(rs2_match_vector_onehot)
       ,.o(bypass_rs2_o)
       );

    bsg_crossbar_o_by_i 
     #(.i_els_p(bypass_els_lp)
       ,.o_els_p(1)
       ,.width_p(reg_data_width_lp)
       ) 
     rs3_crossbar
      (.i(rs3_data_vector)
       ,.sel_oi_one_hot_i(rs3_match_vector_onehot)
       ,.o(bypass_rs3_o)
       );
  end // bypass
else 
  begin : passthrough
    assign bypass_rs1_o = id_rs1_i;
    assign bypass_rs2_o = id_rs2_i;
    assign bypass_rs3_o = id_rs3_i;
  end // passthrough

always_comb 
  begin : vector_generation
    // Completion data has priority over dispatched data, so dispatched data goes to MSB
    rs1_data_vector = {id_rs1_i, fwd_rd_i};
    rs2_data_vector = {id_rs2_i, fwd_rd_i};
    rs3_data_vector = {id_rs3_i, fwd_rd_i};

    for (integer i = 0; i < bypass_els_lp; i++) 
      begin : match_vector
        // Dispatched data always matches the dispatched data, otherwise check for:
        //   * Register address match 
        //   * The completing instruction is writing and the dispatched instruction is reading
        rs1_match_vector[i] = ((i == bypass_els_lp-1)
                               || ((id_rs1_addr_i == fwd_rd_addr_i[i])
                                   & fwd_rd_v_i[i]
                                   )
                               );

        rs2_match_vector[i] = ((i == bypass_els_lp-1)
                               || ((id_rs2_addr_i == fwd_rd_addr_i[i]) 
                                   & fwd_rd_v_i[i]
                                   )
                               );
        rs3_match_vector[i] = ((i == bypass_els_lp-1)
                               || ((id_rs3_addr_i == fwd_rd_addr_i[i]) 
                                   & fwd_rd_v_i[i]
                                   )
                               );
      end
  end

endmodule

