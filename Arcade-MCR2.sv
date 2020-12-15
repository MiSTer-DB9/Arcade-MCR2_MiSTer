//============================================================================
//  Arcade: MCR2
//
//  Port to MiSTer
//  Copyright (C) 2019 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output [11:0] VIDEO_ARX,
	output [11:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler

	// Use framebuffer from DDRAM (USE_FB=1 in qsf)
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of 16 bytes.
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

   input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,    // 1 - signed audio samples, 0 - unsigned

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

        //High latency DDR3 RAM interface
        //Use for non-critical time purposes
        output        DDRAM_CLK,
        input         DDRAM_BUSY,
        output  [7:0] DDRAM_BURSTCNT,
        output [28:0] DDRAM_ADDR,
        input  [63:0] DDRAM_DOUT,
        input         DDRAM_DOUT_READY,
        output        DDRAM_RD,
        output [63:0] DDRAM_DIN,
        output  [7:0] DDRAM_BE,
        output        DDRAM_WE,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT
);

assign VGA_F1    = 0;
assign VGA_SCALER= 0;
assign USER_OUT  = '1;
assign LED_USER  = rom_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;

assign {FB_PAL_CLK, FB_FORCE_BLANK, FB_PAL_ADDR, FB_PAL_DOUT, FB_PAL_WR} = '0;

wire [1:0] ar = status[17:16];
assign VIDEO_ARX = (!ar) ? ((status[2] | orientation[0]) ? 8'd21 : 8'd20) : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? ((status[2] | orientation[0]) ? 8'd20 : 8'd21) : 12'd0;

