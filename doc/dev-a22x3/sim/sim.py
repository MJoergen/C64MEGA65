#!/usr/bin/env python3
"""
Driver for the full-system simulation of the QNICE subsystem (tb/qsys_tb.vhd).

    sim.py build [--cfg NAME] [--sim ghdl|nvc]
        Prepare the sources (WORK/<cfg>/src: patched copies, see below) and
        analyze them: GHDL produces the binary WORK/<cfg>/qsys_tb, nvc the
        library WORK/<cfg>/nvclib. The configuration "default" uses the
        unmodified CORE/vhdl/config.vhd; other configurations are defined in
        CONFIG_PATCHES and use a patched copy (fatal error scenarios).

    sim.py run SCENARIO VARIANT [--cfg NAME] [--sim ghdl|nvc] [--sd FILE.blk]
                                [--timeout SECONDS] [--tag TAG]
        Run the script scenarios/SCENARIO.stim with the ROM set VARIANT (see
        ROMSETS) and collect the output in RUNS/SCENARIO[-TAG]/VARIANT_<sim>/.

The firmware ROM and the string ROM are found by the design via relative file
names (QNICE_FIRMWARE in globals.vhd: ../../../CORE/m2m-rom/m2m-rom.rom,
C_STRROM_FILE in qnice_wrapper.vhd: ../../CORE/m2m-rom/m2m-strings.rom), which
the simulators resolve against the working directory of the run. Each run
therefore gets a directory tree of its own:

    <run>/CORE/m2m-rom/m2m-rom.rom           firmware ROM
    <run>/M2M/CORE/m2m-rom/m2m-strings.rom   string ROM
    <run>/M2M/QNICE/vhdl/                    working directory of the simulator

Two variants of a scenario differ in these two files only.

Sources that are not used as they are in the repository (all other files are
analyzed in place):

    register_file.vhd  power-up value zero for the CPU registers (REGFILE_INIT)
    block_rom.vhd      GHDL syntax patch (VHDL-87 file declaration)
    cycle_counter.vhd  GHDL syntax patch (case without others) and time
                       compression (CYC_SPEEDUP)
    qnice_wrapper.vhd  range guards for the simulation (RANGE_GUARDS)
    config.vhd         range guards for the simulation (RANGE_GUARDS)
    sdcard.vhd         entity of the repository, architecture replaced by the
                       behavioral model tb/sdcard_model_arch.vhd
    config.vhd         in addition, for configurations other than "default": the
                       deliberate defects of the fatal error scenarios
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.dirname(HERE)                                 # SCR/out/A
SCR = os.path.dirname(os.path.dirname(OUT))
REPO = os.path.join(SCR, "wtA")
WORK = os.path.join(OUT, "work")
RUNS = os.path.join(OUT, "runs")
GHDL = shutil.which("ghdl") or "/usr/local/bin/ghdl"
NVC = shutil.which("nvc") or "/usr/local/bin/nvc"
GHDL_OPTS = ["--std=08", "-frelaxed", "-fsynopsys", "-O3"]
NVC_OPTS = ["--std=2008", "-M", "256m", "-H", "2g"]
MAX_SIM_OUTPUT = 20 * 1024 * 1024               # bytes of simulator messages per run

# design files in analysis order
VHDL = [
    "M2M/vhdl/QNICE/qnice_globals.vhd",
    "M2M/QNICE/vhdl/tools.vhd",
    "M2M/QNICE/vhdl/cpu_constants.vhd",
    "M2M/QNICE/vhdl/alu_shifter.vhd",
    "M2M/QNICE/vhdl/alu.vhd",
    "M2M/QNICE/vhdl/register_file.vhd",
    "M2M/QNICE/vhdl/qnice_cpu.vhd",
    "M2M/QNICE/vhdl/block_rom.vhd",            # GHDL patch
    "M2M/QNICE/vhdl/block_ram.vhd",
    "M2M/QNICE/vhdl/fifo.vhd",
    "M2M/QNICE/vhdl/basic_uart.vhd",
    "M2M/QNICE/vhdl/bus_uart.vhd",
    "M2M/QNICE/vhdl/EAE.vhd",
    "M2M/QNICE/vhdl/sdcard.vhd",               # entity of the file + behavioral model
    "M2M/QNICE/vhdl/cycle_counter.vhd",        # GHDL patch, time compression
    "M2M/vhdl/QNICE/qnice_mmio.vhd",
    "M2M/vhdl/QNICE/sdmux.vhd",
    "M2M/vhdl/QNICE/qnice.vhd",
    "M2M/vhdl/av_pipeline/video_modes_pkg.vhd",
    "M2M/vhdl/controllers/HDMI/types_pkg.vhd",
    "CORE/vhdl/globals.vhd",
    "CORE/vhdl/config.vhd",                    # optionally a patched copy (CONFIG_PATCHES)
    "M2M/vhdl/tdp_ram.vhd",
    "M2M/vhdl/2port2clk_ram.vhd",
    "M2M/vhdl/2port2clk_ram_byteenable.vhd",
    "M2M/vhdl/qnice2hyperram.vhd",
    "M2M/vhdl/qnice_csr.vhd",                  # cartridge device of the testbench
    "CORE/vhdl/sw_cartridge_csr.vhd",
    "CORE/vhdl/crt_parser.vhd",
    "M2M/vhdl/controllers/M65/mouse_input.vhdl",
    "M2M/vhdl/qnice_wrapper.vhd",
]

# Syntax that Vivado accepts and GHDL rejects in VHDL-2008 mode
GHDL_PATCHES = {
    "block_rom.vhd": [(r"file\s+rom_file\s*:\s*text\s+is\s+in\s+rom_file_name;",
                       "file rom_file : text open read_mode is rom_file_name;")],
    "cycle_counter.vhd": [(r"(\n(\s*)when \"11\" => [^\n]*\n)",
                           "\\1\\2when others => null;\n")],
}

# Time compression: the 48-bit cycle counter of QNICE (IO$CYC_LO/MID/HI) counts
# CYC_SPEEDUP per clock cycle instead of 1. All waits of the firmware that are
# measured with this counter (2 s before the first SD card access, 2.5 s before
# the core info is logged, SD card timeouts) take CYC_SPEEDUP times fewer clock
# cycles. Busy loops (WAIT333MS, WAIT1SEC) and the UART are not affected. The
# same patched file is used for all firmware variants.
CYC_SPEEDUP = 32
CYC_PATCH = (r"counter <= counter \+ 1;", "counter <= counter + %d;   -- simulation: time compression")

# Power-up value of the CPU registers. The register file of the QNICE CPU has
# no initial value in the source. On the FPGA it is a RAM that powers up with
# zeros; in a simulation it starts as 'U', and the firmware clears registers
# with "XOR Rx, Rx", which stays 'U' forever ('U' xor 'U' = 'U'). Without this
# patch both firmwares print "ROM #:" instead of "ROM #0000:" and stop making
# progress about 103 ms after reset.
REGFILE_INIT = [
    ("signal LowerRegisterWindow : rega;",
     "signal LowerRegisterWindow : rega := (others => (others => '0'));   -- simulation: power-up value"),
    ("signal UpperRegisters      : upper_register_array;",
     "signal UpperRegisters      : upper_register_array := (others => (others => '0'));   -- simulation: power-up value"),
]

# Range guards. The design reads constant arrays with an index that comes
# straight from the address bus. While the 4k window is not addressed, or the
# firmware does not read these arrays, the index is arbitrary: synthesis does
# not care (the value is not used), but a simulator stops with a range error.
# The guards replace an out-of-range index by a defined value and leave every
# in-range read as it is. They are plain text replacements; each one has to
# match exactly the given number of times.
#
# qnice_wrapper.vhd, names of the auto-load ROMs: the original expression
#     to_integer(unsigned(qnice_ramrom_addr_o(15 downto 0))) - 16#7300# + 1
# is negative for every address, because bits 15..12 of qnice_ramrom_addr_o
# belong to the window selector (0x0020) and not to the CPU address 0x7xxx.
# Hardware returns the right characters because only the low bits of the index
# reach the ROM. The guard uses bits 11..0 minus 0x300, which is the same index.
RANGE_GUARDS = {
    "qnice_wrapper.vhd": [
        ("      variable strpos      : natural;",
         "      variable strpos      : integer;   -- simulation: range guard", 1),
        ("""                           if qnice_ramrom_addr_o(11 downto 4) = x"10" then""",
         """                           if qnice_ramrom_addr_o(11 downto 4) = x"10" and   -- simulation: range guard
                              to_integer(unsigned(qnice_ramrom_addr_o(3 downto 0))) <= C_VD_BUFFER'high then""", 1),
        ("""                     elsif qnice_ramrom_addr_o(11 downto 8) = x"1" then""",
         """                     elsif qnice_ramrom_addr_o(11 downto 8) = x"1" and   -- simulation: range guard
                           to_integer(unsigned(qnice_ramrom_addr_o(7 downto 0))) <= C_CRTROMS_MAN'high then""", 1),
        ("""                     elsif qnice_ramrom_addr_o(11 downto 8) = x"2" then""",
         """                     elsif qnice_ramrom_addr_o(11 downto 8) = x"2" and   -- simulation: range guard
                           to_integer(unsigned(qnice_ramrom_addr_o(7 downto 0))) <= C_CRTROMS_AUTO'high then""", 1),
        ("""                        strpos := to_integer(unsigned(qnice_ramrom_addr_o(15 downto 0))) - 16#7300# + 1;
                        qnice_ramrom_data_in <= std_logic_vector(to_unsigned(character'pos(C_CRTROMS_AUTO_NAMES(strpos)), 16));""",
         """                        strpos := to_integer(unsigned(qnice_ramrom_addr_o(11 downto 0))) - 16#300# + 1;   -- simulation: range guard
                        if strpos <= C_CRTROMS_AUTO_NAMES'length then
                           qnice_ramrom_data_in <= std_logic_vector(to_unsigned(character'pos(C_CRTROMS_AUTO_NAMES(strpos)), 16));
                        end if;""", 1),
    ],
    "config.vhd": [
        ("   variable index           : integer;",
         "   variable index           : integer;\n   variable sim_gidx        : integer;   -- simulation: range guard", 1),
        ("      index           := to_integer(unsigned(address_i(11 downto  0)));",
         """      index           := to_integer(unsigned(address_i(11 downto  0)));
      sim_gidx        := index;                -- simulation: range guard
      if sim_gidx > OPTM_SIZE - 1 then
         sim_gidx := 0;
      end if;""", 1),
        ("OPTM_GROUPS(index)", "OPTM_GROUPS(sim_gidx)", 14),
    ],
}

