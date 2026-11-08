// SPDX-License-Identifier: GPL-3.0-or-later
//
// Boot lemmings' 68000 through fx68k_bus against the real program ROM, log every access and count
// clocks for the CPI measurement. From Arcade-Cischeat_MiSTer sim/cischeat_boot_tb.
//
//     mame_boot_trace lemmings
//     python sim/lem_boot_tb/gen_inputs.py <lemmings.zip>
//     sim_compare_boot replay lemmings
//     sim_run lem_boot_tb
//     sim_compare_boot compare lemmings
//
// ROM and regions.json's trace.ram ranges are modelled; every other read replays MAME's value in
// MAME's order. The memory is a level handshake with LAT clocks of latency, not the SDRAM stack.
// Level 6 is raised IRQLEAD accesses before the last access ahead of MAME's interrupt frame
// (+IRQ=file) and held until acknowledged, so the comparison continues past the first interrupt.
// The CPU samples it during the access before an instruction's last prefetch, so 2 lands inside
// the instruction MAME interrupted after, however short that instruction is.
//
// PLUSARGS +ROM= +REPLAY= +TRACE= +IRQ= +N= +LAT= +IRQLEAD=
// PARAMETERS ICACHE, PHASE_NUM, PHASE_DEN.

`timescale 1ns / 1ps

module tb_lem_boot;

    parameter int ICACHE    = 1;
    parameter int PHASE_NUM = 7;     // 49 MHz / 14 MHz = 7/2
    parameter int PHASE_DEN = 2;

    logic clk = 1'b0;
    always #10.204082 clk = ~clk;

    logic reset = 1'b1;

    string  rom_path    = "debug/lemmings-boot/lemmings_rom.hex";
    string  replay_path = "debug/lemmings-boot/lemmings_replay.txt";
    string  trace_path  = "debug/lemmings-boot/lemmings_rtl.trace";
    string  irq_path    = "debug/lemmings-boot/lemmings_irq.txt";
    int     n_max       = 2000000;
    int     lat         = 2;
    int     irq_lead    = 2;

    initial begin
        void'($value$plusargs("ROM=%s", rom_path));
        void'($value$plusargs("REPLAY=%s", replay_path));
        void'($value$plusargs("TRACE=%s", trace_path));
        void'($value$plusargs("IRQ=%s", irq_path));
        void'($value$plusargs("N=%d", n_max));
        void'($value$plusargs("LAT=%d", lat));
        void'($value$plusargs("IRQLEAD=%d", irq_lead));
    end

    logic [15:0] rom [0:524287];
    logic [15:0] ram [0:2097151];

    localparam int MAX_REPLAY = 262144;
    logic [23:0] rp_addr [0:MAX_REPLAY-1];
    logic [15:0] rp_mask [0:MAX_REPLAY-1];
    logic [15:0] rp_data [0:MAX_REPLAY-1];
    int          rp_n = 0, rp_i = 0;

    localparam int MAX_IRQ = 8192;
    int          irq_at [0:MAX_IRQ-1];
    int          irq_n = 0, irq_i = 0;

    int     seq = 0;
    int     unmapped = 0, replay_miss = 0;
    logic   finished = 1'b0;
    longint cycles = 0, stalls = 0, bus_reqs = 0, bus_fills = 0;
    int     fd_trace;

    logic        bus_req, bus_we, bus_uds, bus_lds, bus_is_fill;
    logic [23:1] bus_addr;
    logic [15:0] bus_wdata, bus_rdata;
    logic        bus_ready;
    logic [2:0]  bus_fc;
    logic        dbg_stb, dbg_we, dbg_uds, dbg_lds;
    logic [23:1] dbg_addr;
    logic [15:0] dbg_data;
    logic        cycle_tick, stall_tick, iack;
    logic [2:0]  iack_level;
    logic        irq6 = 1'b0;

    fx68k_bus #(.PHASE_NUM(PHASE_NUM), .PHASE_DEN(PHASE_DEN), .ICACHE(ICACHE)) u_cpu (.fast(1'b0),
        .clk, .reset, .cpu_run(1'b1), .ipl_level(irq6 ? 3'd6 : 3'd0),
        .bus_req, .bus_we, .bus_addr, .bus_wdata, .bus_uds, .bus_lds, .bus_fc, .bus_is_fill,
        .bus_rdata, .bus_ready, .dbg_stb, .dbg_we, .dbg_addr, .dbg_data, .dbg_uds, .dbg_lds,
        .cycle_tick, .stall_tick, .iack, .iack_level);

    function automatic bit is_rom(input [23:0] a);
        is_rom = a < 24'h100000;
    endfunction

    // regions.json trace.ram
    function automatic bit is_ram(input [23:0] a);
        is_ram = (a >= 24'h100000 && a <= 24'h10ffff) || (a >= 24'h120000 && a <= 24'h1207ff) ||
                 (a >= 24'h140000 && a <= 24'h1407ff) || (a >= 24'h160000 && a <= 24'h160fff) ||
                 (a >= 24'h200000 && a <= 24'h202fff) || (a >= 24'h300000 && a <= 24'h39ffff);
    endfunction

    function automatic [15:0] lanes(input logic uds, lds);
        lanes = {uds ? 8'hFF : 8'h00, lds ? 8'hFF : 8'h00};
    endfunction

    logic        m_act, m_ready;
    logic [23:1] m_addr;
    logic [15:0] m_wdata, m_rdata;
    logic        m_we, m_uds, m_lds, m_fill;
    int          m_wait;

    assign bus_ready = m_ready;
    assign bus_rdata = m_rdata;

    always_ff @(posedge clk) begin
        if (reset) begin
            m_act <= 1'b0; m_ready <= 1'b0; m_wait <= 0; m_rdata <= 16'h0000;
        end else if (!bus_req) begin
            m_act <= 1'b0; m_ready <= 1'b0; m_wait <= 0;
        end else if (!m_act) begin
            m_act <= 1'b1; m_ready <= 1'b0; m_wait <= 0;
            m_addr <= bus_addr; m_wdata <= bus_wdata; m_we <= bus_we;
            m_uds <= bus_uds; m_lds <= bus_lds; m_fill <= bus_is_fill;
        end else if (!m_ready) begin
            if (m_wait + 1 >= lat) begin
                m_ready <= 1'b1;
                if (m_we) begin
                    if (is_ram({m_addr, 1'b0})) begin
                        if (m_uds) ram[m_addr[21:1]][15:8] <= m_wdata[15:8];
                        if (m_lds) ram[m_addr[21:1]][7:0]  <= m_wdata[7:0];
                    end
                end else if (is_rom({m_addr, 1'b0})) begin
                    m_rdata <= rom[m_addr[19:1]];
                end else if (is_ram({m_addr, 1'b0})) begin
                    m_rdata <= ram[m_addr[21:1]];
                end else if (m_fill) begin
                    m_rdata <= 16'hFFFF;
                end else if (rp_i < rp_n) begin
                    if (rp_addr[rp_i] == {m_addr, 1'b0} && rp_mask[rp_i] == lanes(m_uds, m_lds)) begin
                        m_rdata <= rp_data[rp_i];
                        rp_i    <= rp_i + 1;
                    end else begin
                        $display("REPLAY-MISS access %0d: RTL %06X %04X, replay %06X %04X",
                                 seq + 1, {m_addr, 1'b0}, lanes(m_uds, m_lds), rp_addr[rp_i], rp_mask[rp_i]);
                        replay_miss <= replay_miss + 1;
                        m_rdata <= 16'hFFFF;
                    end
                end else begin
                    $display("UNMAPPED read %06X at access %0d", {m_addr, 1'b0}, seq + 1);
                    unmapped <= unmapped + 1;
                    m_rdata <= 16'hFFFF;
                end
            end else m_wait <= m_wait + 1;
        end
    end

    initial begin
        int fd, ra, rm, rd, got;
        for (int i = 0; i < 2097152; i++) ram[i] = 16'h0000;
        fd_trace = $fopen(trace_path, "w");
        $readmemh(rom_path, rom);
        fd = $fopen(replay_path, "r");
        if (fd == 0) $fatal(1, "no replay file");
        while (!$feof(fd)) begin
            got = $fscanf(fd, "%x %x %x\n", ra, rm, rd);
            if (got == 3 && rp_n < MAX_REPLAY) begin
                rp_addr[rp_n] = ra[23:0]; rp_mask[rp_n] = rm[15:0]; rp_data[rp_n] = rd[15:0];
                rp_n = rp_n + 1;
            end
        end
        $fclose(fd);
        fd = $fopen(irq_path, "r");
        if (fd != 0) begin
            while (!$feof(fd)) begin
                got = $fscanf(fd, "%d\n", ra);
                if (got == 1 && irq_n < MAX_IRQ) begin irq_at[irq_n] = ra; irq_n = irq_n + 1; end
            end
            $fclose(fd);
        end
        $display("REPLAY %0d, IRQ %0d, ICACHE=%0d, %0d/%0d clk per CPU clock, LAT=%0d, IRQLEAD=%0d",
                 rp_n, irq_n, ICACHE, PHASE_NUM, PHASE_DEN, lat, irq_lead);
        repeat (40) @(posedge clk);
        reset <= 1'b0;
    end

    logic reqs_prev;
    always_ff @(posedge clk) begin
        reqs_prev <= reset ? 1'b0 : bus_req;
        if (!reset) begin
            if (cycle_tick) cycles <= cycles + 1;
            if (stall_tick) stalls <= stalls + 1;
            if (bus_req && !reqs_prev) begin
                bus_reqs <= bus_reqs + 1;
                if (bus_is_fill) bus_fills <= bus_fills + 1;
            end
            if (iack && iack_level == 3'd6) irq6 <= 1'b0;
        end
    end

    always_ff @(posedge clk) begin
        if (dbg_stb && !finished) begin
            seq <= seq + 1;
            $fdisplay(fd_trace, "%0d\t%s\t%06X\t%04X\t%04X", seq + 1, dbg_we ? "w" : "r",
                      {dbg_addr, 1'b0}, lanes(dbg_uds, dbg_lds), dbg_data & lanes(dbg_uds, dbg_lds));
            if (irq_i < irq_n && seq + 1 >= irq_at[irq_i] - irq_lead) begin
                irq6  <= 1'b1;
                irq_i <= irq_i + 1;
            end
            if (seq + 1 >= n_max) begin
                finished <= 1'b1;
                $fclose(fd_trace);
                $display("TRACE %0d accesses (unmapped %0d, replay misses %0d, replay used %0d)",
                         seq + 1, unmapped, replay_miss, rp_i);
                $display("BUS   %0d memory transactions, %0d cache fill words", bus_reqs, bus_fills);
                $display("CPI   %0d CPU clocks, %0d stall clk, %0d accesses: %.3f CPU clocks + %.3f stall clk per access",
                         cycles, stalls, seq + 1, real'(cycles) / real'(seq + 1), real'(stalls) / real'(seq + 1));
                $display("TIME  %.3f ms at 49 MHz; these CPU clocks at 14 MHz with no stalls %.3f ms",
                         real'($time) / 1.0e6, real'(cycles) / 14000.0);
                $finish;
            end
        end
    end

    initial begin
        #20.0e9;
        $display("TIMEOUT at %0d accesses (%0d unmapped, %0d replay misses)", seq, unmapped, replay_miss);
        $fclose(fd_trace);
        $finish;
    end

endmodule
