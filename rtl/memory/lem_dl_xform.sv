// SPDX-License-Identifier: GPL-3.0-or-later
// The download's sprite-ROM reorder, on every write into SDRAM (the byte stream and the DDR3 copy
// both pass here, ahead of the arbiter's write port). Adapted from Arcade-Pandora_MiSTer
// rtl/memory/dl_xform.sv (d0ff7e7): same handshake, Lemmings' transform.
//
// sprites1 and sprites2 are ROM_LOAD32_BYTE in MAME with byte 0 of each dword erased. MiSTer Main
// cannot build that with an <interleave>: its output length follows only the part on byte 0, so
// a three-part interleave sends nothing and later regions overwrite it. The .mra therefore sends
// each region as four 64 KB planes, p = 0..3 holding MAME byte 3 - p (p = 3 is a zero fill), and
// the interleave happens here: MAME offset m = {i, ~p} for plane byte i.
// One sprite row is the dword at m = {t, 0, r, b} and the one at {t, 1, r, b} (t tile, r row,
// b byte; lemmings.cpp gfx layout, 16x16 at 128 bytes a tile). Both go in one 8-byte granule,
// left half high, each dword's byte 0 highest: dst = {t, r, H, ~b}, which from the plane address
// {p, i} is {i[15:5], i[3:0], i[4], p}. lem_video's sprite fetch is then one burst per row.
//
// A two-byte write whose bytes stay adjacent and in order stays one write; otherwise it is split
// into two single-byte writes (a single-byte write carries its byte in the low lane, the lane
// chosen by address bit 0, sdram_phy). Inside the sprite regions every pair is reversed, so every
// pair splits.
//
// Both sides use the arbiter's write contract: req held until busy rises, then busy falls when the
// write is done; addr and data are held throughout.

module lem_dl_xform #(
	parameter logic [24:0] SPR_BASE = 25'h0100000,     // sprites1, then sprites2: 512 KB
	parameter logic [24:0] SPR_SIZE = 25'h0080000
) (
	input  logic        clk,
	input  logic        reset,

	input  logic        s_req,
	input  logic [24:0] s_addr,
	input  logic [15:0] s_data,
	input  logic        s_we16,
	output logic        s_busy,

	output logic        d_req,
	output logic [24:0] d_addr,
	output logic [15:0] d_data,
	output logic        d_we16,
	input  logic        d_busy
);
	function automatic logic [32:0] xbyte(input logic [24:0] a, input logic [7:0] b);
		logic [24:0] o;
		o = a;
		if (a >= SPR_BASE && a < SPR_BASE + SPR_SIZE)
			o[17:0] = {a[15:5], a[3:0], a[4], a[17:16]};
		xbyte = {o, b};
	endfunction

	logic [32:0] x1;
	logic        two;
	logic [1:0]  st;           // 0 idle, 1 first write, 2 second write, 3 wait for the source to drop
	logic        phase;        // 0: req out, 1: waiting for busy to fall

	wire [32:0] c0 = xbyte(s_addr, s_data[7:0]);
	wire [32:0] c1 = xbyte(s_addr + 25'd1, s_data[15:8]);
	wire        pair_ok = !c0[8] && c0[32:9] == c1[32:9] && c1[8];

	always_ff @(posedge clk) begin
		if (reset) begin
			st <= 2'd0; phase <= 1'b0; s_busy <= 1'b0; d_req <= 1'b0;
		end else case (st)
			2'd0: if (s_req) begin
				x1 <= c1; s_busy <= 1'b1;
				two    <= s_we16 && !pair_ok;
				st     <= 2'd1; phase <= 1'b0;
				d_req  <= 1'b1;
				d_addr <= c0[32:8];
				d_data <= (s_we16 && pair_ok) ? {c1[7:0], c0[7:0]} : {8'd0, c0[7:0]};
				d_we16 <= s_we16 && pair_ok;
			end
			2'd1, 2'd2: begin
				if (!phase) begin
					if (d_busy) begin d_req <= 1'b0; phase <= 1'b1; end
				end else if (!d_busy) begin
					phase <= 1'b0;
					if (st == 2'd1 && two) begin
						st <= 2'd2; d_req <= 1'b1;
						d_addr <= x1[32:8]; d_data <= {8'd0, x1[7:0]}; d_we16 <= 1'b0;
					end else begin
						st <= 2'd3; s_busy <= 1'b0;
					end
				end
			end
			2'd3: if (!s_req) st <= 2'd0;
		endcase
	end
endmodule
