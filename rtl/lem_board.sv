// SPDX-License-Identifier: GPL-3.0-or-later
// The Lemmings main board (lemmings.cpp main_map): the 68000, its decode and block RAMs, the
// sprite-list copies, the DECO 146, and the video. ROMs and the pixel layer are in SDRAM
// (lem_sdram_top); the sound board is outside.
//
// Sprite lists (lemmings.cpp:146-152, bufsprite.h): a write to 0x1c0000 / 0x1e0000 copies
// spriteram1 / spriteram2 to its buffer, and vblank start copies each buffer to the list drawn.
// Here each list has two banks: vblank start points the drawn list at the buffer's bank, and a
// trigger copies the live RAM into a bank that is not drawn, over 1024 clocks. A CPU access to
// that live RAM waits for the copy, so the copy is the RAM as the trigger found it.
module lem_board (
	input  logic        clk,          // 49 MHz
	input  logic        reset,
	input  logic        pause,
	input  logic        flip,

	input  logic [15:0] in_inputs,    // DECO 146 port A, active low
	input  logic [2:0]  in_system,    // port B bits 2:0: service, coin 1, coin 2, active low
	input  logic [15:0] in_dsw,       // port C
	input  logic [7:0]  an0, an1, an2, an3,   // trackball counters, lemmings.cpp:271

	output logic        ce_pix,
	output logic [7:0]  vga_r,
	output logic [7:0]  vga_g,
	output logic [7:0]  vga_b,
	output logic        vga_hs,
	output logic        vga_vs,
	output logic        vga_hblank,
	output logic        vga_vblank,

	output logic [14:0] rom0_addr,
	output logic        rom0_cs,
	input  logic        rom0_ok,
	input  logic [63:0] rom0_q,
	output logic [14:0] rom1_addr,
	output logic        rom1_cs,
	input  logic        rom1_ok,
	input  logic [63:0] rom1_q,
	output logic [15:0] pix_addr,
	output logic        pix_cs,
	input  logic        pix_ok,
	input  logic [63:0] pix_q,

	output logic        pr_req,
	output logic        pr_we,
	output logic [18:1] pr_addr,
	output logic        pr_uds,
	output logic        pr_lds,
	output logic [15:0] pr_din,
	input  logic        pr_valid,
	input  logic [15:0] pr_dout,

	output logic        cpu_rom_req,
	output logic [19:1] cpu_rom_addr,
	input  logic        cpu_rom_valid,
	input  logic [15:0] cpu_rom_data,

	output logic [7:0]  snd_latch,
	output logic        snd_irq,
	input  logic        snd_ack,

	output logic [15:0] overrun_spr,
	output logic [15:0] overrun_pix,
	output logic [7:0]  max_tiles,

	// simulation trace: one strobe per completed CPU access
	output logic        dbg_stb,
	output logic        dbg_we,
	output logic [23:1] dbg_addr,
	output logic [15:0] dbg_data,
	output logic        dbg_uds,
	output logic        dbg_lds
);
	// ---------------------------------------------------------------- CPU
	logic [23:1] ca;
	logic        cwe, is_ext, int_stb, ext_req, ext_ready;
	logic [15:0] cwd, int_rdata, ext_rdata;
	logic [1:0]  cbe;
	logic        vblank_rise;

	board_cpu #(.PHASE_NUM(7), .PHASE_DEN(2)) u_cpu (
		.clk, .reset, .cpu_run(!pause), .fast(1'b0),
		.irq_set({1'b0, vblank_rise, 5'b0}),           // level 6, lemmings.cpp:454
		.addr(ca), .we(cwe), .wdata(cwd), .be(cbe),
		.is_ext, .int_stb, .int_rdata, .ext_req, .ext_ready, .ext_rdata,
		.ss_req(1'b0), .ss_parked(), .ss_release(1'b0), .ss_idx(5'd0), .ss_we(1'b0), .ss_wd(32'd0),
		.ss_rd(), .ss_pend(), .ss_pend_we(1'b0), .ss_pend_wd(7'd0),
		.dbg_stb, .dbg_we, .dbg_addr, .dbg_data, .dbg_uds, .dbg_lds
	);

	// ---------------------------------------------------------------- decode, lemmings.cpp:308-326
	wire [23:0] a = {ca, 1'b0};
	wire r_rom  = a[23:20] == 4'h0;
	wire r_wram = a[23:16] == 8'h10;
	wire r_spr1 = a[23:11] == 13'h0240;            // 120000-1207ff
	wire r_spr2 = a[23:11] == 13'h0280;            // 140000-1407ff
	wire r_pal  = a[23:12] == 12'h160;
	wire r_ctl  = a[23:4]  == 20'h17000;
	wire r_tb   = a[23:4]  == 20'h19000;
	wire r_deco = a[23:14] == 10'h068;             // 1a0000-1a3fff
	wire r_trg1 = a[23:1]  == 23'h0e0000;          // 1c0000
	wire r_trg2 = a[23:1]  == 23'h0f0000;          // 1e0000
	wire r_vram = a[23:14] == 10'h080 && a[13:12] != 2'b11;   // 200000-202fff
	wire r_pix0 = a[23:19] == 5'h06;               // 300000-37ffff
	wire r_pix1 = a[23:17] == 7'h1c;               // 380000-39ffff

	logic [1:0] copy_busy;                         // [0] spriteram1, [1] spriteram2
	wire spr_wait = (r_spr1 && copy_busy[0]) || (r_spr2 && copy_busy[1]);
	assign is_ext = (r_rom && !cwe) || r_pix0 || (r_deco && !cwe) || spr_wait;

	// An internal-RAM access that waited for a copy runs as late_stb, one clock, then returns the
	// RAM's word the clock after.
	typedef enum logic [2:0] {X_IDLE, X_ROM, X_PIX, X_DECO, X_SPR, X_SPRQ} xst_t;
	xst_t xst;
	logic late_stb;
	logic deco_rd, deco_valid;
	logic [15:0] deco_q;
	logic [15:0] spr_late_q;
	assign late_stb = xst == X_SPR && !spr_wait;

	always_ff @(posedge clk) begin
		if (reset) xst <= X_IDLE;
		else case (xst)
			X_IDLE: if (ext_req)
				xst <= r_rom ? X_ROM : r_pix0 ? X_PIX : r_deco ? X_DECO : X_SPR;
			X_SPR:  if (!spr_wait) xst <= X_SPRQ;
			default: if (ext_ready) xst <= X_IDLE;
		endcase
	end
	wire x_start = xst == X_IDLE && ext_req;
	assign cpu_rom_req  = x_start && r_rom;
	assign cpu_rom_addr = ca[19:1];
	assign pr_req  = x_start && r_pix0;
	assign pr_we   = cwe;
	assign pr_addr = ca[18:1];
	assign {pr_uds, pr_lds} = cbe;
	assign pr_din  = cwd;
	assign deco_rd = x_start && r_deco;

	always_comb case (xst)
		X_ROM:   begin ext_ready = cpu_rom_valid; ext_rdata = cpu_rom_data; end
		X_PIX:   begin ext_ready = pr_valid;      ext_rdata = pr_dout;      end
		X_DECO:  begin ext_ready = deco_valid;    ext_rdata = deco_q;       end
		X_SPRQ:  begin ext_ready = 1'b1;          ext_rdata = spr_late_q;   end
		default: begin ext_ready = 1'b0;          ext_rdata = 16'h0000;     end
	endcase

	wire stb = int_stb || late_stb;
	wire wr  = stb && cwe;

	// ---------------------------------------------------------------- block RAMs
	logic [15:0] wram_q, spr1_q, spr2_q, pal_e_q, pal_o_q, vram_q_cpu, pix1_q;

	lem_dpram #(.AW(15)) u_wram (.clk,
		.a_addr(ca[15:1]), .a_we(wr && r_wram), .a_be(cbe), .a_d(cwd), .a_q(wram_q),
		.b_addr(ca[15:1]), .b_q());

	// palette, xBGR_888 (lemmings.cpp:469): entry n is words 2n (x, B) and 2n+1 (G, R)
	logic [9:0]  pal_addr;
	logic [15:0] pal_e, pal_o;
	lem_dpram #(.AW(10)) u_pal_e (.clk,
		.a_addr(ca[11:2]), .a_we(wr && r_pal && !ca[1]), .a_be(cbe), .a_d(cwd), .a_q(pal_e_q),
		.b_addr(pal_addr), .b_q(pal_e));
	lem_dpram #(.AW(10)) u_pal_o (.clk,
		.a_addr(ca[11:2]), .a_we(wr && r_pal && ca[1]), .a_be(cbe), .a_d(cwd), .a_q(pal_o_q),
		.b_addr(pal_addr), .b_q(pal_o));

	// tilemap; the video reads the first 2048 words
	logic [10:0] vram_addr;
	logic [15:0] vram_q;
	lem_dpram #(.AW(13)) u_vram (.clk,
		.a_addr(ca[13:1]), .a_we(wr && r_vram), .a_be(cbe), .a_d(cwd), .a_q(vram_q_cpu),
		.b_addr({2'b00, vram_addr}), .b_q(vram_q));

	// tile pixels, pixel_1
	logic [15:0] tpix_addr, tpix_q;
	lem_dpram #(.AW(16)) u_pix1 (.clk,
		.a_addr(ca[16:1]), .a_we(wr && r_pix1), .a_be(cbe), .a_d(cwd), .a_q(pix1_q),
		.b_addr(tpix_addr), .b_q(tpix_q));

	// control words, lemmings.cpp:260-266: word 4 is not stored
	logic [15:0] ctl [0:7];
	logic [15:0] ctl_q;
	always_ff @(posedge clk) begin
		if (reset) for (int i = 0; i < 8; i++) ctl[i] <= 16'h0000;
		else if (wr && r_ctl && ca[3:1] != 3'd4) begin
			if (cbe[1]) ctl[ca[3:1]][15:8] <= cwd[15:8];
			if (cbe[0]) ctl[ca[3:1]][7:0]  <= cwd[7:0];
		end
		ctl_q <= ctl[ca[3:1]];
	end

	// trackball, lemmings.cpp:268-273
	logic [7:0] tb_q;
	always_ff @(posedge clk)
		case ({ca[2], ca[3], ca[1]})               // {offset & 2, offset & 4, offset & 1}
			3'b000: tb_q <= an0;
			3'b001: tb_q <= an1;
			3'b010: tb_q <= an2;
			3'b011: tb_q <= an3;
			default: tb_q <= 8'h00;
		endcase

	// ---------------------------------------------------------------- sprite lists
	logic [9:0]  list0_addr, list1_addr;
	logic [15:0] list0_q, list1_q;
	logic        trig1, trig2;
	assign trig1 = wr && r_trg1;
	assign trig2 = wr && r_trg2;

	// list 1: spriteram1, drawn by chip 1; list 2: spriteram2, drawn by chip 0 (lemmings.cpp:234-235)
	lem_spr_list u_list1 (.clk, .reset,
		.cpu_addr(ca[10:1]), .cpu_we(wr && r_spr1), .cpu_be(cbe), .cpu_d(cwd), .cpu_q(spr1_q),
		.trigger(trig1), .vblank(vblank_rise), .busy(copy_busy[0]),
		.draw_addr(list1_addr), .draw_q(list1_q));
	lem_spr_list u_list2 (.clk, .reset,
		.cpu_addr(ca[10:1]), .cpu_we(wr && r_spr2), .cpu_be(cbe), .cpu_d(cwd), .cpu_q(spr2_q),
		.trigger(trig2), .vblank(vblank_rise), .busy(copy_busy[1]),
		.draw_addr(list0_addr), .draw_q(list0_q));

	// ---------------------------------------------------------------- DECO 146
	logic vblank_s;
	lem_deco146 u_deco (.clk, .reset,
		.rd(deco_rd), .wr(wr && r_deco), .addr(ca[10:1]), .din(cwd), .be(cbe),
		.dout(deco_q), .valid(deco_valid),
		.port_a(in_inputs),
		.port_b({12'h000, vblank_s, in_system}),   // bit 3 is the screen's vblank, active high
		.port_c(in_dsw),
		.snd_latch, .snd_irq, .snd_ack);

	// ---------------------------------------------------------------- CPU read mux
	typedef enum logic [2:0] {Q_ZERO, Q_WRAM, Q_SPR1, Q_SPR2, Q_PAL, Q_VRAM, Q_PIX1, Q_CTL} q_t;
	q_t   qsel;
	logic q_odd, q_tb;
	always_ff @(posedge clk)
		if (stb) begin
			q_odd <= ca[1];
			q_tb  <= r_tb;
			qsel  <= r_wram ? Q_WRAM : r_spr1 ? Q_SPR1 : r_spr2 ? Q_SPR2 : r_pal ? Q_PAL :
			         r_vram ? Q_VRAM : r_pix1 ? Q_PIX1 : r_ctl ? Q_CTL : Q_ZERO;
		end
	always_comb begin
		case (qsel)
			Q_WRAM:  int_rdata = wram_q;
			Q_SPR1:  int_rdata = spr1_q;
			Q_SPR2:  int_rdata = spr2_q;
			Q_PAL:   int_rdata = q_odd ? pal_o_q : pal_e_q;
			Q_VRAM:  int_rdata = vram_q_cpu;
			Q_PIX1:  int_rdata = pix1_q;
			Q_CTL:   int_rdata = ctl_q;
			default: int_rdata = q_tb ? {8'h00, tb_q} : 16'h0000;
		endcase
	end
	assign spr_late_q = int_rdata;

	// ---------------------------------------------------------------- video
	logic frame_odd;
	always_ff @(posedge clk)
		if (reset) frame_odd <= 1'b0;
		else if (vblank_rise) frame_odd <= ~frame_odd;
	// The status bit is MAME's vblank: 529 us from vblank start (lemmings.cpp:465), 25921 clk,
	// not the display's 40 blank lines.
	logic [14:0] vbl_cnt;
	always_ff @(posedge clk)
		if (reset)              vbl_cnt <= '0;
		else if (vblank_rise)   vbl_cnt <= 15'd25921;
		else if (vbl_cnt != '0) vbl_cnt <= vbl_cnt - 15'd1;
	assign vblank_s = vbl_cnt != '0;

	lem_video u_video (.clk, .reset, .flip, .frame_odd,
		.scroll1(ctl[0]), .scroll0(ctl[2]), .window(ctl[6][1]),
		.list0_addr, .list0_q, .list1_addr, .list1_q,
		.rom0_addr, .rom0_cs, .rom0_ok, .rom0_q, .rom1_addr, .rom1_cs, .rom1_ok, .rom1_q,
		.pix_addr, .pix_cs, .pix_ok, .pix_q, .vram_addr, .vram_q, .tpix_addr, .tpix_q,
		.pal_addr, .pal_q({pal_o[7:0], pal_o[15:8], pal_e[7:0]}),
		.ce_pix, .vga_r, .vga_g, .vga_b, .vga_hs, .vga_vs, .vga_hblank, .vga_vblank,
		.vblank_rise, .vcount_o(), .overrun_spr, .overrun_pix, .max_tiles);
endmodule

// One sprite list: the live RAM the CPU writes, and two banks, one drawn, one the buffer.
module lem_spr_list (
	input  logic        clk,
	input  logic        reset,
	input  logic [9:0]  cpu_addr,
	input  logic        cpu_we,
	input  logic [1:0]  cpu_be,
	input  logic [15:0] cpu_d,
	output logic [15:0] cpu_q,
	input  logic        trigger,
	input  logic        vblank,
	output logic        busy,
	input  logic [9:0]  draw_addr,
	output logic [15:0] draw_q
);
	logic        act, wv, bp, dp, tgt, dp_pend;
	logic [9:0]  idx, wa;
	logic [15:0] live_q;
	assign busy = act || wv;

	lem_dpram #(.AW(10)) u_live (.clk,
		.a_addr(cpu_addr), .a_we(cpu_we), .a_be(cpu_be), .a_d(cpu_d), .a_q(cpu_q),
		.b_addr(idx), .b_q(live_q));
	lem_dpram #(.AW(11)) u_banks (.clk,
		.a_addr({tgt, wa}), .a_we(wv), .a_be(2'b11), .a_d(live_q), .a_q(),
		.b_addr({dp, draw_addr}), .b_q(draw_q));

	always_ff @(posedge clk) begin
		if (reset) begin
			act <= 1'b0; wv <= 1'b0; bp <= 1'b0; dp <= 1'b0; tgt <= 1'b0; dp_pend <= 1'b0; idx <= '0;
		end else begin
			wv <= act;
			wa <= idx;
			if (trigger) begin
				// a bank that is not drawn; a copy already running keeps its bank
				if (!busy) tgt <= bp != dp ? bp : ~dp;
				act <= 1'b1;
				idx <= '0;
			end else if (act) begin
				idx <= idx + 10'd1;
				if (&idx) act <= 1'b0;
			end
			// MAME copies the buffer at vblank start; a copy still running finished before it there
			if (vblank) begin
				if (busy) dp_pend <= 1'b1;
				else      dp <= bp;
			end
			if (wv && &wa && !act) begin
				bp <= tgt;
				if (dp_pend) begin dp <= tgt; dp_pend <= 1'b0; end
			end
		end
	end
endmodule
