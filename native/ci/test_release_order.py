"""Publication must be explicitly dispatched after backend readback."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class ReleaseOrderTests(unittest.TestCase):
    def test_upload_requires_explicit_dispatch_confirmation(self):
        workflow = (ROOT.parent / '.github/workflows/ios-testflight.yml').read_text()
        condition = workflow.split('  testflight:\n', 1)[1].split('    needs:', 1)[0]
        self.assertNotIn("github.event_name == 'push'", condition)
        self.assertIn("github.event_name == 'workflow_dispatch'", condition)
        self.assertIn("inputs.publish == 'UPLOAD'", condition)
        self.assertIn('publish:', workflow)
        script = (ROOT / 'ci/testflight.sh').read_text()
        self.assertIn('${KM_PUBLISH_CONFIRMATION:-}', script)
        self.assertIn('UPLOAD', script)
