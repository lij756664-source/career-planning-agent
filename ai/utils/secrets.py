"""
本地密钥存储（Windows DPAPI）
=============================
用 Windows 自带的 DPAPI 加密敏感字符串，密文以二进制形式存放于用户目录：

    %LOCALAPPDATA%\\GradQuest\\<name>.key

特点：
- 只有当前 Windows 账号（且同一台机器）能解密，别人拿到文件也没用；
- 密文不在项目目录内，拷贝/上传项目不会带出去；
- 只用标准库 ctypes，不引入额外依赖。

非 Windows 环境下 save/load 直接返回失败，由调用方走环境变量或提示输入。
"""
import ctypes
import os
import sys
from ctypes import wintypes
from pathlib import Path
from typing import Optional

APP_DIR_NAME = "GradQuest"
CRYPTPROTECT_UI_FORBIDDEN = 0x01
DESCRIPTION = "GradQuest local secret"


class _DataBlob(ctypes.Structure):
    _fields_ = [
        ("cbData", wintypes.DWORD),
        ("pbData", ctypes.POINTER(ctypes.c_char)),
    ]


def _make_blob(data: bytes):
    """把 bytes 包成 DATA_BLOB，同时返回底层 buffer 以保证生命周期。"""
    buffer = ctypes.create_string_buffer(data, len(data))
    blob = _DataBlob(len(data), ctypes.cast(buffer, ctypes.POINTER(ctypes.c_char)))
    return blob, buffer


def _crypt32():
    lib = ctypes.WinDLL("crypt32", use_last_error=True)
    lib.CryptProtectData.argtypes = [
        ctypes.POINTER(_DataBlob), wintypes.LPCWSTR, ctypes.POINTER(_DataBlob),
        ctypes.c_void_p, ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(_DataBlob),
    ]
    lib.CryptProtectData.restype = wintypes.BOOL
    lib.CryptUnprotectData.argtypes = [
        ctypes.POINTER(_DataBlob), ctypes.POINTER(wintypes.LPWSTR), ctypes.POINTER(_DataBlob),
        ctypes.c_void_p, ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(_DataBlob),
    ]
    lib.CryptUnprotectData.restype = wintypes.BOOL
    return lib


def _kernel32():
    lib = ctypes.WinDLL("kernel32", use_last_error=True)
    lib.LocalFree.argtypes = [wintypes.HLOCAL]
    lib.LocalFree.restype = wintypes.HLOCAL
    return lib


def is_supported() -> bool:
    return sys.platform == "win32"


def secret_path(name: str) -> Path:
    base = os.environ.get("LOCALAPPDATA") or str(Path.home())
    return Path(base) / APP_DIR_NAME / f"{name}.key"


def protect(text: str) -> Optional[bytes]:
    """加密字符串，返回密文；失败返回 None。"""
    if not is_supported() or not text:
        return None
    blob_in, _keep_in = _make_blob(text.encode("utf-8"))
    blob_out = _DataBlob()
    ok = _crypt32().CryptProtectData(
        ctypes.byref(blob_in), DESCRIPTION, None, None, None,
        CRYPTPROTECT_UI_FORBIDDEN, ctypes.byref(blob_out),
    )
    if not ok:
        return None
    try:
        return ctypes.string_at(blob_out.pbData, blob_out.cbData)
    finally:
        _kernel32().LocalFree(ctypes.cast(blob_out.pbData, wintypes.HLOCAL))


def unprotect(blob: bytes) -> Optional[str]:
    """解密密文，失败（换了机器或账号）返回 None。"""
    if not is_supported() or not blob:
        return None
    blob_in, _keep_in = _make_blob(blob)
    blob_out = _DataBlob()
    ok = _crypt32().CryptUnprotectData(
        ctypes.byref(blob_in), None, None, None, None,
        CRYPTPROTECT_UI_FORBIDDEN, ctypes.byref(blob_out),
    )
    if not ok:
        return None
    try:
        return ctypes.string_at(blob_out.pbData, blob_out.cbData).decode("utf-8", "ignore")
    finally:
        _kernel32().LocalFree(ctypes.cast(blob_out.pbData, wintypes.HLOCAL))


def save_secret(name: str, value: str) -> bool:
    """加密并写入用户目录，返回是否成功。"""
    blob = protect(value)
    if not blob:
        return False
    path = secret_path(name)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_bytes(blob)
    os.replace(tmp, path)
    return True


def load_secret(name: str) -> str:
    """读取并解密，缺失或无法解密时返回空串。"""
    path = secret_path(name)
    if not path.is_file():
        return ""
    try:
        return unprotect(path.read_bytes()) or ""
    except Exception:
        return ""


def delete_secret(name: str) -> bool:
    path = secret_path(name)
    if path.is_file():
        path.unlink()
        return True
    return False
