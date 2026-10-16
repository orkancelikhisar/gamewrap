#!/usr/bin/env python3
"""Create a separate experimental DXMT app from an existing GameWrap app.

Requires a Wine build exporting macdrv_functions and an unpacked builtin DXMT
release. Never modifies the source app. Runtime downloads are supplied explicitly.
"""
import argparse
import json
import plistlib
import shutil
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('wine', type=Path, help='Runtime directory containing bin and lib')
    parser.add_argument('dxmt', type=Path, help='DXMT directory containing x86_64-unix and x86_64-windows')
    parser.add_argument('destination', type=Path)
    parser.add_argument('--dependency-lib', type=Path, help='Additional runtime libraries, copied only when missing')
    args = parser.parse_args()
    source, wine, dxmt, destination = [p.resolve() for p in (args.source, args.wine, args.dxmt, args.destination)]
    if destination.exists():
        parser.error('Destination already exists; choose a new app name.')
    manifest = json.loads((source / 'Contents/Resources/gamewrap.json').read_text())
    if not (wine / 'bin/wine').is_file():
        parser.error('Runtime must contain bin/wine.')
    symbols = subprocess.check_output(['nm', '-g', str(wine / 'lib/wine/x86_64-unix/winemac.so')], text=True)
    if '_macdrv_functions' not in symbols:
        parser.error('This Wine build does not export the DXMT macdrv_functions interface.')
    dlls = ['winemetal.dll', 'd3d11.dll', 'dxgi.dll', 'd3d10core.dll']
    for file in [dxmt / 'x86_64-unix/winemetal.so'] + [dxmt / 'x86_64-windows' / n for n in dlls]:
        if not file.is_file():
            parser.error(f'Missing DXMT file: {file.name}')
    # Copy only required source resources; the old runtime is deliberately excluded.
    resources = destination / 'Contents/Resources'
    resources.mkdir(parents=True)
    shutil.copy2(source / 'Contents/Info.plist', destination / 'Contents/Info.plist')
    for file in (source / 'Contents/Resources').iterdir():
        if file.name == 'wine':
            continue
        if file.is_dir():
            subprocess.run(['cp', '-cR', str(file), str(resources / file.name)], check=True)
        else:
            shutil.copy2(file, resources / file.name)
    subprocess.run(['cp', '-cR', str(wine), str(resources / 'wine')], check=True)
    runtime = resources / 'wine'
    if args.dependency_lib:
        # Keep dependencies inside the app, rather than depending on a test directory.
        for file in args.dependency_lib.iterdir():
            target = runtime / 'lib' / file.name
            if file.is_file() and file.suffix == '.dylib' and not target.exists():
                shutil.copy2(file, target)
    shutil.copy2(dxmt / 'x86_64-unix/winemetal.so', runtime / 'lib/wine/x86_64-unix/winemetal.so')
    for name in dlls:
        shutil.copy2(dxmt / 'x86_64-windows' / name, runtime / 'lib/wine/x86_64-windows' / name)
    manifest['name'] = destination.stem
    manifest['runtime'] = 'experimental-wine11-dxmt080'
    manifest['env'].pop('WINEMSYNC', None)
    (resources / 'gamewrap.json').write_text(json.dumps(manifest, indent=2) + '\n')
    info = plistlib.loads((destination / 'Contents/Info.plist').read_bytes())
    info.update(CFBundleName=destination.stem, CFBundleDisplayName=destination.stem,
                CFBundleIdentifier=info['CFBundleIdentifier'] + '.dxmt')
    (destination / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    original = (source / 'Contents/MacOS' / info['CFBundleExecutable']).read_text()
    original = original.replace('WINE="$RES/wine/bin/wine64"', 'WINE="$RES/wine/bin/wine"')
    original = original.replace('export WINEDLLOVERRIDES="winemenubuilder.exe=d"',
        'export WINEDLLOVERRIDES="winemenubuilder.exe=d;dxgi,d3d11,d3d10core=b"\n'
        'export DYLD_FALLBACK_LIBRARY_PATH="$RES/wine/lib:/usr/lib"')
    original = original.replace('  touch "$WINEPREFIX/.gamewrap-ready"',
        '  for dll in winemetal d3d11 dxgi d3d10core; do\n'
        '    cp "$RES/wine/lib/wine/x86_64-windows/$dll.dll" "$WINEPREFIX/drive_c/windows/system32/$dll.dll" || exit 1\n'
        '  done\n  touch "$WINEPREFIX/.gamewrap-ready"')
    # Let Launch Services track the Wine game process, rather than a waiting shell.
    original = original[:original.index('start=$SECONDS')] + 'exec "${cmd[@]}" > "$LOG" 2>&1\n'
    executable = destination / 'Contents/MacOS' / info['CFBundleExecutable']
    executable.parent.mkdir()
    executable.write_text(original)
    executable.chmod(0o755)
    subprocess.run(['xattr', '-cr', str(destination)], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', str(destination)], check=True)
    subprocess.run(['codesign', '--verify', str(destination)], check=True)
    print(f'Created {destination}\nUses a separate save environment named {destination.stem}.')


if __name__ == '__main__':
    main()
