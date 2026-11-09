"""Regenerate checked-in native localization resources from localization_data."""
import json
from pathlib import Path
from localization_data import APP, CORE

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ('de', 'en', 'ru', 'es', 'fr')

def main():
    strings = {}
    for row in APP:
        key = row[0]
        values = row[1:] if len(row) == 6 else row
        strings[key] = {'extractionState': 'manual', 'localizations': {
            language: {'stringUnit': {'state': 'translated', 'value': value}}
            for language, value in zip(LANGUAGES, values)}}
    (ROOT / 'App/Localizable.xcstrings').write_text(json.dumps({
        'sourceLanguage': 'de', 'strings': strings, 'version': '1.0'
    }, ensure_ascii=False, indent=2) + '\n')
    for index, language in enumerate(LANGUAGES, 1):
        folder = ROOT / 'Core/Sources/KeineMagieCore/Resources' / (language + '.lproj')
        folder.mkdir(parents=True, exist_ok=True)
        (folder / 'Localizable.strings').write_text(''.join(
            f'{json.dumps(row[0])} = {json.dumps(row[index], ensure_ascii=False)};\n' for row in CORE))
        app_folder = ROOT / 'App' / (language + '.lproj')
        app_folder.mkdir(parents=True, exist_ok=True)
        descriptions = {
            'de': 'Verbindet den Debug-Simulator mit deinem lokalen Keine-Magie-Server.',
            'en': 'Connects the Debug simulator to your local Keine Magie server.',
            'ru': 'Подключает симулятор Debug к вашему локальному серверу Keine Magie.',
            'es': 'Conecta el simulador Debug con tu servidor local de Keine Magie.',
            'fr': 'Connecte le simulateur Debug à votre serveur local Keine Magie.'}
        (app_folder / 'InfoPlist.strings').write_text(
            '"NSLocalNetworkUsageDescription" = ' + json.dumps(descriptions[language], ensure_ascii=False) + ';\n')

if __name__ == '__main__':
    main()
