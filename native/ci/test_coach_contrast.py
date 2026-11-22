"""Conservative WCAG checks for the explicit Coach text palette (not vision)."""
from pathlib import Path
import unittest

def luminance(rgb):
    return sum(weight * (v/12.92 if v <= .04045 else ((v+.055)/1.055)**2.4) for weight,v in zip((.2126,.7152,.0722),rgb))
def contrast(a,b):
    x,y=sorted((luminance(a),luminance(b)))
    return (y+.05)/(x+.05)
class CoachContrastTests(unittest.TestCase):
    def test_semantic_bubbles_keep_text_and_distinct_user_tint(self):
        source=(Path(__file__).resolve().parents[1]/'App/CoachView.swift').read_text()
        self.assertIn('CoachAssistantBubble(status: turn.presentationStatus)', source)
        self.assertIn('case "incorrect": CoachPalette.incorrect', source)
        self.assertIn('case "success": CoachPalette.success', source)
        self.assertIn('default: CoachPalette.surface', source)
        self.assertEqual(source.count('.background(CoachPalette.user,'), 2)
        self.assertIn('Text(LocalizedStringKey(attempt.feedbackKey))', source)
        self.assertNotIn('.foregroundStyle(.white)', source)

    def test_native_explicit_secondary_and_placeholder_palette(self):
        source=(Path(__file__).resolve().parents[1]/'App/CoachView.swift').read_text()
        for token in ['UIColor(white: 0.78, alpha: 1)','UIColor(white: 0.32, alpha: 1)','UIColor(white: 0.15, alpha: 1)','UIColor(white: 0.94, alpha: 1)','prompt: Text("coach.message").foregroundStyle(CoachPalette.secondary)','prompt: Text("coach.answer").foregroundStyle(CoachPalette.secondary)']:
            self.assertIn(token,source)
        # Secondary text appears only on neutral surfaces; semantic bubbles use
        # opaque white, checked against parsed production RGB in test_coach_bold_glass.
        for theme,fg,surfaces in [('dark',(.78,)*3,[(.15,)*3,(0,)*3]),('light',(.32,)*3,[(.94,)*3,(1,)*3])]:
            ratios=[contrast(fg,bg) for bg in surfaces]
            print('NATIVE_CONTRAST',theme,ratios)
            self.assertGreaterEqual(min(ratios),4.5)
if __name__=='__main__':unittest.main()
