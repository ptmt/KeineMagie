"""Regression for SwiftUI task restarts causing paid entry during GET recovery."""
from pathlib import Path
import unittest

class CoachReadinessTests(unittest.TestCase):
    def test_readiness_change_does_not_restart_daily_entry_task(self):
        source = (Path(__file__).resolve().parents[1]/'App/CoachView.swift').read_text()
        task = source.split('.task(id: "\\(model.session.generation)', 1)[1].split('.refreshable', 1)[0]
        self.assertNotIn('\\(model.session.canWrite)', task)
        self.assertIn('let enteredReady = model.session.canWrite', task)
        self.assertLess(task.index('let enteredReady'), task.index('await model.loadCoach()'))
        self.assertIn('if enteredReady && !Task.isCancelled', task)
        self.assertIn('model.sendCoach("entry")', task)

if __name__ == '__main__': unittest.main()
