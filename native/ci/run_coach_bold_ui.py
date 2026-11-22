"""Serial local acceptance; only the two approved existing simulators."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = Path('/Users/tinyserve/.hermes/cache/scratch')
EVIDENCE = ROOT / 'docs/coach-bold-glass-evidence'
SELECTION = ['ActivityUITests', 'CoachStableChatUITests', 'CoachGlassUITests'] + [
    'CoachUITests/' + name for name in (
        'testComposerMenuOpensWithoutSendingOrRevealing',
        'testMenuSelectionUsesOriginalRoutesExactlyOnceAndKeepsFocus',
        'testMenuIncludesEveryAvailableAction',
        'testLargestRussianNativeComposerPlaceholderFits',
        'testChatDesignCompactAnswerControls',
        'testAccessibilityReadingOrderAndLabels')]
DEVICES = [('normal', '93E1113F-6736-4CCB-827D-0E2F1C3876EA'), ('se', '56A70197-59DE-4410-9E76-25272244E9C8')]

def run(*args, **kw):
    return subprocess.run(args, check=True, text=True, **kw)

def export(result, destination):
    destination.mkdir(parents=True, exist_ok=True)
    summary = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(result), '--format', 'json']))
    (destination/'summary.json').write_text(json.dumps(summary, indent=2)+'\n')
    raw = SCRATCH / (result.stem+'-attachments')
    run('xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result), '--output-path', str(raw))
    manifest = json.loads((raw/'manifest.json').read_text())
    receipts = []
    for test in manifest:
        for item in test['attachments']:
            original = raw/item['exportedFileName']
            if original.suffix not in ('.png', '.txt'): continue
            name = item['suggestedHumanReadableName'].split('_0_')[0] + original.suffix
            target = destination/name
            shutil.copyfile(original, target)
            receipts.append({'file': name, 'sha256': hashlib.sha256(target.read_bytes()).hexdigest(), 'test': test['testIdentifier'], 'original': item['exportedFileName']})
    (destination/'manifest.json').write_text(json.dumps(receipts, indent=2)+'\n')
    return summary

if __name__ == '__main__':
    for device_name, udid in DEVICES:
        state = json.loads(subprocess.check_output(['xcrun','simctl','list','devices','--json']))
        device = next(d for items in state['devices'].values() for d in items if d['udid']==udid)
        if device['state'] != 'Booted': run('xcrun','simctl','boot',udid)
        run('xcrun','simctl','bootstatus',udid,'-b')
        try:
            for theme in ('light','dark'):
                label = f'{device_name}-{theme}'
                run('xcrun','simctl','ui',udid,'appearance',theme)
                result = SCRATCH/f'km-bold-final-{label}.xcresult'
                command = ['xcodebuild','-quiet','-project',str(ROOT/'native/KeineMagie.xcodeproj'),'-scheme','KeineMagie','-configuration','Release','-destination',f'platform=iOS Simulator,id={udid}','-parallel-testing-enabled','NO','-maximum-concurrent-test-simulator-destinations','1','-derivedDataPath',str(SCRATCH/'km-bold-derived'),'-resultBundlePath',str(result)]
                command += ['-only-testing:KeineMagieUITests/'+test for test in SELECTION]
                command += ['CODE_SIGN_IDENTITY=-','CODE_SIGNING_ALLOWED=YES','test']
                with (SCRATCH/f'km-bold-final-{label}.log').open('w') as log:
                    status = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT).returncode
                summary = export(result, EVIDENCE/label)
                print(label, status, summary['passedTests'], summary['failedTests'], flush=True)
                if status or summary['failedTests']: raise SystemExit(1)
        finally:
            run('xcrun','simctl','ui',udid,'appearance','dark')
            run('xcrun','simctl','shutdown',udid)
