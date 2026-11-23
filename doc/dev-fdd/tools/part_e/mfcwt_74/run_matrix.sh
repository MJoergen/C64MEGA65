#!/bin/bash
# run_matrix.sh <stock dir> <jd dir> <out dir> [JOBS] [regular expression of group names]
# The covering matrix of the READY rule on the genuine ROM (exp8_matrix.py: UI + "$"; exp9_seek.py:
# one long seek). <stock dir> is a directory without c1581.rom (the stock ROM of the repository),
# <jd dir> one with the JiffyDOS ROM of a 1581 as c1581.rom. One log per group in <out dir>, named
# after the group; JOBS groups run at the same time (default 2); the expression selects groups
# (default: all). The table below is the matrix.
T="$(cd "$(dirname "$0")" && pwd)"
S=${1:?stock dir}; J=${2:?jd dir}; O=${3:?out dir}; JOBS=${4:-2}; SEL=${5:-.}
mkdir -p "$O" || exit 1
# group | ROM | script | arguments
grep -v '^#' > "$O/groups.txt" <<'EOF'
n_rate_h18_c39   | stock | exp8_matrix.py | new rate 18 39 stopped 400:790:30
n_rate_h18_c79   | stock | exp8_matrix.py | new rate 18 79 stopped 400:790:30
n_rate_h18_c10   | stock | exp8_matrix.py | new rate 18 10 stopped 400:790:65
n_rtl_h18_c39    | stock | exp8_matrix.py | new rtl 18 39 stopped 400:790:65
n_12_h30_c79     | stock | exp8_matrix.py | new 12 30 79 stopped 400:790:65
n_rate_h0_c39    | stock | exp8_matrix.py | new rate 0 39 stopped 400:790:65
n_rate_h30_c39   | stock | exp8_matrix.py | new rate 30 39 stopped 400:790:65
n_rate_h18_run   | stock | exp8_matrix.py | new rate 18 39 run9 620
n_jd_rate_h18    | jd    | exp8_matrix.py | new rate 18 39 stopped 400:790:65
n_jd_12_h30_run  | jd    | exp8_matrix.py | new 12 30 39 run9 620
o_rtl_h0_c39     | stock | exp8_matrix.py | old rtl 0 39 stopped 480:690:15
o_rate_h0_c39    | stock | exp8_matrix.py | old rate 0 39 stopped 480:690:15
o_rtl_h18_c39    | stock | exp8_matrix.py | old rtl 18 39 stopped 400:790:30
o_rate_h18_c39   | stock | exp8_matrix.py | old rate 18 39 stopped 400:790:30
o_rtl_h18_c79    | stock | exp8_matrix.py | old rtl 18 79 stopped 400:790:65
o_rate_h18_c79   | stock | exp8_matrix.py | old rate 18 79 stopped 400:790:65
s_old_rtl_50     | stock | exp9_seek.py   | old rtl 18 10 61 12
s_old_rate_50    | stock | exp9_seek.py   | old rate 18 10 61 12
s_new_rate_50    | stock | exp9_seek.py   | new rate 18 10 61 12
s_old_rtl_79     | stock | exp9_seek.py   | old rtl 18 0 80 12
s_old_rate_79    | stock | exp9_seek.py   | old rate 18 0 80 12
s_new_rate_79    | stock | exp9_seek.py   | new rate 18 0 80 12
s_new_12_79      | stock | exp9_seek.py   | new 12 30 0 80 12
EOF
run_group() {
   local line="$1" name rom script args dir
   name=$(echo "$line" | cut -d'|' -f1 | tr -d ' ')
   rom=$(echo "$line" | cut -d'|' -f2 | tr -d ' ')
   script=$(echo "$line" | cut -d'|' -f3 | tr -d ' ')
   args=$(echo "$line" | cut -d'|' -f4)
   if [ "$rom" = jd ]; then dir=$J; else dir=$S; fi
   ( cd "$dir" && python3 -I -B "$T/$script" $args ) > "$O/$name.log" 2>&1
   echo "$name: $(tail -1 "$O/$name.log")"
}
export -f run_group
export T S J O
grep -v '^ *$' "$O/groups.txt" | grep -E "^($SEL)" | tr '\n' '\0' | xargs -0 -P "$JOBS" -I{} bash -c 'run_group "$1"' _ {}
echo "EXIT $?"
