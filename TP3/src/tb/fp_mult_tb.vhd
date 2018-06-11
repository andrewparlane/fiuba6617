library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library common;
use common.all;
use common.type_pkg.all;

use work.fp_type_pkg.all;

entity fp_mult_tb is
    generic(TOTAL_BITS:                 natural := 32;
            EXPONENT_BITS:              natural := 8;
            TEST_FILE:                  string  := "test_files/multiplicacion/test_mul_float_32_8.txt";
            ROUNDING_MODE:              RoundingMode;
            DENORMALS:                  boolean;
            NO_ASSERT_ON_ZERO_NEG_ZERO: boolean := false);
end entity fp_mult_tb;

architecture sim of fp_mult_tb is
    component fp_mult is
        generic (TBITS:     natural;
                 EBITS:     natural;
                 DENORMALS: boolean);
        port (i_clk:    in  std_ulogic;
              i_a:      in  std_ulogic_vector((TBITS - 1) downto 0);
              i_b:      in  std_ulogic_vector((TBITS - 1) downto 0);
              i_rm:     in  RoundingMode;
              o_res:    out std_ulogic_vector((TBITS - 1) downto 0));
    end component fp_mult;

    component fp_mult_wrapper is
    end component fp_mult_wrapper;

    package fpPkg
            is new work.fp_helper_pkg
            generic map (TBITS => TOTAL_BITS,
                         EBITS => EXPONENT_BITS);

    signal A:           std_ulogic_vector((TOTAL_BITS - 1) downto 0);
    signal B:           std_ulogic_vector((TOTAL_BITS - 1) downto 0);
    signal C:           std_ulogic_vector((TOTAL_BITS - 1) downto 0);
    signal expectedC:   std_ulogic_vector((TOTAL_BITS - 1) downto 0);

    -- convert the args and result to fpUnpackeds
    -- for debugging
    signal fpA:         fpPkg.fpUnpacked;
    signal fpB:         fpPkg.fpUnpacked;
    signal fpC:         fpPkg.fpUnpacked;
    signal fpExpectedC: fpPkg.fpUnpacked;

    -- 50 MHz
    signal clk: std_ulogic := '0';
    constant CLK_HZ:        natural := 50 * 1000 * 1000;
    constant CLK_PERIOD:    time := 1 sec / CLK_HZ;
begin

    clk <= not clk after (CLK_PERIOD/2);

    dut: fp_mult    generic map (TBITS      => TOTAL_BITS,
                                 EBITS      => EXPONENT_BITS,
                                 DENORMALS  => DENORMALS)
                    port map (i_clk => clk,
                              i_a   => A,
                              i_b   => B,
                              i_rm  => ROUNDING_MODE,
                              o_res => C);

    mult_coverage:  fp_mult_wrapper;

    fpA         <= fpPkg.unpack(A);
    fpB         <= fpPkg.unpack(B);
    fpC         <= fpPkg.unpack(C);
    fpExpectedC <= fpPkg.unpack(expectedC);

    process
        file     f:     text;
        variable l:     line;
        variable u:     unsigned((TOTAL_BITS - 1) downto 0);
      begin

        report "Starting test with parameters:" &
               " TOTAL_BITS = " & integer'image(TOTAL_BITS) &
               " EXPONENT_BITS = " & integer'image(EXPONENT_BITS) &
               " TEST_FILE = " & TEST_FILE &
               " ROUNDING_MODE = " & RoundingMode'image(ROUNDING_MODE);

        file_open(f, TEST_FILE,  read_mode);

        while not endfile(f) loop
            readline(f, l);

            utils_pkg.read_unsigned_decimal_from_line(l, u);
            A <= std_ulogic_vector(u);

            utils_pkg.read_unsigned_decimal_from_line(l, u);
            B <= std_ulogic_vector(u);

            utils_pkg.read_unsigned_decimal_from_line(l, u);
            expectedC <= std_ulogic_vector(u);

            wait for CLK_PERIOD;

            assert (C = expectedC) or
                    (fpPkg.is_NaN(fpC) and
                     fpPkg.is_NaN(fpExpectedC)) or
                   (NO_ASSERT_ON_ZERO_NEG_ZERO and
                    (fpPkg.is_zero(fpC)) and
                    (fpPkg.is_zero(fpExpectedC)))
                report fpPkg.to_string(fpA) & " * " &
                       fpPkg.to_string(fpB) & " = " &
                       fpPkg.to_string(fpC) & " expecting " &
                       fpPkg.to_string(fpExpectedC)
                severity failure;
        end loop;

        file_close(f);

        std.env.stop;
    end process;
end architecture sim;
