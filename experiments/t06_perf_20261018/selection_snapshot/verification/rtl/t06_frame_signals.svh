logic qsu_enable_i=0;logic [31:0] qsu_capacity_i=0;
logic qsu_rd_valid_o,qsu_rd_ready_i=0,qsu_rd_bank_o;
logic [31:0] qsu_rd_offset_o,qsu_rd_count_o;
logic qsu_r_valid_i=0,qsu_r_ready_o;logic [127:0] qsu_r_data_i=0;
logic qsu_r_last_i=0,qsu_rd_busy_i=0;
logic qsu_wr_valid_o,qsu_wr_ready_i=0,qsu_wr_bank_o;
logic [31:0] qsu_wr_offset_o;logic [127:0] qsu_wr_data_o;
logic qsu_wr_busy_i=0,qsu_mem_error_i=0;logic [223:0] qsu_stats_o;