# Deliberately broken variants of config.vhd for the fatal error scenarios:
# name -> list of (regular expression, replacement, expected number of matches)
CONFIG_PATCHES = {
    "default": [],
    # the firmware reads 255 as the number of menu items: FATAL with ERR_F_MENUSIZE
    "fatal_size": [
        # since #142 SEL_OPTM_ICOUNT returns 16 bits and the Shell accepts 1..512: 513 is illegal
        (r'when SEL_OPTM_ICOUNT       => data_o <= std_logic_vector\(to_unsigned\(OPTM_SIZE, 16\)\);',
         'when SEL_OPTM_ICOUNT       => data_o <= std_logic_vector(to_unsigned(513, 16));', 1),
    ],
    # the submenu "Drive Settings" has no end: FATAL_IDX with ERR_F_MENUSUB
    "fatal_sub": [
        (r'OPTM_G_CLOSE         \+ OPTM_G_SUBMENU,   -- close "Drive Settings"',
         'OPTM_G_TEXT,                             -- simulation: no end of the submenu', 1),
    ],
}

# Configurations that patch other files than config.vhd: name -> {file name: [(regular
# expression, replacement, expected number of matches)]}. A configuration that is not
# listed in CONFIG_PATCHES uses the unmodified config.vhd.
#   bank32      the state before e46bc75: 32 register banks; the simulator stops with an
#               index error in register_file.vhd as soon as the bank level reaches 32
#   bank32mod   32 register banks, and the index of the register file is taken modulo the
#               array size, as the hardware does (the bank number wraps around)
FILE_PATCHES = {
    "bank32": {
        "qnice_globals.vhd": [(r"constant SHADOW_REGFILE_SIZE  : natural   := 64;",
                               "constant SHADOW_REGFILE_SIZE  : natural   := 32;   -- simulation: before e46bc75", 1)],
    },
    "bank32mod": {
        "qnice_globals.vhd": [(r"constant SHADOW_REGFILE_SIZE  : natural   := 64;",
                               "constant SHADOW_REGFILE_SIZE  : natural   := 32;   -- simulation: before e46bc75", 1)],
        "register_file.vhd": [(r"conv_integer\(sel_rbank\)\*8\+",
                               "(conv_integer(sel_rbank) mod SHADOW_REGFILE_SIZE)*8+", 3)],
    },
}
for _k in FILE_PATCHES:
    CONFIG_PATCHES.setdefault(_k, [])

