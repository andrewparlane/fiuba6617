library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library common;
use common.all;

entity tp4 is
    port (CLOCK_50:     in      std_ulogic;
          KEY:          in      std_ulogic_vector(0 downto 0);
          SRAM_ADDR:    out     std_ulogic_vector(17 downto 0);
          SRAM_DQ:      inout   std_ulogic_vector(15 downto 0);
          SRAM_WE_N:    out     std_ulogic;
          SRAM_OE_N:    out     std_ulogic;
          SRAM_UB_N:    out     std_ulogic;
          SRAM_LB_N:    out     std_ulogic;
          SRAM_CE_N:    out     std_ulogic;
          VGA_R:        out     std_ulogic_vector(9 downto 0);
          VGA_G:        out     std_ulogic_vector(9 downto 0);
          VGA_B:        out     std_ulogic_vector(9 downto 0);
          VGA_CLK:      out     std_ulogic;
          VGA_BLANK:    out     std_ulogic;
          VGA_HS:       out     std_ulogic;
          VGA_VS:       out     std_ulogic;
          VGA_SYNC:     out     std_ulogic);
end entity tp4;

architecture synth of tp4 is
    component cordic_rotation_3d is
        generic (N: natural;
                 M: natural;
                 STEPS: natural);
        port (i_clk:    in  std_ulogic;
              i_reset:  in  std_ulogic;
              i_en:     in  std_ulogic;
              i_x:      in  signed((N + M - 1) downto 0);
              i_y:      in  signed((N + M - 1) downto 0);
              i_z:      in  signed((N + M - 1) downto 0);
              i_alpha:  in  unsigned((N + M - 1) downto 0);
              i_beta:   in  unsigned((N + M - 1) downto 0);
              i_gamma:  in  unsigned((N + M - 1) downto 0);
              o_x:      out signed((N + M - 1) downto 0);
              o_y:      out signed((N + M - 1) downto 0);
              o_z:      out signed((N + M - 1) downto 0);
              o_valid:  out std_ulogic);
    end component cordic_rotation_3d;

    -- writes take two cycles
    -- read data appears after 3 ticks
    --  1 to get it from the SRAM
    --  2 in the syncronizer
    component sram is
        port (i_clk:    in      std_ulogic; -- max clk 100MHz
              i_reset:  in      std_ulogic;
              -- inputs
              i_addr:   in      unsigned(17 downto 0);
              i_wdata:  in      std_ulogic_vector(15 downto 0);
              i_rnw:    in      std_ulogic;
              i_start:  in      std_ulogic;
              -- outputs
              o_rdata:  out     std_ulogic_vector(15 downto 0);
              -- status
              o_busy:   out     std_ulogic;
              -- bus ports
              io_data:  inout   std_ulogic_vector(15 downto 0);
              o_addr:   out     std_ulogic_vector(17 downto 0);
              o_nCE:    out     std_ulogic;
              o_nOE:    out     std_ulogic;
              o_nWE:    out     std_ulogic;
              o_nLB:    out     std_ulogic;
              o_nUB:    out     std_ulogic);
    end component sram;

    component delay is
        generic (DELAY: natural;
                 WIDTH: natural);
        port (clk:      in  std_ulogic;
              rst:      in  std_ulogic;
              input:    in  std_ulogic_vector((WIDTH - 1) downto 0);
              output:   out std_ulogic_vector((WIDTH - 1) downto 0));
    end component delay;

    component video_subsystem is
        port (i_clk100M:            in  std_ulogic;
              i_clk25M:             in  std_ulogic;
              i_reset:              in  std_ulogic;
              i_setPixelAddr:       in  unsigned(15 downto 0);
              i_setPixelBitMask:    in  unsigned(7 downto 0);
              i_setPixel:           in  std_ulogic;
              o_requestNewData:     out std_ulogic;
              o_vgaClk:             out std_ulogic;
              o_rOut:               out std_ulogic_vector(9 downto 0);
              o_gOut:               out std_ulogic_vector(9 downto 0);
              o_bOut:               out std_ulogic_vector(9 downto 0);
              o_nBlank:             out std_ulogic;
              o_nSync:              out std_ulogic;
              o_nHSync:             out std_ulogic;
              o_nVSync:             out std_ulogic);
    end component video_subsystem;

    component pll
        port (areset:   in  std_logic;
              inclk0:   in  std_logic;
              c0:       out std_logic;
              c1:       out std_logic;
              locked:   out std_logic);
    end component;

    type CoOrd is
    (
        CoOrd_X,
        CoOrd_Y,
        CoOrd_Z
    );

    constant NUM_COORDS:    natural := 5;

    signal clk25M:          std_ulogic;
    signal clk100M:         std_ulogic;
    signal pll_locked:      std_ulogic;

    signal idle:            std_ulogic;
    signal idleDelayed:     std_ulogic;
    signal currentCoOrd:    CoOrd;

    signal sram_address:    unsigned(17 downto 0);
    signal sram_rnw:        std_ulogic;
    signal sram_start:      std_ulogic;
    signal sram_rdata:      std_ulogic_vector(15 downto 0);
    signal sram_rdata_ext:  signed(31 downto 0);

    signal cordic_en:       std_ulogic;
    signal original_x:      signed(31 downto 0);
    signal original_y:      signed(31 downto 0);
    signal original_z:      signed(31 downto 0);
    signal rotated_x:       signed(31 downto 0);
    signal rotated_y:       signed(31 downto 0);
    signal rotated_z:       signed(31 downto 0);
    constant alpha:         unsigned(31 downto 0) := (others => '0');
    constant beta:          unsigned(31 downto 0) := (others => '0');
    constant gamma:         unsigned(31 downto 0) := (others => '0');
    signal cordic_valid:    std_ulogic;

    signal setPixelAddr:    unsigned(15 downto 0);
    signal setPixelBitMask: unsigned(7 downto 0);
    signal requestNewData:  std_ulogic;

    signal reset:           std_ulogic;

