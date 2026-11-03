module pll (
    input  wire clk_50m,
    input  wire reset,
    output wire pix_clk,
    output wire serial_clk_5x,
    output wire mem_clk,
    output wire sdram_clk,
    output wire locked
);
    wire [4:0] pll_clks;
    EG_PHY_PLL #(
        .FIN("50.0000"),
        .REFCLK_DIV(5),
        .FBCLK_DIV(63),
        .CLKC0_DIV(25), .CLKC1_DIV(5),
        .CLKC2_DIV(15), .CLKC3_DIV(15),
        .CLKC2_CPHASE(1), .CLKC3_CPHASE(8),
        .CLKC0_ENABLE("ENABLE"), .CLKC1_ENABLE("ENABLE"),
        .CLKC2_ENABLE("ENABLE"), .CLKC3_ENABLE("ENABLE"),
        .FEEDBK_MODE("NORMAL"), .FEEDBK_PATH("VCO_PHASE_0")
    ) pll (
        .clkc(pll_clks), .extlock(locked),
        .stdby(1'b0), .refclk(clk_50m), .fbclk(1'b0),
        .reset(reset), .load_reg(1'b0),
        .psdone(), .psclk(1'b0), .psdown(1'b0),
        .psstep(1'b0), .psclksel(3'b000),
        .\do (), .dclk(1'b0), .dcs(1'b0), .dwe(1'b0),
        .di(8'd0), .daddr(6'd0)
    );
    assign pix_clk = pll_clks[0];
    assign serial_clk_5x = pll_clks[1];
    
    assign mem_clk = pll_clks[2];
    assign sdram_clk = pll_clks[3];
endmodule