# name -> (firmware ROM, string ROM or None for an all-zero string ROM, listing of the firmware)
ROMSETS = {
    "OLD": (os.path.join(SCR, "baseline", "m2m-rom.rom"), None,
            os.path.join(SCR, "baseline", "m2m-rom.lis")),
    "NEW": (os.path.join(REPO, "CORE", "m2m-rom", "m2m-rom.rom"),
            os.path.join(REPO, "CORE", "m2m-rom", "m2m-strings.rom"),
            os.path.join(REPO, "CORE", "m2m-rom", "m2m-rom.lis")),
    # firmware of e46bc75 (before 06cda88), saved in <work>/baseline_e46 before the checkout
    "E46": (os.path.join(SCR, "baseline_e46", "m2m-rom.rom"),
            os.path.join(SCR, "baseline_e46", "m2m-strings.rom"),
            os.path.join(SCR, "baseline_e46", "m2m-rom.lis")),
}


def label_address(lis, name):
    """Address of a label from the label list at the end of a qasm listing, as 4 hex digits."""
    text = open(lis, errors="replace").read()
    text = text[text.index("Label-list:"):]
    m = re.search(r"(?<!\S)%s\s*:\s*0x([0-9A-Fa-f]{4})" % re.escape(name), text)
    if not m:
        sys.exit("FAIL: label %s not found in %s" % (name, lis))
    return m.group(1).upper()


