# จำลอง HSM / signing service: key อยู่ในโปรเซสนี้เท่านั้น ใครอยากได้ลายเซ็นต้องมาขอผ่าน HTTP
# มี policy: ยอมเซ็น 7702 authorization แต่ "ปฏิเสธ" การเซ็นโอนเงินตรงๆ (จุดบอดที่โจรใช้)
import os, subprocess, urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer
KEY = os.environ["SIGNER_KEY"]            # <-- ความลับ อยู่แค่ในโปรเซสนี้
RPC = os.environ.get("RPC", "http://127.0.0.1:8545")
def cast(*a): return subprocess.check_output(["cast", *a], text=True).strip()
class H(BaseHTTPRequestHandler):
    def log_message(self,*a): pass
    def _s(self,c,b): self.send_response(c); self.send_header("content-type","text/plain"); self.end_headers(); self.wfile.write(b.encode())
    def do_GET(self):
        u=urllib.parse.urlparse(self.path); q=urllib.parse.parse_qs(u.query)
        if u.path=="/sign-auth":
            t=q["target"][0]; n=q["nonce"][0]
            sig=cast("wallet","sign-auth",t,"--private-key",KEY,"--rpc-url",RPC,"--nonce",n)
            print(f"[signer] 7702 auth -> {t} nonce {n} : ALLOW (ไม่เข้าข่าย 'โอนเงิน' policy เลยปล่อยผ่าน)", flush=True)
            self._s(200,sig)
        elif u.path=="/sign-transfer":
            to=q["to"][0]; v=q.get("value",["0"])[0]
            print(f"[signer] transfer {v} wei -> {to} : DENY (เกิน limit / ปลายทางไม่อยู่ whitelist)", flush=True)
            self._s(403,"DENIED by signing policy")
        else: self._s(404,"no")
print("[signer] up on 127.0.0.1:9099 (key ซ่อนอยู่ในโปรเซสนี้)", flush=True)
HTTPServer(("127.0.0.1",9099),H).serve_forever()
