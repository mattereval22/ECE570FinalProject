`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    16:20:27 09/22/2011 
// Design Name: 
// Module Name:    BPI_ctrl 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module BPI_ctrl #(
	parameter USE_CHIPSCOPE = 1,
	parameter TMR = 0,
	parameter TMR_Err_Det = 0
)
(
	// Chip Scope Pro control signals
	inout [35:0] BPI_VIO_CNTRL,
	inout [35:0] BPI_LA_CNTRL,
	// added for sim of external PROM
//	output [1:0]RD_MODE,
	//
    input CLK,                  // 40 MHz clock
    input CLK1MHZ,              //  1 MHz clock for timers
    input RST,
    input BPI_FIFO_RST,
	 // Interface Signals to/from JTAG interface
	 input [15:0] BPI_CMD_FIFO_DATA, // Data for command FIFO
	 input BPI_WE,                   // Command FIFO write enable  (pulse one clock cycle for one write)
	 input BPI_RE,                   // Read back FIFO read enable  (pulse one clock cycle for one read)
    input BPI_DSBL,                 // Disable parsing of BPI commands in the command FIFO (while being filled)
    input BPI_ENBL,                 // Enable  parsing of BPI commands in the command FIFO
	 output [15:0] BPI_RBK_FIFO_DATA,// Data on output of the Read back FIFO
	 output [10:0] BPI_RBK_WRD_CNT,  // Word count of the Read back FIFO (number of available reads)
	 output [15:0] BPI_STATUS,   // FIFO status bits and latest value of the PROM status register. 
	 output [31:0] BPI_TIMER,    // General timer
	 // Signals to/from low level BPI interface
	 input BPI_BUSY,
	 input [15:0] BPI_DATA_FROM,
	 input BPI_LOAD_DATA,
	 output CSP_BPI_RST,
	 output BPI_ACTIVE,
	 output [1:0] BPI_OP,
	 output [22:0] BPI_ADDR,
	 output [15:0] BPI_DATA_TO,
	 output BPI_EXECUTE,
	 output BPI_SEQ_IDLE
    );
	 
	 //
	 // Declaration of commands used throughout the BPI interface
	 //
localparam 
// commands for the PROM
	NoOp            = 5'h00,
	Write_1         = 5'h01,
	Read_1          = 5'h02,
	Write_n         = 5'h03,
	Read_n          = 5'h04,
	Read_Array      = 5'h05,
	Read_Status_Reg = 5'h06,
	Read_Elec_Sig   = 5'h07,
	Read_CFI_Qry    = 5'h08,
	Clr_Status_Reg  = 5'h09,
	Block_Erase     = 5'h0A,
	Program         = 5'h0B,
	Buffer_Program  = 5'h0C,
	Buf_Prog_Wrt_n  = 5'h0D,
	Buf_Prog_Conf   = 5'h0E,
	PE_Susp         = 5'h0F,
	PE_Resume       = 5'h10,
	Prot_Reg_Prog   = 5'h11,
	Set_Cnfg_Reg    = 5'h12,
	Block_Lock      = 5'h13,
	Block_UnLock    = 5'h14,
	Block_Lock_Down = 5'h15,
	Blank_Check     = 5'h16,
// commands for local control
	Load_Address    = 5'h17,
	Unassigned      = 5'h18,
	Start_Timer     = 5'h19,
	Stop_Timer      = 5'h1A,
	Reset_Timer     = 5'h1B,
	Clr_BPI_Status  = 5'h1C;

localparam // Read modes (Array, Status Register, Electronic Signature, or Common Flash Interface Query)
   Rd_Array        = 2'd0,
   Rd_SR           = 2'd1,
   Rd_ESig         = 2'd2,
   Rd_CFIQ         = 2'd3;
	
localparam // Operational modes (synchronous or asynchronous)
   CRD_Sync        = 16'h3DDF,
   CRD_ASync       = 16'hBDDF;
	
// BPI_cmd_parser_FSM output signals
wire fsm_ack;
wire decode;
wire enable_cmd;
wire parser_idle;
wire ld_cnts;
wire ld_full;
wire ld_status;
wire ld_usr;
wire read_ff;
wire [3:0] parse_state;

//BPI_sequencer_FSM output signals
wire check_PEC;
wire check_buf;
wire check_stat;
wire cnfrm_lk;
wire [4:0] command;
wire read_es_state;
wire rpt_error;
wire seq_cmplt;
wire seqr_idle;
wire set_asynch;
wire [4:0] seq_state;

//BPI_ctrl_FSM output signals
wire cycle2;
wire decr;
wire load_n;
wire next;
wire seq_done;
wire [3:0] ctrl_state;
// end of FSM output signals

// BPI command FIFO signals
wire bpi_cmd_mt;
wire bpi_cmd_full;
wire bpi_wrena;
wire bpi_wrterr;
wire bpi_rdena;
wire bpi_rderr;
wire [15:0] data_fifo;     // command FIFO data output
wire [15:0] bpi_wrt_data;  // command FIFO data input
wire sbitcmderr;
wire dbitcmderr;

// BPI read FIFO signals
wire bpi_rbk_mt;
wire bpi_rbk_full;
wire bpi_rbk_wrterr;
wire bpi_rbk_rderr;
wire sbitrbkerr;
wire dbitrbkerr;

// chip scope signals
wire [6:0]  csp_base_address;
wire [15:0] csp_start_offset;
wire [15:0] csp_data;
wire [15:0] csp_ncnt;
wire [4:0]  csp_usr_cmnd;
wire csp_rbk_cnt_rst;
wire csp_load_offset;
wire csp_load_count;
wire csp_man_rst;
wire csp_bpi_wrena;
wire csp_ctrl;
wire csp_fifo_src;
wire csp_ack;
wire csp_bpi_enbl;
wire csp_bpi_dsbl;
reg [15:0] rbkbuf0, rbkbuf1, rbkbuf2, rbkbuf3, rbkbuf4, rbkbuf5, rbkbuf6, rbkbuf7;


//single nets that do not need to be replicated
wire ack; 
wire pec_busy;
wire buf_prog;
wire term_cnt;
wire loop_done;
reg  has_data;
reg  pass;
reg  xtra_word;
reg [4:0] seq_cmnd;
reg  noop_seq;
reg  simple_cmd;
reg  lk_unlk;
reg  std_seq; 
reg error;
reg lk_ok;
wire rbk_cnt_rst;
wire [6:0]  base_address;
reg  [22:0] addr;
wire [22:0] waddr;
reg  [22:0] block_addr;
wire [22:0] bank_addr;
wire [22:0] lk_stat_addr;
wire [22:0] prot_reg_addr;
wire [8:0]  pra_offset;
reg  [15:0] data1;
reg  [15:0] data2;
reg  [15:0] prog_data;
wire [15:0] prot_reg_data;
reg  two_cycle;
wire intf_busy;
wire intf_rdy;
wire noop;
wire other;
wire read_1;
wire read_n;
wire write_n;

// nets outside of TMR generation code
wire [1:0]  read_mode_i;
wire [7:0]  sr_reg_i;
wire [15:0] esig_reg_i;
wire [15:0] cfiq_reg_i;
wire [15:0] cngf_reg_data_i;
wire [4:0]  bcount_i;
wire [15:0] rbk_count_i;
wire [15:0] adr_offset_i;
wire [10:0] bpi_cmd_cnt_i;       // words in FIFO
wire bpi_enable_i;
wire parser_active_i;
wire cnt_cmd_i;
wire local_i;
wire bpi_rbk_wena_i;
wire usr_read_req_i;
wire [4:0] usr_cmnd_i;


assign BPI_SEQ_IDLE = seqr_idle;
assign BPI_OP = (read_1 || read_n) ? 2'b10 : 2'b01;
assign BPI_ADDR = addr;
assign BPI_DATA_TO = cycle2 ? data2 : data1;
assign CSP_BPI_RST  = csp_man_rst;

//assign RD_MODE = read_mode; // only for simulations
assign rbk_cnt_rst  = csp_rbk_cnt_rst || RST;
assign bpi_wrt_data = csp_fifo_src ? csp_data : BPI_CMD_FIFO_DATA;
assign ack = fsm_ack || csp_ack;

assign waddr = {base_address,adr_offset_i};
assign bank_addr = waddr & 23'h780000;
assign lk_stat_addr = block_addr | 23'h000002;
assign prot_reg_addr = bank_addr + pra_offset;
assign prot_reg_data = 16'hFFFF;
assign intf_busy =  BPI_BUSY;
assign intf_rdy  = !BPI_BUSY;
assign noop = (command == NoOp);
assign read_1 = (command == Read_1);
assign read_n = (command == Read_n);
assign write_n = (command == Write_n);
assign other = !noop && !read_n && !write_n;
assign bpi_rdena = (next && write_n) || read_ff;
assign bpi_wrena = csp_bpi_wrena || BPI_WE;
assign buf_prog  = (usr_cmnd_i == Buffer_Program);



always @* begin
	if(waddr > 23'h7EFFFF)
		block_addr = waddr & 23'h7FC000; // for 16 KWord parameter blocks
	else
		block_addr = waddr & 23'h7F0000; // for 64 KWord blocks
end

always @* begin
	case(usr_cmnd_i)
		NoOp, Write_n, Buf_Prog_Wrt_n, Buf_Prog_Conf:
					noop_seq   = 1;
		default: noop_seq   = 0;
	endcase
	case(usr_cmnd_i)
		Read_1, Read_n, Write_1, Read_Array, Read_Status_Reg, Read_Elec_Sig, Read_CFI_Qry, PE_Resume, Set_Cnfg_Reg, Clr_Status_Reg:
					simple_cmd   = 1;
		default: simple_cmd   = 0;
	endcase
	case(usr_cmnd_i)
		Block_Erase, Program, PE_Susp, Prot_Reg_Prog, Blank_Check:
					std_seq   = 1;
		default: std_seq   = 0;
	endcase
	case(usr_cmnd_i)
		Block_Lock, Block_UnLock, Block_Lock_Down: 
					lk_unlk   = 1;
		default: lk_unlk   = 0;
	endcase
	case(usr_cmnd_i)
		Read_1, Read_n, Write_1, Read_Array, Read_Status_Reg, Read_Elec_Sig, Read_CFI_Qry,
		PE_Resume, Set_Cnfg_Reg, Clr_Status_Reg,
		Block_Erase, Program, PE_Susp, Prot_Reg_Prog, Blank_Check,
		Block_Lock, Block_UnLock, Block_Lock_Down: 
					seq_cmnd   = usr_cmnd_i;
		default: seq_cmnd   = NoOp;
	endcase
	case(usr_cmnd_i)
		Block_Lock:
			lk_ok = (cnfrm_lk) && ((esig_reg_i & 16'hFFFD)== 16'h0001);
		Block_UnLock:
			lk_ok = (cnfrm_lk) && ((esig_reg_i & 16'hFFFD)== 16'h0000);
		Block_Lock_Down:
			lk_ok = (cnfrm_lk) && ((esig_reg_i & 16'hFFFE)== 16'h0002);
		default:
			lk_ok = 0;
	endcase
	case(usr_cmnd_i)
		Block_Erase:
			error = (check_stat) &&  |(sr_reg_i & 8'h2A);
		Program, Buffer_Program, Prot_Reg_Prog:
			error = (check_stat) && |(sr_reg_i & 8'h1A);
		PE_Susp:
			error = 0;
		Blank_Check:
			error = (check_stat) && sr_reg_i[5];
		default:
			error = 0;
	endcase
	case(usr_cmnd_i)
		Buffer_Program:
			prog_data = data_fifo;
		default:
			prog_data = csp_ctrl ? csp_data : data_fifo;
	endcase
end

always @*
begin
	case(command)
		NoOp:
			begin
				addr = bank_addr;
				data1 = 16'h0000;
				data2 = 16'h0000;
				two_cycle = 0;
			end
		Write_1, Write_n:
			begin
				addr = waddr;
				data1 = prog_data;
				data2 = 16'h0000;
				two_cycle = 0;
			end
		Read_1, Read_n:
			begin
				addr = read_es_state ? lk_stat_addr : waddr;   // seq_state
				data1 = 16'h0000;
				data2 = 16'h0000;
				two_cycle = 0;
			end
		Read_Array:
			begin
				addr = bank_addr;
				data1 = 16'h00FF;
				data2 = 16'h0000;
				two_cycle = 0;
			end
		Read_Status_Reg:
			begin
				addr = bank_addr;
				data1 = 16'h0070;
				data2 = 16'h0000;
				two_cycle = 0;
			end
		Read_Elec_Sig:
			begin
				addr = bank_addr;
				data1 = 16'h0090;
				data2 = 16'h0000;
				two_cycle = 0;
			end
		Read_CFI_Qry:
			begin
				addr = bank_addr;
				data1 = 16'h0098;
				data2 = 16'h0000;
				two_cycle = 0;
			end
		Clr_Status_Reg:
			begin
				addr = bank_addr;
				data1 = 16'h0050;
				data2 = 16'h0000;
				two_cycle = 0;
			end
		Block_Erase:
			begin
				addr = block_addr;
				data1 = 16'h0020;
				data2 = 16'h00D0;
				two_cycle = 1;
			end
		Program:
			begin
				addr = waddr;
				data1 = 16'h0040;
				data2 = prog_data;
				two_cycle = 1;
			end
		Buffer_Program:
			begin
				addr = block_addr;
				data1 = 16'h00E8;
				data2 = 16'h0000;
				two_cycle = 0;
			end
		Buf_Prog_Wrt_n:
			begin
				addr = block_addr;
				data1 = {11'h000,bcount_i};
				data2 = 16'h0000;
				two_cycle = 0;
			end
		Buf_Prog_Conf:
			begin
				addr = bank_addr;
				data1 = 16'h00D0;
				data2 = 16'h0000;
				two_cycle = 0;
			end
		PE_Susp:
			begin
				addr = bank_addr;
				data1 = 16'h00B0;
				data2 = 16'h0070;  // set status register read mode
				two_cycle = 1;
			end
		PE_Resume:
			begin
				addr = bank_addr;
				data1 = 16'h00D0;
				data2 = 16'h0000;
				two_cycle = 0;
			end
		Prot_Reg_Prog:
			begin
				addr = prot_reg_addr;
				data1 = 16'h00C0;
				data2 = prot_reg_data;
				two_cycle = 1;
			end
		Set_Cnfg_Reg:
			begin
				addr = {7'h00,cngf_reg_data_i};
				data1 = 16'h0060;
				data2 = 16'h0003;
				two_cycle = 1;
			end
		Block_Lock:
			begin
				addr = block_addr;
				data1 = 16'h0060;
				data2 = 16'h0001;
				two_cycle = 1;
			end
		Block_UnLock:
			begin
				addr = block_addr;
				data1 = 16'h0060;
				data2 = 16'h00D0;
				two_cycle = 1;
			end
		Block_Lock_Down:
			begin
				addr = block_addr;
				data1 = 16'h0060;
				data2 = 16'h002F;
				two_cycle = 1;
			end
		Blank_Check:
			begin
				addr = block_addr;
				data1 = 16'h00BC;
				data2 = 16'h00CB;
				two_cycle = 1;
			end
		default:
			begin
				addr = bank_addr;
				data1 = 16'h0000;
				data2 = 16'h0000;
				two_cycle = 0;
			end
	endcase
end

	always @(posedge CLK)
	begin
		if(BPI_LOAD_DATA ) begin
			if(read_mode_i == Rd_Array) begin
				if(rbk_count_i[2:0] == 3'd0) rbkbuf0 <= BPI_DATA_FROM;
				else rbkbuf0  <= rbkbuf0;
				if(rbk_count_i[2:0] == 3'd1) rbkbuf1 <= BPI_DATA_FROM;
				else rbkbuf1  <= rbkbuf1;
				if(rbk_count_i[2:0] == 3'd2) rbkbuf2 <= BPI_DATA_FROM;
				else rbkbuf2  <= rbkbuf2;
				if(rbk_count_i[2:0] == 3'd3) rbkbuf3 <= BPI_DATA_FROM;
				else rbkbuf3  <= rbkbuf3;
				if(rbk_count_i[2:0] == 3'd4) rbkbuf4 <= BPI_DATA_FROM;
				else rbkbuf4  <= rbkbuf4;
				if(rbk_count_i[2:0] == 3'd5) rbkbuf5 <= BPI_DATA_FROM;
				else rbkbuf5  <= rbkbuf5;
				if(rbk_count_i[2:0] == 3'd6) rbkbuf6 <= BPI_DATA_FROM;
				else rbkbuf6  <= rbkbuf6;
				if(rbk_count_i[2:0] == 3'd7) rbkbuf7 <= BPI_DATA_FROM;
				else rbkbuf7  <= rbkbuf7;
			end
		end
	end


generate
if(TMR==1) 
begin : BPI_logic_TMR

	(* syn_preserve = "true" *) reg [1:0]  read_mode_1 = 2'b00;
	(* syn_preserve = "true" *) reg [7:0]  sr_reg_1;
	(* syn_preserve = "true" *) reg [15:0] esig_reg_1;
	(* syn_preserve = "true" *) reg [15:0] cfiq_reg_1;
	(* syn_preserve = "true" *) reg [4:0]  ff_usr_cmnd_1;
	(* syn_preserve = "true" *) reg [10:0] ff_ba_cnt_1;
	(* syn_preserve = "true" *) reg [6:0]  ff_base_address_1;
	(* syn_preserve = "true" *) reg [15:0] ff_start_offset_1;
	(* syn_preserve = "true" *) reg [10:0] ff_n_minus_1_1;
	(* syn_preserve = "true" *) reg [15:0] cngf_reg_data_1;
	(* syn_preserve = "true" *) reg [15:0] count_mux_1;
	(* syn_preserve = "true" *) reg [4:0]  bcount_1;
	(* syn_preserve = "true" *) reg [15:0] count_1;
	(* syn_preserve = "true" *) reg [15:0] full_count_1;
	(* syn_preserve = "true" *) reg [15:0] rbk_count_1;
	(* syn_preserve = "true" *) reg [15:0] adr_offset_1;
	(* syn_preserve = "true" *) reg [15:0] bpi_status_r_1;   // FIFO status bits and latest value of the PROM status register. 
	(* syn_preserve = "true" *) reg [31:0] bpi_timer_r_1;    // General timer
	(* syn_preserve = "true" *) reg [10:0] bpi_cmd_cnt_1;       // words in FIFO
	(* syn_preserve = "true" *) reg [10:0] bpi_rbk_cnt_1;       // words in FIFO
	(* syn_preserve = "true" *) reg [19:0] parser_inactive_tmr_1;
	(* syn_preserve = "true" *) reg incr_tmr_1;
	(* syn_preserve = "true" *) reg bpi_enable_1;
	(* syn_preserve = "true" *) reg parser_active_1;
	(* syn_preserve = "true" *) reg parser_active_r_1;
	(* syn_preserve = "true" *) reg pe_in_suspense_1;

	(* syn_preserve = "true" *) reg [1:0]  read_mode_2 = 2'b00;
	(* syn_preserve = "true" *) reg [7:0]  sr_reg_2;
	(* syn_preserve = "true" *) reg [15:0] esig_reg_2;
	(* syn_preserve = "true" *) reg [15:0] cfiq_reg_2;
	(* syn_preserve = "true" *) reg [4:0]  ff_usr_cmnd_2;
	(* syn_preserve = "true" *) reg [10:0] ff_ba_cnt_2;
	(* syn_preserve = "true" *) reg [6:0]  ff_base_address_2;
	(* syn_preserve = "true" *) reg [15:0] ff_start_offset_2;
	(* syn_preserve = "true" *) reg [10:0] ff_n_minus_1_2;
	(* syn_preserve = "true" *) reg [15:0] cngf_reg_data_2;
	(* syn_preserve = "true" *) reg [15:0] count_mux_2;
	(* syn_preserve = "true" *) reg [4:0]  bcount_2;
	(* syn_preserve = "true" *) reg [15:0] count_2;
	(* syn_preserve = "true" *) reg [15:0] full_count_2;
	(* syn_preserve = "true" *) reg [15:0] rbk_count_2;
	(* syn_preserve = "true" *) reg [15:0] adr_offset_2;
	(* syn_preserve = "true" *) reg [15:0] bpi_status_r_2;   // FIFO status bits and latest value of the PROM status register. 
	(* syn_preserve = "true" *) reg [31:0] bpi_timer_r_2;    // General timer
	(* syn_preserve = "true" *) reg [10:0] bpi_cmd_cnt_2;       // words in FIFO
	(* syn_preserve = "true" *) reg [10:0] bpi_rbk_cnt_2;       // words in FIFO
	(* syn_preserve = "true" *) reg [19:0] parser_inactive_tmr_2;
	(* syn_preserve = "true" *) reg incr_tmr_2;
	(* syn_preserve = "true" *) reg bpi_enable_2;
	(* syn_preserve = "true" *) reg parser_active_2;
	(* syn_preserve = "true" *) reg parser_active_r_2;
	(* syn_preserve = "true" *) reg pe_in_suspense_2;

	(* syn_preserve = "true" *) reg [1:0]  read_mode_3 = 2'b00;
	(* syn_preserve = "true" *) reg [7:0]  sr_reg_3;
	(* syn_preserve = "true" *) reg [15:0] esig_reg_3;
	(* syn_preserve = "true" *) reg [15:0] cfiq_reg_3;
	(* syn_preserve = "true" *) reg [4:0]  ff_usr_cmnd_3;
	(* syn_preserve = "true" *) reg [10:0] ff_ba_cnt_3;
	(* syn_preserve = "true" *) reg [6:0]  ff_base_address_3;
	(* syn_preserve = "true" *) reg [15:0] ff_start_offset_3;
	(* syn_preserve = "true" *) reg [10:0] ff_n_minus_1_3;
	(* syn_preserve = "true" *) reg [15:0] cngf_reg_data_3;
	(* syn_preserve = "true" *) reg [15:0] count_mux_3;
	(* syn_preserve = "true" *) reg [4:0]  bcount_3;
	(* syn_preserve = "true" *) reg [15:0] count_3;
	(* syn_preserve = "true" *) reg [15:0] full_count_3;
	(* syn_preserve = "true" *) reg [15:0] rbk_count_3;
	(* syn_preserve = "true" *) reg [15:0] adr_offset_3;
	(* syn_preserve = "true" *) reg [15:0] bpi_status_r_3;   // FIFO status bits and latest value of the PROM status register. 
	(* syn_preserve = "true" *) reg [31:0] bpi_timer_r_3;    // General timer
	(* syn_preserve = "true" *) reg [10:0] bpi_cmd_cnt_3;       // words in FIFO
	(* syn_preserve = "true" *) reg [10:0] bpi_rbk_cnt_3;       // words in FIFO
	(* syn_preserve = "true" *) reg [19:0] parser_inactive_tmr_3;
	(* syn_preserve = "true" *) reg incr_tmr_3;
	(* syn_preserve = "true" *) reg bpi_enable_3;
	(* syn_preserve = "true" *) reg parser_active_3;
	(* syn_preserve = "true" *) reg parser_active_r_3;
	(* syn_preserve = "true" *) reg pe_in_suspense_3;

	(* syn_keep = "true" *) wire [1:0]  vt_read_mode_1;
	(* syn_keep = "true" *) wire [7:0]  vt_sr_reg_1;
	(* syn_keep = "true" *) wire [15:0] vt_esig_reg_1;
	(* syn_keep = "true" *) wire [15:0] vt_cfiq_reg_1;
	(* syn_keep = "true" *) wire [4:0]  vt_ff_usr_cmnd_1;
	(* syn_keep = "true" *) wire [10:0] vt_ff_ba_cnt_1;
	(* syn_keep = "true" *) wire [6:0]  vt_ff_base_address_1;
	(* syn_keep = "true" *) wire [15:0] vt_ff_start_offset_1;
	(* syn_keep = "true" *) wire [10:0] vt_ff_n_minus_1_1;
	(* syn_keep = "true" *) wire [15:0] vt_cngf_reg_data_1;
	(* syn_keep = "true" *) wire [15:0] vt_count_mux_1;
	(* syn_keep = "true" *) wire [4:0]  vt_bcount_1;
	(* syn_keep = "true" *) wire [15:0] vt_count_1;
	(* syn_keep = "true" *) wire [15:0] vt_full_count_1;
	(* syn_keep = "true" *) wire [15:0] vt_rbk_count_1;
	(* syn_keep = "true" *) wire [15:0] vt_adr_offset_1;
	(* syn_keep = "true" *) wire [15:0] vt_bpi_status_r_1;   // FIFO status bits and latest value of the PROM status register. 
	(* syn_keep = "true" *) wire [31:0] vt_bpi_timer_r_1;    // General timer
	(* syn_keep = "true" *) wire [10:0] vt_bpi_cmd_cnt_1;       // words in FIFO
	(* syn_keep = "true" *) wire [10:0] vt_bpi_rbk_cnt_1;       // words in FIFO
	(* syn_keep = "true" *) wire [19:0] vt_parser_inactive_tmr_1;
	(* syn_keep = "true" *) wire vt_incr_tmr_1;
	(* syn_keep = "true" *) wire vt_bpi_enable_1;
	(* syn_keep = "true" *) wire vt_parser_active_1;
	(* syn_keep = "true" *) wire vt_parser_active_r_1;
	(* syn_keep = "true" *) wire vt_pe_in_suspense_1;

	(* syn_keep = "true" *) wire [1:0]  vt_read_mode_2;
	(* syn_keep = "true" *) wire [7:0]  vt_sr_reg_2;
	(* syn_keep = "true" *) wire [15:0] vt_esig_reg_2;
	(* syn_keep = "true" *) wire [15:0] vt_cfiq_reg_2;
	(* syn_keep = "true" *) wire [4:0]  vt_ff_usr_cmnd_2;
	(* syn_keep = "true" *) wire [10:0] vt_ff_ba_cnt_2;
	(* syn_keep = "true" *) wire [6:0]  vt_ff_base_address_2;
	(* syn_keep = "true" *) wire [15:0] vt_ff_start_offset_2;
	(* syn_keep = "true" *) wire [10:0] vt_ff_n_minus_1_2;
	(* syn_keep = "true" *) wire [15:0] vt_cngf_reg_data_2;
	(* syn_keep = "true" *) wire [15:0] vt_count_mux_2;
	(* syn_keep = "true" *) wire [4:0]  vt_bcount_2;
	(* syn_keep = "true" *) wire [15:0] vt_count_2;
	(* syn_keep = "true" *) wire [15:0] vt_full_count_2;
	(* syn_keep = "true" *) wire [15:0] vt_rbk_count_2;
	(* syn_keep = "true" *) wire [15:0] vt_adr_offset_2;
	(* syn_keep = "true" *) wire [15:0] vt_bpi_status_r_2;   // FIFO status bits and latest value of the PROM status register. 
	(* syn_keep = "true" *) wire [31:0] vt_bpi_timer_r_2;    // General timer
	(* syn_keep = "true" *) wire [10:0] vt_bpi_cmd_cnt_2;       // words in FIFO
	(* syn_keep = "true" *) wire [10:0] vt_bpi_rbk_cnt_2;       // words in FIFO
	(* syn_keep = "true" *) wire [19:0] vt_parser_inactive_tmr_2;
	(* syn_keep = "true" *) wire vt_incr_tmr_2;
	(* syn_keep = "true" *) wire vt_bpi_enable_2;
	(* syn_keep = "true" *) wire vt_parser_active_2;
	(* syn_keep = "true" *) wire vt_parser_active_r_2;
	(* syn_keep = "true" *) wire vt_pe_in_suspense_2;

	(* syn_keep = "true" *) wire [1:0]  vt_read_mode_3;
	(* syn_keep = "true" *) wire [7:0]  vt_sr_reg_3;
	(* syn_keep = "true" *) wire [15:0] vt_esig_reg_3;
	(* syn_keep = "true" *) wire [15:0] vt_cfiq_reg_3;
	(* syn_keep = "true" *) wire [4:0]  vt_ff_usr_cmnd_3;
	(* syn_keep = "true" *) wire [10:0] vt_ff_ba_cnt_3;
	(* syn_keep = "true" *) wire [6:0]  vt_ff_base_address_3;
	(* syn_keep = "true" *) wire [15:0] vt_ff_start_offset_3;
	(* syn_keep = "true" *) wire [10:0] vt_ff_n_minus_1_3;
	(* syn_keep = "true" *) wire [15:0] vt_cngf_reg_data_3;
	(* syn_keep = "true" *) wire [15:0] vt_count_mux_3;
	(* syn_keep = "true" *) wire [4:0]  vt_bcount_3;
	(* syn_keep = "true" *) wire [15:0] vt_count_3;
	(* syn_keep = "true" *) wire [15:0] vt_full_count_3;
	(* syn_keep = "true" *) wire [15:0] vt_rbk_count_3;
	(* syn_keep = "true" *) wire [15:0] vt_adr_offset_3;
	(* syn_keep = "true" *) wire [15:0] vt_bpi_status_r_3;   // FIFO status bits and latest value of the PROM status register. 
	(* syn_keep = "true" *) wire [31:0] vt_bpi_timer_r_3;    // General timer
	(* syn_keep = "true" *) wire [10:0] vt_bpi_cmd_cnt_3;       // words in FIFO
	(* syn_keep = "true" *) wire [10:0] vt_bpi_rbk_cnt_3;       // words in FIFO
	(* syn_keep = "true" *) wire [19:0] vt_parser_inactive_tmr_3;
	(* syn_keep = "true" *) wire vt_incr_tmr_3;
	(* syn_keep = "true" *) wire vt_bpi_enable_3;
	(* syn_keep = "true" *) wire vt_parser_active_3;
	(* syn_keep = "true" *) wire vt_parser_active_r_3;
	(* syn_keep = "true" *) wire vt_pe_in_suspense_3;

  assign vt_read_mode_1           = (read_mode_1           & read_mode_2          ) | (read_mode_2           & read_mode_3          ) | (read_mode_1           & read_mode_3          ); // Majority logic
  assign vt_sr_reg_1              = (sr_reg_1              & sr_reg_2             ) | (sr_reg_2              & sr_reg_3             ) | (sr_reg_1              & sr_reg_3             ); // Majority logic
  assign vt_esig_reg_1            = (esig_reg_1            & esig_reg_2           ) | (esig_reg_2            & esig_reg_3           ) | (esig_reg_1            & esig_reg_3           ); // Majority logic
  assign vt_cfiq_reg_1            = (cfiq_reg_1            & cfiq_reg_2           ) | (cfiq_reg_2            & cfiq_reg_3           ) | (cfiq_reg_1            & cfiq_reg_3           ); // Majority logic
  assign vt_ff_usr_cmnd_1         = (ff_usr_cmnd_1         & ff_usr_cmnd_2        ) | (ff_usr_cmnd_2         & ff_usr_cmnd_3        ) | (ff_usr_cmnd_1         & ff_usr_cmnd_3        ); // Majority logic
  assign vt_ff_ba_cnt_1           = (ff_ba_cnt_1           & ff_ba_cnt_2          ) | (ff_ba_cnt_2           & ff_ba_cnt_3          ) | (ff_ba_cnt_1           & ff_ba_cnt_3          ); // Majority logic
  assign vt_ff_base_address_1     = (ff_base_address_1     & ff_base_address_2    ) | (ff_base_address_2     & ff_base_address_3    ) | (ff_base_address_1     & ff_base_address_3    ); // Majority logic
  assign vt_ff_start_offset_1     = (ff_start_offset_1     & ff_start_offset_2    ) | (ff_start_offset_2     & ff_start_offset_3    ) | (ff_start_offset_1     & ff_start_offset_3    ); // Majority logic
  assign vt_ff_n_minus_1_1        = (ff_n_minus_1_1        & ff_n_minus_1_2       ) | (ff_n_minus_1_2        & ff_n_minus_1_3       ) | (ff_n_minus_1_1        & ff_n_minus_1_3       ); // Majority logic
  assign vt_cngf_reg_data_1       = (cngf_reg_data_1       & cngf_reg_data_2      ) | (cngf_reg_data_2       & cngf_reg_data_3      ) | (cngf_reg_data_1       & cngf_reg_data_3      ); // Majority logic
  assign vt_count_mux_1           = (count_mux_1           & count_mux_2          ) | (count_mux_2           & count_mux_3          ) | (count_mux_1           & count_mux_3          ); // Majority logic
  assign vt_bcount_1              = (bcount_1              & bcount_2             ) | (bcount_2              & bcount_3             ) | (bcount_1              & bcount_3             ); // Majority logic
  assign vt_count_1               = (count_1               & count_2              ) | (count_2               & count_3              ) | (count_1               & count_3              ); // Majority logic
  assign vt_full_count_1          = (full_count_1          & full_count_2         ) | (full_count_2          & full_count_3         ) | (full_count_1          & full_count_3         ); // Majority logic
  assign vt_rbk_count_1           = (rbk_count_1           & rbk_count_2          ) | (rbk_count_2           & rbk_count_3          ) | (rbk_count_1           & rbk_count_3          ); // Majority logic
  assign vt_adr_offset_1          = (adr_offset_1          & adr_offset_2         ) | (adr_offset_2          & adr_offset_3         ) | (adr_offset_1          & adr_offset_3         ); // Majority logic
  assign vt_bpi_status_r_1        = (bpi_status_r_1        & bpi_status_r_2       ) | (bpi_status_r_2        & bpi_status_r_3       ) | (bpi_status_r_1        & bpi_status_r_3       ); // Majority logic
  assign vt_bpi_timer_r_1         = (bpi_timer_r_1         & bpi_timer_r_2        ) | (bpi_timer_r_2         & bpi_timer_r_3        ) | (bpi_timer_r_1         & bpi_timer_r_3        ); // Majority logic
  assign vt_bpi_cmd_cnt_1         = (bpi_cmd_cnt_1         & bpi_cmd_cnt_2        ) | (bpi_cmd_cnt_2         & bpi_cmd_cnt_3        ) | (bpi_cmd_cnt_1         & bpi_cmd_cnt_3        ); // Majority logic
  assign vt_bpi_rbk_cnt_1         = (bpi_rbk_cnt_1         & bpi_rbk_cnt_2        ) | (bpi_rbk_cnt_2         & bpi_rbk_cnt_3        ) | (bpi_rbk_cnt_1         & bpi_rbk_cnt_3        ); // Majority logic
  assign vt_parser_inactive_tmr_1 = (parser_inactive_tmr_1 & parser_inactive_tmr_2) | (parser_inactive_tmr_2 & parser_inactive_tmr_3) | (parser_inactive_tmr_1 & parser_inactive_tmr_3); // Majority logic
  assign vt_incr_tmr_1            = (incr_tmr_1            & incr_tmr_2           ) | (incr_tmr_2            & incr_tmr_3           ) | (incr_tmr_1            & incr_tmr_3           ); // Majority logic
  assign vt_bpi_enable_1          = (bpi_enable_1          & bpi_enable_2         ) | (bpi_enable_2          & bpi_enable_3         ) | (bpi_enable_1          & bpi_enable_3         ); // Majority logic
  assign vt_parser_active_1       = (parser_active_1       & parser_active_2      ) | (parser_active_2       & parser_active_3      ) | (parser_active_1       & parser_active_3      ); // Majority logic
  assign vt_parser_active_r_1     = (parser_active_r_1     & parser_active_r_2    ) | (parser_active_r_2     & parser_active_r_3    ) | (parser_active_r_1     & parser_active_r_3    ); // Majority logic
  assign vt_pe_in_suspense_1      = (pe_in_suspense_1      & pe_in_suspense_2     ) | (pe_in_suspense_2      & pe_in_suspense_3     ) | (pe_in_suspense_1      & pe_in_suspense_3     ); // Majority logic

  assign vt_read_mode_2           = (read_mode_1           & read_mode_2          ) | (read_mode_2           & read_mode_3          ) | (read_mode_1           & read_mode_3          ); // Majority logic
  assign vt_sr_reg_2              = (sr_reg_1              & sr_reg_2             ) | (sr_reg_2              & sr_reg_3             ) | (sr_reg_1              & sr_reg_3             ); // Majority logic
  assign vt_esig_reg_2            = (esig_reg_1            & esig_reg_2           ) | (esig_reg_2            & esig_reg_3           ) | (esig_reg_1            & esig_reg_3           ); // Majority logic
  assign vt_cfiq_reg_2            = (cfiq_reg_1            & cfiq_reg_2           ) | (cfiq_reg_2            & cfiq_reg_3           ) | (cfiq_reg_1            & cfiq_reg_3           ); // Majority logic
  assign vt_ff_usr_cmnd_2         = (ff_usr_cmnd_1         & ff_usr_cmnd_2        ) | (ff_usr_cmnd_2         & ff_usr_cmnd_3        ) | (ff_usr_cmnd_1         & ff_usr_cmnd_3        ); // Majority logic
  assign vt_ff_ba_cnt_2           = (ff_ba_cnt_1           & ff_ba_cnt_2          ) | (ff_ba_cnt_2           & ff_ba_cnt_3          ) | (ff_ba_cnt_1           & ff_ba_cnt_3          ); // Majority logic
  assign vt_ff_base_address_2     = (ff_base_address_1     & ff_base_address_2    ) | (ff_base_address_2     & ff_base_address_3    ) | (ff_base_address_1     & ff_base_address_3    ); // Majority logic
  assign vt_ff_start_offset_2     = (ff_start_offset_1     & ff_start_offset_2    ) | (ff_start_offset_2     & ff_start_offset_3    ) | (ff_start_offset_1     & ff_start_offset_3    ); // Majority logic
  assign vt_ff_n_minus_1_2        = (ff_n_minus_1_1        & ff_n_minus_1_2       ) | (ff_n_minus_1_2        & ff_n_minus_1_3       ) | (ff_n_minus_1_1        & ff_n_minus_1_3       ); // Majority logic
  assign vt_cngf_reg_data_2       = (cngf_reg_data_1       & cngf_reg_data_2      ) | (cngf_reg_data_2       & cngf_reg_data_3      ) | (cngf_reg_data_1       & cngf_reg_data_3      ); // Majority logic
  assign vt_count_mux_2           = (count_mux_1           & count_mux_2          ) | (count_mux_2           & count_mux_3          ) | (count_mux_1           & count_mux_3          ); // Majority logic
  assign vt_bcount_2              = (bcount_1              & bcount_2             ) | (bcount_2              & bcount_3             ) | (bcount_1              & bcount_3             ); // Majority logic
  assign vt_count_2               = (count_1               & count_2              ) | (count_2               & count_3              ) | (count_1               & count_3              ); // Majority logic
  assign vt_full_count_2          = (full_count_1          & full_count_2         ) | (full_count_2          & full_count_3         ) | (full_count_1          & full_count_3         ); // Majority logic
  assign vt_rbk_count_2           = (rbk_count_1           & rbk_count_2          ) | (rbk_count_2           & rbk_count_3          ) | (rbk_count_1           & rbk_count_3          ); // Majority logic
  assign vt_adr_offset_2          = (adr_offset_1          & adr_offset_2         ) | (adr_offset_2          & adr_offset_3         ) | (adr_offset_1          & adr_offset_3         ); // Majority logic
  assign vt_bpi_status_r_2        = (bpi_status_r_1        & bpi_status_r_2       ) | (bpi_status_r_2        & bpi_status_r_3       ) | (bpi_status_r_1        & bpi_status_r_3       ); // Majority logic
  assign vt_bpi_timer_r_2         = (bpi_timer_r_1         & bpi_timer_r_2        ) | (bpi_timer_r_2         & bpi_timer_r_3        ) | (bpi_timer_r_1         & bpi_timer_r_3        ); // Majority logic
  assign vt_bpi_cmd_cnt_2         = (bpi_cmd_cnt_1         & bpi_cmd_cnt_2        ) | (bpi_cmd_cnt_2         & bpi_cmd_cnt_3        ) | (bpi_cmd_cnt_1         & bpi_cmd_cnt_3        ); // Majority logic
  assign vt_bpi_rbk_cnt_2         = (bpi_rbk_cnt_1         & bpi_rbk_cnt_2        ) | (bpi_rbk_cnt_2         & bpi_rbk_cnt_3        ) | (bpi_rbk_cnt_1         & bpi_rbk_cnt_3        ); // Majority logic
  assign vt_parser_inactive_tmr_2 = (parser_inactive_tmr_1 & parser_inactive_tmr_2) | (parser_inactive_tmr_2 & parser_inactive_tmr_3) | (parser_inactive_tmr_1 & parser_inactive_tmr_3); // Majority logic
  assign vt_incr_tmr_2            = (incr_tmr_1            & incr_tmr_2           ) | (incr_tmr_2            & incr_tmr_3           ) | (incr_tmr_1            & incr_tmr_3           ); // Majority logic
  assign vt_bpi_enable_2          = (bpi_enable_1          & bpi_enable_2         ) | (bpi_enable_2          & bpi_enable_3         ) | (bpi_enable_1          & bpi_enable_3         ); // Majority logic
  assign vt_parser_active_2       = (parser_active_1       & parser_active_2      ) | (parser_active_2       & parser_active_3      ) | (parser_active_1       & parser_active_3      ); // Majority logic
  assign vt_parser_active_r_2     = (parser_active_r_1     & parser_active_r_2    ) | (parser_active_r_2     & parser_active_r_3    ) | (parser_active_r_1     & parser_active_r_3    ); // Majority logic
  assign vt_pe_in_suspense_2      = (pe_in_suspense_1      & pe_in_suspense_2     ) | (pe_in_suspense_2      & pe_in_suspense_3     ) | (pe_in_suspense_1      & pe_in_suspense_3     ); // Majority logic

  assign vt_read_mode_3           = (read_mode_1           & read_mode_2          ) | (read_mode_2           & read_mode_3          ) | (read_mode_1           & read_mode_3          ); // Majority logic
  assign vt_sr_reg_3              = (sr_reg_1              & sr_reg_2             ) | (sr_reg_2              & sr_reg_3             ) | (sr_reg_1              & sr_reg_3             ); // Majority logic
  assign vt_esig_reg_3            = (esig_reg_1            & esig_reg_2           ) | (esig_reg_2            & esig_reg_3           ) | (esig_reg_1            & esig_reg_3           ); // Majority logic
  assign vt_cfiq_reg_3            = (cfiq_reg_1            & cfiq_reg_2           ) | (cfiq_reg_2            & cfiq_reg_3           ) | (cfiq_reg_1            & cfiq_reg_3           ); // Majority logic
  assign vt_ff_usr_cmnd_3         = (ff_usr_cmnd_1         & ff_usr_cmnd_2        ) | (ff_usr_cmnd_2         & ff_usr_cmnd_3        ) | (ff_usr_cmnd_1         & ff_usr_cmnd_3        ); // Majority logic
  assign vt_ff_ba_cnt_3           = (ff_ba_cnt_1           & ff_ba_cnt_2          ) | (ff_ba_cnt_2           & ff_ba_cnt_3          ) | (ff_ba_cnt_1           & ff_ba_cnt_3          ); // Majority logic
  assign vt_ff_base_address_3     = (ff_base_address_1     & ff_base_address_2    ) | (ff_base_address_2     & ff_base_address_3    ) | (ff_base_address_1     & ff_base_address_3    ); // Majority logic
  assign vt_ff_start_offset_3     = (ff_start_offset_1     & ff_start_offset_2    ) | (ff_start_offset_2     & ff_start_offset_3    ) | (ff_start_offset_1     & ff_start_offset_3    ); // Majority logic
  assign vt_ff_n_minus_1_3        = (ff_n_minus_1_1        & ff_n_minus_1_2       ) | (ff_n_minus_1_2        & ff_n_minus_1_3       ) | (ff_n_minus_1_1        & ff_n_minus_1_3       ); // Majority logic
  assign vt_cngf_reg_data_3       = (cngf_reg_data_1       & cngf_reg_data_2      ) | (cngf_reg_data_2       & cngf_reg_data_3      ) | (cngf_reg_data_1       & cngf_reg_data_3      ); // Majority logic
  assign vt_count_mux_3           = (count_mux_1           & count_mux_2          ) | (count_mux_2           & count_mux_3          ) | (count_mux_1           & count_mux_3          ); // Majority logic
  assign vt_bcount_3              = (bcount_1              & bcount_2             ) | (bcount_2              & bcount_3             ) | (bcount_1              & bcount_3             ); // Majority logic
  assign vt_count_3               = (count_1               & count_2              ) | (count_2               & count_3              ) | (count_1               & count_3              ); // Majority logic
  assign vt_full_count_3          = (full_count_1          & full_count_2         ) | (full_count_2          & full_count_3         ) | (full_count_1          & full_count_3         ); // Majority logic
  assign vt_rbk_count_3           = (rbk_count_1           & rbk_count_2          ) | (rbk_count_2           & rbk_count_3          ) | (rbk_count_1           & rbk_count_3          ); // Majority logic
  assign vt_adr_offset_3          = (adr_offset_1          & adr_offset_2         ) | (adr_offset_2          & adr_offset_3         ) | (adr_offset_1          & adr_offset_3         ); // Majority logic
  assign vt_bpi_status_r_3        = (bpi_status_r_1        & bpi_status_r_2       ) | (bpi_status_r_2        & bpi_status_r_3       ) | (bpi_status_r_1        & bpi_status_r_3       ); // Majority logic
  assign vt_bpi_timer_r_3         = (bpi_timer_r_1         & bpi_timer_r_2        ) | (bpi_timer_r_2         & bpi_timer_r_3        ) | (bpi_timer_r_1         & bpi_timer_r_3        ); // Majority logic
  assign vt_bpi_cmd_cnt_3         = (bpi_cmd_cnt_1         & bpi_cmd_cnt_2        ) | (bpi_cmd_cnt_2         & bpi_cmd_cnt_3        ) | (bpi_cmd_cnt_1         & bpi_cmd_cnt_3        ); // Majority logic
  assign vt_bpi_rbk_cnt_3         = (bpi_rbk_cnt_1         & bpi_rbk_cnt_2        ) | (bpi_rbk_cnt_2         & bpi_rbk_cnt_3        ) | (bpi_rbk_cnt_1         & bpi_rbk_cnt_3        ); // Majority logic
  assign vt_parser_inactive_tmr_3 = (parser_inactive_tmr_1 & parser_inactive_tmr_2) | (parser_inactive_tmr_2 & parser_inactive_tmr_3) | (parser_inactive_tmr_1 & parser_inactive_tmr_3); // Majority logic
  assign vt_incr_tmr_3            = (incr_tmr_1            & incr_tmr_2           ) | (incr_tmr_2            & incr_tmr_3           ) | (incr_tmr_1            & incr_tmr_3           ); // Majority logic
  assign vt_bpi_enable_3          = (bpi_enable_1          & bpi_enable_2         ) | (bpi_enable_2          & bpi_enable_3         ) | (bpi_enable_1          & bpi_enable_3         ); // Majority logic
  assign vt_parser_active_3       = (parser_active_1       & parser_active_2      ) | (parser_active_2       & parser_active_3      ) | (parser_active_1       & parser_active_3      ); // Majority logic
  assign vt_parser_active_r_3     = (parser_active_r_1     & parser_active_r_2    ) | (parser_active_r_2     & parser_active_r_3    ) | (parser_active_r_1     & parser_active_r_3    ); // Majority logic
  assign vt_pe_in_suspense_3      = (pe_in_suspense_1      & pe_in_suspense_2     ) | (pe_in_suspense_2      & pe_in_suspense_3     ) | (pe_in_suspense_1      & pe_in_suspense_3     ); // Majority logic

	//nets that could be replicated
	(* syn_keep = "true" *) reg  cnt_cmd_1;
	(* syn_keep = "true" *) reg  local_1;
	(* syn_keep = "true" *) wire ld_n32_1;
	(* syn_keep = "true" *) wire ld_remainder_1;
	(* syn_keep = "true" *) wire [4:0] n_minus_1_1;
	(* syn_keep = "true" *) wire [15:0] ncnt_1;
	(* syn_keep = "true" *) wire clr_error_bits_1;
	(* syn_keep = "true" *) wire rst_tmr_1;
	(* syn_keep = "true" *) wire bpi_rbk_wena_1;
	(* syn_keep = "true" *) wire usr_read_req_1;
	(* syn_keep = "true" *) wire [4:0]  usr_cmnd_1;
	(* syn_keep = "true" *) wire p_tmr_rst_1;
	(* syn_keep = "true" *) wire trl_edge_pa_1;
	(* syn_keep = "true" *) wire ff_load_offset_1;
	(* syn_keep = "true" *) wire start_tmr_1;
	(* syn_keep = "true" *) wire stop_tmr_1;
	(* syn_keep = "true" *) wire [15:0] start_offset_1;
	(* syn_keep = "true" *) wire load_offset_1;

	(* syn_keep = "true" *) reg  cnt_cmd_2;
	(* syn_keep = "true" *) reg  local_2;
	(* syn_keep = "true" *) wire ld_n32_2;
	(* syn_keep = "true" *) wire ld_remainder_2;
	(* syn_keep = "true" *) wire [4:0] n_minus_1_2;
	(* syn_keep = "true" *) wire [15:0] ncnt_2;
	(* syn_keep = "true" *) wire clr_error_bits_2;
	(* syn_keep = "true" *) wire rst_tmr_2;
	(* syn_keep = "true" *) wire bpi_rbk_wena_2;
	(* syn_keep = "true" *) wire usr_read_req_2;
	(* syn_keep = "true" *) wire [4:0]  usr_cmnd_2;
	(* syn_keep = "true" *) wire p_tmr_rst_2;
	(* syn_keep = "true" *) wire trl_edge_pa_2;
	(* syn_keep = "true" *) wire ff_load_offset_2;
	(* syn_keep = "true" *) wire start_tmr_2;
	(* syn_keep = "true" *) wire stop_tmr_2;
	(* syn_keep = "true" *) wire [15:0] start_offset_2;
	(* syn_keep = "true" *) wire load_offset_2;

	(* syn_keep = "true" *) reg  cnt_cmd_3;
	(* syn_keep = "true" *) reg  local_3;
	(* syn_keep = "true" *) wire ld_n32_3;
	(* syn_keep = "true" *) wire ld_remainder_3;
	(* syn_keep = "true" *) wire [4:0] n_minus_1_3;
	(* syn_keep = "true" *) wire [15:0] ncnt_3;
	(* syn_keep = "true" *) wire clr_error_bits_3;
	(* syn_keep = "true" *) wire rst_tmr_3;
	(* syn_keep = "true" *) wire bpi_rbk_wena_3;
	(* syn_keep = "true" *) wire usr_read_req_3;
	(* syn_keep = "true" *) wire [4:0]  usr_cmnd_3;
	(* syn_keep = "true" *) wire p_tmr_rst_3;
	(* syn_keep = "true" *) wire trl_edge_pa_3;
	(* syn_keep = "true" *) wire ff_load_offset_3;
	(* syn_keep = "true" *) wire start_tmr_3;
	(* syn_keep = "true" *) wire stop_tmr_3;
	(* syn_keep = "true" *) wire [15:0] start_offset_3;
	(* syn_keep = "true" *) wire load_offset_3;

	assign pec_busy = (check_PEC || check_buf) && !vt_sr_reg_1[7];
	assign usr_cmnd_1     = csp_ctrl ? csp_usr_cmnd     : ((enable_cmd && !local_1) ? vt_ff_usr_cmnd_1 : 5'h00);
	assign usr_cmnd_2     = csp_ctrl ? csp_usr_cmnd     : ((enable_cmd && !local_2) ? vt_ff_usr_cmnd_2 : 5'h00);
	assign usr_cmnd_3     = csp_ctrl ? csp_usr_cmnd     : ((enable_cmd && !local_3) ? vt_ff_usr_cmnd_3 : 5'h00);
	assign ff_load_offset_1 = enable_cmd && (vt_ff_usr_cmnd_1 == Load_Address);
	assign ff_load_offset_2 = enable_cmd && (vt_ff_usr_cmnd_2 == Load_Address);
	assign ff_load_offset_3 = enable_cmd && (vt_ff_usr_cmnd_3 == Load_Address);
	assign start_tmr_1      = enable_cmd && (vt_ff_usr_cmnd_1 == Start_Timer);
	assign start_tmr_2      = enable_cmd && (vt_ff_usr_cmnd_2 == Start_Timer);
	assign start_tmr_3      = enable_cmd && (vt_ff_usr_cmnd_3 == Start_Timer);
	assign stop_tmr_1       = enable_cmd && (vt_ff_usr_cmnd_1 == Stop_Timer);
	assign stop_tmr_2       = enable_cmd && (vt_ff_usr_cmnd_2 == Stop_Timer);
	assign stop_tmr_3       = enable_cmd && (vt_ff_usr_cmnd_3 == Stop_Timer);
	assign rst_tmr_1        = enable_cmd && (vt_ff_usr_cmnd_1 == Reset_Timer);
	assign rst_tmr_2        = enable_cmd && (vt_ff_usr_cmnd_2 == Reset_Timer);
	assign rst_tmr_3        = enable_cmd && (vt_ff_usr_cmnd_3 == Reset_Timer);
	assign clr_error_bits_1 = enable_cmd && (vt_ff_usr_cmnd_1 == Clr_BPI_Status);
	assign clr_error_bits_2 = enable_cmd && (vt_ff_usr_cmnd_2 == Clr_BPI_Status);
	assign clr_error_bits_3 = enable_cmd && (vt_ff_usr_cmnd_3 == Clr_BPI_Status);
	assign base_address = csp_ctrl ? csp_base_address : vt_ff_base_address_1;
	assign start_offset_1 = csp_ctrl ? csp_start_offset : vt_ff_start_offset_1;
	assign start_offset_2 = csp_ctrl ? csp_start_offset : vt_ff_start_offset_2;
	assign start_offset_3 = csp_ctrl ? csp_start_offset : vt_ff_start_offset_3;
	assign n_minus_1_1  = csp_ctrl ? (csp_ncnt[4:0]-1): vt_ff_n_minus_1_1[4:0];
	assign n_minus_1_2  = csp_ctrl ? (csp_ncnt[4:0]-1): vt_ff_n_minus_1_2[4:0];
	assign n_minus_1_3  = csp_ctrl ? (csp_ncnt[4:0]-1): vt_ff_n_minus_1_3[4:0];
	assign ncnt_1       = csp_ctrl ? csp_ncnt         : vt_ff_n_minus_1_1 + 1;
	assign ncnt_2       = csp_ctrl ? csp_ncnt         : vt_ff_n_minus_1_2 + 1;
	assign ncnt_3       = csp_ctrl ? csp_ncnt         : vt_ff_n_minus_1_3 + 1;
	assign ld_n32_1     = |vt_full_count_1[15:5];
	assign ld_n32_2     = |vt_full_count_2[15:5];
	assign ld_n32_3     = |vt_full_count_3[15:5];
	assign ld_remainder_1 = !ld_n32_1;
	assign ld_remainder_2 = !ld_n32_2;
	assign ld_remainder_3 = !ld_n32_3;
	assign term_cnt = (vt_count_1 == 16'h0000);
	assign loop_done = (vt_full_count_1 == 16'h0000);
	assign pra_offset = vt_adr_offset_1[8:0];
	assign trl_edge_pa_1  = ~vt_parser_active_r_1 & vt_parser_active_r_1;
	assign trl_edge_pa_2  = ~vt_parser_active_r_2 & vt_parser_active_r_2;
	assign trl_edge_pa_3  = ~vt_parser_active_r_3 & vt_parser_active_r_3;
	assign p_tmr_rst_1    = RST || ~parser_idle || trl_edge_pa_1;
	assign p_tmr_rst_2    = RST || ~parser_idle || trl_edge_pa_2;
	assign p_tmr_rst_3    = RST || ~parser_idle || trl_edge_pa_3;
	assign usr_read_req_1 = (usr_cmnd_1 == Read_1) || (usr_cmnd_1 == Read_n);
	assign usr_read_req_2 = (usr_cmnd_2 == Read_1) || (usr_cmnd_2 == Read_n);
	assign usr_read_req_3 = (usr_cmnd_3 == Read_1) || (usr_cmnd_3 == Read_n);
	assign bpi_rbk_wena_1 = usr_read_req_1 && BPI_LOAD_DATA;
	assign bpi_rbk_wena_2 = usr_read_req_2 && BPI_LOAD_DATA;
	assign bpi_rbk_wena_3 = usr_read_req_3 && BPI_LOAD_DATA;
	assign load_offset_1  = csp_load_offset || ff_load_offset_1;
	assign load_offset_2  = csp_load_offset || ff_load_offset_2;
	assign load_offset_3  = csp_load_offset || ff_load_offset_3;

	assign BPI_STATUS = vt_bpi_status_r_1;
	assign BPI_TIMER  = vt_bpi_timer_r_1;
	assign BPI_RBK_WRD_CNT = vt_bpi_rbk_cnt_1;
	assign BPI_ACTIVE   = csp_ctrl || csp_fifo_src || vt_parser_active_1;

	assign read_mode_i     = vt_read_mode_1;
	assign sr_reg_i        = vt_sr_reg_1;
	assign esig_reg_i      = vt_esig_reg_1;
	assign cfiq_reg_i      = vt_cfiq_reg_1;
	assign cngf_reg_data_i = vt_cngf_reg_data_1;
	assign bcount_i        = vt_bcount_1;
	assign rbk_count_i     = vt_rbk_count_1;
	assign adr_offset_i    = vt_adr_offset_1;
	assign bpi_cmd_cnt_i   = vt_bpi_cmd_cnt_1;
	assign bpi_enable_i    = vt_bpi_enable_1;
	assign parser_active_i = vt_parser_active_1;
	assign cnt_cmd_i       = cnt_cmd_1;
	assign local_i         = local_1;
	assign bpi_rbk_wena_i  = bpi_rbk_wena_1;
	assign usr_read_req_i  = usr_read_req_1;
	assign usr_cmnd_i      = usr_cmnd_1;


	always @* begin
		case(vt_ff_usr_cmnd_1)
			Read_1, Read_Array, Read_Status_Reg, Read_Elec_Sig, Read_CFI_Qry, Clr_Status_Reg, Block_Erase,
			PE_Susp, PE_Resume, Block_Lock, Block_UnLock, Block_Lock_Down, Blank_Check:
						pass   = 1;
			default: pass   = 0;
		endcase
		case(vt_ff_usr_cmnd_1)
			Program, Prot_Reg_Prog, Set_Cnfg_Reg:
						has_data   = 1;
			default: has_data   = 0;
		endcase
		case(vt_ff_usr_cmnd_1)
			Load_Address, Program, Prot_Reg_Prog, Set_Cnfg_Reg:
						xtra_word   = 1;
			default: xtra_word   = 0;
		endcase
		case(vt_ff_usr_cmnd_1) //-> rep
			Read_n, Buffer_Program:
						cnt_cmd_1   = 1;
			default: cnt_cmd_1   = 0;
		endcase
		case(vt_ff_usr_cmnd_2) //-> rep
			Read_n, Buffer_Program:
						cnt_cmd_2   = 1;
			default: cnt_cmd_2   = 0;
		endcase
		case(vt_ff_usr_cmnd_3) //-> rep
			Read_n, Buffer_Program:
						cnt_cmd_3   = 1;
			default: cnt_cmd_3   = 0;
		endcase
		case(vt_ff_usr_cmnd_1) // -> rep
			Load_Address, Start_Timer, Stop_Timer, Reset_Timer, Clr_BPI_Status:
						local_1   = 1;
			default: local_1   = 0;
		endcase
		case(vt_ff_usr_cmnd_2) // -> rep
			Load_Address, Start_Timer, Stop_Timer, Reset_Timer, Clr_BPI_Status:
						local_2   = 1;
			default: local_2   = 0;
		endcase
		case(vt_ff_usr_cmnd_3) // -> rep
			Load_Address, Start_Timer, Stop_Timer, Reset_Timer, Clr_BPI_Status:
						local_3   = 1;
			default: local_3   = 0;
		endcase
	end

	always @(posedge CLK)
	begin
		case(command)
			Read_Array       : read_mode_1 <= Rd_Array;
			Read_Status_Reg  : read_mode_1 <= Rd_SR;
			Read_Elec_Sig    : read_mode_1 <= Rd_ESig;
			Read_CFI_Qry     : read_mode_1 <= Rd_CFIQ;
			Block_Erase,
			Program,
			Buffer_Program,
			Buf_Prog_Conf,
			PE_Susp,
			Prot_Reg_Prog,
			Set_Cnfg_Reg,
			Blank_Check      : read_mode_1 <= Rd_SR;
			default          : read_mode_1 <= vt_read_mode_1;  //no change
		endcase
		case(command)
			Read_Array       : read_mode_2 <= Rd_Array;
			Read_Status_Reg  : read_mode_2 <= Rd_SR;
			Read_Elec_Sig    : read_mode_2 <= Rd_ESig;
			Read_CFI_Qry     : read_mode_2 <= Rd_CFIQ;
			Block_Erase,
			Program,
			Buffer_Program,
			Buf_Prog_Conf,
			PE_Susp,
			Prot_Reg_Prog,
			Set_Cnfg_Reg,
			Blank_Check      : read_mode_2 <= Rd_SR;
			default          : read_mode_2 <= vt_read_mode_2;  //no change
		endcase
		case(command)
			Read_Array       : read_mode_3 <= Rd_Array;
			Read_Status_Reg  : read_mode_3 <= Rd_SR;
			Read_Elec_Sig    : read_mode_3 <= Rd_ESig;
			Read_CFI_Qry     : read_mode_3 <= Rd_CFIQ;
			Block_Erase,
			Program,
			Buffer_Program,
			Buf_Prog_Conf,
			PE_Susp,
			Prot_Reg_Prog,
			Set_Cnfg_Reg,
			Blank_Check      : read_mode_3 <= Rd_SR;
			default          : read_mode_3 <= vt_read_mode_3;  //no change
		endcase
	end

	always @(posedge CLK)
	begin
		if(BPI_LOAD_DATA ) begin
			sr_reg_1     <= (vt_read_mode_1 == Rd_SR)   ? BPI_DATA_FROM[7:0] : vt_sr_reg_1;
			sr_reg_2     <= (vt_read_mode_2 == Rd_SR)   ? BPI_DATA_FROM[7:0] : vt_sr_reg_2;
			sr_reg_3     <= (vt_read_mode_3 == Rd_SR)   ? BPI_DATA_FROM[7:0] : vt_sr_reg_3;
			esig_reg_1   <= (vt_read_mode_1 == Rd_ESig) ? BPI_DATA_FROM      : vt_esig_reg_1;
			esig_reg_2   <= (vt_read_mode_2 == Rd_ESig) ? BPI_DATA_FROM      : vt_esig_reg_2;
			esig_reg_3   <= (vt_read_mode_3 == Rd_ESig) ? BPI_DATA_FROM      : vt_esig_reg_3;
			cfiq_reg_1   <= (vt_read_mode_1 == Rd_CFIQ) ? BPI_DATA_FROM      : vt_cfiq_reg_1;
			cfiq_reg_2   <= (vt_read_mode_2 == Rd_CFIQ) ? BPI_DATA_FROM      : vt_cfiq_reg_2;
			cfiq_reg_3   <= (vt_read_mode_3 == Rd_CFIQ) ? BPI_DATA_FROM      : vt_cfiq_reg_3;
		end
	end

	always @(posedge CLK)
	begin
		parser_active_r_1 <= vt_parser_active_1;
		parser_active_r_2 <= vt_parser_active_2;
		parser_active_r_3 <= vt_parser_active_3;
		ff_usr_cmnd_1     <= ld_usr ? data_fifo[4:0]  : vt_ff_usr_cmnd_1;
		ff_usr_cmnd_2     <= ld_usr ? data_fifo[4:0]  : vt_ff_usr_cmnd_2;
		ff_usr_cmnd_3     <= ld_usr ? data_fifo[4:0]  : vt_ff_usr_cmnd_3;
		ff_ba_cnt_1       <= ld_usr ? data_fifo[15:5] : vt_ff_ba_cnt_1;
		ff_ba_cnt_2       <= ld_usr ? data_fifo[15:5] : vt_ff_ba_cnt_2;
		ff_ba_cnt_3       <= ld_usr ? data_fifo[15:5] : vt_ff_ba_cnt_3;
		ff_base_address_1 <= ((vt_ff_usr_cmnd_1 == Load_Address) && decode && !bpi_cmd_mt) ? vt_ff_ba_cnt_1[6:0] : vt_ff_base_address_1;
		ff_base_address_2 <= ((vt_ff_usr_cmnd_2 == Load_Address) && decode && !bpi_cmd_mt) ? vt_ff_ba_cnt_2[6:0] : vt_ff_base_address_2;
		ff_base_address_3 <= ((vt_ff_usr_cmnd_3 == Load_Address) && decode && !bpi_cmd_mt) ? vt_ff_ba_cnt_3[6:0] : vt_ff_base_address_3;
		ff_start_offset_1 <= ((vt_ff_usr_cmnd_1 == Load_Address) && decode && !bpi_cmd_mt) ? data_fifo      : vt_ff_start_offset_1;
		ff_start_offset_2 <= ((vt_ff_usr_cmnd_2 == Load_Address) && decode && !bpi_cmd_mt) ? data_fifo      : vt_ff_start_offset_2;
		ff_start_offset_3 <= ((vt_ff_usr_cmnd_3 == Load_Address) && decode && !bpi_cmd_mt) ? data_fifo      : vt_ff_start_offset_3;
		cngf_reg_data_1   <= ((vt_ff_usr_cmnd_1 == Set_Cnfg_Reg) && decode && !bpi_cmd_mt) ? data_fifo      : (set_asynch ? CRD_ASync : vt_cngf_reg_data_1);
		cngf_reg_data_2   <= ((vt_ff_usr_cmnd_2 == Set_Cnfg_Reg) && decode && !bpi_cmd_mt) ? data_fifo      : (set_asynch ? CRD_ASync : vt_cngf_reg_data_2);
		cngf_reg_data_3   <= ((vt_ff_usr_cmnd_3 == Set_Cnfg_Reg) && decode && !bpi_cmd_mt) ? data_fifo      : (set_asynch ? CRD_ASync : vt_cngf_reg_data_3);
		ff_n_minus_1_1    <= (cnt_cmd_1 && decode)   ? vt_ff_ba_cnt_1      : vt_ff_n_minus_1_1;
		ff_n_minus_1_2    <= (cnt_cmd_2 && decode)   ? vt_ff_ba_cnt_2      : vt_ff_n_minus_1_2;
		ff_n_minus_1_3    <= (cnt_cmd_3 && decode)   ? vt_ff_ba_cnt_3      : vt_ff_n_minus_1_3;
		incr_tmr_1        <= (stop_tmr_1 || rst_tmr_1) ? 0              : (start_tmr_1      ? 1              : vt_incr_tmr_1);
		incr_tmr_2        <= (stop_tmr_2 || rst_tmr_2) ? 0              : (start_tmr_2      ? 1              : vt_incr_tmr_2);
		incr_tmr_3        <= (stop_tmr_3 || rst_tmr_3) ? 0              : (start_tmr_3      ? 1              : vt_incr_tmr_3);
	end

	always @(posedge CLK)
	begin
		if(ld_cnts && ld_n32_1) begin
			count_mux_1 <= 16'h0020;
			bcount_1 <= 5'h1F;
		end
		else if(ld_cnts && ld_remainder_1) begin
			count_mux_1 <= vt_full_count_1;
			bcount_1 <= n_minus_1_1[4:0];
		end
		else if((ld_full && (vt_ff_usr_cmnd_1 == Read_n)) || csp_load_count) begin
			count_mux_1 <= ncnt_1;
			bcount_1 <= n_minus_1_1[4:0];
		end
		else begin
			count_mux_1 <= vt_count_mux_1;
			bcount_1 <= vt_bcount_1;
		end
		//
		if(ld_cnts && ld_n32_2) begin
			count_mux_2 <= 16'h0020;
			bcount_2 <= 5'h1F;
		end
		else if(ld_cnts && ld_remainder_2) begin
			count_mux_2 <= vt_full_count_2;
			bcount_2 <= n_minus_1_2[4:0];
		end
		else if((ld_full && (vt_ff_usr_cmnd_2 == Read_n)) || csp_load_count) begin
			count_mux_2 <= ncnt_2;
			bcount_2 <= n_minus_1_2[4:0];
		end
		else begin
			count_mux_2 <= vt_count_mux_2;
			bcount_2 <= vt_bcount_2;
		end
		//
		if(ld_cnts && ld_n32_3) begin
			count_mux_3 <= 16'h0020;
			bcount_3 <= 5'h1F;
		end
		else if(ld_cnts && ld_remainder_3) begin
			count_mux_3 <= vt_full_count_3;
			bcount_3 <= n_minus_1_3[4:0];
		end
		else if((ld_full && (vt_ff_usr_cmnd_3 == Read_n)) || csp_load_count) begin
			count_mux_3 <= ncnt_3;
			bcount_3 <= n_minus_1_3[4:0];
		end
		else begin
			count_mux_3 <= vt_count_mux_3;
			bcount_3 <= vt_bcount_3;
		end
	end

	always @(posedge CLK or posedge RST)
	begin
		if(RST) begin
			count_1          <= 16'h0000;
			count_2          <= 16'h0000;
			count_3          <= 16'h0000;
			full_count_1     <= 16'h0000;
			full_count_2     <= 16'h0000;
			full_count_3     <= 16'h0000;
			adr_offset_1     <= 16'h0000;
			adr_offset_2     <= 16'h0000;
			adr_offset_3     <= 16'h0000;
			parser_active_1  <= 1'b0;
			parser_active_2  <= 1'b0;
			parser_active_3  <= 1'b0;
			bpi_cmd_cnt_1    <= 11'h000;
			bpi_cmd_cnt_2    <= 11'h000;
			bpi_cmd_cnt_3    <= 11'h000;
			bpi_rbk_cnt_1    <= 11'h000;
			bpi_rbk_cnt_2    <= 11'h000;
			bpi_rbk_cnt_3    <= 11'h000;
			pe_in_suspense_1 <= 0;
			pe_in_suspense_2 <= 0;
			pe_in_suspense_3 <= 0;
			bpi_enable_1     <= 0;
			bpi_enable_2     <= 0;
			bpi_enable_3     <= 0;
			bpi_status_r_1   <= 16'h0000;
			bpi_status_r_2   <= 16'h0000;
			bpi_status_r_3   <= 16'h0000;
		end
		else begin
			count_1         <= load_n                      ? vt_count_mux_1 : (decr ? vt_count_1 - 1      : vt_count_1     );
			count_2         <= load_n                      ? vt_count_mux_2 : (decr ? vt_count_2 - 1      : vt_count_2     );
			count_3         <= load_n                      ? vt_count_mux_3 : (decr ? vt_count_3 - 1      : vt_count_3     );
			full_count_1    <= (ld_full || csp_load_count) ? ncnt_1         : (decr ? vt_full_count_1 - 1 : vt_full_count_1);
			full_count_2    <= (ld_full || csp_load_count) ? ncnt_2         : (decr ? vt_full_count_2 - 1 : vt_full_count_2);
			full_count_3    <= (ld_full || csp_load_count) ? ncnt_3         : (decr ? vt_full_count_3 - 1 : vt_full_count_3);
			adr_offset_1    <= load_offset_1               ? start_offset_1 : (next ? vt_adr_offset_1 + 1 : vt_adr_offset_1);
			adr_offset_2    <= load_offset_2               ? start_offset_2 : (next ? vt_adr_offset_2 + 1 : vt_adr_offset_2);
			adr_offset_3    <= load_offset_3               ? start_offset_3 : (next ? vt_adr_offset_3 + 1 : vt_adr_offset_3);
			parser_active_1 <= ~parser_idle                ? 1'b1           : ((vt_parser_inactive_tmr_1 == 20'h7A120) ? 1'b0 : vt_parser_active_1);
			parser_active_2 <= ~parser_idle                ? 1'b1           : ((vt_parser_inactive_tmr_2 == 20'h7A120) ? 1'b0 : vt_parser_active_2);
			parser_active_3 <= ~parser_idle                ? 1'b1           : ((vt_parser_inactive_tmr_3 == 20'h7A120) ? 1'b0 : vt_parser_active_3);
			casex ({bpi_cmd_mt,bpi_cmd_full,bpi_wrena,bpi_rdena})// Command FIFO word counter
			  4'b01x1,4'b0001:  bpi_cmd_cnt_1 <= vt_bpi_cmd_cnt_1 - 1;  // count down
			  4'b101x,4'b0010:  bpi_cmd_cnt_1 <= vt_bpi_cmd_cnt_1 + 1;  // count up
			  default:          bpi_cmd_cnt_1 <= vt_bpi_cmd_cnt_1;      // hold
			endcase
			casex ({bpi_cmd_mt,bpi_cmd_full,bpi_wrena,bpi_rdena})// Command FIFO word counter
			  4'b01x1,4'b0001:  bpi_cmd_cnt_2 <= vt_bpi_cmd_cnt_2 - 1;  // count down
			  4'b101x,4'b0010:  bpi_cmd_cnt_2 <= vt_bpi_cmd_cnt_2 + 1;  // count up
			  default:          bpi_cmd_cnt_2 <= vt_bpi_cmd_cnt_2;      // hold
			endcase
			casex ({bpi_cmd_mt,bpi_cmd_full,bpi_wrena,bpi_rdena})// Command FIFO word counter
			  4'b01x1,4'b0001:  bpi_cmd_cnt_3 <= vt_bpi_cmd_cnt_3 - 1;  // count down
			  4'b101x,4'b0010:  bpi_cmd_cnt_3 <= vt_bpi_cmd_cnt_3 + 1;  // count up
			  default:          bpi_cmd_cnt_3 <= vt_bpi_cmd_cnt_3;      // hold
			endcase
			casex ({bpi_rbk_mt,bpi_rbk_full,bpi_rbk_wena_1,BPI_RE})// Readback FIFO word counter
			  4'b01x1,4'b0001:  bpi_rbk_cnt_1 <= vt_bpi_rbk_cnt_1 - 1;  // count down
			  4'b101x,4'b0010:  bpi_rbk_cnt_1 <= vt_bpi_rbk_cnt_1 + 1;  // count up
			  default:          bpi_rbk_cnt_1 <= vt_bpi_rbk_cnt_1;      // hold
			endcase
			casex ({bpi_rbk_mt,bpi_rbk_full,bpi_rbk_wena_2,BPI_RE})// Readback FIFO word counter
			  4'b01x1,4'b0001:  bpi_rbk_cnt_2 <= vt_bpi_rbk_cnt_2 - 1;  // count down
			  4'b101x,4'b0010:  bpi_rbk_cnt_2 <= vt_bpi_rbk_cnt_2 + 1;  // count up
			  default:          bpi_rbk_cnt_2 <= vt_bpi_rbk_cnt_2;      // hold
			endcase
			casex ({bpi_rbk_mt,bpi_rbk_full,bpi_rbk_wena_3,BPI_RE})// Readback FIFO word counter
			  4'b01x1,4'b0001:  bpi_rbk_cnt_3 <= vt_bpi_rbk_cnt_3 - 1;  // count down
			  4'b101x,4'b0010:  bpi_rbk_cnt_3 <= vt_bpi_rbk_cnt_3 + 1;  // count up
			  default:          bpi_rbk_cnt_3 <= vt_bpi_rbk_cnt_3;      // hold
			endcase
			case(usr_cmnd_1)
				PE_Susp:         pe_in_suspense_1 <= (check_stat) && |(vt_sr_reg_1 & 8'h44);
				PE_Resume:       pe_in_suspense_1 <= 0;
				default:         pe_in_suspense_1 <= vt_pe_in_suspense_1;
			endcase
			case(usr_cmnd_2)
				PE_Susp:         pe_in_suspense_2 <= (check_stat) && |(vt_sr_reg_2 & 8'h44);
				PE_Resume:       pe_in_suspense_2 <= 0;
				default:         pe_in_suspense_2 <= vt_pe_in_suspense_2;
			endcase
			case(usr_cmnd_3)
				PE_Susp:         pe_in_suspense_3 <= (check_stat) && |(vt_sr_reg_3 & 8'h44);
				PE_Resume:       pe_in_suspense_3 <= 0;
				default:         pe_in_suspense_3 <= vt_pe_in_suspense_3;
			endcase
			
			if(csp_fifo_src)
				if(csp_bpi_enbl)
					bpi_enable_1 <= 1;
				else if(csp_bpi_dsbl)
					bpi_enable_1 <= 0;
				else
					bpi_enable_1 <= vt_bpi_enable_1;
			else
				if(BPI_ENBL)
					bpi_enable_1 <= 1;
				else if(BPI_DSBL)
					bpi_enable_1 <= 0;
				else
					bpi_enable_1 <= vt_bpi_enable_1;
			//
			if(csp_fifo_src)
				if(csp_bpi_enbl)
					bpi_enable_2 <= 1;
				else if(csp_bpi_dsbl)
					bpi_enable_2 <= 0;
				else
					bpi_enable_2 <= vt_bpi_enable_2;
			else
				if(BPI_ENBL)
					bpi_enable_2 <= 1;
				else if(BPI_DSBL)
					bpi_enable_2 <= 0;
				else
					bpi_enable_2 <= vt_bpi_enable_2;
			//
			if(csp_fifo_src)
				if(csp_bpi_enbl)
					bpi_enable_3 <= 1;
				else if(csp_bpi_dsbl)
					bpi_enable_3 <= 0;
				else
					bpi_enable_3 <= vt_bpi_enable_3;
			else
				if(BPI_ENBL)
					bpi_enable_3 <= 1;
				else if(BPI_DSBL)
					bpi_enable_3 <= 0;
				else
					bpi_enable_3 <= vt_bpi_enable_3;
			
			if(ld_status)
				bpi_status_r_1 <= {bpi_rbk_mt, bpi_rbk_full, bpi_rbk_rderr | vt_bpi_status_r_1[13], bpi_rbk_wrterr | vt_bpi_status_r_1[12], bpi_cmd_mt, bpi_cmd_full, bpi_rderr | vt_bpi_status_r_1[9], bpi_wrterr | vt_bpi_status_r_1[8], vt_sr_reg_1};
			else if(clr_error_bits_1)
				bpi_status_r_1 <= {bpi_rbk_mt, bpi_rbk_full, 1'b0, 1'b0,bpi_cmd_mt, bpi_cmd_full, 1'b0, 1'b0,vt_sr_reg_1[7:6],3'b000,vt_sr_reg_1[2],1'b0,vt_sr_reg_1[0]};
			else
				bpi_status_r_1 <= {bpi_rbk_mt, bpi_rbk_full, bpi_rbk_rderr | vt_bpi_status_r_1[13], bpi_rbk_wrterr | vt_bpi_status_r_1[12], bpi_cmd_mt, bpi_cmd_full, bpi_rderr | vt_bpi_status_r_1[9], bpi_wrterr | vt_bpi_status_r_1[8], vt_sr_reg_1[7:6], vt_bpi_status_r_1[5:3], vt_sr_reg_1[2], vt_bpi_status_r_1[1], vt_sr_reg_1[0]};
			//
			if(ld_status)
				bpi_status_r_2 <= {bpi_rbk_mt, bpi_rbk_full, bpi_rbk_rderr | vt_bpi_status_r_2[13], bpi_rbk_wrterr | vt_bpi_status_r_2[12], bpi_cmd_mt, bpi_cmd_full, bpi_rderr | vt_bpi_status_r_2[9], bpi_wrterr | vt_bpi_status_r_2[8], vt_sr_reg_2};
			else if(clr_error_bits_2)
				bpi_status_r_2 <= {bpi_rbk_mt, bpi_rbk_full, 1'b0, 1'b0,bpi_cmd_mt, bpi_cmd_full, 1'b0, 1'b0,vt_sr_reg_2[7:6],3'b000,vt_sr_reg_2[2],1'b0,vt_sr_reg_2[0]};
			else
				bpi_status_r_2 <= {bpi_rbk_mt, bpi_rbk_full, bpi_rbk_rderr | vt_bpi_status_r_2[13], bpi_rbk_wrterr | vt_bpi_status_r_2[12], bpi_cmd_mt, bpi_cmd_full, bpi_rderr | vt_bpi_status_r_2[9], bpi_wrterr | vt_bpi_status_r_2[8], vt_sr_reg_2[7:6], vt_bpi_status_r_2[5:3], vt_sr_reg_2[2], vt_bpi_status_r_2[1], vt_sr_reg_2[0]};
			//
			if(ld_status)
				bpi_status_r_3 <= {bpi_rbk_mt, bpi_rbk_full, bpi_rbk_rderr | vt_bpi_status_r_3[13], bpi_rbk_wrterr | vt_bpi_status_r_3[12], bpi_cmd_mt, bpi_cmd_full, bpi_rderr | vt_bpi_status_r_3[9], bpi_wrterr | vt_bpi_status_r_3[8], vt_sr_reg_3};
			else if(clr_error_bits_3)
				bpi_status_r_3 <= {bpi_rbk_mt, bpi_rbk_full, 1'b0, 1'b0,bpi_cmd_mt, bpi_cmd_full, 1'b0, 1'b0,vt_sr_reg_3[7:6],3'b000,vt_sr_reg_3[2],1'b0,vt_sr_reg_3[0]};
			else
				bpi_status_r_3 <= {bpi_rbk_mt, bpi_rbk_full, bpi_rbk_rderr | vt_bpi_status_r_3[13], bpi_rbk_wrterr | vt_bpi_status_r_3[12], bpi_cmd_mt, bpi_cmd_full, bpi_rderr | vt_bpi_status_r_3[9], bpi_wrterr | vt_bpi_status_r_3[8], vt_sr_reg_3[7:6], vt_bpi_status_r_3[5:3], vt_sr_reg_3[2], vt_bpi_status_r_3[1], vt_sr_reg_3[0]};
		end
	end

	always @(posedge CLK or posedge rbk_cnt_rst)
	begin
		if(rbk_cnt_rst) begin
			rbk_count_1 <= 16'h0000;
			rbk_count_2 <= 16'h0000;
			rbk_count_3 <= 16'h0000;
		end
		else begin
			rbk_count_1 <= (next && (vt_read_mode_1 == Rd_Array)) ? vt_rbk_count_1 + 1 : vt_rbk_count_1;
			rbk_count_2 <= (next && (vt_read_mode_2 == Rd_Array)) ? vt_rbk_count_2 + 1 : vt_rbk_count_2;
			rbk_count_3 <= (next && (vt_read_mode_3 == Rd_Array)) ? vt_rbk_count_3 + 1 : vt_rbk_count_3;
		end
	end

	always @(posedge CLK1MHZ or posedge rst_tmr_1)
	begin
		if(rst_tmr_1)	begin
			bpi_timer_r_1 <= 32'h00000000;
		end
		else begin
			bpi_timer_r_1 <= vt_incr_tmr_1 ? vt_bpi_timer_r_1 + 1 : vt_bpi_timer_r_1;
		end
	end

	always @(posedge CLK1MHZ or posedge rst_tmr_2)
	begin
		if(rst_tmr_2)	begin
			bpi_timer_r_2 <= 32'h00000000;
		end
		else begin
			bpi_timer_r_2 <= vt_incr_tmr_2 ? vt_bpi_timer_r_2 + 1 : vt_bpi_timer_r_2;
		end
	end

	always @(posedge CLK1MHZ or posedge rst_tmr_3)
	begin
		if(rst_tmr_3)	begin
			bpi_timer_r_3 <= 32'h00000000;
		end
		else begin
			bpi_timer_r_3 <= vt_incr_tmr_3 ? vt_bpi_timer_r_3 + 1 : vt_bpi_timer_r_3;
		end
	end

	always @(posedge CLK1MHZ or posedge p_tmr_rst_1)
	begin
		if(p_tmr_rst_1) begin
			parser_inactive_tmr_1 <= 20'h00000;
		end
		else begin
			parser_inactive_tmr_1 <= (vt_parser_active_1 && parser_idle) ? vt_parser_inactive_tmr_1 + 1 : vt_parser_inactive_tmr_1;
		end
	end

	always @(posedge CLK1MHZ or posedge p_tmr_rst_2)
	begin
		if(p_tmr_rst_2) begin
			parser_inactive_tmr_2 <= 20'h00000;
		end
		else begin
			parser_inactive_tmr_2 <= (vt_parser_active_2 && parser_idle) ? vt_parser_inactive_tmr_2 + 1 : vt_parser_inactive_tmr_2;
		end
	end

	always @(posedge CLK1MHZ or posedge p_tmr_rst_3)
	begin
		if(p_tmr_rst_3) begin
			parser_inactive_tmr_3 <= 20'h00000;
		end
		else begin
			parser_inactive_tmr_3 <= (vt_parser_active_3 && parser_idle) ? vt_parser_inactive_tmr_3 + 1 : vt_parser_inactive_tmr_3;
		end
	end

end
else 
begin : BPI_logic

	reg [1:0]  read_mode = 2'b00;
	reg [7:0]  sr_reg;
	reg [15:0] esig_reg;
	reg [15:0] cfiq_reg;
	reg [4:0]  ff_usr_cmnd;
	reg [10:0] ff_ba_cnt;
	reg [6:0]  ff_base_address;
	reg [15:0] ff_start_offset;
	reg [10:0] ff_n_minus_1;
	reg [15:0] cngf_reg_data;
	reg [15:0] count_mux;
	reg [4:0]  bcount;
	reg [15:0] count;
	reg [15:0] full_count;
	reg [15:0] rbk_count;
	reg [15:0] adr_offset;
	reg [15:0] bpi_status_r;   // FIFO status bits and latest value of the PROM status register. 
	reg [31:0] bpi_timer_r;    // General timer
	reg [10:0] bpi_cmd_cnt;       // words in FIFO
	reg [10:0] bpi_rbk_cnt;       // words in FIFO
	reg [19:0] parser_inactive_tmr;
	reg incr_tmr;
	reg bpi_enable;
	reg parser_active;
	reg parser_active_r;
	reg pe_in_suspense;


	//nets that could be replicated
	reg  cnt_cmd;
	reg  local;
	wire ld_n32;
	wire ld_remainder;
	wire [4:0] n_minus_1;
	wire [15:0] ncnt;
	wire clr_error_bits;
	wire rst_tmr;
	wire bpi_rbk_wena;
	wire usr_read_req;
	wire [4:0]  usr_cmnd;
	wire p_tmr_rst;
	wire trl_edge_pa;
	wire ff_load_offset;
	wire start_tmr;
	wire stop_tmr;
	wire [15:0] start_offset;
	wire load_offset;

	assign pec_busy = (check_PEC || check_buf) && !sr_reg[7];
	assign usr_cmnd     = csp_ctrl ? csp_usr_cmnd     : ((enable_cmd && !local) ? ff_usr_cmnd : 5'h00);
	assign ff_load_offset = enable_cmd && (ff_usr_cmnd == Load_Address);
	assign start_tmr      = enable_cmd && (ff_usr_cmnd == Start_Timer);
	assign stop_tmr       = enable_cmd && (ff_usr_cmnd == Stop_Timer);
	assign rst_tmr        = enable_cmd && (ff_usr_cmnd == Reset_Timer);
	assign clr_error_bits = enable_cmd && (ff_usr_cmnd == Clr_BPI_Status);
	assign base_address = csp_ctrl ? csp_base_address : ff_base_address;
	assign start_offset = csp_ctrl ? csp_start_offset : ff_start_offset;
	assign n_minus_1    = csp_ctrl ? (csp_ncnt[4:0]-1): ff_n_minus_1[4:0];
	assign ncnt         = csp_ctrl ? csp_ncnt         : ff_n_minus_1 + 1;
	assign ld_n32       = |full_count[15:5];
	assign ld_remainder = !ld_n32;
	assign term_cnt = (count == 16'h0000);
	assign loop_done = (full_count == 16'h0000);
	assign pra_offset = adr_offset[8:0];
	assign trl_edge_pa  = ~parser_active & parser_active_r;
	assign p_tmr_rst    = RST || ~parser_idle || trl_edge_pa;
	assign usr_read_req = (usr_cmnd == Read_1) || (usr_cmnd == Read_n);
	assign bpi_rbk_wena = usr_read_req && BPI_LOAD_DATA;
	assign load_offset  = csp_load_offset || ff_load_offset;

	assign BPI_STATUS = bpi_status_r;
	assign BPI_TIMER  = bpi_timer_r;
	assign BPI_RBK_WRD_CNT = bpi_rbk_cnt;
	assign BPI_ACTIVE   = csp_ctrl || csp_fifo_src || parser_active;

	assign read_mode_i     = read_mode;
	assign sr_reg_i        = sr_reg;
	assign esig_reg_i      = esig_reg;
	assign cfiq_reg_i      = cfiq_reg;
	assign cngf_reg_data_i = cngf_reg_data;
	assign bcount_i        = bcount;
	assign rbk_count_i     = rbk_count;
	assign adr_offset_i    = adr_offset;
	assign bpi_cmd_cnt_i   = bpi_cmd_cnt;
	assign bpi_enable_i    = bpi_enable;
	assign parser_active_i = parser_active;
	assign cnt_cmd_i       = cnt_cmd;
	assign local_i         = local;
	assign bpi_rbk_wena_i  = bpi_rbk_wena;
	assign usr_read_req_i  = usr_read_req;
	assign usr_cmnd_i      = usr_cmnd;

	always @* begin
		case(ff_usr_cmnd)
			Read_1, Read_Array, Read_Status_Reg, Read_Elec_Sig, Read_CFI_Qry, Clr_Status_Reg, Block_Erase,
			PE_Susp, PE_Resume, Block_Lock, Block_UnLock, Block_Lock_Down, Blank_Check:
						pass   = 1;
			default: pass   = 0;
		endcase
		case(ff_usr_cmnd)
			Program, Prot_Reg_Prog, Set_Cnfg_Reg:
						has_data   = 1;
			default: has_data   = 0;
		endcase
		case(ff_usr_cmnd)
			Load_Address, Program, Prot_Reg_Prog, Set_Cnfg_Reg:
						xtra_word   = 1;
			default: xtra_word   = 0;
		endcase
		case(ff_usr_cmnd) //-> rep
			Read_n, Buffer_Program:
						cnt_cmd   = 1;
			default: cnt_cmd   = 0;
		endcase
		case(ff_usr_cmnd) // -> rep
			Load_Address, Start_Timer, Stop_Timer, Reset_Timer, Clr_BPI_Status:
						local   = 1;
			default: local   = 0;
		endcase
	end

	always @(posedge CLK)
	begin
		case(command)
			Read_Array       : read_mode <= Rd_Array;
			Read_Status_Reg  : read_mode <= Rd_SR;
			Read_Elec_Sig    : read_mode <= Rd_ESig;
			Read_CFI_Qry     : read_mode <= Rd_CFIQ;
			Block_Erase,
			Program,
			Buffer_Program,
			Buf_Prog_Conf,
			PE_Susp,
			Prot_Reg_Prog,
			Set_Cnfg_Reg,
			Blank_Check      : read_mode <= Rd_SR;
			default          : read_mode <= read_mode;  //no change
		endcase
	end

	always @(posedge CLK)
	begin
		if(BPI_LOAD_DATA ) begin
			sr_reg     <= (read_mode == Rd_SR)   ? BPI_DATA_FROM[7:0] : sr_reg;
			esig_reg   <= (read_mode == Rd_ESig) ? BPI_DATA_FROM      : esig_reg;
			cfiq_reg   <= (read_mode == Rd_CFIQ) ? BPI_DATA_FROM      : cfiq_reg;
		end
	end

	always @(posedge CLK)
	begin
		parser_active_r <= parser_active;
		ff_usr_cmnd     <= ld_usr ? data_fifo[4:0]  : ff_usr_cmnd;
		ff_ba_cnt       <= ld_usr ? data_fifo[15:5] : ff_ba_cnt;
		ff_base_address <= ((ff_usr_cmnd == Load_Address) && decode && !bpi_cmd_mt) ? ff_ba_cnt[6:0] : ff_base_address;
		ff_start_offset <= ((ff_usr_cmnd == Load_Address) && decode && !bpi_cmd_mt) ? data_fifo      : ff_start_offset;
		cngf_reg_data   <= ((ff_usr_cmnd == Set_Cnfg_Reg) && decode && !bpi_cmd_mt) ? data_fifo      : (set_asynch ? CRD_ASync : cngf_reg_data);
		ff_n_minus_1    <= (cnt_cmd && decode)   ? ff_ba_cnt      : ff_n_minus_1;
		incr_tmr        <= (stop_tmr || rst_tmr) ? 0              : (start_tmr      ? 1              : incr_tmr);
	end

	always @(posedge CLK)
	begin
		if(ld_cnts && ld_n32) begin
			count_mux <= 16'h0020;
			bcount <= 5'h1F;
		end
		else if(ld_cnts && ld_remainder) begin
			count_mux <= full_count;
			bcount <= n_minus_1[4:0];
		end
		else if((ld_full && (ff_usr_cmnd == Read_n)) || csp_load_count) begin
			count_mux <= ncnt;
			bcount <= n_minus_1[4:0];
		end
		else begin
			count_mux <= count_mux;
			bcount <= bcount;
		end
	end

	always @(posedge CLK or posedge RST)
	begin
		if(RST) begin
			count          <= 16'h0000;
			full_count     <= 16'h0000;
			adr_offset     <= 16'h0000;
			parser_active  <= 1'b0;
			bpi_cmd_cnt    <= 11'h000;
			bpi_rbk_cnt    <= 11'h000;
			pe_in_suspense <= 0;
			bpi_enable     <= 0;
			bpi_status_r   <= 16'h0000;
		end
		else begin
			count         <= load_n                      ? count_mux    : (decr ? count - 1      : count     );
			full_count    <= (ld_full || csp_load_count) ? ncnt         : (decr ? full_count - 1 : full_count);
			adr_offset    <= load_offset                 ? start_offset : (next ? adr_offset + 1 : adr_offset);
			parser_active <= ~parser_idle                ? 1'b1         : ((parser_inactive_tmr == 20'h7A120) ? 1'b0 : parser_active);
			casex ({bpi_cmd_mt,bpi_cmd_full,bpi_wrena,bpi_rdena})// Command FIFO word counter
			  4'b01x1,4'b0001:  bpi_cmd_cnt <= bpi_cmd_cnt - 1;  // count down
			  4'b101x,4'b0010:  bpi_cmd_cnt <= bpi_cmd_cnt + 1;  // count up
			  default:          bpi_cmd_cnt <= bpi_cmd_cnt;      // hold
			endcase
			casex ({bpi_rbk_mt,bpi_rbk_full,bpi_rbk_wena,BPI_RE})// Readback FIFO word counter
			  4'b01x1,4'b0001:  bpi_rbk_cnt <= bpi_rbk_cnt - 1;  // count down
			  4'b101x,4'b0010:  bpi_rbk_cnt <= bpi_rbk_cnt + 1;  // count up
			  default:          bpi_rbk_cnt <= bpi_rbk_cnt;      // hold
			endcase
			case(usr_cmnd)
				PE_Susp:         pe_in_suspense <= (check_stat) && |(sr_reg & 8'h44);
				PE_Resume:       pe_in_suspense <= 0;
				default:         pe_in_suspense <= pe_in_suspense;
			endcase
			if(csp_fifo_src)
				if(csp_bpi_enbl)
					bpi_enable <= 1;
				else if(csp_bpi_dsbl)
					bpi_enable <= 0;
				else
					bpi_enable <= bpi_enable;
			else
				if(BPI_ENBL)
					bpi_enable <= 1;
				else if(BPI_DSBL)
					bpi_enable <= 0;
				else
					bpi_enable <= bpi_enable;
			if(ld_status)
				bpi_status_r <= {bpi_rbk_mt, bpi_rbk_full, bpi_rbk_rderr | bpi_status_r[13], bpi_rbk_wrterr | bpi_status_r[12], bpi_cmd_mt, bpi_cmd_full, bpi_rderr | bpi_status_r[9], bpi_wrterr | bpi_status_r[8], sr_reg};
			else if(clr_error_bits)
				bpi_status_r <= {bpi_rbk_mt, bpi_rbk_full, 1'b0, 1'b0,bpi_cmd_mt, bpi_cmd_full, 1'b0, 1'b0,sr_reg[7:6],3'b000,sr_reg[2],1'b0,sr_reg[0]};
			else
				bpi_status_r <= {bpi_rbk_mt, bpi_rbk_full, bpi_rbk_rderr | bpi_status_r[13], bpi_rbk_wrterr | bpi_status_r[12], bpi_cmd_mt, bpi_cmd_full, bpi_rderr | bpi_status_r[9], bpi_wrterr | bpi_status_r[8], sr_reg[7:6], bpi_status_r[5:3], sr_reg[2], bpi_status_r[1], sr_reg[0]};
		end
	end

	always @(posedge CLK or posedge rbk_cnt_rst)
	begin
		if(rbk_cnt_rst) begin
			rbk_count <= 16'h0000;
		end
		else begin
			rbk_count <= (next && (read_mode == Rd_Array)) ? rbk_count + 1 : rbk_count;
		end
	end

	always @(posedge CLK1MHZ or posedge rst_tmr)
	begin
		if(rst_tmr)	begin
			bpi_timer_r <= 32'h00000000;
		end
		else begin
			bpi_timer_r <= incr_tmr ? bpi_timer_r + 1 : bpi_timer_r;
		end
	end

	always @(posedge CLK1MHZ or posedge p_tmr_rst)
	begin
		if(p_tmr_rst) begin
			parser_inactive_tmr <= 20'h00000;
		end
		else begin
			parser_inactive_tmr <= (parser_active && parser_idle) ? parser_inactive_tmr + 1 : parser_inactive_tmr;
		end
	end
	
end
endgenerate

	//
	// BPI Command FIFO  (holds commands to be executed -- either local or for the BPI PROM)
	//                    disable the parsing of commands while FIFO is being filled
	//                    16 bits wide by 2048 words deep
	// ECC protected FIFO
   //

	BPI_FIFO BPI_CMD_FIFO_i (
	  .clk(CLK), // input clk
	  .rst(BPI_FIFO_RST), // input rst
	  .din(bpi_wrt_data), // input [15 : 0] din
	  .wr_en(bpi_wrena), // input wr_en
	  .rd_en(bpi_rdena), // input rd_en
	  .dout(data_fifo), // output [15 : 0] dout
	  .full(bpi_cmd_full), // output full
	  .overflow(bpi_wrterr), // output overflow
	  .empty(bpi_cmd_mt), // output empty
	  .underflow(bpi_rderr), // output underflow
	  .sbiterr(sbitcmderr), // output sbiterr
	  .dbiterr(dbitcmderr) // output dbiterr
	);
	
	//
	// BPI Readback FIFO (holds data read back from the BPI PROM until read by VME)
	//                    16 bits wide by 2048 words deep
	// ECC protected FIFO
   //
	
	BPI_FIFO BPI_rbk_FIFO_data_i (
	  .clk(CLK), // input clk
	  .rst(BPI_FIFO_RST), // input rst
	  .din(BPI_DATA_FROM), // input [15 : 0] din
	  .wr_en(bpi_rbk_wena_i), // input wr_en
	  .rd_en(BPI_RE), // input rd_en
	  .dout(BPI_RBK_FIFO_DATA), // output [15 : 0] dout
	  .full(bpi_rbk_full), // output full
	  .overflow(bpi_rbk_wrterr), // output overflow
	  .empty(bpi_rbk_mt), // output empty
	  .underflow(bpi_rbk_rderr), // output underflow
	  .sbiterr(sbitrbkerr), // output sbiterr
	  .dbiterr(dbitrbkerr) // output dbiterr
	);


generate
if(TMR==1) 
begin : BPI_FSM_TMR
	BPI_cmd_parser_FSM_TMR
	BPI_cmd_parser_FSM_i(
		.ACK(fsm_ack),
		.DECODE(decode),
		.ENABLE_CMD(enable_cmd),
		.IDLE(parser_idle),
		.LD_CNTS(ld_cnts),
		.LD_FULL(ld_full),
		.LD_STATUS(ld_status),
		.LD_USR(ld_usr),
		.READ_FF(read_ff),
		.OUT_STATE(parse_state),
		//
		.BUF_PROG(buf_prog),
		.CLK(CLK),
		.CNT_CMD(cnt_cmd_i),
		.ENABLE(!csp_ctrl && bpi_enable_i),
		.DATA(has_data),
		.LOCAL(local_i),
		.LOOP_DONE(loop_done),
		.MT(bpi_cmd_mt),
		.PASS(pass),
		.READ_N(read_n),
		.RPT_ERROR(rpt_error),
		.RST(RST),
		.SEQR_IDLE(seqr_idle),
		.SEQ_CMPLT(seq_cmplt),
		.XTRA_WORD(xtra_word)
	);

	BPI_sequencer_FSM_TMR
	BPI_sequencer_FSM_i(
		.check_PEC(check_PEC),
		.check_buf(check_buf),
		.check_stat(check_stat),
		.cnfrm_lk(cnfrm_lk),
		.command(command),
		.read_es_state(read_es_state),
		.rpt_error(rpt_error),
		.seq_cmplt(seq_cmplt),
		.seqr_idle(seqr_idle),
		.set_asynch(set_asynch),
		.OUT_STATE(seq_state),
		.CLK(CLK),
		.RST(RST),
		.ack(ack),
		.buf_prog(buf_prog),
		.error(error),
		.lk_ok(lk_ok),
		.lk_unlk(lk_unlk),
		.noop_seq(noop_seq),
		.pec_busy(pec_busy),
		.seq_cmnd(seq_cmnd),
		.seq_done(seq_done),
		.simple_cmd(simple_cmd),
		.std_seq(std_seq)
	);

	BPI_ctrl_FSM_TMR
	BPI_ctrl_FSM_i(
		.CYCLE2(cycle2),
		.DECR(decr),
		.EXECUTE(BPI_EXECUTE),
		.LOAD_N(load_n),
		.NEXT(next),
		.SEQ_DONE(seq_done),
		.OUT_STATE(ctrl_state),
		//
		.BUSY(intf_busy),
		.CLK(CLK),
		.LD_DAT(BPI_LOAD_DATA),
		.MT(bpi_cmd_mt),
		.NOOP(noop),
		.OTHER(other),
		.RDY(intf_rdy),
		.READ_1(read_1),
		.READ_N(read_n),
		.RST(RST),
		.TERM_CNT(term_cnt),
		.TWO_CYCLE(two_cycle),
		.WRITE_N(write_n)
	);
end
else 
begin : BPI_FSM
	BPI_cmd_parser_FSM
	BPI_cmd_parser_FSM_i(
		.ACK(fsm_ack),
		.DECODE(decode),
		.ENABLE_CMD(enable_cmd),
		.IDLE(parser_idle),
		.LD_CNTS(ld_cnts),
		.LD_FULL(ld_full),
		.LD_STATUS(ld_status),
		.LD_USR(ld_usr),
		.READ_FF(read_ff),
		.OUT_STATE(parse_state),
		//
		.BUF_PROG(buf_prog),
		.CLK(CLK),
		.CNT_CMD(cnt_cmd_i),
		.ENABLE(!csp_ctrl && bpi_enable_i),
		.DATA(has_data),
		.LOCAL(local_i),
		.LOOP_DONE(loop_done),
		.MT(bpi_cmd_mt),
		.PASS(pass),
		.READ_N(read_n),
		.RPT_ERROR(rpt_error),
		.RST(RST),
		.SEQR_IDLE(seqr_idle),
		.SEQ_CMPLT(seq_cmplt),
		.XTRA_WORD(xtra_word)
	);

	BPI_sequencer_FSM
	BPI_sequencer_FSM_i(
		.check_PEC(check_PEC),
		.check_buf(check_buf),
		.check_stat(check_stat),
		.cnfrm_lk(cnfrm_lk),
		.command(command),
		.read_es_state(read_es_state),
		.rpt_error(rpt_error),
		.seq_cmplt(seq_cmplt),
		.seqr_idle(seqr_idle),
		.set_asynch(set_asynch),
		.OUT_STATE(seq_state),
		.CLK(CLK),
		.RST(RST),
		.ack(ack),
		.buf_prog(buf_prog),
		.error(error),
		.lk_ok(lk_ok),
		.lk_unlk(lk_unlk),
		.noop_seq(noop_seq),
		.pec_busy(pec_busy),
		.seq_cmnd(seq_cmnd),
		.seq_done(seq_done),
		.simple_cmd(simple_cmd),
		.std_seq(std_seq)
	);

	BPI_ctrl_FSM
	BPI_ctrl_FSM_i(
		.CYCLE2(cycle2),
		.DECR(decr),
		.EXECUTE(BPI_EXECUTE),
		.LOAD_N(load_n),
		.NEXT(next),
		.SEQ_DONE(seq_done),
		.OUT_STATE(ctrl_state),
		//
		.BUSY(intf_busy),
		.CLK(CLK),
		.LD_DAT(BPI_LOAD_DATA),
		.MT(bpi_cmd_mt),
		.NOOP(noop),
		.OTHER(other),
		.RDY(intf_rdy),
		.READ_1(read_1),
		.READ_N(read_n),
		.RST(RST),
		.TERM_CNT(term_cnt),
		.TWO_CYCLE(two_cycle),
		.WRITE_N(write_n)
	);
end
endgenerate

generate
if(USE_CHIPSCOPE==1) 
begin : chipscope_bpi
wire [127:0] bpi_vio_async_in;
wire [59:0]  bpi_vio_async_out;
wire [79:0] bpi_vio_sync_in;
wire [12:0]  bpi_vio_sync_out;
wire [163:0] bpi_la_data;
wire [7:0]  bpi_la_trig;

wire [3:0] dummy_asigs;
wire [3:0] dummy_ssigs;

	bpi_vio bpi_vio_i (
		 .CONTROL(BPI_VIO_CNTRL), // INOUT BUS [35:0]
		 .CLK(CLK),
		 .ASYNC_IN(bpi_vio_async_in), // IN BUS [127:0]
		 .ASYNC_OUT(bpi_vio_async_out), // OUT BUS [59:0]
		 .SYNC_IN(bpi_vio_sync_in), // IN BUS [79:0]
		 .SYNC_OUT(bpi_vio_sync_out) // OUT BUS [12:0]
	);


//		 ASYNC_IN [127:0]
	assign bpi_vio_async_in[127:0]     = {rbkbuf0,rbkbuf1,rbkbuf2,rbkbuf3,rbkbuf4,rbkbuf5,rbkbuf6,rbkbuf7};
		 
//		 ASYNC_OUT [59:0]
	assign csp_start_offset    = bpi_vio_async_out[15:0];
	assign csp_data            = bpi_vio_async_out[31:16];
	assign csp_ncnt            = bpi_vio_async_out[47:32];
	assign csp_base_address    = bpi_vio_async_out[54:48];
	assign csp_ctrl            = bpi_vio_async_out[55];
	assign csp_fifo_src        = bpi_vio_async_out[56];
	assign dummy_asigs[2:0]    = bpi_vio_async_out[59:57];

//		 SYNC_IN [79:0]
	assign bpi_vio_sync_in[4:0]     = seq_state; // seq_state
	assign bpi_vio_sync_in[9:5]     = command;
	assign bpi_vio_sync_in[10]      = rpt_error;
	assign bpi_vio_sync_in[11]      = seq_cmplt;
	assign bpi_vio_sync_in[12]      = error;
	assign bpi_vio_sync_in[22:13]   = bpi_cmd_cnt_i[9:0];
	assign bpi_vio_sync_in[23]      = bpi_cmd_mt;
	assign bpi_vio_sync_in[31:24]   = rbk_count_i[7:0];
	assign bpi_vio_sync_in[39:32]   = sr_reg_i;
	assign bpi_vio_sync_in[55:40]   = esig_reg_i;
	assign bpi_vio_sync_in[71:56]   = cfiq_reg_i;
	assign bpi_vio_sync_in[73:72]   = read_mode_i;
	assign bpi_vio_sync_in[74]      = bpi_enable_i;
	assign bpi_vio_sync_in[75]      = BPI_ACTIVE;
	assign bpi_vio_sync_in[76]      = parser_active_i;
	assign bpi_vio_sync_in[79:77]   = 3'b000;

//		 SYNC_OUT [12:0]
	assign csp_usr_cmnd        = bpi_vio_sync_out[4:0];
	assign csp_ack             = bpi_vio_sync_out[5];
	assign csp_bpi_wrena       = bpi_vio_sync_out[6];
	assign csp_rbk_cnt_rst     = bpi_vio_sync_out[7];
	assign csp_load_offset     = bpi_vio_sync_out[8];
	assign csp_man_rst         = bpi_vio_sync_out[9];
	assign csp_load_count      = bpi_vio_sync_out[10];
	assign csp_bpi_enbl        = bpi_vio_sync_out[11];
	assign csp_bpi_dsbl        = bpi_vio_sync_out[12];

	bpi_la bpi_la_i (
		 .CONTROL(BPI_LA_CNTRL),
		 .CLK(CLK),
		 .DATA(bpi_la_data), // IN BUS [163:0]
		 .TRIG0(bpi_la_trig) // IN BUS [7:0]
	);
	
// LA Data [163:0]
	assign bpi_la_data[4:0]    = seq_state; // seq_state
	assign bpi_la_data[9:5]    = command;
	assign bpi_la_data[10]     = rpt_error;
	assign bpi_la_data[11]     = seq_cmplt;
	assign bpi_la_data[12]     = check_PEC;
	assign bpi_la_data[13]     = check_buf;
	assign bpi_la_data[14]     = check_stat;
	assign bpi_la_data[15]     = cnfrm_lk;
	assign bpi_la_data[16]     = lk_ok;
	assign bpi_la_data[17]     = lk_unlk;
	assign bpi_la_data[18]     = noop_seq;
	assign bpi_la_data[19]     = buf_prog;
	assign bpi_la_data[20]     = simple_cmd;
	assign bpi_la_data[21]     = std_seq;
	assign bpi_la_data[22]     = seq_done;
	assign bpi_la_data[23]     = pec_busy;
	assign bpi_la_data[24]     = error;
	assign bpi_la_data[25]     = ack;
	assign bpi_la_data[27:26]  = read_mode_i;
	assign bpi_la_data[28]     = load_n;
	assign bpi_la_data[29]     = BPI_BUSY;
	assign bpi_la_data[30]     = BPI_EXECUTE;
	assign bpi_la_data[31]     = BPI_LOAD_DATA;
	assign bpi_la_data[47:32]  = BPI_DATA_FROM;
	assign bpi_la_data[63:48]  = BPI_DATA_TO;
	assign bpi_la_data[65:64]  = BPI_OP;
	assign bpi_la_data[88:66]  = BPI_ADDR;
	assign bpi_la_data[89]     = cycle2;
	assign bpi_la_data[90]     = decr;
	assign bpi_la_data[91]     = next;
	assign bpi_la_data[92]     = term_cnt;
	assign bpi_la_data[93]     = two_cycle;
	assign bpi_la_data[94]     = RST;
	assign bpi_la_data[95]     = read_n;
	assign bpi_la_data[99:96]  = ctrl_state;
	assign bpi_la_data[104:100]= usr_cmnd_i;
	assign bpi_la_data[120:105]= data_fifo;
	assign bpi_la_data[124:121]= parse_state;
	assign bpi_la_data[125]    = bpi_cmd_mt;
	assign bpi_la_data[126]    = bpi_rdena;
	assign bpi_la_data[127]    = bpi_wrena;
	assign bpi_la_data[143:128]= bpi_wrt_data;
	assign bpi_la_data[144]    = bpi_rbk_mt;
	assign bpi_la_data[145]    = usr_read_req_i;
	assign bpi_la_data[146]    = bpi_rbk_wena_i;
	assign bpi_la_data[147]    = BPI_RE;
	assign bpi_la_data[163:148]= BPI_RBK_FIFO_DATA;

// LA Trigger [7:0]
	assign bpi_la_trig[0]      = RST;
	assign bpi_la_trig[1]      = noop_seq;
	assign bpi_la_trig[2]      = BPI_EXECUTE;
	assign bpi_la_trig[3]      = bpi_rdena;
	assign bpi_la_trig[4]      = bpi_wrena;
	assign bpi_la_trig[5]      = bpi_rbk_mt;
	assign bpi_la_trig[6]      = bpi_rbk_wena_i;
	assign bpi_la_trig[7]      = BPI_RE;

end
else
begin : no_chipscope_bpi
	assign csp_start_offset    = 16'h0000;
	assign csp_data            = 16'h0000;
	assign csp_ncnt            = 16'h0000;
	assign csp_base_address    = 7'h00;
	assign csp_ctrl            = 0;
	assign csp_fifo_src        = 0;
	
	assign csp_usr_cmnd        = 5'h00;
	assign csp_ack             = 0;
	assign csp_bpi_wrena       = 0;
	assign csp_rbk_cnt_rst     = 0;
	assign csp_load_offset     = 0;
	assign csp_man_rst         = 0;
	assign csp_load_count      = 0;
	assign csp_bpi_enbl        = 0;
	assign csp_bpi_dsbl        = 0;
end
endgenerate


endmodule