def run(cmd, cwd, timeout):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)


def sdcard_with_model(src):
    text = open(src).read()
    m = re.search(r"^library.*?^end\s+(entity\s+)?sdcard\s*;", text, re.S | re.M | re.I)
    if not m:
        sys.exit("FAIL: entity sdcard not found in " + src)
    arch = open(os.path.join(HERE, "tb", "sdcard_model_arch.vhd")).read()
    ctx = ("\nlibrary ieee;\nuse ieee.std_logic_1164.all;\nuse ieee.numeric_std.all;\n"
           "library std;\nuse std.textio.all;\n\n")
    return m.group(0) + "\n" + ctx + arch


def prepare_sources(cfg):
    """Returns the list of files to analyze; writes the patched copies."""
    if cfg not in CONFIG_PATCHES:
        sys.exit("unknown configuration " + cfg)
    work = os.path.join(WORK, cfg)
    os.makedirs(os.path.join(work, "src"), exist_ok=True)
    files = []
    notes = []
    for rel in VHDL:
        src = os.path.join(REPO, rel)
        name = os.path.basename(rel)
        text = None
        if name == "sdcard.vhd":
            text = sdcard_with_model(src)
            notes.append(name + ": architecture replaced by tb/sdcard_model_arch.vhd")
        elif name in GHDL_PATCHES:
            text = open(src).read()
            for rx, rep in GHDL_PATCHES[name]:
                text, n = re.subn(rx, rep, text)
                if n == 0:
                    sys.exit("FAIL: GHDL patch for %s does not apply" % name)
                notes.append("%s: GHDL syntax patch, %d replacement(s) of /%s/" % (name, n, rx))
            if name == "cycle_counter.vhd" and CYC_SPEEDUP != 1:
                text, n = re.subn(CYC_PATCH[0], CYC_PATCH[1] % CYC_SPEEDUP, text)
                if n != 1:
                    sys.exit("FAIL: cycle counter speed-up patch does not apply")
                notes.append("%s: the cycle counter counts %d per clock cycle (time compression)" %
                             (name, CYC_SPEEDUP))
        elif name == "register_file.vhd":
            text = open(src).read()
            for a, b in REGFILE_INIT:
                if text.count(a) != 1:
                    sys.exit("FAIL: register file patch does not apply: " + a)
                text = text.replace(a, b)
            notes.append(name + ": registers start with zero like the RAM of the FPGA")
        elif name in RANGE_GUARDS:
            text = open(src).read()
            if name == "config.vhd":
                for rx, rep, cnt in CONFIG_PATCHES[cfg]:
                    text, n = re.subn(rx, rep, text)
                    if n != cnt:
                        sys.exit("FAIL: config patch %r applies %d times instead of %d" % (rx, n, cnt))
                if CONFIG_PATCHES[cfg]:
                    notes.append(name + ": patched for configuration " + cfg)
            for old, new, cnt in RANGE_GUARDS[name]:
                if text.count(old) != cnt:
                    sys.exit("FAIL: range guard for %s matches %d times instead of %d:\n%s" %
                             (name, text.count(old), cnt, old))
                text = text.replace(old, new.replace("\\n", "\n"))
            notes.append("%s: %d range guards for the simulation" % (name, len(RANGE_GUARDS[name])))
        for rx, rep_, cnt in FILE_PATCHES.get(cfg, {}).get(name, []):
            if text is None:
                text = open(src).read()
            text, n = re.subn(rx, rep_, text)
            if n != cnt:
                sys.exit("FAIL: patch %r of configuration %s applies %d times to %s instead of %d" %
                         (rx, cfg, n, name, cnt))
            notes.append("%s: patched for configuration %s (/%s/)" % (name, cfg, rx))
        if text is not None:
            src = os.path.join(work, "src", name)
            old = open(src).read() if os.path.exists(src) else None
            if old != text:
                with open(src, "w") as f:
                    f.write(text)
        files.append(src)
    files.append(os.path.join(HERE, "tb", "qsys_tb.vhd"))
    with open(os.path.join(work, "BUILD_NOTES.txt"), "w") as f:
        f.write("\n".join(notes) + "\n")
    return work, files, notes


