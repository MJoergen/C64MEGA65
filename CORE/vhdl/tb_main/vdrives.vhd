library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

package vdrives_pkg is

  type     vd_vec_array is array(natural range <>) of std_logic_vector;

  type     vd_std_array is array(natural range <>) of std_logic;

  type     vd_unsigned_array is array(natural range <>) of unsigned;

  constant AW : natural := 13; -- 14-bit
  constant DW : natural := 7;  -- 8-bit

end package vdrives_pkg;

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.vdrives_pkg.all;

entity vdrives is
  generic (
    VDNUM : natural := 1; -- amount of virtual drives, MiSTer supports a maximum of 10
    BLKSZ : natural := 2  -- block size for LBA adressing: 0..7: 0 = 128, 1 = 256, 2 = 512(default), .. 7 = 16384
  );
  port (
    clk_qnice_i      : in    std_logic;
    clk_core_i       : in    std_logic;
    reset_core_i     : in    std_logic;

    ---------------------------------------------------------------------------------------
    -- Core clock domain
    ---------------------------------------------------------------------------------------

    -- MiSTer's "SD config" interface:
    -- While the appropriate bit in img_mounted_o is strobed, the other values are latched by MiSTer
    img_mounted_o    : out   std_logic_vector(VDNUM - 1 downto 0);         -- signaling that new image has been mounted
    img_readonly_o   : out   std_logic;                                    -- mounted as read only; valid only for active bit in img_mounted
    img_size_o       : out   std_logic_vector(31 downto 0);                -- size of image in bytes; valid only for active bit in img_mounted
    img_type_o       : out   std_logic_vector(1 downto 0);

    -- While "img_mounted_o" needs to be strobed, "drive_mounted" latches the strobe,
    -- so that it can be used for resetting (and unresetting) the drive.
    drive_mounted_o  : out   std_logic_vector(VDNUM - 1 downto 0);

    -- Cache output signals: The dirty flags can be used to enforce data consistency
    -- (for example by ignoring/delaying a reset or delaying a drive unmount/mount, etc.)
    -- The flushing flags can be used to signal the fact that the caches are currently
    -- flushing to the user, for example using a special color/signal for example
    -- at the drive led
    cache_dirty_o    : out   std_logic_vector(VDNUM - 1 downto 0);
    cache_flushing_o : out   std_logic_vector(VDNUM - 1 downto 0);

    ---------------------------------------------------------------------------------------
    -- QNICE clock domain
    ---------------------------------------------------------------------------------------

    -- MiSTer's "SD block level access" interface, which runs in QNICE's clock domain using a dedicated signal
    -- on Mister's side such as "clk_sys" (<== oddly deep down in MiSTer code "clk_sys" is not the core, but the "sd write", i.e. QNICE)
    sd_lba_i         : in    vd_vec_array(VDNUM - 1 downto 0)(31 downto 0);
    sd_blk_cnt_i     : in    vd_vec_array(VDNUM - 1 downto 0)(5 downto 0); -- number of blocks-1, total size ((sd_blk_cnt+1)*(1<<(BLKSZ+7))) must be <= 16384!
    sd_rd_i          : in    vd_std_array(VDNUM - 1 downto 0);
    sd_wr_i          : in    vd_std_array(VDNUM - 1 downto 0);
    sd_ack_o         : out   vd_std_array(VDNUM - 1 downto 0);

    -- MiSTer's "SD byte level access": the MiSTer components use a combination of the drive-specific sd_ack and the sd_buff_wr
    -- to determine, which RAM buffer actually needs to be written to (using the clk_qnice_i clock domain)
    sd_buff_addr_o   : out   std_logic_vector(AW downto 0);
    sd_buff_dout_o   : out   std_logic_vector(DW downto 0);
    sd_buff_din_i    : in    vd_vec_array(VDNUM - 1 downto 0)(DW downto 0);
    sd_buff_wr_o     : out   std_logic;

    -- QNICE interface (MMIO, 4k-segmented)
    -- qnice_addr is 28-bit because we have a 16-bit window selector and a 4k window: 65536*4096 = 268.435.456 = 2^28
    qnice_addr_i     : in    std_logic_vector(27 downto 0);
    qnice_data_i     : in    std_logic_vector(15 downto 0);
    qnice_data_o     : out   std_logic_vector(15 downto 0);
    qnice_ce_i       : in    std_logic;
    qnice_we_i       : in    std_logic
  );
end entity vdrives;

architecture simulation of vdrives is

begin

end architecture simulation;

