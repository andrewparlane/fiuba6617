library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.fp_type_pkg.all;

entity fp_mult is
    generic (TBITS:     natural;
             EBITS:     natural;
             DENORMALS: boolean);
    port (i_clk:    in  std_ulogic;
          i_a:      in  std_ulogic_vector((TBITS - 1) downto 0);
          i_b:      in  std_ulogic_vector((TBITS - 1) downto 0);
          i_rm:     in  RoundingMode;
          o_res:    out std_ulogic_vector((TBITS - 1) downto 0));
end entity fp_mult;

architecture synth of fp_mult is
    component fp_round is
        generic (TBITS:     natural;
                 EBITS:     natural;
                 SBITS:     natural;
                 DENORMALS: boolean);
        port (i_clk:    in  std_ulogic;
              i_sig:    in  unsigned((SBITS - 1) downto 0);
              i_bExp:   in  signed((EBITS + 1) downto 0);
              i_sign:   in  std_ulogic;
              i_r:      in  std_ulogic;
              i_s:      in  std_ulogic;
              i_rm:     in  RoundingMode;
              o_sig:    out unsigned((SBITS - 1) downto 0);
              o_bExp:   out unsigned((EBITS - 1) downto 0);
              o_type:   out fpNumType);
    end component fp_round;

    package fpPkg
            is new work.fp_helper_pkg
            generic map (TBITS => TBITS,
                         EBITS => EBITS);

    constant SBITS:     natural := fpPkg.SBITS;
    -- number of bits in the product
    constant PBITS:     natural := SBITS * 2;

    signal fpA: fpPkg.fpUnpacked;
    signal fpB: fpPkg.fpUnpacked;
    signal fpC: fpPkg.fpUnpacked;

    -- EBITS + 2 so we have the carry out bits to detect
    -- overflow and underflow
    -- first we just sum them. Then we try and normalize
    -- the product which requires adjusting the exponent
    -- then we round which may require one final adjustment
    signal sumOfBExps:      signed((EBITS + 1) downto 0);
    signal adjustedBExp:    signed((EBITS + 1) downto 0);
    signal finalBExp:       unsigned((EBITS - 1) downto 0);

    -- The product of the two significands
    signal product:         unsigned((PBITS - 1) downto 0);

    -- The new significand is the product. We try and normalize
    -- it. Then we may have to round it.
    signal normalizedSig:   unsigned((SBITS - 1) downto 0);
    signal finalSig:        unsigned((SBITS - 1) downto 0);

    -- rounding bits
    -- r - is the MSb after the significand
    -- s - is the reduction-or of all subsequent bits
    signal r:               std_ulogic;
    signal s:               std_ulogic;

    -- the new sign depends on the signs of the arguments
    signal newSign:         std_ulogic;

    -- The fp_round component tells us if the type of the result.
    signal resultType:      fpNumType;
