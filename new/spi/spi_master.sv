
// RXI - EXT_IF - SYNC1200's mezzanine
// EXT_IF mezzanine external interfaces controller FPGA
// spi master controller module
// modified version of https://github.com/pConst/basic_verilog/blob/master/spi_master.sv

module spi_master #( parameter

  bit [7:0] MAX_DATA_WIDTH = 250,// maximal data word width in bits

  bit MSB_FIRST = 1              // 0 - LSB first
                                 // 1 - MSB first
)(
  input clk,                     // system clock
  input nrst,                    // reset (inversed)

  input spi_clk,                 // prescaler clock
                                 // spi_clk must be >= 2 clk cycles
                                 // must be synchronous multiple of clk cycles

  input cpol,                    // Clock polarity for SPI interface
                                 // 0 - data sampling is performed on the rising
                                 //     edge of the SCL signal
                                 // 1 - data sampling is performed on the falling
                                 //     edge of the SCL signal

  input cpha,                    // 0 - data is sampled by the rising edge
                                 //     of the synchronization signal.
                                 // 1 - data sampling is performed on the falling
                                 //     edge of the synchronization signal

  input free_running_spi_clk,    // 0 - clk_pin is active only when ncs_pin = 0
                                 // 1 - clk pin is always active

  input spi_start_cmd,           // spi write or read, shifting begins on rising edge

  output logic spi_busy,         // shifting is active

  input [MAX_DATA_WIDTH-1:0] mosi_data,               // data for shifting out from master
  input [$clog2(MAX_DATA_WIDTH):0] mosi_data_width, // variable width of data from master

  output logic [MAX_DATA_WIDTH-1:0] miso_data,        // shifted in data from slave
  input [$clog2(MAX_DATA_WIDTH):0] miso_data_width, // variable width of data from slave

  output logic clk_pin,          // spi master's clock pin
  output logic ncs_pin = 1,      // spi master's chip select (inversed)
  output logic mosi_pin = 0,     // spi master's data in
  output logic oe_pin = 0,       // spi master's output enable
                                 // in case of using bidirectional buffer for SDIO pin
  input miso_pin                 // spi master's data in
);


// first extra state for getting command and buffering
// second extra state to initialize outputs
localparam [$clog2(MAX_DATA_WIDTH)+1:0] WRITE_SEQ_START = 2;
logic [$clog2(MAX_DATA_WIDTH)+2:0] write_seq_end;
logic [$clog2(MAX_DATA_WIDTH)+2:0] read_seq_start;
logic [$clog2(MAX_DATA_WIDTH)+2:0] read_seq_end;

assign write_seq_end = WRITE_SEQ_START + {1'b0, mosi_data_width, 1'b0};
assign read_seq_start = write_seq_end;
assign read_seq_end = read_seq_start + {1'b0, miso_data_width, 1'b0};

logic spi_clk_rise;
logic spi_clk_fall;
logic cpha_1_clk_rise;
logic cpha_0_clk_fall;

// if cpha is equal to 1, then there will be an impulse for each rise edge.
// if cpha is equal to 0 then there will be an impulse for each fall edge.
assign cpha_1_clk_rise = (~cpha & spi_clk_fall || cpha & spi_clk_rise);
// if cpha is equal to 0, then there will be an impulse for each rise edge.
// if cpha is equal to 1 then there will be an impulse for each fall edge.
assign cpha_0_clk_fall = (~cpha & spi_clk_rise || cpha & spi_clk_fall);

edge_detect ed_spi_clk (
  .clk( clk ),
  .nrst( nrst ),
  .in( spi_clk ),
  .rising( spi_clk_rise ),
  .falling( spi_clk_fall ),
  .both(  )
);

logic spi_start_cmd_rise;
edge_detect ed_cmd (
  .clk( clk ),
  .nrst( nrst ),
  .in( spi_start_cmd ),
  .rising( spi_start_cmd_rise ),
  .falling(  ),
  .both(  )
);

// no need to synchronize miso pin because that is a slave`s responsibility
// to hold stable signal and avoid metastability


// shifting out is always LSB first
// optionally shifting acltual msb of data to leftmost position before reversing bit order
logic [$clog2(MAX_DATA_WIDTH):0] shift_size;
assign shift_size = MAX_DATA_WIDTH - mosi_data_width;

logic [MAX_DATA_WIDTH-1:0] mosi_data_shifted;
assign mosi_data_shifted = (mosi_data << shift_size);


// optionally reversing miso data if requested
logic [MAX_DATA_WIDTH-1:0] mosi_data_rev;
reverse_vector #(
  .WIDTH( MAX_DATA_WIDTH )
) reverse_mosi_data (
  .in( mosi_data_shifted ),
  .out( mosi_data_rev )
);


logic clk_pin_before_inversion;                  // inversion is optional, see CPOL parameter
logic [$clog2(MAX_DATA_WIDTH)+1:0] sequence_cntr = 0;

                                            // Buffering:
logic [MAX_DATA_WIDTH-1:0] mosi_data_buf = 0;   // mosi_data
logic [MAX_DATA_WIDTH-1:0] miso_data_buf = 0;   // miso_data

