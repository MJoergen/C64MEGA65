#!/usr/bin/env bash

##############################################################################
# MiSTer2MEGA65 (M2M) QNICE ROM
#
# asm_strrom.sh: Assemble a QNICE firmware and move its string ROM strings
# into the string ROM
#
# Usage: asm_strrom.sh <firmware.asm> <strings> <address width>
#
#   <firmware.asm>   Source of the firmware. The outputs are written next to
#                    it, like the "asm" wrapper of QNICE does:
#                    <firmware>.out, <firmware>.lis, <firmware>.def and
#                    <firmware>.rom
#   <strings>        Name of the string ROM outputs without extension:
#                    <strings>.rom is the content of the string ROM, one
#                    character per line as two hexadecimal digits;
#                    <strings>.lis and <strings>.out are the listing and the
#                    words of the strings as they are written in the sources,
#                    i.e. before they are placed in the string ROM
#   <address width>  The string ROM holds 2 ** <address width> characters and
#                    <strings>.rom always has exactly this amount of lines
#
# Call it from the directory of <firmware.asm>. Exit code 0 means success. In
# case of an error the exit code is 1 and neither <firmware>.rom nor
# <strings>.rom exist.
#
# The concept of the string ROM is described in M2M/rom/strrom.asm: The
# firmware ROM ends at 0x7000 and a string costs one word per character. The
# strings between the marker comments ";STRROM_BEGIN" and ";STRROM_END" are
# therefore not assembled into the firmware ROM. They go into a block RAM that
# QNICE reads as the device M2M$STRROM (see C_DEV_STRROM in
# M2M/vhdl/qnice_wrapper.vhd), and the firmware keeps one word per label: the
# position of the string in the string ROM. These words are inserted behind
# the marker comment ";STRROM_TABLE" in M2M/rom/strrom.asm.
#
# Steps:
#
# 1. Run the C preprocessor over the firmware source, exactly like the "asm"
#    wrapper of QNICE does. All following steps work on its output, so that
#    #include and #ifdef are already resolved.
# 2. Copy the lines between the markers into a source file of their own and
#    assemble it at address 0. Using the assembler for this guarantees that
#    the characters, including the escape sequences, are encoded like in any
#    other string.
# 3. Place the strings in the string ROM. A string is read through the 4k
#    window of QNICE, so it must not cross a 4k boundary: a string that would
#    do so is moved to the start of the next 4k block. "String" means
#    everything up to and including a zero terminator, because an .ASCII_P
#    line continues in the next line.
# 4. Write <strings>.rom and the table lines, remove the lines between the
#    markers from the preprocessed source, insert the table lines and assemble
#    the result.
#
# The string ROM is only used when the ";STRROM_TABLE" marker is part of the
# preprocessed source. M2M/rom/strrom.asm contains it in release builds only.
# If the firmware is built to run in RAM (RELEASE is not defined), the strings
# are assembled where they stand, because the QNICE Monitor in ROM is then the
# one of QNICE, which only handles ordinary strings. <strings>.rom is always
# written, because the block RAM is always part of the design.
#
# Two limits of the QNICE assembler are checked for the lines between the
# markers, because the assembler itself does not report them: it stores an
# undefined word for a backslash that is followed by a backslash or by a
# double quote, and it does not handle long source lines. Such lines are
# rejected with an error message.
#
# Portability of the awk scripts: POSIX awk only. No strtonum() and no 0x
# literals, because both are gawk extensions and POSIX awk silently evaluates
# 0x7000 as 0. No /dev/stderr either, so errors are printed on stdout. CRLF
# line endings are tolerated. All tools run in the C locale, so that the
# sources are processed byte by byte, whatever their character encoding is.
#
# done by sy2002 in 2026 and licensed under GPL v3
##############################################################################

if [ $# -ne 3 ]; then
    echo "MiSTer2MEGA65 - Assemble a QNICE firmware that uses the string ROM."
    echo "Usage: asm_strrom.sh <firmware.asm> <strings> <address width>"
    exit 1
fi

export LC_ALL=C

FW_ASM=$1
FW=${FW_ASM%.asm}
STR=$2
STRROM_AW=$3
STRROM_WIN=4096                     # size of the MMIO window of QNICE
STRROM_MAXLINE=200                  # longest line between the markers

QNICE_ASM_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null 2>&1 && pwd )/../QNICE/assembler"

FW_PRE=__${FW}-pre__.asm            # firmware source after the C preprocessor
FW_SRC=__${FW}__.asm                # the source that is assembled
STR_SRC=__${STR}__.asm              # the strings between the markers
STR_TAB=__${STR}-tab__.asm          # one table line per string ROM string