begin

    -----------------------------------------------------------------
    -- Type conversions
    -----------------------------------------------------------------

    -- Convert A and B to fpUnpackeds
    fpA <= fpPkg.unpack(i_a);
    fpB <= fpPkg.unpack(i_b);

    -- Convert the result to a vector
    o_res <= fpPkg.pack(fpC);

    -----------------------------------------------------------------
    -- Add the exponents
    -----------------------------------------------------------------
    sumOfBExps <= ("00" & signed(fpA.bExp)) +
                  ("00" & signed(fpB.bExp)) -
                  to_signed(fpPkg.BIAS, EBITS + 2);

    -----------------------------------------------------------------
    -- Multiply the significands
    -----------------------------------------------------------------

    -- The significand has 1 bit of integer + SBITS-1
    -- of fractional. Therefore the product gives us 2 bits of
    -- integer + (SBITS-1)*2 bits of fractional
    product <= unsigned(fpA.sig) * unsigned(fpB.sig);

    process (all)
        variable productExt:    unsigned((PBITS + SBITS) downto 0);
        variable bitsToShift:   integer;
        variable maxShift:      integer;
        variable lsb:           integer;
    begin
        if ((to_integer(sumOfBExps) < fpPkg.EMIN) and
            DENORMALS) then

            -- Our current exponent is less than EMIN,
            -- which means we have to shift the result right
            -- to get it back to EMIN (gradual underflow).
            -- If we shift out all the bits of the product
            -- then we end up with an actual underflow
            -- and the result is 0.
            bitsToShift := fpPkg.EMIN - to_integer(sumOfBExps);

            if (bitsToShift > SBITS) then
                -- if we shift by more than SBITS
                -- then the significand is 0
                -- s is the reduction-or of the product.
                -- r is the last bit shifted out, which is
                -- either the MSb of the product, or 0
                normalizedSig <= to_unsigned(0, SBITS);
                r <= product(PBITS-1)
                     when (bitsToShift = (SBITS+1))
                     else '0';
                s <= '1' when (product /= to_unsigned(0, PBITS))
                     else '0';
            else
                -- The significand is the product, right shifted
                -- by bitsToShift. Since the decimal point is:
                -- xx.xxxxx then we want to add bitsToShift-1
                -- 0s and then the rest of the bits are from
                -- the product.
                -- bitsFromProduct := SBITS - (bitsToShift-1)
                -- so the range is PBITS-1 downto lsb, where:
                -- lsb := (PBITS-1) - (SBITS - (bitsToShift-1)) + 1
                lsb := PBITS + bitsToShift - SBITS - 1;
                normalizedSig <= to_unsigned(0, bitsToShift-1) &
                                 product((PBITS-1) downto lsb);

                -- r is the next bit
                r <= product(lsb - 1);

                -- s is the reduction or of all lower bits
                s <= '0' when (product((lsb - 2) downto 0) =
                               to_unsigned(0, lsb - 1))
                     else '1';
            end if;

            -- set the exponent to EMIN. This gets changed to
            -- a 0 when we get packed into the vector
            adjustedBExp <= to_signed(fpPkg.EMIN, EBITS + 2);

        else
            -- either we don't support denormals,
            -- or we didn't have [gradual] underflow

            if (product(PBITS - 1) = '1') then
                -- The MSb is 1 so we have:
                -- 1x.xxxx but we require the significand to be
                -- 1.xxx so we need to shift right by 1
                normalizedSig <= product((PBITS - 1) downto SBITS);

                -- we shifted right, so add 1 to the exponent
                adjustedBExp <= sumOfBExps + to_signed(1, EBITS+2);

                -- r is the next bit
                r <= product(SBITS - 1);

                -- and s is the reduction or of all lower bits
                s <= '0' when (product((SBITS - 2) downto 0) =
                               to_unsigned(0, SBITS - 1))
                     else '1';
            else

                -- we have 0x.xxxx, and want 1.xxxx
                -- so we need to shift left by some amount

                if (not DENORMALS) then
                    -- we don't support denormals,
                    -- which means 1.xxx * 1.xxx > 1.0
                    -- (unless one of the args is 0).
                    -- And because we are 0x.xxxx, we know
                    -- tha we are actually: 01.xxxx.
                    -- drop the leading 0 and we are good
                    normalizedSig <= product((PBITS - 2) downto (SBITS-1));
                    -- r is the next bit
                    r <= product(SBITS - 2);
                    -- and s is the reduction or of all lower bits
                    s <= '0' when (product((SBITS - 3) downto 0) =
                                   to_unsigned(0, SBITS - 2))
                         else '1';

                    -- no need to adjust the exponent
                    adjustedBExp <= sumOfBExps;
                else
                    -- we support denormals, so we need to shift
                    -- left until normalized (ie. msb is 1)
                    -- or we would underflow (adjust = EMIN)
                    maxShift := to_integer(sumOfBExps) - fpPkg.EMIN;

                    -- if all the bits are 0, then we have
                    -- underflowed and are 0. Note we ignore
                    -- the msb, because we know it's not a 1
                    bitsToShift := -1;
                    for i in 0 to (PBITS - 2) loop
                        if ((product(PBITS - i - 2) = '1') or
                            (i >= maxShift)) then
                            bitsToShift := i;
                            exit;
                        end if;
                    end loop;

                    if (bitsToShift = -1) then
                        -- all bits are 0, result is 0
                        normalizedSig <= to_unsigned(0, SBITS);

                        -- biased exponent is 0
                        adjustedBExp <= to_signed(0, EBITS + 2);

                        -- r is 0, s is 0
                        r <= '0';
                        s <= '0';
                    else
                        -- bitsToShift max = PBITS - 2
                        -- shifting the product by that would
                        -- leave 2 bits of the product.
                        -- We need SBITS + 3 (ignored msb, r and s),
                        -- so if we append (SBITS+1) bits
                        -- of 0s to the product we don't need
                        -- to worry about ranges.
                        productExt := product((PBITS-1) downto 0) &
                                      to_unsigned(0, SBITS+1);

                        -- the msb of the productExt is PBITS + SBITS
                        -- we shift left by bitsToShift, so we want
                        -- PBITS + SBITS - bitsToShift - 1 downto lsb
                        -- where lsb := PBITS + SBITS - bitsToShift - 1 - (SBITS-1)
                        lsb := PBITS - bitsToShift;
                        normalizedSig <= productExt((PBITS + SBITS - bitsToShift - 1)
                                                     downto lsb);
                        -- r is the next bit
                        r <= productExt(lsb - 1);
                        -- s is the reduction-or of the rest of the bits
                        s <= '0' when (productExt((lsb - 2) downto 0) =
                                       to_unsigned(0, lsb - 1))
                             else '1';

                        -- adjust the exponent.
                        -- we shifted left by bitsToShift bits
                        -- so we need to decrement the exponent by
                        -- bitsToShift
                        adjustedBExp <= sumOfBExps -
                                        to_signed(bitsToShift,
                                                  EBITS + 2);
                    end if;
                end if;
            end if;
        end if;
    end process;

    -----------------------------------------------------------------
    -- Sign:
    -----------------------------------------------------------------
    -- The new sign is the XOR of the signs of the arguments
    newSign <= fpA.sign xor fpB.sign;

    -----------------------------------------------------------------
    -- rounding:
    -----------------------------------------------------------------
    fpRound: fp_round generic map (TBITS     => TBITS,
                                   EBITS     => EBITS,
                                   SBITS     => SBITS,
                                   DENORMALS => DENORMALS)
                      port map (i_clk   => i_clk,
                                i_sig   => normalizedSig,
                                i_bExp  => adjustedBExp,
                                i_sign  => newSign,
                                i_r     => r,
                                i_s     => s,
                                i_rm    => i_rm,
                                o_sig   => finalSig,
                                o_bExp  => finalBExp,
                                o_type  => resultType);

    -----------------------------------------------------------------
    -- Pick the correct result:
    -----------------------------------------------------------------

    process (all)
    begin
        -- If either of the arguments is NaN
        -- or they are 0 * infinity then
        -- the output should be NaN
        if (fpPkg.is_NaN(fpA) or
            fpPkg.is_NaN(fpB) or
            (fpPkg.is_zero(fpA) and fpPkg.is_infinity(fpB)) or
            (fpPkg.is_zero(fpB) and fpPkg.is_infinity(fpA))) then
            fpC <= fpPkg.set_NaN(newSign);

        -- If either of the inputs is infinity then the
        -- result is infinity.
        elsif (fpPkg.is_infinity(fpA) or
               fpPkg.is_infinity(fpB)) then
            fpC <= fpPkg.set_infinity(newSign);

        -- If either of the arguments is 0
        -- then the result is zero.
        elsif (fpPkg.is_zero(fpA) or
               fpPkg.is_zero(fpB)) then
            fpC <= fpPkg.set_zero(newSign);

        -- Finally in all others cases the result is
        -- the calculated one
        else
            fpC.sign    <= newSign;
            fpC.bExp    <= finalBExp;
            fpC.sig     <= finalSig;
            fpC.numType <= resultType;
        end if;
    end process;

end architecture synth;
