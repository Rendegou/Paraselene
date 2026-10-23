"""Build offline Chinese WOFF2 assets from Google Fonts' OFL-licensed variable sources.

Usage: python prepare-studio-fonts.py <font-tools-dir> <source-dir>
The tools directory is a build-only location, not an application dependency.
"""
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[1])
from fontTools.ttLib import TTFont
from fontTools.subset import Options, Subsetter
from fontTools.varLib.instancer import instantiateVariableFont

target = Path(__file__).resolve().parents[2] / "src" / "assets" / "fonts"
source = Path(sys.argv[2]).resolve()
for family, weight, style in (("NotoSansSC", 400, "Regular"),
                             ("NotoSansSC", 500, "Medium"),
                             ("NotoSansSC", 600, "Semibold"),
                             ("NotoSerifSC", 400, "Regular")):
    font = TTFont(source / (family + ".ttf"))
    instantiateVariableFont(font, {"wght": weight}, inplace=True)
    options = Options()
    options.hinting = True
    subset = Subsetter(options=options)
    # Keep Latin, CJK unified/extensions A, punctuation and full-width forms.
    ranges = [(0, 0x024F), (0x2000, 0x206F), (0x3000, 0x303F),
              (0x3400, 0x9FFF), (0xFF00, 0xFFEF)]
    subset.populate(unicodes=[code for code in font.getBestCmap()
                             if any(start <= code <= end for start, end in ranges)])
    subset.subset(font)
    font.flavor = "woff2"
    destination = target / (family + "-" + style + ".woff2")
    font.save(destination)
    print(f"{destination.name}: {destination.stat().st_size} bytes")
