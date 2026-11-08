// SPDX-License-Identifier: GPL-3.0-or-later
// Block RAM, 16 bits as two byte lanes. Port A reads and writes (be = {high, low}); port B reads.
// Both reads are registered: q is the word at the address of the previous clock.
module lem_dpram #(
	parameter int AW = 10
) (
	input  logic          clk,

	input  logic [AW-1:0] a_addr,
	input  logic          a_we,
	input  logic [1:0]    a_be,
	input  logic [15:0]   a_d,
	output logic [15:0]   a_q,

	input  logic [AW-1:0] b_addr,
	output logic [15:0]   b_q
);
	logic [7:0] hi [0:(1<<AW)-1];
	logic [7:0] lo [0:(1<<AW)-1];   // zero at configuration, as MAME's RAM at start

	always_ff @(posedge clk) begin
		if (a_we && a_be[1]) hi[a_addr] <= a_d[15:8];
		a_q[15:8] <= hi[a_addr];
		b_q[15:8] <= hi[b_addr];
	end
	always_ff @(posedge clk) begin
		if (a_we && a_be[0]) lo[a_addr] <= a_d[7:0];
		a_q[7:0] <= lo[a_addr];
		b_q[7:0] <= lo[b_addr];
	end
endmodule
