`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////
// engineer Kalashnikov N.A
////////////////////////////////////////////////////////////////////////////////
`define N(c)             [(c)-1:0]

module i2c_master_build #(
  parameter SPEED_W                   = 4,
  parameter BYTE_W                    = 8,
  parameter CMD_W                     = 4,
  //50ms/1µs = 50_000; log2(50_000) = 16
  parameter LOW_SEXT_MEXT_W           = 16

)(
  // clock (48 MHz)
  input  logic                        clk,
  // reset (inversed)
  input  logic                        rst,
  // clock divider value
  input  logic `N(SPEED_W)            speed,
  // i2c start command,operation begins on rising edge
  input  logic                        valid_i,
  output logic                        valid_o,
  // read byte data from a slave
  output logic `N(BYTE_W)             data_rd,
  // write byte data to slave
  input  logic `N(BYTE_W)             data_wr,
  // start command
  input  logic `N(CMD_W)              cmd_i,
  // control command
  output  logic `N(CMD_W)             cmd_o,
  // ready to receive a command
  output logic                        ready,
  // acknowledge from slave
  output logic                        ack_s,
  // bus i2c
  inout  logic                        i2c_sda,
  inout  logic                        i2c_scl,
  // limit time of one command. measure unit - 1µs
  input  logic `N(LOW_SEXT_MEXT_W)    limit_low_mex,
  // time limit for all commands except start and stop
  input  logic `N(LOW_SEXT_MEXT_W)    limit_low_sext,
  // the time limit of one command has been reached
  output logic                        reach_tim_low_mex,
  // the time limit for all commands except start and stop has been reached
  output logic                        reach_tim_low_sext
);

//selected divide i2c_scl
//i2c_scl = (clk/2^(1+speed))/60

// selected command //
// waiting for the command
localparam IDLE            = 0; //--> waiting for the command
// condition start and restart
localparam S               = 1; //--> |S|
// stop condition
localparam P               = 2; //--> |P|
// writing data to the SLAVE
// A_S - acknowledge bit from the SLAVE
// DATA_W - byte of writing to the SLAVE
localparam W               = 3; //--> |DATA_W|A_S|
// reading data from a SLAVE
// DATA_R - read a byte from a SLAVE
// A_M - acknowledge bit from MASTER
localparam R               = 4; //--> |DATA_R|A_M|
// reading data from the SLAVE (without ACK confirmation)
// AN_M - bit without acknowledge from MASTER
// DATA_R - read a byte from a SLAVE
localparam RN              = 5; //--> |DATA_R|AN_M|

// 24 MHz -> max clk_div // T = 1/24 MHz = 41.67 nS
// 0.4 MHz -> max scl_i2c // T = 1/0.4 MHz = 1.25 microS
// cnt_clk_div = 24 MHz / 0.4 MHz = 60 ->the period time of the SCL clock signal is 0.4 MHz
// cnt_clk_div = 60 / 4 = 15 -> the quarter-period time of the SCL clock signal is 0.4 MHz
localparam QUARTER_PER_SCL       = 15;
localparam DIV_CLK_W          = 12;
localparam CNT_DIV_W          = 10;
localparam CNT_QUARTER_PER_W  = 6;

// i2c bidirectional signals
logic                        scl_oe;
logic                        sda_oe;
// flag completion of the command
logic                        cmd_end;
// byte to write to the slave
logic `N(BYTE_W)             data_wr_r;
// selecting a command to execute
logic `N(CMD_W)              cmd_i_r;
// SCL frequency
logic `N(SPEED_W)            speed_r;
// frequency divider
logic `N(DIV_CLK_W)          div;
// the result of the divided frequency (div)
logic                        clk_div;
// pulse along the rising edge
logic                        clk_div_ris;
// counter based on clk_div
logic `N(CNT_DIV_W)          cnt_clk_div;
// flag - holding  in the law state of the slave
logic                        slave_delay;
// SCL quarter period counter
logic `N(CNT_QUARTER_PER_W)  cnt_quarter_per;

edge_detect _clk_div_ris (
.clk( clk ),
.nrst( 1'b1 ),
.in( clk_div ),
.rising( clk_div_ris ),
.falling( ),
.both(  )
);

// open-drain i2c bidir ports
assign i2c_sda = sda_oe ? '0  : 'z ;
assign i2c_scl = scl_oe ? '0  : 'z ;

// flag holding  in the law state of the slave
assign slave_delay = (~scl_oe & ~i2c_scl)? '1 : '0;

always_ff @(posedge clk)begin
  if(rst || cmd_end)begin
    ready            <= '0;
    valid_o          <= '0;
    div              <= '0;
    cnt_clk_div      <= '0;
    cnt_quarter_per  <= '0;
    ack_s            <= '0;
    cmd_end          <= '0;
    scl_oe           <= '0;
    sda_oe           <= '0;
    cmd_i_r          <= '0;
    cmd_o            <= '0;
  end else begin
    // сounter quarter-cycle of the SCL clock signal
    if(clk_div_ris & ~slave_delay)begin
      cnt_clk_div <= cnt_clk_div + 1'b1;
      if(cnt_clk_div == QUARTER_PER_SCL-1'b1)begin
        cnt_quarter_per <= cnt_quarter_per + 1'b1;
        cnt_clk_div     <= '0;
     end
    end
    div       <= div + 1'b1;
    clk_div   <= div[speed];
    cmd_end   <= '0;

    if (valid_i & ready)begin
      valid_o         <= '0;
      ready           <= '0;
      cnt_clk_div     <= '0;
      cnt_quarter_per <= '0;
      ack_s           <= '0;
      data_wr_r       <= data_wr ;
      speed_r         <= speed;
      cmd_i_r         <= cmd_i;
    end else begin

      // IDLE - waiting or non-existent command
      if(cmd_i_r == IDLE || cmd_i_r > RN)begin
        ready     <= '1;
        sda_oe    <= '0;
        scl_oe    <= '0;
        cmd_o     <= '0;
        data_rd   <= '0;
      end

      // S – condition start and restart;
      //                   ___
      //          DATA  XXX   |______
      //                   ______
      //           SCL  XXX      |___
      //
      //cnt_quarter_per 0  1  2  3  4
      //XXX - for the first quarter of the period, the state of the lines remains unchanged
      if(cmd_i_r == S)begin
        case (cnt_quarter_per)
          0 : begin end
          1 : begin
              sda_oe    <= '0;
              scl_oe    <= '0;
              end
          2 : sda_oe    <= '1;
          3 : scl_oe    <= '1;
          4 : begin
                valid_o <= '1;
                ready   <= '1;
                cmd_o   <= S;
                data_rd <= '0;
              end
          5 : cmd_end   <= '1;
          default : /* default */;
        endcase
      end

      // P - stop condition;
      //                          ___
      //          DATA  _________|
      //                       ______
      //           SCL  ______|
      //
      //cnt_quarter_per 0  1  2  3  4
      if(cmd_i_r == P)begin
        // delay   <= '1;
        case (cnt_quarter_per)
          0 : begin
                sda_oe  <= '1;
                scl_oe  <= '1;
              end
          2 : scl_oe    <= '0;
          3 : sda_oe    <= '0;
          4 : begin
                valid_o <= '1;
                ready   <= '1;
                cmd_o   <= P;
                data_rd <= '0;
              end
          5 : cmd_end   <= '1;
          default : /* default */;
        endcase
      end

      // W – writing data to the SLAVE

      //       DATA     |    bit7   |    bit6   | ... |    bit0   |    A_S    |
      //                    _____       _____             _____       _____
      //        SCL     ___|     |_____|     |___ ... ___|     |_____|     |___

      //cnt_quarter_per 0  1  2  3  4  5  6  7  8 ... 28 29 30 31 32 33 34 35 36

      if(cmd_i_r == W)begin
        case (cnt_quarter_per)
          0   : begin
                  scl_oe  <= '1;
                  sda_oe  <= data_wr_r[8'h7] ? '0 : '1 ;
                end
          1   : scl_oe    <= '0;
          3   : scl_oe    <= '1;
          4   : sda_oe    <= data_wr_r[8'h6] ? '0 : '1 ;
          5   : scl_oe    <= '0;
          7   : scl_oe    <= '1;
          8   : sda_oe    <= data_wr_r[8'h5] ? '0 : '1 ;
          9   : scl_oe    <= '0;
          11  : scl_oe    <= '1;
          12  : sda_oe    <= data_wr_r[8'h4] ? '0 : '1 ;
          13  : scl_oe    <= '0;
          15  : scl_oe    <= '1;
          16  : sda_oe    <= data_wr_r[8'h3] ? '0 : '1 ;
          17  : scl_oe    <= '0;
          19  : scl_oe    <= '1;
          20  : sda_oe    <= data_wr_r[8'h2] ? '0 : '1 ;
          21  : scl_oe    <= '0;
          23  : scl_oe    <= '1;
          24  : sda_oe    <= data_wr_r[8'h1] ? '0 : '1 ;
          25  : scl_oe    <= '0;
          27  : scl_oe    <= '1;
          28  : sda_oe    <= data_wr_r[8'h0] ? '0 : '1 ;
          29  : scl_oe    <= '0;
          31  : scl_oe    <= '1;
          32  : sda_oe    <= '0;
          33  : scl_oe    <= '0;
          34  : ack_s     <= ~i2c_sda;
          35  : scl_oe    <= '1;
          36  : begin
                  valid_o <= '1;
                  ready   <= '1;
                  cmd_o   <= W;
                  data_rd <= '0;
                end
          37  : cmd_end   <= '1;
          default   : /* default */;
        endcase
      end

      // R – reading data from a SLAVE and RN – reading data from the
      // SLAVE (without ACK confirmation)

      //       DATA     |    bit7   |    bit6   | ... |    bit0   | A_M / AN_M |
      //                    _____       _____             _____       _____
      //        SCL     ___|     |_____|     |___ ... ___|     |_____|     |___

      //cnt_quarter_per 0  1  2  3  4  5  6  7  8 ... 28 29 30 31 32 33 34 35 36
      if(cmd_i_r == RN || cmd_i_r == R)begin
        case (cnt_quarter_per)
          0   : begin
                  sda_oe      <= '0;
                  scl_oe      <= '1;
                end
          1   : scl_oe        <= '0;
          2   : data_rd[8'h7] <= i2c_sda;
          3   : scl_oe        <= '1;
          5   : scl_oe        <= '0;
          6   : data_rd[8'h6] <= i2c_sda;
          7   : scl_oe        <= '1;
          9   : scl_oe        <= '0;
          10  : data_rd[8'h5] <= i2c_sda;
          11  : scl_oe        <= '1;
          13  : scl_oe        <= '0;
          14  : data_rd[8'h4] <= i2c_sda;
          15  : scl_oe        <= '1;
          17  : scl_oe        <= '0;
          18  : data_rd[8'h3] <= i2c_sda;
          19  : scl_oe        <= '1;
          21  : scl_oe        <= '0;
          22  : data_rd[8'h2] <= i2c_sda;
          23  : scl_oe        <= '1;
          25  : scl_oe        <= '0;
          26  : data_rd[8'h1] <= i2c_sda;
          27  : scl_oe        <= '1;
          29  : scl_oe        <= '0;
          30  : data_rd[8'h0] <= i2c_sda;
          31  : scl_oe        <= '1;
          32  : sda_oe        <= (cmd_i_r == R);
          33  : scl_oe        <= '0;
          35  : scl_oe        <= '1;
          36  : begin
                  valid_o     <= '1;
                  ready       <= '1;
                  if(cmd_i_r == RN) cmd_o   <= RN; else cmd_o   <= R;
                end
          37  : cmd_end       <= '1;
          default   : /* default */;
        endcase
      end
    end
  end
end


//  START                                                                            STOP
//    |  |             t_low_mex             |        t_low_mex                  |    |
//    |<>|<--------------------------------->|<--------------------------------->|<-->|
//    |  |                            t_low_sext                                 |    |
//    |<----------------------------------------------------------------------------->|
//    |  |                                   |                                   |    |
//   ___   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _______
//SCL   |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_|
//         0   1   2   3   4   5   6   7   8   0   1   2   3   4   5   6   7   8
//   _                                                                                 ___
//    |  | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |   | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |   |    |
//    |  | B | B | B | B | B | B | B | B | A | B | B | B | B | B | B | B | B | A |    |
//DAT |  | I | I | I | I | I | I | I | I | C | I | I | I | I | I | I | I | I | C |    |
//    |__| T | T | T | T | T | T | T | T | K | T | T | T | T | T | T | T | T | K |____|

// logic clk_div_ris;
// edge_detect _ready_fall (
// .clk( clk ),
// .nrst( 1'b1 ),
// .in( ready ),
// .rising(  ),
// .falling( ready_fall ),
// .both(  )
// );

//1µs/1/48MHZ = 48; log2(48)     = 6
localparam DIV_CNT_MEXT_SEXT_W   = 6;
localparam ONE_MICRO_SEC         = 48-1;

logic `N(LOW_SEXT_MEXT_W)     cnt_t_low_mex;
logic `N(LOW_SEXT_MEXT_W)     cnt_t_low_sext;
logic `N(DIV_CNT_MEXT_SEXT_W) div_cnt_mex;
logic `N(DIV_CNT_MEXT_SEXT_W) div_cnt_sext;
// start of execution of the start command
logic begin_com_s;
// end of execution of the stop command
logic end_com_p;
// start condition of the start command
assign begin_com_s = (cmd_i == S) & valid_i & ready;
// stop command completion condition
assign end_com_p   = (cmd_i_r == P) & valid_o;
always_ff @(posedge clk)begin
  if(rst)begin
    cnt_t_low_mex       <= '0;
    cnt_t_low_sext      <= '0;
    div_cnt_mex         <= '0;
    div_cnt_sext        <= '0;
    reach_tim_low_mex   <= '0;
    reach_tim_low_sext  <= '0;
  end else begin
// checking the execution time of all commands except start and stop(t_low_sext)
    //if((cmd_i_r == P && valid_o == '1) || cmd_i_r == IDLE || cmd_i_r == S)begin
    if( begin_com_s || cmd_i_r == IDLE || end_com_p)begin
      div_cnt_sext       <= 2;
      cnt_t_low_sext     <= '0;
      reach_tim_low_sext <= '0;
    end else begin
      div_cnt_sext <= div_cnt_sext + 1'b1;
      if(div_cnt_sext == ONE_MICRO_SEC ) begin
        div_cnt_sext   <= '0;
        cnt_t_low_sext <= cnt_t_low_sext + 1'b1;
      end
      if(cnt_t_low_sext == limit_low_sext) reach_tim_low_sext <= '1;
    end
// checking the execution time of the transmission of a single command(t_low_mex)
    // if(ready_fall)begin
      if(ready)begin
      div_cnt_mex       <= 3;
      cnt_t_low_mex     <= '0;
      reach_tim_low_mex <= '0;
    end else begin
      //if(~ready)div_cnt_mex <= div_cnt_mex + 1'b1;
      div_cnt_mex <= div_cnt_mex + 1'b1;
      if(div_cnt_mex == ONE_MICRO_SEC ) begin
        div_cnt_mex   <= '0;
        cnt_t_low_mex <= cnt_t_low_mex + 1'b1;
      end
      if(cnt_t_low_mex == limit_low_mex) reach_tim_low_mex <= '1;
    end
  end
end

endmodule



















