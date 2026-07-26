"""Fill jaclang 0.16.7's unimplemented send_static_file at runtime.

The dev server routes asset requests (assets/, dist/) to Jac.send_static_file,
but this build's implementation just raises NotImplementedError — only the CSS
path works. Patching here lets one server serve both walkers and the static
frontend, locally and on any host that runs main.jac. Guarded so a runtime that
already implements it (or a different layout) is left untouched on failure.
"""

import mimetypes
from pathlib import Path


def _send_static_file(handler, file_path, content_type=None):
    p = Path(file_path)
    data = p.read_bytes()
    ctype = content_type or mimetypes.guess_type(p.name)[0] or "application/octet-stream"
    if p.suffix in (".html", ".htm"):
        ctype = "text/html; charset=utf-8"
    handler.send_response(200)
    handler.send_header("Content-Type", ctype)
    handler.send_header("Content-Length", str(len(data)))
    handler.send_header("Access-Control-Allow-Origin", "*")
    handler.end_headers()
    handler.wfile.write(data)


def apply():
    patched = 0
    try:
        import jaclang

        targets = [getattr(jaclang, "JacRuntime", None)]
        try:
            from jaclang.jac0core import runtime as _rt

            targets += [
                getattr(_rt, n, None)
                for n in ("JacRuntime", "JacRuntimeImpl", "JacResponseBuilder")
            ]
        except Exception:
            pass
        for t in targets:
            if t is not None and hasattr(t, "send_static_file"):
                t.send_static_file = staticmethod(_send_static_file)
                patched += 1
    except Exception:
        pass
    return patched


PATCHED_TARGETS = apply()
