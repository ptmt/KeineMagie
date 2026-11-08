"""Deterministic manual-signing configuration; no third-party dependencies."""
import datetime as dt
import re
import uuid


def validate_certificate_subject(subject):
    if not re.search(r'(?:^|,)CN=Apple Distribution:[^,]+(?:,|$)', subject) or not re.search(
        r'(?:^|,)OU=49PJNAT2WC(?:,|$)', subject
    ):
        raise ValueError('Certificate must be Apple Distribution for team 49PJNAT2WC')


def install_profiles(root, home):
    import json
    import os
    from pathlib import Path

    root, home = Path(root), Path(home)
    profile_uuid = (root / 'profile-uuid').read_text().strip()
    if not re.fullmatch(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', profile_uuid):
        raise ValueError('Invalid canonical profile UUID')
    paths = [home / directory / (profile_uuid + '.mobileprovision') for directory in (
        'Library/MobileDevice/Provisioning Profiles',
        'Library/Developer/Xcode/UserData/Provisioning Profiles',
    )]
    for path in paths:
        if os.path.lexists(path):
            raise FileExistsError(f'Refusing to replace existing profile: {path}')
    source = root / 'profile.mobileprovision'
    import shutil

    journal = root / 'profile-install.json'
    record = {'uuid': profile_uuid, 'files': {}}

    def save():
        temporary = journal.with_suffix('.pending')
        with temporary.open('w') as stream:
            json.dump(record, stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, journal)

    save()
    for path in paths:
        path.parent.mkdir(parents=True, exist_ok=True)
        # O_EXCL atomically refuses files/symlinks appearing after preflight.
        # Each destination is a regular file, including across filesystems.
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'wb') as destination:
            metadata = os.fstat(destination.fileno())
            record['files'][str(path)] = {
                'device': metadata.st_dev, 'inode': metadata.st_ino,
                'birthtime': getattr(metadata, 'st_birthtime', None),
            }
            try:
                save()  # Ownership is durable before copying any sensitive bytes.
            except BaseException:
                current = path.lstat()
                if (current.st_dev, current.st_ino) == (metadata.st_dev, metadata.st_ino):
                    path.unlink()
                raise
            with source.open('rb') as incoming:
                shutil.copyfileobj(incoming, destination)
            destination.flush()
            os.fsync(destination.fileno())


def profile_diagnostics(root, home):
    """Decode only our installed files; print a strict nonsecret allowlist."""
    import json
    from pathlib import Path
    import plistlib
    import stat
    import subprocess

    root, home = Path(root), Path(home)
    profile_uuid = (root / 'profile-uuid').read_text().strip()
    expected_name = (root / 'profile-name').read_text()
    for directory in ('Library/MobileDevice/Provisioning Profiles',
                      'Library/Developer/Xcode/UserData/Provisioning Profiles'):
        path = home / directory / (profile_uuid + '.mobileprovision')
        record = {'path': str(path), 'exists': path.exists()}
        if not path.exists():
            print(json.dumps(record))
            raise ValueError('Installed profile missing')
        metadata = path.lstat()
        record.update(bytes=metadata.st_size, links=metadata.st_nlink,
                      regular=stat.S_ISREG(metadata.st_mode))
        decoded = subprocess.run(['security', 'cms', '-D', '-i', str(path)], capture_output=True)
        if decoded.returncode:
            print(json.dumps(record))
            raise ValueError('Installed profile cannot be decoded')
        profile = plistlib.loads(decoded.stdout)
        record.update(uuid=profile.get('UUID'), name=profile_name(profile))
        print(json.dumps(record))
        if not record['regular'] or not record['bytes'] or record['uuid'] != profile_uuid or record['name'] != expected_name:
            raise ValueError('Installed profile metadata differs from validated selection')


