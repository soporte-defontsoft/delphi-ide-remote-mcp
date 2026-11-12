"""Shared by the check.py of every Python example: load a module from its given/ or answer/ folder.

One loader for all of them, so a check never picks up the wrong copy of a module from sys.path.
"""
import importlib.util
import os
import sys


def load(example_dir, folder, module):
    """Import <example_dir>/<folder>/<module>.py fresh, as `module` (replacing any earlier copy)."""
    path = os.path.join(example_dir, folder, module + ".py")
    sys.modules.pop(module, None)
    spec = importlib.util.spec_from_file_location(module, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[module] = mod
    spec.loader.exec_module(mod)
    return mod


def raises(exc, fn, *args):
    """True when fn(*args) raises exc."""
    try:
        fn(*args)
    except exc:
        return True
    return False
