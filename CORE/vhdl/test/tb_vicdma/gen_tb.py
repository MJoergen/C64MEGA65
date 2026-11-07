#!/usr/bin/env python3
"""Generate the tb_vicdma benches (issue #259) from the real RTL text.

usage: gen_tb.py <main.vhd> <fpga64_sid_iec.vhd> <outdir>

What is generated (into <outdir>):

  fpga64_sid_iec_tb.vhd  The WHOLE fpga64_sid_iec.vhd (entity and architecture as written),
                         with exactly four instances replaced by stubs: cpu (cpu_6510), sid
                         (sid_top), cia1 and cia2 (mos6526). The CPU stub replays a fixed bus
                         program (register writes to the VIC-II and the color RAM, then an idle
                         read loop) with the T65's timing: outputs change on enableCpu, a read is
                         held while RDY (= baLoc) is low, a write completes. Everything else (the
                         sysCycle state machine and all clock enables, the cpuHasBus/phi0 grant,
                         dma_active sampling, the cpuAddr/cpuDo/cpuWe muxes, vicBus, vicDiAec and
                         colorDataAec, ramCE/ramWE/cpu_cyc, the VIC-II, the PLA/bus logic, the
                         color RAM) is the real code. The fpga64_rgbcolor LUT is stubbed too (the
                         bench compares the VIC's colorIndex). Additions: power-up '0' for registers
                         that have no initial value (FPGA GSR), read-only probe assignments to package
                         signals, the VIC's unconnected debugX/debugY outputs wired to probes, and two
                         GHDL-only workarounds that keep the behavior identical: "when others => null"
                         in the turbo_speed case, and a guard around sysCycleDef'succ(preCycle) (GHDL
                         bound-checks it at CYCLE_CPUF although the next statement overrides it).
                         GHDL 5.1 crashes on VHDL-2008 external names, hence the package probes; the
                         VIC-II itself is observed through its ports only (ba, addrValid, vicAddr).
  tb_vicdma_pkg.vhd      CPU program and probe signals.
  tb_vicdma_g<N>.vhd     Top bench for C_CART_DMA_GRACE_RD_CYCLES = N. Contains, spliced verbatim
                         from main.vhd: the fpga64_sid_iec_inst instance with its port map,
                         cpu_data_in_proc, c64_ram_we_o, cart_out_a, cart_out_sel,
                         cart_output_pipeline_proc, cart_input_pipeline_proc,
                         cart_dotclk_shape_proc, cart_dma_ba_proc, handle_hardware_expansion_proc
                         and handle_cores_expansion_port_signals_proc. The signal, constant and
                         port declarations these need are extracted from main.vhd itself, so a
                         new register in main.vhd is picked up without editing this script.
                         Inputs of main.vhd that are driven by code that is not spliced are tied
                         off (list printed below). N = 3 is the file as written; N = 1 (A24) and
                         N = 4 (negative control: one grace cycle too many) are text
                         substitutions of the spliced constant.
  ram_ramp.hex, ram_ff.hex  Power-on image of the 64 KB C64 RAM (loaded by the real
                         dualport_2clk_ram/tdp_ram through ROM_PRELOAD, as mega65.vhd does).
  roms/*.hex             Contents for the dprom instances of fpga64_buslogic (never selected).

If an anchor disappears from the RTL, this script fails loudly."""
import re, sys, os

main_p, sid_p, out = sys.argv[1], sys.argv[2], sys.argv[3]
main = open(main_p).read()
sid = open(sid_p).read()


def die(msg):
    sys.exit("gen_tb.py: " + msg)


def strip_comments(s):
    return re.sub(r'--[^\n]*', '', s)


def find(src, a, who, start=0):
    i = src.find(a, start)
    if i < 0:
        die(f"anchor not found in {who}: {a[:70]!r}")
    return i


def between(src, a, b, who):
    i = find(src, a, who)
    j = find(src, b, who, i) + len(b)
    return src[i:j]


def statement(src, a, who):
    """from anchor a to the next ';' (a concurrent assignment)"""
    i = find(src, a, who)
    return src[i:src.index(';', i) + 1]


def paren_end(src, i):
    """index just after the ')' matching the first '(' at or after i (skips comments, strings)"""
    k = src.index('(', i)
    depth = 0
    while True:
        c = src[k]
        if src.startswith('--', k):
            k = src.index('\n', k)
            continue
        if c == '"':
            k = src.index('"', k + 1)
        elif c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return k + 1
        k += 1


def idents(text):
    t = re.sub(r'"[^"\n]*"', '""', strip_comments(text))
    return set(w.lower() for w in re.findall(r'[A-Za-z]\w*', t))


def parse_decls(region):
    """signal/constant/type/subtype declarations: name -> (order, kind, name, rest)"""
    decls = {}
    for n_st, st in enumerate(strip_comments(region).split(';')):
        s = st.strip()
        if not s:
            continue
        m = re.match(r'signal\s+(.+?)\s*:\s*(.+)$', s, re.S | re.I)
        if m:
            for n in m.group(1).split(','):
                n = n.strip()
                decls[n.lower()] = (n_st, 'signal', n, m.group(2).strip())
            continue
        m = re.match(r'constant\s+(\w+)\s*:\s*(.+)$', s, re.S | re.I)
        if m:
            decls[m.group(1).lower()] = (n_st, 'constant', m.group(1), m.group(2).strip())
            continue
        m = re.match(r'(subtype|type)\s+(\w+)\s+is\s+(.+)$', s, re.S | re.I)
        if m:
            decls[m.group(2).lower()] = (n_st, m.group(1).lower(), m.group(2), m.group(3).strip())
    return decls


def parse_ports(entity_text):
    t = strip_comments(entity_text)
    m = re.search(r'\bport\s*\(', t, re.I)
    body = t[m.end():t.rindex(')')]
    ports = {}
    for n_st, st in enumerate(body.split(';')):
        m = re.match(r'\s*(\w+(?:\s*,\s*\w+)*)\s*:\s*(in|out|inout|buffer)\s+(.+?)\s*$', st, re.S | re.I)
        if m:
            typ = m.group(3).partition(':=')[0].strip()
            for n in m.group(1).split(','):
                ports[n.strip().lower()] = (n_st, m.group(2).lower(), n.strip(), typ)
    return ports


# ------------------------------------------------------------------------------------------------
# 1. fpga64_sid_iec.vhd: the whole file, four instances replaced by stubs, probes added
# ------------------------------------------------------------------------------------------------
red = sid


def cut_instance(src, label_re, who):
    m = re.search(label_re, src, re.M)
    if not m:
        die(f"instance not found in {who}: {label_re}")
    pm = src.index("port map", m.start())
    end = src.index(';', paren_end(src, pm)) + 1
    return src[:m.start()] + f"-- [tb_vicdma] instance '{m.group(0).strip()}' removed, stub at the end of the architecture\n" + src[end:]


for lab in (r'^cpu\s*:\s*entity\s+work\.cpu_6510', r'^sid\s*:\s*sid_top', r'^cia1\s*:\s*mos6526', r'^cia2\s*:\s*mos6526',
            r'^c64colors\s*:\s*entity\s+work\.fpga64_rgbcolor'):
    red = cut_instance(red, lab, "fpga64_sid_iec.vhd")

# GHDL insists on full coverage of a case over a std_logic_vector (Vivado does not): the turbo_speed
# case covers the four binary values only. Adding "when others" changes nothing for binary values.
old_case = '''					when "11" => turbo_m <= "111"; -- unused\n'''
if red.count(old_case) != 1:
    die("turbo_speed case ('when \"11\" => turbo_m <= \"111\"; -- unused') not found exactly once")
red = red.replace(old_case, old_case + "\t\t\t\t\twhen others => null; -- [tb_vicdma] GHDL: full case coverage\n")

# GHDL bound-checks sysCycleDef'succ(CYCLE_CPUF) although the next statement overrides that assignment
# (synthesis never evaluates it). Guarding it keeps the behavior identical.
old_succ = "\t\tpreCycle <= sysCycleDef'succ(preCycle);\n"
if red.count(old_succ) != 1:
    die("'preCycle <= sysCycleDef'succ(preCycle);' not found exactly once")
