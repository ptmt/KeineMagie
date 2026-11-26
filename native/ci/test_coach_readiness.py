"""Wire the tested one-shot recovery fence into readiness task admission."""
from pathlib import Path
import unittest

class CoachReadinessTests(unittest.TestCase):
    def test_readiness_restart_consumes_recovery_fence_before_daily_entry(self):
        source = (Path(__file__).resolve().parents[1]/'App/CoachView.swift').read_text()
        task = source.split('.task(id: "\\(model.session.generation)', 1)[1].split('.refreshable', 1)[0]
        self.assertIn('\\(model.session.canWrite)', task)  # Preserve foreground validation lifecycle.
        self.assertIn('await model.loadCoach()', task)
        self.assertIn('&& model.consumeCoachEntryPermission()', task)
        self.assertLess(task.index('await model.loadCoach()'), task.index('model.consumeCoachEntryPermission()'))
        self.assertLess(task.index('model.consumeCoachEntryPermission()'), task.index('model.sendCoach("entry")'))

if __name__ == '__main__': unittest.main()
