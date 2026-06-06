#!/usr/bin/env python3

import math

MODE_OUT = 1
MODE_ASM = 2

def tohex(val, nbits):
    return format((val + (1 << nbits)) % (1 << nbits), '04X')

# Sanity-check window around ASCAL polyphase unity (= 256). Peak post-shift
# row sums for every shipped filter land between 256 (uniform-brightness)
# and ~308 (Scan_Br_120_80, the brightest scanline file). [240, 320] gives
# ~5% headroom on both sides; widen if a non-standard brighter filter is
# added in the future. See README "Polyphase unity — the critical math".
UNITY_ROW_SUM_MIN = 240
UNITY_ROW_SUM_MAX = 320

# Signed-10-bit range of ASCAL's poly_phase_t (signed(9 downto 0)).
POLY_COEFF_MIN = -512
POLY_COEFF_MAX =  511


def convert_file(mode, file_in, file_out, address, bits, skip_header_lines, skip_lines, shift_right, shift_left):
    # --- read input + parse coefficient rows (with header skip + decimation) ---
    with open(file_in, 'r') as input:
        all_lines = input.readlines()
    header_lines = all_lines[:skip_header_lines]
    body_lines   = all_lines[skip_header_lines:]

    raw_rows = []
    skip_counter = 0
    for line in body_lines:
        elements = line.split(',')
        if len(elements) != 4:
            continue
        if skip_counter % skip_lines == 0:
            raw_rows.append(tuple(int(x) for x in elements))
        skip_counter += 1

    # --- scale coefficients (shift_right then shift_left) ---
    scaled_rows = [
        tuple(math.floor(e / 2**shift_right) * 2**shift_left for e in row)
        for row in raw_rows
    ]

    # --- sanity checks (abort before writing if any fails) ---
    # 1) silent under-production: wrong skip_header_lines / skip_lines drops rows
    if len(scaled_rows) != 64:
        raise AssertionError(
            f"{file_out}: expected 64 coefficient rows after decimation, got "
            f"{len(scaled_rows)}. Check skip_header_lines={skip_header_lines} "
            f"and skip_lines={skip_lines} against the source phase count."
        )

    # 2) signed-10-bit overflow / sign-flip: shift_left too high
    flat = [v for row in scaled_rows for v in row]
    smin, smax = min(flat), max(flat)
    if smin < POLY_COEFF_MIN or smax > POLY_COEFF_MAX:
        raise AssertionError(
            f"{file_out}: scaled coefficient range [{smin}, {smax}] outside "
            f"ASCAL signed-10-bit [{POLY_COEFF_MIN}, {POLY_COEFF_MAX}]. "
            f"shift_left={shift_left} is too high — values would wrap to the "
            f"wrong sign on hardware. Lower shift_left so peak * 2^shift_left "
            f"stays inside {POLY_COEFF_MAX}."
        )

    # 3) ASCAL unity drift: shift_left wrong = picture too bright / too dim
    peak_row_sum = max(sum(row) for row in scaled_rows)
    if not (UNITY_ROW_SUM_MIN <= peak_row_sum <= UNITY_ROW_SUM_MAX):
        raise AssertionError(
            f"{file_out}: peak row sum {peak_row_sum} outside the unity window "
            f"[{UNITY_ROW_SUM_MIN}, {UNITY_ROW_SUM_MAX}] around ASCAL polyphase "
            f"unity (= 256). shift_left={shift_left} is wrong for this file — "
            f"a value of {peak_row_sum} means the picture will be "
            f"{peak_row_sum/256:.2f}x the intended brightness. For 64-phase "
            f"8-bit MiSTer files use shift_left=1; for 256-phase 10-bit files "
            f"(lanczos2_12 etc.) use shift_left=0."
        )

    # --- write output (only reached if all sanity checks passed) ---
    with open(file_out, 'w') as output:
        if mode == MODE_ASM:
            for h in header_lines:
                output.write('; ' + h)
            output.write((file_in[:len(file_in)-4]+'\n').upper())

        element_counter = 0
        for row in scaled_rows:
            if mode == MODE_OUT:
                for e in row:
                    output.write('0x' + tohex(address + element_counter, 16) + ' ')
                    output.write('0x' + tohex(e, bits) + '\n')
                    element_counter += 1
            else:
                output.write('.DW ')
                for i, e in enumerate(row):
                    output.write('0x' + tohex(e, bits))
                    if i != 3:
                        output.write(', ')
                    else:
                        output.write('\n')

