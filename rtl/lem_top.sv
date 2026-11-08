// SPDX-License-Identifier: GPL-3.0-or-later
// lem_board wired to lem_sdram_top, with the two reset domains of Arcade-Pandora_MiSTer's
// snowbros_top: MiSTer holds RESET for the whole download, so
//   core_reset   holds the board during the download and the DDR3 copy;
//   sdram_reset  is low during the download, or sdram_download never leaves idle.
module lem_top (
	input  logic        clk,
	input  logic        reset,
	input  logic        init,
	input  logic        pause,
	input  logic        flip,

	output logic [12:0] SDRAM_A,
	output logic        SDRAM_DQML, SDRAM_DQMH,
	output logic [1:0]  SDRAM_BA,
	output logic        SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS,
	output logic        SDRAM_CLK, SDRAM_CKE,
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

	input  logic [15:0] in_inputs,
	input  logic [2:0]  in_system,
	input  logic [15:0] in_dsw,
	input  logic [7:0]  an0, an1, an2, an3,

	output logic        ce_pix,
	output logic [7:0]  r, g, b,
	output logic        hblank, vblank, hsync, vsync,

	output logic signed [15:0] audio_l,
	output logic signed [15:0] audio_r,

	output logic [15:0] overrun_spr,
	output logic [15:0] overrun_pix,
	output logic [7:0]  max_tiles,

	output logic        dbg_stb,
	output logic        dbg_we,
	output logic [23:1] dbg_addr,
	output logic [15:0] dbg_data,
	output logic        dbg_uds,
	output logic        dbg_lds
);
	wire core_reset  = reset | ioctl_download | ldr_active;
	wire sdram_reset = reset & ~ioctl_download;

	logic [14:0] rom0_addr, rom1_addr;
	logic        rom0_cs, rom0_ok, rom1_cs, rom1_ok, pix_cs, pix_ok;
	logic [63:0] rom0_q, rom1_q, pix_q;
	logic [15:0] pix_addr;
	logic        pr_req, pr_we, pr_uds, pr_lds, pr_valid;
	logic [18:1] pr_addr;
	logic [15:0] pr_din, pr_dout;
	logic        cpu_rom_req, cpu_rom_valid;
	logic [19:1] cpu_rom_addr;
	logic [15:0] cpu_rom_data;
	logic        dl_tap_we, dl_tap_we16, oki_req, oki_valid, snd_irq, snd_ack;
	logic [24:0] dl_tap_addr;
	logic [15:0] dl_tap_data;
	logic [17:0] oki_addr;
	logic [7:0]  oki_data, snd_latch;

	lem_sdram_top u_sdram (
		.clk, .reset(sdram_reset), .init,
		.SDRAM_A, .SDRAM_DQML, .SDRAM_DQMH, .SDRAM_BA, .SDRAM_nCS, .SDRAM_nWE, .SDRAM_nRAS,
		.SDRAM_nCAS, .SDRAM_CLK, .SDRAM_CKE, .SDRAM_DQ,
		.ioctl_download, .ioctl_index, .ioctl_wr, .ioctl_addr, .ioctl_dout, .ioctl_wait,
		.ldr_active, .ldr_req, .ldr_addr, .ldr_data, .ldr_we16, .ldr_busy,
		.rom0_addr, .rom0_cs, .rom0_ok, .rom0_q, .rom1_addr, .rom1_cs, .rom1_ok, .rom1_q,
		.pix_addr, .pix_cs, .pix_ok, .pix_q,
		.pr_req, .pr_we, .pr_addr, .pr_uds, .pr_lds, .pr_din, .pr_valid, .pr_dout,
		.cpu_rom_req, .cpu_rom_addr, .cpu_rom_valid, .cpu_rom_data,
		// the 6809's ROM is in block RAM (lem_sound), filled from dl_tap
		.snd_rom_req(1'b0), .snd_rom_addr(16'd0), .snd_rom_valid(), .snd_rom_data(),
		.dl_tap_we, .dl_tap_addr, .dl_tap_data, .dl_tap_we16,
		.oki_rom_req(oki_req), .oki_rom_addr(oki_addr), .oki_rom_valid(oki_valid), .oki_rom_data(oki_data)
	);

	lem_board u_board (
		.clk, .reset(core_reset), .pause, .flip,
		.in_inputs, .in_system, .in_dsw, .an0, .an1, .an2, .an3,
		.ce_pix, .vga_r(r), .vga_g(g), .vga_b(b), .vga_hs(hsync), .vga_vs(vsync),
		.vga_hblank(hblank), .vga_vblank(vblank),
		.rom0_addr, .rom0_cs, .rom0_ok, .rom0_q, .rom1_addr, .rom1_cs, .rom1_ok, .rom1_q,
		.pix_addr, .pix_cs, .pix_ok, .pix_q,
		.pr_req, .pr_we, .pr_addr, .pr_uds, .pr_lds, .pr_din, .pr_valid, .pr_dout,
		.cpu_rom_req, .cpu_rom_addr, .cpu_rom_valid, .cpu_rom_data,
		.snd_latch, .snd_irq, .snd_ack,
		.overrun_spr, .overrun_pix, .max_tiles,
		.dbg_stb, .dbg_we, .dbg_addr, .dbg_data, .dbg_uds, .dbg_lds
	);

	lem_sound u_sound (
		.clk, .reset(core_reset), .pause,
		.latch(snd_latch), .latch_irq(snd_irq), .latch_ack(snd_ack),
		.dl_we(dl_tap_we), .dl_addr(dl_tap_addr), .dl_data(dl_tap_data), .dl_we16(dl_tap_we16),
		.oki_req, .oki_addr, .oki_valid, .oki_data,
		.left(audio_l), .right(audio_r)
	);
endmodule