red = red.replace(old_succ, "\t\tif preCycle /= sysCycleDef'high then preCycle <= sysCycleDef'succ(preCycle); end if; -- [tb_vicdma] GHDL bound check\n")

arch_i = find(red, "architecture rtl of fpga64_sid_iec is", "fpga64_sid_iec.vhd")
beg_i = red.index("\nbegin\n", arch_i)
region = red[arch_i:beg_i]
inits = []


def add_init(m):
    name, sp, typ = m.group(1), m.group(2), m.group(3)
    inits.append(name)
    val = "'0'" if typ.lower() == 'std_logic' else "(others => '0')"
    return f"signal {name}{sp}: {typ} := {val}; -- [tb_vicdma] power-up value"


region = re.sub(r'^signal\s+(\w+)(\s*):\s*(std_logic|unsigned\([^)]*\)|std_logic_vector\([^)]*\))\s*;',
                add_init, region, flags=re.M | re.I)
region += "\n-- [tb_vicdma] CPU stub program counter\nsignal tb_cpu_pc : natural := 0;\n"
red = red[:arch_i] + "library work;\nuse work.tb_vicdma_pkg.all;\n\n" + region + red[beg_i:]

old = "\tirq_n => irq_vic\n);"
if red.count(old) != 1:
    die("VIC port map end ('irq_n => irq_vic') not found exactly once in fpga64_sid_iec.vhd")
red = red.replace(old, "\tirq_n => irq_vic,\n\t-- [tb_vicdma] unconnected debug outputs wired to probes\n\tdebugX => tb_p_debugX,\n\tdebugY => tb_p_debugY\n);")

STUBS = r'''
-- =====================================================================================
-- [tb_vicdma] stubs for the removed instances and read-only probes
-- =====================================================================================
-- cpu_6510 stub: replays C_TB_CPU_PROG with the bus timing of the T65 in this core:
-- enable => enableCpu and not dma_active, rdy => baLoc (a read is repeated while RDY is
-- low, a write completes), address/data/we change on the enable tick (edge into CYCLE_EXT0).
tb_cpu_stub : process(clk32)
begin
	if rising_edge(clk32) then
		if reset = '1' then
			tb_cpu_pc <= 0;
		elsif enableCpu = '1' and dma_active = '0' then
			if (C_TB_CPU_PROG(tb_cpu_pc).we = '1' or baLoc = '1') and tb_cpu_pc < C_TB_CPU_PROG'high then
				tb_cpu_pc <= tb_cpu_pc + 1;
			end if;
		end if;
	end if;
end process;
cpuAddr_pre <= C_TB_CPU_PROG(tb_cpu_pc).addr;
cpuDo_pre   <= C_TB_CPU_PROG(tb_cpu_pc).data;
cpuWe_pre   <= C_TB_CPU_PROG(tb_cpu_pc).we;
cpuIO       <= x"37";      -- $01 = $37: LORAM = HIRAM = CHAREN = 1
nmi_ack     <= '0';
-- fpga64_rgbcolor stub (color LUT for the r/g/b outputs; the bench compares colorIndex)
r <= x"00"; g <= x"00"; b <= x"00";
-- sid_top stub
sid_do  <= x"00";
audio_l <= (others => '0');
audio_r <= (others => '0');
-- mos6526 stubs (CIA2 port A = $97: VIC bank 0)
cia1Do   <= x"FF"; cia1_pao <= x"FF"; cia1_pbo <= x"FF"; sp1_o <= '1'; cnt1_o <= '1'; irq_cia1 <= '1';
cia2Do   <= x"FF"; cia2_pao <= x"97"; cia2_pbo <= x"FF"; cia2_pbe <= x"00"; pc2_n_o <= '1'; sp2_o <= '1'; cnt2_o <= '1'; irq_cia2 <= '1';
-- probes
tb_p_aec        <= aec;
tb_p_cpuHasBus  <= cpuHasBus;
tb_p_phi0       <= phi0_cpu;
tb_p_enaVic     <= enableVic;
tb_p_enaPix     <= enablePixel;
tb_p_dma_active <= dma_active;
tb_p_ba_dma     <= ba_dma;
tb_p_vicAddr    <= vicAddr;
tb_p_colorIndex <= vicColorIndex;
tb_p_vicDi      <= vicDiAec;
tb_p_vicColor   <= colorDataAec;
tb_p_cycle      <= sysCycleDef'pos(sysCycle);
tb_p_cpu_pc     <= tb_cpu_pc;
tb_p_cpuWe      <= cpuWe;
'''
k = red.rindex("end architecture;")
red = red[:k] + STUBS + "\n" + red[k:]
open(os.path.join(out, "fpga64_sid_iec_tb.vhd"), "w").write(red)

# ------------------------------------------------------------------------------------------------
# 2. main.vhd: splice the processes, extract their declarations
# ------------------------------------------------------------------------------------------------
W = "main.vhd"
pieces = [
    ("fpga64_sid_iec_inst", between(main, "  fpga64_sid_iec_inst : entity work.fpga64_sid_iec", "); -- fpga64_sid_iec_inst", W)),
    ("cpu_data_in_proc", between(main, "  cpu_data_in_proc : process (all)", "  end process cpu_data_in_proc;", W)),
    ("c64_ram_we_o", statement(main, "  c64_ram_we_o <= c64_ram_ce and c64_ram_we", W)),
    ("cart_out_a", statement(main, "  cart_out_a <= ", W)),
    ("cart_out_sel", statement(main, "  cart_out_sel <= ", W)),
    ("cart_output_pipeline_proc", between(main, "  cart_output_pipeline_proc : process (clk_main_i)", "  end process cart_output_pipeline_proc;", W)),
    ("cart_input_pipeline_proc", between(main, "  cart_input_pipeline_proc : process (clk_main_i)", "  end process cart_input_pipeline_proc;", W)),
    ("cart_dotclk_shape_proc", between(main, "  cart_dotclk_shape_proc : process (clk_main_i)", "  end process cart_dotclk_shape_proc;", W)),
    ("cart_dma_ba_proc", between(main, "  cart_dma_ba_proc : process (clk_main_i)", "  end process cart_dma_ba_proc;", W)),
    ("handle_hardware_expansion_proc", between(main, "  handle_hardware_expansion_proc : process (all)", "  end process handle_hardware_expansion_proc;", W)),
    ("handle_cores_expansion_port_signals_proc", between(main, "  handle_cores_expansion_port_signals_proc : process (all)", "  end process handle_cores_expansion_port_signals_proc;", W)),
]
spliced = "\n\n".join(f"  -- ===== spliced from main.vhd: {n} =====\n{t}" for n, t in pieces)

m_arch = find(main, "architecture synthesis of main is", W)
m_beg = main.index("\nbegin\n", m_arch)
mdecl = parse_decls(main[m_arch + len("architecture synthesis of main is"):m_beg])
ment = between(main, "entity main is", "end entity main;", W)
mports = parse_ports(ment)
mgen = {"g_vdnum": "constant G_VDNUM : natural := 2;", "g_board": 'constant G_BOARD : string := "MEGA65_R6";'}
fports = parse_ports(between(sid, "entity fpga64_sid_iec is", "end fpga64_sid_iec;", "fpga64_sid_iec.vhd"))

# what the spliced code drives
drv = set(m.group(1).lower() for m in re.finditer(r'^\s*(\w+)\s*(?:\([^\n;]*?\))?\s*<=', strip_comments(spliced), re.M))
inst = strip_comments(pieces[0][1])
pm = inst[inst.index("port map"):]
for m in re.finditer(r'(\w+)\s*=>\s*([^,\n]+)', pm):
    formal = m.group(1).lower()
    if formal not in fports:
        die(f"formal {formal} of fpga64_sid_iec_inst is not a port of fpga64_sid_iec")
    if fports[formal][1] in ('out', 'inout', 'buffer'):
        a = re.match(r'\s*(\w+)', m.group(2)).group(1).lower()
        if a != 'open':
            drv.add(a)
drv.discard('variable')

