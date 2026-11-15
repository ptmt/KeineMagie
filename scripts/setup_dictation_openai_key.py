#!/usr/bin/env python3
"""Owner-operated local secret entry. Does not enable TTS or contact OpenAI."""
import getpass
import os
from pathlib import Path
import sys

DESTINATION=Path.home()/'.config'/'keinemagie'/'secrets'/'dictation-openai.key'

def save_secret(path, key):
    path=Path(path)
    if not key or len(key)>4096 or any(c.isspace() for c in key):
        raise ValueError('Invalid secret format')
    if not path.is_absolute() or any(p.is_symlink() for p in (path,*path.parents)):
        raise ValueError('Secret path must be absolute and not use symlinks')
    path.parent.mkdir(parents=True,mode=0o700,exist_ok=True)
    os.chmod(path.parent,0o700)
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    with os.fdopen(fd,'w') as file:
        file.write(key+'\n');file.flush();os.fsync(file.fileno())
    directory=os.open(path.parent,os.O_RDONLY)
    try:os.fsync(directory)
    finally:os.close(directory)

def main():
    if not sys.stdin.isatty() or not sys.stderr.isatty():
        raise SystemExit('Run this yourself in a local interactive terminal, not chat or CI.')
    if DESTINATION.exists():
        raise SystemExit('Dedicated secret already exists. No overwrite performed.')
    print('Enter a new project-scoped OpenAI key. Input is hidden. No API call will run.')
    key=getpass.getpass('Diktat project key: ')
    try:save_secret(DESTINATION,key)
    except (OSError,ValueError):raise SystemExit('Could not save dedicated secret. No provider call made.')
    finally:key=''
    print('Saved private secret at '+str(DESTINATION))
    print('TTS remains disabled until explicitly configured. Do not paste the key into chat.')

if __name__=='__main__':main()
