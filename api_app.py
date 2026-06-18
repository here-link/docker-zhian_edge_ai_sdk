# pyright: reportMissingImports=false
"""Small compatibility wrapper around Zhian's BE3V120 API module.

The vendor image contains /workspace/doorlock_api.py and the new ZF-BP3-X
algorithm support.  Keep that module as the source of truth; this wrapper only
adds the legacy root health response used by the previous optimized image.
"""
from doorlock_api import app


@app.route("/")
def hello():
    return "Nice To Meet You!"
