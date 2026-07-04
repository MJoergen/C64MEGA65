#!/usr/bin/env python3
"""
make_release.py — Package a C64MEGA65 release.

Given a release name (e.g. V6, V6.1, WIP-V6-A6, WIP-V6-A13X1, or with
--ignore an ad-hoc name such as A15test1) and an output folder, this script
validates the version string against config.vhd, sanity-checks alpha releases
against doc/inofficial.md and the git history unless --ignore was passed,
copies the per-board bitstreams from CORE/CORE-R{3..6}.runs/impl_1/, produces
.cor files via the external `coretool` or `bit2core` tool, generates the
`c64mega65-<version>` config file via M2M/tools/make_config.sh, and copies
VERSIONS.md into the release folder. Alpha releases also copy
doc/inofficial.md (timestamps preserved).

By default the script prints only the final release summary; pass
--verbatim to print the full step-by-step log.
"""

import argparse
import datetime as _dt
import os
import re
import shlex
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

CORE_NAME       = "C64 for MEGA65"
CORE_FILE_BASE  = "C64MEGA65"
BIT2CORE_TAIL   = "=default,c64cart+c64cart"
CORETOOL_FLAGS  = "c64cart"
CORETOOL_CAPS   = "c64cart,default"
BOARD_REVS      = ("R3", "R4", "R5", "R6")

# Regex for the three accepted version conventions.
RE_MAJOR = re.compile(r"^V(\d+)$")
RE_MINOR = re.compile(r"^V(\d+)\.(\d+)$")
RE_ALPHA = re.compile(r"^WIP-V(\d+)-A(\d+)(?:X([1-9]\d*))?$")


# ---------------------------------------------------------------------------
# Colored output (cross-platform)
# ---------------------------------------------------------------------------

def _supports_color() -> bool:
    if os.environ.get("NO_COLOR"):
        return False
    if not sys.stdout.isatty():
        return False
    if sys.platform == "win32":
        # Try to enable VT mode on Windows 10+. If it fails, fall back to no color.
        try:
            import ctypes
            kernel32 = ctypes.windll.kernel32
            handle = kernel32.GetStdHandle(-11)
            mode = ctypes.c_ulong()
            if not kernel32.GetConsoleMode(handle, ctypes.byref(mode)):
                return False
            kernel32.SetConsoleMode(handle, mode.value | 0x0004)
            return True
        except Exception:
            return False
    return True


_COLOR = _supports_color()
_VERBATIM = False


