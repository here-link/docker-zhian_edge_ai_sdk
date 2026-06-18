# pyright: reportMissingImports=false
"""Concurrency-safe wrapper for Zhian's BE3V120 doorlock_api module.

The vendor API already contains the ZF-BP3-X algorithm integration and better
error-code/download handling.  Keep that module as the source of truth, but
replace the unsafe request-level behavior that shares /data1 file names across
concurrent requests.
"""
from __future__ import annotations

import fcntl
import os
import re
import shutil
import threading
import time
import urllib.parse
import uuid
from typing import Any

from concurrent.futures import TimeoutError
from flask import jsonify, request

_ALLOWED_IMAGE_EXT_RE = re.compile(r"\.(jpg|jpeg|png|bmp|webp)$", re.IGNORECASE)
_UNSAFE_NAME_RE = re.compile(r"[<>?|:\"*/\\\s]+")


class _NullLock:
    def __enter__(self) -> "_NullLock":
        return self

    def __exit__(self, exc_type: Any, exc: Any, tb: Any) -> None:
        return None


class FileSlotSemaphore:
    """Small fcntl-based cross-process semaphore for gunicorn workers.

    The vendor code uses ``with PROCESS_LOCK`` around subprocess.run().  A
    normal threading.Lock only serializes threads inside one worker process;
    this lock shares N slot files across all workers so requests queue before
    launching the native feature extraction program.
    """

    def __init__(self, lock_dir: str, slots: int = 1, wait_seconds: float = 0.05) -> None:
        self.lock_dir = lock_dir
        self.slots = max(1, int(slots))
        self.wait_seconds = wait_seconds
        self._local = threading.local()

    def __enter__(self) -> "FileSlotSemaphore":
        os.makedirs(self.lock_dir, exist_ok=True)

        while True:
            for slot in range(self.slots):
                path = os.path.join(self.lock_dir, f"feature-process-{slot}.lock")
                fh = open(path, "a+")
                try:
                    fcntl.flock(fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    fh.close()
                    continue

                stack = getattr(self._local, "stack", [])
                stack.append(fh)
                self._local.stack = stack
                return self

            time.sleep(self.wait_seconds)

    def __exit__(self, exc_type: Any, exc: Any, tb: Any) -> None:
        stack = getattr(self._local, "stack", [])
        if not stack:
            return None

        fh = stack.pop()
        try:
            fcntl.flock(fh.fileno(), fcntl.LOCK_UN)
        finally:
            fh.close()
        return None


def _feature_process_concurrency() -> int:
    raw = os.getenv("FEATURE_PROCESS_CONCURRENCY", "1").strip().lower()
    if raw in {"0", "off", "false", "none", "unlimited"}:
        return 0
    try:
        return max(1, int(raw))
    except ValueError:
        return 1


def _request_prefix() -> str:
    return f"hlreq_{int(time.time() * 1000)}_{os.getpid()}_{threading.get_ident()}_{uuid.uuid4().hex[:12]}_"


def _safe_name(raw_name: str, default_name: str = "image.jpg") -> str:
    name = os.path.basename(raw_name) or default_name
    name = urllib.parse.unquote(name)
    name = _UNSAFE_NAME_RE.sub("_", name).strip("._") or default_name
    if not _ALLOWED_IMAGE_EXT_RE.search(name):
        name += ".jpg"
    return name


def _remote_image_name(image_url: str) -> str:
    parsed = urllib.parse.urlsplit(image_url)
    return _safe_name(os.path.basename(parsed.path) or os.path.basename(image_url))


def _copy_local_image_to_request_file(vendor: Any, image_url: str, prefix: str) -> str | None:
    input_dir = os.path.abspath(vendor.INPUT_DIR)
    input_prefix = f"{os.path.basename(vendor.INPUT_DIR)}/"
    rel_path = image_url.split("/", 1)[1] if image_url.startswith(input_prefix) else image_url
    source_path = os.path.abspath(os.path.join(input_dir, rel_path))

    if source_path != input_dir and not source_path.startswith(input_dir + os.sep):
        return None

    if not os.path.exists(source_path) or os.path.getsize(source_path) < 128:
        return None

    target_name = prefix + _safe_name(os.path.basename(source_path))
    target_path = os.path.join(vendor.INPUT_DIR, target_name)
    shutil.copyfile(source_path, target_path)
    os.chmod(target_path, 0o666)
    os.utime(target_path, None)
    return target_path


def _cleanup_request_files(vendor: Any, prefix: str) -> None:
    try:
        for file_name in os.listdir(vendor.INPUT_DIR):
            if not file_name.startswith(prefix):
                continue
            file_path = os.path.join(vendor.INPUT_DIR, file_name)
            if os.path.isfile(file_path):
                try:
                    os.remove(file_path)
                except FileNotFoundError:
                    pass
                except Exception as exc:  # pragma: no cover - best effort cleanup
                    print(f"[并发清理警告] 删除请求临时文件失败 {file_path}: {exc}")
    except FileNotFoundError:
        pass


def _make_safe_predict(vendor: Any):
    def predict():
        image_url = urllib.parse.unquote(request.args.get("image", "").strip())
        version = urllib.parse.unquote(request.args.get("version", "V2").strip()).upper()

        match = re.search(r"https?://[^\s]+", image_url)
        if match:
            image_url = match.group(0)

        if not image_url:
            return jsonify({
                "code": 1,
                "codemsg": "缺少image参数",
                "datamsg": [{"data": ""}],
            }), 400

        if version not in ["V1", "V2"]:
            return jsonify({
                "code": 4,
                "codemsg": "仅支持V1/V2版本",
                "datamsg": [{"data": ""}],
            }), 400

        prefix = _request_prefix()
        img_path = ""

        try:
            input_prefix = f"{os.path.basename(vendor.INPUT_DIR)}/"
            if image_url.startswith(input_prefix):
                img_path = _copy_local_image_to_request_file(vendor, image_url, prefix) or ""
                if not img_path:
                    return jsonify({
                        "code": 2,
                        "codemsg": "本地文件不存在或无效",
                        "datamsg": [{"data": ""}],
                    }), 404

            elif image_url.startswith(("http://", "https://")):
                img_name = prefix + _remote_image_name(image_url)
                img_path = os.path.join(vendor.INPUT_DIR, img_name)
                if not vendor.download_image(image_url, img_path):
                    return jsonify({
                        "code": 2,
                        "codemsg": "下载失败",
                        "datamsg": [{"data": ""}],
                    }), 400
            else:
                return jsonify({
                    "code": 1,
                    "codemsg": "image参数格式错误",
                    "datamsg": [{"data": ""}],
                }), 400

            if vendor.executor._work_queue.qsize() >= vendor.MAX_QUEUE:
                return jsonify({
                    "code": 6,
                    "codemsg": "请求过多，请稍后重试",
                    "datamsg": [{"data": ""}],
                }), 503

            future = vendor.executor.submit(vendor.process_feature, img_path, version)
            result = future.result(timeout=60)
            return jsonify(result), 200 if result.get("code") == 0 else 400

        except TimeoutError:
            return jsonify({
                "code": 5,
                "codemsg": "请求超时",
                "datamsg": [{"data": ""}],
            }), 504
        except Exception as exc:
            return jsonify({
                "code": 5,
                "codemsg": f"处理异常：{exc}",
                "datamsg": [{"data": ""}],
            }), 500
        finally:
            _cleanup_request_files(vendor, prefix)

    predict.__name__ = "predict"
    return predict


def configure_vendor_api(vendor: Any) -> None:
    """Patch BE3V120 vendor API for safe concurrent HTTP requests."""

    # The vendor function deletes every image/bin in /data1 except the current
    # basename.  That is unsafe for concurrent requests and also deletes bundled
    # sample images.  Our request handler uses unique temp file names and cleans
    # only its own files; age-based cleanup remains in auto-del-3-days-ago-image.sh.
    def _skip_global_cleanup(current_img_name: str) -> None:
        if os.getenv("LOG_SKIPPED_VENDOR_GLOBAL_CLEANUP", "0") == "1":
            print(f"[并发安全] 跳过 vendor 全局清理 current={current_img_name}")

    vendor.clean_all_old_files = _skip_global_cleanup

    concurrency = _feature_process_concurrency()
    if concurrency <= 0:
        vendor.PROCESS_LOCK = _NullLock()
        lock_desc = "disabled/unlimited"
    else:
        lock_dir = os.getenv("FEATURE_PROCESS_LOCK_DIR", "/workspace/tmp/feature-locks")
        vendor.PROCESS_LOCK = FileSlotSemaphore(lock_dir=lock_dir, slots=concurrency)
        lock_desc = f"cross-process slots={concurrency} dir={lock_dir}"

    vendor.app.view_functions["predict"] = _make_safe_predict(vendor)
    print(f"[并发安全] predict wrapper enabled; feature process lock: {lock_desc}")
