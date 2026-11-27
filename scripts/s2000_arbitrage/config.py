"""Read the controller's TOML config, with its secrets merged in.

A top-level ``secrets = PATH`` (relative to the config file) names a second
TOML file whose tables are merged into the config's, so credentials such as
``[home_assistant] token`` stay out of the config itself. A key may be set in
only one of the two files.
"""

import tomllib
from pathlib import Path


def load(path):
    with open(path, "rb") as f:
        cfg = tomllib.load(f)
    if "secrets" in cfg:
        with open(Path(path).parent / cfg.pop("secrets"), "rb") as f:
            secrets = tomllib.load(f)
        for table, values in secrets.items():
            both = cfg.setdefault(table, {}).keys() & values.keys()
            if both:
                raise ValueError(
                    f"[{table}] {', '.join(sorted(both))} set in both the config and its secrets"
                )
            cfg[table].update(values)
    return cfg
