-------------------------------------------------------------------------------
-- Architecture "hostile" of hdmi_genlock for tb_hdmi_raw_wiring (issue #184)
--
-- run.sh puts it behind the entity declaration of the real
-- M2M/vhdl/av_pipeline/hdmi_genlock.vhd. Its line length is wrong in every clock
-- cycle, also with enable_i = '0': in a mode that is not a raw mode the scaler
-- must not see it (the multiplexer in front of the scaler's htotal port of
-- digital_pipeline.vhd), in a raw mode it must.
-------------------------------------------------------------------------------

architecture hostile of hdmi_genlock is
begin
   htotal_o  <= htotal_i + 7;
   locked_o  <= '1';
   stretch_o <= 7;
end architecture hostile;