fw_cleanup() {
    rm -f "$FW_PRE" "$FW_SRC" "$STR_SRC" "$STR_TAB"
}

# Never leave results of an earlier run behind: a failed run must not look
# like a successful one.
fw_fail() {
    echo "ERROR: $1"
    fw_cleanup
    rm -f "$FW.out" "$FW.rom" "$STR.rom"
    exit 1
}

fw_cleanup
rm -f "$FW.out" "$FW.rom" "$FW.lis" "$FW.def"
rm -f "$STR.out" "$STR.rom" "$STR.lis" "$STR.def"

# An interrupted run leaves no temporary files and no half of the outputs
trap 'fw_cleanup' EXIT
trap 'fw_fail "interrupted."' HUP INT TERM

if [ ! -f "$FW_ASM" ] || [ "$FW" = "$FW_ASM" ]; then
    fw_fail "$FW_ASM is not an existing .asm file in the current directory."
fi

# The temporary files are named after the arguments, and the assembler writes
# <strings>.out next to <firmware>.out: both need to be plain, different names
case "$FW_ASM/$STR" in
    */*/*) fw_fail "<firmware.asm> and <strings> need to be file names without a directory." ;;
esac
if [ "$STR" = "$FW" ]; then
    fw_fail "<strings> needs to differ from the name of the firmware ($FW)."
fi

if [ ! -x "$QNICE_ASM_DIR/qasm" ] || [ ! -x "$QNICE_ASM_DIR/qasm2rom" ]; then
    fw_fail "the QNICE assembler is missing in $QNICE_ASM_DIR; build the QNICE toolchain first."
fi

case "$STRROM_AW" in
    ''|*[!0-9]*) fw_fail "the address width \"$STRROM_AW\" is not a number." ;;
esac
STRROM_AW=$(( 10#$STRROM_AW ))      # decimal, also with leading zeros
if [ "$STRROM_AW" -lt 12 ] || [ "$STRROM_AW" -gt 16 ]; then
    fw_fail "the address width is $STRROM_AW, but needs to be between 12 and 16."
fi
STRROM_SIZE=$(( 1 << STRROM_AW ))

# ----------------------------------------------------------------------------
# Step 1: C preprocessor
# ----------------------------------------------------------------------------

if command -v cc > /dev/null 2>&1; then
    FW_CPP=cc
elif command -v gcc > /dev/null 2>&1; then
    FW_CPP=gcc
else
    fw_fail "neither cc nor gcc has been found; the C preprocessor is needed to assemble $FW_ASM."
fi

"$FW_CPP" -xc -E "$FW_ASM" | sed '/^#.*/d' > "$FW_PRE"
FW_PIPE=("${PIPESTATUS[@]}")
if [ "${FW_PIPE[0]}" -ne 0 ] || [ "${FW_PIPE[1]}" -ne 0 ] || [ ! -s "$FW_PRE" ]; then
    fw_fail "the C preprocessor failed on $FW_ASM."
fi

# ----------------------------------------------------------------------------
# Step 2: Copy the lines between the markers and check the rules for them
# Prints "<table markers> <sections> <string lines> <labels>"
# ----------------------------------------------------------------------------