def _c(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if _COLOR else text


def set_verbatim(enabled: bool) -> None:
    global _VERBATIM
    _VERBATIM = enabled


def info(msg: str) -> None:
    if _VERBATIM:
        print(f"{_c('36', '[INFO]')} {msg}")


def ok(msg: str) -> None:
    if _VERBATIM:
        print(f"{_c('32', '[ OK ]')} {msg}")


_WARNINGS: list = []


def warn(msg: str) -> None:
    _WARNINGS.append(msg)
    if _VERBATIM:
        print(f"{_c('33', '[WARN]')} {msg}")


def err(msg: str) -> None:
    print(f"{_c('31;1', '[FAIL]')} {msg}", file=sys.stderr)


def die(msg: str, code: int = 1) -> "NoReturn":
    err(msg)
    sys.exit(code)


# ---------------------------------------------------------------------------
# Version parsing
# ---------------------------------------------------------------------------

def classify_version(name: str) -> str:
    """Return one of 'major', 'minor', 'alpha' or raise ValueError."""
    if RE_MAJOR.match(name):
        return "major"
    if RE_MINOR.match(name):
        return "minor"
    if RE_ALPHA.match(name):
        return "alpha"
    raise ValueError(
        f"'{name}' is not a valid version. Expected one of:\n"
        f"  Major  : V<n>          (e.g. V6)\n"
        f"  Minor  : V<n>.<m>      (e.g. V6.1)\n"
        f"  Alpha  : WIP-V<n>-A<m>[X<k>] (e.g. WIP-V6-A6, WIP-V6-A13X1)\n"
        f"  Or pass -i / --ignore for an ad-hoc name that is already present "
        f"in config.vhd."
    )


# ---------------------------------------------------------------------------
# Repo discovery
# ---------------------------------------------------------------------------

def find_repo_root() -> Path:
    """The script lives at <repo>/make_release.py."""
    here = Path(__file__).resolve()
    root = here.parent
    if not (root / "CORE" / "vhdl" / "config.vhd").is_file():
        die(f"Cannot locate repository root from {here} "
            f"(expected CORE/vhdl/config.vhd under {root})")
    return root


# ---------------------------------------------------------------------------
# config.vhd check
# ---------------------------------------------------------------------------

_CORE_VERSION_RE = re.compile(
    r'constant\s+CORE_VERSION\s*:\s*string\s*:=\s*"([^"]+)"\s*;'
)


def check_config_vhd(repo: Path, version: str) -> None:
    """Confirm the CORE_VERSION constant in config.vhd matches the CLI version.

    Since GitHub issue #182, the version string lives in exactly one place in
    config.vhd — the `CORE_VERSION` constant — and every welcome/help screen,
    the CORENAME serial-terminal banner, and the CFG_FILE on-SD-card filename
    derive from it via VHDL string concatenation. We parse the constant out
    and assert it matches `args.version`.
    """
    cfg = repo / "CORE" / "vhdl" / "config.vhd"
    text = cfg.read_text(encoding="utf-8", errors="replace")

    matches = _CORE_VERSION_RE.findall(text)
    if not matches:
        die(f"Could not find a `constant CORE_VERSION : string := \"...\";` "
            f"line in {cfg.relative_to(repo)}. Add one (see the section near "
            f"the top of the user-configurable area) or rewrite this regex.")
    if len(matches) > 1:
        die(f"Found {len(matches)} `CORE_VERSION` constant assignments in "
            f"{cfg.relative_to(repo)}; expected exactly one. Values: "
            f"{', '.join(repr(m) for m in matches)}.")

    found = matches[0]
    if found != version:
        die(f"Version mismatch: command line says '{version}' but "
            f"{cfg.relative_to(repo)} has `CORE_VERSION := \"{found}\"`. "
            f"Update CORE_VERSION in config.vhd to '{version}' (or call the "
            f"script with '{found}').")
    ok(f"CORE_VERSION in config.vhd matches command line: '{version}'.")


# ---------------------------------------------------------------------------
# Alpha-release checks
# ---------------------------------------------------------------------------

def check_inofficial_md(repo: Path, version: str) -> str:
    """Verify the alpha is listed in doc/inofficial.md and return its commit."""
    path = repo / "doc" / "inofficial.md"
    if not path.is_file():
        die(f"{path.relative_to(repo)} not found.")

    # Lines look like:
    # | WIP-V6-A6     | 04/21/26 | 4975181 | Improve initial RAM contents ...
    row_re = re.compile(
        r"^\|\s*" + re.escape(version) + r"\s*\|"
        r"\s*([0-9/]+)\s*\|"
        r"\s*([0-9a-fA-F]+)\s*\|"
        r"\s*(.*?)\s*$"
    )

    for line in path.read_text(encoding="utf-8").splitlines():
        m = row_re.match(line)
        if m:
            date, commit, comment = m.groups()
            ok(f"Found '{version}' in doc/inofficial.md "
               f"(date {date}, commit {commit}).")
            return commit

    die(f"Alpha release '{version}' is not listed in doc/inofficial.md. "
        f"Add a row before building the release.")


def check_git_commit(repo: Path, commit: str, version: str) -> None:
    try:
        result = subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "--verify", f"{commit}^{{commit}}"],
            capture_output=True, text=True, check=False,
        )
    except FileNotFoundError:
        die("git executable not found in PATH (needed for alpha-release verification).")

    if result.returncode != 0:
        die(f"Commit '{commit}' from doc/inofficial.md (row '{version}') "
            f"is not a valid git commit in this repository.\n"
            f"  git said: {result.stderr.strip()}")
    full = result.stdout.strip()
    ok(f"Commit '{commit}' resolves to {full[:12]} in git.")


# ---------------------------------------------------------------------------
# Target selection
# ---------------------------------------------------------------------------