def build(cfg, sim):
    work, files, notes = prepare_sources(cfg)
    t0 = time.time()
    if sim == "ghdl":
        lib = os.path.join(work, "ghdllib")
        shutil.rmtree(lib, ignore_errors=True)
        os.makedirs(lib)
        opts = GHDL_OPTS + ["--workdir=" + lib]
        steps = [[GHDL, "-a"] + opts + files,
                 [GHDL, "-e"] + opts + ["-o", os.path.join(work, "qsys_tb"), "qsys_tb"]]
    else:
        lib = os.path.join(work, "nvclib")
        shutil.rmtree(lib, ignore_errors=True)
        steps = [[NVC] + NVC_OPTS + ["--work=work:" + lib, "-a", "--relaxed"] + files]
    for step in steps:
        res = run(step, work, 1200)
        out = (res.stdout + res.stderr).strip()
        if res.returncode != 0:
            print(out[-6000:])
            sys.exit("FAIL: " + " ".join(step[:2]))
    print("built configuration %s for %s in %.1f s" % (cfg, sim, time.time() - t0))
    for n in notes:
        print("  " + n)


def last_time_ns(path):
    """Simulation time of the last line of a log file, in nanoseconds."""
    last = None
    with open(path) as f:
        for line in f:
            if line.strip():
                last = line
    if last is None:
        return 0
    m = re.match(r"\s*(\d+(\.\d+)?) ", last)             # time stamps are in microseconds
    if not m:
        return 0
    return float(m.group(1)) * 1e3


