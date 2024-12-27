`timescale 1ns / 1ps

// the algorithm of division into a column of binary numbers is implemented
// quotient.reminder = divident/divider
// calculation time = 2*N*(1/clk)

module divider #(parameter N = 32)
(
input   logic              clk,
input   logic              start,    // start of division
input   logic [ N-1 :  0 ] divident, // integer
input   logic [ N-1 :  0 ] divider,  // integer
output  logic [ N-1 :  0 ] quotient, // integer part of a number
output  logic [ N-1 :  0 ] reminder, // remainder of the division
output  logic              ready     // module is ready
);

localparam M = 2*N;

logic signed [ N-1 :  0 ] r_quotient    = '0;
logic signed [ M-1 :  0 ] divident_copy = '0;
logic signed [ M-1 :  0 ] divider_copy  = '0;
logic signed [ M-1 :  0 ] diff;
logic        [   5 :  0 ] cnt           = '0;

assign quotient = r_quotient;
assign reminder = divident_copy[N-1:0];
assign ready    = cnt == 0;
assign diff     = divident_copy - divider_copy;

always@(posedge clk)
if(ready && start)
begin
  cnt           <= N;
  r_quotient    <= '0;
  divident_copy <= divident;
  divider_copy  <= divider << (N - 1);
end else begin
  cnt           <= cnt - 1'b1;
  divider_copy  <= divider_copy >> 1;
  if(!diff[63])
  begin
    divident_copy <= diff;
    r_quotient    <= {quotient[30:0], 1'b1};
  end else begin
    r_quotient    <= {quotient[30:0], 1'b0};
  end
end

// test 6 fix
endmodule



