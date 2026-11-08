// SPDX-License-Identifier: GPL-3.0-or-later
//
// The Lemmings board's video: raster, two sprite line engines, the pixel layer's line fetch, the
// tilemap and the mix. Every RAM is outside, with a synchronous read of one clock. Sprites and the
// pixel layer are rendered into line buffers two raster lines ahead; the tilemap is read as shown.
//
// Timing per clk_sys pixel: hcount holds x for 7 clocks. In the next 7 (x_prev = x) the sprite
// buffers, tilemap, tile pixels, pixel-layer buffer and palette are read for x, and the colour is
// registered at that pixel's ce: vga_* trail hcount by two pixels.
//
// flip rotates the frame 180 degrees: every fetch and buffer read takes the rotated coordinate.
module lem_video (
    input  logic        clk,          // 49 MHz
    input  logic        reset,
    input  logic        flip,
    input  logic        frame_odd,    // decospr.cpp:227, blink

    input  logic [15:0] scroll1,      // control word 0
    input  logic [15:0] scroll0,      // control word 2
    input  logic        window,       // control word 6 bit 1

    // chip 0 draws list 2 from sprites2, chip 1 list 1 from sprites1 (lemmings.cpp:234-235, 474-475).
    output logic [9:0]  list0_addr,
    input  logic [15:0] list0_q,
    output logic [9:0]  list1_addr,
    input  logic [15:0] list1_q,

    // Held until ok; ok follows the address.
    output logic [14:0] rom0_addr,    // tile rows: {code, row}
    output logic        rom0_cs,
    input  logic        rom0_ok,
    input  logic [63:0] rom0_q,       // lem_sprite_line's layout
    output logic [14:0] rom1_addr,
    output logic        rom1_cs,
    input  logic        rom1_ok,
    input  logic [63:0] rom1_q,

    output logic [15:0] pix_addr,     // four-word groups of 0x300000, word i in q[16*i +: 16]
    output logic        pix_cs,
    input  logic        pix_ok,
    input  logic [63:0] pix_q,

    output logic [10:0] vram_addr,
    input  logic [15:0] vram_q,
    output logic [15:0] tpix_addr,    // words of 0x380000
    input  logic [15:0] tpix_q,
    output logic [9:0]  pal_addr,
    input  logic [23:0] pal_q,        // RGB

    output logic        ce_pix,
    output logic [7:0]  vga_r,
    output logic [7:0]  vga_g,
    output logic [7:0]  vga_b,
    output logic        vga_hs,
    output logic        vga_vs,
    output logic        vga_hblank,
    output logic        vga_vblank,

    output logic        vblank_rise,
    output logic [8:0]  vcount_o,
    output logic [15:0] overrun_spr,  // lines whose sprites were cut short, saturating
    output logic [15:0] overrun_pix,
    output logic [7:0]  max_tiles     // most tiles drawn on one line by either chip
);
    localparam int H_TOTAL = 442, H_ACTIVE = 320, H_SYNC = 344, H_SYNC_END = 376;
    localparam int V_TOTAL = 264, V_FIRST = 16, V_LAST = 239, V_SYNC = 244, V_SYNC_END = 247;

    // ---------------------------------------------------------------- raster
    logic [2:0] phase;
    logic [8:0] hcount, vcount;
    logic [8:0] x_prev;                 // the pixel being read and mixed
    assign ce_pix = phase == 3'd6;
    assign vcount_o = vcount;

    always_ff @(posedge clk) begin
        if (reset) begin
            phase <= 3'd0; hcount <= 9'd0; vcount <= 9'd0;
        end else begin
            phase <= ce_pix ? 3'd0 : phase + 3'd1;
            if (ce_pix) begin
                if (hcount == 9'(H_TOTAL - 1)) begin
                    hcount <= 9'd0;
                    vcount <= vcount == 9'(V_TOTAL - 1) ? 9'd0 : vcount + 9'd1;
                end else
                    hcount <= hcount + 9'd1;
            end
        end
    end

    assign vblank_rise = ce_pix && hcount == 9'(H_TOTAL - 1) && vcount == 9'(V_LAST);

    // One pixel before hcount 0: the buffers swap and the next line's render starts.
    logic line_end, line_start;
    assign line_end   = hcount == 9'(H_TOTAL - 1);
    assign line_start = line_end && ce_pix;

    // A line rendered between two swaps is read out after the second, so the render that starts
    // here is for the raster line after next.
    logic [8:0] vnext;
    assign vnext = vcount >= 9'(V_TOTAL - 2) ? vcount - 9'(V_TOTAL - 2) : vcount + 9'd2;
    logic       vnext_vis;
    assign vnext_vis = vnext >= 9'(V_FIRST) && vnext <= 9'(V_LAST);
    logic [7:0] target;                 // the rotated line that raster line shows
    assign target = flip ? 8'd255 - vnext[7:0] : vnext[7:0];

    // ---------------------------------------------------------------- sprites
    logic [8:0] spr0, spr1;             // {priority, colour, pen}
    lem_sprite_line u_spr0 (.clk, .reset, .flip, .frame_odd, .hdump(x_prev), .ce_pix,
        .line_end, .start(line_start && vnext_vis), .target(target),
        .list_addr(list0_addr), .list_q(list0_q),
        .rom_addr(rom0_addr), .rom_cs(rom0_cs), .rom_ok(rom0_ok), .rom_q(rom0_q),
        .pxl(spr0), .overrun(ovr0), .tiles(tiles0));
    lem_sprite_line u_spr1 (.clk, .reset, .flip, .frame_odd, .hdump(x_prev), .ce_pix,
        .line_end, .start(line_start && vnext_vis), .target(target),
        .list_addr(list1_addr), .list_q(list1_q),
        .rom_addr(rom1_addr), .rom_cs(rom1_cs), .rom_ok(rom1_ok), .rom_q(rom1_q),
        .pxl(spr1), .overrun(ovr1), .tiles(tiles1));
    logic       ovr0, ovr1;
    logic [7:0] tiles0, tiles1;

    always_ff @(posedge clk) begin
        if (reset) begin
            overrun_spr <= '0; overrun_pix <= '0; max_tiles <= '0;
        end else begin
            if ((ovr0 || ovr1) && &overrun_spr == 1'b0) overrun_spr <= overrun_spr + 1'd1;
            if (pix_overrun && &overrun_pix == 1'b0)    overrun_pix <= overrun_pix + 1'd1;
            if (tiles0 > max_tiles) max_tiles <= tiles0;
            if (tiles1 > max_tiles) max_tiles <= tiles1;
        end
    end

    // ---------------------------------------------------------------- pixel layer line fetch
    // lemmings.cpp:206-222: the last column of each rectangle and the last line are not drawn;
    // docs/MAME_KLUDGES.md. The buffer is written in unrotated x and read rotated.
    logic       page;
    logic [3:0] plb [0:1023];
    logic [8:0] fx;
    logic       fbusy, fword_ok, pix_overrun;
    logic [7:0] fline;
    logic [63:0] fword;
    logic [10:0] fpos;
    logic        fwin_left;
    assign fwin_left = window && fx < 9'd160;
    assign fpos = 11'(fx) + (fwin_left ? scroll0[10:0] : scroll1[10:0]);
    assign pix_addr = {fline, fpos[10:3]};

    logic fskip;
    assign fskip = fx == 9'd319 || (window && fx == 9'd159) || fline == 8'(V_LAST);

    logic [3:0] fnib;
    logic [15:0] fw;
    always_comb case (fpos[2:1])
        2'd0: fw = fword[15:0];
        2'd1: fw = fword[31:16];
        2'd2: fw = fword[47:32];
        2'd3: fw = fword[63:48];
    endcase
    assign fnib = fpos[0] ? fw[3:0] : fw[11:8];

    typedef enum logic [1:0] {F_IDLE, F_REQ, F_WR} fstate_t;
    fstate_t fstate;
    assign pix_cs = fstate == F_REQ;

    always_ff @(posedge clk) begin
        pix_overrun <= 1'b0;
        if (reset) begin
            fstate <= F_IDLE; page <= 1'b0; fx <= '0; fline <= '0;
        end else begin
            if (line_start) begin
                page <= ~page;
                if (fstate != F_IDLE) pix_overrun <= 1'b1;
                fstate <= F_IDLE;
                if (vnext_vis) begin
                    fx     <= '0;
                    fline  <= target;
                    fstate <= F_REQ;
                end
            end else case (fstate)
                F_REQ: if (pix_ok) begin
                    fword  <= pix_q;
                    fstate <= F_WR;
                end
                F_WR: begin
                    plb[{page, fx}] <= fskip ? 4'd0 : fnib;
                    fx <= fx + 9'd1;
                    if (fx == 9'(H_ACTIVE - 1))
                        fstate <= F_IDLE;
                    else if (&fpos[2:0] || (window && fx == 9'd159))
                        fstate <= F_REQ;    // the next pixel is in another group
                end
                default: ;
            endcase
        end
    end

    // ---------------------------------------------------------------- pixel pipeline
    // x_prev is the pixel whose sprite data is now arriving.
    logic       vis_prev;
    logic [8:0] xr;
    logic [7:0] yr;
    assign xr = flip ? 9'd319 - x_prev : x_prev;
    assign yr = flip ? 8'd255 - vcount[7:0] : vcount[7:0];

    // Tile index: lemmings.cpp:130, TILEMAP_SCAN_COLS.
    assign vram_addr = {xr[8:3], yr[7:3]};

    logic [3:0] tcol;
    logic [3:0] tpen, lpen;
    logic [3:0] tcol_r;
    // Tile pixels: lemmings.cpp:187-196, tile t at sx = t[10:5]*8, sy = t[4:0]*8.
    assign tpix_addr = {tile_r[4:0], yr[2:0], tile_r[10:5], xr[2:1]};
    logic [10:0] tile_r;

    logic [3:0] plb_q;
    always_ff @(posedge clk) begin
        plb_q <= plb[{~page, xr}];
        case (phase)
            3'd1: begin tile_r <= vram_q[10:0]; tcol_r <= vram_q[15:12]; end
            3'd3: begin tpen <= xr[0] ? tpix_q[3:0] : tpix_q[11:8]; tcol <= tcol_r; end
            3'd2: lpen <= plb_q;
            default: ;
        endcase
    end

    // ---------------------------------------------------------------- mix, lemmings.cpp:237-257
    logic [9:0] mix;
    logic       mix_black;
    always_comb begin
        mix_black = 1'b0;
        mix       = 10'd0;
        if (spr1[3:0] != 0 && !spr1[8])      mix = {2'b10, spr1[7:0]};
        else if (tpen != 0)                  mix = {2'b00, tcol, tpen};
        else if (spr0[3:0] != 0 && !spr0[8]) mix = {2'b11, spr0[7:0]};
        else if (spr1[3:0] != 0 && spr1[8])  mix = {2'b10, spr1[7:0]};
        else if (lpen != 0)                  mix = {6'b010000, lpen};
        else if (spr0[3:0] != 0 && spr0[8])  mix = {2'b11, spr0[7:0]};
        else                                 mix_black = 1'b1;
    end

    logic mix_black_r;
    logic [8:0] x_out;
    always_ff @(posedge clk) begin
        if (phase == 3'd4) begin
            pal_addr    <= mix;
            mix_black_r <= mix_black;
        end
        if (ce_pix) begin
            x_prev   <= hcount;
            vis_prev <= hcount < 9'(H_ACTIVE) && vcount >= 9'(V_FIRST) && vcount <= 9'(V_LAST);
            {vga_r, vga_g, vga_b} <= vis_prev && !mix_black_r ? pal_q : 24'd0;
            vga_hblank <= !(x_prev < 9'(H_ACTIVE));
            vga_vblank <= !(vcount >= 9'(V_FIRST) && vcount <= 9'(V_LAST));
            vga_hs     <= x_prev >= 9'(H_SYNC) && x_prev < 9'(H_SYNC_END);
            vga_vs     <= vcount >= 9'(V_SYNC) && vcount < 9'(V_SYNC_END);
        end
    end
endmodule

// One chip's line, as three stages joined by queues so the ROM fetch of one tile overlaps the
// drawing of the one before: the scan walks the list in order and queues every tile row that crosses
// the target line; the fetch reads that row, both halves in one 64-bit access; the draw feeds it to
// jtframe_objdraw. Later entries overwrite earlier ones, as decospr.cpp:211 draws them.
module lem_sprite_line (
    input  logic        clk,
    input  logic        reset,
    input  logic        flip,
    input  logic        frame_odd,
    input  logic [8:0]  hdump,
    input  logic        ce_pix,
    input  logic        line_end,     // high for the last pixel of the line
    input  logic        start,
    input  logic [7:0]  target,

    output logic [9:0]  list_addr,
    input  logic [15:0] list_q,

    // One tile row: {code, row}. q[63:32] is the left half (region offset +64), q[31:0] the right,
    // each the region's bytes 0..3 MSB first.
    output logic [14:0] rom_addr,
    output logic        rom_cs,
    input  logic        rom_ok,
    input  logic [63:0] rom_q,

    output logic [8:0]  pxl,
    output logic        overrun,
    output logic [7:0]  tiles
);
    // ------------------------------------------------------------ scan
    typedef enum logic [2:0] {S_IDLE, S_Y, S_X, S_CODE, S_PUSH, S_NEXT} state_t;
    state_t state;
    logic [7:0]  idx;
    logic [15:0] y0, x0, code0;
    logic        second;              // the double-width tile

    // decospr.cpp:254-256, 263-273, 297-304 with flip_screen true: the two 240 - y and 304 - x
    // cancel, both flips invert.
    logic [7:0] line_r;               // target moves with vcount one pixel after start
    logic [8:0] dline;
    assign dline = {1'b0, line_r} - y0[8:0];
    logic [7:0] multi;
    assign multi = (8'd1 << y0[10:9]) - 8'd1;
    logic [8:0] dline_y;
    assign dline_y = {1'b0, line_r} - list_q[8:0];
    logic hit_q, blink_q;
    assign hit_q   = dline_y[8:4] < (5'd1 << list_q[10:9]);
    assign blink_q = list_q[12] && frame_odd;

    logic [10:0] base, slot, code_y, code_d, multi11;
    assign multi11 = {3'd0, multi};
    assign base   = code0[10:0] & ~multi11;
    assign slot   = {6'd0, dline[8:4]};
    assign code_y = y0[14] ? base + slot : base + multi11 - slot;
    assign code_d = second ? code_y - multi11 - 11'd1 : code_y;
    logic [8:0] x_d;
    assign x_d = second ? x0[8:0] + 9'd16 : x0[8:0];
    logic x_vis;                      // any of the 16 columns lands in 0..319 of the 9-bit buffer
    assign x_vis = x_d < 9'd320 || x_d > 9'd496;

    assign list_addr = {idx, state == S_Y ? 2'b10 : state == S_X ? 2'b01 : 2'b00};

    // Job: {pal[4:0], vflip, hflip, ysub[3:0], x[8:0], code[10:0]}
    localparam int JW = 31;
    logic [JW-1:0] job_in;
    assign job_in = {y0[15], x0[12:9], ~y0[14], ~y0[13], dline[3:0], x_d, code_d};

    logic [JW-1:0] jq [0:3];
    logic [2:0]    jq_wr, jq_rd;
    logic          jq_full, jq_empty, jq_push, jq_pop;
    assign jq_full  = jq_wr - jq_rd == 3'd4;
    assign jq_empty = jq_wr == jq_rd;

    logic [7:0] tile_count;
    logic       scan_done;
    assign scan_done = state == S_IDLE;

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= S_IDLE; idx <= '0; tiles <= '0; tile_count <= '0; second <= 1'b0;
        end else if (start) begin
            tiles      <= tile_count;
            tile_count <= '0;
            line_r     <= target;
            idx        <= '0;
            second     <= 1'b0;
            state      <= S_NEXT;     // one clock for word 0 of entry 0
        end else case (state)
            S_Y: begin                // list_q is word 0 of idx
                y0 <= list_q;
                if (hit_q && !blink_q) state <= S_X;
                else if (idx == 8'd255) state <= S_IDLE;
                else begin idx <= idx + 8'd1; state <= S_NEXT; end
            end
            S_X:    begin x0 <= list_q; state <= S_CODE; end
            S_CODE: begin code0 <= list_q; second <= 1'b0; state <= S_PUSH; end
            S_PUSH: if (!x_vis || !jq_full) begin
                if (x_vis && tile_count != 8'hff) tile_count <= tile_count + 8'd1;
                if (y0[11] && !second) second <= 1'b1;
                else if (idx == 8'd255) state <= S_IDLE;
                else begin idx <= idx + 8'd1; state <= S_NEXT; end
            end
            S_NEXT: state <= S_Y;
            default: ;
        endcase
    end
    assign jq_push = state == S_PUSH && x_vis && !jq_full && !start;

    // ------------------------------------------------------------ fetch
    // Two rows ready for the draw: the one drawing and the next.
    logic [JW-1:0] dq_job  [0:1];
    logic [63:0]   dq_data [0:1];
    logic [1:0]    dq_wr, dq_rd;
    logic          dq_full, dq_empty;
    assign dq_full  = dq_wr - dq_rd == 2'd2;
    assign dq_empty = dq_wr == dq_rd;

    logic [JW-1:0] fjob;
    assign fjob     = jq[jq_rd[1:0]];
    logic fgap;                       // cs drops for a clock between rows: ok follows the address late
    assign rom_cs   = !jq_empty && !dq_full && !start && !fgap;
    assign rom_addr = {fjob[10:0], fjob[23:20] ^ {4{fjob[25]}}};
    assign jq_pop   = rom_cs && rom_ok;

    always_ff @(posedge clk) begin
        fgap <= jq_pop;
        if (reset || start) begin
            jq_wr <= '0; jq_rd <= '0; dq_wr <= '0;
        end else begin
            if (jq_push) begin jq[jq_wr[1:0]] <= job_in; jq_wr <= jq_wr + 3'd1; end
            if (jq_pop) begin
                dq_job[dq_wr[0]]  <= fjob;
                dq_data[dq_wr[0]] <= rom_q;
                dq_wr <= dq_wr + 2'd1;
                jq_rd <= jq_rd + 3'd1;
            end
        end
    end

    // ------------------------------------------------------------ draw
    logic [JW-1:0] djob;
    logic [63:0]   ddata;
    assign djob  = dq_job[dq_rd[0]];
    assign ddata = dq_data[dq_rd[0]];

    logic busy, draw, drawing;
    logic [17:2] d_rom_addr;          // {code, H, row} from jtframe_draw
    logic        d_rom_cs;
    logic [31:0] half, half_rev;
    assign half = d_rom_addr[6] ? ddata[63:32] : ddata[31:0];

    function automatic logic [7:0] rev8(input logic [7:0] v);
        rev8 = {v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7]};
    endfunction
    // sprite_layout: plane 0 (region byte 0) is the pen's top bit and each byte's MSB is leftmost;
    // jtframe_draw takes plane 3 in the top byte and each byte's LSB leftmost.
    assign half_rev = {rev8(half[31:24]), rev8(half[23:16]), rev8(half[15:8]), rev8(half[7:0])};

    always_ff @(posedge clk) begin
        draw <= 1'b0;
        if (reset || start) begin
            dq_rd <= '0; drawing <= 1'b0;
        end else if (!drawing) begin
            if (!dq_empty && !busy) begin draw <= 1'b1; drawing <= 1'b1; end
        end else if (!draw && !busy) begin  // busy rises the clock after draw
            drawing <= 1'b0;
            dq_rd   <= dq_rd + 2'd1;
        end
    end

    always_ff @(posedge clk)
        if (start) overrun <= !scan_done || !jq_empty || !dq_empty || drawing;
        else       overrun <= 1'b0;

    // SWAPH: sprite_layout holds the right half first. HFIX off: hdump is the pixel whose ce just
    // passed, since the buffer is addressed the clock after rd. FLIP_OFFSET: ~x + 320 is 319 - x in
    // nine bits.
    jtframe_objdraw #(
        .AW(9), .CW(11), .PW(9), .ZW(6), .SWAPH(1), .HFIX(0), .FLIP_OFFSET(320), .ALPHA(0)
    ) u_draw (
        .rst(reset), .clk, .pxl_cen(ce_pix), .hs(line_end), .flip, .hdump,
        .draw, .busy, .code(djob[10:0]), .xpos(djob[19:11]), .ysub(djob[23:20]),
        .hzoom(6'd0), .hz_keep(1'b0),
        .hflip(djob[24]), .vflip(djob[25]), .pal(djob[30:26]), .rom_addr(d_rom_addr),
        .rom_cs(d_rom_cs), .rom_ok(drawing && d_rom_cs), .rom_data(half_rev),
        .pxl
    );
endmodule
