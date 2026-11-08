"""Offline tests use synthetic provisioning metadata, never Apple credentials."""
import datetime as dt
import importlib.util
from pathlib import Path
import unittest

PATH = Path(__file__).with_name('signing_config.py')


class SigningConfigTests(unittest.TestCase):
    def test_export_options_are_manual_for_exact_app(self):
        self.assertTrue(PATH.exists(), 'signing configuration helper is missing')
        spec = importlib.util.spec_from_file_location('signing_config', PATH)
        assert spec is not None and spec.loader is not None
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertEqual(module.export_options('PROFILE', 'A' * 40), {
            'method': 'app-store-connect', 'destination': 'export',
            'teamID': '49PJNAT2WC', 'signingStyle': 'manual',
            'signingCertificate': 'A' * 40,
            'provisioningProfiles': {'de.keinemagie.app': 'PROFILE'},
            'manageAppVersionAndBuildNumber': False,
            'stripSwiftSymbols': True, 'uploadSymbols': True,
        })

    def test_profile_must_be_current_app_store_apple_signin_and_match_certificate(self):
        import copy
        import signing_config as config
        self.assertTrue(hasattr(config, 'validate_profile'), 'profile validator missing')
        now = dt.datetime(2026, 11, 8, tzinfo=dt.timezone.utc)
        profile = {
            'UUID': 'FD91EDAC-8DF3-4AEF-9081-3028F101E204', 'Name': 'App Store',
            'TeamIdentifier': ['49PJNAT2WC'], 'Platform': ['iOS'],
            'CreationDate': dt.datetime(2026, 1, 1),
            'ExpirationDate': dt.datetime(2027, 1, 1),
            'DeveloperCertificates': [b'certificate'],
            'Entitlements': {
                'application-identifier': '49PJNAT2WC.de.keinemagie.app',
                'com.apple.developer.team-identifier': '49PJNAT2WC',
                'com.apple.developer.applesignin': ['Default'],
                'get-task-allow': False, 'beta-reports-active': True,
            },
        }
        self.assertEqual(config.validate_profile(profile, b'certificate', now), profile['UUID'])
        mutations = [
            ('TeamIdentifier', ['WRONG']), ('Platform', ['macOS']),
            ('ExpirationDate', dt.datetime(2026, 1, 1)),
            ('CreationDate', dt.datetime(2027, 1, 1)),
            ('DeveloperCertificates', [b'wrong']), ('UUID', '../escape'),
            ('ProvisionedDevices', ['DEVICE']), ('ProvisionsAllDevices', True),
        ]
        for key, value in mutations:
            invalid = copy.deepcopy(profile)
            invalid[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                config.validate_profile(invalid, b'certificate', now)
        for key, value in [
            ('application-identifier', '49PJNAT2WC.*'),
            ('com.apple.developer.team-identifier', 'WRONG'),
            ('com.apple.developer.applesignin', []),
            ('get-task-allow', True), ('beta-reports-active', False),
        ]:
            invalid = copy.deepcopy(profile)
            invalid['Entitlements'][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                config.validate_profile(invalid, b'certificate', now)
    def test_certificate_requires_distribution_and_exact_team(self):
        import signing_config as config
        self.assertTrue(hasattr(config, 'validate_certificate_subject'), 'certificate validator missing')
        config.validate_certificate_subject('CN=Apple Distribution: Example (49PJNAT2WC),OU=49PJNAT2WC,O=Example,C=DE')
        for subject in ['CN=Apple Development: Example,OU=49PJNAT2WC',
                        'CN=Apple Distribution: Example,OU=WRONG',
                        'CN=Apple Distribution: Example,OU=49PJNAT2WCFAKE']:
            with self.subTest(subject=subject), self.assertRaises(ValueError):
                config.validate_certificate_subject(subject)

    def test_timestamp_build_version_is_numeric_and_ordered(self):
        import signing_config as config
        self.assertTrue(hasattr(config, 'build_number'), 'build number generator missing')
        now = dt.datetime(2026, 11, 8, 12, 34, 56, tzinfo=dt.timezone.utc)
        value = config.build_number(now)
        self.assertTrue(value.isdigit())
        self.assertEqual(value, '20261108123456')
        self.assertGreater(int(config.build_number(now + dt.timedelta(seconds=1))), int(value))
    def test_cli_generates_plist_and_nonsecret_build_settings(self):
        import plistlib
        import subprocess
        import tempfile
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            result = subprocess.run(['python3', str(PATH), '--build-number'], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertRegex(result.stdout.strip(), r'^\d{14}$')
            # Invalid profile must fail closed, before producing export configuration.
            (root / 'profile.plist').write_bytes(plistlib.dumps({}))
            (root / 'cert.der').write_bytes(b'certificate')
            (root / 'subject.txt').write_text('CN=Apple Distribution: Example,OU=49PJNAT2WC')
            result = subprocess.run(['python3', str(PATH), str(root)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((root / 'ExportOptions.plist').exists())

    def test_cleanup_removes_only_owned_profile_and_restores_search_list(self):
        import os
        import subprocess
        import tempfile
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            home = root / 'home'
            owned = root / 'km-testflight.test1234'
            owned.mkdir()
            (owned / 'owned-by-testflight').touch()
            (owned / 'keychains-before').write_text('/original/path with spaces.keychain-db\n')
            (owned / 'keychain-path').write_text(str(owned / 'signing.keychain-db') + '\n')
            (owned / 'signing.keychain-db').touch()
            profiles = home / 'Library/Developer/Xcode/UserData/Provisioning Profiles'
            profiles.mkdir(parents=True)
            other = profiles / 'existing.mobileprovision'
            other.write_text('must survive')
            installed = profiles / ('km-' + owned.name + '.mobileprovision')
            installed.write_text('owned profile')
            (owned / 'profile-path').write_text(str(installed) + '\n')
            (owned / 'distribution.p12').write_text('sensitive test fixture')
            tools = root / 'bin'
            tools.mkdir()
            log = root / 'calls'
            security = tools / 'security'
            security.write_text('#!/bin/bash\nprintf "%s\\n" "$@" >> "$CALL_LOG"\nexit "${FAIL_SECURITY:-0}"\n')
            security.chmod(0o700)
            env = dict(os.environ, HOME=str(home), PATH=str(tools) + ':' + os.environ['PATH'], CALL_LOG=str(log))
            command = ['bash', str(PATH.with_name('cleanup.sh')), str(owned)]
            result = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(owned.exists())
            self.assertFalse(installed.exists())
            self.assertEqual(other.read_text(), 'must survive')
            self.assertIn('/original/path with spaces.keychain-db', log.read_text())
            self.assertEqual(subprocess.run(command, env=env, capture_output=True).returncode, 0)

    def test_cleanup_retains_recovery_metadata_if_keychain_restore_fails(self):
        import os
        import subprocess
        import tempfile
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            owned = root / 'km-testflight.failed123'
            owned.mkdir()
            (owned / 'owned-by-testflight').touch()
            (owned / 'keychains-before').write_text('/original.keychain-db\n')
            (owned / 'distribution.p12').write_text('sensitive test fixture')
            tools = root / 'bin'
            tools.mkdir()
            security = tools / 'security'
            security.write_text('#!/bin/bash\nexit 1\n')
            security.chmod(0o700)
            env = dict(os.environ, PATH=str(tools) + ':' + os.environ['PATH'])
            result = subprocess.run(['bash', str(PATH.with_name('cleanup.sh')), str(owned)], env=env, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue((owned / 'keychains-before').exists(), 'always() cleanup needs restoration metadata for retry')
            self.assertFalse((owned / 'distribution.p12').exists())


if __name__ == '__main__':
    unittest.main()