# what the bench drives itself (clock, reset, RAM data, the Expansion Port input pins)
BENCH = {'clk_main_i': "'0'", 'reset_core_n': "'0'", 'c64_ram_data_i': None,
         'cart_a_i': None, 'cart_d_i': None, 'cart_rw_i': None, 'cart_ba_i': None, 'cart_dma_i': None,
         'cart_io1_i': None, 'cart_io2_i': None, 'cart_game_i': None, 'cart_exrom_i': None, 'cart_nmi_i': None,
         'cart_irq_i': None, 'cart_roml_i': None, 'cart_romh_i': None, 'cart_reset_i': None}
for b in BENCH:
    if b in drv:
        die(f"{b} is driven by spliced code and by the bench")

# tie-offs for everything that is read but driven by non-spliced code of main.vhd
TIE = {'pause_i': "'0'", 'c64_ntsc_i': "'0'", 'clk_main_speed_i': "31527778", 'c64_rom_i': '"01"',
       'c64_exp_port_mode_i': '"0000"', 'cia1_pa_in': 'x"FF"', 'cia1_pb_in': 'x"FF"', 'hard_reset_n': "'1'",
       'cold_start_done': "'1'", 'reset_core_int_n': "'1'", 'restore_key_n': "'1'", 'rrnet_mk3_enabled': "'0'",
       'c64_cia_ver_i': "'0'", 'c64rom_we_i': "'0'", 'c64_clk_sd_i': "'0'", 'cartridge_loading_i': "'0'",
       'crt_bank_wait_i': "'0'", 'reu_dma_req': "'0'", 'reu_irq': "'0'", 'reu_dma_we': "'0'", 'reu_oe': "'0'",
       'crt_roml_we': "'0'", 'crt_ioe_wr_ena': "'0'", 'crt_iof_wr_ena': "'0'", 'crt_nmi': "'0'"}

need, stack = set(), list(idents(spliced))
while stack:
    n = stack.pop()
    if n in need:
        continue
    if n in mdecl:
        need.add(n)
        stack += list(idents(mdecl[n][3]))
    elif n in mports:
        need.add(n)
        stack += list(idents(mports[n][3]))
    elif n in mgen:
        need.add(n)

GRACE_DECL = "constant C_CART_DMA_GRACE_RD_CYCLES : natural := 3;"
lines, ties = [], []
for n in sorted((x for x in need if x in mgen)):
    lines.append("  " + mgen[n])
for n in sorted((x for x in need if x in mports), key=lambda x: mports[x][0]):
    _, mode, name, typ = mports[n]
    init = ""
    if n in BENCH:
        init = f" := {BENCH[n]}" if BENCH[n] else ""
    elif n not in drv:
        val = TIE.get(n)
        if val is None:
            val = "'1'" if typ.lower() == 'std_logic' else ("(others => '0')" if re.search(r'vector|unsigned|signed', typ, re.I) else None)
        if val is not None:
            init = f" := {val}"
        ties.append(f"{name}{init or ' (default)'}")
    lines.append(f"  signal {name} : {typ}{init}; -- port ({mode}) of main")
for n in sorted((x for x in need if x in mdecl), key=lambda x: mdecl[x][0]):
    _, kind, name, rest = mdecl[n]
    if kind == 'signal':
        typ, _, init = rest.partition(':=')
        typ, init = typ.strip(), init.strip()
        if n in BENCH:
            if BENCH[n]:
                init = BENCH[n]
        elif n not in drv:
            if n in TIE:
                init = TIE[n]
            elif not init:
                init = "'1'" if typ.lower() == 'std_logic' else ("(others => '0')" if re.search(r'vector|unsigned|signed', typ, re.I) else "")
            ties.append(f"{name} := {init or '(default)'}")
        lines.append(f"  signal {name} : {typ}" + (f" := {init}" if init else "") + ";")
    elif kind == 'constant':
        lines.append(f"  constant {name} : {rest};")
    else:
        lines.append(f"  {kind} {name} is {rest};")
decls = "\n".join(lines)
if decls.count(GRACE_DECL) != 1:
    die(f"'{GRACE_DECL}' not found exactly once in the extracted declarations of main.vhd")

# ------------------------------------------------------------------------------------------------
# 3. CPU program, RAM image, ROM contents
# ------------------------------------------------------------------------------------------------
IDLE = 0x0002                                     # the CPU stub's idle loop reads this RAM byte
regs = {}
for n in range(8):
    regs[2 * n] = (40 + 30 * n) & 0xFF            # sprite X
    regs[2 * n + 1] = 70 + 16 * n                 # sprite Y: lines 70..202 (sprites 0 and 1 Y-expanded)
regs.update({0x10: 0x00, 0x11: 0x1B, 0x12: 0x00, 0x15: 0xFF, 0x16: 0x08, 0x17: 0x03, 0x18: 0x18, 0x19: 0xFF,
             0x1A: 0x00, 0x1B: 0xAA, 0x1C: 0x0F, 0x1D: 0x30, 0x20: 0x0E, 0x21: 0x06, 0x22: 0x02, 0x23: 0x05,
             0x24: 0x07, 0x25: 0x0A, 0x26: 0x0D})
for n in range(8):
    regs[0x27 + n] = n + 1                        # sprite colors
prog = [(IDLE, 0, 0)] * 4
prog += [(0xD000 + r, regs[r], 1) for r in sorted(regs)]
prog += [(0xD800 + i, (i * 5 + 3) & 0x0F, 1) for i in range(1000)]
prog += [(IDLE, 0, 0)]
PROG = ",\n".join(f'    (x"{a:04X}", x"{d:02X}", \'{w}\')' for a, d, w in prog)

PKG = '''library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

-- generated by CORE/vhdl/test/tb_vicdma/gen_tb.py
package tb_vicdma_pkg is
  type t_tb_cpu_op is record
    addr : unsigned(15 downto 0);
    data : unsigned(7 downto 0);
    we   : std_logic;
  end record;
  type t_tb_cpu_prog is array (natural range <>) of t_tb_cpu_op;
  -- idle reads, VIC-II registers $D000..$D02E, color RAM $D800..$DBE7, then an idle read loop
  constant C_TB_CPU_PROG : t_tb_cpu_prog := (
@PROG@);

  -- read-only probes, assigned inside fpga64_sid_iec_tb.vhd
  signal tb_p_aec, tb_p_cpuHasBus, tb_p_phi0, tb_p_enaVic, tb_p_enaPix, tb_p_dma_active, tb_p_ba_dma, tb_p_cpuWe : std_logic;
  signal tb_p_vicAddr    : unsigned(15 downto 0);
  signal tb_p_colorIndex : unsigned(3 downto 0);
  signal tb_p_vicDi      : unsigned(7 downto 0);
  signal tb_p_vicColor   : unsigned(3 downto 0);
  signal tb_p_cycle      : natural;              -- sysCycle'pos: 0 = CYCLE_EXT0 .. 31 = CYCLE_CPUF
  signal tb_p_cpu_pc     : natural;
  signal tb_p_debugX     : unsigned(9 downto 0);
  signal tb_p_debugY     : unsigned(8 downto 0); -- rasterY

  -- shadow of the C64 RAM (expected contents)
  type t_tb_mem is protected
    procedure set(a : natural; v : unsigned(7 downto 0));
    impure function get(a : natural) return unsigned;
  end protected;
end package;

package body tb_vicdma_pkg is
  type t_tb_mem is protected body
    type t_arr is array (0 to 65535) of unsigned(7 downto 0);
    variable m : t_arr := (others => x"00");
    procedure set(a : natural; v : unsigned(7 downto 0)) is begin m(a) := v; end;
    impure function get(a : natural) return unsigned is begin return m(a); end;
  end protected body;
end package body;
'''.replace("@PROG@", PROG)
open(os.path.join(out, "tb_vicdma_pkg.vhd"), "w").write(PKG)


def image(ff):
    m = bytearray(65536)
    m[IDLE] = 0x5A
    for i in range(1000):
        m[0x0400 + i] = (i * 3 + 1) & 0xFF        # screen matrix ($D018 = $18)
    for n in range(8):
        m[0x07F8 + n] = 0xC0 + n                  # sprite pointers -> $3000..$31FF
    for i in range(0x800):
        m[0x2000 + i] = (i * 13 + 7) & 0xFF       # character set in RAM
    for i in range(0x200):
        m[0x3000 + i] = (i * 5 + 0x33) & 0xFF     # sprite data
    m[0x3FFF] = 0xAA                              # idle fetches
    for a in range(0x4000, 0x6000):               # verify source (outside VIC bank 0)
        m[a] = 0xFF if ff else (a & 0xFF)
    for a in range(0x6000, 0x6800):               # fetch target: differs from every byte the REC writes
        m[a] = 0x00 if ff else ((a * 7 + 3 + 128) & 0xFF)
    return m


