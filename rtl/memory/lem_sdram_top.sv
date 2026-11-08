// SPDX-License-Identifier: GPL-3.0-or-later
// The SDRAM backend: the burst-4 controller's three ports (rtl/memory/sdram), fixed priority,
// port 0 highest. Structure from Arcade-Pandora_MiSTer rtl/memory/snowbros_sdram_top.sv.
//   Port 0  video: both sprite engines and the pixel-layer fetch, round robin (sdram_arbiter6)
//   Port 1  the 68000's pixel-layer RAM, read and write
//   Port 2  sdram_arbiter6: c0 the M6295's samples (ahead of the round robin), c1 the 6809's
//           program, c2 the 68000's program; and the download's write port
// Every download write passes lem_dl_xform (the sprite-row reorder).
//
// A granule's byte k is the byte at its address + k; word i is q[16*i +: 16]. The pixel layer
// holds 68000 words as they are written, so its word i is the 68000 word at granule + 2i.
module lem_sdram_top (
	input  logic clk,
	input  logic reset,
	input  logic init,

	output logic [12:0] SDRAM_A,
	output logic        SDRAM_DQML,
	output logic        SDRAM_DQMH,
	output logic [1:0]  SDRAM_BA,
	output logic        SDRAM_nCS,
	output logic        SDRAM_nWE,
	output logic        SDRAM_nRAS,
	output logic        SDRAM_nCAS,
	output logic        SDRAM_CLK,
	output logic        SDRAM_CKE,
	inout  wire  [15:0] SDRAM_DQ,

	input  logic        ioctl_download,
	input  logic [15:0] ioctl_index,
	input  logic        ioctl_wr,
	input  logic [24:0] ioctl_addr,
	input  logic [7:0]  ioctl_dout,
	output logic        ioctl_wait,

	input  logic        ldr_active,
	input  logic        ldr_req,
	input  logic [24:0] ldr_addr,
	input  logic [15:0] ldr_data,
	input  logic        ldr_we16,
	output logic        ldr_busy,

	// video, lem_video's ports: cs held, ok while the data is for the address presented
	input  logic [14:0] rom0_addr,        // chip 0, sprites2: {code, row}
	input  logic        rom0_cs,
	output logic        rom0_ok,
	output logic [63:0] rom0_q,
	input  logic [14:0] rom1_addr,        // chip 1, sprites1
	input  logic        rom1_cs,
	output logic        rom1_ok,
	output logic [63:0] rom1_q,
	input  logic [15:0] pix_addr,         // 8-byte groups of the pixel layer
	input  logic        pix_cs,
	output logic        pix_ok,
	output logic [63:0] pix_q,

	// 68000 pixel layer, 0x300000-0x37ffff: req pulsed, valid pulsed on read data or write done;
	// dout holds from valid until the next read
	input  logic        pr_req,
	input  logic        pr_we,
	input  logic [18:1] pr_addr,
	input  logic        pr_uds,
	input  logic        pr_lds,
	input  logic [15:0] pr_din,
	output logic        pr_valid,
	output logic [15:0] pr_dout,

	input  logic        cpu_rom_req,
	input  logic [19:1] cpu_rom_addr,
	output logic        cpu_rom_valid,
	output logic [15:0] cpu_rom_data,

	input  logic        snd_rom_req,
	input  logic [15:0] snd_rom_addr,
	output logic        snd_rom_valid,
	output logic [7:0]  snd_rom_data,

	// every download write as it goes to SDRAM, one pulse each (the sound ROM's block RAM copy)
	output logic        dl_tap_we,
	output logic [24:0] dl_tap_addr,
	output logic [15:0] dl_tap_data,
	output logic        dl_tap_we16,

	input  logic        oki_rom_req,
	input  logic [17:0] oki_rom_addr,
	output logic        oki_rom_valid,
	output logic [7:0]  oki_rom_data
);
	// Byte offsets into SDRAM; the .mra stream is laid out the same (scripts/build_mra.py).
	localparam logic [24:0] MAIN_BASE  = 25'h0000000;   // 1 MB
	localparam logic [24:0] SPR1_BASE  = 25'h0100000;   // sprites1, 256 KB
	localparam logic [24:0] SPR2_BASE  = 25'h0140000;   // sprites2, 256 KB
	localparam logic [24:0] SOUND_BASE = 25'h0180000;   // 64 KB
	localparam logic [24:0] OKI_BASE   = 25'h0190000;   // 256 KB
	localparam logic [24:0] PIX_BASE   = 25'h0200000;   // 512 KB, zeroed by the download

	// each dword's byte 0 is erased in MAME's region and not stored
	localparam logic [63:0] SPR_MASK   = 64'h00ffffff_00ffffff;

	wire inval = ioctl_download | ldr_active;

	logic [24:1] p0_addr, p1_addr, p2_addr;
	logic        p0_wrl, p0_wrh, p1_wrl, p1_wrh, p2_wrl, p2_wrh;
	logic [15:0] p0_din, p1_din, p2_din;
	logic [63:0] p0_dout, p1_dout, p2_dout;
	logic        p0_req, p1_req, p2_req;
	logic        p0_ack, p1_ack, p2_ack;

	sdram mem_ctrl (
		.SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
		.SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE),
		.SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS),
		.SDRAM_CLK(SDRAM_CLK), .SDRAM_CKE(SDRAM_CKE), .SDRAM_DQ(SDRAM_DQ),
		.init(init), .clk(clk),
		.addr0({1'b0, p0_addr}), .wrl0(p0_wrl), .wrh0(p0_wrh), .din0(p0_din), .dout0(p0_dout), .req0(p0_req), .ack0(p0_ack),
		.addr1({1'b0, p1_addr}), .wrl1(p1_wrl), .wrh1(p1_wrh), .din1(p1_din), .dout1(p1_dout), .req1(p1_req), .ack1(p1_ack),
		.addr2({1'b0, p2_addr}), .wrl2(p2_wrl), .wrh2(p2_wrh), .din2(p2_din), .dout2(p2_dout), .req2(p2_req), .ack2(p2_ack)
	);

	// ---------------------------------------------------------------- Port 0: video
	logic        v_phy_req, v_phy_we, v_phy_we16, v_phy_busy, v_phy_valid;
	logic [24:0] v_phy_addr;
	logic [15:0] v_phy_wdata;
	logic [63:0] v_phy_rdata;
	sdram_phy phy0 (
		.clk(clk), .reset(reset),
		.port_addr(p0_addr), .port_wrl(p0_wrl), .port_wrh(p0_wrh),
		.port_din(p0_din), .port_dout(p0_dout), .port_req(p0_req), .port_ack(p0_ack),
		.req(v_phy_req), .we(v_phy_we), .we16(v_phy_we16), .addr(v_phy_addr), .wdata(v_phy_wdata),
		.busy(v_phy_busy), .valid(v_phy_valid), .rdata(v_phy_rdata)
	);

	logic        s0_req, s1_req, px_req, s0_valid, s1_valid, px_valid;
	logic [24:0] s0_addr, s1_addr, px_addr;
	logic [63:0] s0_data, s1_data, px_data, vu_data;
	logic        vu_valid, v_dl_busy;

	sdram_arbiter6 u_video_arb (
		.clk(clk), .reset(reset),
		.phy_req(v_phy_req), .phy_we(v_phy_we), .phy_we16(v_phy_we16), .phy_addr(v_phy_addr), .phy_wdata(v_phy_wdata),
		.phy_busy(v_phy_busy), .phy_valid(v_phy_valid), .phy_rdata(v_phy_rdata),
		.c0_req(1'b0),   .c0_addr('0),      .c0_valid(vu_valid), .c0_data(vu_data),
		.c1_req(s0_req), .c1_addr(s0_addr), .c1_valid(s0_valid), .c1_data(s0_data),
		.c2_req(s1_req), .c2_addr(s1_addr), .c2_valid(s1_valid), .c2_data(s1_data),
		.c3_req(px_req), .c3_addr(px_addr), .c3_valid(px_valid), .c3_data(px_data),
		.c4_req(1'b0),   .c4_addr('0),      .c4_valid(),         .c4_data(),
		.dl_req(1'b0), .dl_addr('0), .dl_data('0), .dl_we16(1'b0), .dl_busy(v_dl_busy)
	);

	logic [63:0] rom0_raw, rom1_raw;
	lem_vport u_vp0 (.clk, .reset, .cs(rom0_cs), .addr(SPR2_BASE + {7'd0, rom0_addr, 3'd0}),
		.ok(rom0_ok), .q(rom0_raw), .g_req(s0_req), .g_addr(s0_addr), .g_valid(s0_valid), .g_data(s0_data));
	lem_vport u_vp1 (.clk, .reset, .cs(rom1_cs), .addr(SPR1_BASE + {7'd0, rom1_addr, 3'd0}),
		.ok(rom1_ok), .q(rom1_raw), .g_req(s1_req), .g_addr(s1_addr), .g_valid(s1_valid), .g_data(s1_data));
	lem_vport u_vpx (.clk, .reset, .cs(pix_cs), .addr(PIX_BASE + {6'd0, pix_addr, 3'd0}),
		.ok(pix_ok), .q(pix_q), .g_req(px_req), .g_addr(px_addr), .g_valid(px_valid), .g_data(px_data));
	assign rom0_q = rom0_raw & SPR_MASK;
	assign rom1_q = rom1_raw & SPR_MASK;

	// ---------------------------------------------------------------- Port 1: 68000 pixel layer
	logic        pr_busy, pr_rvalid, pr_busy_d, pr_wr;
	logic [1:0]  pr_word;
	logic [63:0] pr_rdata;
	wire         pr_we16 = pr_uds && pr_lds;
	sdram_phy phy1 (
		.clk(clk), .reset(reset),
		.port_addr(p1_addr), .port_wrl(p1_wrl), .port_wrh(p1_wrh),
		.port_din(p1_din), .port_dout(p1_dout), .port_req(p1_req), .port_ack(p1_ack),
		.req(pr_req), .we(pr_we), .we16(pr_we16),
		// a 68000 word sits in one lane as written: the upper byte is the high lane. A read
		// fetches the aligned granule and pr_word picks the lane: from an unaligned column the
		// chip's burst wraps within the granule, so lane k would not be word k.
		.addr(PIX_BASE + (pr_we ? {6'd0, pr_addr, pr_uds && !pr_lds} : {6'd0, pr_addr[18:3], 3'd0})),
		.wdata(pr_we16 ? pr_din : {8'd0, pr_uds ? pr_din[15:8] : pr_din[7:0]}),
		.busy(pr_busy), .valid(pr_rvalid), .rdata(pr_rdata)
	);
	always_ff @(posedge clk) begin
		pr_busy_d <= pr_busy;
		if (pr_req) begin pr_wr <= pr_we; pr_word <= pr_addr[2:1]; end
	end
	// rdata is the controller's port register, held until this port's next read
	always_comb case (pr_word)
		2'd0: pr_dout = pr_rdata[15:0];
		2'd1: pr_dout = pr_rdata[31:16];
		2'd2: pr_dout = pr_rdata[47:32];
		2'd3: pr_dout = pr_rdata[63:48];
	endcase
	assign pr_valid = pr_wr ? (pr_busy_d && !pr_busy) : pr_rvalid;

	// ---------------------------------------------------------------- Port 2: ROMs and download
	logic        p2phy_req, p2phy_we, p2phy_busy, p2phy_valid, p2phy_we16;
	logic [24:0] p2phy_addr;
	logic [15:0] p2phy_wdata;
	logic [63:0] p2phy_rdata;
	sdram_phy phy2 (
		.clk(clk), .reset(reset),
		.port_addr(p2_addr), .port_wrl(p2_wrl), .port_wrh(p2_wrh),
		.port_din(p2_din), .port_dout(p2_dout), .port_req(p2_req), .port_ack(p2_ack),
		.req(p2phy_req), .we(p2phy_we), .we16(p2phy_we16), .addr(p2phy_addr), .wdata(p2phy_wdata),
		.busy(p2phy_busy), .valid(p2phy_valid), .rdata(p2phy_rdata)
	);

	logic        c0_req, c1_req, c2_req;
	logic [24:0] c0_addr, c1_addr, c2_addr;
	logic        c0_valid, c1_valid, c2_valid, c3_valid, c4_valid;
	logic [63:0] c0_data, c1_data, c2_data, c3_data, c4_data;
	logic        arb_req, arb_we16, arb_busy;
	logic [24:0] arb_addr;
	logic [15:0] arb_data;

	sdram_arbiter6 u_arbiter (
		.clk(clk), .reset(reset),
		.phy_req(p2phy_req), .phy_we(p2phy_we), .phy_we16(p2phy_we16), .phy_addr(p2phy_addr), .phy_wdata(p2phy_wdata),
		.phy_busy(p2phy_busy), .phy_valid(p2phy_valid), .phy_rdata(p2phy_rdata),
		.c0_req(c0_req), .c0_addr(c0_addr), .c0_valid(c0_valid), .c0_data(c0_data),
		.c1_req(c1_req), .c1_addr(c1_addr), .c1_valid(c1_valid), .c1_data(c1_data),
		.c2_req(c2_req), .c2_addr(c2_addr), .c2_valid(c2_valid), .c2_data(c2_data),
		.c3_req(1'b0), .c3_addr('0), .c3_valid(c3_valid), .c3_data(c3_data),
		.c4_req(1'b0), .c4_addr('0), .c4_valid(c4_valid), .c4_data(c4_data),
		.dl_req(arb_req), .dl_addr(arb_addr), .dl_data(arb_data),
		.dl_we16(arb_we16), .dl_busy(arb_busy)
	);

	// the write port: the DDR3 copy while it runs, else the byte stream; then the reorder
	logic        dl_req, dl_busy, dl_we16, x_busy;
	logic [24:0] dl_addr;
	logic [15:0] dl_data;
	wire         s_req  = ldr_active ? ldr_req  : dl_req;
	wire  [24:0] s_addr = ldr_active ? ldr_addr : dl_addr;
	wire  [15:0] s_data = ldr_active ? ldr_data : dl_data;
	wire         s_we16 = ldr_active ? ldr_we16 : dl_we16;
	assign dl_busy  = ldr_active ? 1'b0 : x_busy;
	assign ldr_busy = ldr_active ? x_busy : 1'b0;

	lem_dl_xform #(.SPR_BASE(SPR1_BASE), .SPR_SIZE(25'h0080000)) u_xform (
		.clk(clk), .reset(reset),
		.s_req(s_req), .s_addr(s_addr), .s_data(s_data), .s_we16(s_we16), .s_busy(x_busy),
		.d_req(arb_req), .d_addr(arb_addr), .d_data(arb_data), .d_we16(arb_we16), .d_busy(arb_busy)
	);

	// lem_dl_xform raises d_req once per write and holds addr and data until busy
	logic arb_req_q;
	always_ff @(posedge clk) arb_req_q <= reset ? 1'b0 : arb_req;
	assign dl_tap_we   = arb_req && !arb_req_q;
	assign dl_tap_addr = arb_addr;
	assign dl_tap_data = arb_data;
	assign dl_tap_we16 = arb_we16;

	sdram_download u_download (
		.clk(clk), .reset(reset),
		.ioctl_download(ioctl_download), .ioctl_index(ioctl_index),
		.ioctl_wr(ioctl_wr), .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout),
		.ioctl_wait(ioctl_wait),
		.dl_req(dl_req), .dl_addr(dl_addr), .dl_data(dl_data), .dl_we16(dl_we16), .dl_busy(dl_busy)
	);

	// read clients
	logic [25:0] oki_g_addr;
	sample_cache #(.ENTRIES(8)) u_oki_cache (
		.clk(clk), .reset(reset), .inval(inval),
		.req(oki_rom_req), .addr({1'b0, OKI_BASE + {7'd0, oki_rom_addr}}),
		.valid(oki_rom_valid), .data(oki_rom_data),
		.g_req(c0_req), .g_addr(oki_g_addr), .g_valid(c0_valid), .g_data(c0_data)
	);
	assign c0_addr = oki_g_addr[24:0];

	sdram_narrow_bridge #(.WORD_BYTES(1)) u_snd_bridge (
		.clk(clk), .reset(reset), .inval(inval),
		.req(snd_rom_req), .addr(SOUND_BASE + {9'd0, snd_rom_addr}),
		.valid(snd_rom_valid), .data(snd_rom_data),
		.g_req(c1_req), .g_addr(c1_addr), .g_valid(c1_valid), .g_data(c1_data)
	);

	// the 68000's program is big-endian (ROM_LOAD16_BYTE); the bridge packs words little-endian
	logic [15:0] cpu_le;
	assign cpu_rom_data = {cpu_le[7:0], cpu_le[15:8]};
	sdram_narrow_bridge #(.WORD_BYTES(2)) u_cpu_bridge (
		.clk(clk), .reset(reset), .inval(inval),
		.req(cpu_rom_req), .addr(MAIN_BASE + {5'd0, cpu_rom_addr, 1'b0}),
		.valid(cpu_rom_valid), .data(cpu_le),
		.g_req(c2_req), .g_addr(c2_addr), .g_valid(c2_valid), .g_data(c2_data)
	);
endmodule

// A held-cs video client onto the arbiter's hold-until-valid contract. ok is high while the
// client presents the address the held data came from; a new address starts a new fetch.
module lem_vport (
	input  logic        clk,
	input  logic        reset,
	input  logic        cs,
	input  logic [24:0] addr,
	output logic        ok,
	output logic [63:0] q,
	output logic        g_req,
	output logic [24:0] g_addr,
	input  logic        g_valid,
	input  logic [63:0] g_data
);
	logic pend, have;
	assign g_req = pend;
	assign ok    = cs && have && addr == g_addr;
	always_ff @(posedge clk or posedge reset) begin
		if (reset) begin
			pend <= 1'b0; have <= 1'b0;
		end else if (pend) begin
			if (g_valid) begin pend <= 1'b0; have <= 1'b1; q <= g_data; end
		end else if (cs && !(have && addr == g_addr)) begin
			pend <= 1'b1; have <= 1'b0; g_addr <= addr;
		end
	end
endmodule
