"""Focused Release matrix; serial existing devices, no clones or live services."""
import json
import subprocess
from run_coach_bold_ui import ROOT, SCRATCH, DEVICES, run, export

SELECTION = ['CoachStableChatUITests'] + ['CoachUITests/' + name for name in (
    'testChatDesignCompactAnswerControls', 'testLargestRussianNativeComposerPlaceholderFits')]

if __name__ == '__main__':
    for device_name, udid in DEVICES:
        state = json.loads(subprocess.check_output(['xcrun','simctl','list','devices','--json']))
        device = next(d for items in state['devices'].values() for d in items if d['udid'] == udid)
        if device['state'] != 'Shutdown':
            raise SystemExit('Simulator not free: ' + udid)
        run('xcrun','simctl','boot',udid)
        run('xcrun','simctl','bootstatus',udid,'-b')
        appearance = subprocess.check_output(['xcrun','simctl','ui',udid,'appearance'], text=True).strip()
        try:
            for theme in ('light','dark'):
                label = f'{device_name}-{theme}'
                run('xcrun','simctl','ui',udid,'appearance',theme)
                result = SCRATCH/f'km-soft-red-{label}.xcresult'
                command = ['xcodebuild','-quiet','-project',str(ROOT/'native/KeineMagie.xcodeproj'),'-scheme','KeineMagie','-configuration','Release','-destination',f'platform=iOS Simulator,id={udid}','-parallel-testing-enabled','NO','-maximum-concurrent-test-simulator-destinations','1','-derivedDataPath',str(SCRATCH/'km-soft-red-derived'),'-resultBundlePath',str(result)]
                command += ['-only-testing:KeineMagieUITests/'+test for test in SELECTION]
                command += ['CODE_SIGN_IDENTITY=-','CODE_SIGNING_ALLOWED=YES','test']
                with (SCRATCH/f'km-soft-red-{label}.log').open('w') as log:
                    status = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT).returncode
                summary = export(result, ROOT/'docs/coach-soft-red-evidence'/label)
                print(label, status, summary['passedTests'], summary['failedTests'], flush=True)
                if status or summary['failedTests'] or summary['passedTests'] != 6:
                    raise SystemExit(1)
        finally:
            run('xcrun','simctl','ui',udid,'appearance',appearance)
            run('xcrun','simctl','shutdown',udid)