def parse_targets(spec: str) -> tuple:
    """Parse a target spec like 'R3,R5' / 'r3+r6' / 'R4 R5' into a tuple
    of canonical board revisions ordered as in BOARD_REVS.

    Accepted separators: comma, plus, slash, semicolon, whitespace. Case
    insensitive. Each token must be one of R3, R4, R5, R6.
    """
    tokens = [t for t in re.split(r"[\s,+/;]+", spec.strip()) if t]
    if not tokens:
        die("Target list is empty. Use e.g. 'R3,R6' or omit the argument "
            "to build all targets.")
    chosen = []
    for tok in tokens:
        norm = tok.upper()
        if norm not in BOARD_REVS:
            die(f"Unknown target '{tok}'. Valid targets: "
                f"{', '.join(BOARD_REVS)}. Separate multiple with comma "
                f"(e.g. R3,R5).")
        if norm not in chosen:
            chosen.append(norm)
    return tuple(r for r in BOARD_REVS if r in chosen)


def warn_if_stale(repo: Path, targets: tuple) -> None:
    """Warn for any bitstream whose mtime is older than today (local time)."""
    today_start = _dt.datetime.combine(_dt.date.today(), _dt.time.min).timestamp()
    stale = []
    for rev in targets:
        p = source_bit_path(repo, rev)
        if not p.is_file():
            continue
        if p.stat().st_mtime < today_start:
            mtime = _dt.datetime.fromtimestamp(p.stat().st_mtime)
            stale.append((rev, mtime))
    if stale:
        warn("Some bitstreams were not built today — you may be packaging "
             "an outdated release:")
        for rev, mtime in stale:
            warn(f"  {rev}: {source_bit_path(repo, rev).name} last built "
                 f"{mtime.strftime('%Y-%m-%d %H:%M:%S')}")


# ---------------------------------------------------------------------------
# coretool / bit2core / bitstreams
# ---------------------------------------------------------------------------

OUTPUT_SEPARATE = "separate"
OUTPUT_MERGED_PYTHON = "merged-python"


@dataclass(frozen=True)
class CoreFileTool:
    """External tool used to produce .cor files from .bit files."""

    name: str
    command_prefix: tuple
    source: str
    output_mode: str


def _format_command_prefix(prefix: tuple) -> str:
    return " ".join(_quote(part) for part in prefix)


def _normalize_command_prefix(parts: list) -> tuple:
    """Validate and normalize a command prefix parsed from PATH or an alias."""
    if not parts:
        return ()

    expanded = [os.path.expandvars(os.path.expanduser(part)) for part in parts]
    exe = expanded[0]
    if os.sep in exe:
        if not (Path(exe).is_file() and os.access(exe, os.X_OK)):
            return ()
    else:
        resolved = shutil.which(exe)
        if not resolved:
            return ()
        expanded[0] = resolved

    return tuple(expanded)


def _parse_shell_type_output(tool_name: str, out: str) -> tuple:
    """Parse bash/zsh-ish `type` output into a runnable command prefix."""
    if "is a function" in out:
        return ()

    alias_patterns = (
        rf"^{re.escape(tool_name)} is aliased to [`'](.+)'$",
        rf"^{re.escape(tool_name)}: aliased to (.+)$",
    )
    path_patterns = (
        rf"^{re.escape(tool_name)} is (~?/.*)$",
        rf"^{re.escape(tool_name)}: (~?/.*)$",
    )

    for raw_line in out.splitlines():
        line = raw_line.strip()
        for pattern in alias_patterns:
            m = re.match(pattern, line)
            if m:
                try:
                    return _normalize_command_prefix(shlex.split(m.group(1)))
                except ValueError:
                    return ()
        for pattern in path_patterns:
            m = re.match(pattern, line)
            if m:
                return _normalize_command_prefix([m.group(1)])

    return ()


