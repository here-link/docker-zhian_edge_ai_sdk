# pyright: reportMissingImports=false
"""Compatibility wrapper around Zhian's BE3V120 API module.

The vendor image contains /workspace/doorlock_api.py and the new ZF-BP3-X
algorithm support.  Keep that module as the source of truth, then patch only
container-level behavior: legacy root health response and safe concurrent
request handling.
"""
import doorlock_api as _doorlock_api
from zhian_concurrency import configure_vendor_api


configure_vendor_api(_doorlock_api)
app = _doorlock_api.app


@app.route("/")
def hello():
    return "Nice To Meet You!"
