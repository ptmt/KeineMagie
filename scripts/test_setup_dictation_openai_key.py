"""Secret writer tests use synthetic strings only; never contact a provider."""
import importlib.util
import pathlib
import tempfile
import unittest

SPEC=importlib.util.spec_from_file_location('setup',pathlib.Path(__file__).with_name('setup_dictation_openai_key.py'))
assert SPEC is not None and SPEC.loader is not None
SETUP=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SETUP)

class SecretTests(unittest.TestCase):
 def test_private_exclusive_file(self):
  with tempfile.TemporaryDirectory(dir=pathlib.Path.home()/'.hermes'/'cache'/'scratch') as tmp:
   p=pathlib.Path(tmp)/'secrets'/'dictation-openai.key'
   SETUP.save_secret(p,'synthetic-test-key')
   self.assertEqual(p.stat().st_mode&0o777,0o600)
   self.assertEqual(p.parent.stat().st_mode&0o777,0o700)
   self.assertEqual(p.read_text(),'synthetic-test-key\n')
   with self.assertRaises(FileExistsError):SETUP.save_secret(p,'replacement')
   self.assertEqual(p.read_text(),'synthetic-test-key\n')
 def test_rejects_symlink_and_whitespace(self):
  with tempfile.TemporaryDirectory(dir=pathlib.Path.home()/'.hermes'/'cache'/'scratch') as tmp:
   root=pathlib.Path(tmp);(root/'real').mkdir();(root/'link').symlink_to(root/'real',target_is_directory=True)
   with self.assertRaises(ValueError):SETUP.save_secret(root/'link'/'key','synthetic')
   with self.assertRaises(ValueError):SETUP.save_secret(root/'real'/'key','bad\nkey')
if __name__=='__main__':unittest.main()