def _resolve_tool_via_shell_rc(tool_name: str) -> tuple:
    """Resolve a tool from shell startup files if it is not on PATH.

    Subprocesses do not inherit shell aliases, so a user with
    `alias coretool='~/some/path/coretool'` in their .bash_profile is not
    visible to shutil.which. Source the common rc files in a bash subshell
    with expand_aliases set, ask `type` what the name resolves to, then parse
    the result into a command prefix. Aliases that include a launcher, such as
    `alias coretool='python3 ~/bin/coretool'`, are supported too.
    """
    if os.name == "nt":
        return ()

    snippet = (
        "shopt -s expand_aliases 2>/dev/null; "
        "for rc in ~/.bash_profile ~/.bashrc ~/.zshrc ~/.zprofile ~/.profile; do "
        "  [ -f \"$rc\" ] && . \"$rc\" >/dev/null 2>&1; "
        "done; "
        f"type {shlex.quote(tool_name)} 2>/dev/null"
    )

    try:
        result = subprocess.run(
            ["/bin/bash", "-c", snippet],
            capture_output=True, text=True, timeout=10,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return ()

    out = (result.stdout or "") + "\n" + (result.stderr or "")
    return _parse_shell_type_output(tool_name, out)


def _tool_output_mode(tool_name: str) -> str:
    if tool_name == "coretool":
        return OUTPUT_MERGED_PYTHON
    if tool_name == "bit2core":
        return OUTPUT_SEPARATE
    raise ValueError(f"Unsupported core-file tool: {tool_name}")


def _find_core_file_tool(tool_name: str):
    path = shutil.which(tool_name)
    if path:
        return CoreFileTool(tool_name, (path,), "PATH", _tool_output_mode(tool_name))

    prefix = _resolve_tool_via_shell_rc(tool_name)
    if prefix:
        return CoreFileTool(tool_name, prefix, "shell startup files",
                            _tool_output_mode(tool_name))

    return None


def check_core_file_tool() -> CoreFileTool:
    tools = []
    for tool_name in ("coretool", "bit2core"):
        tool = _find_core_file_tool(tool_name)
        if tool:
            tools.append(tool)
            ok(f"Found {tool.name} via {tool.source}: "
               f"{_format_command_prefix(tool.command_prefix)}.")

    if not tools:
        die("'coretool' or 'bit2core' not found. Neither tool is on PATH nor "
            "resolvable from bash/zsh startup files. Install mega65-tools or "
            "add coretool/bit2core to your PATH/aliases and try again.")

    selected = next((tool for tool in tools if tool.name == "coretool"), tools[0])
    if selected.name == "coretool" and any(tool.name == "bit2core" for tool in tools):
        info("Both coretool and bit2core are available; using coretool.")
    else:
        info(f"Using {selected.name} to generate .cor files.")
    return selected


def board_to_machine(rev: str) -> str:
    """coretool target / bit2core machine argument: 'mega65rN'."""
    return f"mega65r{rev[1:].lower()}"


def source_bit_path(repo: Path, rev: str) -> Path:
    return repo / "CORE" / f"CORE-{rev}.runs" / "impl_1" / f"mega65_{rev.lower()}.bit"


def dest_bit_name(version: str, rev: str) -> str:
    return f"{CORE_FILE_BASE}-{version}-{rev}.bit"


def dest_cor_name(version: str, rev: str) -> str:
    return f"{CORE_FILE_BASE}-{version}-{rev}.cor"


def copy_preserving_timestamps(src: Path, dst: Path) -> None:
    shutil.copy2(src, dst)


def generate_shell_config(repo: Path, dst: Path) -> None:
    """Run M2M/tools/make_config.sh to produce the QNICE Shell's persistence
    file (the `/c64/c64mega65-<version>` config that stores the user's menu
    choices; see GitHub issue #182 for why the filename is versioned).

    The script uses a hard-coded relative path (`../../CORE/vhdl/config.vhd`)
    when 'auto' is requested, so we invoke it with cwd set to M2M/tools/.
    We always go through `bash` explicitly so Windows + Git Bash works the
    same way as macOS/Linux (the shebang is not honoured on Windows).
    """
    bash = shutil.which("bash")
    if not bash:
        die("'bash' not found in PATH. Cannot run make_config.sh to generate "
            "the c64mega65-<version> config file. Install bash (Git Bash on "
            "Windows) and retry.")

    tools_dir = repo / "M2M" / "tools"
    script = tools_dir / "make_config.sh"
    if not script.is_file():
        die(f"{script.relative_to(repo)} not found.")

    cmd = [bash, str(script), str(dst), "auto"]
    info(f"Running: bash {script.relative_to(repo)} {dst.name} auto")
    result = subprocess.run(cmd, cwd=str(tools_dir),
                            capture_output=True, text=True)
    if _VERBATIM or result.returncode != 0:
        for stream in (result.stdout, result.stderr):
            _print_tool_output(stream)
    if result.returncode != 0:
        die(f"make_config.sh failed (exit code {result.returncode}).")
    if not dst.is_file():
        die(f"make_config.sh did not produce {dst}.")


def copy_versions_md(repo: Path, out: Path) -> Path:
    src = repo / "VERSIONS.md"
    if not src.is_file():
        die(f"{src.relative_to(repo)} not found in repository root.")
    dst = out / src.name
    copy_preserving_timestamps(src, dst)
    return dst


def copy_inofficial_md(repo: Path, out: Path) -> Path:
    src = repo / "doc" / "inofficial.md"
    if not src.is_file():
        die(f"{src.relative_to(repo)} not found.")
    dst = out / src.name
    copy_preserving_timestamps(src, dst)
    return dst


def _build_coretool_args(machine: str, src_bit: Path, core_name: str,
                         version: str, dst_cor: Path,
                         overwrite: bool) -> tuple:
    args = [
        "-B", str(dst_cor),
        "--bit", str(src_bit),
        "--target", machine,
        "--bit-name", core_name,
        "--bit-version", version,
        "--flags", CORETOOL_FLAGS,
        "--caps", CORETOOL_CAPS,
    ]
    display = [
        "-B", _quote(str(dst_cor)),
        "--bit", _quote(str(src_bit)),
        "--target", machine,
        "--bit-name", _force_quote(core_name),
        "--bit-version", _force_quote(version),
        "--flags", CORETOOL_FLAGS,
        "--caps", _quote(CORETOOL_CAPS),
    ]
    if overwrite:
        args.insert(0, "--force")
        display.insert(0, "--force")
    return tuple(args), tuple(display)


def _build_bit2core_args(machine: str, src_bit: Path, core_name: str,
                         version: str, dst_cor: Path) -> tuple:
    args = [
        machine, str(src_bit),
        core_name, version,
        str(dst_cor),
        BIT2CORE_TAIL,
    ]
    # core_name and version are always force-quoted in the display output so
    # the printed command mirrors how a user would type it. subprocess.run
    # still receives each unquoted value as one argv slot.
    display = (
        [machine, _quote(str(src_bit))]
        + [_force_quote(core_name), _force_quote(version)]
        + [_quote(str(dst_cor)), _quote(BIT2CORE_TAIL)]
    )
    return tuple(args), tuple(display)


def _build_core_file_command(tool: CoreFileTool, machine: str, src_bit: Path,
                             core_name: str, version: str, dst_cor: Path,
                             overwrite: bool) -> tuple:
    if tool.name == "coretool":
        args, display_args = _build_coretool_args(
            machine, src_bit, core_name, version, dst_cor, overwrite
        )
    elif tool.name == "bit2core":
        args, display_args = _build_bit2core_args(
            machine, src_bit, core_name, version, dst_cor
        )
    else:
        raise ValueError(f"Unsupported core-file tool: {tool.name}")

    cmd = tuple(tool.command_prefix) + args
    display = tuple(_quote(part) for part in tool.command_prefix) + display_args
    return cmd, display


def _print_tool_output(stream: str, force: bool = False) -> None:
    if (_VERBATIM or force) and stream and stream.strip():
        for line in stream.rstrip().splitlines():
            print(f"        {line}")


def _run_separate_capture(tool: CoreFileTool, cmd: tuple, machine: str) -> None:
    # bit2core emits Xilinx-header validation lines on stdout and the
    # WARNING/INFO/"Core file written" lines on stderr. Capture them
    # separately and print stdout first, then stderr, matching the order
    # bit2core produces in an interactive terminal. A merged-stream pipe would
    # reorder them due to stdout becoming block-buffered when not connected to
    # a TTY.
    result = subprocess.run(cmd, capture_output=True, text=True)
    force_output = result.returncode != 0
    for stream in (result.stdout, result.stderr):
        _print_tool_output(stream, force=force_output)
    if result.returncode != 0:
        die(f"{tool.name} failed for {machine} (exit code {result.returncode}).")


def _run_python_merged_capture(tool: CoreFileTool, cmd: tuple, machine: str) -> None:
    # coretool is a Python program. PYTHONUNBUFFERED keeps stdout/stderr write
    # order stable when both streams are merged into one captured pipe.
    env = os.environ.copy()
    env["PYTHONUNBUFFERED"] = "1"
    result = subprocess.run(cmd, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, env=env)
    _print_tool_output(result.stdout, force=result.returncode != 0)
    if result.returncode != 0:
        die(f"{tool.name} failed for {machine} (exit code {result.returncode}).")


def run_core_file_tool(tool: CoreFileTool, machine: str, src_bit: Path,
                       core_name: str, version: str, dst_cor: Path,
                       overwrite: bool) -> None:
    cmd, display = _build_core_file_command(
        tool, machine, src_bit, core_name, version, dst_cor, overwrite
    )
    info(f"Running ({tool.name}): " + " ".join(display))
    try:
        if tool.output_mode == OUTPUT_SEPARATE:
            _run_separate_capture(tool, cmd, machine)
        elif tool.output_mode == OUTPUT_MERGED_PYTHON:
            _run_python_merged_capture(tool, cmd, machine)
        else:
            raise ValueError(f"Unsupported output mode: {tool.output_mode}")
    except FileNotFoundError:
        die(f"{tool.name} executable not found while running: "
            f"{_format_command_prefix(tool.command_prefix)}")


def _quote(arg: str) -> str:
    if " " in arg or "+" in arg or "=" in arg or "," in arg:
        return f'"{arg}"'
    return arg


def _force_quote(arg: str) -> str:
    return f'"{arg}"'


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        prog="make_release.py",
        description="Package a C64MEGA65 release: copy R3..R6 bitstreams, "
                    "produce .cor files via coretool or bit2core, generate the "
                    "c64mega65-<version> config file and copy VERSIONS.md "
                    "into the output folder. Alpha releases also copy "
                    "inofficial.md.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Version conventions:\n"
            "  Major  : V<n>          (e.g. V6)\n"
            "  Minor  : V<n>.<m>      (e.g. V6.1)\n"
            "  Alpha  : WIP-V<n>-A<m>[X<k>] (e.g. WIP-V6-A6, WIP-V6-A13X1)\n"
            "  Ignore : pass -i / --ignore to package an ad-hoc version name\n"
            "           such as A15test1. The name still must appear in\n"
            "           config.vhd, but no doc/inofficial.md row is required.\n\n"
            "Target selection:\n"
            "  Omit the third argument to build all four boards (R3..R6).\n"
            "  Otherwise pass a comma-separated list, e.g. 'R3,R6' or 'R4,R5'.\n"
            "  Other accepted separators: + / ; whitespace. Case-insensitive.\n\n"
            "Output layout:\n"
            "  The second argument is a *parent* folder. The script creates\n"
            "  a subfolder named C64MEGA65-<version> in it and places the\n"
            "  per-board .bit and .cor files, the c64mega65-<version>\n"
            "  config file and VERSIONS.md there. Alpha releases also\n"
            "  include inofficial.md. Example:\n"
            "  passing '~/Desktop'\n"
            "  with version V6.1 produces:\n"
            "    ~/Desktop/C64MEGA65-V6.1/\n"
            "      C64MEGA65-V6.1-R{3,4,5,6}.{bit,cor}\n"
            "      c64mega65-V6.1\n"
            "      VERSIONS.md\n"
            "  If the release subfolder already exists and is non-empty, the\n"
            "  script aborts unless -f / --force is passed.\n\n"
            "Examples:\n"
            "  make_release.py V6 ~/Desktop\n"
            "  make_release.py WIP-V6-A6 /tmp/builds\n"
            "  make_release.py WIP-V6-A13X1 /tmp/builds R6\n"
            "  make_release.py A15test1 /tmp/builds R6 --ignore\n"
            "  make_release.py V6.1 ./out R3,R6\n"
            "  make_release.py V6.1 ./out R3,R6 --force\n"
            "  make_release.py V6.1 ./out R6 --verbatim\n"
        ),
    )
    parser.add_argument("version",
                        help="Release name, e.g. V6, V6.1, WIP-V6-A6 or "
                             "WIP-V6-A13X1")
    parser.add_argument("output_folder",
                        help="Parent folder. The script creates a subfolder "
                             "named C64MEGA65-<version> inside it and places "
                             "all release files there. The parent is created "
                             "if missing; the subfolder must not already exist "
                             "and be non-empty (use --force to overwrite).")
    parser.add_argument("targets", nargs="?", default=None,
                        help="Optional comma-separated subset of boards to "
                             "build, e.g. 'R3,R6'. Defaults to all four "
                             "(R3,R4,R5,R6).")
    parser.add_argument("-f", "--force", action="store_true",
                        help="Overwrite an existing, non-empty release "
                             "subfolder. Without this flag, the script "
                             "refuses to clobber an existing release.")
    parser.add_argument("-i", "--ignore", action="store_true",
                        help="Ignore the standard version-name grammar and "
                             "skip the doc/inofficial.md alpha-release row "
                             "check. The version string is still required to "
                             "appear in CORE/vhdl/config.vhd.")
    parser.add_argument("-v", "--verbatim", action="store_true",
                        help="Print the full step-by-step output, including "
                             "external tool commands and captured tool output. "
                             "By default only the final release summary is "
                             "printed.")
    args = parser.parse_args()
    set_verbatim(args.verbatim)

    # 1) Validate version format up front.
    if args.ignore:
        kind = "ignored"
        info("Version grammar ignored; config.vhd will still be checked.")
    else:
        try:
            kind = classify_version(args.version)
        except ValueError as e:
            die(str(e))

        info({"major": "Major release detected.",
              "minor": "Minor release detected.",
              "alpha": "Alpha release detected."}[kind])

    # 2) Locate the repo.
    repo = find_repo_root()
    info(f"Repository root: {repo}")

    # 3) Check that a .cor builder is available before doing anything expensive.
    core_file_tool = check_core_file_tool()

    # 4) Cross-check config.vhd.
    check_config_vhd(repo, args.version)

    # 5) Alpha releases: cross-check inofficial.md and git history.
    if kind == "alpha":
        commit = check_inofficial_md(repo, args.version)
        check_git_commit(repo, commit, args.version)
    elif kind == "ignored":
        info("--ignore was passed; skipping doc/inofficial.md and git "
             "release-row checks.")

    # 6) Resolve target boards.
    if args.targets is None:
        targets = BOARD_REVS
        info(f"No target list given — building all boards: "
             f"{', '.join(targets)}.")
        # Only when building everything do we warn about stale bitstreams,
        # so that targeted re-builds don't get spurious warnings about the
        # boards the user is intentionally not rebuilding.
        warn_if_stale(repo, targets)
    else:
        targets = parse_targets(args.targets)
        info(f"Building selected boards: {', '.join(targets)}.")

    # 7) Verify the requested bitstreams exist before we start copying.
    missing = [r for r in targets if not source_bit_path(repo, r).is_file()]
    if missing:
        die("Missing bitstream(s): " + ", ".join(
            str(source_bit_path(repo, r).relative_to(repo)) for r in missing
        ) + ". Run synthesis & implementation in Vivado for each board first.")

    # 8) Prepare the output folder. The second CLI argument is a *parent*
    #    folder; we create a release subfolder named C64MEGA65-<version>
    #    inside it and put all .bit / .cor files into that subfolder.
    #    Refuse to clobber an existing, non-empty release folder unless
    #    --force was passed.
    parent = Path(args.output_folder).expanduser().resolve()
    parent.mkdir(parents=True, exist_ok=True)
    out = parent / f"{CORE_FILE_BASE}-{args.version}"
    if out.exists() and any(out.iterdir()):
        if not args.force:
            die(f"Release folder already exists and is not empty: {out}\n"
                f"  Pick a different output folder, delete the existing one, "
                f"or pass -f / --force to overwrite.")
        warn(f"Release folder exists and is not empty; --force was given, "
             f"overwriting: {out}")
    out.mkdir(parents=True, exist_ok=True)
    if kind != "alpha":
        stale_inofficial = out / "inofficial.md"
        if stale_inofficial.is_file() or stale_inofficial.is_symlink():
            stale_inofficial.unlink()
        elif stale_inofficial.exists():
            die(f"Cannot remove stale non-file artifact: {stale_inofficial}")
    # Always remove a stale, unversioned `c64mega65` config file from the
    # release folder. Pre-#182 releases produced it, and re-running the
    # script in the same out folder would otherwise leave it behind next to
    # the new c64mega65-<version> file and confuse end users.
    stale_cfg = out / "c64mega65"
    if stale_cfg.is_file() or stale_cfg.is_symlink():
        stale_cfg.unlink()
    elif stale_cfg.exists():
        die(f"Cannot remove stale non-file artifact: {stale_cfg}")
    info(f"Parent folder:  {parent}")
    info(f"Release folder: {out}")

    # 9) Copy bitstreams (preserving mtime/atime) and generate .cor files.
    for rev in targets:
        src_bit = source_bit_path(repo, rev)
        dst_bit = out / dest_bit_name(args.version, rev)
        dst_cor = out / dest_cor_name(args.version, rev)

        info(f"[{rev}] Copying {src_bit.relative_to(repo)} -> "
             f"{dst_bit.name}")
        copy_preserving_timestamps(src_bit, dst_bit)
        ok(f"[{rev}] {dst_bit.name} ({dst_bit.stat().st_size:,} bytes)")

        info(f"[{rev}] Generating {dst_cor.name}")
        run_core_file_tool(core_file_tool, board_to_machine(rev), dst_bit,
                           CORE_NAME, args.version, dst_cor, args.force)
        if not dst_cor.is_file():
            die(f"[{rev}] {core_file_tool.name} did not produce {dst_cor}.")
        ok(f"[{rev}] {dst_cor.name} ({dst_cor.stat().st_size:,} bytes)")

    # 10) Generate the c64mega65-<version> config file alongside the cores so
    #     end users can drop it into /c64/ on their SD card to enable menu
    #     persistence. The version suffix MUST match what CFG_FILE in
    #     config.vhd produces (which derives from CORE_VERSION, validated by
    #     check_config_vhd() earlier in this run).
    cfg_dst = out / f"c64mega65-{args.version}"
    info(f"Generating config file {cfg_dst.name}")
    generate_shell_config(repo, cfg_dst)
    ok(f"{cfg_dst.name} ({cfg_dst.stat().st_size:,} bytes)")

    # 11) Ship release notes alongside the release (mtime preserved).
    info("Copying VERSIONS.md into the release folder")
    vmd = copy_versions_md(repo, out)
    ok(f"{vmd.name} ({vmd.stat().st_size:,} bytes)")

    imd = None
    if kind == "alpha":
        info("Copying doc/inofficial.md into the release folder")
        imd = copy_inofficial_md(repo, out)
        ok(f"{imd.name} ({imd.stat().st_size:,} bytes)")

    # 12) Final summary so the default output stays concise and verbatim mode
    #     still ends with an at-a-glance view of what was produced.
    print_summary(args.version, kind, targets, cfg_dst, vmd, imd, out)


