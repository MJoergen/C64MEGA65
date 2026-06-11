set cur_dir [exec pwd]
# ../../CORE/CORE-R3.runs/synth_1/

cd ../../../CORE/m2m-rom/
exec ./make_rom.sh <@stdin >@stdout 2>@stderr
cd $cur_dir

# ============================================================================
# Cosmetic log hygiene: scoped suppression of analyzed-benign warnings.
# set_msg_config only configures Vivado's message reporting (UG835); it has
# no input to elaboration, synthesis, or netlist generation -- the bitstream
# is bit-identical with or without these rules. Every rule below is scoped
# with -string so the same message IDs stay LIVE for project code paths.
# Each block is independent: delete any block to re-enable its messages.
# Audit trail: warning analysis of 2026-06-11 (R3 synth log, 550 warnings),
# see doc/improvement_ideas.md.
# ============================================================================

# [Synth 8-7129] unconnected ports INSIDE Xilinx's own XPM FIFO macro
# (xpm_memory_base within xpm_fifo_axis, used via M2M/vhdl/memory/axi_fifo.vhd):
# the macro intentionally ties off unused features (port-B write data, ECC
# injection, sleep, port-A read pipeline). -string keeps 8-7129 VISIBLE for
# any project entity with a genuinely forgotten connection.
set_msg_config -id {Synth 8-7129} -string {{xpm_memory_base}} -suppress

# Upstream-MiSTer coding-style lint in the unmodified core drop -- all legal
# SV/VHDL idioms, verified benign 2026-06-11: 8-6901/8-8895 use-before-declare
# (declarations exist later, widths match), 8-10180 missing static/automatic
# keyword (static is the intended and applied semantics), 8-9661 defaultless
# parameters (all instantiations override; elaboration would error otherwise),
# 8-9400 stray ';' after endcase (mos6526.v), 8-4747 shared-variable BRAM
# idiom (dprom/spram, Vivado-supported). Scoped to the submodule path so the
# IDs stay live for CORE/vhdl and M2M/vhdl. Delete any line to re-enable that
# ID; comment the whole block out for an upstream-merge audit build.
foreach id {{Synth 8-6901} {Synth 8-10180} {Synth 8-8895} {Synth 8-9661} {Synth 8-9400} {Synth 8-4747}} {
    set_msg_config -id $id -string {{C64_MiSTerMEGA65}} -suppress
}

# [Synth 8-6014] benign 'unused sequential element removed' from the M2M
# av_pipeline whole-record pipeline idiom (vga_osm.vhd, video_overlay.vhd,
# audio_out.v): stages copy entire records each clock and synthesis trims
# the unread fields by design. Scoped by path substring so 8-6014 stays
# visible for CORE/vhdl, the MiSTer core, and the rest of M2M.
set_msg_config -id {Synth 8-6014} -string {av_pipeline} -suppress

# [Constraints 18-4570] the 11 HyperRAM OE/CS/RESET registers carry IOB=TRUE
# (M2M/common.xdc) and also sit inside pblock_hr (MEGA65-R3/R6.xdc).
# 'IOB takes priority' is exactly the designer's intent (deterministic
# clock-to-out; see hyperram_tx.vhd). Scoped so any future, unrelated
# IOB/pblock conflict still warns.
set_msg_config -id {Constraints 18-4570} -string {i_hyperram} -suppress

# [Designutils 20-1567] set_multicycle_path -hold (common.xdc, QNICE EAE
# multicycle pair per UG903) is by design not consumed by synthesis, which
# performs no hold fixing; implementation reads common.xdc directly and
# applies it (verified: zero instances of this ID in the impl log).
set_msg_config -id {Designutils 20-1567} -string {common.xdc} -suppress
