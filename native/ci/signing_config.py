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
    if not re.fullmatch(r'[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}', profile_uuid):
        raise ValueError('Invalid canonical profile UUID')
    paths = [home / directory / (profile_uuid + '.mobileprovision') for directory in (
        'Library/MobileDevice/Provisioning Profiles',
        'Library/Developer/Xcode/UserData/Provisioning Profiles',
    )]
    for path in paths:
        if os.path.lexists(path):
            raise FileExistsError(f'Refusing to replace existing profile: {path}')
    source = root / 'profile.mobileprovision'
    stat = source.stat()
    # Journal before mutation; hard links make ownership atomic and verifiable.
    (root / 'profile-install.json').write_text(json.dumps({
        'uuid': profile_uuid, 'device': stat.st_dev, 'inode': stat.st_ino,
    }))
    for path in paths:
        path.parent.mkdir(parents=True, exist_ok=True)
        os.link(source, path)


def cleanup_profiles(root, home):
    import json
    from pathlib import Path

    root, home = Path(root), Path(home)
    journal = root / 'profile-install.json'
    if not journal.exists():
        return
    record = json.loads(journal.read_text())
    profile_uuid = record['uuid']
    if not re.fullmatch(r'[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}', profile_uuid):
        raise ValueError('Invalid canonical profile UUID in cleanup journal')
    errors = []
    for directory in ('Library/MobileDevice/Provisioning Profiles',
                      'Library/Developer/Xcode/UserData/Provisioning Profiles'):
        path = home / directory / (profile_uuid + '.mobileprovision')
        try:
            stat = path.lstat()
            if (stat.st_dev, stat.st_ino) != (record['device'], record['inode']):
                raise ValueError('Refusing to delete an unowned provisioning profile')
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


def validate_profile(profile, certificate_der, now=None):
    now = now or dt.datetime.now(dt.timezone.utc)
    ent = profile.get('Entitlements', {})
    def utc(value):
        if not isinstance(value, dt.datetime):
            raise ValueError('Profile dates missing')
        return value.replace(tzinfo=dt.timezone.utc) if value.tzinfo is None else value

    try:
        profile_uuid = str(uuid.UUID(profile['UUID']))
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
    return profile_uuid.upper()



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
    elif sys.argv[1:2] in (['--install-profiles'], ['--cleanup-profiles']):
        import os
        operation = install_profiles if sys.argv[1] == '--install-profiles' else cleanup_profiles
        operation(Path(sys.argv[2]), Path(os.environ['HOME']))
    else:
        root = Path(sys.argv[1])
        try:
            certificate = (root / 'cert.der').read_bytes()
            validate_certificate_subject((root / 'subject.txt').read_text().strip())
            profile_uuid = validate_profile(plistlib.loads((root / 'profile.plist').read_bytes()), certificate)
            fingerprint = hashlib.sha1(certificate).hexdigest().upper()
            (root / 'ExportOptions.plist').write_bytes(plistlib.dumps(export_options(profile_uuid, fingerprint)))
            (root / 'profile-uuid').write_text(profile_uuid)
            (root / 'certificate-sha1').write_text(fingerprint)
        except (ValueError, KeyError, TypeError) as exc:
            sys.exit(str(exc))