def simulate(scenario, variant, cfg="default", sim="ghdl", timeout=36000, sd=None,
             stim_text=None, romset=None, tag=None, quiet=False):
    work = os.path.join(WORK, cfg)
    fw, strings, lis = romset if romset else ROMSETS[variant]
    rundir = os.path.join(RUNS, scenario + ("-" + tag if tag else ""), variant + "_" + sim)
    shutil.rmtree(rundir, ignore_errors=True)
    cwd = os.path.join(rundir, "M2M", "QNICE", "vhdl")
    os.makedirs(cwd)
    os.makedirs(os.path.join(rundir, "CORE", "m2m-rom"))
    os.makedirs(os.path.join(rundir, "M2M", "CORE", "m2m-rom"))
    shutil.copyfile(fw, os.path.join(rundir, "CORE", "m2m-rom", "m2m-rom.rom"))
    strrom = os.path.join(rundir, "M2M", "CORE", "m2m-rom", "m2m-strings.rom")
    if strings:
        shutil.copyfile(strings, strrom)
    else:
        with open(strrom, "w") as f:                    # the old firmware never reads it
            f.write("00\n" * 16384)
    if stim_text is None:
        stim_text = open(os.path.join(HERE, "scenarios", scenario + ".stim")).read()
    # {LABEL} in a script stands for the address of this label in the firmware of the variant
    stim_text = re.sub(r"\{([A-Za-z_$][A-Za-z0-9_$]*)\}", lambda m: label_address(lis, m.group(1)), stim_text)
    with open(os.path.join(cwd, "stim.txt"), "w") as f:
        f.write(stim_text)
    if sd:
        shutil.copyfile(sd, os.path.join(cwd, "sdcard.blk"))
    if sim == "ghdl":
        binary = os.path.join(work, "qsys_tb")
        if not os.path.exists(binary):
            sys.exit("run 'sim.py build --cfg %s --sim ghdl' first" % cfg)
        cmd = [binary, "--ieee-asserts=disable-at-0", "--max-stack-alloc=0"]
    else:
        # Each run analyzes and elaborates into a library of its own, so that several runs
        # can execute at the same time (the ROM files are read when the design is elaborated).
        # G_SPY: the CPU spy of the testbench needs VHDL-2008 external names
        _, files, _ = prepare_sources(cfg)
        lib = os.path.join(rundir, "nvclib")
        # QSYS_WATCH="LABEL[+n|-n],LABEL[+n|-n]": the spy counts how often the program counter
        # reaches these two addresses of the firmware of the variant (columns w1 and w2 of spy.log)
        watch = []
        for k, expr in enumerate([e for e in os.environ.get("QSYS_WATCH", "").split(",") if e][:2]):
            m = re.match(r"^([A-Za-z_$][A-Za-z0-9_$]*)([+-]\d+)?$", expr)
            addr = int(label_address(lis, m.group(1)), 16) + int(m.group(2) or 0)
            watch.append("-gG_WATCH%d=%d" % (k + 1, addr))
        cmd = [NVC] + NVC_OPTS + ["--ieee-warnings=off-at-0", "--work=work:" + lib,
                                  "-a", "--relaxed"] + files + ["-e", "-gG_SPY=true"] + watch + ["qsys_tb", "-r", "qsys_tb"]
    # The messages of the simulator go to a file. A simulation that floods it
    # (for example with metavalue warnings after a crash of the firmware) is
    # stopped, so that it can neither fill the disk nor run forever.
    t0 = time.time()
    outpath = os.path.join(rundir, "sim_output.txt")
    note = ""
    with open(outpath, "w") as outf:
        proc = subprocess.Popen(cmd, cwd=cwd, stdout=outf, stderr=subprocess.STDOUT)
        while True:
            try:
                rc = proc.wait(timeout=2)
                break
            except subprocess.TimeoutExpired:
                pass
            if os.path.getsize(outpath) > MAX_SIM_OUTPUT:
                note = "STOPPED: more than %d bytes of simulator messages\n" % MAX_SIM_OUTPUT
            elif time.time() - t0 > timeout:
                note = "STOPPED: timeout after %d s\n" % timeout
            if note:
                proc.kill()
                proc.wait()
                rc = -1
                break
    wall = time.time() - t0
    with open(outpath, errors="replace") as f:
        out = f.read()
    if note:
        out += note
        with open(outpath, "a") as f:
            f.write(note)
    shutil.rmtree(os.path.join(rundir, "nvclib"), ignore_errors=True)
    # collect the output files next to the ROM tree
    for name in sorted(os.listdir(cwd)):
        if name != "sdcard.blk":
            shutil.move(os.path.join(cwd, name), os.path.join(rundir, name))
    sim_ns = 0
    ev = os.path.join(rundir, "events.log")
    if os.path.exists(ev):
        sim_ns = last_time_ns(ev)
    cycles = sim_ns / 20.0
    with open(os.path.join(rundir, "run_info.txt"), "w") as f:
        f.write("scenario %s variant %s cfg %s simulator %s\n" % (scenario, variant, cfg, sim))
        f.write("firmware ROM %s\nstring ROM %s\nSD card %s\n" % (fw, strings or "all zero", sd or "none"))
        f.write("cycle counter speed-up %d\n" % CYC_SPEEDUP)
        f.write("exit code %d\nwall time %.1f s\nsimulated time %.3f ms = %d clock cycles\n" %
                (rc, wall, sim_ns / 1e6, cycles))
        if wall > 0:
            f.write("speed %.0f clock cycles per second\n" % (cycles / wall))
    if not quiet:
        print("%s/%s_%s: exit code %d, %.1f s wall, %.3f ms simulated, %.0f cycles/s" %
              (scenario, variant, sim, rc, wall, sim_ns / 1e6, cycles / wall if wall else 0))
        for l in [l for l in out.splitlines() if l.strip()][-6:]:
            print("   | " + l[:300])
    return rc


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build")
    b.add_argument("--cfg", default="default")
    b.add_argument("--sim", default="ghdl", choices=["ghdl", "nvc"])
    r = sub.add_parser("run")
    r.add_argument("scenario")
    r.add_argument("variant")
    r.add_argument("--cfg", default="default")
    r.add_argument("--sim", default="ghdl", choices=["ghdl", "nvc"])
    r.add_argument("--timeout", type=int, default=36000)
    r.add_argument("--sd", default=None)
    r.add_argument("--tag", default=None)
    args = ap.parse_args()
    if args.cmd == "build":
        build(args.cfg, args.sim)
    else:
        rc = simulate(args.scenario, args.variant, args.cfg, args.sim, args.timeout, args.sd, tag=args.tag)
        sys.exit(1 if rc else 0)


if __name__ == "__main__":
    main()
