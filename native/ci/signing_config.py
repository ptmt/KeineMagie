"""Deterministic manual-signing configuration; no third-party dependencies."""
import datetime as dt
import re
import uuid


def validate_certificate_subject(subject):
    if not re.search(r'(?:^|,)CN=Apple Distribution:[^,]+(?:,|$)', subject) or not re.search(
        r'(?:^|,)OU=49PJNAT2WC(?:,|$)', subject
    ):
        raise ValueError('Certificate must be Apple Distribution for team 49PJNAT2WC')


def build_number(now=None):
    return (now or dt.datetime.now(dt.timezone.utc)).astimezone(dt.timezone.utc).strftime('%Y%m%d%H%M%S')


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