for name, ff in (("ram_ramp.hex", False), ("ram_ff.hex", True)):
    open(os.path.join(out, name), "w").write("".join(f"{b:02X}\n" for b in image(ff)))
os.makedirs(os.path.join(out, "roms"), exist_ok=True)
for name, size in (("chargen", 4096), ("chargenj", 4096), ("std_C64GS", 16384), ("std_C64", 16384), ("jap_C64", 16384)):
    open(os.path.join(out, "roms", name + ".mif.hex"), "w").write("".join(f"{(i * 11 + 5) & 0xFF:02X}\n" for i in range(size)))

# ------------------------------------------------------------------------------------------------
# 4. top bench
# ------------------------------------------------------------------------------------------------
TB = r'''library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.numeric_std_unsigned.all;
library std;
  use std.textio.all;
library work;
  use work.tb_vicdma_pkg.all;

-- generated by CORE/vhdl/test/tb_vicdma/gen_tb.py (issue #259), C_CART_DMA_GRACE_RD_CYCLES = @G@
entity @ENT@ is
  generic (
    DMA_ON      : boolean := true;          -- false: reference run, the REC model stays idle
    RAM_FILE    : string  := "ram_ramp.hex";
    FF_DATA     : boolean := false;         -- the REC writes $FF in its fetches (use with ram_ff.hex)
    LATE_RESUME : boolean := false;         -- REC resumes one cycle after it saw BA high at a PHI2 rise
    TAG         : string  := "run"
  );
end entity;

architecture sim of @ENT@ is
  -- ===== declarations extracted from main.vhd =====
@DECLS@

  -- ===== bench =====
  constant C_TB_REC_ADDR_TICK  : natural := 4;   -- the REC drives address and R/W from tick 5 (~190 ns after PHI2 fell)
  constant C_TB_REC_WDATA_TICK : natural := 20;  -- ... and write data from tick 21 (~130 ns after PHI2 rose)
  constant C_TB_REC_HOLD_READS : natural := 3;   -- the REC holds a read for three BA-low cycles, then releases the bus
  type t_tb_xfer is record
    wr    : boolean;     -- false: verify (reads), true: fetch (writes)
    c64   : natural;     -- C64 start address
    len   : natural;
    frame : natural;     -- start not before this frame ...
    line  : natural;     -- ... and raster line (0 = right after the previous transfer)
  end record;
  type t_tb_xfers is array (natural range <>) of t_tb_xfer;
  constant C_TB_XFERS : t_tb_xfers := (
    (false, 16#4000#, 4096, 1, 20),
    (false, 16#5000#, 4096, 1, 0),
    (true,  16#6000#, 1024, 1, 0),
    (false, 16#6000#, 1024, 1, 0),
    (true,  16#6400#, 1024, 2, 60),
    (false, 16#6400#, 1024, 2, 0));

  signal tb_done, tb_stop      : boolean := false;
  signal tb_frame              : natural := 0;
  signal tb_lcyc               : natural := 0;      -- C64 cycles since rasterY last changed
  -- Expansion Port lines as the cartridge sees them
  signal tb_net_a, tb_hold_a   : unsigned(15 downto 0) := x"0000";
  signal tb_net_d              : unsigned(7 downto 0);
  signal tb_net_rw, tb_net_ba  : std_logic;
  signal tb_hold_rw            : std_logic := '1';
  -- REC model drivers
  signal tb_rec_dma_n          : std_logic := '1';
  signal tb_rec_a              : unsigned(15 downto 0) := x"0000";
  signal tb_rec_d              : unsigned(7 downto 0) := x"00";
  signal tb_rec_rw             : std_logic := '1';
  signal tb_rec_a_oe, tb_rec_rw_oe, tb_rec_d_oe : std_logic := '0';
  signal tb_rec_kind           : natural := 0;      -- 0 idle, 1 verify, 2 fetch
  signal tb_rec_on             : std_logic := '0';  -- the REC has an access on the bus in this cycle
  signal tb_xfers_done         : natural := 0;
  -- REC -> monitor event, valid during tick 31 (set at the PHI2 falling edge)
  signal tb_ev_valid, tb_ev_rd, tb_ev_counted, tb_ev_mis : std_logic := '0';
  signal tb_ev_pos             : natural := 0;      -- 0: counted access, k: k-th held read (or the write) in a stall
  signal tb_ev_val, tb_ev_exp  : unsigned(7 downto 0) := x"00";
  signal tb_ev_addr            : unsigned(15 downto 0) := x"0000";
  -- C64 RAM
  signal tb_ram_qa, tb_ramb_q  : std_logic_vector(7 downto 0);
  signal tb_ramb_addr          : std_logic_vector(15 downto 0) := (others => '0');
  shared variable tb_shadow    : t_tb_mem;

  function h(v : unsigned) return string is begin return to_hstring(v); end;
  function b(s : std_logic) return string is begin return std_logic'image(s)(2 to 2); end;
  function kind_s(w : boolean) return string is begin if w then return "fetch "; else return "verify"; end if; end;
  function rec_data(a : natural) return unsigned is
  begin
    if FF_DATA then return x"FF"; end if;
    return to_unsigned((a * 7 + 3) mod 256, 8);
  end;
begin
@SPLICED@

  -- ===== clock and reset =====
  clk_main_i   <= not clk_main_i after 15.86 ns when not tb_done;
  reset_core_n <= '0', '1' after 3 us;

  -- ===== C64 RAM: the same entity and generics as c64_ram in mega65.vhd (port B = bench readback) =====
  tb_c64_ram : entity work.dualport_2clk_ram
    generic map (
      ROM_FILE => RAM_FILE, ROM_FILE_HEX => true, ROM_PRELOAD => true,
      ADDR_WIDTH => 16, DATA_WIDTH => 8, FALLING_A => false, FALLING_B => true)
    port map (
      clock_a => clk_main_i, address_a => std_logic_vector(c64_ram_addr_o), data_a => std_logic_vector(c64_ram_data_o),
      wren_a => c64_ram_we_o, q_a => tb_ram_qa,
      clock_b => clk_main_i, address_b => tb_ramb_addr, data_b => x"00", wren_b => '0', q_b => tb_ramb_q);
  c64_ram_data_i <= unsigned(tb_ram_qa);

  tb_load : process
    file f : text;
    variable l : line;
    variable v : std_logic_vector(7 downto 0);
  begin
    file_open(f, RAM_FILE, read_mode);
    for i in 0 to 65535 loop
      readline(f, l); hread(l, v); tb_shadow.set(i, unsigned(v));
    end loop;
    file_close(f);
    wait;
  end process;

  -- ===== Expansion Port: transceivers (an FPGA input reads back what the FPGA drives) and the lines =====
  -- address and R/W: bus hold (the last driven value) when nobody drives; data: pull-ups ($FF); BA: pull-up
  tb_net_a  <= cart_a_o  when cart_addr_oe_o = '1' else tb_rec_a  when tb_rec_a_oe  = '1' else tb_hold_a;
  tb_net_rw <= cart_rw_o when cart_ctrl_oe_o = '1' else tb_rec_rw when tb_rec_rw_oe = '1' else tb_hold_rw;
  tb_net_d  <= cart_d_o  when cart_data_oe_o = '1' else tb_rec_d  when tb_rec_d_oe  = '1' else x"FF";
  tb_net_ba <= cart_ba_o when cart_ctrl_oe_o = '1' else '1';
  cart_a_i     <= tb_net_a;
  cart_rw_i    <= tb_net_rw;
  cart_d_i     <= tb_net_d;
  cart_ba_i    <= tb_net_ba;
  cart_io1_i   <= cart_io1_o when cart_ctrl_oe_o = '1' else '1';
  cart_io2_i   <= cart_io2_o when cart_ctrl_oe_o = '1' else '1';
  cart_dma_i   <= tb_rec_dma_n;
  cart_game_i  <= '1';
  cart_exrom_i <= '1';
  cart_nmi_i   <= '1';
  cart_irq_i   <= '1';
  cart_reset_i <= '1';
  cart_roml_i  <= cart_roml_o;
  cart_romh_i  <= cart_romh_o;
  tb_hold_proc : process (clk_main_i)
  begin
    if rising_edge(clk_main_i) then
      tb_hold_a  <= tb_net_a;
      tb_hold_rw <= tb_net_rw;
    end if;
  end process;

  -- ===== frame and line position (from the VIC-II's rasterY) =====
  tb_pos_proc : process (clk_main_i)
    variable prev_y : unsigned(8 downto 0) := (others => '0');
  begin
    if rising_edge(clk_main_i) then
      if tb_p_cycle = 31 then
        if tb_p_debugY /= prev_y then
          tb_lcyc <= 0;
          if tb_p_debugY = 0 then tb_frame <= tb_frame + 1; end if;
        else
          tb_lcyc <= tb_lcyc + 1;
        end if;
        prev_y := tb_p_debugY;
      end if;
    end if;
  end process;

  -- ===== behavioral MOS 8726 REC (cartridge side only: PHI2, BA and the data lines) =====
  -- One access per C64 cycle, address and R/W driven from early in the VIC half to early in the next
  -- cycle. BA is sampled at the PHI2 rising edge: high = the access counts. After a read the REC
  -- holds the read (same address) through the first three BA-low cycles, latching and comparing the
  -- data at the PHI2 falling edge of each, then releases address and R/W. After a write the write in
  -- the first BA-low cycle counts (VICE reu_clk_inc_post_write), then the REC releases. It resumes in
  -- the first cycle in which it sees BA high (VICE: the wait ends in the first cycle whose BA is high).
  tb_rec : process (clk_main_i)
    type t_st is (S_IDLE, S_RUN, S_REL, S_END);
    variable st        : t_st := S_IDLE;
    variable rp        : natural := 0;
    variable prev_phi  : std_logic := '0';
    variable xi        : natural := 0;
    variable wr        : boolean := false;
    variable addr, cnt, held, idle_cyc, cycles, mis_x, held_x, stalls_x : natural := 0;
    variable on_bus, ba_rise, resume : boolean := false;
    variable dval, ev  : unsigned(7 downto 0);
    variable start_y   : unsigned(8 downto 0);
  begin
    if rising_edge(clk_main_i) then
      if prev_phi = '1' and cart_phi2_o = '0' then rp := 31; else rp := (rp + 1) mod 32; end if;
      prev_phi := cart_phi2_o;
      tb_ev_valid <= '0';
      if rp = 0 then
        if st = S_IDLE then
          if DMA_ON and xi <= C_TB_XFERS'high and idle_cyc >= 8 and
             (tb_frame > C_TB_XFERS(xi).frame or (tb_frame = C_TB_XFERS(xi).frame and tb_p_debugY >= C_TB_XFERS(xi).line)) then
            -- the first access waits for BA high like a resume (S_REL, see below)
            st := S_REL; wr := C_TB_XFERS(xi).wr; addr := C_TB_XFERS(xi).c64; cnt := 0; held := 0;
            cycles := 0; mis_x := 0; held_x := 0; stalls_x := 0; resume := false; start_y := tb_p_debugY;
            tb_rec_dma_n <= '0';                       -- /DMA low from tick 1, the first access in this cycle if BA is high
            tb_rec_kind  <= 2 when wr else 1;
          else
            idle_cyc := idle_cyc + 1;
          end if;
        end if;
      elsif rp = C_TB_REC_ADDR_TICK then
        tb_rec_d_oe <= '0';                            -- write data held until here
        on_bus := false;
        case st is
          when S_RUN => on_bus := true;
          when S_REL =>
            if (not LATE_RESUME and tb_net_ba = '1') or (LATE_RESUME and resume) then
              st := S_RUN; on_bus := true; resume := false;
            end if;
          when S_END =>
            tb_rec_dma_n <= '1'; tb_rec_kind <= 0; st := S_IDLE; idle_cyc := 0;
            report "XFER " & integer'image(xi) & " " & kind_s(wr) & " c64=$" & h(to_unsigned(C_TB_XFERS(xi).c64, 16)) &
                   " len=" & integer'image(C_TB_XFERS(xi).len) & " counted=" & integer'image(cnt) &
                   " cycles=" & integer'image(cycles) & " stalls=" & integer'image(stalls_x) &
                   " held_reads=" & integer'image(held_x) & " mismatches=" & integer'image(mis_x) &
                   " lines=" & integer'image(to_integer(start_y)) & ".." & integer'image(to_integer(tb_p_debugY));
            xi := xi + 1; tb_xfers_done <= xi;
          when others => null;
        end case;
        if on_bus then
          tb_rec_a <= to_unsigned(addr, 16); tb_rec_a_oe <= '1';
          tb_rec_rw <= '0' when wr else '1'; tb_rec_rw_oe <= '1';
        else
          tb_rec_a_oe <= '0'; tb_rec_rw_oe <= '0';
        end if;
        tb_rec_on <= '1' when on_bus else '0';
      elsif rp = 16 then
        ba_rise := tb_net_ba = '1';                    -- BA at the PHI2 rising edge (the edge into tick 17)
      elsif rp = C_TB_REC_WDATA_TICK then
        if on_bus and wr then
          tb_rec_d <= rec_data(addr); tb_rec_d_oe <= '1';
        end if;
      elsif rp = 30 then                               -- the PHI2 falling edge (the edge into tick 31)
        if st /= S_IDLE then cycles := cycles + 1; end if;
        if on_bus then
          tb_ev_valid <= '1'; tb_ev_addr <= to_unsigned(addr, 16); tb_ev_mis <= '0';
          tb_ev_rd <= '0' when wr else '1';
          if not wr then
            dval := tb_net_d;                          -- data lines during tick 30
            ev := tb_shadow.get(addr);
            tb_ev_val <= dval; tb_ev_exp <= ev;
            if dval /= ev then tb_ev_mis <= '1'; mis_x := mis_x + 1; end if;
          end if;
          if ba_rise then                              -- counted access
            tb_ev_counted <= '1'; tb_ev_pos <= 0;
            if wr then tb_shadow.set(addr, rec_data(addr)); end if;
            cnt := cnt + 1; addr := addr + 1; held := 0;
            if cnt = C_TB_XFERS(xi).len then st := S_END; end if;
          elsif wr then                                -- the write of the first BA-low cycle counts, then wait
            tb_ev_counted <= '1'; tb_ev_pos <= 1; stalls_x := stalls_x + 1;
            tb_shadow.set(addr, rec_data(addr));
            cnt := cnt + 1; addr := addr + 1;
            if cnt = C_TB_XFERS(xi).len then st := S_END; else st := S_REL; end if;
          else                                         -- a held read
            held := held + 1; held_x := held_x + 1;
            if held = 1 then stalls_x := stalls_x + 1; end if;
            tb_ev_counted <= '0'; tb_ev_pos <= held;
            if held = C_TB_REC_HOLD_READS then st := S_REL; held := 0; end if;
          end if;
        elsif st = S_REL and LATE_RESUME and ba_rise then
          resume := true;
        end if;
      end if;
    end if;
  end process;
@MONITOR@
end architecture;
'''

