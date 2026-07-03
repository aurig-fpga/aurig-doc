library ieee;
use ieee.std_logic_1164.all;

entity top_unit is
    port (
        clk : in std_logic
    );
end entity top_unit;

architecture rtl of top_unit is
begin
    u_leaf : entity work.leaf_x
        port map (clk => clk);
end architecture rtl;
