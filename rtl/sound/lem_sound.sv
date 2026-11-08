// SPDX-License-Identifier: GPL-3.0-or-later
// The sound board: MC6809E, 2 KB RAM, YM2151 (jt51), M6295 (jt6295). lemmings.cpp:317-323, 454-496.
//
//   0000-07ff RAM   0800-0801 YM2151   1000 M6295   1800 the 146's sound latch (read)   8000-ffff ROM
//   (writes to 1800 are dropped, as MAME's nopw)
//
// IRQ is the YM2151's, FIRQ the latch's (the 146 raises it on a 68000 write and drops it when the
// 6809 reads 1800). The ROM is the upper 32 KB of lemmings.15, held in block RAM: mc6809i has no
// wait input. It is written from the download's SDRAM write stream (dl_*, after lem_dl_xform),
// the same bytes the SDRAM gets, so the ioctl and the DDR3 load both fill it.
//
// Clocks from fractional enables of 49 MHz (docs/ROADMAP.md, Clocks): E and Q alternate at twice
// 1.3425 MHz; YM2151 3.58 MHz with cen_p1 every other; M6295 1023924 Hz, pin 7 high (ss = 1).
// Pause stops all three: the CPU and the chips hold, so the output holds its last sample.
//
// Mix, lemmings.cpp:491-496: YM2151 left and right at 0.45 each to their side, M6295 at 0.50 to
// both. jt6295 is 14 bits; x16 brings it to the YM's full scale (Pandora's semicom_sound), so the
// M6295 is x8. 0.45 is 1/4 + 1/8 + 1/16 + 1/128 + 1/256 (0.4492), by shifts.
module lem_sound (
	input  logic        clk,
	input  logic        reset,
	input  logic        pause,

	input  logic [7:0]  latch,
	input  logic        latch_irq,
	output logic        latch_ack,      // one clk: the 6809 read 1800

	// the download's SDRAM writes (lem_sdram_top dl_tap_*): one pulse a write
	input  logic        dl_we,
	input  logic [24:0] dl_addr,
	input  logic [15:0] dl_data,
	input  logic        dl_we16,

	// M6295 samples, req held until valid (sample_cache)
	output logic        oki_req,
	output logic [17:0] oki_addr,
	input  logic        oki_valid,
	input  logic [7:0]  oki_data,

	output logic signed [15:0] left,
	output logic signed [15:0] right
);
	localparam logic [24:0] ROM_DL = 25'h0188000;   // SOUND_BASE + 0x8000

	// ---------------------------------------------------------------- clock enables
	logic [13:0] acc_cpu;
	logic        eq;                                // 0: next is Q, 1: next is E
	logic        tick_cpu;
	always_ff @(posedge clk) begin
		if (reset) begin acc_cpu <= '0; eq <= 1'b0; tick_cpu <= 1'b0; end
		else begin
			// 2 x 1.3425 MHz = 537/9800 of 49 MHz
			tick_cpu <= 1'b0;
			if (!pause) begin
				if (acc_cpu + 14'd537 >= 14'd9800) begin
					acc_cpu <= acc_cpu + 14'd537 - 14'd9800; tick_cpu <= 1'b1; eq <= ~eq;
				end else acc_cpu <= acc_cpu + 14'd537;
			end
		end
	end
	wire cen_Q = tick_cpu && eq;                    // eq toggled with the tick: Q, then E
	wire cen_E = tick_cpu && !eq;

	logic [11:0] acc_ym;
	logic        cen_ym, cen_ym_p1, ym_half;
	always_ff @(posedge clk) begin
		if (reset) begin acc_ym <= '0; cen_ym <= 1'b0; cen_ym_p1 <= 1'b0; ym_half <= 1'b0; end
		else begin
			cen_ym <= 1'b0; cen_ym_p1 <= 1'b0;
			if (!pause) begin
				// 3.58 MHz = 179/2450 of 49 MHz
				if (acc_ym + 12'd179 >= 12'd2450) begin
					acc_ym <= acc_ym + 12'd179 - 12'd2450;
					cen_ym <= 1'b1; cen_ym_p1 <= ym_half; ym_half <= ~ym_half;
				end else acc_ym <= acc_ym + 12'd179;
			end
		end
	end

	logic [23:0] acc_oki;
	logic        cen_oki;
	always_ff @(posedge clk) begin
		if (reset) begin acc_oki <= '0; cen_oki <= 1'b0; end
		else begin
			cen_oki <= 1'b0;
			if (!pause) begin
				// 1023924 Hz = 255981/12250000 of 49 MHz
				if (acc_oki + 24'd255981 >= 24'd12250000) begin
					acc_oki <= acc_oki + 24'd255981 - 24'd12250000; cen_oki <= 1'b1;
				end else acc_oki <= acc_oki + 24'd255981;
			end
		end
	end

	// ---------------------------------------------------------------- CPU
	logic [15:0] A;
	logic [7:0]  DOut, D;
	logic        RnW, ym_irq_n;

	mc6809i #(.ILLEGAL_INSTRUCTIONS("GHOST")) u_cpu (
		.D(D), .DOut(DOut), .ADDR(A), .RnW(RnW),
		.clk(clk), .cen_E(cen_E), .cen_Q(cen_Q),
		.BS(), .BA(),
		.nIRQ(ym_irq_n), .nFIRQ(~latch_irq), .nNMI(1'b1),
		.AVMA(), .BUSY(), .LIC(),
		.nHALT(1'b1), .nRESET(~reset), .nDMABREQ(1'b1),
		.OP(), .RegData()
	);

	// decoded as MAME maps them, no mirrors: the program reads 1800-1fff in a loop, and a mirrored
	// latch would take each of those reads as the FIRQ acknowledge
	wire is_ram = A[15:11] == 5'b00000;
	wire is_ym  = A[15:1]  == 15'h0400;
	wire is_oki = A == 16'h1000;
	wire is_lat = A == 16'h1800;
	wire is_rom = A[15];
	wire cpu_wr = cen_E && !RnW;

	// RAM and ROM: registered reads, many clocks before E samples D
	logic [7:0] ram [0:2047];
	logic [7:0] ram_q;
	always_ff @(posedge clk) begin
		if (cpu_wr && is_ram) ram[A[10:0]] <= DOut;
		ram_q <= ram[A[10:0]];
	end

	// the ROM as even and odd bytes, as the SDRAM lanes carry them
	logic [7:0] rom_e [0:16383];
	logic [7:0] rom_o [0:16383];
	logic [7:0] rom_e_q, rom_o_q;
	wire        dl_rom = dl_we && dl_addr[24:15] == ROM_DL[24:15];
	wire [13:0] dl_w   = dl_addr[14:1];
	always_ff @(posedge clk) begin
		if (dl_rom && (dl_we16 || !dl_addr[0])) rom_e[dl_w] <= dl_data[7:0];
		rom_e_q <= rom_e[A[14:1]];
	end
	always_ff @(posedge clk) begin
		if (dl_rom && dl_we16)                  rom_o[dl_w] <= dl_data[15:8];
		else if (dl_rom && dl_addr[0])          rom_o[dl_w] <= dl_data[7:0];
		rom_o_q <= rom_o[A[14:1]];
	end
	logic a0_q;
	always_ff @(posedge clk) a0_q <= A[0];

	// ---------------------------------------------------------------- YM2151
	// The write is held from Q to E, the 6809's address-and-data-valid window, so jt51 sees it
	// across at least one of its own enables and sets busy as the chip does.
	logic        ym_wr;
	logic [7:0]  ym_dout;
	logic signed [15:0] ym_l, ym_r;
	always_ff @(posedge clk) begin
		if (reset || cen_E) ym_wr <= 1'b0;
		else if (cen_Q)     ym_wr <= !RnW && is_ym;
	end
	jt51 u_ym (
		.rst(reset), .clk(clk), .cen(cen_ym), .cen_p1(cen_ym_p1),
		.cs_n(~ym_wr), .wr_n(~ym_wr), .a0(A[0]), .din(DOut), .dout(ym_dout),
		.ct1(), .ct2(), .irq_n(ym_irq_n), .sample(),
		.left(ym_l), .right(ym_r), .xleft(), .xright()
	);

	// ---------------------------------------------------------------- M6295
	logic [17:0] oki_rom_addr;
	logic [7:0]  oki_rom_data, oki_dout;
	logic        oki_rom_ok;
	logic signed [13:0] oki_snd;
	jt6295 #(.INTERPOL(0)) u_oki (
		.rst(reset), .clk(clk), .cen(cen_oki), .ss(1'b1),
		.wrn(~(cpu_wr && is_oki)), .din(DOut), .dout(oki_dout),
		.rom_addr(oki_rom_addr), .rom_data(oki_rom_data), .rom_ok(oki_rom_ok),
		.sound(oki_snd), .sample()
	);
	logic [19:0] br_addr;
	oki_rom_bridge u_bridge (
		.clk(clk), .reset(reset),
		.rom_addr(oki_rom_addr), .rom_data(oki_rom_data), .rom_ok(oki_rom_ok), .bank(2'd0),
		.req(oki_req), .addr(br_addr), .valid(oki_valid), .data(oki_data)
	);
	assign oki_addr = br_addr[17:0];

	// ---------------------------------------------------------------- read mux, latch ack
	always_comb begin
		if      (is_rom) D = a0_q ? rom_o_q : rom_e_q;
		else if (is_ram) D = ram_q;
		else if (is_ym)  D = ym_dout;
		else if (is_oki) D = oki_dout;
		else if (is_lat) D = latch;
		else             D = 8'h00;    // MAME's unmapped read
	end
	assign latch_ack = cen_E && RnW && is_lat;

	// ---------------------------------------------------------------- mix
	function automatic logic signed [20:0] x045(input logic signed [15:0] v);
		logic signed [20:0] w;
		w = 21'(v);
		x045 = (w >>> 2) + (w >>> 3) + (w >>> 4) + (w >>> 7) + (w >>> 8);
	endfunction
	function automatic logic signed [15:0] sat(input logic signed [20:0] v);
		sat = v > 21'sd32767 ? 16'sd32767 : v < -21'sd32768 ? -16'sd32768 : v[15:0];
	endfunction
	logic signed [20:0] oki8;
	always_ff @(posedge clk) begin
		oki8  <= 21'(oki_snd) <<< 3;
		left  <= sat(x045(ym_l) + oki8);
		right <= sat(x045(ym_r) + oki8);
	end
endmodule
