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
        lowercase = copy.deepcopy(profile)
        lowercase['UUID'] = profile['UUID'].lower()
        self.assertEqual(config.validate_profile(lowercase, b'certificate', now), lowercase['UUID'],
                         'Preserve the profile identifier, not an uppercased approximation')
        mutations = [
            ('TeamIdentifier', ['WRONG']), ('Platform', ['macOS']),
            ('ExpirationDate', dt.datetime(2026, 1, 1)),
            ('CreationDate', dt.datetime(2027, 1, 1)),
            ('DeveloperCertificates', [b'wrong']), ('UUID', '../escape'),
            ('UUID', 'FD91EDAC8DF34AEF90813028F101E204'), ('Name', ''),
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
    def test_archive_uses_uuid_and_validated_name_with_selected_xcode_diagnostics(self):
        script = PATH.with_name('testflight.sh').read_text()
        self.assertIn('profile_name="$(< "$root/profile-name")"', script)
        # Standard xcodebuild overrides reach every SwiftPM target, including
        # resource bundles that cannot accept provisioning profiles.
        archive_args = script.split('archive_args=(', 1)[1].split('\n#', 1)[0]
        import re
        for setting in ('CODE_SIGN_STYLE', 'CODE_SIGN_IDENTITY',
                        'PROVISIONING_PROFILE', 'PROVISIONING_PROFILE_SPECIFIER',
                        'OTHER_CODE_SIGN_FLAGS'):
            self.assertIsNone(re.search(r'(?<![A-Z_])' + setting + '=', archive_args), setting)
        for setting, value in (('CODE_SIGN_STYLE', 'Manual'),
                               ('CODE_SIGN_IDENTITY', '"$fingerprint"'),
                               ('PROVISIONING_PROFILE', '"$uuid"'),
                               ('PROVISIONING_PROFILE_SPECIFIER', '"$profile_name"'),
                               ('OTHER_CODE_SIGN_FLAGS', '"--keychain $keychain"')):
            self.assertIn(f'KM_CI_{setting}={value}', archive_args)
        project = PATH.parent.parent.joinpath('project.yml').read_text()
        project_settings, app = project.split('targets:\n  KeineMagie:', 1)
        self.assertNotIn('KM_CI_', project_settings)
        self.assertIn('CODE_SIGN_STYLE: Automatic', project_settings)
        self.assertIn('KM_CI_CODE_SIGN_STYLE: Automatic', app)
        self.assertIn('KM_CI_CODE_SIGN_IDENTITY: Apple Development', app)
        for setting in ('CODE_SIGN_STYLE', 'PROVISIONING_PROFILE',
                        'PROVISIONING_PROFILE_SPECIFIER', 'OTHER_CODE_SIGN_FLAGS'):
            self.assertIn(f'{setting}: "$(KM_CI_{setting})"', app)
        self.assertIn('"CODE_SIGN_IDENTITY[sdk=iphoneos*]": "$(KM_CI_CODE_SIGN_IDENTITY)"', app)
        self.assertIn('--profile-diagnostics', script)
        self.assertIn('-showBuildSettings -json', script)
        self.assertIn('EXPANDED_PROVISIONING_PROFILE', script)
        self.assertNotIn('PROVISIONING_PROFILE_SPECIFIER="$uuid"', script)

    def test_profile_name_is_required_and_preserved_without_log_injection(self):
        import signing_config as config
        self.assertTrue(hasattr(config, 'profile_name'), 'validated Name accessor missing')
        self.assertEqual(config.profile_name({'Name': 'KeineMagie App Store CI'}), 'KeineMagie App Store CI')
        for name in (None, '', '   ', 'bad\n::warning::injected', 'bad\rname', 'bad\x00name', 'bad\x1bname'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                config.profile_name({'Name': name})
        with self.assertRaises(ValueError):
            config.profile_name({})

    def test_certificate_requires_distribution_and_exact_team(self):
        import signing_config as config
        self.assertTrue(hasattr(config, 'validate_certificate_subject'), 'certificate validator missing')
        config.validate_certificate_subject('CN=Apple Distribution: Example (49PJNAT2WC),OU=49PJNAT2WC,O=Example,C=DE')
        for subject in ['CN=Apple Development: Example,OU=49PJNAT2WC',
                        'CN=Apple Distribution: Example,OU=WRONG',
                        'CN=Apple Distribution: Example,OU=49PJNAT2WCFAKE']:
            with self.subTest(subject=subject), self.assertRaises(ValueError):
                config.validate_certificate_subject(subject)

    def test_build_version_is_apple_bounded_and_seconds_ordered(self):
        import signing_config as config
        epoch = dt.datetime(2026, 1, 1, tzinfo=dt.timezone.utc)
        previous = None
        for seconds in (0, 1, 99, 100, 9999, 10000, 86399, 86400, 99989999):
            now = epoch + dt.timedelta(seconds=seconds)
            value = config.build_number(now)
            self.assertRegex(value, r'^[1-9][0-9]{0,3}\.[0-9]{1,2}\.[0-9]{1,2}$')
            parts = tuple(map(int, value.split('.')))
            if previous is not None:
                self.assertGreater(parts, previous)
            previous = parts
            self.assertEqual(config.build_number(now.astimezone(dt.timezone(dt.timedelta(hours=3)))), value)
        for now in (epoch - dt.timedelta(seconds=1), epoch + dt.timedelta(seconds=99990000)):
            with self.assertRaises(ValueError):
                config.build_number(now)

    def test_build_number_validator_rejects_oversized_or_malformed_versions(self):
        import signing_config as config
        for value in ('1.0.0', '9999.99.99'):
            self.assertEqual(config.validate_build_number(value), value)
        for value in ('20261108123456', '10000.0.0', '1.100.0', '1.0.100',
                      '0.1.1', '1.2', '1.2.3.4', '1.2.3b1', '1.2.3\n', None):
            with self.subTest(value=value), self.assertRaises(ValueError):
                config.validate_build_number(value)

    def test_cli_generates_plist_and_nonsecret_build_settings(self):
        import plistlib
        import subprocess
        import tempfile
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            result = subprocess.run(['python3', str(PATH), '--build-number'], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertRegex(result.stdout.strip(), r'^[1-9][0-9]{0,3}\.[0-9]{1,2}\.[0-9]{1,2}$')
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