convert_file(MODE_OUT, 'lanczos2_12.txt',     'lanczos2_12.out'    , 0x7000, 10, 6, 4, 0, 0)
convert_file(MODE_ASM, 'lanczos2_12.txt',     'lanczos2_12.asm'    , 0x7000, 10, 6, 4, 0, 0)
convert_file(MODE_OUT, 'Scanlines_80.txt',    'Scanlines_80.out'   , 0x7100, 10, 7, 1, 0, 1)
convert_file(MODE_ASM, 'Scanlines_80.txt',    'Scanlines_80.asm'   , 0x7100, 10, 7, 1, 0, 1)
convert_file(MODE_OUT, 'Scan_Br_105_80.txt',  'Scan_Br_105_80.out' , 0x7100, 10, 7, 1, 0, 1)
convert_file(MODE_ASM, 'Scan_Br_105_80.txt',  'Scan_Br_105_80.asm' , 0x7100, 10, 7, 1, 0, 1)
convert_file(MODE_OUT, 'Scan_Br_110_80.txt',  'Scan_Br_110_80.out' , 0x7100, 10, 7, 1, 0, 1)
convert_file(MODE_ASM, 'Scan_Br_110_80.txt',  'Scan_Br_110_80.asm' , 0x7100, 10, 7, 1, 0, 1)
convert_file(MODE_OUT, 'Scan_Br_115_80.txt',  'Scan_Br_115_80.out' , 0x7100, 10, 7, 1, 0, 1)
convert_file(MODE_ASM, 'Scan_Br_115_80.txt',  'Scan_Br_115_80.asm' , 0x7100, 10, 7, 1, 0, 1)
convert_file(MODE_OUT, 'Scan_Br_120_80.txt',  'Scan_Br_120_80.out' , 0x7100, 10, 7, 1, 0, 1)
convert_file(MODE_ASM, 'Scan_Br_120_80.txt',  'Scan_Br_120_80.asm' , 0x7100, 10, 7, 1, 0, 1)

# Added for C64MEGA65 V6 "HDMI: %s" filter submenu
# (M2M V2.1: additive only; existing entries above are unchanged.)
# Dual-use blobs (loaded into both H and V slots by the core):
# SharpBilinear_080 uses shift_left=1 — its peak source coefficient is 128, which
# at shift_left=2 would scale to 512 and silently wrap to signed -512 in
# ASCAL's signed(9 downto 0) RAM (10-bit max is +511). At shift_left=1 it scales
# to 256 = +256 signed, same dynamic range as the Scan_Br_*_80 family.
convert_file(MODE_OUT, 'SharpBilinear_080.txt',  'SharpBilinear_080.out' , 0x7000, 10,  7, 1, 0, 1)
convert_file(MODE_ASM, 'SharpBilinear_080.txt',  'SharpBilinear_080.asm' , 0x7000, 10,  7, 1, 0, 1)
convert_file(MODE_OUT, 'GS_Sharpness_050.txt',   'GS_Sharpness_050.out'  , 0x7000, 10, 11, 1, 0, 1)
convert_file(MODE_ASM, 'GS_Sharpness_050.txt',   'GS_Sharpness_050.asm'  , 0x7000, 10, 11, 1, 0, 1)
# CRT Composite simulation — H to slot 0x7000, V to slot 0x7100:
convert_file(MODE_OUT, 'CRT_Sim_Composite_H.txt','CRT_Sim_Composite_H.out', 0x7000, 10,  7, 1, 0, 1)
convert_file(MODE_ASM, 'CRT_Sim_Composite_H.txt','CRT_Sim_Composite_H.asm', 0x7000, 10,  7, 1, 0, 1)
convert_file(MODE_OUT, 'CRT_Sim_Composite_V.txt','CRT_Sim_Composite_V.out', 0x7100, 10,  7, 1, 0, 1)
convert_file(MODE_ASM, 'CRT_Sim_Composite_V.txt','CRT_Sim_Composite_V.asm', 0x7100, 10,  7, 1, 0, 1)
# CRT S-Video simulation — H to 0x7000, V to 0x7100:
convert_file(MODE_OUT, 'CRT_Sim_SVideo_H.txt',   'CRT_Sim_SVideo_H.out'   , 0x7000, 10,  7, 1, 0, 1)
convert_file(MODE_ASM, 'CRT_Sim_SVideo_H.txt',   'CRT_Sim_SVideo_H.asm'   , 0x7000, 10,  7, 1, 0, 1)
convert_file(MODE_OUT, 'CRT_Sim_SVideo_V.txt',   'CRT_Sim_SVideo_V.out'   , 0x7100, 10,  7, 1, 0, 1)
convert_file(MODE_ASM, 'CRT_Sim_SVideo_V.txt',   'CRT_Sim_SVideo_V.asm'   , 0x7100, 10,  7, 1, 0, 1)
