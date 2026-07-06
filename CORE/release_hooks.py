"""Optional release hooks for C64MEGA65.

The generic make_release.py imports this module when present. Keep release
policy in CORE/release.toml whenever possible; use hooks only for checks or
artifacts that cannot be expressed declaratively.
"""


def validate(ctx):
    """Run core-specific validation before the output folder is written."""
    return None


def after_package(ctx):
    """Return extra artifact paths created after standard packaging."""
    return []
