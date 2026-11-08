// SPDX-License-Identifier: GPL-3.0-or-later
//
// Area and Fmax for one 68000 behind fx68k_bus at this core's 7/2 clocks per CPU clock, with a
// synchronous RAM on its memory side: CPU -> wrapper -> RAM -> wrapper -> CPU, the loop the core
// runs. From Arcade-Cischeat_MiSTer rtl/synth_check/fx68k. The RAM has a write port so Quartus
// cannot treat its contents as a constant and prune the CPU's datapath.
module fx68k_top (
    input  logic       clk,
    input  logic       reset,
    output logic [7:0] sig
);
    logic        r_reset;
    logic [2:0]  r_ipl;
    always_ff @(posedge clk) begin
        r_reset <= reset;
        r_ipl   <= r_ipl + 3'd1;
    end

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

    logic [15:0] rom [0:2047];
    logic [15:0] rom_q;
    logic        ready_q;
    logic [10:0] wr_addr;
    logic [15:0] wr_data;

    fx68k_bus #(.PHASE_NUM(7), .PHASE_DEN(2), .ICACHE(1'b1)) u_bus (.fast(1'b0),
        .clk(clk), .reset(r_reset), .cpu_run(1'b1), .ipl_level(r_ipl),
        .bus_req(bus_req), .bus_we(bus_we), .bus_addr(bus_addr), .bus_wdata(bus_wdata),
        .bus_uds(bus_uds), .bus_lds(bus_lds), .bus_fc(bus_fc), .bus_is_fill(bus_is_fill),
        .bus_rdata(bus_rdata), .bus_ready(bus_ready), .dbg_stb(dbg_stb), .dbg_we(dbg_we),
        .dbg_addr(dbg_addr), .dbg_data(dbg_data), .dbg_uds(dbg_uds), .dbg_lds(dbg_lds),
        .cycle_tick(cycle_tick), .stall_tick(stall_tick), .iack(iack), .iack_level(iack_level));

    always_ff @(posedge clk) begin
        ready_q <= bus_req;
        if (bus_req) rom_q <= rom[bus_addr[11:1]];
        rom[wr_addr] <= wr_data;
        wr_addr      <= wr_addr + 11'd1;
        wr_data      <= wr_data + 16'd7;
    end

    assign bus_ready = ready_q;
    assign bus_rdata = rom_q;

    always_ff @(posedge clk)
        sig <= {8{^{cycle_tick, stall_tick, dbg_stb, dbg_we, dbg_uds, dbg_lds, dbg_addr, dbg_data,
                    bus_we, bus_uds, bus_lds, bus_is_fill, bus_addr, bus_wdata, bus_fc,
                    iack, iack_level}}};
endmodule
