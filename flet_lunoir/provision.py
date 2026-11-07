"""Download Flet's matching official desktop client during setup, not launch."""
from pathlib import Path
import urllib.request

import flet
from flet.utils import safe_zip_extractall
import zipfile

from .backend import ROOT


def main():
    runtime = ROOT / "flet_lunoir/runtime/flet"
    if (runtime / "flet/flet.exe").is_file():
        return
    archive = runtime.parent / "flet-windows.zip"
    url = f"https://github.com/flet-dev/flet/releases/download/v{flet.__version__}/flet-windows.zip"
    print(f"Downloading Flet {flet.__version__}'s Windows desktop client...")
    if not archive.is_file():
        urllib.request.urlretrieve(url, archive)
    runtime.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as package:
        safe_zip_extractall(package, str(runtime))
    if not (runtime / "flet/flet.exe").is_file():
        raise RuntimeError("The Flet desktop archive did not contain flet.exe.")
    archive.unlink()


if __name__ == "__main__":
    main()
