"""Runtime-adaptive byLLM Model loader.

jachammer's hosted runtime (the new self-contained jac binary) ships byLLM
inside jaclang core (jaclang.byllm.lib), and its compiler cannot parse the
legacy pip byllm package's .jac sources (old-style `global x;` statements).
The local dev env (pip jaclang 0.16.7) is the mirror image: only the legacy
pip package exists. Importing here in Python — not in Jac — means only the
implementation that actually exists on the running host is ever touched.
"""

import os


def get_model():
    try:
        from jaclang.byllm.lib import Model  # hosted runtime: byLLM in jaclang core
    except ImportError:
        from byllm.lib import Model  # local dev: legacy pip byllm

    return Model(model_name=os.environ.get("CAREGRAPH_MODEL", "claude-sonnet-4-6"))
