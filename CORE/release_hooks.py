"""Optional release hooks for C64MEGA65.

The generic make_release.py imports this module when present. Keep release
policy in CORE/release.toml whenever possible; use hooks only for checks or
artifacts that cannot be expressed declaratively.
"""

import re


# Matches the RHS of `constant CFG_FILE : string := <rhs>;` in config.vhd.
_CFG_FILE_RE = re.compile(
    r"constant\s+CFG_FILE\s*:\s*string\s*:=\s*(?P<rhs>[^;]+);"
)


def validate(ctx):
    """Run core-specific validation before the output folder is written.

    Guard against silent drift between the two independent sources that build
    the on-SD config file name: CFG_FILE in CORE/vhdl/config.vhd (the name the
    core opens at runtime) and shell_config.filename in CORE/release.toml (the
    name this release ships). The generic tool only cross-checks CORE_VERSION,
    so changing the prefix or extension in one place but not the other would
    otherwise ship a release whose config the core silently ignores (issue
    #239 added the ".cfg" extension). Raising here aborts the release.
    """
    if not ctx.config.shell_config_enabled:
        return None

    config_vhd = ctx.repo / "CORE" / "vhdl" / "config.vhd"
    text = config_vhd.read_text(encoding="utf-8", errors="replace")

    match = _CFG_FILE_RE.search(text)
    if not match:
        raise ValueError(
            "could not find `constant CFG_FILE : string := ...;` in "
            "CORE/vhdl/config.vhd; update the core or this guard")
    actual_rhs = re.sub(r"\s+", " ", match.group("rhs").strip())
    expected_rhs = '"/c64/c64mega65-" & CORE_VERSION & ".cfg"'
    if actual_rhs != expected_rhs:
        raise ValueError(
            "CFG_FILE in CORE/vhdl/config.vhd does not build the expected "
            "on-SD config file name (issue #239).\n"
            f"  expected RHS: {expected_rhs}\n"
            f"  found RHS:    {actual_rhs}\n"
            "If you intentionally changed the config file name, update both "
            "this guard and shell_config.filename in CORE/release.toml.")

    # Cross-check the concrete file name both sources produce for this build.
    # CORE_VERSION == ctx.version is already enforced by the generic tool
    # (check_config_vhd), so config.vhd yields exactly this name; the
    # release.toml pattern must agree.
    core_name = f"c64mega65-{ctx.version}.cfg"
    toml_name = ctx.config.shell_config_filename.format(
        version=ctx.version,
        file_base=ctx.config.file_base,
        display_name=ctx.config.display_name,
        rev="",
        rev_lower="",
    )
    if toml_name != core_name:
        raise ValueError(
            "config file name drift: CORE/vhdl/config.vhd builds "
            f"'/c64/{core_name}' but shell_config.filename in "
            f"CORE/release.toml yields '{toml_name}'; make them agree")

    return None


def after_package(ctx):
    """Return extra artifact paths created after standard packaging."""
    return []
