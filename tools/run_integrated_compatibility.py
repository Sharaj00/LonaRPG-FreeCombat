"""Run one focused case in the existing private native runner, never story-mods."""
from pathlib import Path
import argparse
import configparser
import json
import shutil
import subprocess
import sys
import random

ROOT = Path(__file__).resolve().parents[1]
LAB = ROOT / 'output/mod-compat-lab'
EVIDENCE = ROOT / 'output/load-order-verification'
CORE = ['FreeCombatPrototype', 'FreeCombatDiagnostics', 'LonaPerformance']
FULL = json.loads((ROOT / 'output/mod-compat-verification/load-order.json').read_text())
FULL = [name for name in FULL if name != 'FreeCombatCompatibility']
FEATURES = ['passive_stamina', 'temper_frame_pause', 'faction_interaction_intent',
            'external_load_rollback', 'roleplay_backward_dodge', 'rest_journal_extra_maps']
CASES = {
    'base': dict(folders=CORE[::-1], features=[]),
    'full': dict(folders=FULL, features=FEATURES, gameplay=True),
    'legacy': dict(folders=FULL[:12]+['FreeCombatCompatibility']+CORE, features=FEATURES, legacy=True),
    'temper': dict(folders=['Temper Trine']+CORE, features=['temper_frame_pause']),
    'faction': dict(folders=['LonaRPG_FactionClashes']+CORE, features=['faction_interaction_intent']),
    'journal': dict(folders=['LonaRPG_RestJournal']+CORE, features=['external_load_rollback'], skipped=['rest_journal_extra_maps']),
    'roleplay': dict(folders=['RolePlayS']+CORE, features=['external_load_rollback','roleplay_backward_dodge'], skipped=['rest_journal_extra_maps']),
    'passive': dict(folders=['PassiveStaminaRegen']+CORE, features=['passive_stamina']),
    'unsupported': dict(folders=FULL, features=[f for f in FEATURES if f!='temper_frame_pause'], skipped=['temper_frame_pause'], unsupported=True),
    'interface': dict(folders=FULL, features=[f for f in FEATURES if f!='temper_frame_pause'], skipped=['temper_frame_pause'], missing_interface=True),
    'passive_order': dict(folders=CORE[:1]+['PassiveStaminaRegen']+CORE[1:], features=['passive_stamina']),
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('case', choices=CASES)
    parser.add_argument('--shuffle', type=int)
    parser.add_argument('--fixtures', action='store_true')
    parser.add_argument('--title-only', action='store_true')
    parser.add_argument('--release-versions', action='store_true')
    args = parser.parse_args()
    label = args.case + ('-title' if args.title_only else '') + ('-release' if args.release_versions else '')
    EVIDENCE.mkdir(exist_ok=True)
    backup = EVIDENCE / 'before-tests'
    if not backup.exists():
        shutil.copytree(LAB / 'UserData', backup / 'UserData')
        for addon in CORE:
            shutil.copytree(LAB / 'ModScripts/_Mods' / addon, backup / addon)
    legacy = LAB / 'ModScripts/_Mods/FreeCombatCompatibility'
    parked = EVIDENCE / 'parked-FreeCombatCompatibility'
    for path in (legacy, parked):
        assert path.resolve().is_relative_to(ROOT.resolve())
    case = dict(CASES[args.case])
    if args.release_versions:
        case['versions'] = {addon:json.loads((ROOT/'src'/addon/'_ModInfo.json').read_text())['version'] for addon in CORE}
    if args.title_only:
        case['gameplay'] = False
    if case.get('legacy'):
        if parked.exists():
            shutil.move(str(parked), str(legacy))
        elif not legacy.exists():
            shutil.copytree(ROOT / 'output/integrated-compatibility-verification/parked-FreeCombatCompatibility', legacy)
    elif legacy.exists():
        shutil.move(str(legacy), str(parked))
    for addon in CORE[:2]:
        shutil.copytree(ROOT / 'src' / addon, LAB / 'ModScripts/_Mods' / addon, dirs_exist_ok=True)
    for source, target in [('mod_compat_probe.rb','integrated-probe-helpers.rb'),
                           ('mod_compat_acceptance.rb','mod_compat_acceptance.rb')]:
        shutil.copy2(ROOT / 'tests' / source, LAB / target)
    hook = LAB / 'ModScripts/65000_IntegratedCompatibilityProbe.rb'
    assert not [p for p in hook.parent.glob('65000*.rb') if p != hook]
    shutil.copy2(ROOT / 'tests/integrated_compatibility_probe.rb', hook)
    shutil.copy2(ROOT / 'tests/load_order_native_probe.rb', LAB / 'ModScripts/400_LoadOrderProbe.rb')
    config = configparser.ConfigParser()
    config.optionxform = str
    config['Mods'] = {}
    folders = list(case.pop('folders'))
    if args.shuffle is not None:
        random.Random(args.shuffle).shuffle(folders)
    if args.fixtures:
        folders.insert(1, 'OrderFixtureA')
        folders.insert(4, 'OrderFixtureB')
        for fixture in ('OrderFixtureA','OrderFixtureB','OrderFixtureDisabled'):
            target = LAB / 'ModScripts/_Mods' / fixture
            target.mkdir(exist_ok=True)
            info = {'id':fixture, 'version':'1.0','entry':'entry.rb'}
            if fixture == 'OrderFixtureA':
                info['requires'] = {'RolePlayS':['==','0.7.9.3']}
            (target / '_ModInfo.json').write_text(json.dumps(info),encoding='utf-8')
            (target / 'entry.rb').write_text("File.open('order-fixture-loads.txt','a') { |file| file.puts('"+fixture+"') }\n",encoding='utf-8')
    case['enabled'] = []
    for i, folder in enumerate(folders):
        config[folder] = {'Banned':'0','LoadOrder':str(i)}
        if folder != 'FreeCombatCompatibility':
            case['enabled'].append('temper_trine' if folder=='Temper Trine' else folder)
    if args.fixtures:
        config['OrderFixtureA']['CustomSetting'] = '71'
        config['OrderFixtureDisabled'] = {'Banned':'1','LoadOrder':'2','CustomSetting':'29'}
    with (LAB / 'UserData/GameMods.ini').open('w',encoding='utf-8') as file:
        config.write(file)
    (LAB / 'integrated-config.json').write_text(json.dumps(case),encoding='utf-8')
    previous = EVIDENCE / 'running.json'
    previous_case = json.loads(previous.read_text())['case'] if previous.exists() else 'before'
    # Archive only this runner's previous test outputs, preserving every result.
    for path in LAB.glob('mod-compat-*.txt'):
        dest = EVIDENCE / (previous_case + '-' + path.name)
        shutil.move(str(path), str(dest))
    for attempt in range(2):
        notice = LAB / 'load-order-notice.txt'
        if notice.exists():
            shutil.move(str(notice),str(EVIDENCE/(label+'-previous-notice.txt')))
        with (EVIDENCE / (label+'-'+str(attempt)+'-stdout.txt')).open('wb') as stdout, \
             (EVIDENCE / (label+'-'+str(attempt)+'-stderr.txt')).open('wb') as stderr:
            process = subprocess.Popen([str(LAB/'Game.exe')],cwd=str(LAB),stdout=stdout,stderr=stderr)
            (EVIDENCE / 'running.json').write_text(json.dumps({'case':label,'attempt':attempt,'pid':process.pid}),encoding='utf-8')
            print(json.dumps({'case':label,'attempt':attempt,'pid':process.pid}),flush=True)
            try:
                process.wait(timeout=50)
            except subprocess.TimeoutExpired:
                print('Still running; read running.json and native output before continuing')
                sys.exit(2)
        if not notice.exists():
            break
        message=notice.read_text()
        assert 'configured' in message,message
        assert attempt==0,'Order correction must converge after one restart'
        original=(LAB/'load-order-before.ini').read_bytes()
        assert (LAB/'UserData/GameMods.ini.free-combat-order.bak').read_bytes()==original,'Previous INI was not backed up exactly'
        previous=configparser.ConfigParser();previous.optionxform=str
        previous.read_string(original.decode('utf-8-sig'))
        current=configparser.ConfigParser();current.optionxform=str
        current.read(LAB/'UserData/GameMods.ini',encoding='utf-8-sig')
        for section in previous.sections():
            for key,value in previous[section].items():
                if key!='LoadOrder':
                    assert current[section][key]==value,(section,key)
        shutil.copy2(notice,EVIDENCE/(label+'-reorder.txt'))
        shutil.copy2(LAB/'load-order-before.ini',EVIDENCE/(label+'-before.ini'))
        shutil.copy2(LAB/'UserData/GameMods.ini',EVIDENCE/(label+'-after.ini'))
        print('PASS: order saved, flags/custom settings unchanged, original INI backed up; restarting private fixture',flush=True)
    for path in LAB.glob('mod-compat-*.txt'):
        shutil.copy2(path,EVIDENCE/(label+'-'+path.name))
    complete = LAB/'mod-compat-complete.txt'
    summary = complete.read_text() if complete.exists() else 'No completion; inspect failure/stdout'
    print(summary)
    if not complete.exists() or '0 failed' not in summary:
        sys.exit(1)


if __name__ == '__main__':
    main()