MON = r'''
  -- ===== monitors (sampled at the rising edges of clk_main_i, i.e. the values of the tick that ends;
  --       t = sysCycle'pos of that tick: 0 = CYCLE_EXT0, PHI2 high in 17..30, falls at the edge into 31) =====
  tb_mon : process (clk_main_i)
    type t_m is array (natural range <>, natural range <>) of integer;
    variable t : natural;
    variable s_ba, s_dma, s_grace, s_grace_rd, s_rw, s_on : std_logic := '0';
    variable cond : boolean;
    variable run_d, run_off : integer := -1;
    variable oe_cpu : boolean := false;
    variable rep : natural := 0;
    variable lowidx, gidx, g, cls : natural := 0;
    -- current stall
    variable c_kind, c_first_aec, c_pg_idx, c_granted, c_early_c, c_early_s, c_cacc, c_sacc : natural := 0;
    variable c_pg_off : integer := -1;
    variable c_pg_viol, c_gviol, c_held, c_mis_nonff, c_line, c_lcyc, c_c2a : natural := 0;
    variable cur_idx, br : natural := 0;
    variable fr_h    : t_m(0 to 17, 0 to 31) := (others => (others => 0));   -- R/W fights [branch*6+idx, tick]
    variable c_held_exp : unsigned(7 downto 0) := x"00";
    variable c_fv_min, c_fv_max : t_m(0 to 0, 1 to 4);
    variable c_mis : t_m(0 to 0, 0 to 3);
    -- totals, first index = class: 0 badline stall (>= 40 BA-low cycles), 1 sprite stall
    variable st_n    : t_m(0 to 1, 0 to 2) := (others => (others => 0));   -- stalls by REC kind 0 none, 1 verify, 2 fetch
    variable gr_hist : t_m(0 to 5, 0 to 5) := (others => (others => 0));   -- [class*3+kind, served grace cycles]
    variable aec_h   : t_m(0 to 1, 0 to 5) := (others => (others => 0));   -- first BA-low cycle with AEC in phi2
    variable fv_min  : t_m(0 to 1, 1 to 4) := (others => (others => 99));
    variable fv_max  : t_m(0 to 1, 1 to 4) := (others => (others => -1));
    variable fv_n    : t_m(0 to 1, 1 to 4) := (others => (others => 0));
    variable mis     : t_m(0 to 1, 0 to 3) := (others => (others => 0));
    variable pg_h    : t_m(0 to 1, 0 to 5) := (others => (others => 0));
    variable pgo_min : t_m(0 to 1, 0 to 0) := (others => (others => 99));
    variable pgo_max : t_m(0 to 1, 0 to 0) := (others => (others => -1));
    variable k1      : t_m(0 to 1, 0 to 10) := (others => (others => 0));
    -- k1(c, 0) gviol, 1 pg_viol, 2 mis_nonff, 3 early_c, 4 early_s, 5 cacc, 6 sacc, 7 rd stalls with held reads,
    --       8 rd stalls whose 2nd and 3rd held read both mismatched, 9 rd stalls whose held byte is $FF,
    --       10 DMA-served CPU halves with AEC
    variable n_norm, norm_viol, c2a_viol, rep_viol, unserved, mis_out, ev_cnt, held_ev : natural := 0;
    variable norm_min : integer := 99;
    variable norm_max : integer := -1;
    variable f_a, f_rw, f_d, p_a, p_rw, p_d, dma_cyc, dma_cyc_low, we_dma : natural := 0;
    variable we_t    : t_m(0 to 0, 0 to 31) := (others => (others => 0));
    variable n_stall_lines : t_m(0 to 1, 0 to 0) := (others => (others => 0));
    variable printed : boolean := false;
    variable a : unsigned(15 downto 0);
    variable w_addr  : integer := -1;    -- address of the FPGA's RAM write in this cycle (tick 28)
    variable lost_w, w_hist_n : natural := 0;
    variable s_hist  : string(1 to 5);   -- core_dma_last_we, prev_we, prev_valid, grace_armed, grace_rd at the BA fall

    procedure stat(name : string; v : integer) is
    begin
      report "STAT " & TAG & " " & name & " " & integer'image(v);
    end;
    function cname(c : natural) return string is begin if c = 0 then return "badline"; else return "sprite "; end if; end;
    function kname(k : natural) return string is
    begin
      if k = 1 then return "verify"; elsif k = 2 then return "fetch "; else return "none  "; end if;
    end;
  begin
    if rising_edge(clk_main_i) then
      t := tb_p_cycle;

      -- replica of the VIC-II's baCnt from its ports (ba, phi, enaData); in phi2 addrValid = baCnt(2)
      if tb_p_phi0 = '1' and ((rep = 4) /= (tb_p_aec = '1')) then rep_viol := rep_viol + 1; end if;
      if core_ba = '0' then
        if tb_p_phi0 = '0' and tb_p_enaVic = '1' and rep < 4 then rep := rep + 1; end if;
      else
        rep := 0;
      end if;

      -- C2: a DMA-served CPU half must never be one in which the VIC-II's address is valid
      if core_dma_cycle = '1' then
        dma_cyc := dma_cyc + 1;
        if tb_p_aec = '1' then
          c2a_viol := c2a_viol + 1; c_c2a := c_c2a + 1;
          if c2a_viol <= 5 then
            report "C2VIOL " & TAG & " aec=1 in a DMA cycle: line " & integer'image(to_integer(tb_p_debugY)) &
                   " lcyc " & integer'image(tb_lcyc) & " tick " & integer'image(t) & " BA-low cycle " & integer'image(lowidx);
          end if;
        end if;
      end if;
      if t = 0 then w_addr := -1; end if;
      if c64_ram_we_o = '1' and tb_p_dma_active = '1' then
        we_dma := we_dma + 1; we_t(0, t) := we_t(0, t) + 1;
        w_addr := to_integer(c64_ram_addr_o);
      end if;
      if t = 1 and core_ba = '0' and core_ba_q = '1' then
        s_hist := b(core_dma_last_we) & b(core_dma_prev_we) & b(core_dma_prev_valid) & b(core_dma_grace_armed) & b(core_dma_last_valid);
      end if;

      -- bus fights between the FPGA and the REC model
      if cart_addr_oe_o = '1' and tb_rec_a_oe = '1' then
        if cart_a_o /= tb_rec_a then f_a := f_a + 1; else p_a := p_a + 1; end if;
      end if;
      -- BA-low index of the cycle this tick belongs to (BA changes at the edge into tick 1)
      if t >= 20 or t = 0 then cur_idx := lowidx; elsif core_ba = '0' then cur_idx := lowidx + 1; else cur_idx := 0; end if;
      if cart_ctrl_oe_o = '1' and tb_rec_rw_oe = '1' then
        if cart_rw_o /= tb_rec_rw then
          f_rw := f_rw + 1;
          if core_ba = '0' and core_dma_grace = '1' then br := 2; elsif core_ba = '0' then br := 0; else br := 1; end if;
          fr_h(br * 6 + minimum(cur_idx, 5), t) := fr_h(br * 6 + minimum(cur_idx, 5), t) + 1;
        else
          p_rw := p_rw + 1;
        end if;
      end if;
      if cart_data_oe_o = '1' and tb_rec_d_oe = '1' then
        if cart_d_o /= tb_rec_d then
          f_d := f_d + 1;
          if f_d <= 6 then
            report "FIGHT " & TAG & " D: FPGA=$" & h(cart_d_o) & " REC=$" & h(tb_rec_d) & " tick " & integer'image(t) &
                   " BA-low cycle " & integer'image(lowidx) & " line " & integer'image(to_integer(tb_p_debugY)) & " lcyc " & integer'image(tb_lcyc);
          end if;
        else
          p_d := p_d + 1;
        end if;
      end if;

      -- C3: data the FPGA drives to the cartridge, per tick of the cycle
      cond := false;
      if not is_x(cart_in_a_q) and not is_x(cart_d_o) then
        cond := cart_data_oe_o = '1' and cart_d_o = tb_shadow.get(to_integer(cart_in_a_q));
      end if;
      if t = 0 then run_d := -1; run_off := -1; oe_cpu := false; end if;
      if t <= 30 then
        if cond then
          if run_d < 0 then run_d := t; end if;
        else
          run_d := -1;
        end if;
        if cart_data_oe_o = '0' then
          if run_off < 0 then run_off := t; end if;
        else
          run_off := -1;
        end if;
        if t >= 16 and cart_data_oe_o = '1' then oe_cpu := true; end if;
      end if;

      if t = 20 then
        s_ba := core_ba; s_dma := core_dma_cycle; s_grace := core_dma_grace; s_grace_rd := core_dma_grace_rd;
        s_rw := cart_in_rw_q; s_on := tb_rec_on;
        if s_dma = '1' and s_ba = '0' then dma_cyc_low := dma_cyc_low + 1; end if;
        if s_ba = '0' then
          if lowidx = 0 then
            c_kind := tb_rec_kind; c_first_aec := 0; c_pg_idx := 0; c_pg_off := -1; c_granted := 0;
            c_early_c := 0; c_early_s := 0; c_cacc := 0; c_sacc := 0; c_pg_viol := 0; c_gviol := 0; c_held := 0;
            c_mis_nonff := 0; c_line := to_integer(tb_p_debugY); c_lcyc := tb_lcyc; c_held_exp := x"00"; c_c2a := 0;
            c_fv_min := (others => (others => 99)); c_fv_max := (others => (others => -1));
            c_mis := (others => (others => 0));
            gidx := 0;
          end if;
          lowidx := lowidx + 1;
          if s_dma = '1' then c_granted := c_granted + 1; end if;
          if tb_p_aec = '1' and c_first_aec = 0 then c_first_aec := lowidx; end if;
        elsif lowidx > 0 then
          -- the stall has ended: classify it and add it to the totals
          if lowidx >= 40 then cls := 0; else cls := 1; end if;
          st_n(cls, c_kind) := st_n(cls, c_kind) + 1;
          gr_hist(cls * 3 + c_kind, minimum(gidx, 5)) := gr_hist(cls * 3 + c_kind, minimum(gidx, 5)) + 1;
          if lowidx >= 4 then aec_h(cls, minimum(c_first_aec, 5)) := aec_h(cls, minimum(c_first_aec, 5)) + 1; end if;
          for i in 1 to 4 loop
            if c_fv_max(0, i) >= 0 then
              fv_n(cls, i) := fv_n(cls, i) + 1;
              fv_min(cls, i) := minimum(fv_min(cls, i), c_fv_min(0, i));
              fv_max(cls, i) := maximum(fv_max(cls, i), c_fv_max(0, i));
            end if;
          end loop;
          for i in 0 to 3 loop mis(cls, i) := mis(cls, i) + c_mis(0, i); end loop;
          if gidx > 0 then
            pg_h(cls, minimum(c_pg_idx, 5)) := pg_h(cls, minimum(c_pg_idx, 5)) + 1;
            if c_pg_idx > 0 then
              pgo_min(cls, 0) := minimum(pgo_min(cls, 0), c_pg_off);
              pgo_max(cls, 0) := maximum(pgo_max(cls, 0), c_pg_off);
            end if;
          end if;
          k1(cls, 0) := k1(cls, 0) + c_gviol;
          k1(cls, 1) := k1(cls, 1) + c_pg_viol;
          k1(cls, 2) := k1(cls, 2) + c_mis_nonff;
          k1(cls, 3) := k1(cls, 3) + c_early_c;
          k1(cls, 4) := k1(cls, 4) + c_early_s;
          k1(cls, 5) := k1(cls, 5) + c_cacc;
          k1(cls, 6) := k1(cls, 6) + c_sacc;
          k1(cls, 10) := k1(cls, 10) + c_c2a;
          if c_kind = 1 and c_held > 0 then
            k1(cls, 7) := k1(cls, 7) + 1;
            if c_mis(0, 2) > 0 and c_mis(0, 3) > 0 then k1(cls, 8) := k1(cls, 8) + 1; end if;
            if c_held_exp = x"FF" then k1(cls, 9) := k1(cls, 9) + 1; end if;
          end if;
          if c_kind /= 0 and n_stall_lines(cls, 0) < 8 then
            n_stall_lines(cls, 0) := n_stall_lines(cls, 0) + 1;
            report "STALL " & TAG & " " & cname(cls) & " REC " & kname(c_kind) & " line " & integer'image(c_line) &
                   " lcyc " & integer'image(c_lcyc) & " BA-low cycles " & integer'image(lowidx) &
                   " | DMA-served BA-low cycles " & integer'image(c_granted) & ", grace " & integer'image(gidx) &
                   " | first phi2 with AEC: BA-low cycle " & integer'image(c_first_aec) &
                   " | data valid from tick (grace 1/2/3) " & integer'image(c_fv_min(0, 1)) & "/" &
                   integer'image(c_fv_min(0, 2)) & "/" & integer'image(c_fv_min(0, 3)) &
                   " | first unserved BA-low cycle " & integer'image(c_pg_idx) & ", data released from tick " & integer'image(c_pg_off) &
                   ", driven in its CPU half: " & integer'image(c_pg_viol) &
                   " | REC held reads " & integer'image(c_held) & " (byte $" & h(c_held_exp) & "), mismatches counted/held1/held2/held3 " &
                   integer'image(c_mis(0, 0)) & "/" & integer'image(c_mis(0, 1)) & "/" & integer'image(c_mis(0, 2)) & "/" & integer'image(c_mis(0, 3)) &
                   " | VIC phi2 samples with AEC: screen " & integer'image(c_cacc) & ", sprite data " & integer'image(c_sacc);
          end if;
          lowidx := 0; gidx := 0;
        end if;
      end if;

      if t = 30 then
        if s_ba = '1' and s_dma = '1' and s_rw = '1' and s_on = '1' then
          n_norm := n_norm + 1;
          norm_min := minimum(norm_min, run_d); norm_max := maximum(norm_max, run_d);
          if run_d < 0 or run_d > 20 then norm_viol := norm_viol + 1; end if;
        elsif s_ba = '0' and s_grace = '1' and s_dma = '1' then
          gidx := gidx + 1;
          if s_grace_rd = '1' then
            g := minimum(gidx, 4);
            if run_d >= 0 then
              c_fv_min(0, g) := minimum(c_fv_min(0, g), run_d); c_fv_max(0, g) := maximum(c_fv_max(0, g), run_d);
            else
              c_fv_max(0, g) := 99; c_fv_min(0, g) := minimum(c_fv_min(0, g), 99);
            end if;
            if run_d < 0 or run_d > 20 then c_gviol := c_gviol + 1; end if;
          end if;
        elsif s_ba = '0' and s_grace = '0' and gidx > 0 and c_pg_idx = 0 then
          c_pg_idx := lowidx; c_pg_off := run_off;
          if oe_cpu then c_pg_viol := c_pg_viol + 1; end if;
        end if;
      end if;

      if t = 31 then
        -- the VIC-II samples its data bus in phi2 at this tick (enaData, phi = 1)
        if tb_p_enaVic = '1' and tb_p_phi0 = '1' and lowidx > 0 then
          a := tb_p_vicAddr;
          if tb_p_aec = '1' then
            if a >= x"0400" and a <= x"07E7" then c_cacc := c_cacc + 1; end if;
            if a >= x"3000" and a <= x"31FF" then c_sacc := c_sacc + 1; end if;
          else
            if a >= x"0400" and a <= x"07E7" then c_early_c := c_early_c + 1; end if;
            if a >= x"3000" and a <= x"31FF" then c_early_s := c_early_s + 1; end if;
          end if;
        end if;
        if tb_ev_valid = '1' then
          ev_cnt := ev_cnt + 1;
          if tb_ev_counted = '1' and s_dma = '0' then
            unserved := unserved + 1;
            if unserved <= 5 then
              report "UNSERVED " & TAG & " counted REC access in a cycle the FPGA did not serve: $" & h(tb_ev_addr) &
                     " line " & integer'image(to_integer(tb_p_debugY)) & " lcyc " & integer'image(tb_lcyc);
            end if;
          end if;
          if tb_ev_rd = '0' and tb_ev_counted = '1' and w_addr /= to_integer(tb_ev_addr) then
            lost_w := lost_w + 1;
            if lost_w <= 5 then
              report "LOSTWRITE " & TAG & " counted REC write to $" & h(tb_ev_addr) & " not written (FPGA RAM write: " &
                     integer'image(w_addr) & ") BA-low cycle " & integer'image(lowidx) & " served " & b(s_dma) &
                     " grace " & b(s_grace) & " grace_rd " & b(s_grace_rd) &
                     " | at the BA fall last_we/prev_we/prev_valid/armed/last_valid = " & s_hist &
                     " line " & integer'image(to_integer(tb_p_debugY)) & " lcyc " & integer'image(tb_lcyc);
            end if;
          end if;
          if tb_ev_rd = '1' and tb_ev_counted = '0' and lowidx > 0 then
            c_held := c_held + 1; held_ev := held_ev + 1;
            if tb_ev_pos = 1 then c_held_exp := tb_ev_exp; end if;
          end if;
          if tb_ev_rd = '1' and tb_ev_mis = '1' then
            if lowidx > 0 then
              c_mis(0, minimum(tb_ev_pos, 3)) := c_mis(0, minimum(tb_ev_pos, 3)) + 1;
              if tb_ev_val /= x"FF" then c_mis_nonff := c_mis_nonff + 1; end if;
            else
              mis_out := mis_out + 1;
            end if;
            if mis(0, 0) + mis(0, 1) + mis(0, 2) + mis(0, 3) + mis(1, 0) + mis(1, 1) + mis(1, 2) + mis(1, 3) + mis_out < 6 and
               c_mis(0, 0) + c_mis(0, 1) + c_mis(0, 2) + c_mis(0, 3) <= 2 then
              report "MIS " & TAG & " $" & h(tb_ev_addr) & " got $" & h(tb_ev_val) & " expected $" & h(tb_ev_exp) &
                     " held read " & integer'image(tb_ev_pos) & " (0 = counted) BA-low cycle " & integer'image(lowidx) &
                     " line " & integer'image(to_integer(tb_p_debugY)) & " lcyc " & integer'image(tb_lcyc);
            end if;
          end if;
        end if;
      end if;

      if tb_stop and not printed then
        printed := true;
        for c in 0 to 1 loop
          for k in 0 to 2 loop
            stat("stalls_" & cname(c)(1 to 3) & "_" & kname(k)(1 to 3), st_n(c, k));
            for n in 0 to 5 loop stat("grace_" & cname(c)(1 to 3) & "_" & kname(k)(1 to 3) & "_" & integer'image(n), gr_hist(c * 3 + k, n)); end loop;
          end loop;
          for n in 0 to 5 loop stat("firstaec_" & cname(c)(1 to 3) & "_" & integer'image(n), aec_h(c, n)); end loop;
          for n in 0 to 5 loop stat("postgrace_" & cname(c)(1 to 3) & "_" & integer'image(n), pg_h(c, n)); end loop;
          stat("postgrace_off_min_" & cname(c)(1 to 3), pgo_min(c, 0));
          stat("postgrace_off_max_" & cname(c)(1 to 3), pgo_max(c, 0));
          for i in 1 to 4 loop
            stat("fv_n_" & cname(c)(1 to 3) & "_" & integer'image(i), fv_n(c, i));
            stat("fv_min_" & cname(c)(1 to 3) & "_" & integer'image(i), fv_min(c, i));
            stat("fv_max_" & cname(c)(1 to 3) & "_" & integer'image(i), fv_max(c, i));
          end loop;
          for i in 0 to 3 loop stat("mis_" & cname(c)(1 to 3) & "_" & integer'image(i), mis(c, i)); end loop;
          stat("gviol_" & cname(c)(1 to 3), k1(c, 0));
          stat("pgviol_" & cname(c)(1 to 3), k1(c, 1));
          stat("misnonff_" & cname(c)(1 to 3), k1(c, 2));
          stat("earlyc_" & cname(c)(1 to 3), k1(c, 3));
          stat("earlys_" & cname(c)(1 to 3), k1(c, 4));
          stat("cacc_" & cname(c)(1 to 3), k1(c, 5));
          stat("sacc_" & cname(c)(1 to 3), k1(c, 6));
          stat("rdstalls_" & cname(c)(1 to 3), k1(c, 7));
          stat("rdstalls_mis23_" & cname(c)(1 to 3), k1(c, 8));
          stat("rdstalls_ff_" & cname(c)(1 to 3), k1(c, 9));
          stat("c2a_" & cname(c)(1 to 3), k1(c, 10));
        end loop;
        stat("lost_writes", lost_w);
        stat("norm_n", n_norm); stat("norm_min", norm_min); stat("norm_max", norm_max); stat("norm_viol", norm_viol);
        stat("c2a_viol", c2a_viol); stat("rep_viol", rep_viol); stat("unserved", unserved); stat("mis_out", mis_out);
        stat("events", ev_cnt); stat("held_events", held_ev);
        stat("fight_a", f_a); stat("fight_rw", f_rw); stat("fight_d", f_d);
        stat("par_a", p_a); stat("par_rw", p_rw); stat("par_d", p_d);
        stat("dma_cycles", dma_cyc); stat("dma_cycles_ba_low", dma_cyc_low); stat("ram_we_ticks_dma", we_dma);
        for i in 0 to 31 loop
          if we_t(0, i) > 0 then stat("ram_we_tick_" & integer'image(i), we_t(0, i)); end if;
        end loop;
        for i in 0 to 17 loop
          for j in 0 to 31 loop
            if fr_h(i, j) > 0 then
              stat("fightrw_" & integer'image(i / 6) & "_" & integer'image(i mod 6) & "_" & integer'image(j), fr_h(i, j));
            end if;
          end loop;
        end loop;
        stat("xfers_done", tb_xfers_done); stat("xfers", C_TB_XFERS'length);
        stat("cpu_pc", tb_p_cpu_pc); stat("cpu_prog_len", C_TB_CPU_PROG'length);
      end if;
    end if;
  end process;

  -- ===== traces for C1: VIC-II pixel outputs per enaPixel, and every VIC-II data sample with AEC =====
  tb_trace : process (clk_main_i)
    file fp : text open write_mode is TAG & ".pix";
    file ff : text open write_mode is TAG & ".fetch";
    variable l : line;
    variable closed : boolean := false;
  begin
    if rising_edge(clk_main_i) and not closed then
      if tb_stop then
        file_close(fp); file_close(ff); closed := true;
      else
        if tb_p_enaPix = '1' then
          write(l, to_hstring(tb_p_colorIndex) & " " & b(vga_hs) & b(vga_vs));
          writeline(fp, l);
        end if;
        if tb_p_enaVic = '1' and tb_p_aec = '1' then
          write(l, to_hstring(tb_p_vicAddr) & " " & to_hstring(tb_p_vicDi) & " " & to_hstring(tb_p_vicColor) & " " & b(tb_p_phi0));
          writeline(ff, l);
        end if;
      end if;
    end if;
  end process;

  -- ===== end: three complete frames (0 settles, the transfers run in 1 and 2), then read the RAM back =====
  tb_ctrl : process
    variable diffs : natural := 0;
  begin
    wait until tb_frame = 3;
    tb_stop <= true;
    for i in 1 to 4 loop wait until rising_edge(clk_main_i); end loop;
    for i in 0 to 65535 loop
      tb_ramb_addr <= std_logic_vector(to_unsigned(i, 16));
      wait until falling_edge(clk_main_i);
      wait for 1 ns;
      if unsigned(tb_ramb_q) /= tb_shadow.get(i) then
        diffs := diffs + 1;
        if diffs <= 8 then
          report "RAMDIFF " & TAG & " $" & h(to_unsigned(i, 16)) & " RAM $" & h(unsigned(tb_ramb_q)) & " expected $" & h(tb_shadow.get(i));
        end if;
      end if;
    end loop;
    report "STAT " & TAG & " ram_diffs " & integer'image(diffs);
    report "STAT " & TAG & " end_ns " & integer'image(now / 1 ns);
    tb_done <= true;
    wait;
  end process;
'''

# ------------------------------------------------------------------------------------------------
# 5. write the variants
# ------------------------------------------------------------------------------------------------
for g in (3, 1, 4):
    ent = f"tb_vicdma_g{g}"
    d = decls if g == 3 else decls.replace(GRACE_DECL, f"constant C_CART_DMA_GRACE_RD_CYCLES : natural := {g}; -- [tb_vicdma] variant")
    txt = TB.replace("@MONITOR@", MON).replace("@DECLS@", d).replace("@SPLICED@", spliced).replace("@ENT@", ent).replace("@G@", str(g))
    open(os.path.join(out, ent + ".vhd"), "w").write(txt)

print(f"gen_tb.py: fpga64_sid_iec: cpu/sid/cia1/cia2 replaced by stubs (and the fpga64_rgbcolor LUT), power-up '0' for {len(inits)} registers")
print(f"gen_tb.py: main.vhd: {len(pieces)} pieces spliced, {len(lines)} declarations extracted, {len(ties)} inputs tied off:")
print("    " + ", ".join(ties))
print("gen_tb.py: generated tb_vicdma_g3 (as written), tb_vicdma_g1 (A24), tb_vicdma_g4 (negative control)")
