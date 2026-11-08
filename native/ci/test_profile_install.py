"""Profile discovery/cleanup regressions; isolated HOME, synthetic profile bytes."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

import signing_config as config

UUID = 'D78E856B-FB81-4D46-BB18-7DEAB629BCE7'


class ProfileInstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.home = self.base / 'home'
        self.root = self.base / 'km-testflight.fixture'
        self.root.mkdir()
        (self.root / 'owned-by-testflight').touch()
        (self.root / 'profile-uuid').write_text(UUID)
        (self.root / 'profile.mobileprovision').write_bytes(b'synthetic profile')
        self.paths = [self.home / directory / (UUID + '.mobileprovision') for directory in (
            'Library/MobileDevice/Provisioning Profiles',
            'Library/Developer/Xcode/UserData/Provisioning Profiles',
        )]

    def test_preexisting_profile_fails_before_mutating_either_path(self):
        for existing in self.paths:
            with self.subTest(existing=existing):
                existing.parent.mkdir(parents=True, exist_ok=True)
                existing.write_bytes(b'preexisting profile')
                with self.assertRaises(FileExistsError):
                    config.install_profiles(self.root, self.home)
                self.assertEqual(existing.read_bytes(), b'preexisting profile')
                self.assertFalse(self.paths[1 - self.paths.index(existing)].exists())
                existing.unlink()

    def test_cleanup_continues_after_one_profile_unlink_fails(self):
        config.install_profiles(self.root, self.home)
        unlink = Path.unlink

        def fail_first(path, *args, **kwargs):
            if path == self.paths[0]:
                raise PermissionError('injected unlink failure')
            return unlink(path, *args, **kwargs)

        with mock.patch.object(Path, 'unlink', fail_first):
            with self.assertRaises(OSError):
                config.cleanup_profiles(self.root, self.home)
        self.assertTrue(self.paths[0].exists())
        self.assertFalse(self.paths[1].exists(), 'independent cleanup must still run')
        self.assertTrue((self.root / 'profile-install.json').exists())
        config.cleanup_profiles(self.root, self.home)
        self.assertFalse(self.paths[0].exists())

    def test_partial_install_failure_cleans_owned_link_and_keeps_other_profiles(self):
        other = self.paths[0].with_name('unrelated.mobileprovision')
        other.parent.mkdir(parents=True)
        other.write_bytes(b'keep unrelated')
        link = os.link

        def fail_second(source, destination):
            if destination == self.paths[1]:
                raise OSError('injected second install failure')
            return link(source, destination)

        with mock.patch.object(os, 'link', fail_second):
            with self.assertRaises(OSError):
                config.install_profiles(self.root, self.home)
        self.assertTrue(self.paths[0].exists())
        result = self.cleanup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.paths[0].exists())
        self.assertEqual(other.read_bytes(), b'keep unrelated')

    def test_preexisting_dangling_symlink_is_not_followed_or_replaced(self):
        self.paths[1].parent.mkdir(parents=True)
        self.paths[1].symlink_to(self.base / 'missing')
        with self.assertRaises(FileExistsError):
            config.install_profiles(self.root, self.home)
        self.assertTrue(self.paths[1].is_symlink())
        self.assertFalse(self.paths[0].exists())

    def test_cleanup_preserves_replaced_profile_and_retries_after_keychain_failure(self):
        config.install_profiles(self.root, self.home)
        self.paths[0].unlink()
        self.paths[0].write_bytes(b'unrelated replacement')
        (self.root / 'keychains-before').write_text('/original.keychain-db\n')
        (self.root / 'distribution.p12').write_bytes(b'sensitive')
        tools = self.base / 'bin'
        tools.mkdir()
        security = tools / 'security'
        security.write_text('#!/bin/bash\nexit "${FAIL_SECURITY:-0}"\n')
        security.chmod(0o700)
        env = dict(PATH=str(tools) + ':' + os.environ['PATH'], FAIL_SECURITY='1')
        result = self.cleanup(**env)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.paths[0].read_bytes(), b'unrelated replacement')
        self.assertFalse(self.paths[1].exists())
        self.assertFalse((self.root / 'distribution.p12').exists())
        self.assertFalse((self.root / 'profile.mobileprovision').exists())
        self.assertTrue((self.root / 'profile-install.json').exists())
        self.assertTrue((self.root / 'keychains-before').exists())
        self.paths[0].unlink()  # External owner resolves conflict; retry is idempotent.
        env['FAIL_SECURITY'] = '0'
        self.assertEqual(self.cleanup(**env).returncode, 0)
        self.assertEqual(self.cleanup(**env).returncode, 0)
        self.assertFalse(self.root.exists())

    def test_invalid_uuid_cannot_escape_profile_directories(self):
        (self.root / 'profile-uuid').write_text('../escape')
        with self.assertRaises(ValueError):
            config.install_profiles(self.root, self.home)
        self.assertFalse((self.root / 'profile-install.json').exists())

    def cleanup(self, **env):
        return subprocess.run(
            ['bash', str(Path(__file__).with_name('cleanup.sh')), str(self.root)],
            env=dict(os.environ, HOME=str(self.home), **env), capture_output=True, text=True,
        )

    def test_install_and_cleanup_both_uuid_discovery_paths(self):
        self.assertTrue(hasattr(config, 'install_profiles'), 'canonical profile installer missing')
        config.install_profiles(self.root, self.home)
        for path in self.paths:
            self.assertEqual(path.read_bytes(), b'synthetic profile')
        result = subprocess.run(
            ['bash', str(Path(__file__).with_name('cleanup.sh')), str(self.root)],
            env=dict(os.environ, HOME=str(self.home)), capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.root.exists())
        for path in self.paths:
            self.assertFalse(path.exists(), str(path))


if __name__ == '__main__':
    unittest.main()
