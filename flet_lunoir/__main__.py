from __future__ import annotations

import logging
import os
from pathlib import Path
import sys

from .backend import ROOT

# Keep the desktop runtime with the project instead of downloading it at launch.
runtime = ROOT / "flet_lunoir/runtime/flet/flet/flet.exe"
if runtime.exists():
    os.environ["FLET_VIEW_PATH"] = str(runtime.parent)

log_dir = Path(os.environ.get("LOCALAPPDATA", ROOT)) / "Lunoir V"
log_dir.mkdir(parents=True, exist_ok=True)
logging.basicConfig(filename=log_dir / "ui.log", level=logging.INFO,
                    format="%(asctime)s %(levelname)s %(name)s %(message)s")

from .instance import Instance, targets
from .profile import Profile

startup = targets(sys.argv[1:])
instance = Instance(Profile.default_directory())
if not instance.claim():
    if instance.forward(startup):
        sys.exit(0)
    logging.warning("the running player did not answer; starting another")
    instance = None

import flet as ft
from .app import main

async def start(page):
    await main(page, startup, instance)

ft.run(start, assets_dir=str(ROOT / "lunoir/src/renderer/src/assets"))
