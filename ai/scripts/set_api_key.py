"""
DeepSeek API Key 本地加密存储工具
=================================
把密钥用 Windows DPAPI 加密后写入用户目录，项目里不残留任何明文。

用法：
    python ai/scripts/set_api_key.py            # 交互输入并保存
    python ai/scripts/set_api_key.py --check    # 查看是否已保存（脱敏显示）
    python ai/scripts/set_api_key.py --delete   # 删除已保存的密钥
"""
import argparse
import getpass
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from utils.secrets import (  # noqa: E402
    delete_secret,
    is_supported,
    load_secret,
    save_secret,
    secret_path,
)

NAME = "deepseek"


def mask(value: str) -> str:
    if len(value) <= 12:
        return "*" * len(value)
    return f"{value[:6]}...{value[-4:]}"


def main() -> int:
    parser = argparse.ArgumentParser(description="store DeepSeek API key with DPAPI")
    parser.add_argument("--check", action="store_true", help="show masked key status")
    parser.add_argument("--delete", action="store_true", help="remove stored key")
    args = parser.parse_args()

    if not is_supported():
        print("[FAIL] DPAPI store is Windows-only. Use the DEEPSEEK_API_KEY env var instead.")
        return 1

    if args.delete:
        removed = delete_secret(NAME)
        print("[ OK ] removed" if removed else "[INFO] nothing to remove")
        return 0

    if args.check:
        value = load_secret(NAME)
        if value:
            print(f"[ OK ] stored: {mask(value)}  ({secret_path(NAME)})")
            return 0
        print("[INFO] no stored key")
        return 1

    key = getpass.getpass("DeepSeek API key (input hidden): ").strip()
    if not key:
        print("[WARN] empty input, nothing saved")
        return 1
    if not key.startswith("sk-"):
        print("[WARN] key does not start with 'sk-', saving anyway")

    if not save_secret(NAME, key):
        print("[FAIL] failed to encrypt/save key")
        return 1

    print(f"[ OK ] saved (encrypted with DPAPI): {secret_path(NAME)}")
    print("       readable only by your Windows account on this machine")
    return 0


if __name__ == "__main__":
    sys.exit(main())
