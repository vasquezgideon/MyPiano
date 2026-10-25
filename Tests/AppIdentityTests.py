#!/usr/bin/env python3
"""Static checks for app identity and icon catalog (no external libraries)."""
from pathlib import Path
import json
import re
import struct

root = Path(__file__).resolve().parents[1]
project = (root / 'MyPiano.xcodeproj/project.pbxproj').read_text()
workflow = (root / '.github/workflows/build-ipa.yml').read_text()
assert project.count('PRODUCT_BUNDLE_IDENTIFIER = com.vasquezgideon.mypiano;') == 2
assert project.count('INFOPLIST_KEY_CFBundleDisplayName = MyPiano;') == 2
assert project.count('MARKETING_VERSION = 1.4.7;') == 2
assert project.count('CURRENT_PROJECT_VERSION = 7;') == 2
assert '/* MyPiano.app */' in project
assert 'name = MyPiano;' in project
assert 'productName = MyPiano;' in project
assert 'struct MyPianoApp: App' in (root / 'SimplyKeys/MyPianoApp.swift').read_text()
assert 'CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER}"' in workflow
assert '-project MyPiano.xcodeproj' in workflow
assert '-scheme MyPiano' in workflow
assert 'MyPiano-unsigned.ipa' in workflow
icons = root / 'SimplyKeys/Assets.xcassets/AppIcon.appiconset'
metadata = json.loads((icons / 'Contents.json').read_text())
entries = metadata['images']
assert len(entries) == 2
by_file = {x['filename']: x for x in entries}
assert by_file['AppIcon-Light.png'].get('appearances') is None
assert by_file['AppIcon-Dark.png']['appearances'] == [{'appearance':'luminosity', 'value':'dark'}]
for name in by_file:
    data = (icons / name).read_bytes()
    assert data.startswith(b'\x89PNG\r\n\x1a\n'), name
    assert struct.unpack('>II', data[16:24]) == (1024, 1024), name
print('App identity, version, workflow and adaptive icon assets: PASS')
