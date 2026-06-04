#!/usr/bin/env python3
"""
make_release.py — Package a C64MEGA65 release.

Given a release name (e.g. V6, V6.1, WIP-V6-A6, WIP-V6-A13X1, or with
--ignore an ad-hoc name such as A15test1) and an output folder, this script
validates the version string against config.vhd, sanity-checks alpha releases
against doc/inofficial.md and the git history unless --ignore was passed,
copies the per-board bitstreams from CORE/CORE-R{3..6}.runs/impl_1/, produces
.cor files via the external `bit2core` tool, generates the
`c64mega65-<version>` config file via M2M/tools/make_config.sh, and copies
VERSIONS.md into the release folder. Alpha releases also copy
doc/inofficial.md (timestamps preserved).
"""

import argparse
import datetime as _dt
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

CORE_NAME       = "C64 for MEGA65"
CORE_FILE_BASE  = "C64MEGA65"
BIT2CORE_TAIL   = "=default,c64cart+c64cart"
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


def _c(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if _COLOR else text


def info(msg: str) -> None:
    print(f"{_c('36', '[INFO]')} {msg}")


def ok(msg: str) -> None:
    print(f"{_c('32', '[ OK ]')} {msg}")


_WARNINGS: list = []


def warn(msg: str) -> None:
    _WARNINGS.append(msg)
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
# bit2core / bitstreams
# ---------------------------------------------------------------------------

def _resolve_bit2core_via_shell_rc() -> str:
    """If bit2core isn't on PATH, try to resolve a shell alias defined in
    the user's bash/zsh startup files. Returns an absolute path to an
    executable or "" if nothing usable was found.

    Subprocesses don't inherit shell aliases, so a user with
    `alias bit2core='~/some/path/bit2core'` in their .bash_profile won't
    be visible to shutil.which. We re-source the common rc files in a
    bash subshell with expand_aliases set, ask `type` what it resolves
    to, then parse out a path. Windows has no equivalent and is skipped.
    """
    if os.name == "nt":
        return ""

    snippet = (
        "shopt -s expand_aliases 2>/dev/null; "
        "for rc in ~/.bash_profile ~/.bashrc ~/.zshrc ~/.zprofile ~/.profile; do "
        "  [ -f \"$rc\" ] && . \"$rc\" >/dev/null 2>&1; "
        "done; "
        "type bit2core 2>/dev/null"
    )

    try:
        result = subprocess.run(
            ["/bin/bash", "-c", snippet],
            capture_output=True, text=True, timeout=10,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return ""

    out = (result.stdout or "") + "\n" + (result.stderr or "")

    # Functions can't be reduced to a single path — give up cleanly.
    if "is a function" in out:
        return ""

    # Pull the first path-looking token (~/... or /...) out of the
    # `type` output. Common forms produced by bash/zsh:
    #   bit2core is aliased to `~/.dev/.../bit2core'
    #   bit2core: aliased to /usr/local/bin/bit2core
    #   bit2core is /usr/local/bin/bit2core
    m = re.search(r"['\"`]?(~?/[^\s'\"`]+)", out)
    if not m:
        return ""

    candidate = os.path.expanduser(m.group(1))
    if Path(candidate).is_file() and os.access(candidate, os.X_OK):
        return candidate
    return ""


def check_bit2core() -> str:
    path = shutil.which("bit2core")
    if path:
        ok(f"Found bit2core at {path}.")
        return path

    # Not on PATH — maybe it's a shell alias.
    resolved = _resolve_bit2core_via_shell_rc()
    if resolved:
        ok(f"Found bit2core via shell alias at {resolved}.")
        return resolved

    die("'bit2core' not found. It is neither on PATH nor resolvable as "
        "a bash/zsh alias from your startup files. Install mega65-tools "
        "(which provides bit2core) or add it to your PATH/aliases and "
        "try again.")


def board_to_machine(rev: str) -> str:
    """bit2core's `machine` argument: 'mega65rN'."""
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
    for stream in (result.stdout, result.stderr):
        if stream and stream.strip():
            for line in stream.rstrip().splitlines():
                print(f"        {line}")
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


def run_bit2core(bit2core: str, machine: str, src_bit: Path,
                 core_name: str, version: str, dst_cor: Path) -> None:
    cmd = [
        bit2core, machine, str(src_bit),
        core_name, version,
        str(dst_cor),
        BIT2CORE_TAIL,
    ]
    # Build a human-readable log line. core_name and version are always
    # force-quoted (regardless of whether they happen to contain spaces or
    # special characters) so the printed command exactly mirrors how a user
    # would type it. Note: subprocess.run with a list does NOT pass these
    # quotes to bit2core itself — each list element is one argv slot.
    display = (
        [bit2core, machine, _quote(str(src_bit))]
        + [_force_quote(core_name), _force_quote(version)]
        + [_quote(str(dst_cor)), _quote(BIT2CORE_TAIL)]
    )
    info("Running: " + " ".join(display))
    # bit2core emits Xilinx-header validation lines on stdout and the
    # WARNING/INFO/"Core file written" lines on stderr. We capture them
    # separately and print stdout first, then stderr — matching the order
    # bit2core produces in an interactive terminal. (A merged-stream pipe
    # would reorder them due to stdout becoming block-buffered when not
    # connected to a TTY.)
    result = subprocess.run(cmd, capture_output=True, text=True)
    for stream in (result.stdout, result.stderr):
        if stream and stream.strip():
            for line in stream.rstrip().splitlines():
                print(f"        {line}")
    if result.returncode != 0:
        die(f"bit2core failed for {machine} (exit code {result.returncode}).")


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
                    "produce .cor files via bit2core, generate the "
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
    args = parser.parse_args()

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

    # 3) Check that bit2core is available before doing anything expensive.
    bit2core = check_bit2core()

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
        run_bit2core(bit2core, board_to_machine(rev), dst_bit,
                     CORE_NAME, args.version, dst_cor)
        if not dst_cor.is_file():
            die(f"[{rev}] bit2core did not produce {dst_cor}.")
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

    # 12) Final summary so the user can see at-a-glance what was produced
    #     without having to scroll back through the verbose live output.
    print_summary(args.version, kind, targets, cfg_dst, vmd, imd, out)


def print_summary(version: str, kind: str, targets: tuple,
                  cfg_dst: Path, versions_md: Path, inofficial_md,
                  out: Path) -> None:
    bar = "=" * 64
    check = _c("32", "[OK]")
    warn_mark = _c("33", "[!!]")
    title = _c("1", f"Release Summary — {version} ({kind})")

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
            # warnings; user can scroll up for full context.
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