if ! STRROM_INFO=$(awk -v OUT="$STR_SRC" -v MAXLINE="$STRROM_MAXLINE" '
function fail(msg) { print "ERROR: " msg; bad = 1; exit 1 }
BEGIN { MAXLINE += 0; print "                .ORG    0x0000" > OUT }
{ sub(/\r$/, "") }
/^[ \t]*;[ \t]*STRROM_TABLE[ \t]*$/ {
    if (inreg) fail("the marker STRROM_TABLE is located between STRROM_BEGIN and STRROM_END.")
    ntab++; next
}
/^[ \t]*;[ \t]*STRROM_BEGIN[ \t]*$/ {
    if (inreg) fail("STRROM_BEGIN follows STRROM_BEGIN without a STRROM_END in between.")
    inreg = 1; nreg++; last = ""; pending = ""; next
}
/^[ \t]*;[ \t]*STRROM_END[ \t]*$/ {
    if (!inreg)        fail("STRROM_END without STRROM_BEGIN.")
    if (pending != "") fail("the label " pending " is not followed by a string before STRROM_END.")
    if (last == "")    fail("there is no string between STRROM_BEGIN and STRROM_END.")
    if (last != "W")   fail("the last string before a STRROM_END needs to end with an .ASCII_W line. Last line: " lastline)
    inreg = 0; next
}
!inreg { next }
length($0) > MAXLINE {
    fail("a line between STRROM_BEGIN and STRROM_END has more than " MAXLINE " characters; split the string with .ASCII_P: " substr($0, 1, 60) "...")
}
/^[ \t]*$/ || /^[ \t]*;/ { print > OUT; next }
{
    rest = $0; label = ""
    if (rest !~ /^[ \t]/) {
        label = rest; sub(/[ \t;].*$/, "", label)
        sub(/^[^ \t;]+/, "", rest)
        if (label ~ /!$/)
            fail("the label " label " is exported, but a handle is no string pointer for other programs: " $0)
    }
    if (rest ~ /^[ \t]*(;.*)?$/) {
        pending = label; nlab++
        print > OUT; next
    }
    if (rest ~ /^[ \t]+\.ASCII_[WP][ \t]+"/) {
        if (label == "" && pending == "" && last != "P")
            fail("string without a label between STRROM_BEGIN and STRROM_END: " $0)
        text = rest; sub(/^[ \t]+\.ASCII_[WP][ \t]+"/, "", text)
        quote = index(text, "\"")
        if (quote == 0)
            fail("string without a closing double quote: " $0)
        text = substr(text, 1, quote - 1)
        if (text ~ /\\\\/ || text ~ /\\$/)
            fail("the assembler cannot encode a backslash that is followed by a backslash or by a double quote: " $0)
        if (label != "") nlab++
        last = (rest ~ /^[ \t]+\.ASCII_W/) ? "W" : "P"
        pending = ""; lastline = $0; ndir++
        print > OUT; next
    }
    fail("only labels, .ASCII_W, .ASCII_P and comments are allowed between STRROM_BEGIN and STRROM_END: " $0)
}
END {
    if (bad) exit 1
    if (inreg) { print "ERROR: STRROM_BEGIN without STRROM_END."; exit 1 }
    print ntab + 0, nreg + 0, ndir + 0, nlab + 0
}' "$FW_PRE"); then
    echo "$STRROM_INFO"
    fw_fail "the string ROM sections in the source of $FW_ASM are not valid."
fi

set -- $STRROM_INFO
STRROM_TABS=$1
STRROM_DIRS=$3
STRROM_LABS=$4

if [ "$STRROM_TABS" -gt 1 ]; then
    fw_fail "the marker STRROM_TABLE occurs $STRROM_TABS times; M2M/rom/strrom.asm must be included exactly once."
fi

STRROM_CHARS=0
STRROM_COUNT=0

if [ "$STRROM_TABS" -eq 1 ] && [ "$STRROM_DIRS" -gt 0 ]; then

    # Assemble the strings at address 0
    if ! "$QNICE_ASM_DIR/qasm" "$STR_SRC" "$STR.out" || [ ! -f "$STR.out" ] || [ ! -f "$STR.lis" ]; then
        fw_fail "assembling the string ROM strings failed."
    fi

    # ------------------------------------------------------------------------
    # Step 3 and the outputs of step 4: <strings>.rom and the table lines
    # Prints "<characters used> <labels>"
    # ------------------------------------------------------------------------

    if ! STRROM_INFO=$(awk -v SIZE="$STRROM_SIZE" -v WIN="$STRROM_WIN" -v ROMFILE="$STR.rom" -v TABFILE="$STR_TAB" '
    function fail(msg) { print "ERROR: " msg; bad = 1; exit 1 }
    function hex(s,   i, c, v, d) {
        v = 0; s = toupper(s); sub(/^0X/, "", s)
        if (length(s) == 0) return -1
        for (i = 1; i <= length(s); i++) {
            c = substr(s, i, 1); d = index("0123456789ABCDEF", c) - 1
            if (d < 0) return -1
            v = v * 16 + d
        }
        return v
    }
    BEGIN { SIZE += 0; WIN += 0 }   # compare and calculate as numbers
    FNR == 1 { fileno++ }
    { sub(/\r$/, "") }
    fileno == 1 {
        a = hex($1); v = hex($2)
        if (a != FNR - 1)     fail("unexpected address " $1 " in line " FNR " of the assembled strings.")
        if (v < 0 || v > 255) fail("the value " $2 " at " $1 " of the assembled strings is not an 8-bit character.")
        w[n++] = v
        next
    }
    /^Label-list:/ { inlist = 1; next }
    inlist {
        line = $0
        gsub(/:/, " ", line)
        m = split(line, t, /[ \t]+/)
        for (i = 1; i < m; i++)
            if (t[i] != "" && t[i + 1] ~ /^0x[0-9A-Fa-f]+$/) {
                lab[++nl] = t[i]; adr[nl] = hex(t[i + 1]); i++
            }
    }
    END {
        if (bad) exit 1
        if (n + 0 == 0)    { print "ERROR: there are no assembled strings."; exit 1 }
        if (w[n - 1] != 0) { print "ERROR: the last string ROM string has no zero terminator."; exit 1 }

        # place the strings: pos[i] is the string ROM position of word i
        cursor = 0; start = 0
        for (i = 0; i < n; i++) {
            if (w[i] != 0) continue
            len = i - start + 1
            if (len > WIN) {
                print "ERROR: a string ROM string has " len " characters including its zero terminator, but the"
                print "       maximum is " WIN ". It starts at address " start " of the listing of the strings."
                exit 1
            }
            if ((cursor % WIN) + len > WIN) cursor += WIN - (cursor % WIN)
            for (k = start; k <= i; k++) pos[k] = cursor + k - start
            cursor += len
            start = i + 1
        }
        if (cursor > SIZE) {
            print "ERROR: the string ROM is full: " cursor " characters are needed, but only " SIZE " are"
            print "       available. Increase C_STRROM_ADDR_WIDTH in M2M/vhdl/qnice_wrapper.vhd."
            exit 1
        }

        for (a = 0; a < SIZE; a++) img[a] = 0
        for (k = 0; k < n; k++) img[pos[k]] = w[k]
        for (a = 0; a < SIZE; a++) printf("%02X\n", img[a]) > ROMFILE

        for (i = 1; i <= nl; i++) {
            if (adr[i] < 0 || adr[i] >= n) {
                print "ERROR: the label " lab[i] " does not point to a string ROM string."
                exit 1
            }
            printf("%-23s .DW     0x%04X\n", lab[i], pos[adr[i]]) > TABFILE
        }
        print cursor, nl + 0
    }' "$STR.out" "$STR.lis"); then
        echo "$STRROM_INFO"
        fw_fail "placing the strings in the string ROM failed."
    fi

    set -- $STRROM_INFO
    STRROM_CHARS=$1
    STRROM_COUNT=$2

    if [ "$STRROM_COUNT" -ne "$STRROM_LABS" ]; then
        fw_fail "there are $STRROM_LABS labels between the markers, but the assembler reports $STRROM_COUNT."
    fi

    # ------------------------------------------------------------------------
    # The rest of step 4: remove the strings from the firmware source and
    # insert the table lines behind the table marker
    # ------------------------------------------------------------------------

    if ! awk -v TAB="$STR_TAB" '
    BEGIN { while ((getline line < TAB) > 0) tab[++nt] = line; close(TAB) }
    { probe = $0; sub(/\r$/, "", probe) }
    probe ~ /^[ \t]*;[ \t]*STRROM_TABLE[ \t]*$/ { print; for (i = 1; i <= nt; i++) print tab[i]; done = 1; next }
    probe ~ /^[ \t]*;[ \t]*STRROM_BEGIN[ \t]*$/ { inreg = 1; print; next }
    probe ~ /^[ \t]*;[ \t]*STRROM_END[ \t]*$/   { inreg = 0; print; next }
    inreg { next }
    { print }
    END { if (!done || nt + 0 == 0) exit 1 }' "$FW_PRE" > "$FW_SRC"; then
        fw_fail "inserting the string ROM table into the firmware source failed."
    fi

else

    # No string ROM strings: the firmware is assembled as it is and the
    # string ROM is empty
    cp "$FW_PRE" "$FW_SRC"
    if ! awk -v SIZE="$STRROM_SIZE" 'BEGIN { for (a = 0; a < SIZE; a++) print "00" }' > "$STR.rom"; then
        fw_fail "cannot write $STR.rom."
    fi

fi

STRROM_LINES=$(wc -l < "$STR.rom" | tr -d ' ')
if [ "$STRROM_LINES" -ne "$STRROM_SIZE" ]; then
    fw_fail "$STR.rom has $STRROM_LINES lines, expected $STRROM_SIZE."
fi

# ----------------------------------------------------------------------------
# Assemble the firmware
# ----------------------------------------------------------------------------

if ! "$QNICE_ASM_DIR/qasm" "$FW_SRC" "$FW.out" || [ ! -f "$FW.out" ]; then
    fw_fail "assembling $FW_ASM failed."
fi

if ! "$QNICE_ASM_DIR/qasm2rom" "$FW.out" "$FW.rom" || [ ! -f "$FW.rom" ]; then
    fw_fail "converting $FW.out to $FW.rom failed."
fi

fw_cleanup

if [ "$STRROM_TABS" -eq 1 ]; then
    echo "String ROM: ${STRROM_CHARS}/${STRROM_SIZE} characters in ${STRROM_COUNT} strings."
else
    echo "String ROM: not used, all strings are part of the firmware."
fi

exit 0
