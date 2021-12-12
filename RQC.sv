
`timescale 1 ns / 10 ps
// Необходимо было изменить некоторые названия на ххх.
module kintex7_mcu_top
    #(
    parameter HARDWARE_ID           = 64'h0000_0000_0000_0051,                  // HARDWARE_ID
    parameter FIRMWARE_ID           = 64'h0000_0000_0000_0003,                  // FIRMWARE_ID
    parameter MGT115_PORTS          = 4,                                        // 4 ports for external devices in that bank
    parameter SFP_PORTS             = MGT115_PORTS,   				            // Max 4 ports for external devices total
	parameter PORTS_UART			= 64,										// Ports UART RS-422
    parameter UPLINKS               = MGT115_PORTS/2,          	                // 2 ports for uplink 
    parameter DOWNLINKS             = MGT115_PORTS/2,	                        // 2 ports for downlink 
    parameter MGT_PORTS             = 1,                                        // Max 2 MGT clock ports
    parameter TDATA_WIDTH           = 64,                                       // Aurora 64b/66b lane tdata width
    parameter TKEEP_WIDTH           = TDATA_WIDTH/8,                            // Aurora 64b/66b lane tkeep width
    parameter USE_REGS              = 0,
    parameter PLINE_READY           = 1,
    parameter USE_INPIPE            = 0,
    parameter USE_OUTPIPE           = 1,
    parameter EMPTY_LATENCY         = 3,
    parameter PACKET_LENGTH_WIDTH   = TDATA_WIDTH/2,
    parameter DATA_TYPES            = 4,                                        // 0 - csr, 1 - single device rw, 2 - detection, 3 - rays calculation data
    parameter DELAY_TRANSLATE_BYTE  = 3,
	parameter USE_CHIPSCOPE         = 0,
	parameter USE_CHIPSCOPE_USI     = 1
    )
    (
    // Init clock for aurora cores 200 MHz
    input  	wire                    INIT_CLK_P				,
    input  	wire                    INIT_CLK_N				,
	

    // GTX reference clocks for aurora cores 192 MHz
    // Bank 115 (SFP)
    input  	wire                    GTXQ0_P					,
    input  	wire                    GTXQ0_N					,

    // GTX Serial I/O
    // SFP links
	
    input 	wire					MGT_RX0_P				,	
    input 	wire					MGT_RX0_N				,	
	input 	wire					MGT_RX1_P				,	
    input 	wire					MGT_RX1_N				,	
	input 	wire      				MGT_RX2_P				,
    input 	wire      				MGT_RX2_N				,
	input 	wire      				MGT_RX3_P				,
	input 	wire      				MGT_RX3_N				,
	output 	wire	                MGT_TX0_P				,
	output 	wire	                MGT_TX0_N				,
	output 	wire	                MGT_TX1_P				,
	output 	wire	                MGT_TX1_N				,
	output 	wire	                MGT_TX2_P				,
	output 	wire	                MGT_TX2_N				,
	output 	wire	                MGT_TX3_P				,
	output 	wire	                MGT_TX3_N				,

	// TX disable for SFP (inverted)
	output  wire 	[7:0]     		SFP_DIS					,			 		

    // SFP interface
	output  wire 	[7:0]          SST_TX_FPGA_P            , 
	output  wire 	[7:0]          SST_TX_FPGA_N            , 
	
	input   wire 	[7:0]          SST_RX_FPGA_P            , 
	input   wire 	[7:0]          SST_RX_FPGA_N            , 	
	
    // SFP_MEZ interface
	input   wire 	[47:0]          SST_RX_MEZ_P            , 
	input   wire 	[47:0]          SST_RX_MEZ_N            , 	    
    
	output  wire 	[47:0]          SST_TX_MEZ_P            , 
	output  wire 	[47:0]          SST_TX_MEZ_N            , 	

	// RS-422	
	input	wire [(PORTS_UART-1):0]	rx	 			        ,		
	output	wire [(PORTS_UART-1):0]	tx			 		    ,
	
	output  wire                    VD1                     , // Power 1-light OFF, 0 - Light ON
	output  wire                    VD2                       // Fatal Error 1-light OFF, 0 - Light ON	
    );
	
	
	////////////////////////////////////////////////////////////////////////////
	// Signals
	////////////////////////////////////////////////////////////////////////////
	
	// Generate variable
	genvar                                              		i;
	
	// System up reset
	(* TIG="TRUE" *)  wire           							glbl_reset;
 	(* TIG="TRUE" *)  wire           							glbl_reset_n;   
    // System clock and reset
    (* KEEP = "TRUE" *) wire                            		sys_clk;
    wire                                                		sys_reset;
    wire                                                		sys_reset_n;
    
    // Requested resets
	wire                                                		soft_reset;
    wire                                                		aurora_reset;
	wire                                                		soft_reset_n;
    wire                                                		aurora_reset_n;
    
    // CSR clock and reset
    (* KEEP = "TRUE" *) wire                            		csr_clk;
    wire                                                		csr_reset;
    wire                                                		csr_reset_n;
    
	// Aurora clocks
    (* KEEP = "TRUE" *) wire                            		init_clk_i;
    (* KEEP = "TRUE" *) wire [MGT_PORTS-1:0]            		gt_refclk_i;
    
    // User clock/reset
    wire [MGT_PORTS-1:0]                                		user_clk;
    wire [MGT_PORTS-1:0]                                		user_reset;
	
	wire [UPLINKS-1  :0	] 										manual_reset_uplink;
	wire [DOWNLINKS-1:0	] 										manual_reset_downlink;	
    
	// Aurora status signals
    (* KEEP = "TRUE" *) wire [DOWNLINKS-1:0]                    down_hard_err;
    (* KEEP = "TRUE" *) wire [DOWNLINKS-1:0]                    down_soft_err;
    (* KEEP = "TRUE" *) wire [DOWNLINKS-1:0]                    down_lane_up;
    (* KEEP = "TRUE" *) wire [DOWNLINKS-1:0]                    down_channel_up;
    
    (* KEEP = "TRUE" *) wire [UPLINKS-1:0]                      up_hard_err;
    (* KEEP = "TRUE" *) wire [UPLINKS-1:0]                      up_soft_err;
    (* KEEP = "TRUE" *) wire [UPLINKS-1:0]                      up_lane_up;
    (* KEEP = "TRUE" *) wire [UPLINKS-1:0]                      up_channel_up;
	
	// TX Interface DOWNLINK
	(* KEEP = "TRUE" *) wire [DOWNLINKS-1:0][TDATA_WIDTH-1:0]   down_tx_tdata;
	(* KEEP = "TRUE" *) wire [DOWNLINKS-1:0]                    down_tx_tvalid;
	(* KEEP = "TRUE" *) wire [DOWNLINKS-1:0][TKEEP_WIDTH-1:0]   down_tx_tkeep;
	(* KEEP = "TRUE" *) wire [DOWNLINKS-1:0]                    down_tx_tlast;
	(* KEEP = "TRUE" *) wire [DOWNLINKS-1:0]                    down_tx_tready;
	
	// RX Interface DOWNLINK
	(* KEEP = "TRUE" *) wire [DOWNLINKS-1:0][TDATA_WIDTH-1:0]   down_rx_tdata;
	(* KEEP = "TRUE" *) wire [DOWNLINKS-1:0]                    down_rx_tvalid;
	(* KEEP = "TRUE" *) wire [DOWNLINKS-1:0][TKEEP_WIDTH-1:0]   down_rx_tkeep;
	(* KEEP = "TRUE" *) wire [DOWNLINKS-1:0]                    down_rx_tlast;
	
	// TX Interface UPLINK
	(* KEEP = "TRUE" *) wire [UPLINKS-1:0][TDATA_WIDTH-1:0]     up_tx_tdata;
	(* KEEP = "TRUE" *) wire [UPLINKS-1:0]                      up_tx_tvalid;
	(* KEEP = "TRUE" *) wire [UPLINKS-1:0][TKEEP_WIDTH-1:0]     up_tx_tkeep;
	(* KEEP = "TRUE" *) wire [UPLINKS-1:0]                      up_tx_tlast;
	(* KEEP = "TRUE" *) wire [UPLINKS-1:0]                      up_tx_tready;
	
	// RX Interface UPLINK
	(* KEEP = "TRUE" *) wire [UPLINKS-1:0][TDATA_WIDTH-1:0]     up_rx_tdata;
	(* KEEP = "TRUE" *) wire [UPLINKS-1:0]                      up_rx_tvalid;
	(* KEEP = "TRUE" *) wire [UPLINKS-1:0][TKEEP_WIDTH-1:0]     up_rx_tkeep;
	(* KEEP = "TRUE" *) wire [UPLINKS-1:0]                      up_rx_tlast;
	
	// AXI-Stream arbiter DOWN TX
	wire [DOWNLINKS-1:0][TDATA_WIDTH-1:0]               arbiter_down_tx_tdata;
	wire [DOWNLINKS-1:0]                                arbiter_down_tx_tvalid;
	wire [DOWNLINKS-1:0][TKEEP_WIDTH-1:0]               arbiter_down_tx_tkeep;
	wire [DOWNLINKS-1:0]                                arbiter_down_tx_tlast;
	wire [DOWNLINKS-1:0]                                arbiter_down_tx_tready;
	
	wire [DOWNLINKS-1:0]                                arbiter_down_status_timeout;
	
	// AXI-Stream arbiter DOWN RX
	wire [DOWNLINKS-1:0]                                arbiter_down_rx_tready;
	wire [DOWNLINKS-1:0][TDATA_WIDTH-1:0]               arbiter_down_rx_tdata;
	wire [DOWNLINKS-1:0]                                arbiter_down_rx_tvalid;
	wire [DOWNLINKS-1:0][TKEEP_WIDTH-1:0]               arbiter_down_rx_tkeep;
	wire [DOWNLINKS-1:0]                                arbiter_down_rx_tlast;
	
	// AXI-Stream arbiter UP TX
	wire [UPLINKS-1:0][TDATA_WIDTH-1:0]                 arbiter_up_tx_tdata;
	wire [UPLINKS-1:0]                                  arbiter_up_tx_tvalid;
	
	
	
    wire [UPLINKS-1:0][TKEEP_WIDTH-1:0]                 arbiter_up_tx_tkeep;
    wire [UPLINKS-1:0]                                  arbiter_up_tx_tlast;
    wire [UPLINKS-1:0]                                  arbiter_up_tx_tready;

    wire [UPLINKS-1:0]                                  arbiter_up_status_timeout;

    // AXI-Stream arbiter UP RX
    wire [UPLINKS-1:0]                                  arbiter_up_rx_tready;
    wire [UPLINKS-1:0][TDATA_WIDTH-1:0]                 arbiter_up_rx_tdata;
    wire [UPLINKS-1:0]                                  arbiter_up_rx_tvalid;
    wire [UPLINKS-1:0][TKEEP_WIDTH-1:0]                 arbiter_up_rx_tkeep;
    wire [UPLINKS-1:0]                                  arbiter_up_rx_tlast;

    // Destination router DOWNLINK
    wire [DOWNLINKS*(UPLINKS+1)-1:0]                    destination_router_down_tready;
    wire [DOWNLINKS*(UPLINKS+1)-1:0]                    destination_router_down_tvalid;
    wire [DOWNLINKS*(UPLINKS+1)-1:0][TDATA_WIDTH-1:0]   destination_router_down_tdata;
    wire [DOWNLINKS*(UPLINKS+1)-1:0]                    destination_router_down_tlast;
    wire [DOWNLINKS*(UPLINKS+1)-1:0][TKEEP_WIDTH-1:0]   destination_router_down_tkeep;

    // Destination router DOWNLINK
    wire [UPLINKS*(DOWNLINKS+1)-1:0]                    destination_router_up_tready;
    wire [UPLINKS*(DOWNLINKS+1)-1:0]                    destination_router_up_tvalid;
    wire [UPLINKS*(DOWNLINKS+1)-1:0][TDATA_WIDTH-1:0]   destination_router_up_tdata;
    wire [UPLINKS*(DOWNLINKS+1)-1:0]                    destination_router_up_tlast;
    wire [UPLINKS*(DOWNLINKS+1)-1:0][TKEEP_WIDTH-1:0]   destination_router_up_tkeep;

    // Destination router CSR down
    wire [DOWNLINKS-1:0]                                destination_router_csr_down_tready;
    wire [DOWNLINKS-1:0]                                destination_router_csr_down_tvalid;
    wire [DOWNLINKS-1:0][TDATA_WIDTH-1:0]               destination_router_csr_down_tdata;
    wire [DOWNLINKS-1:0]                                destination_router_csr_down_tlast;
    wire [DOWNLINKS-1:0][TKEEP_WIDTH-1:0]               destination_router_csr_down_tkeep;

    // Destination router CSR up
    wire [UPLINKS-1:0]                                  destination_router_csr_up_tready;
    wire [UPLINKS-1:0]                                  destination_router_csr_up_tvalid;
    wire [UPLINKS-1:0][TDATA_WIDTH-1:0]                 destination_router_csr_up_tdata;
    wire [UPLINKS-1:0]                                  destination_router_csr_up_tlast;
    wire [UPLINKS-1:0][TKEEP_WIDTH-1:0]                 destination_router_csr_up_tkeep;


    // Multichannel AXI-Stream arbiter DOWNLINK
    wire [DOWNLINKS*(UPLINKS+1)-1:0]                    multi_axis_arbiter_down_tready;
    wire [DOWNLINKS*(UPLINKS+1)-1:0]                    multi_axis_arbiter_down_tvalid;
    wire [DOWNLINKS*(UPLINKS+1)-1:0][TDATA_WIDTH-1:0]   multi_axis_arbiter_down_tdata;
    wire [DOWNLINKS*(UPLINKS+1)-1:0]                    multi_axis_arbiter_down_tlast;
    wire [DOWNLINKS*(UPLINKS+1)-1:0][TKEEP_WIDTH-1:0]   multi_axis_arbiter_down_tkeep;

    // Multichannel AXI-Stream arbiter UPLINK
    wire [UPLINKS*(DOWNLINKS+1)-1:0]                    multi_axis_arbiter_up_tready;
    wire [UPLINKS*(DOWNLINKS+1)-1:0]                    multi_axis_arbiter_up_tvalid;
    wire [UPLINKS*(DOWNLINKS+1)-1:0][TDATA_WIDTH-1:0]   multi_axis_arbiter_up_tdata;
    wire [UPLINKS*(DOWNLINKS+1)-1:0]                    multi_axis_arbiter_up_tlast;
    wire [UPLINKS*(DOWNLINKS+1)-1:0][TKEEP_WIDTH-1:0]   multi_axis_arbiter_up_tkeep;

    // Type router DOWNLINK
    wire [DOWNLINKS*DATA_TYPES-1:0]                     type_router_down_tready;
    wire [DOWNLINKS*DATA_TYPES-1:0]                     type_router_down_tvalid;
    wire [DOWNLINKS*DATA_TYPES-1:0][TDATA_WIDTH-1:0]    type_router_down_tdata;
    wire [DOWNLINKS*DATA_TYPES-1:0]                     type_router_down_tlast;
    wire [DOWNLINKS*DATA_TYPES-1:0][TKEEP_WIDTH-1:0]    type_router_down_tkeep;

    // Type router UPLINK
    wire                        						type_router_up_tready;
    wire                        						type_router_up_tvalid;
    wire [TDATA_WIDTH-1:0]      						type_router_up_tdata;
    wire                        						type_router_up_tlast;
    wire [TKEEP_WIDTH-1:0]      						type_router_up_tkeep;

    // Router requests
    wire [DOWNLINKS-1:0][ceil_log2(TDATA_WIDTH)-1:0]    destination_router_down_request;
    wire [UPLINKS-1:0][ceil_log2(TDATA_WIDTH)-1:0]      destination_router_up_request;
    wire [DOWNLINKS-1:0][ceil_log2(TDATA_WIDTH)-1:0]    type_router_down_request;
    wire [TDATA_WIDTH-1:0]                              delay_and_usart_reverse_bit;

    // Reset requests
    wire                                                ctrl_soft_reset_request;
    wire                                                ctrl_aurora_reset_request;
    
    // Downlink and uplink masks
    wire [DOWNLINKS-1:0]                                ctrl_downlink_mask;
    wire [  UPLINKS-1:0]                                ctrl_uplink_mask;

	wire [7:0]											sfp_tx_dis;
	
	wire												locked_mmcm_mcu_rto			;
	
	// Aurora data lanes
	wire [(SFP_PORTS-1):0]								SFP_RXP						;	
	wire [(SFP_PORTS-1):0]								SFP_RXN						;	
	wire [(SFP_PORTS-1):0]								SFP_TXP						;
	wire [(SFP_PORTS-1):0]								SFP_TXN						;
			
	wire [(PORTS_UART-1):0] 							csr_wrp_tx_dav				;	
	wire [(PORTS_UART-1):0] [63:0]						csr_wrp_tx_data				;	
	wire [(PORTS_UART-1):0] 							csr_wrp_rx_dav				;		
	wire [(PORTS_UART-1):0] [7:0]						csr_wrp_rx_data				;	
	
	wire [(PORTS_UART-1):0]								tx_uart						;
	wire [(PORTS_UART-1):0]								rx_uart						;
	
	wire [63:0]											rx_lock						;
	wire [63:0]											tx_lock						;

	wire												usart_cnt_clk_fsg			;
	wire												usart_cnt_clk_meopg			;
	wire												s_mmcm_input_clk_stopped 	;	
	
	
	
	(* KEEP = "TRUE" *)wire [63:0]						s_csr_tx_i_rst				;  
	(* KEEP = "TRUE" *)wire [(PORTS_UART-1):0] [ 7:0]	s_csr_tx_i_len				;
	(* KEEP = "TRUE" *)wire [63:0]						s_csr_rx_i_rst				;  
	(* KEEP = "TRUE" *)wire [63:0] 						s_csr_rx_i_rdy				;  
	(* KEEP = "TRUE" *)wire [(PORTS_UART-1):0] 			s_csr_rx_o_mpt				;	
	(* KEEP = "TRUE" *)wire [(PORTS_UART-1):0] [9 :0]	s_csr_rx_o_cntrd			;	
		
	wire [63:0]											control_reg_csr				;
	wire [63:0]											status_reg_csr				;	
		
	wire												manual_xxx_control			; 
	wire												manual_xxx_value	    	;
	
	wire 												csr_usr_dat_xxx_sim_en	 	;
	wire  					[11:0] 						csr_usr_dat_xxx_sim_hold	;
	wire  					[11:0]						csr_usr_dat_xxx_sim_setup 	;
	wire  					[7:0 ]						csr_usr_dat_xxx_sim_mask	;
	wire  												csr_usr_dat_xxx_invert_en 	;
	wire  					[11:0]						csr_usr_dat_xxx_delay	 	;
	wire  					[7:0 ]						csr_usr_dat_xxx_duration	;	
	
	wire												s_usr_dat_xxx_x1				;				
	wire												s_usr_dat_xxx_x2				;				
	wire												s_usr_dat_xxx_x3				;				
	wire												s_usr_dat_xxx_x4				;				
	wire												s_usr_dat_xxx_ku1			;					
	wire												s_usr_dat_xxx_ku2			;					
	wire												s_usr_dat_xxx_ku3			;					
	wire												s_usr_dat_xxx_ku4			;					
	wire												s_usr_dat_xxx_x1				;				
	wire												s_usr_dat_xxx_x2				;				
	wire												s_usr_dat_xxx_x3				;				
	wire												s_usr_dat_xxx_x4				;				
	wire												s_usr_dat_xxx_s1				;				
	wire												s_usr_dat_xxx_s2				;				
	wire												s_usr_dat_xxx_s3				;				
	wire												s_usr_dat_xxx_s4				;	

	wire  [7:0 ]										csr_usr_dat_xxx_mask			;
	wire												xxx_enable					;	
	
	// regs status
	wire  [81:0]										status_alarms				;	
	wire  [135:0]										status_diagmode				;	
	wire  [36:0]										status_automode				;	
	
	wire  [81:0]										status_alarms_resynch		;	
	wire  [135:0]										status_diagmode_resynch		;	
	wire  [36:0]										status_automode_resynch		;		

	wire  [63:0]										s_regX22_resync				;	
	wire  [63:0]										s_regX22					;
	wire  [63:0]										s_regX23_resync				;	
	wire  [63:0]										s_regX23					;
	wire  [63:0]										s_regX24_resync				;	
	wire  [63:0]										s_regX24					;
	wire  [63:0]										s_regX25_resync				;	
	wire  [63:0]										s_regX25					;	

    wire  [2:0]                                         vio_mod                     ; 
    wire  [7:0]                                         vio_channel_ap			    ;
	wire  [7:0]                                         vio_channel_xxx_0		    ;
	wire  [7:0]                                         vio_channel_xxx_1		    ;
	wire  [7:0]                                         vio_channel_xxx_2			;
	wire  [7:0]                                         vio_channel_xxx_3			;
	
	wire  [15:0]	                                    vio_value_ap				;
	wire  [15:0]	                                    vio_value_xxx_0				;
	wire  [15:0]	                                    vio_value_xxx_1				;
	wire  [15:0]	                                    vio_value_xxx_2				;
	wire  [15:0]	                                    vio_value_xxx_3				;
	                                                   
	wire	                                            vio_valid_ap				;
	wire  [4:0]	                                        vio_valid_xxx				;	
  

	
	////////////////////////////////////////////////////////////////////////////
    //Light Diodes
    ////////////////////////////////////////////////////////////////////////////	
    assign VD1 = 1'b0;
    assign VD2 = 1'b1;
    

	////////////////////////////////////////////////////////////////////////////
    // TX disable (inverted)
    ////////////////////////////////////////////////////////////////////////////

    assign sfp_tx_dis = {8{1'b1}};
	
	assign SFP_DIS	  =  sfp_tx_dis;	


	////////////////////////////////////////////////////////////////////////////
    // Aurora lanes demapper
    ////////////////////////////////////////////////////////////////////////////

	assign SFP_RXP = {MGT_RX3_P, MGT_RX2_P, MGT_RX1_P, MGT_RX0_P};
    assign SFP_RXN = {MGT_RX3_N, MGT_RX2_N, MGT_RX1_N, MGT_RX0_N};
			
	assign {MGT_TX3_P, MGT_TX2_P, MGT_TX1_P, MGT_TX0_P} = SFP_TXP;
    assign {MGT_TX3_N, MGT_TX2_N, MGT_TX1_N, MGT_TX0_N} = SFP_TXN;
    
    ////////////////////////////////////////////////////////////////////////////

     vio_0 vio(
		.clk                        (sys_clk                  ),
		.probe_out0                 (vio_mod                  ),
		.probe_out1                 (vio_channel_ap           ), 
		.probe_out2                 (vio_channel_xxx_0        ), 
		.probe_out3                 (vio_channel_xxx_1        ), 
		.probe_out4                 (vio_channel_xxx_2        ), 
		.probe_out5                 (vio_channel_xxx_3        ), 
		.probe_out6                 (vio_value_ap			  ), 
		.probe_out7                 (vio_value_xxx_0          ), 
		.probe_out8                 (vio_value_xxx_1          ), 
		.probe_out9                 (vio_value_xxx_2          ), 
		.probe_out10                (vio_value_xxx_3          ), 
		.probe_out11                (vio_valid_ap			  ), 
		.probe_out12                (vio_valid_xxx            )  
              
 ); 	

	////////////////////////////////////////////////////////////////////////////
    // Initial reset generator
    ////////////////////////////////////////////////////////////////////////////

	xilinx_reset_gen
    #(
		.TIMEOUT       	(128*4			),
		.SYNC_LENGTH   	(8      		)
    )
	sync_reset_gen_inst
    (
		.clk			(init_clk_i		),
		.reset			(glbl_reset		),
		.reset_n		(glbl_reset_n	)
    );
	

    ////////////////////////////////////////////////////////////////////////////
    // Clocks and resets
    ////////////////////////////////////////////////////////////////////////////

    clock_module
            #(
            .INIT_PORTS             (1                                      ),
            .MGT_PORTS              (MGT_PORTS                              )
            )
        the_clock_module
            (
            .INIT_CLK_P             (INIT_CLK_P                            	),
            .INIT_CLK_N             (INIT_CLK_N                            	),
            .INIT_CLK_O             (init_clk_i                             ),
            .MGTREFCLK_P            (GTXQ0_P                                ),   
            .MGTREFCLK_N            (GTXQ0_N                                ),    
            .MGTREFCLK_O            (gt_refclk_i                            )
            );

    mcu_mmcm
        the_mmcm_mcu_sovch
            (
            .clk_in1                (init_clk_i                             ),
            
            .clk_out1               (sys_clk                                ),
            .clk_out2               (csr_clk                                ),
            .clk_out3               (usart_cnt_clk_fsg                  	),
            .clk_out4               (usart_cnt_clk_meopg                    ),  
			.input_clk_stopped		(s_mmcm_input_clk_stopped				),	
            .reset                  (glbl_reset                             ),
            .locked                 (locked_mmcm_mcu_rto                    )
            );

    sync_chain_bit
            #(
            .SYNC_LENGTH            (8                                      )
            )
        sys_reset_sync
            (
            .clk                    (sys_clk                                ),
            .in_data                (glbl_reset                              ),
            .out_data               (sys_reset                              )
            );

    sync_chain_bit
            #(
            .SYNC_LENGTH            (8                                      )
            )
        csr_reset_sync
            (
            .clk                    (csr_clk                                ),
            .in_data                (glbl_reset                              ),
            .out_data               (csr_reset                              )
            );

    soft_reset_gen
            #(
            .CNT_WIDTH              (16                                     ),
            .RESET_LENGTH           (128                                    )
            )
        the_soft_reset_gen
            (
            .clk                    (sys_clk                                ),
            .reset_n                (sys_reset_n                            ),
            .start                  (ctrl_soft_reset_request				),
            .soft_reset             (soft_reset                             ),
            .soft_reset_n           (soft_reset_n                           )
            );

    soft_reset_gen
            #(
            .CNT_WIDTH              (16                                     ),
            .RESET_LENGTH           (8192                                   )
            )
        the_aurora_reset_gen
            (
            .clk                    (sys_clk                                ),
            .reset_n                (sys_reset_n                            ),
            .start                  (ctrl_aurora_reset_request              ),
            .soft_reset             (aurora_reset                           ),
            .soft_reset_n           (aurora_reset_n                         )
            );

    assign sys_reset_n              = ~(sys_reset) && locked_mmcm_mcu_xxx;
    assign csr_reset_n              = ~csr_reset;

    ////////////////////////////////////////////////////////////////////////////
    // Aurora wrappers
    ////////////////////////////////////////////////////////////////////////////

    aurora_64b66b_kintex7_wrp
            #(
            .PORTS                  (MGT115_PORTS           )
            )
        the_aurora_115
            (
            .reset                  ({ 	glbl_reset || aurora_reset || manual_reset_downlink[1],
										glbl_reset || aurora_reset || manual_reset_downlink[0],
										glbl_reset || aurora_reset || manual_reset_uplink  [1],
									  	glbl_reset || aurora_reset || manual_reset_uplink  [0]
														   }),
            .power_down             (1'b0                   ),

            .hard_err               ({down_hard_err  [1:0], up_hard_err  [1:0] }	),
            .soft_err               ({down_soft_err  [1:0], up_soft_err  [1:0] }	),
            .lane_up                ({down_lane_up   [1:0], up_lane_up   [1:0] }	),
            .channel_up             ({down_channel_up[1:0], up_channel_up[1:0] }	),

            .init_clk               (init_clk_i             ),
            .pma_init               ({ 	glbl_reset || aurora_reset || manual_reset_downlink[1],
			                        	glbl_reset || aurora_reset || manual_reset_downlink[0],
			                        	glbl_reset || aurora_reset || manual_reset_uplink  [1],
			                          	glbl_reset || aurora_reset || manual_reset_uplink  [0]
			                        					   }),

            .gt_refclk              (gt_refclk_i[0]         ),

            .rxp                    (SFP_RXP[3:0]           ),
            .rxn                    (SFP_RXN[3:0]           ),
            .txp                    (SFP_TXP[3:0]           ),
            .txn                    (SFP_TXN[3:0]           ),

            .user_clk               (user_clk  [0]          ),
            .user_reset             (user_reset[0]          ),

            .tx_tdata               ({down_tx_tdata [1:0], up_tx_tdata [1:0] }),
            .tx_tvalid              ({down_tx_tvalid[1:0], up_tx_tvalid[1:0] }),
            .tx_tkeep               ({down_tx_tkeep [1:0], up_tx_tkeep [1:0] }),
            .tx_tlast               ({down_tx_tlast [1:0], up_tx_tlast [1:0] }),
            .tx_tready              ({down_tx_tready[1:0], up_tx_tready[1:0] }),

            .rx_tdata               ({down_rx_tdata [1:0], up_rx_tdata [1:0] }),
            .rx_tvalid              ({down_rx_tvalid[1:0], up_rx_tvalid[1:0] }),
            .rx_tkeep               ({down_rx_tkeep [1:0], up_rx_tkeep [1:0] }),
            .rx_tlast               ({down_rx_tlast [1:0], up_rx_tlast [1:0] })
            );

    ////////////////////////////////////////////////////////////////////////////
    // Aurora manual reset UPLINKS
    ////////////////////////////////////////////////////////////////////////////				
	generate
    for (i=0;i<UPLINKS;i=i+1) begin: gen_reset_manual_up_auroras			
	reset_synchro_generator 
			#(						
			.PORTS				  	(1						),  
			.TDATA_WIDTH         	(64						),  
			.CNT_VALUE_RESET_START  (800000					),  
			.CNT_VALUE_RESET_STOP   (800100					),  
			.CNT_VALUE_COUNT_STOP	(400000000  			)   
			)
	reset_manual_aurora_uplink_wrp
			(						
			//Interface: clk/reset  
			.clk                    (init_clk_i				),   
			.reset_i                (up_channel_up	 	 [i]),   
			//Output:    reset        
			.reset_g                (manual_reset_uplink [i])                                  
			); 
	end		
    endgenerate


    ////////////////////////////////////////////////////////////////////////////
    // Aurora manual reset DOWNLINKS
    ////////////////////////////////////////////////////////////////////////////	
	
	generate
    for (i=0;i<DOWNLINKS;i=i+1) begin: gen_reset_manual_down_auroras			
	reset_synchro_generator 
			#(						
			.PORTS				  	(1						),  
			.TDATA_WIDTH         	(64						),  
			.CNT_VALUE_RESET_START  (800000					),  
			.CNT_VALUE_RESET_STOP   (800100					),  
			.CNT_VALUE_COUNT_STOP	(400000000  			)   
			)		
	reset_manual_aurora_downlink_wrp
			(						
			//Interface: clk/reset  
			.clk                    (init_clk_i				),   
			.reset_i                (down_channel_up	 [i]),   
			//Output:    reset        
			.reset_g                (manual_reset_downlink[i])                                  
			); 
	end		
    endgenerate	
	
	
    ////////////////////////////////////////////////////////////////////////////
    // Dual clock FIFO buffers for aurora ports
    ////////////////////////////////////////////////////////////////////////////

    aurora_dcfifo_wrp
            #(
            .TDATA_WIDTH            (TDATA_WIDTH                                    ),
            .TKEEP_WIDTH            (TKEEP_WIDTH                                    ),
            .PORTS                  (UPLINKS+DOWNLINKS                              ),
            .USE_CHIPSCOPE          (USE_CHIPSCOPE	                                )
            )
        the_aurora_dcfifo_wrp
            (
            .sys_clk                (sys_clk),
            .sys_reset_n            (sys_reset_n || soft_reset_n					),
            .aurora_clk             ({user_clk[0], user_clk[0], user_clk[0], user_clk[0]}),

            .aurora_in_tvalid       ({down_rx_tvalid, up_rx_tvalid                 }),
            .aurora_in_tdata        ({down_rx_tdata,  up_rx_tdata                  }),
            .aurora_in_tlast        ({down_rx_tlast,  up_rx_tlast                  }),
            .aurora_in_tkeep        ({down_rx_tkeep,  up_rx_tkeep                  }),
    
            .aurora_out_tready      ({down_tx_tready, up_tx_tready                 }),
            .aurora_out_tvalid      ({down_tx_tvalid, up_tx_tvalid                 }),
            .aurora_out_tdata       ({down_tx_tdata,  up_tx_tdata                  }),
            .aurora_out_tlast       ({down_tx_tlast,  up_tx_tlast                  }),
            .aurora_out_tkeep       ({down_tx_tkeep,  up_tx_tkeep                  }),
    
            .sys_in_tready          ({arbiter_down_tx_tready, arbiter_up_tx_tready }),
            .sys_in_tvalid          ({arbiter_down_tx_tvalid, arbiter_up_tx_tvalid }),
            .sys_in_tdata           ({arbiter_down_tx_tdata,  arbiter_up_tx_tdata  }),
            .sys_in_tlast           ({arbiter_down_tx_tlast,  arbiter_up_tx_tlast  }),
            .sys_in_tkeep           ({arbiter_down_tx_tkeep,  arbiter_up_tx_tkeep  }),
    
            .sys_out_tready         ({arbiter_down_rx_tready,  arbiter_up_rx_tready  }),
            .sys_out_tvalid         ({arbiter_down_rx_tvalid,  arbiter_up_rx_tvalid  }),
            .sys_out_tdata          ({arbiter_down_rx_tdata,   arbiter_up_rx_tdata   }),
            .sys_out_tlast          ({arbiter_down_rx_tlast,   arbiter_up_rx_tlast   }),
            .sys_out_tkeep          ({arbiter_down_rx_tkeep,   arbiter_up_rx_tkeep   }),

            .ctrl_pass              ({ctrl_downlink_mask, ctrl_uplink_mask         }),
            .ctrl_channel_up        ({down_channel_up   , up_channel_up            })
            );
			
		   
    ////////////////////////////////////////////////////////////////////////////
    // CSR
    ////////////////////////////////////////////////////////////////////////////

    mcu_csr_wrp
            #(
            .PIO_REGS                               (64                                     ),
            .HARDWARE_ID                            (HARDWARE_ID                            ),
			.FIRMWARE_ID							(FIRMWARE_ID							),
            .UPLINKS                                (UPLINKS                                ),
            .DOWNLINKS                              (DOWNLINKS                              ),
            .TDATA_WIDTH                            (TDATA_WIDTH                            ),
            .TKEEP_WIDTH                            (TKEEP_WIDTH                            ),
            .BUFFER_DEPTH                           (256                                    ),
            .USE_REGS                               (USE_REGS                               ),
            .PLINE_READY                            (PLINE_READY                            ),
            .USE_INPIPE                             (USE_INPIPE                             ),
            .USE_OUTPIPE                            (USE_OUTPIPE                            ),
            .EMPTY_LATENCY                          (EMPTY_LATENCY                          ),
            .MM_ADDR_WIDTH                          (8                                      ),
            .MM_DATA_WIDTH                          (TDATA_WIDTH                            ),
            .PACKET_LENGTH_WIDTH                    (PACKET_LENGTH_WIDTH                    ),
            .XADC_DATA_WIDTH                        (16                                     ),
			.PORTS_USART							(PORTS_UART								),
            .USE_CHIPSCOPE                          (USE_CHIPSCOPE                          )
            )
        the_mcu_csr_wrp
            (
            .clk                                    (sys_clk                                ),
            .reset_n                                (sys_reset_n                            ),
            .csr_clk                                (csr_clk                                ),
            .csr_reset_n                            (csr_reset_n                            ),

            .up_in_tready                           (arbiter_up_rx_tready					),
            .up_in_tvalid                           (arbiter_up_rx_tvalid					),
            .up_in_tdata                            (arbiter_up_rx_tdata 					),
            .up_in_tlast                            (arbiter_up_rx_tlast 					),
            .up_in_tkeep                            (arbiter_up_rx_tkeep 					),

            .up_out_tready                          (arbiter_up_tx_tready 					),
            .up_out_tvalid                          (arbiter_up_tx_tvalid 					),
            .up_out_tdata                           (arbiter_up_tx_tdata  					),
            .up_out_tlast                           (arbiter_up_tx_tlast  					),
            .up_out_tkeep                           (arbiter_up_tx_tkeep  					),

            .down_in_tready                         (arbiter_down_rx_tready					),
            .down_in_tvalid                         (arbiter_down_rx_tvalid					),
            .down_in_tdata                          (arbiter_down_rx_tdata 					),
            .down_in_tlast                          (arbiter_down_rx_tlast 					),
            .down_in_tkeep                          (arbiter_down_rx_tkeep 					),

            .down_out_tready                        (arbiter_down_tx_tready					),
            .down_out_tvalid                        (arbiter_down_tx_tvalid					),
            .down_out_tdata                         (arbiter_down_tx_tdata 					),
            .down_out_tlast                         (arbiter_down_tx_tlast 					),
            .down_out_tkeep                         (arbiter_down_tx_tkeep 					),

            .destination_router_down_request        (destination_router_down_request        ),
            .destination_router_up_request          (destination_router_up_request          ),
            .type_router_down_request               (type_router_down_request               ),

            .ctrl_soft_reset_request                (ctrl_soft_reset_request                ),
            .ctrl_aurora_reset_request              (ctrl_aurora_reset_request              ),

            .status_up_channel_up                   (up_channel_up                          ),
            .status_down_channel_up                 (down_channel_up                        ),


			.csr_wrp_tx_dav							(csr_wrp_tx_dav	    					),
			.csr_wrp_tx_data						(csr_wrp_tx_data						),
			.csr_wrp_rx_dav							(csr_wrp_rx_dav	    					),
			.csr_wrp_rx_data						(csr_wrp_rx_data						),
			
			// tx/rx control
			.csr_tx_i_rst							(s_csr_tx_i_rst							),  
			.csr_tx_i_len							(s_csr_tx_i_len							),
			.csr_rx_i_rst							(s_csr_rx_i_rst							),  
			.csr_rx_i_rdy							(s_csr_rx_i_rdy							),  
			.csr_rx_o_mpt							(s_csr_rx_o_mpt							),	
			.csr_rx_o_cntrd							(s_csr_rx_o_cntrd						),				
			
						
			.ctrl_downlink_mask                     (ctrl_downlink_mask                     ),
            .ctrl_uplink_mask                       (ctrl_uplink_mask                       ),
			
			.rx_lock_csr							(rx_lock								),
			.tx_lock_csr							(tx_lock								),
			
			.control_reg_csr						(control_reg_csr						),
			.status_reg_csr							(status_reg_csr							),

			.csr_usr_dat_xxx_sim_en	 	            (csr_usr_dat_xxx_sim_en	 				),
			.csr_usr_dat_xxx_sim_hold	            (csr_usr_dat_xxx_sim_hold				),
			.csr_usr_dat_xxx_sim_setup 	            (csr_usr_dat_xxx_sim_setup 				),
			.csr_usr_dat_xxx_sim_mask	            (csr_usr_dat_xxx_sim_mask				),
			.csr_usr_dat_xxx_invert_en 	            (csr_usr_dat_xxx_invert_en 				),
			.csr_usr_dat_xxx_delay	 	            (csr_usr_dat_xxx_delay	 				),
			.csr_usr_dat_xxx_duration				(csr_usr_dat_xxx_duration				),
			.csr_usr_dat_xxx_mask					(csr_usr_dat_xxx_mask					),
			
			.regX25									(s_regX25								),
			.regX24									(s_regX24								),
			.regX23									(s_regX23								),
			.regX22									(s_regX22								),
			
			.status_automode						(status_automode_resynch				),			
			.status_diagmode						(status_diagmode_resynch				),			
			.status_alarms							(status_alarms_resynch					)			
        );

	
    ////////////////////////////////////////////////////////////////////////////
    // Multi-usart-interface
    ////////////////////////////////////////////////////////////////////////////			
	multi_usart_interface
			#(
			.PORTS         							(PORTS_UART								),
			.TDATA_WIDTH   							(TDATA_WIDTH							),
			.DELAY_TRANSLATE_BYTE					(DELAY_TRANSLATE_BYTE					),
			.USE_CHIPSCOPE          				(USE_CHIPSCOPE	                        )
			)
	multi_usart_interface_inst
			(
			// Interface: System
			.clk									(sys_clk 														),
			.reset_n								(sys_reset_n || soft_reset_n									),
			.usart_cnt_clk_fsg			            (usart_cnt_clk_fsg                      						),
			.usart_cnt_clk_meopg		            (usart_cnt_clk_meopg                      						),// 52 MHZ
			// Interface: In
			.in_tvalid								(csr_wrp_tx_dav													),
			.in_tdata								(csr_wrp_tx_data												),
			// Interface: Out
			.out_tvalid								(csr_wrp_rx_dav													),
			.out_tdata								(csr_wrp_rx_data												),
			// usart_ports
			.rx_uart								(rx_uart														),
			.tx_uart								(tx_uart														),
			// tx/rx control
			.csr_tx_i_rst							(s_csr_tx_i_rst[(PORTS_UART-1):0]								),  
			.csr_tx_i_len							(s_csr_tx_i_len													),
			.csr_rx_i_rst							(s_csr_rx_i_rst[(PORTS_UART-1):0]								),  
			.csr_rx_i_rdy							(s_csr_rx_i_rdy[(PORTS_UART-1):0]								),  
			.csr_rx_o_mpt							(s_csr_rx_o_mpt													),
			.csr_rx_o_cntrd							(s_csr_rx_o_cntrd												)		
			);			


    ////////////////////////////////////////////////////////////////////////////
    // Auto_diagnostic_and_cmd_creator
    ////////////////////////////////////////////////////////////////////////////
	xpm_cdc_array_single #(
	
	//Common module parameters
	.DEST_SYNC_FF   				(3												), // integer; range: 2-10
	.SIM_ASSERT_CHK 				(0												), // integer; 0=disable simulation messages, 1=enable simulation messages
	.SRC_INPUT_REG  				(1												), // integer; 0=do not register input, 1=register input
	.WIDTH          				(256											)  // integer; range: 2-1024
	
	) xpm_cdc_array_single_inst_s_reg_auto (
	
	.src_clk  						(sys_clk										),  // optional; required when SRC_INPUT_REG = 1
	.src_in   						({  s_regX25,
									    s_regX24,	
									 	s_regX23,				
									 	s_regX22					}				),	
	.dest_clk 						(usart_cnt_clk_meopg							), 
	.dest_out 						({  s_regX25_resync,
	                                    s_regX24_resync,	
										s_regX23_resync,							
										s_regX22_resync				}				)
	);	
	
	
	xpm_cdc_array_single #(
	
	//Common module parameters
	.DEST_SYNC_FF   				(3												), // integer; range: 2-10
	.SIM_ASSERT_CHK 				(0												), // integer; 0=disable simulation messages, 1=enable simulation messages
	.SRC_INPUT_REG  				(1												), // integer; 0=do not register input, 1=register input
	.WIDTH          				(82+136+37										)  // integer; range: 2-1024
	
	) xpm_cdc_array_single_inst_adc (
	
	.src_clk  						(usart_cnt_clk_meopg							),  // optional; required when SRC_INPUT_REG = 1
	.src_in   						({  status_automode,
									    status_diagmode,	
									 	status_alarms					
																	}				),	
	.dest_clk 						(sys_clk										), 
	.dest_out 						({  status_automode_resynch,
	                                    status_diagmode_resynch,	
										status_alarms_resynch								
																	}				)
	);		
	
		
	auto_setup#(
		.VALUE_CHECK 						(8							),
		.RTO_MODULES 						(4							),
		.CHECK_MODULES 						(15							),
		.RECEIVE_RTO_MODULES 				(4							),
		.BFSG_MODULES 						(8							),
		.CHANNEL 							(8							),
		.CHANNEL_RTO 						(3							)
	)
    ////////////////////////////////////////////////////////////////////////////
    // auto_setup_inst
    ////////////////////////////////////////////////////////////////////////////
	
	
	auto_setup_inst
	(
	    .ila_clk                            (sys_clk                    ),		
        .channel_ap							(vio_channel_ap		    	), 
		.channel_xxx_0						(vio_channel_xxx_0			), 
		.channel_xxx_1						(vio_channel_xxx_1			), 
		.channel_xxx_2						(vio_channel_xxx_2			), 
		.channel_xxx_3						(vio_channel_xxx_3			), 
	
  
		.value_ap							(vio_value_ap				),
		.value_xxx_0						(vio_value_xxx_0			),
		.value_xxx_1						(vio_value_xxx_1			),
		.value_xxx_2						(vio_value_xxx_2			),
		.value_xxx_3						(vio_value_xxx_3			),
		
	    .valid_ap							(vio_valid_ap				),	
		.valid_xxx							(vio_valid_xxx				),	
	
 
	
		//.mode								(s_regX25_resync[2:0]		),	// in3  operating mode: 0 - off modules, 1 - the mode semi-automatic, 2 - diagnostics, 3 - a repeater of data
		.mode								(vio_mod		                ),	// in3  operating mode: 0 - off modules, 1 - the mode semi-automatic, 2 - diagnostics, 3 - a repeater of dat
		.clk_x16							(usart_cnt_clk_meopg		    ),
		.rst								(~(sys_reset_n || soft_reset_n) ),
		.manual_mode_tx_receive_ap			(tx_uart	[4]				    ),	
		.manual_mode_tx_transfer_xxx_ap		(tx_uart	[59]			    ),	
		.manual_mode_tx_transfer_xxx_ap     (tx_uart	[58]		        ),	
		.manual_mode_tx_receive_xxx		    (tx_uart	[3:0]	            ),	
		.manual_mode_tx_xxx				    ({tx_uart[34:30],tx_uart[63:61]}),	
		  
	
	
		.tx_receive_ap						(tx			[4]				    ),	
		.rx_receive_ap						(rx_uart	[4]				    ),	
		.tx_transfer_xxx_ap					(tx			[59]				),	
		.rx_transfer_xxx_ap					(rx_uart	[59]				),	
		.tx_transfer_xxx_ap				    (tx			[58]				),	
		.rx_transfer_xxx_ap				    (rx_uart	[58]				),	



        .tx_receive_xxx_0                   (tx			[0]             ),
        .tx_receive_xxx_1                   (tx			[1]             ),
        .tx_receive_xxx_2                   (tx			[2]             ),
        .tx_receive_xxx_3                   (tx			[3]             ),
                                  
        .tx_xxx_0                          	(tx			[61]			),
        .tx_xxx_1                          	(tx			[62]			),
        .tx_xxx_2                          	(tx			[63]			),
        .tx_xxx_3                          	(tx			[30]			),
        .tx_xxx_4                          	(tx			[31]			),
        .tx_xxx_5                          	(tx			[32]			),
        .tx_xxx_6                          	(tx			[33]			),
        .tx_xxx_7                          	(tx			[34]			),
        
		.rx_receive_xxx						(tx_uart	[3:0]	        ),	        
		.rx_xxx							   ({rx_uart    [34:30],rx_uart[63:61]}),


		
			      


	// statuses AUTO_MODE_FREQUENCY_SETUP
		.status_setup_xxx_ap				(status_automode[7:0]		),	
		.status_setup_receive_xxx	        (status_automode[10:8]		),	
		.status_setup_receive_xxx	        (status_automode[13:11]		),	
		.status_setup_receive_xxx	        (status_automode[16:14]		),	
		.status_setup_receive_xxx	        (status_automode[19:17]		),	
		.status_setup_transfer_xxx_ap	    (status_automode[27:20]		),	
		.status_setup_transfer_xxx_ap	    (status_automode[28]		),	
		.status_setup_receive_xxx_ap		(status_automode[36:29]		),	
	
	// statuses Diagnoze_MODE
		.status_check_tx_receive_ap			(status_diagmode[0]			), 	
		.status_check_tx_transfer_xxx_ap	(status_diagmode[1]			), 	
		.status_check_tx_transfer_xxx_ap	(status_diagmode[2]			), 	
		.status_check_tx_receive_xxx		(status_diagmode[6:3]		), 	
		.status_check_tx_xxx				(status_diagmode[14:7]		), 	
	
		.value_check_tx_transfer_xxx_ap		(status_diagmode[23:16]		),	                    
		.value_check_tx_transfer_xxx_ap		(status_diagmode[31:24]		),	                    
		.value_check_tx_receive_xxx			(status_diagmode[39:32]		),	                    
		.value_check_tx_receive_xxx			({							
											 status_diagmode[71:64],	
											 status_diagmode[63:56],		
											 status_diagmode[55:48],	
											 status_diagmode[47:40]	
											}							),	//[RECEIVE_RTO_MODULES-1:0][VALUE_CHECK-1:0]          
		.value_check_tx_xxx 				(							
											{									
											status_diagmode[135:128],			
											status_diagmode[127:120],				
											status_diagmode[119:112],			
											status_diagmode[111:104],		
											status_diagmode[103:96],	
                                            status_diagmode[95:88],	
                                            status_diagmode[87:80],	
											status_diagmode[79:72]	
											}									
																		),	//[BFSG_MODULES-1:0][VALUE_CHECK-1:0]                 
	
	// Alarms
		.alarm_bytes_number_xxx				(status_alarms[81:74]	), 
		.alarm_record_check_xxx				(status_alarms[7:0]		), 
		.alarm_bytes_number_xxx				(status_alarms[8]		), 
		.alarm_record_check_xxx				(status_alarms[9]		), 
		.alarm_bytes_number_receive_ap		(status_alarms[17:10]	), 
		.alarm_record_check_receive_ap		(status_alarms[25:18]	), 

		.alarm_bytes_number_receive_xxx 	(status_alarms[28:26]	), 
		.alarm_record_check_receive_xxx 	(status_alarms[31:29]	), 
		.alarm_bytes_number_receive_xxx 	(status_alarms[34:32]	), 
		.alarm_record_check_receive_xxx 	(status_alarms[37:35]	), 
		.alarm_bytes_number_receive_xxx 	(status_alarms[40:38]	), 
		.alarm_record_check_receive_xxx 	(status_alarms[43:41]	), 
		.alarm_bytes_number_receive_xxx 	(status_alarms[46:44]	), 
		.alarm_record_check_receive_xxx 	(status_alarms[49:47]	), 
		.alarm_bytes_number_xxx			    (status_alarms[52:50]	), 	
		.alarm_record_check_xxx			    (status_alarms[55:53]	), 
		.alarm_bytes_number_xxx			    (status_alarms[71:56]	), 
	
		.busy								(status_alarms[72]		),
		.ready                              (status_alarms[73]		)
    );			
			
    ////////////////////////////////////////////////////////////////////////////
    // Mapping USART pins TX
    ////////////////////////////////////////////////////////////////////////////
	//assign tx[(PORTS_UART-1):16] 		= 	tx_uart[(PORTS_UART-1):16];///////////?????????????

	
    ////////////////////////////////////////////////////////////////////////////
    // Mapping USART pins RX
    ////////////////////////////////////////////////////////////////////////////			
	// X10
	assign	rx_uart	=	rx;	            		

	
    ////////////////////////////////////////////////////////////////////////////
    // Mapping EMS pins 
    ////////////////////////////////////////////////////////////////////////////
	wire		OR_ems_rx;
	reg 		OR_ems_rx_reg;
	
	assign manual_xxx_control = control_reg_csr[0];
	assign manual_xxx_value	  = control_reg_csr[1];
	
	assign OR_xxx_rx = |rx[2:0];
	
	always@(posedge sys_clk)
	begin
		if(control_reg_csr[10]) 
			OR_xxx_rx_reg <= !OR_xxx_rx;
		else 
			OR_xxx_rx_reg <= OR_xxx_rx;
	end 	
	
	// EMS summary
	assign tx[60]		=   (manual_xxx_control) ? manual_ems_value : // manual control TR AFAR
							(zi_enable		   ) ? 1'b1			    : // disable TR AFAR 	
							OR_ems_rx_reg;							  // MCPFS control TR AFAR

							
	assign zi_enable =  	(s_usr_dat_xxxi_x1	&& csr_usr_dat_xxx_mask[0] )
						||	(s_usr_dat_xxxi_x2	&& csr_usr_dat_xxx_mask[1] )
						||	(s_usr_dat_xxxi_x3    && csr_usr_dat_xxx_mask[2] )
						||	(s_usr_dat_xxxi_x4	&& csr_usr_dat_xxx_mask[3] )		
						||	(s_usr_dat_xxxi_ku1	&& csr_usr_dat_xxx_mask[4] )
						||	(s_usr_dat_xxxi_ku2	&& csr_usr_dat_xxx_mask[5] )
						||	(s_usr_dat_xxxi_ku3   && csr_usr_dat_xxx_mask[6] )
						||	(s_usr_dat_xxxi_ku4   && csr_usr_dat_xxx_mask[7] ) ;


						
    ////////////////////////////////////////////////////////////////////////////
    // Status CSR register
    ////////////////////////////////////////////////////////////////////////////	
	
	assign status_reg_csr[0] 	= 1'b1				;
	assign status_reg_csr[1] 	= 1'b1				;
	assign status_reg_csr[2] 	= 1'b1				;
	assign status_reg_csr[3] 	= 1'b1				;
	assign status_reg_csr[4] 	= 1'b0				;
	assign status_reg_csr[5] 	= 1'b0				;
	assign status_reg_csr[6] 	= 1'b0				;
	assign status_reg_csr[7] 	= 1'b0				;
	assign status_reg_csr[8] 	= s_usr_dat_xxx_x1	;
	assign status_reg_csr[9] 	= s_usr_dat_xxx_x2	;
	assign status_reg_csr[10]	= s_usr_dat_xxx_x3	;
	assign status_reg_csr[11]	= s_usr_dat_xxx_x4	;
	assign status_reg_csr[12]	= s_usr_dat_xxx_ku1	;
	assign status_reg_csr[13]	= s_usr_dat_xxx_ku2	;
	assign status_reg_csr[14]	= s_usr_dat_xxx_ku3	;
	assign status_reg_csr[15]	= s_usr_dat_xxx_ku4	;
	assign status_reg_csr[16] 	= s_usr_dat_xxx_x1	;
	assign status_reg_csr[17] 	= s_usr_dat_xxx_x2	;
	assign status_reg_csr[18]	= s_usr_dat_xxx_x3	;
	assign status_reg_csr[19]	= s_usr_dat_xxx_x4	;
	assign status_reg_csr[20]	= s_usr_dat_xxx_s1	;
	assign status_reg_csr[21]	= s_usr_dat_xxx_s2	;
	assign status_reg_csr[22]	= s_usr_dat_xxx_s3	;
	assign status_reg_csr[23]	= s_usr_dat_xxx_s4	;	
	
	
    ////////////////////////////////////////////////////////////////////////////
    // EMS wrapper and shared logic
    ////////////////////////////////////////////////////////////////////////////	

	wire 	[1:0]						s_rx_channel				; 
	wire								s_clk_ems_100mhz			;
	wire								s_clk_ems_300mhz			;
	wire								s_locked_mmcm_ems			;
	wire								s_phy_tx_dat_usi			;

	
	IBUFDS 
	#(
      .DIFF_TERM				("FALSE"							),   
      .IBUF_LOW_PWR				("TRUE"								),   
      .IOSTANDARD				("DEFAULT"							)    
	) IBUFDS_x6g_rx_channel_3 (
      .O						(s_rx_channel[0]					),  
      .I						(SST_RX_FPGA_P[0]					),  
      .IB						(SST_RX_FPGA_N[0]					) 
	);	
		
	IBUFDS 
	#(
      .DIFF_TERM				("FALSE"							),   
      .IBUF_LOW_PWR				("TRUE"								),   
      .IOSTANDARD				("DEFAULT"							)    
	) IBUFDS_x6g_rx_channel_4 (
      .O						(s_rx_channel[1]					),  
      .I						(SST_RX_FPGA_P[1]					),  
      .IB						(SST_RX_FPGA_N[1]					) 
	);		

	mcu_mmcm_ems_wrp
	mcu_mmcm_ems_wrp_inst
	(
		.CLK_IN_100MHz			(sys_clk							),
		.CLK_OUT_100MHz			(s_clk_ems_100mhz					),
		.CLK_300_MHz			(s_clk_ems_300mhz					),
		.reset					(sys_reset || soft_reset			),
		.locked             	(s_locked_mmcm_ems					)
	);	
	

	////////////////////////////////////////////////////////////////////////////
    // Generate SFP FPFA/Mezonine
    ////////////////////////////////////////////////////////////////////////////

	wire	[7:0	]													sst_tx_fpga	;
	wire	[48:0	]													sst_tx_mez	;
	
	assign  sst_tx_fpga	=	{8{s_phy_tx_dat_xxx} };
	assign  sst_tx_mez	=	{48{s_phy_tx_dat_xxx}};
	
	
	generate 	
        for (i=0;i<8;i=i+1) begin: gen_out_sfp_fpga
		OBUFDS #(
		  .IOSTANDARD("LVDS"			), 			// Specify the output I/O standard
		  .SLEW		 ("SLOW"			)           // Specify the output slew rate
	   ) OBUFDS_SFP_FPGA (
		  .O		(SST_TX_FPGA_P	[i]	),     		// Diff_p output (connect directly to top-level port)
		  .OB		(SST_TX_FPGA_N	[i]	),   		// Diff_n output (connect directly to top-level port)
		  .I		(sst_tx_fpga	[i]	)     		// Buffer input
	   );
	end
	endgenerate	


	generate 
        for (i=0;i<48;i=i+1) begin: gen_out_sfp_mez
		OBUFDS #(
		  .IOSTANDARD("LVDS"			), 			// Specify the output I/O standard
		  .SLEW		 ("SLOW"			)           // Specify the output slew rate
	   ) OBUFDS_SFP_MEZ (
		  .O		(SST_TX_MEZ_P	[i]	),     		// Diff_p output (connect directly to top-level port)
		  .OB		(SST_TX_MEZ_N	[i]	),   		// Diff_n output (connect directly to top-level port)
		  .I		(sst_tx_mez		[i]	)     		// Buffer input
	   );
	end
	endgenerate	



	
	
	////////////////////////////////////////////////////////////////////////////
    // ChipScope
    ////////////////////////////////////////////////////////////////////////////
    ///////////
  
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [7:0]		      cs_channel_ap	                         ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [7:0]              cs_channel_xxx_0	                     ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [7:0]              cs_channel_xxx_1                       ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [7:0]              cs_channel_xxx_2	                     ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [7:0]              cs_channel_xxx_3	                     ;
                                                                            
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	[2:0]             cs_mode			                      ;					  
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	                  cs_clk_x16		                      ;					 
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	                  cs_rst			                      ;					 

            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	                  cs_manual_mode_tx_receive_ap		      ;	 
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	                  cs_manual_mode_tx_transfer_xxx_ap       ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	                  cs_manual_mode_tx_transfer_xxx_ap       ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	[3:0]             cs_manual_mode_tx_receive_xxx		      ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	[7:0]             cs_manual_mode_tx_xxx  			      ; 
                                                                                                                                
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	                  cs_tx_receive_ap					      ; 
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	                  cs_rx_receive_ap					      ; 
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	                  cs_tx_transfer_xxx_ap				      ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	                  cs_rx_transfer_xxx_ap				      ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	                  cs_tx_transfer_xxx_ap				      ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	                  cs_rx_transfer_xxx_ap				      ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	[3:0]             cs_tx_receive_xxx					      ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	[3:0]             cs_rx_receive_xxx					      ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	[7:0]             cs_tx_xxx	    					      ; 
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	[7:0]             cs_rx_xxx	    					      ; 
                                                                                                                          
             // statuses AUTO_MODE_FREQUENCY_SETUP             
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	[7:0]             cs_status_setup_xxx_ap			      ; 
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	[2:0]             cs_status_setup_receive_xxx_xxx_0       ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	[2:0]             cs_status_setup_receive_xxx_xxx_1       ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	[2:0]             cs_status_setup_receive_xxx_xxx_2       ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	[2:0]             cs_status_setup_receive_xxx_xxx_3       ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	[7:0]             cs_status_setup_transfer_xxx_xxx_ap     ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	                  cs_status_setup_transfer_xxx_xxx_xxx    ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	[7:0]             cs_status_setup_receive_xxx_ap          ;
                                                                                                                             
            // statuses Diagnoze_MODE                         
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	                  cs_status_check_tx_receive_xxx		  ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	                  cs_status_check_tx_transfer_xxx         ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	                  cs_status_check_tx_transfer_xxx         ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	[3:0]             cs_status_check_tx_receive_xxx	      ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	[7:0]             cs_status_check_tx_xxx			      ; 

            // Alarms                                                   
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [7:0]             cs_alarm_bytes_number_xxx				  ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [7:0]             cs_alarm_record_check_xxx				  ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg                    cs_alarm_bytes_number_xxx				  ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg                    cs_alarm_record_check_xxx				  ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [7:0]             cs_alarm_bytes_number_receive_ap		  ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [7:0]             cs_alarm_record_check_receive_ap		  ;
                                   
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [2:0]             cs_alarm_bytes_number_receive_xxx 	  ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [2:0]             cs_alarm_record_check_receive_xxx 	  ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [2:0]             cs_alarm_bytes_number_receive_xxx 	  ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [2:0]             cs_alarm_record_check_receive_xxx 	  ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [2:0]             cs_alarm_bytes_number_receive_xxx 	  ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [2:0]             cs_alarm_record_check_receive_xxx 	  ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [2:0]             cs_alarm_bytes_number_receive_xxx 	  ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [2:0]             cs_alarm_record_check_receive_xxx 	  ;
                                  
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [2:0]             cs_alarm_bytes_number_xxx			      ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [2:0]             cs_alarm_record_check_xxx			      ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [14:0]            cs_alarm_bytes_number_check			  ;
          
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg                    cs_busy								  ;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [3:0]             cs_up_channel_up                        ;                        
            
            always @(posedge sys_clk) begin 
                                                                                                     
                     cs_up_channel_up                         <=    {down_channel_up   , up_channel_up            }                       ;                                                                                                         
                     cs_channel_ap	                          <=    s_regX22_resync[39:32]                                                ;
                     cs_channel_xxx_0	                      <=    s_regX23_resync[23:16]		                                          ;
                     cs_channel_xxx_1                         <=    s_regX23_resync[55:48]		                                          ;
                     cs_channel_xxx_2	                      <=    s_regX24_resync[23:16]		                                          ;
                     cs_channel_xxx_3	                      <=    s_regX24_resync[55:48]		                                          ;
                                                                    
                     cs_mode			                      <=	s_regX25_resync[2:0]		                                          ;
                     cs_clk_x16		                          <=	usart_cnt_clk_meopg		                                              ;
                     cs_rst			                          <=	sys_reset_n || soft_reset_n		                                      ;
                                                                                                      
                     cs_manual_mode_tx_receive_ap		      <=    tx_uart	[4]			                                                  ;
                     cs_manual_mode_tx_transfer_xxx_ap        <=    tx_uart	[59]				                                          ;
                     cs_manual_mode_tx_transfer_xxx_ap        <=    tx_uart	[58]				                                          ;
                     cs_manual_mode_tx_receive_xxx		      <=    tx_uart	[3:0]			                                              ;
                     cs_manual_mode_tx_xxx			          <=    {tx_uart[34:30],tx_uart[63:61]}                                       ;
                            
                     cs_tx_receive_ap					      <=    tx		[4]		                                                      ;
                     cs_rx_receive_ap					      <=    rx_uart	[4]		                                                      ;	
                     cs_tx_transfer_xxx_ap				      <=    tx		[59]		                                                  ;
                     cs_rx_transfer_xxx_ap				      <=    rx_uart	[59]		                                                  ;	
                     cs_tx_transfer_xxx_ap				      <=    tx		[58]		                                                  ;
                     cs_rx_transfer_xxx_ap				      <=    rx_uart	[58]		                                                  ;	
                     cs_tx_receive_xxx					      <=    tx		[3:0]	                                                      ;
                     cs_rx_receive_xxx					      <=    rx_uart	[3:0]	                                                      ;	
                     cs_tx_xxx						          <=    {tx      [34:30],tx[63:61]     }	                                  ;		
                     cs_rx_xxx						          <=    {rx_uart [34:30],rx_uart[63:61]}	                                  ;                                     
                                                  
                     cs_status_setup_xxx_ap			          <=   status_automode   [7:0]	                                              ;
                     cs_status_setup_receive_afar_xxx_0       <=   status_automode   [10:8]		                                          ;
                     cs_status_setup_receive_afar_xxx_1       <=   status_automode   [13:11]		                                      ;
                     cs_status_setup_receive_afar_xxx_2       <=   status_automode   [16:14]		                                      ;
                     cs_status_setup_receive_afar_xxx_3       <=   status_automode   [19:17]		                                      ;
                     cs_status_setup_transfer_xxx_ap          <=   status_automode   [27:20]	                                          ;       
                     cs_status_setup_transfer_xxx_apaf        <=   status_automode   [28]		                                          ;
                     cs_status_setup_receive_afar_ap          <=   status_automode   [36:29]		                                      ;
                                                     
                                                     
                     cs_status_check_tx_receive_ap		      <=   status_diagmode[0]	                                                  ;
                     cs_status_check_tx_transfer_xxx          <=   status_diagmode[1]	                                                  ;
                     cs_status_check_tx_transfer_xxx          <=   status_diagmode[2]	                                                  ;
                     cs_status_check_tx_receive_xxx	          <=   status_diagmode[6:3]	                                                  ;
                     cs_status_check_tx_xxx  			      <=   status_diagmode[14:7]                                                  ;
                       
                                                           
                     cs_alarm_bytes_number_xxx				  <=     status_alarms[81:74]	                                             ;
                     cs_alarm_record_check_xxx				  <=     status_alarms[7:0]		                                             ;
                     cs_alarm_bytes_number_xxx				  <=     status_alarms[8]		                                             ;
                     cs_alarm_record_check_xxx				  <=     status_alarms[9]		                                             ;
                     cs_alarm_bytes_number_receive_ap		  <=     status_alarms[17:10]	                                             ;
                     cs_alarm_record_check_receive_ap		  <=     status_alarms[25:18]	                                             ;     
                                                   
                     cs_alarm_bytes_number_receive_xxx_0	  <=     status_alarms[28:26]                                                ;
                     cs_alarm_record_check_receive_xxx_0	  <=     status_alarms[31:29]                                                ;
                     cs_alarm_bytes_number_receive_xxx_1	  <=     status_alarms[34:32]                                                ;
                     cs_alarm_record_check_receive_xxx_1	  <=     status_alarms[37:35]                                                ;
                     cs_alarm_bytes_number_receive_xxx_2	  <=     status_alarms[40:38]                                                ;
                     cs_alarm_record_check_receive_xxx_2	  <=     status_alarms[43:41]                                                ;
                     cs_alarm_bytes_number_receive_xxx_3	  <=     status_alarms[46:44]                                                ;
                     cs_alarm_record_check_receive_xxx_3	  <=     status_alarms[49:47]                                                ;
                                                                                                                                         
                     cs_alarm_bytes_number_xxx			      <=     status_alarms[52:50]	                                             ;
                     cs_alarm_record_check_xxx			      <=     status_alarms[55:53]	                                             ;
                     cs_alarm_bytes_number_check			  <=     status_alarms[71:56]                                                ;
                                                                                                                                         
                     cs_busy								  <=     status_alarms[72]	                                                 ;
   
end                                                                                                                                       
                                                                                	                                                      
/*
    generate
        if (USE_CHIPSCOPE) begin: gen_chipscope
            
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [UPLINKS*TDATA_WIDTH-1:0]    cs_up_tx_tdata;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [UPLINKS-1:0]                cs_up_tx_tvalid;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [UPLINKS-1:0]                cs_up_tx_tlast;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [UPLINKS-1:0]                cs_up_tx_tready;

            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [UPLINKS*TDATA_WIDTH-1:0]    cs_up_rx_tdata;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [UPLINKS-1:0]                cs_up_rx_tvalid;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [UPLINKS-1:0]                cs_up_rx_tlast;

            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [DOWNLINKS*TDATA_WIDTH-1:0]  cs_down_tx_tdata;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [DOWNLINKS-1:0]              cs_down_tx_tvalid;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [DOWNLINKS-1:0]              cs_down_tx_tlast;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [DOWNLINKS-1:0]              cs_down_tx_tready;

            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [DOWNLINKS*TDATA_WIDTH-1:0]  cs_down_rx_tdata;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [DOWNLINKS-1:0]              cs_down_rx_tvalid;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [DOWNLINKS-1:0]              cs_down_rx_tlast;
            
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [DOWNLINKS-1:0]             cs_down_hard_err;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [DOWNLINKS-1:0]             cs_down_soft_err;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [DOWNLINKS-1:0]             cs_down_lane_up;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [DOWNLINKS-1:0]             cs_down_channel_up;

            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [UPLINKS-1:0]               cs_up_hard_err;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [UPLINKS-1:0]               cs_up_soft_err;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [UPLINKS-1:0]               cs_up_lane_up;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [UPLINKS-1:0]               cs_up_channel_up;
                       
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [DOWNLINKS-1:0]             cs_arbiter_down_status_timeout;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [UPLINKS-1:0]               cs_arbiter_up_status_timeout  ;

            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg                              cs_ctrl_soft_reset_request;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg                              cs_ctrl_aurora_reset_request;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg                              cs_sys_reset_n;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg                              cs_soft_reset;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg                              cs_aurora_reset;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg                              cs_csr_reset_n;
			(* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 								cs_s_mmcm_input_clk_stopped;
			(* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 								cs_locked_mmcm_mcu_rto	;					
			
			

            always @(posedge sys_clk) begin
                
                cs_up_tx_tdata                      <= up_tx_tdata ;
                cs_up_tx_tvalid                     <= up_tx_tvalid;
                cs_up_tx_tlast                      <= up_tx_tlast ;
                cs_up_tx_tready                     <= up_tx_tready;

                cs_up_rx_tdata                      <= up_rx_tdata ;
                cs_up_rx_tvalid                     <= up_rx_tvalid;
                cs_up_rx_tlast                      <= up_rx_tlast ;

                cs_down_tx_tdata                    <= down_tx_tdata ; 
                cs_down_tx_tvalid                   <= down_tx_tvalid;
                cs_down_tx_tlast                    <= down_tx_tlast ;
                cs_down_tx_tready                   <= down_tx_tready;

                cs_down_rx_tdata                    <= down_rx_tdata ;
                cs_down_rx_tvalid                   <= down_rx_tvalid;
                cs_down_rx_tlast                    <= down_rx_tlast ;
                
                cs_down_hard_err                    <= down_hard_err  ;
                cs_down_soft_err                    <= down_soft_err  ;
                cs_down_lane_up                     <= down_lane_up   ;
                cs_down_channel_up                  <= down_channel_up;
                
                cs_up_hard_err                      <= up_hard_err  ;
                cs_up_soft_err                      <= up_soft_err  ;
                cs_up_lane_up                       <= up_lane_up   ;
                cs_up_channel_up                    <= up_channel_up;
                
          
                cs_ctrl_soft_reset_request          <= ctrl_soft_reset_request  ;
                cs_ctrl_aurora_reset_request        <= ctrl_aurora_reset_request;
                cs_sys_reset_n                      <= sys_reset_n              ;
                cs_soft_reset                       <= soft_reset               ;
                cs_aurora_reset                     <= aurora_reset             ;
                cs_csr_reset_n                      <= csr_reset_n              ;
				
				cs_s_mmcm_input_clk_stopped			<= s_mmcm_input_clk_stopped	;
				cs_locked_mmcm_mcu_rto				<= locked_mmcm_mcu_rto		;
            end
        end
    endgenerate
	
	
    generate
        if (USE_CHIPSCOPE_USI) begin: gen_chipscope_usi
            
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [UPLINKS*TDATA_WIDTH-1:0]    cs_up_tx_tdata;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [UPLINKS-1:0]                cs_up_tx_tvalid;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [UPLINKS-1:0]                cs_up_tx_tlast;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [UPLINKS-1:0]                cs_up_tx_tready;

            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [UPLINKS*TDATA_WIDTH-1:0]    cs_up_rx_tdata;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [UPLINKS-1:0]                cs_up_rx_tvalid;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [UPLINKS-1:0]                cs_up_rx_tlast;

            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [DOWNLINKS*TDATA_WIDTH-1:0]  cs_down_tx_tdata;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [DOWNLINKS-1:0]              cs_down_tx_tvalid;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [DOWNLINKS-1:0]              cs_down_tx_tlast;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [DOWNLINKS-1:0]              cs_down_tx_tready;

            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [DOWNLINKS*TDATA_WIDTH-1:0]  cs_down_rx_tdata;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [DOWNLINKS-1:0]              cs_down_rx_tvalid;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [DOWNLINKS-1:0]              cs_down_rx_tlast;
            
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [DOWNLINKS-1:0]             cs_down_hard_err;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [DOWNLINKS-1:0]             cs_down_soft_err;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [DOWNLINKS-1:0]             cs_down_lane_up;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [DOWNLINKS-1:0]             cs_down_channel_up;

            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [UPLINKS-1:0]               cs_up_hard_err;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [UPLINKS-1:0]               cs_up_soft_err;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [UPLINKS-1:0]               cs_up_lane_up;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [UPLINKS-1:0]               cs_up_channel_up;
                       
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [DOWNLINKS-1:0]             cs_arbiter_down_status_timeout;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg  [UPLINKS-1:0]               cs_arbiter_up_status_timeout  ;

            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg                              cs_ctrl_soft_reset_request;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg                              cs_ctrl_aurora_reset_request;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg                              cs_sys_reset_n;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg                              cs_soft_reset;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg                              cs_aurora_reset;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg                              cs_csr_reset_n;
			(* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 								cs_s_mmcm_input_clk_stopped;
			(* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 								cs_locked_mmcm_mcu_rto	;	

			(* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	 							cs_csr_usr_dat_xxx_sim_en	 		;
			(* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [11:0] 						cs_csr_usr_dat_xxx_sim_hold			;
			(* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [11:0]						cs_csr_usr_dat_xxx_sim_setup 		;
			(* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [7:0 ]						cs_csr_usr_dat_xxx_sim_mask			;
			(* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 								cs_csr_usr_dat_xxx_invert_en 		;
			(* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [11:0]						cs_csr_usr_dat_xxx_delay	 		;
			(* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [7:0 ]						cs_csr_usr_dat_xxx_duration			;	

			(* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 	 							cs_s_usr_dat_xxx_x1			;		
			(* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 								cs_s_usr_dat_xxx_x2			;		
			(* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 								cs_s_usr_dat_xxx_x3			;		
			(* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 								cs_s_usr_dat_xxx_x4			;		
			(* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 								cs_s_usr_dat_xxx_ku1	    ;		
			(* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 								cs_s_usr_dat_xxx_ku2	    ;		
			(* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 								cs_s_usr_dat_xxx_ku3	    ;	
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg      						cs_s_usr_dat_xxx_ku4	    ;	
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg      						cs_s_usr_dat_xxx_x1			;	
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg      						cs_s_usr_dat_xxx_x2			;	
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg      						cs_s_usr_dat_xxx_x3			;	
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg      						cs_s_usr_dat_xxx_x4			;	
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg      						cs_s_usr_dat_xxx_s1			;	
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg      						cs_s_usr_dat_xxx_s2			;	
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg      						cs_s_usr_dat_xxx_s3			;	
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg      						cs_s_usr_dat_xxx_s4			;	

            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 								cs_s_locked_mmcm_xxx 		;
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg [1:0]						cs_s_rx_channel				; 
            (* TIG="TRUE" *) (* KEEP = "TRUE" *) (* mark_debug = "true" *) reg 								cs_s_phy_tx_dat_xxx			;




            always @(posedge sys_clk) begin
                
                cs_up_tx_tdata                      <= up_tx_tdata ;
                cs_up_tx_tvalid                     <= up_tx_tvalid;
                cs_up_tx_tlast                      <= up_tx_tlast ;
                cs_up_tx_tready                     <= up_tx_tready;

                cs_up_rx_tdata                      <= up_rx_tdata ;
                cs_up_rx_tvalid                     <= up_rx_tvalid;
                cs_up_rx_tlast                      <= up_rx_tlast ;

                cs_down_tx_tdata                    <= down_tx_tdata ; 
                cs_down_tx_tvalid                   <= down_tx_tvalid;
                cs_down_tx_tlast                    <= down_tx_tlast ;
                cs_down_tx_tready                   <= down_tx_tready;

                cs_down_rx_tdata                    <= down_rx_tdata ;
                cs_down_rx_tvalid                   <= down_rx_tvalid;
                cs_down_rx_tlast                    <= down_rx_tlast ;
                
                cs_down_hard_err                    <= down_hard_err  ;
                cs_down_soft_err                    <= down_soft_err  ;
                cs_down_lane_up                     <= down_lane_up   ;
                cs_down_channel_up                  <= down_channel_up;
                
                cs_up_hard_err                      <= up_hard_err  ;
                cs_up_soft_err                      <= up_soft_err  ;
                cs_up_lane_up                       <= up_lane_up   ;
                cs_up_channel_up                    <= up_channel_up;
                
          
                cs_ctrl_soft_reset_request          <= ctrl_soft_reset_request  ;
                cs_ctrl_aurora_reset_request        <= ctrl_aurora_reset_request;
                cs_sys_reset_n                      <= sys_reset_n              ;
                cs_soft_reset                       <= soft_reset               ;
                cs_aurora_reset                     <= aurora_reset             ;
                cs_csr_reset_n                      <= csr_reset_n              ;
				
				cs_s_mmcm_input_clk_stopped			<= s_mmcm_input_clk_stopped	;
				cs_locked_mmcm_mcu_rto				<= locked_mmcm_mcu_rto		;
				
				cs_csr_usr_dat_xxx_sim_en			<= csr_usr_dat_xxx_sim_en	;			
				cs_csr_usr_dat_xxx_sim_hold			<= csr_usr_dat_xxx_sim_hold	;			
				cs_csr_usr_dat_xxx_sim_setup		<= csr_usr_dat_xxx_sim_setup;			
				cs_csr_usr_dat_xxx_sim_mask			<= csr_usr_dat_xxx_sim_mask	;			
				cs_csr_usr_dat_xxx_invert_en		<= csr_usr_dat_xxx_invert_en;			
				cs_csr_usr_dat_xxx_delay			<= csr_usr_dat_xxx_delay	;			
				cs_csr_usr_dat_xxx_duration			<= csr_usr_dat_xxx_duration	;	

				cs_s_usr_dat_xxx_x1					<= s_usr_dat_xxx_x1			;						
				cs_s_usr_dat_xxx_x2				    <= s_usr_dat_xxx_x2			;			
				cs_s_usr_dat_xxx_x3				    <= s_usr_dat_xxx_x3			;			
				cs_s_usr_dat_xxx_x4				    <= s_usr_dat_xxx_x4			;			
				cs_s_usr_dat_xxx_ku1					<= s_usr_dat_xxx_ku1			;			
				cs_s_usr_dat_xxx_ku2					<= s_usr_dat_xxx_ku2			;			
				cs_s_usr_dat_xxx_ku3					<= s_usr_dat_xxx_ku3			;			
				cs_s_usr_dat_xxx_ku4					<= s_usr_dat_xxx_ku4			;			
				cs_s_usr_dat_xxx_x1					<= s_usr_dat_xxx_x1			;			
				cs_s_usr_dat_xxx_x2					<= s_usr_dat_xxx_x2			;			
				cs_s_usr_dat_xxx_x3					<= s_usr_dat_xxx_x3			;			
				cs_s_usr_dat_xxx_x4					<= s_usr_dat_xxx_x4			;			
				cs_s_usr_dat_xxx_s1					<= s_usr_dat_xxx_s1			;			
				cs_s_usr_dat_xxx_s2					<= s_usr_dat_xxx_s2			;			
				cs_s_usr_dat_xxx_s3					<= s_usr_dat_xxx_s3			;			
				cs_s_usr_dat_xxx_s4					<= s_usr_dat_xxx_s4			;			

            end
			
			
            always @(posedge s_clk_xxx_300mhz) begin
                
                cs_s_locked_mmcm_xxx                <= s_locked_mmcm_xxx 	;
                cs_s_rx_channel[0]                  <= s_rx_channel[0]		;
                cs_s_rx_channel[1]                  <= s_rx_channel[1] 		;

            end			
		
			
            always @(posedge s_clk_xxx_100mhz) begin
                
                cs_s_phy_tx_dat_xxx               	<= s_phy_tx_dat_xxx 	;

            end						
			
        end
    endgenerate	
	   */
endmodule




