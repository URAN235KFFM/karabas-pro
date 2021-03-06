-------------------------------------------------------------------------------
--
-- Karabas-pro Pong v1.0
--
-- Copyright (c) 2020 Andy Karpov
--
-------------------------------------------------------------------------------

--
-- All rights reserved
--
-- Redistribution and use in source and synthezised forms, with or without
-- modification, are permitted provided that the following conditions are met:
--
-- * Redistributions of source code must retain the above copyright notice,
--   this list of conditions and the following disclaimer.
--
-- * Redistributions in synthesized form must reproduce the above copyright
--   notice, this list of conditions and the following disclaimer in the
--   documentation and/or other materials provided with the distribution.
--
-- * Neither the name of the author nor the names of other contributors may
--   be used to endorse or promote products derived from this software without
--   specific prior written agreement from the author.
--
-- * License is granted for non-commercial use only.  A fee may not be charged
--   for redistributions as source code or in synthesized/hardware form without 
--   specific prior written agreement from the author.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
-- AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
-- THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
-- LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
-- CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
-- SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
-- INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
-- CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
-- ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
-- POSSIBILITY OF SUCH DAMAGE.

library IEEE; 
use IEEE.std_logic_1164.all; 
use IEEE.std_logic_unsigned.all;
use IEEE.numeric_std.all; 

entity karabas_pro_pong is
port (
	-- Clock (50MHz)
	CLK_50MHZ	: in std_logic;

	-- SRAM (2MB 2x8bit)
	SRAM_D		: inout std_logic_vector(7 downto 0);
	SRAM_A		: buffer std_logic_vector(20 downto 0);
	SRAM_NWR		: buffer std_logic;
	SRAM_NRD		: buffer std_logic;
	
	-- SPI FLASH (M25P16)
	DATA0			: in std_logic;  -- MISO
	NCSO			: out std_logic; -- /CS 
	DCLK			: out std_logic; -- SCK
	ASDO			: out std_logic; -- MOSI
	
	-- SD/MMC Card
	SD_NCS		: out std_logic; -- /CS
	
	-- VGA 
	VGA_R 		: out std_logic_vector(2 downto 0);
	VGA_G 		: out std_logic_vector(2 downto 0);
	VGA_B 		: out std_logic_vector(2 downto 0);
	VGA_HS 		: buffer std_logic;
	VGA_VS 		: buffer std_logic;
		
	-- AVR SPI slave
	AVR_SCK 		: in std_logic;
	AVR_MOSI 	: in std_logic;
	AVR_MISO 	: out std_logic;
	AVR_NCS		: in std_logic;
	
	-- Parallel bus for CPLD
	NRESET 		: out std_logic;
	CPLD_CLK 	: out std_logic;
	CPLD_CLK2 	: out std_logic;
	SDIR 			: out std_logic;
	SA				: out std_logic_vector(1 downto 0);
	SD				: inout std_logic_vector(15 downto 0) := "ZZZZZZZZZZZZZZZZ";
	
	-- I2S Sound TDA1543
	SND_BS		: out std_logic;
	SND_WS 		: out std_logic;
	SND_DAT 		: out std_logic;
	
	-- Misc I/O
	PIN_141		: inout std_logic;
	PIN_138 		: inout std_logic;
	PIN_121		: inout std_logic;
	PIN_120		: inout std_logic;
	PIN_119		: inout std_logic;
	PIN_115		: inout std_logic;
		
	-- UART / ESP8266
	UART_RX 		: in std_logic;
	UART_TX 		: out std_logic;
	UART_CTS 	: out std_logic
	
);
end karabas_pro_pong;

architecture rtl of karabas_pro_pong is

-- Keyboard
signal kb_l_paddle	: std_logic_vector(2 downto 0);
signal kb_r_paddle	: std_logic_vector(2 downto 0);
signal kb_reset 		: std_logic := '0';
signal kb_scanlines  : std_logic := '0';

-- CLOCK
signal clk_28 			: std_logic := '0';
signal clk_8 			: std_logic := '0';

-- System
signal reset			: std_logic;
signal areset			: std_logic;
signal locked			: std_logic;

-- Sound 
signal speaker 		: std_logic;
signal audio_l 		: std_logic_vector(15 downto 0);
signal audio_r 		: std_logic_vector(15 downto 0);

-- Game 
signal pix_div 		: std_logic_vector(3 downto 0) := "0000";
signal dummyclk 		: std_logic := '0';
signal pixtick 		: std_logic;

signal l_human 		: std_logic := '0';
signal l_move 			: std_logic_vector(1 downto 0) := "00";
signal r_human 		: std_logic := '0';
signal r_move 			: std_logic_vector(1 downto 0) := "00";

signal prev_vsync 	: std_logic := '1';

signal hsync 			: std_logic;
signal vsync 			: std_logic;
signal csync 			: std_logic;
signal ball 			: std_logic;
signal left_bat 		: std_logic;
signal right_bat 		: std_logic;
signal field_and_score : std_logic;
signal sound 			: std_logic;
signal sel 				: std_logic_vector(3 downto 0) := "0000";
signal rgb 				: std_logic_vector(8 downto 0) := "000000000";

component altpll0 
port (
	inclk0 				: in std_logic;
	locked 				: out std_logic;
	c0 					: out std_logic;
	c1 					: out std_logic
);
end component;

