"""Source/palette contracts, complementary to actual native UI tests."""
from pathlib import Path
import re
import unittest
from test_coach_contrast import contrast

SOURCE = Path(__file__).resolve().parents[1] / 'App/CoachView.swift'

class BoldCoachTests(unittest.TestCase):
    def test_composer_uses_native_glass_with_opaque_accessibility_fallback(self):
        source = SOURCE.read_text()
        self.assertIn('GlassEffectContainer(spacing: 8)', source)
        self.assertIn('.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26))', source)
        self.assertIn('@Environment(\\.accessibilityReduceTransparency)', source)
        self.assertIn('if #available(iOS 26.0, *), !reduceTransparency', source)
        self.assertNotIn('.padding(.vertical, 8).background(.bar)', source)

    def test_verdict_keeps_text_with_noncolor_symbol(self):
        source = SOURCE.read_text()
        self.assertIn('turn.presentationStatus == "success" ? "checkmark.circle.fill" : "xmark.circle.fill"', source)
        self.assertIn('Text(LocalizedStringKey(attempt.feedbackKey))', source)

    def test_semantic_surfaces_are_saturated_and_support_white_text(self):
        source = SOURCE.read_text()
        for name in ('success', 'user'):
            line = next(line for line in source.splitlines() if f'static let {name} =' in line)
            colors = re.findall(r'UIColor\(red: ([\d.]+), green: ([\d.]+), blue: ([\d.]+), alpha: 1\)', line)
            self.assertEqual(len(colors), 2)
            for values in colors:
                rgb = tuple(map(float, values))
                self.assertGreaterEqual(max(rgb) - min(rgb), .20, name)
                self.assertGreaterEqual(contrast((1, 1, 1), rgb), 4.5, name)
        self.assertEqual(source.count('.foregroundStyle(CoachPalette.onColor)'), 2)
        self.assertIn('status == "success" ? CoachPalette.onColor : Color.primary', source)

    def test_incorrect_is_soft_adaptive_fill_with_border_and_primary_text(self):
        source = SOURCE.read_text()
        line = next(line for line in source.splitlines() if 'static let incorrect =' in line)
        alphas = [float(v) for v in re.findall(r'alpha: ([\d.]+)', line)]
        self.assertEqual(len(alphas), 2)
        self.assertTrue(all(0 < alpha <= .15 for alpha in alphas), alphas)
        self.assertIn('status == "success" ? CoachPalette.onColor : Color.primary', source)
        self.assertIn('if status == "incorrect" {', source)
        self.assertIn('.strokeBorder(CoachPalette.incorrectBorder, lineWidth: 1)', source)

if __name__ == '__main__':
    unittest.main()
