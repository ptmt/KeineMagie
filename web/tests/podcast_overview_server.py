"""Serve real assets locally, including the production reader-path shell fallback.
No real account or API is configured; use podcast_overview_browser.py injection.
"""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlsplit
ROOT = Path(__file__).resolve().parents[1]
class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)
    def do_GET(self):
        if urlsplit(self.path).path.startswith('/podcasts/episodes/'):
            self.path = '/index.html'
        super().do_GET()
if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', 8773), Handler).serve_forever()
