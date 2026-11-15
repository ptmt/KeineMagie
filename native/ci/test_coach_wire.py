"""Decode actual authenticated Go Coach handler JSON using production Swift DTOs."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='coach-wire-', dir=os.environ.get('TMPDIR')) as tmp:
    folder = Path(tmp)
    subprocess.run(['go', 'test', '-run', '^TestCoachWireExport$', '-count=1', '.'], cwd=ROOT/'server', env={**os.environ, 'KM_COACH_WIRE_DIR': tmp}, check=True)
    (folder/'main.swift').write_text('''import Foundation
@main struct WireCheck {
 static func main() throws {
  for path in CommandLine.arguments.dropFirst() {
   let data = try Data(contentsOf: URL(fileURLWithPath: path))
   let snapshot = try JSONDecoder().decode(CoachSnapshot.self, from: data)
   print("Decoded Go handler: \\(URL(fileURLWithPath:path).lastPathComponent), turns=\\(snapshot.turns.count), observations=\\(snapshot.observations.count)")
  }
 }
}
''')
    subprocess.run(['swiftc', '-parse-as-library', str(ROOT/'native/Core/Sources/KeineMagieCore/Coach.swift'), str(folder/'main.swift'), '-o', str(folder/'decode')], check=True)
    paths = sorted(folder.glob('*.json'))
    assert len(paths) == 8
    subprocess.run([str(folder/'decode'), *map(str, paths)], check=True)
