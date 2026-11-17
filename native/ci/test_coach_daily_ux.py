"""Focused macOS AppModel harness: synthetic transport, no UI host or provider."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    with tempfile.TemporaryDirectory(prefix='km-coach-daily-') as temp:
        p = Path(temp)
        source = p/'Sources/Lifecycle'
        tests = p/'Tests/LifecycleTests'
        source.mkdir(parents=True)
        tests.mkdir(parents=True)
        (p/'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name:"Lifecycle",platforms:[.macOS(.v14)],dependencies:[.package(path:"%s")],targets:[.target(name:"Lifecycle",dependencies:[.product(name:"KeineMagieCore",package:"Core")]),.testTarget(name:"LifecycleTests",dependencies:["Lifecycle"])])
''' % (ROOT/'Core'))
        app = (ROOT/'App/AppModel.swift').read_text().replace('import SwiftUI','import Foundation\nimport Observation')
        (source/'AppModel.swift').write_text(app)
        (source/'PodcastStore.swift').write_text((ROOT/'App/PodcastStore.swift').read_text())
        (source/'Stubs.swift').write_text('''import Foundation
import KeineMagieCore
struct ChatGPTBrowser: Identifiable { let id = UUID(); let url: URL }
enum TokenStore { static func readIdentity() throws -> SavedNativeIdentity? { fatalError("Keychain forbidden") }; static func saveIdentity(_ identity: SavedNativeIdentity?) throws { fatalError("Keychain forbidden") }; static func read() throws -> String { fatalError("Keychain forbidden") }; static func save(_ s:String) throws { fatalError("Keychain forbidden") } }
enum ProductIdentity { static let defaultServerURL = "https://synthetic.invalid" }
enum AppL10n { static func text(_ key:String) -> String { key } }
''')
        for name in ['coach_harness.swift','coach_daily_harness.swift']:
            (tests/name).write_text((ROOT/'ci'/name).read_text())
        subprocess.run(['swift','test','--disable-sandbox','--package-path',temp,'--jobs','2','-Xswiftc','-module-cache-path','-Xswiftc',str(p/'module-cache')],check=True,env={**os.environ,'CLANG_MODULE_CACHE_PATH':str(p/'module-cache')})

if __name__ == '__main__': main()