always_ff @(posedge clk) begin
  if( ~nrst ) begin
    clk_pin_before_inversion <= cpol;
    ncs_pin       <= 1'b1;
    mosi_pin      <= 1'b0;
    oe_pin        <= 1'b0;
    sequence_cntr <= 0;
    mosi_data_buf[MAX_DATA_WIDTH-1:0] <= 0;
    miso_data_buf[MAX_DATA_WIDTH-1:0] <= 0;
  end else begin

    // CPOL==1 means output clock inversion

    if( free_running_spi_clk ) begin
      if ( spi_clk_rise ) begin
        if (!cpol) clk_pin_before_inversion <= 1'b1;
        else clk_pin_before_inversion <= 1'b0;
      end
      if( spi_clk_fall ) begin
        if (!cpol) clk_pin_before_inversion <= 1'b0;
        else clk_pin_before_inversion <= 1'b1;
      end
    end else begin  // FREE_RUNNING_SPI_CLK = 0
      if ( !ncs_pin ) begin
        if ( spi_clk_rise ) begin
          if (!cpol) clk_pin_before_inversion <= 1'b1;
          else clk_pin_before_inversion <= 1'b0;
        end
        if( spi_clk_fall ) begin
          if (!cpol) clk_pin_before_inversion <= 1'b0;
          else clk_pin_before_inversion <= 1'b1;
        end
      end else begin // ncs_pin = 1
        clk_pin_before_inversion <= cpol;
      end
    end // if( FREE_RUNNING_SPI_CLK )

// WRITE =======================================================================

    // sequence start condition
    //*cmd_rise signals are NOT synchronous with spi_clk edges
    if( sequence_cntr==0 && spi_start_cmd_rise) begin

      // buffering mosi_data to avoid data change after shift_cmd issued
      if( MSB_FIRST ) begin
        mosi_data_buf <= mosi_data_rev;
      end else begin
        mosi_data_buf <= mosi_data;
      end
      sequence_cntr <= sequence_cntr + 1'b1;
    end

    // second step of initialization, updating outputs synchronously with spi_clk edge
    if( sequence_cntr==1 && cpha_0_clk_fall) begin
      ncs_pin <= 1'b0;
      oe_pin <= 1'b1;
      sequence_cntr <= sequence_cntr + 1'b1;
    end

    // clocking out data
    if( sequence_cntr >= WRITE_SEQ_START && sequence_cntr < write_seq_end ) begin

      // we should omit this to start sequence on specific edge
        if (cpha_0_clk_fall) begin
        sequence_cntr <= sequence_cntr + 1'b1;
      end
       if (cpha_1_clk_rise) begin
        // changing mosi_pin
        mosi_pin <= mosi_data_buf[0];
        // shifting out data is alvays LSB first
        mosi_data_buf <= {1'b0, mosi_data_buf[MAX_DATA_WIDTH-1:1]};
        sequence_cntr <= sequence_cntr + 1'b1;
      end
    end

    // waiting for valid edge to switch direction
    if( !miso_data_width ) begin
      // end of write transaction
      // resetting shifter to default state
        if( sequence_cntr == write_seq_end && cpha_1_clk_rise) begin
        ncs_pin <= 1'b1;
        mosi_pin <= 1'b0;
        oe_pin <= 1'b0;
        sequence_cntr <= 0;
      end
    end else begin
          if( sequence_cntr == write_seq_end && cpha_1_clk_rise) begin
        //ncs_pin <= 1'b0;
        mosi_pin <= 1'b0;
        oe_pin <= 1'b0;
        sequence_cntr <= sequence_cntr + 1'b1;
      end

// READ ========================================================================

      // clocking in data
      if( sequence_cntr >= read_seq_start && sequence_cntr < read_seq_end ) begin
          if(cpha_0_clk_fall) begin
          // shifting in data is alvays LSB first
          miso_data_buf <= { miso_pin, miso_data_buf[MAX_DATA_WIDTH-1:1] };
          sequence_cntr <= sequence_cntr + 1'b1;
        end
        // we should omit this to start sequence on specific edge
        //if( spi_clk_fall ) begin
          if(cpha_1_clk_rise) begin
          sequence_cntr <= sequence_cntr + 1'b1;
        end
      end

      // waiting for valid edge to end read transaction
        if(sequence_cntr == read_seq_end && cpha_1_clk_rise) begin
          ncs_pin <= 1'b1;
          mosi_pin <= 1'b0;
          oe_pin <= 1'b0;
          sequence_cntr <= 0;
      end
    end // if( !miso_MAX_DATA_WIDTH )
  end // if( nrst )
end // always


logic [MAX_DATA_WIDTH-1:0] miso_data_buf_rev;
reverse_vector #(
  .WIDTH( MAX_DATA_WIDTH )
) reverse_miso_data (
  .in( miso_data_buf ),
  .out( miso_data_buf_rev )
);


always_comb begin
  // shifting in is always LSB first
  // optionally reversing miso data if requested
  if( MSB_FIRST ) begin
    miso_data = miso_data_buf_rev;
  end else begin
    miso_data = miso_data_buf;
  end

  clk_pin = clk_pin_before_inversion;
  spi_busy = (sequence_cntr != 0);
end

endmodule