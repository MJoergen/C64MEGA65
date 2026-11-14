#!/bin/bash
# reg_setup.sh <git repository to clone from> <commit> <regression directory>
# Clones the repository at <commit> into <dir>/src (detached), analyzes the physical_1581 tree, the
# test packages, the mechanism model and the benches into <dir>/b/lib and elaborates the benches
# into <dir>/b. Prints REG_SETUP_OK at the end.
set -u
FROM=${1:?repo}; REV=${2:?commit}; D=${3:?dir}
mkdir -p "$D" && cd "$D" || exit 1
[ -d src ] || git clone -q --no-checkout "$FROM" src || exit 1
git -C src checkout -q --detach "$REV" || exit 1
echo "source tree: $(git -C src log --oneline -1)"
P=$D/src/CORE/vhdl/physical_1581; T=$D/src/CORE/vhdl/test; C=$T/tb_physical_1581_controller
rm -rf b && mkdir -p b/lib b/logs && cd b || exit 1
ghdl -a --std=08 --workdir=lib \
  $P/physical_1581_pkg.vhd $P/physical_1581_crc.vhd \
  $P/physical_1581_mfm_gaps.vhd $P/physical_1581_mfm_quantise.vhd \
  $P/physical_1581_mfm_gaps_to_bits.vhd $P/physical_1581_mfm_bits_to_bytes.vhd \
  $P/physical_1581_mfm_decoder.vhd $P/physical_1581_inputs.vhd \
  $P/physical_1581_rdfifo.vhd $P/physical_1581_wfifo.vhd \
  $P/physical_1581_mfm_encoder.vhd $P/physical_1581_writer.vhd \
  $P/physical_1581_rdahead.vhd $P/physical_1581_controller.vhd $P/physical_1581_diag.vhd \
  $T/tb_physical_1581_codec/mfm_flux_gen_pkg.vhd $C/golden_1581_pkg.vhd $C/mech_model_1581.vhd \
  $C/tb_mech_model_1581.vhd $C/tb_physical_1581_controller.vhd $C/tb_physical_1581_media_contract.vhd \
  $C/tb_physical_1581_ovf.vhd $C/tb_physical_1581_rdahead.vhd $C/tb_physical_1581_rdseq.vhd \
  $C/tb_physical_1581_rdahead_loop.vhd $T/tb_physical_1581_diag/tb_physical_1581_diag.vhd \
  || { echo "ANALYZE FAILED"; exit 1; }
for tb in tb_mech_model_1581 tb_physical_1581_controller tb_physical_1581_media_contract tb_physical_1581_ovf \
          tb_physical_1581_rdahead tb_physical_1581_rdseq tb_physical_1581_rdahead_loop tb_physical_1581_diag; do
  ghdl -e --std=08 --workdir=lib $tb || { echo "ELABORATE FAILED: $tb"; exit 1; }
done
echo REG_SETUP_OK
