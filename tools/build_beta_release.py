"""Build public addon archives from explicit source allowlists; no game required."""
from pathlib import Path
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = '0.8.11-beta.1'


def main():
    out = ROOT / 'output' / 'releases' / VERSION
    out.mkdir(parents=True, exist_ok=True)
    addons = {
        'FreeCombatPrototype': ['_ModInfo.json', 'entry.rb', 'core.rb', 'scene.rb',
            'map_world.rb', 'map_combat.rb', 'map_effects.rb', 'map_mode.rb', 'map_npcs.rb', 'story_mode.rb'],
        'FreeCombatDiagnostics': ['_ModInfo.json', 'entry.rb', 'README.md', 'test_world.rb',
            'arena.rb', 'test_modes.rb', 'overlay.rb', 'combat_journal.rb'],
        'FreeCombatCompatibility': ['_ModInfo.json', 'entry.rb', 'README.md'],
        'LonaPerformance': ['_ModInfo.json', 'entry.rb', 'settings.rb', 'README.md', 'CHANGELOG.md', 'MANUAL_TESTS.md'],
    }
    manifest = {}
    for addon, names in addons.items():
        base = ROOT / 'src' / addon
        info = json.loads((base / '_ModInfo.json').read_text(encoding='utf-8'))
        members = {name: (base / name).read_bytes() for name in names}
        if addon == 'FreeCombatPrototype':
            members['README.md'] = (ROOT / 'docs/releases/0.8.11-beta/README.md').read_bytes()
        if addon == 'LonaPerformance':
            for name, source in {
                'modules/scalar.rb': 'src/RGSSPerformance/60000_RGSSPerformancePatch.rb',
                'modules/native.rb': 'src/RGSSPerformance/60010_RGSSCombatPerformance.rb',
                'modules/gc.rb': 'src/RGSSPerformance/60020_RGSSCombatGCExperiment.rb',
                'source/geometry.c': 'src/RGSSPerformance/geometry.c',
                'native/geometry-x86.dll': 'output/native-geometry/geometry-x86.dll',
            }.items():
                members[name] = (ROOT / source).read_bytes()
            members['SOURCE.md'] = b'# Source\n\nAuthored numeric DLL, built from source/geometry.c with MSVC x86. No game or RGSS binaries are included. GC batching is experimental and disabled by default.\n'
            members['SHA256.json'] = json.dumps({name: hashlib.sha256(data).hexdigest()
                for name, data in members.items()}, indent=2).encode('utf-8')
            assert 'GC_BATCH_FRAMES = 0' in members['settings.rb'].decode('utf-8')
        prefix = 'ModScripts/_Mods/' + addon + '/'
        archive = out / (addon + '-' + info['version'] + '.zip')
        with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as bundle:
            for name, data in members.items():
                bundle.writestr(prefix + name, data)
        with zipfile.ZipFile(archive) as bundle:
            assert bundle.testzip() is None
            assert set(bundle.namelist()) == {prefix + name for name in members}
            for name in bundle.namelist():
                assert '..' not in Path(name).parts
                assert not name.lower().endswith(('.exe', '.rvdata2', '.log', '.jsonl', '.png', '.bmp'))
                assert not name.endswith('.dll') or name == prefix + 'native/geometry-x86.dll'
            assert json.loads(bundle.read(prefix + '_ModInfo.json')) == info
        manifest[archive.name] = {'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
            'bytes': archive.stat().st_size, 'addon': addon, 'version': info['version']}
    (out / 'SHA256SUMS.txt').write_text(''.join(
        item['sha256'] + '  ' + name + '\n' for name, item in manifest.items()), encoding='utf-8')
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
