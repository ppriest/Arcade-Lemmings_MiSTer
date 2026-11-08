`timescale 1ns/10ps
// clk_sys and SDRAM_CLK, both 49 MHz from the 50 MHz reference (docs/ROADMAP.md, Clocks):
// 7 x the 7 MHz pixel clock. outclk_1 is SDRAM_CLK 17857 ps behind (315 degrees, 2.55 ns ahead
// of clk_sys), near the 2.5 ns lead Arcade-Pandora_MiSTer uses at 48 MHz with this controller.
// The phase must be a multiple of the VCO step (1/8 VCO period): 17857 ps is one at either VCO
// Quartus can pick for 49 MHz (980 or 1470 MHz); 17908 ps was rejected by the fitter.
// Not swept (docs/HACKS.md).
module  pll_0002(

	// interface 'refclk'
	input wire refclk,

	// interface 'reset'
	input wire rst,

	// interface 'outclk0'
	output wire outclk_0,

	// interface 'outclk1'
	output wire outclk_1,

	// interface 'locked'
	output wire locked
);

	altera_pll #(
		.fractional_vco_multiplier("false"),
		.reference_clock_frequency("50.0 MHz"),
		.operation_mode("direct"),
		.number_of_clocks(2),
		.output_clock_frequency0("49.0 MHz"),
		.phase_shift0("0 ps"),
		.duty_cycle0(50),
		.output_clock_frequency1("49.0 MHz"),
		.phase_shift1("17857 ps"),
		.duty_cycle1(50),
		.output_clock_frequency2("0 MHz"),
		.phase_shift2("0 ps"),
		.duty_cycle2(50),
		.output_clock_frequency3("0 MHz"),
		.phase_shift3("0 ps"),
		.duty_cycle3(50),
		.output_clock_frequency4("0 MHz"),
		.phase_shift4("0 ps"),
		.duty_cycle4(50),
		.output_clock_frequency5("0 MHz"),
		.phase_shift5("0 ps"),
		.duty_cycle5(50),
		.output_clock_frequency6("0 MHz"),
		.phase_shift6("0 ps"),
		.duty_cycle6(50),
		.output_clock_frequency7("0 MHz"),
		.phase_shift7("0 ps"),
		.duty_cycle7(50),
		.output_clock_frequency8("0 MHz"),
		.phase_shift8("0 ps"),
		.duty_cycle8(50),
		.output_clock_frequency9("0 MHz"),
		.phase_shift9("0 ps"),
		.duty_cycle9(50),
		.output_clock_frequency10("0 MHz"),
		.phase_shift10("0 ps"),
		.duty_cycle10(50),
		.output_clock_frequency11("0 MHz"),
		.phase_shift11("0 ps"),
		.duty_cycle11(50),
		.output_clock_frequency12("0 MHz"),
		.phase_shift12("0 ps"),
		.duty_cycle12(50),
		.output_clock_frequency13("0 MHz"),
		.phase_shift13("0 ps"),
		.duty_cycle13(50),
		.output_clock_frequency14("0 MHz"),
		.phase_shift14("0 ps"),
		.duty_cycle14(50),
		.output_clock_frequency15("0 MHz"),
		.phase_shift15("0 ps"),
		.duty_cycle15(50),
		.output_clock_frequency16("0 MHz"),
		.phase_shift16("0 ps"),
		.duty_cycle16(50),
		.output_clock_frequency17("0 MHz"),
		.phase_shift17("0 ps"),
		.duty_cycle17(50),
		.pll_type("General"),
		.pll_subtype("General")
	) altera_pll_i (
		.rst	(rst),
		.outclk	({outclk_1, outclk_0}),
		.locked	(locked),
		.fboutclk	( ),
		.fbclk	(1'b0),
		.refclk	(refclk)
	);
endmodule