def cleanup_profiles(root, home):
    import json
    from pathlib import Path

    root, home = Path(root), Path(home)
    journal = root / 'profile-install.json'
    if not journal.exists():
        return
    record = json.loads(journal.read_text())
    profile_uuid = record['uuid']
    if not re.fullmatch(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', profile_uuid):
        raise ValueError('Invalid canonical profile UUID in cleanup journal')
    errors = []
    for directory in ('Library/MobileDevice/Provisioning Profiles',
                      'Library/Developer/Xcode/UserData/Provisioning Profiles'):
        path = home / directory / (profile_uuid + '.mobileprovision')
        try:
            stat = path.lstat()
            # Accept the old shared-inode journal for interrupted older runs.
            owned = record.get('files', {}).get(str(path)) if 'files' in record else record
            if owned is None or (stat.st_dev, stat.st_ino) != (owned['device'], owned['inode']):
                raise ValueError('Refusing to delete an unowned provisioning profile')
            if owned.get('birthtime') is not None and stat.st_birthtime != owned['birthtime']:
                raise ValueError('Refusing to delete a replaced provisioning profile')
            path.unlink()
        except FileNotFoundError:
            continue
        except (OSError, ValueError) as exc:
            errors.append(str(exc))
    if errors:
        raise OSError('; '.join(errors))


BUILD_EPOCH = dt.datetime(2026, 1, 1, tzinfo=dt.timezone.utc)


def validate_build_number(value):
    if not isinstance(value, str) or not re.fullmatch(r'[1-9][0-9]{0,3}\.[0-9]{1,2}\.[0-9]{1,2}', value):
        raise ValueError('Build number must have three numeric components (4/2/2 digits)')
    return value


def build_number(now=None):
    now = now or dt.datetime.now(dt.timezone.utc)
    if now.tzinfo is None:
        raise ValueError('Build time must be timezone-aware')
    seconds = int((now.astimezone(dt.timezone.utc) - BUILD_EPOCH).total_seconds() // 1)
    if not 0 <= seconds < 99990000:
        raise ValueError('Build time outside supported epoch horizon')
    major, remainder = divmod(seconds, 10000)
    minor, patch = divmod(remainder, 100)
    return validate_build_number(f'{major + 1}.{minor}.{patch}')


TEAM = '49PJNAT2WC'
BUNDLE = 'de.keinemagie.app'


def profile_name(profile):
    name = profile.get('Name')
    if not isinstance(name, str) or not name.strip() or any(not c.isprintable() for c in name):
        raise ValueError('Profile Name must be nonempty printable text')
    return name


def validate_profile(profile, certificate_der, now=None):
    profile_name(profile)
    now = now or dt.datetime.now(dt.timezone.utc)
    ent = profile.get('Entitlements', {})
    def utc(value):
        if not isinstance(value, dt.datetime):
            raise ValueError('Profile dates missing')
        return value.replace(tzinfo=dt.timezone.utc) if value.tzinfo is None else value

    try:
        profile_uuid = profile['UUID']
        if not isinstance(profile_uuid, str) or not re.fullmatch(
            r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', profile_uuid
        ):
            raise ValueError('Invalid profile UUID')
        uuid.UUID(profile_uuid)
    except (KeyError, ValueError, TypeError, AttributeError) as exc:
        raise ValueError('Invalid profile UUID') from exc
    checks = (
        profile.get('TeamIdentifier') == [TEAM],
        'iOS' in profile.get('Platform', []),
        utc(profile.get('CreationDate')) <= now < utc(profile.get('ExpirationDate')),
        'ProvisionedDevices' not in profile,
        not profile.get('ProvisionsAllDevices', False),
        ent.get('get-task-allow') is False,
        ent.get('beta-reports-active') is True,
        ent.get('application-identifier') == f'{TEAM}.{BUNDLE}',
        ent.get('com.apple.developer.team-identifier') == TEAM,
        ent.get('com.apple.developer.applesignin') == ['Default'],
        certificate_der in profile.get('DeveloperCertificates', []),
    )
    if not all(checks):
        raise ValueError('Profile must be current iOS App Store, exact team/app, Apple sign-in, and match certificate')
    return profile_uuid



def export_options(profile_uuid, certificate_sha1):
    return {
        'method': 'app-store-connect', 'destination': 'export',
        'teamID': TEAM, 'signingStyle': 'manual',
        'signingCertificate': certificate_sha1,
        'provisioningProfiles': {BUNDLE: profile_uuid},
        'manageAppVersionAndBuildNumber': False,
        'stripSwiftSymbols': True, 'uploadSymbols': True,
    }


if __name__ == '__main__':
    import hashlib
    from pathlib import Path
    import plistlib
    import sys

    if sys.argv[1:] == ['--build-number']:
        print(build_number())
    elif sys.argv[1:2] in (['--install-profiles'], ['--cleanup-profiles'], ['--profile-diagnostics']):
        import os
        operation = {'--install-profiles': install_profiles, '--cleanup-profiles': cleanup_profiles,
                     '--profile-diagnostics': profile_diagnostics}[sys.argv[1]]
        operation(Path(sys.argv[2]), Path(os.environ['HOME']))
    else:
        root = Path(sys.argv[1])
        try:
            certificate = (root / 'cert.der').read_bytes()
            validate_certificate_subject((root / 'subject.txt').read_text().strip())
            profile = plistlib.loads((root / 'profile.plist').read_bytes())
            profile_uuid = validate_profile(profile, certificate)
            (root / 'profile-name').write_text(profile_name(profile))
            fingerprint = hashlib.sha1(certificate).hexdigest().upper()
            (root / 'ExportOptions.plist').write_bytes(plistlib.dumps(export_options(profile_uuid, fingerprint)))
            (root / 'profile-uuid').write_text(profile_uuid)
            (root / 'certificate-sha1').write_text(fingerprint)
        except (ValueError, KeyError, TypeError) as exc:
            sys.exit(str(exc))
