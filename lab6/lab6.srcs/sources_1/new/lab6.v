`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Dept. of CS, National Chiao Tung University
// Engineer: Chun-Jen Tsai
// 
// Create Date: 2018/10/10 16:10:38
// Design Name: UART I/O example for Arty
// Module Name: lab6
// Project Name: 
// Target Devices: Xilinx FPGA @ 100MHz
// Tool Versions: 
// Description: 
// 
// The parameters for the UART controller are 9600 baudrate, 8-N-1-N
//
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module lab6(
  input  clk,
  input  reset_n,
  input  [3:0] usr_btn,
  output [3:0] usr_led,
  input  uart_rx,
  output uart_tx
);

localparam [2:0] S_MAIN_INIT = 0, S_MAIN_PROMPT = 1,
                 S_MAIN_READ_NUM = 2, S_MAIN_REPLY = 5,
                 S_SECOND_PROMPT = 3, S_SECOND_READ_NUM = 4;
localparam [1:0] S_UART_IDLE = 0, S_UART_WAIT = 1,
                 S_UART_SEND = 2, S_UART_INCR = 3;
localparam INIT_DELAY = 100_000; // 1 msec @ 100 MHz
localparam PROMPT_STR = 0;  // starting index of the prompt message
localparam PROMPT_LEN = 35; //27; // length of the prompt message
localparam PROMPT2_STR= 35;
localparam PROMPT2_LEN= 36;
localparam REPLY_STR  = 71; //27; // starting index of the hello message
localparam REPLY_LEN  = 37; //38; // length of the hello message
localparam MEM_SIZE   = PROMPT_LEN+PROMPT2_LEN+REPLY_LEN;

// declare system variables
wire enter_pressed;
wire print_enable, print_done;
reg [$clog2(MEM_SIZE):0] send_counter;
reg [1:0] P, P_next;
reg [1:0] Q, Q_next;
reg [$clog2(INIT_DELAY):0] init_counter;
reg [7:0] data[0:MEM_SIZE-1];
// reg  [0:PROMPT_LEN*8-1] msg1 = { "\015\012Enter a decimal number: ", 8'h00 };
reg  [0:PROMPT_LEN*8-1] msg1 = { "\015\012Enter the first decimal number: ", 8'h00 };
// reg  [0:REPLY_LEN*8-1]  msg2 = { "\015\012The number you typed was: 0x0000.\015\012", 8'h00 };
reg  [0:PROMPT2_LEN*8-1]  msg2 = { "\015\012Enter the second decimal number: ", 8'h00 };
reg  [0:REPLY_LEN*8-1] msg3 = {"\015\012The integer quotient is: 0x0000.\015\012",8'h00};
reg  [15:0] num_reg;  // The key-in number register
reg  [2:0]  key_cnt;  // The key strokes counter
reg  [15:0] num1 = 16'b0;
reg  [15:0] num2 = 16'b0;
reg  [15:0] Quotient = 16'b0;
reg  [15:0] Rest = 16'b0;
reg result_ready;

// declare UART signals
wire transmit;
wire received;
wire [7:0] rx_byte;
reg  [7:0] rx_temp;  // if recevied is true, rx_temp latches rx_byte for ONLY ONE CLOCK CYCLE!
wire [7:0] tx_byte;
wire [7:0] echo_key; // keystrokes to be echoed to the terminal
wire is_num_key;
wire is_receiving;
wire is_transmitting;
wire recv_error;

/* The UART device takes a 100MHz clock to handle I/O at 9600 baudrate */
uart uart(
  .clk(clk),
  .rst(~reset_n),
  .rx(uart_rx),
  .tx(uart_tx),
  .transmit(transmit),
  .tx_byte(tx_byte),
  .received(received),
  .rx_byte(rx_byte),
  .is_receiving(is_receiving),
  .is_transmitting(is_transmitting),
  .recv_error(recv_error)
);

// Initializes some strings.
// System Verilog has an easier way to initialize an array,
// but we are using Verilog 2001 :(
//
integer idx;
integer didx = 15;


always @(posedge clk) begin
  if (~reset_n) begin
    for (idx = 0; idx < PROMPT_LEN; idx = idx + 1) data[idx] = msg1[idx*8 +: 8];
    for (idx = 0; idx < PROMPT2_LEN; idx = idx + 1) data[idx+PROMPT_LEN] = msg2[idx*8 +: 8];
    for (idx = 0; idx < REPLY_LEN; idx = idx + 1) data[idx+PROMPT_LEN+PROMPT2_LEN] = msg3[idx*8 +: 8];
  end
  else if (P == S_MAIN_REPLY && result_ready) begin
    data[REPLY_STR+30] <= ((num_reg[15:12] > 9)? "7" : "0") + num_reg[15:12];
    data[REPLY_STR+31] <= ((num_reg[11: 8] > 9)? "7" : "0") + num_reg[11: 8];
    data[REPLY_STR+32] <= ((num_reg[ 7: 4] > 9)? "7" : "0") + num_reg[ 7: 4];
    data[REPLY_STR+33] <= ((num_reg[ 3: 0] > 9)? "7" : "0") + num_reg[ 3: 0];
  end
end

// Combinational I/O logics of the top-level system
assign usr_led = usr_btn;
assign enter_pressed = (rx_temp == 8'h0D); // don't use rx_byte here!

// ------------------------------------------------------------------------
// Main FSM that reads the UART input and triggers
// the output of the string "Hello, World!".
always @(posedge clk) begin
  if (~reset_n) P <= S_MAIN_INIT;
  else P <= P_next;
end

always @(*) begin // FSM next-state logic
  case (P)
    S_MAIN_INIT: // Wait for initial delay of the circuit.
	   if (init_counter < INIT_DELAY) P_next = S_MAIN_INIT;
		else P_next = S_MAIN_PROMPT;
    S_MAIN_PROMPT: // Print the prompt message.
      if (print_done) P_next = S_MAIN_READ_NUM;
      else P_next = S_MAIN_PROMPT;
    S_MAIN_READ_NUM: // wait for <Enter> key.
      if (enter_pressed) P_next = S_SECOND_PROMPT; //S_MAIN_REPLY;
      else P_next = S_MAIN_READ_NUM;
    S_SECOND_PROMPT:
      if (print_done) P_next = S_SECOND_READ_NUM;
      else P_next = S_SECOND_PROMPT;
    S_SECOND_READ_NUM:
      if (enter_pressed) P_next = S_MAIN_REPLY;
      else P_next = S_SECOND_READ_NUM;
    S_MAIN_REPLY: // Print the hello message.
      if (print_done) P_next = S_MAIN_INIT;
      else P_next = S_MAIN_REPLY;
  endcase
end

// FSM output logics: print string control signals.
assign print_enable = (P != S_MAIN_PROMPT && P_next == S_MAIN_PROMPT) ||
                  (P == S_MAIN_READ_NUM && P_next == S_MAIN_REPLY);
assign print_done = (tx_byte == 8'h0);

// Initialization counter.
always @(posedge clk) begin
  if (P == S_MAIN_INIT) init_counter <= init_counter + 1;
  else init_counter <= 0;
end
// End of the FSM of the print string controller
// ------------------------------------------------------------------------

// ------------------------------------------------------------------------
// FSM of the controller that sends a string to the UART.
always @(posedge clk) begin
  if (~reset_n) Q <= S_UART_IDLE;
  else Q <= Q_next;
end

always @(*) begin // FSM next-state logic
  case (Q)
    S_UART_IDLE: // wait for the print_string flag
      if (print_enable) Q_next = S_UART_WAIT;
      else Q_next = S_UART_IDLE;
    S_UART_WAIT: // wait for the transmission of current data byte begins
      if (is_transmitting == 1) Q_next = S_UART_SEND;
      else Q_next = S_UART_WAIT;
    S_UART_SEND: // wait for the transmission of current data byte finishes
      if (is_transmitting == 0) Q_next = S_UART_INCR; // transmit next character
      else Q_next = S_UART_SEND;
    S_UART_INCR:
      if (tx_byte == 8'h0) Q_next = S_UART_IDLE; // string transmission ends
      else Q_next = S_UART_WAIT;
  endcase
end

// FSM output logics: UART transmission control signals
assign transmit = (Q_next == S_UART_WAIT ||
                  (P == S_MAIN_READ_NUM && received) || (P == S_SECOND_READ_NUM && received)
                   print_enable);
assign is_num_key = (rx_byte > 8'h2F) && (rx_byte < 8'h3A) && (key_cnt < 5);
assign echo_key = (is_num_key || rx_byte == 8'h0D)? rx_byte : 0;
assign tx_byte  = ((P == S_MAIN_READ_NUM) && received)? echo_key : data[send_counter];

// UART send_counter control circuit
always @(posedge clk) begin
  case (P_next)
    S_MAIN_INIT: send_counter <= PROMPT_STR;
    S_MAIN_READ_NUM: send_counter <= PROMPT2_STR; //REPLY_STR;
    S_SECOND_READ_NUM: send_counter <= REPLY_STR;
    default: send_counter <= send_counter + (Q_next == S_UART_INCR);
  endcase
end
// End of the FSM of the print string controller
// ------------------------------------------------------------------------

// ------------------------------------------------------------------------
// UART input logic
// Decimal number input will be saved in num1 or num2.
always @(posedge clk) begin
  if (~reset_n || (P == S_MAIN_INIT || P == S_MAIN_PROMPT || P == S_SECOND_PROMPT)) key_cnt <= 0;
  else if (received && is_num_key) key_cnt <= key_cnt + 1;
end

always @(posedge clk)begin
  if (~reset_n) begin
    // num_reg <= 0;
    num1 <= 0;
    num2 <= 0;
    didx <= 15;
    Quotient <= 0;
    Rest <= 0;
    result_ready = 0;
  end
  else if (P == S_MAIN_INIT || P == S_MAIN_PROMPT || P == S_SECOND_PROMPT) begin
    // num_reg <= 0;
    num1 <= 0;
    num2 <= 0;
    didx <= 15;
    Quotient <= 0;
    Rest <= 0;
    result_ready = 0;
  end
  else if (received && is_num_key && P == S_MAIN_READ_NUM) begin
    // num_reg <= (num_reg * 10) + (rx_byte - 48);
    num1 <= num1*10 + (rx_byte-48);
  end
  else if (received && is_num_key && P == S_SECOND_READ_NUM) begin
    num2 <= num2*10 + (rx_byte-48);
  end
  else if (P == S_MAIN_REPLY && !result_ready) begin
    Rest = Rest<<1;
    R[0] = num1[didx];
    Rest = (Rest>=num2) ? Rest-num2 : Rest;
    Quotient[didx] = (Rest>=num2) ? 1 : Quotient[didx];
    didx = didx - 1;
    if (didx<0) begin
      result_ready = 1;
    end 
  end
end

always @(posedge clk) begin
  if (result_ready) num_reg <= Quotient;
  else num_reg <= 0;
end

// The following logic stores the UART input in a temporary buffer.
// The input character will stay in the buffer for one clock cycle.
always @(posedge clk) begin
  rx_temp <= (received)? rx_byte : 8'h0;
end
// End of the UART input logic
// ------------------------------------------------------------------------

endmodule