def print_summary(version: str, kind: str, targets: tuple,
                  cfg_dst: Path, versions_md: Path, inofficial_md,
                  out: Path) -> None:
    bar = "=" * 64
    check = _c("32", "[OK]")
    warn_mark = _c("33", "[!!]")
    title = _c("1", f"Release Summary — {version} ({kind})")

    if _VERBATIM:
        print()
    print(_c("36", bar))
    print(" " + title)
    print(_c("36", bar))
    print(f" {check} Boards:        {', '.join(targets)} "
          f"(.bit + .cor for each)")
    print(f" {check} Config file:   {cfg_dst.name} "
          f"({cfg_dst.stat().st_size:,} bytes)")
    print(f" {check} VERSIONS.md:   {versions_md.stat().st_size:,} bytes "
          f"(timestamp preserved)")
    if inofficial_md is not None:
        print(f" {check} inofficial.md: {inofficial_md.stat().st_size:,} bytes "
              f"(timestamp preserved)")
    print(f" {check} Release at:    {out}")
    if _WARNINGS:
        print()
        print(f" {warn_mark} {len(_WARNINGS)} warning(s) emitted during the run:")
        for w in _WARNINGS:
            # Keep summary lines short — show first line only of multi-line
            # warnings.
            first = w.splitlines()[0]
            if len(first) > 56:
                first = first[:53] + "..."
            print(f"      - {first}")
    print(_c("36", bar))


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        die("Interrupted.", code=130)
