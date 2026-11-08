// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// lem_top end to end, after Arcade-Pandora_MiSTer sim/top_tb: the image through the real download
// path (ioctl, sdram_download, lem_dl_xform, the arbiter, sdram.sv) into the SDRAM chip model, then
// the board out of reset.
//
// 1. The first +LIMIT bytes (hex) of each ROM region (segs.txt) are streamed as hps_io does, a
//    byte per ioctl_wr, held off by ioctl_wait, and the SDRAM compared word for word with
//    expect.hex over them: the reorder as computed in Python. The whole of expect.hex is then
//    written into the model, so the board runs on the full image.
// 2. The board is released; every 68000 access goes to debug/lemmings-top/lemmings_top.trace
//    (sim_compare_boot rtl=...) up to +MAXACC.
// 3. Frames listed in +FRAMES (comma separated, counted from reset) are written as
//    debug/lemmings-top/rtl_frame_<n>.txt, the visible 320 x 224. The run ends after +MS ms or
//    the last frame. At the last frame the pixel layer and the palette RAM are
//    written as rtl_pixel0.hex and rtl_palette.hex.
//
//     python sim/lem_top_tb/gen_fixture.py
//     sim_run lem_top_tb simulator=verilator +MAXACC=200000 +FRAMES=60
// 4. +SNDTRACE writes the 6809's chip writes and latch reads to rtl_snd.trace, in the format of
//    scripts/mame/sndtrace.lua (frames counted from reset).
// 5. +PIXTRACE writes the 68000's pixel-layer writes to rtl_pix.trace (scripts/mame/pixtrace.lua's
//    format), and every pixel-layer access is checked against the SDRAM model as it completes.
// PLUSARGS +OUT= (an existing directory) +LIMIT= +MAXACC= +MS= +FRAMES= +IN= +DSW= +SNDTRACE
//          +SNDBUS= +PIXTRACE
module tb_lem_top;
	localparam real HALF = 10.204082;   // 49 MHz
	logic clk = 0;
	always #(HALF) clk = ~clk;
	logic reset = 1;

	wire  [15:0] SDRAM_DQ;
	logic [12:0] SDRAM_A;
	logic [1:0]  SDRAM_BA;
	logic        SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS, SDRAM_DQML, SDRAM_DQMH, SDRAM_CKE, SDRAM_CLK;
	sdram_chip_model #(.ROWBITS(12)) u_chip (
		.clk(clk), .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA),
		.SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS)
	);

	logic        ioctl_download = 0, ioctl_wr = 0, ioctl_wait;
	logic [24:0] ioctl_addr = 0;
	logic [7:0]  ioctl_dout = 0;
	logic [15:0] in_inputs = 16'hffff, in_dsw = 16'hffff;
	logic        ce_pix, hb, vb, hs, vs;
	logic [7:0]  r, g, b;
	logic [15:0] overrun_spr, overrun_pix;
	logic signed [15:0] audio_l, audio_r;
	logic [7:0]  max_tiles;
	logic        dbg_stb, dbg_we, dbg_uds, dbg_lds;
	logic [23:1] dbg_addr;
	logic [15:0] dbg_data;

	lem_top dut (
		.clk, .reset, .init(1'b0), .pause(1'b0), .flip(1'b0),
		.SDRAM_A, .SDRAM_DQML, .SDRAM_DQMH, .SDRAM_BA, .SDRAM_nCS, .SDRAM_nWE, .SDRAM_nRAS, .SDRAM_nCAS,
		.SDRAM_CLK, .SDRAM_CKE, .SDRAM_DQ,
		.ioctl_download, .ioctl_index(16'd0), .ioctl_wr, .ioctl_addr, .ioctl_dout, .ioctl_wait,
		.ldr_active(1'b0), .ldr_req(1'b0), .ldr_addr(25'd0), .ldr_data(16'd0), .ldr_we16(1'b0), .ldr_busy(),
		// the X axes are PORT_REVERSE: MAME reads FF at rest
		.in_inputs, .in_system(3'b111), .in_dsw, .an0(8'hff), .an1(8'd0), .an2(8'hff), .an3(8'd0),
		.ce_pix, .r, .g, .b, .hblank(hb), .vblank(vb), .hsync(hs), .vsync(vs),
		.audio_l, .audio_r,
		.overrun_spr, .overrun_pix, .max_tiles,
		.dbg_stb, .dbg_we, .dbg_addr, .dbg_data, .dbg_uds, .dbg_lds
	);

	string dir = "debug/lemmings-top";   // fixtures
	string out = "debug/lemmings-top";   // results; +OUT= keeps runs side by side apart

	// ---- trace ----
	int    fd = 0, nacc = 0, maxacc = 200000;
	logic  tracing = 0;
	function automatic [15:0] lanes(input logic uds, lds);
		lanes = {uds ? 8'hFF : 8'h00, lds ? 8'hFF : 8'h00};
	endfunction
	always @(posedge clk) if (tracing && dbg_stb && nacc < maxacc) begin
		nacc++;
		$fwrite(fd, "%0d\t%s\t%06X\t%04X\t%04X\n", nacc, dbg_we ? "w" : "r",
		        {dbg_addr, 1'b0}, lanes(dbg_uds, dbg_lds), dbg_data & lanes(dbg_uds, dbg_lds));
		if (nacc == maxacc) begin $fclose(fd); fd = 0; $display("%t: %0d accesses traced", $time, nacc); end
	end

	// ---- every 68000 pixel-layer access against the SDRAM model when it completes ----
	int pix_bad = 0, pix_n = 0, pxfd = 0;   // +PIXTRACE: the writes, as scripts/mame/pixtrace.lua logs them
	always @(posedge clk) if (tracing && dut.u_board.xst == 3'd2 && dut.u_board.ext_ready) begin
		automatic int w = 'h100000 + int'(dut.u_board.pr_addr);
		automatic logic [15:0] m = u_chip.mem[w];
		automatic logic [15:0] lanes = {dut.u_board.pr_uds ? 8'hff : 8'h00, dut.u_board.pr_lds ? 8'hff : 8'h00};
		automatic logic bad = dut.u_board.pr_we ? ((m ^ dut.u_board.pr_din) & lanes) != 0
		                                         : ((m ^ dut.u_board.ext_rdata) & lanes) != 0;
		pix_n++;
		if (pxfd != 0 && dut.u_board.pr_we)
			$fwrite(pxfd, "%0d\t%05X\t%04X\t%04X\n", frames, dut.u_board.pr_addr, lanes, dut.u_board.pr_din & lanes);
		if (bad) begin
			pix_bad++;
			if (pix_bad <= 10)
				$display("%t: PIX %s word %05x lanes %04x: cpu %04x, sdram %04x (access %0d, frame %0d)", $time,
				         dut.u_board.pr_we ? "write" : "read", dut.u_board.pr_addr, lanes,
				         dut.u_board.pr_we ? dut.u_board.pr_din : dut.u_board.ext_rdata, m, pix_n, frames);
		end
	end

	// ---- the sound CPU's device writes and latch reads, as scripts/mame/sndtrace.lua logs them ----
	int sfd = 0;
	always @(posedge clk) if (tracing && sfd != 0) begin
		if (dut.u_sound.cpu_wr && dut.u_sound.A >= 16'h0800 && dut.u_sound.A < 16'h2000)
			$fwrite(sfd, "%0d\tw\t%04X\t%02X\n", frames, dut.u_sound.A, dut.u_sound.DOut);
		if (dut.u_sound.latch_ack)
			$fwrite(sfd, "%0d\tr\t1800\t%02X\n", frames, dut.u_sound.latch);
	end

	// ---- +SNDBUS=n: the 6809's first n bus cycles, address, direction and data, to rtl_sndbus.txt ----
	int bfd = 0, bn = 0, bmax = 0;
	always @(posedge clk) if (tracing && bfd != 0 && dut.u_sound.cen_E) begin
		$fwrite(bfd, "%04X %s %02X\n", dut.u_sound.A, dut.u_sound.RnW ? "r" : "w",
		        dut.u_sound.RnW ? dut.u_sound.D : dut.u_sound.DOut);
		if (++bn == bmax) begin $fclose(bfd); bfd = 0; end
	end

	// ---- the pixel layer in SDRAM, a 16-bit word a line in the 68000's order (MAME's pixel0.bin) ----
	task automatic dump_pix();
		int pf = $fopen({out, "/rtl_pixel0.hex"}, "w");
		for (int w = 'h100000; w < 'h140000; w++) $fdisplay(pf, "%04x", u_chip.mem[w]);
		$fclose(pf);
		// palette RAM in MAME's word order (palette.bin): even word, odd word per entry
		pf = $fopen({out, "/rtl_palette.hex"}, "w");
		for (int i = 0; i < 1024; i++)
			$fdisplay(pf, "%02x%02x\n%02x%02x", dut.u_board.u_pal_e.hi[i], dut.u_board.u_pal_e.lo[i],
			          dut.u_board.u_pal_o.hi[i], dut.u_board.u_pal_o.lo[i]);
		$fclose(pf);
	endtask

	// ---- frames ----
	int    frames = 0, ffd = 0, npix = 0, last_frame = 0;
	int    want [0:63];
	int    nwant = 0;
	logic  vs_prev = 0;
	always @(posedge clk) if (tracing && ce_pix) begin
		vs_prev <= vs;
		if (vs && !vs_prev) begin
			if (ffd != 0) begin
				$fclose(ffd); ffd = 0;
				$display("%t: frame %0d written, %0d pixels; overruns sprite %0d pixel %0d, max tiles %0d; pixel-layer accesses %0d, wrong %0d",
				         $time, frames, npix, overrun_spr, overrun_pix, max_tiles, pix_n, pix_bad);
				if (frames >= last_frame) begin
					if (fd != 0) $fclose(fd);
					dump_pix();
					$finish;
				end
			end
			frames = frames + 1;
			for (int i = 0; i < nwant; i++)
				if (want[i] == frames) begin
					ffd = $fopen($sformatf("%s/rtl_frame_%0d.txt", out, frames), "w");
					npix = 0;
				end
		end
		if (ffd != 0 && !hb && !vb) begin
			$fdisplay(ffd, "%02x%02x%02x", r, g, b);
			npix++;
		end
	end

	logic [7:0]  image [0:2621439];
	logic [15:0] expect_w [0:1310719];

	initial begin
		int f, nseg, bad, ms, lim, waited;
		int seg_a [8], seg_l [8];
		string frl;
		ms = 2000; lim = 'h400;
		void'($value$plusargs("OUT=%s", out));
		void'($value$plusargs("LIMIT=%h", lim));
		void'($value$plusargs("MAXACC=%d", maxacc));
		void'($value$plusargs("MS=%d", ms));
		void'($value$plusargs("IN=%h", in_inputs));
		void'($value$plusargs("DSW=%h", in_dsw));
		if ($value$plusargs("FRAMES=%s", frl)) begin
			int v = 0;
			for (int i = 0; i <= frl.len(); i++)
				if (i == frl.len() || frl[i] == ",") begin
					want[nwant++] = v;
					if (v > last_frame) last_frame = v;
					v = 0;
				end else v = v * 10 + (frl[i] - "0");
		end
		$readmemh({dir, "/image.hex"}, image);
		$readmemh({dir, "/expect.hex"}, expect_w);
		f = $fopen({dir, "/segs.txt"}, "r");
		nseg = 0;
		while ($fscanf(f, "%h %h", seg_a[nseg], seg_l[nseg]) == 2) nseg++;
		$fclose(f);

		// ---- 1: download ----
		repeat (20) @(posedge clk);
		ioctl_download = 1;
		for (int s = 0; s < nseg; s++) begin
			// the sound ROM goes whole: lem_sound's block RAM copy is filled only by the download
			if (lim != 0 && seg_l[s] > lim && seg_a[s] != 'h180000) seg_l[s] = lim;
			for (int i = 0; i < seg_l[s]; i++) begin
				@(posedge clk);
				waited = 0;
				while (ioctl_wait) begin
					@(posedge clk);
					if (++waited == 100000) $fatal(1, "ioctl_wait held 100000 clk at byte 0x%06x", seg_a[s] + i);
				end
				ioctl_addr = 25'(seg_a[s] + i); ioctl_dout = image[seg_a[s] + i]; ioctl_wr = 1;
				@(posedge clk) ioctl_wr = 0;
			end
		end
		repeat (50) @(posedge clk);
		ioctl_download = 0;
		repeat (200) @(posedge clk);

		// ---- the SDRAM against the reorder computed in Python ----
		// a sprite region's first LIMIT bytes scatter across it, so compare where they went, a byte
		// at a time (the other bytes of their words come from planes not yet sent)
		bad = 0;
		for (int s = 0; s < nseg; s++)
			for (int i = 0; i < seg_l[s]; i++) begin
				automatic int a = seg_a[s] + i;
				automatic int d = a;
				// a sprite region arrives as four 64 KB planes p, MAME byte 3 - p of each dword
				if (a >= 'h100000 && a < 'h180000)
					d = (a & ~'h3ffff) | (((a >> 5) & 'h7ff) << 7) | ((a & 'hf) << 3) | (((a >> 4) & 1) << 2)
					  | ((a >> 16) & 3);
				if (8'(u_chip.peek_word_addr(24'(d >> 1)) >> (8 * (d & 1))) !== 8'(expect_w[d >> 1] >> (8 * (d & 1)))) begin
					bad++;
					if (bad <= 5) $display("FAIL SDRAM byte 0x%06x (from 0x%06x): word %04x, expected %04x", d, a,
					                       u_chip.peek_word_addr(24'(d >> 1)), expect_w[d >> 1]);
				end
			end
		$display("%t: download done; %0d SDRAM bytes differ from expect.hex", $time, bad);
		for (int w = 0; w < 1310720; w++) u_chip.mem[w] = expect_w[w];

		// ---- 2: boot ----
		if ($test$plusargs("SNDTRACE")) sfd = $fopen({out, "/rtl_snd.trace"}, "w");
		if ($test$plusargs("PIXTRACE")) pxfd = $fopen({out, "/rtl_pix.trace"}, "w");
		if ($value$plusargs("SNDBUS=%d", bmax)) bfd = $fopen({out, "/rtl_sndbus.txt"}, "w");
		fd = $fopen({out, "/lemmings_top.trace"}, "w");
		if (fd == 0) $fatal(1, "cannot open %s/lemmings_top.trace", out);
		$fwrite(fd, "# RTL bus accesses from reset (sim/lem_top_tb), seq rw addr mask data\n");
		tracing = 1;
		@(negedge clk) reset = 0;
		repeat (ms) repeat (49000) @(posedge clk);
		$display("%t: %0d ms, %0d accesses, %0d frames; overruns sprite %0d pixel %0d", $time, ms, nacc, frames,
		         overrun_spr, overrun_pix);
		if (fd != 0) $fclose(fd);
		$finish;
	end
endmodule
