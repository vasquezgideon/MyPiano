#!/usr/bin/env python3
"""Static regression checks for the real keyboard-rendering path."""
from pathlib import Path
import re

src = Path("SimplyKeys/PianoKeyboard.swift").read_text()
screen = Path("SimplyKeys/PianoScreen.swift").read_text()

# Newly pressed notes must be registered; otherwise CADisplayLink never animates them.
begin = src.split("private func begin(", 1)[1].split("private func finish(", 1)[0]
assert "pressAmounts[note] =" in begin, "Begin must seed the press animation"
assert begin.index("pressAmounts[note] =") < begin.index("ensureAnimation()")
assert "let target: CGFloat = keyHolds[midi, default: 0] > 0 ? 1 : 0" in src

# Dark and light idle backgrounds are exactly black/white, without a color cast.
assert "let background: UIColor = dark ? .black : .white" in src
assert "let natural: UIColor = dark ? .black : .white" in src
assert "let pressedSharp: UIColor = dark ? .black : .white" in src

# Press animations interpolate to the selected accent or to the neutral theme color.
assert "blend(natural, blue, amount: press).setFill()" in src
assert "blend(blue, pressedSharp, amount: press).setFill()" in src
assert "let blue = accentColor.resolvedColor(with: traitCollection)" in src
assert "traits.userInterfaceStyle == .dark ? .black : .white" in screen

# All changed render paths should remain direct, simple and redraw on animation frames.
assert "redraw(midi)" in src.split("@objc private func animateKeys(", 1)[1]
assert "private func redraw(_ midi: Int)" in src
print("Keyboard appearance and press-animation regression checks passed")
