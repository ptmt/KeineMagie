"""Local-only synthetic artwork fixture; never production authentication.
Run from repo: python3 web/tests/podcast_fixture_server.py
All other URLs serve actual web assets. Browser API is separately synthetic.
"""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
import struct, zlib
ROOT=Path(__file__).resolve().parents[1]
def png():
    def chunk(kind,data):return struct.pack('!I',len(data))+kind+data+struct.pack('!I',zlib.crc32(kind+data))
    pixels=b''.join(b'\0'+b''.join(bytes((40,92,72) if (x//16+y//16)%2 else (164,206,179)) for x in range(128)) for y in range(128))
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('!2I5B',128,128,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(pixels))+chunk(b'IEND',b'')
class Handler(SimpleHTTPRequestHandler):
    def __init__(self,*args,**kwargs):super().__init__(*args,directory=str(ROOT),**kwargs)
    def do_GET(self):
        if self.path=='/v1/podcasts/subscriptions/Feed_A/artwork':
            body=png();self.send_response(200);self.send_header('Content-Type','image/png');self.send_header('Cache-Control','no-store');self.end_headers();self.wfile.write(body)
        else:super().do_GET()
if __name__=='__main__':ThreadingHTTPServer(('127.0.0.1',8769),Handler).serve_forever()
