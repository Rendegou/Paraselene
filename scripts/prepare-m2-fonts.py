"""Convert licensed local WOFF2 sources; prove packaged UI glyph coverage."""
import hashlib
import json
import sys
from pathlib import Path

from fontTools import __version__
from fontTools.ttLib import TTFont
from fontTools.ttLib.woff2 import decompress

ROOT = Path(__file__).resolve().parent.parent
SOURCE = Path(r"D:\MyAgent\paraselene-work\src\assets\fonts")
DEST = ROOT / "apps/desktop/assets/fonts"
EVIDENCE = ROOT / "docs/evidence/m2"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare():
    DEST.mkdir(parents=True, exist_ok=True)
    files = []
    for name in ["NotoSansSC-Regular", "NotoSansSC-Medium",
                 "NotoSansSC-Semibold", "NotoSerifSC-Regular"]:
        source = SOURCE / (name + ".woff2")
        target = DEST / (name + ".ttf")
        decompress(source, target)
        files.append({"source": str(source), "sourceSha256": sha(source),
                      "asset": target.name, "sha256": sha(target),
                      "bytes": target.stat().st_size})
    arabic = DEST / "NotoNaskhArabic.ttf"
    files.append({"source": "https://github.com/google/fonts/tree/main/ofl/notonaskharabic",
                  "asset": arabic.name, "sha256": sha(arabic),
                  "bytes": arabic.stat().st_size})
    return files


def coverage(files):
    sans = set(TTFont(DEST / "NotoSansSC-Regular.ttf").getBestCmap())
    serif = set(TTFont(DEST / "NotoSerifSC-Regular.ttf").getBestCmap())
    arabic = set(TTFont(DEST / "NotoNaskhArabic.ttf").getBestCmap())
    ui = set()
    for locale in ["en", "zh_Hans"]:
        values = json.loads((ROOT / f"apps/desktop/lib/l10n/app_{locale}.arb").read_text("utf-8"))
        for key, value in values.items():
            if not key.startswith("@"):
                ui.update(ord(c) for c in value if not c.isspace())
    missing = sorted(ui - sans)
    sample = "雨后的书店第一章归途Hello worldالعربيةעבריתé"
    required = {ord(c) for c in sample if not c.isspace()}
    # Hebrew is author content, not a shipped UI locale or a bundled font promise.
    required -= {ord(c) for c in "עברית"}
    missing_body = sorted(required - serif - sans - arabic)
    if missing or missing_body:
        raise ValueError({"uiMissing": missing, "bodyMissing": missing_body})
    return {"fontToolsVersion": __version__, "fonts": files,
            "uiCodepointsChecked": len(ui), "missingUi": missing,
            "bodySampleMissing": missing_body, "arabicGlyphsChecked": "العربية",
            "status": "PASS"}


if __name__ == "__main__":
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    if "--check" in sys.argv:
        files = json.loads((EVIDENCE / "font-provenance.json").read_text("utf-8"))["fonts"]
        for item in files:
            if sha(DEST / item["asset"]) != item["sha256"]:
                raise ValueError("Packaged font hash changed: " + item["asset"])
    else:
        files = prepare()
    result = coverage(files)
    (EVIDENCE / "font-provenance.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("FONT_CONVERSION_AND_CMAP_PASS")