`include "build_id.v" 
localparam CONF_STR = {
	"A.MCR2;;",
	"H0OGH,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"H1H0O2,Orientation,Vert,Horz;",
	"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"D4OD,Deinterlacer Hi-Res,Off,On;",
	"-;",
	"DIP;",
	"-;",
	"OA,Background Graphic,On,Off;",
	"-;",
	"R0,Reset;",
	"J1,Fire A,Fire B,Fire C,Fire D,Rotate CW,Rotate CCW,Start 1P,Start 2P,Coin;",
	"jn,A,B,X,Y,R,L,Start,Select;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys,clk_80m,pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys), // 40M
	.outclk_1(clk_80m), // 80M
	.locked(pll_locked)
);

///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire        direct_video;

wire [31:0] joy1, joy2;
wire [31:0] joy = joy1 | joy2;
wire  [8:0] sp1, sp2; 

wire [21:0] gamma_bus;

wire        ioctl_download;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;

wire [15:0] sdram_sz;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.buttons(buttons),
	.status(status),
	.status_menumask({|status[5:3],mod_twotiger,mod_tron|mod_kroozr,orientation[0],direct_video}),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_index(ioctl_index),

	.sdram_sz(sdram_sz),


	.joystick_0(joy1),
	.joystick_1(joy2),

	.spinner_0(sp1),
	.spinner_1(sp2) 

);

reg mod_shollow    = 0;
reg mod_tron       = 0;
reg mod_twotiger   = 0;
reg mod_wacko      = 0;
reg mod_kroozr     = 0;
reg mod_domino     = 0;

always @(posedge clk_sys) begin
	reg [7:0] mod = 0;
	if (ioctl_wr & (ioctl_index==1)) mod <= ioctl_dout;

	mod_shollow    <= ( mod == 0 );
	mod_tron       <= ( mod == 1 );
	mod_twotiger   <= ( mod == 2 );
	mod_wacko      <= ( mod == 3 );
	mod_kroozr     <= ( mod == 4 );
	mod_domino     <= ( mod == 5 );
end

// load the DIPS
reg [7:0] sw[8];
always @(posedge clk_sys) if (ioctl_wr && (ioctl_index==254) && !ioctl_addr[24:3]) sw[ioctl_addr[2:0]] <= ioctl_dout;



wire service = sw[1][0];

// Generic controls - make a module from this?

wire m_tilt    = 0;

wire m_start1  = joy[10];
wire m_start2  = joy[11];
wire m_coin1   = joy[12];

wire m_right1  = joy1[0];
wire m_left1   = joy1[1];
wire m_down1   = joy1[2];
wire m_up1     = joy1[3];
wire m_fire1a  = joy1[4];
wire m_fire1b  = joy1[5];
wire m_fire1c  = joy1[6];
wire m_fire1d  = joy1[7];
wire m_rcw1    = joy1[8];
wire m_rccw1   = joy1[9];
wire m_spccw1  = joy1[30];
wire m_spcw1   = joy1[31];

wire m_right2  = joy2[0];
wire m_left2   = joy2[1];
wire m_down2   = joy2[2];
wire m_up2     = joy2[3];
wire m_fire2a  = joy2[4];
wire m_fire2b  = joy2[5];
wire m_fire2c  = joy2[6];
wire m_fire2d  = joy2[7];
wire m_rcw2    = joy2[8];
wire m_rccw2   = joy2[9];
wire m_spccw2  = joy2[30];
wire m_spcw2   = joy2[31];

wire m_right   = m_right1 | m_right2;
wire m_left    = m_left1  | m_left2; 
wire m_down    = m_down1  | m_down2; 
wire m_up      = m_up1    | m_up2;   
wire m_fire_a  = m_fire1a | m_fire2a;
wire m_fire_b  = m_fire1b | m_fire2b;
wire m_fire_c  = m_fire1c | m_fire2c;
wire m_fire_d  = m_fire1d | m_fire2d;
wire m_rcw     = m_rcw1   | m_rcw2;
wire m_rccw    = m_rccw1  | m_rccw2;
wire m_spccw   = m_spccw1 | m_spccw2;
wire m_spcw    = m_spcw1  | m_spcw2;

reg [8:0] sp;
always @(posedge clk_sys) begin
	reg [8:0] old_sp1, old_sp2;
	reg       sp_sel = 0;

	old_sp1 <= sp1;
	old_sp2 <= sp2;
	
	if(old_sp1 != sp1) sp_sel <= 0;
	if(old_sp2 != sp2) sp_sel <= 1;

	sp <= sp_sel ? sp2 : sp1;
end
 
reg  [1:0] orientation; //left/right / portrait/landscape
reg  [7:0] input_0;
reg  [7:0] input_1;
reg  [7:0] input_2;
reg  [7:0] input_3;
reg  [7:0] input_4;

// Game specific sound board/DIP/input settings
always @(*) begin

	orientation = 2'b00;
	input_0 = 8'hff;
	input_1 = 8'hff;
	input_2 = 8'hff;
	input_3 = sw[0];
	input_4 = 8'hff;

	if (mod_shollow) begin
		input_0 = ~{ service, 1'b0, m_tilt, 1'b0, m_start2, m_start1, 1'b0, m_coin1 };
		input_1 = ~{ m_fire_a, m_fire_b, m_right, m_left, m_fire_a, m_fire_b, m_right, m_left };
	end
	else if (mod_tron) begin
		input_0 = ~{ service, 1'b0, m_tilt, m_fire_a, m_start2, m_start1, 1'b0, m_coin1 };
		input_1 = ~{ 1'b0, spin_tron[7:1] };
		input_2 = ~{ m_down, m_up, m_right, m_left, m_down, m_up, m_right, m_left };
		input_3[7] = ~{ m_fire_a };
		input_4 = ~{ 1'b0, spin_tron[7:1] };
	end
	else if (mod_twotiger) begin
		orientation = 2'b01;
		input_0 = ~{ service, 1'b0, m_tilt, m_fire_c, m_start2, m_start1, 1'b0, m_coin1 };
		input_1 = ~{ 1'b0, spin_angle1[7:1] };
		input_2 = ~{ 4'b0000, m_fire2b, m_fire2a, m_fire1b, m_fire1a };
		input_4 = ~{ 1'b0, spin_angle2[7:1] };
	end
	else if (mod_wacko) begin
		orientation = 2'b01;
		input_0 = ~{ service, 1'b0, m_tilt, 1'b0, m_start2, m_start1, 1'b0, m_coin1 };
		input_1 = wx;
		input_2 = wy;
		input_4 = ~{ m_fire_c, m_fire_b, m_fire_d, m_fire_a, m_fire_c, m_fire_b, m_fire_d, m_fire_a };
	end
	else if (mod_kroozr) begin
		orientation = 2'b01;
		input_0 = ~{ service, 1'b0, m_tilt, m_fire_a, m_start2, m_start1, 1'b0, m_coin1 };
		input_1 = ~{ m_fire_b, spin_krookz[7], 3'b111, spin_krookz[6:4] };
		input_2 = 8'd100 + (m_left ? -8'd63 : m_right ? 8'd63 : 8'd0);
		input_4 = 8'd100 + (m_up   ? -8'd63 : m_down  ? 8'd63 : 8'd0);
	end
	else if (mod_domino) begin
		orientation = 2'b01;
		input_0 = ~{ service, 1'b0, m_tilt, m_fire_a, m_start2, m_start1, 1'b0, m_coin1 };
		input_1 = ~{ 4'b0000, m_down, m_up, m_right, m_left };
		input_2 = ~{ 3'b000, m_fire_a, m_down, m_up, m_right, m_left };
	end
end

wire rom_download = ioctl_download && !ioctl_index;

wire [15:0] rom_addr;
wire  [7:0] rom_do;
wire [13:0] snd_addr;
wire  [7:0] snd_do;

/* ROM structure
00000 - 0BFFF  48k CPU1
0C000 - 0FFFF  16k CPU2
10000 - 13FFF  16k GFX1
14000 - 1BFFF  32k GFX2
*/
dpram #(8,16) rom
(
	.clk_a(clk_sys),
	.we_a(ioctl_wr && rom_download && !ioctl_addr[24:16]),
	.addr_a(rom_download ? ioctl_addr[15:0] : rom_addr),
	.d_a(ioctl_dout),
	.q_a(rom_do),

	.clk_b(clk_sys),
	.addr_b({2'b11,snd_addr}),
	.q_b(snd_do)
);

// reset signal generation
reg reset = 1;
reg rom_loaded = 0;
always @(posedge clk_sys) begin
	reg rom_downloadD;
	integer reset_count;
	rom_downloadD <= rom_download;

	// generate a second reset signal - needed for some reason
	if(reset_count) reset_count <= reset_count - 1;

	if (rom_downloadD & ~rom_download) rom_loaded <= 1;
	if(~rom_loaded) reset_count <= 40000000;

	reset <= status[0] | buttons[1] | rom_download | ~rom_loaded | (reset_count == 1);
end

mcr2 mcr2
(
	.clock_40(clk_sys),
	.reset(reset),
	.video_r(r),
	.video_g(g),
	.video_b(b),
	.video_vblank(vblank),
	.video_hblank(hblank),
	.video_hs(hs),
	.video_vs(vs),
	.video_csync(cs),
	.video_ce(ce_pix_old),
	.tv15Khz_mode(~status[13] || status[5:3]),
	.separate_audio(1'b0),
	.audio_out_l(AUDIO_L),
	.audio_out_r(AUDIO_R),

	.input_0(input_0),
	.input_1(input_1),
	.input_2(input_2),
	.input_3(input_3),
	.input_4(input_4),

	.cpu_rom_addr(rom_addr),
	.cpu_rom_do(rom_do),
	.snd_rom_addr(snd_addr),
	.snd_rom_do(snd_do),

	.dl_addr(ioctl_addr[16:0]),
	.dl_wr(ioctl_wr&rom_download),
	.dl_data(ioctl_dout)
);

wire ce_pix_old;
wire ce_pix;
wire hs, vs, cs;
wire hblank, vblank;
wire [2:0] r,g,b;

wire no_rotate = status[2] | direct_video | orientation[0];

wire fg = |{r,g,b};

wire [8:0] rgbdata  = status[10]? {r,g,b}  : (fg && !bg_a) ? {r,g,b} : {bg_r[7:5],bg_g[7:5],bg_b[7:5]};

wire rotate_ccw=orientation[1];

screen_rotate screen_rotate (.*);
always @(posedge clk_sys) begin
        reg [2:0] div;

        div <= div + 1'd1;
        ce_pix <= !div;
end


arcade_video #(512,9) arcade_video
(
	.*,
	.ce_pix(status[13] ? ce_pix_old: ce_pix),
	.clk_video(clk_sys),
	//.RGB_in({r,g,b}),
	.RGB_in(rgbdata),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(hs),
	.VSync(vs),

	.fx(status[5:3])
);

assign AUDIO_S = 0;


// Spinner for Tron
wire [7:0] spin_tron;
spinner #(25, 0, 12) spinner_tr
(
	.clk(clk_sys),
	.reset(reset),
	.minus(m_rccw | m_spccw),
	.plus(m_rcw | m_spcw),
	.strobe(vs),
	.spin_in(sp),
	.spin_out(spin_tron)
);

// Spinner for Krooz'r
wire [7:0] spin_krookz;
spinner #(25, 0, 12) spinner_kr
(
	.clk(clk_sys),
	.reset(reset),
	.minus(m_rccw | m_spccw),
	.plus(m_rcw | m_spcw),
	.strobe(vs),
	.spin_in(sp),
	.spin_out(spin_krookz)
);

// Spinners Two Tigers
wire [7:0] spin_angle1;
spinner #(55, 0, 25) spinner1 
(
	.clk(clk_sys),
	.reset(reset),
	.minus(m_rccw1 | m_left1 | m_spccw1),
	.plus(m_rcw1 | m_right1 | m_spcw1),
	.strobe(vs),
	.spin_in(sp1),
	.spin_out(spin_angle1)
);

wire [7:0] spin_angle2;
spinner #(55, 0, 25) spinner2 
(
	.clk(clk_sys),
	.reset(reset),
	.minus(m_rccw2 | m_left2 | m_spccw2),
	.plus(m_rcw2 | m_right2 | m_spcw2),
	.strobe(vs),
	.spin_in(sp2),
	.spin_out(spin_angle2)
);

// wacko
wire [7:0] wx;
spinner #(10) spinner_wx 
(
	.clk(clk_sys),
	.reset(reset),
	.minus(m_left),
	.plus(m_right),
	.strobe(vs),
	.spin_out(wx)
);

wire [7:0] wy;
spinner #(10) spinner_wy 
(
	.clk(clk_sys),
	.reset(reset),
	.minus(m_down),
	.plus(m_up),
	.strobe(vs),
	.spin_out(wy)
);

wire bg_download = ioctl_download && (ioctl_index == 2);

reg [7:0] ioctl_dout_r;
always @(posedge clk_sys) if(ioctl_wr & ~ioctl_addr[0]) ioctl_dout_r <= ioctl_dout;

wire [31:0] pic_data;
sdram sdram
(
        .*,

        .init(~pll_locked),
        .clk(clk_80m),
        .ch1_addr(bg_download ? ioctl_addr[24:1] : pic_addr),
        .ch1_dout(pic_data),
        .ch1_din({ioctl_dout, ioctl_dout_r}),
        .ch1_req(bg_download ? (ioctl_wr & ioctl_addr[0]) : pic_req),
        .ch1_rnw(~bg_download)
);


reg        pic_req;
reg [24:1] pic_addr;
reg  [7:0] bg_r,bg_g,bg_b,bg_a;
always @(posedge clk_sys) begin
        reg old_vs;
        reg use_bg = 0;

        if(bg_download && sdram_sz[2:0]) use_bg <= 1;

        pic_req <= 0;

        if(use_bg) begin
                if(ce_pix) begin
                        old_vs <= vs;
                        {bg_a,bg_b,bg_g,bg_r} <= pic_data;
                        if(~(hblank|vblank)) begin
                                pic_addr <= pic_addr + 2'd2;
                                pic_req <= 1;
                        end

                        if(~old_vs & vs) begin
                                pic_addr <= 0;
                                pic_req <= 1;
                        end
                end
        end
        else begin
                {bg_a,bg_b,bg_g,bg_r} <= 0;
        end
end


endmodule
