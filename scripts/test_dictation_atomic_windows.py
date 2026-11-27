import pathlib,json,subprocess,os,sys
repo=pathlib.Path(__file__).resolve().parents[1]
s=pathlib.Path(sys.argv[1]) if len(sys.argv)>1 else repo/'scratch'/'dictation-atomic-windows';s.mkdir(parents=True,exist_ok=True)
source=(repo/'server/learning.go').read_text();start=source.index('func learningAtomicJSON(');end=source.index('\nfunc learningLevel(',start);body=source[start:end]
for call,before,after in [('if _, e = f.Write(b); e != nil {\n\t\treturn e\n\t}', 'before-write','after-write'),('if e = f.Sync(); e != nil {\n\t\treturn e\n\t}','before-file-sync','after-file-sync'),('if e = f.Close(); e != nil {\n\t\treturn e\n\t}','before-close','after-close'),('if e = os.Rename(f.Name(), path); e != nil {\n\t\treturn e\n\t}','before-rename','after-rename')]:
 assert body.count(call)==1,call
 body=body.replace(call,'dictationInjectedKill(path,"'+before+'")\n\t'+call+'\n\tdictationInjectedKill(path,"'+after+'")')
assert body.count('return dir.Sync()')==1
body=body.replace('return dir.Sync()','dictationInjectedKill(path,"before-dir-sync")\n\te=dir.Sync()\n\tdictationInjectedKill(path,"after-dir-sync")\n\treturn e')
helper='\nfunc dictationInjectedKill(path,point string) { if os.Getenv("KM_ATOMIC_KILL_PATH")==path && os.Getenv("KM_ATOMIC_KILL_POINT")==point { p,_:=os.FindProcess(os.Getpid());_ = p.Kill();select{} } }\n'
(s/'learning.go').write_text(source[:start]+body+source[end:]+helper)
overlay={'Replace':{str(repo/'server/learning.go'):str(s/'learning.go'),str(repo/'server/dictation_settlement_crash_test.go'):str(repo/'scripts/fixtures/dictation_atomic_windows_test.go')}}
(s/'overlay.json').write_text(json.dumps(overlay));env=dict(os.environ);env['TMPDIR']=str(s.resolve())
with (s/'sigkill-windows.log').open('w') as log:
 result=subprocess.run(['go','test','-overlay',str(s/'overlay.json'),'-run','^TestDictationInjectedAtomicKillWindows$','-count=1','-v','.'],cwd=repo/'server',env=env,stdout=log,stderr=subprocess.STDOUT)
logtext=(s/'sigkill-windows.log').read_text();assert logtext.count('    --- PASS: TestDictationInjectedAtomicKillWindows/')==40, 'all 40 fault windows must execute'
print('SIGKILL injection exit',result.returncode,'log',s/'sigkill-windows.log')
raise SystemExit(result.returncode)
