from http.server import HTTPServer, BaseHTTPRequestHandler

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        rows = "".join(
            f"<tr><td>{k}</td><td style='word-break:break-all'>{v}</td></tr>"
            for k, v in sorted(self.headers.items())
        )
        body = f"""<!DOCTYPE html>
<html>
<head>
  <title>Request Headers</title>
  <style>
    body {{ font-family: monospace; padding: 2rem; background: #f5f5f5; }}
    h2 {{ color: #333; }}
    table {{ border-collapse: collapse; width: 100%; background: white;
             box-shadow: 0 1px 3px rgba(0,0,0,0.1); }}
    th, td {{ text-align: left; padding: 0.6rem 1rem; border-bottom: 1px solid #eee; }}
    th {{ background: #e8e8e8; font-weight: bold; }}
    tr:hover td {{ background: #fafafa; }}
    td:first-child {{ color: #555; white-space: nowrap; padding-right: 2rem; }}
    td:last-child {{ color: #222; }}
  </style>
</head>
<body>
  <h2>Request Headers</h2>
  <table>
    <tr><th>Header</th><th>Value</th></tr>
    {rows}
  </table>
</body>
</html>""".encode()

        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass  # silence default access log noise

HTTPServer(("0.0.0.0", 80), Handler).serve_forever()
