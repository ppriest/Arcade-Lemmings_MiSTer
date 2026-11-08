// SPDX-License-Identifier: GPL-3.0-or-later
// rtl/protection/lem_deco146.sv against a Python port of MAME's deco_146_base_device
// (scripts/gen_deco146.py), over sim/deco146_tb/gen_ops.py's operations.
// sim/deco146_tb/run.sh runs it. RUN FROM THE REPOSITORY ROOT.
`timescale 1ns/1ps
module tb_deco146;
	logic clk = 0;
	always #5 clk = ~clk;
	logic reset = 1, rd = 0, wr = 0, snd_ack = 0;
	logic [10:1] addr;
	logic [15:0] din, dout, port_a, port_b, port_c;
	logic [1:0]  be;
	logic        valid, snd_irq;
	logic [7:0]  snd_latch;
	lem_deco146 dut (.clk, .reset, .rd, .wr, .addr, .din, .be, .dout, .valid,
		.port_a, .port_b, .port_c, .snd_latch, .snd_irq, .snd_ack);

	initial begin
		int f, kind, a, d, m, e, pa, pb, pc, irq, n, bad, nr, nl;
		f = $fopen("obj_iverilog/deco146_ops.txt", "r");
		if (f == 0) $fatal(1, "no ops file");
		repeat (4) @(posedge clk);
		reset <= 0;
		n = 0; bad = 0; nr = 0; nl = 0;
		while ($fscanf(f, "%h %h %h %h %h %h %h %h %h", kind, a, d, m, e, pa, pb, pc, irq) == 9) begin
			@(posedge clk);
			port_a <= pa; port_b <= pb; port_c <= pc;
			addr <= a[10:1]; din <= d; be <= {m[15:8] != 0, m[7:0] != 0};
			case (kind)
				0: rd <= 1;
				1: wr <= 1;
				default: begin
					snd_ack <= 1;
					if (snd_latch !== e[7:0]) begin
						if (bad < 10) $display("op %0d: latch RTL %02x MAME %02x", n, snd_latch, e);
						bad++;
					end
					nl++;
				end
			endcase
			@(posedge clk);
			wr <= 0; rd <= 0; snd_ack <= 0;
			if (kind == 0) begin
				do @(posedge clk); while (!valid);
				if (dout !== e[15:0]) begin
					if (bad < 10) $display("op %0d: read %03x RTL %04x MAME %04x", n, a, dout, e);
					bad++;
				end
				nr++;
			end else @(posedge clk);
			if (snd_irq !== irq[0]) begin
				if (bad < 10) $display("op %0d: snd_irq RTL %b MAME %b", n, snd_irq, irq[0]);
				bad++;
			end
			n++;
		end
		if (bad == 0) $display("PASS: %0d operations, %0d reads and %0d latch reads equal MAME's", n, nr, nl);
		else $display("FAIL: %0d differences in %0d operations", bad, n);
		$finish;
	end
endmodule
