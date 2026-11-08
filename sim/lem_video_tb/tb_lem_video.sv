// SPDX-License-Identifier: GPL-3.0-or-later
//
// lem_video against a mame_capture: preload RAMs and lists from gen_inputs.py's hex, run two frames,
// write the second frame's visible pixels. compare.py checks them against MAME's reference.png.
//
//     python sim/lem_video_tb/gen_inputs.py <lemmings.zip> debug/lemmings-1p
//     sim_run lem_video_tb simulator=verilator +CAP=debug/lemmings-1p
//     python sim/lem_video_tb/compare.py debug/lemmings-1p
//
// PLUSARGS +CAP= +LAT= (ROM and pixel read latency in clocks) +FLIP=
`timescale 1ns / 1ps

module tb_lem_video;
    logic clk = 1'b0;
    always #10.204082 clk = ~clk;
    logic reset = 1'b1;

    string cap = "debug/lemmings-1p";
    int    lat = 10;
    int    flip_arg = 0;

    logic [15:0] list0 [0:1023], list1 [0:1023];
    logic [63:0] rom0 [0:32767], rom1 [0:32767];
    logic [63:0] pix [0:65535];
    logic [15:0] tpix [0:65535], vram [0:2047];
    logic [23:0] pal [0:1023];
    logic [15:0] ctl [0:7];
    logic [15:0] meta [0:0];

    logic [9:0]  list0_addr, list1_addr, pal_addr;
    logic [15:0] list0_q, list1_q, vram_q, tpix_q;
    logic [63:0] pix_q;
    logic [23:0] pal_q;
    logic [14:0] rom0_addr, rom1_addr;
    logic [15:0] tpix_addr;
    logic        rom0_cs, rom1_cs, rom0_ok, rom1_ok, pix_cs, pix_ok;
    logic [63:0] rom0_q, rom1_q;
    logic [15:0] pix_addr;
    logic [10:0] vram_addr;
    logic        ce_pix, vga_hs, vga_vs, vga_hblank, vga_vblank, vblank_rise;
    logic [7:0]  vga_r, vga_g, vga_b, max_tiles;
    logic [8:0]  vcount;
    logic [15:0] overrun_spr, overrun_pix;
    logic        flip = 1'b0, frame_odd = 1'b0;

    lem_video dut (.clk, .reset, .flip, .frame_odd,
        .scroll1(ctl[0]), .scroll0(ctl[2]), .window(ctl[6][1]),
        .list0_addr, .list0_q, .list1_addr, .list1_q,
        .rom0_addr, .rom0_cs, .rom0_ok, .rom0_q, .rom1_addr, .rom1_cs, .rom1_ok, .rom1_q,
        .pix_addr, .pix_cs, .pix_ok, .pix_q, .vram_addr, .vram_q, .tpix_addr, .tpix_q,
        .pal_addr, .pal_q, .ce_pix, .vga_r, .vga_g, .vga_b, .vga_hs, .vga_vs, .vga_hblank,
        .vga_vblank, .vblank_rise, .vcount_o(vcount), .overrun_spr, .overrun_pix, .max_tiles);

    always_ff @(posedge clk) begin
        list0_q <= list0[list0_addr];
        list1_q <= list1[list1_addr];
        vram_q  <= vram[vram_addr];
        tpix_q  <= tpix[tpix_addr];
        pal_q   <= pal[pal_addr];
    end

    // ok follows the address, LAT clocks after it changes or cs rises.
    int w0, w1, wp;
    logic [14:0] a0, a1;
    logic [15:0] ap;
    logic have0 = 1'b0, have1 = 1'b0, havep = 1'b0;
    int reads0 = 0, reads1 = 0, readsp = 0;
    always_ff @(posedge clk) begin
        rom0_ok <= 1'b0;
        if (rom0_cs) begin
            if (!have0 || a0 != rom0_addr) begin
                have0 <= 1'b1; a0 <= rom0_addr; w0 <= lat; reads0 <= reads0 + 1;
            end else if (w0 > 1) w0 <= w0 - 1;
            else begin rom0_ok <= 1'b1; rom0_q <= rom0[rom0_addr]; end
        end else have0 <= 1'b0;

        rom1_ok <= 1'b0;
        if (rom1_cs) begin
            if (!have1 || a1 != rom1_addr) begin
                have1 <= 1'b1; a1 <= rom1_addr; w1 <= lat; reads1 <= reads1 + 1;
            end else if (w1 > 1) w1 <= w1 - 1;
            else begin rom1_ok <= 1'b1; rom1_q <= rom1[rom1_addr]; end
        end else have1 <= 1'b0;

        pix_ok <= 1'b0;
        if (pix_cs && !pix_ok) begin
            if (!havep || ap != pix_addr) begin
                havep <= 1'b1; ap <= pix_addr; wp <= lat; readsp <= readsp + 1;
            end else if (wp > 1) wp <= wp - 1;
            else begin pix_ok <= 1'b1; pix_q <= pix[pix_addr]; end
        end else havep <= 1'b0;
    end

    int fd = 0, frames = 0, n_out = 0;
    logic vs_prev = 1'b0;

    initial begin
        void'($value$plusargs("CAP=%s", cap));
        void'($value$plusargs("LAT=%d", lat));
        void'($value$plusargs("FLIP=%d", flip_arg));
        flip = flip_arg != 0;
        $readmemh({cap, "/rtl_list0.hex"}, list0);
        $readmemh({cap, "/rtl_list1.hex"}, list1);
        $readmemh("debug/lemmings-video/rom0.hex", rom0);
        $readmemh("debug/lemmings-video/rom1.hex", rom1);
        $readmemh({cap, "/rtl_pix.hex"}, pix);
        $readmemh({cap, "/rtl_tpix.hex"}, tpix);
        $readmemh({cap, "/rtl_vram.hex"}, vram);
        $readmemh({cap, "/rtl_pal.hex"}, pal);
        $readmemh({cap, "/rtl_ctl.hex"}, ctl);
        $readmemh({cap, "/rtl_odd.hex"}, meta);
        frame_odd = meta[0][0];
        repeat (20) @(posedge clk);
        reset <= 1'b0;
    end

    always_ff @(posedge clk) begin
        if (!reset && ce_pix) begin
            vs_prev <= vga_vs;
            if (vga_vs && !vs_prev) begin
                frames <= frames + 1;
                if (frames == 0) fd = $fopen({cap, flip ? "/rtl_flip.txt" : "/rtl_frame.txt"}, "w");
                if (frames == 1) begin
                    $fclose(fd);
                    $display("FRAME %0d pixels, LAT=%0d flip=%0d", n_out, lat, flip);
                    $display("OVERRUN sprites %0d pixel %0d, max tiles per line %0d", overrun_spr, overrun_pix, max_tiles);
                    $display("READS sprite0 %0d sprite1 %0d pixel %0d over two frames", reads0, reads1, readsp);
                    $finish;
                end
            end
            if (fd != 0 && !vga_hblank && !vga_vblank) begin
                $fdisplay(fd, "%02x%02x%02x", vga_r, vga_g, vga_b);
                n_out <= n_out + 1;
            end
        end
    end
endmodule