component tennis
port (
	glb_clk				: in std_logic;
	pixtick				: in std_logic;
	reset					: in std_logic;
	lbat_human			: in std_logic;
	lbat_move			: in std_logic_vector(8 downto 0);
	rbat_human			: in std_logic;
	rbat_move			: in std_logic_vector(8 downto 0);
	tv_mode 				: in std_logic;
	scanlines 			: in std_logic;
	
	hsync					: out std_logic;
	vsync					: out std_logic;
	csync					: out std_logic;
	
	ball					: out std_logic;
	left_bat				: out std_logic;
	right_bat			: out std_logic;
	field_and_score 	: out std_logic;
	sound 				: out std_logic);
end component;

begin

-------------------------------------------------------------------------------
-- PLL

U1: altpll0
port map (
	inclk0			=> CLK_50MHZ,	--  50.0 MHz
	locked			=> locked,
	c0 				=> clk_28,
	c1 				=> clk_8);

-------------------------------------------------------------------------------
-- AVR keyboard

U2: entity work.cpld_kbd
port map (
	 CLK 				=> clk_28,
	 N_RESET 		=> not areset,

    AVR_MOSI		=> AVR_MOSI,
    AVR_MISO		=> AVR_MISO,
    AVR_SCK			=> AVR_SCK,
	 AVR_SS 			=> AVR_NCS,
	 
	 RESET 			=> kb_reset,
	 SCANLINES 		=> kb_scanlines,
	 
	 L_PADDLE 		=> kb_l_paddle,
	 R_PADDLE 		=> kb_r_paddle);

-------------------------------------------------------------------------------
-- i2s sound

U3: entity work.tda1543
port map (
	RESET				=> reset,
	CLK 				=> clk_8,
	CS 				=> '1',
	DATA_L 			=> audio_l,
	DATA_R 			=> audio_r,
	BCK 				=> SND_BS,
	WS  				=> SND_WS,
	DATA 				=> SND_DAT);

-------------------------------------------------------------------------------
-- game logic

U4: tennis 
port map (
	glb_clk 			=> clk_28,
	pixtick 			=> pixtick,
	reset 			=> reset,
	lbat_human 		=> l_human,
	lbat_move 		=> l_move(1) & l_move(1) & l_move(1) & l_move(1) & l_move(1) & l_move(1) & l_move(0) & "00",
	rbat_human 		=> r_human,
	rbat_move 		=> r_move(1) & r_move(1) & r_move(1) & r_move(1) & r_move(1) & r_move(1) & r_move(0) & "00",
	tv_mode 			=> '0',
	scanlines 		=> kb_scanlines,
	hsync 			=> hsync, 
	vsync 			=> vsync,
	csync 			=> open,
	ball 				=> ball,
	left_bat 		=> left_bat,
	right_bat 		=> right_bat,
	field_and_score => field_and_score,
	sound 			=> sound);
	
-------------------------------------------------------------------------------
-- Global signals

areset <= not locked; -- global reset
reset <= areset or kb_reset; -- hot reset

-------------------------------------------------------------------------------
-- Disabled hw

SD_NCS	<= '1'; 
NCSO 		<= '1';
SRAM_NWR <= '1';
SRAM_NRD <= '1';
CPLD_CLK <= '0';
CPLD_CLK2 <='0';
SDIR <= '0';
SA <= "00";

-------------------------------------------------------------------------------
-- Audio mixer

audio_l <= "0000000000000000" when reset = '1' else ("000" & speaker & "000000000000");
audio_r <= "0000000000000000" when reset = '1' else ("000" & speaker & "000000000000");

-------------------------------------------------------------------------------
-- Game

process (clk_28)
begin 
	if rising_edge(clk_28) then 
		if pixtick = '1' then 
			pix_div <= "0000";
			dummyclk <= not dummyclk;
		else 
			pix_div <= pix_div + 1;
		end if;
	end if;
end process;

pixtick <= '1' when  pix_div="0100" else '0';
sel <= ball & left_bat & right_bat & field_and_score;

process (clk_28)
begin 
	if rising_edge(clk_28) then 
		if pixtick = '1' then 
			case sel is 
				when "1000" => rgb <= "111111111";
				when "0100" => rgb <= "000111111";
				when "0010" => rgb <= "111111000";
				when "0001" => rgb <= "000011000";
				when others => rgb <= "000000000";
			end case;
			VGA_HS <= hsync;
			VGA_VS <= vsync;
			speaker <= sound;
		end if;
	end if;
end process;

VGA_R <= rgb(8 downto 6);
VGA_G <= rgb(5 downto 3);
VGA_B <= rgb(2 downto 0);

process (clk_28, reset)
begin 
	if reset = '1' then 
		l_human <= '0';
		l_move <= (others => '0');
	elsif rising_edge(clk_28) then 
		if (kb_l_paddle(2)='1' or kb_l_paddle(1) = '1') then 
			l_human <= '1';
		end if;
		l_move <= (not(kb_l_paddle(2)) and kb_l_paddle(1)) & (kb_l_paddle(2) xor kb_l_paddle(1));
	end if;
end process;

process (clk_28, reset)
begin 
	if reset = '1' then 
		r_human <= '0';
		r_move <= (others => '0');
	elsif rising_edge(clk_28) then 
		if (kb_r_paddle(2)='1' or kb_r_paddle(1) = '1') then 
			r_human <= '1';
		end if;
		r_move <= (not(kb_r_paddle(2)) and kb_r_paddle(1)) & (kb_r_paddle(2) xor kb_r_paddle(1));
	end if;
end process;
	
end rtl;