begin

    reset <= not (KEY(0) or pll_locked);

    -----------------------------------------------------------------
    -- PLLs
    -----------------------------------------------------------------
    pll_inst: pll port map (areset  => '0',
                            inclk0  => CLOCK_50,
                            c0      => clk100M,
                            c1      => clk25M,
                            locked  => pll_locked);

    -----------------------------------------------------------------
    -- SRAM
    -----------------------------------------------------------------

    sram_rnw <= '1';

    sramInst:
    sram port map (i_clk        => clk100M,
                   i_reset      => reset,
                   -- inputs
                   i_addr       => sram_address,
                   i_wdata      => std_ulogic_vector(to_unsigned(0, 16)),
                   i_rnw        => sram_rnw,
                   i_start      => sram_start,
                   -- outputs
                   o_rdata      => sram_rdata,
                   -- status
                   o_busy       => open,
                   -- bus ports
                   io_data      => SRAM_DQ,
                   o_addr       => SRAM_ADDR,
                   o_nCE        => SRAM_CE_N,
                   o_nOE        => SRAM_OE_N,
                   o_nWE        => SRAM_WE_N,
                   o_nLB        => SRAM_LB_N,
                   o_nUB        => SRAM_UB_N);

    -- we extend the read sram data from Q6.10 to Q9.23
    -- adding zeros to the lower bits and sign extending the
    -- upper bits
    sram_rdata_ext(12 downto 0) <= (others => '0');
    sram_rdata_ext(28 downto 13) <= signed(sram_rdata);
    sram_rdata_ext(31 downto 29) <= (others => sram_rdata(15));

    -- We need to know when we are reading sram. This is the
    -- idle signal. However our reads are delayed by 3 ticks
    -- so we must delay idle by 3 ticks too
    dly:    delay
            generic map (DELAY => 3,
                         WIDTH => 1)
            port map (clk => clk100M,
                      rst => reset,
                      input(0) => idle,
                      output(0) => idleDelayed);

    -- Control logic
    process (clk100M, reset)
    begin
        if (reset = '1') then
            idle <= '0';
            sram_start <= '0';
        elsif (rising_edge(clk100M)) then
            if (idle = '1') then
                -- wait for start signal
                if (requestNewData = '1') then
                    idle <= '0';
                    sram_address <= to_unsigned(0, 18);
                    sram_start <= '1';
                end if;
            else
                -- have we finished reading?
                if (sram_address = (to_unsigned(3 * NUM_COORDS, 18))) then
                    -- we are done
                    idle <= '1';
                    sram_start <= '0';
                end if;

                -- read the next address
                sram_address <= sram_address + to_unsigned(1, 18);
            end if;
        end if;
    end process;

    -----------------------------------------------------------------
    -- CORDIC 3D
    -----------------------------------------------------------------

    -- set up the input co-ordinates
    process (clk100M, reset)
    begin
        if (reset = '1') then
            currentCoOrd <= CoOrd_X;
            cordic_en <= '0';
        elsif (rising_edge(clk100M)) then
            -- deassert en (if it was set)
            cordic_en <= '0';

            if (idleDelayed) then
                currentCoOrd <= CoOrd_X;
            else
                -- sram_rdata should contain our data now
                -- we put it in the correct spot
                if (currentCoOrd = CoOrd_X) then
                    original_x <= sram_rdata_ext;
                    currentCoOrd <= CoOrd_Y;
                elsif (currentCoOrd = CoOrd_Y) then
                    original_y <= sram_rdata_ext;
                    currentCoOrd <= CoOrd_Z;
                elsif (currentCoOrd = CoOrd_Z) then
                    original_z <= sram_rdata_ext;
                    currentCoOrd <= CoOrd_X;

                    -- now all the data is valid start the cordic
                    cordic_en <= '1';
                end if;
            end if;
        end if;
    end process;

    cordic: cordic_rotation_3d
            generic map (N => 9,
                         M => 23,
                         STEPS => 10)
            port map (i_clk => clk100M,
                      i_reset => reset,
                      i_en => cordic_en,
                      i_x => original_x,
                      i_y => original_y,
                      i_z => original_z,
                      i_alpha => alpha,
                      i_beta  => beta,
                      i_gamma => gamma,
                      o_x => rotated_x,
                      o_y => rotated_y,
                      o_z => rotated_z,
                      o_valid => cordic_valid);

    -----------------------------------------------------------------
    -- Video subsystem
    -----------------------------------------------------------------
    -- Video RAM + ADV7123 controller
    -----------------------------------------------------------------

    process (all)
        variable intX:      integer;
        variable intY:      integer;
        variable pixelIdx:  unsigned(18 downto 0);
    begin
        -- rotated_x and rotated_y are between (approx)
        -- -225.0 and 225.0, so we first convert to be between
        -- (for x) 95 and 545
        -- (for y) 15 and 465
        intX := to_integer((rotated_x(31) &
                            rotated_x(31 downto 23)) + -- sign extend the integer part
                           to_signed(320, 10));
        intY := to_integer(rotated_y(31 downto 23) +
                           to_signed(240, 9));

        -- next we need to work out the index of the pixel
        pixelIdx := to_unsigned((intY * 640) + intX, 19);

        -- the pixel address is the top 16 bits of that
        setPixelAddr <= pixelIdx(18 downto 3);

        -- then the bit mask is the decoded lower 3 bits
        setPixelBitMask <= (others => '0');
        setPixelBitMask(to_integer(pixelIdx(2 downto 0))) <= '1';
    end process;

    dut: video_subsystem
        port map (i_clk100M             => clk100M,
                  i_clk25M              => clk25M,
                  i_reset               => reset,
                  i_setPixelAddr        => setPixelAddr,
                  i_setPixelBitMask     => setPixelBitMask,
                  i_setPixel            => cordic_valid,
                  o_requestNewData      => requestNewData,
                  o_vgaClk              => VGA_CLK,
                  o_rOut                => VGA_R,
                  o_gOut                => VGA_G,
                  o_bOut                => VGA_B,
                  o_nBlank              => VGA_BLANK,
                  o_nSync               => VGA_SYNC,
                  o_nHSync              => VGA_HS,
                  o_nVSync              => VGA_VS);

end architecture synth;
