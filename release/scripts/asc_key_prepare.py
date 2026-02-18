import base64
import os
import sys


def main() -> int:
    raw = os.environ.get("ASC_KEY_CONTENT", "")
    raw = raw.strip().replace("\r", "").replace("\\n", "\n")

    if not raw:
        print("ASC_KEY_CONTENT is empty", file=sys.stderr)
        return 2

    if "BEGIN PRIVATE KEY" in raw:
        pem = raw
    else:
        try:
            pem = base64.b64decode(raw).decode("utf-8")
        except Exception as exc:
            print(f"Failed to decode ASC_KEY_CONTENT as base64: {exc}", file=sys.stderr)
            return 3

    key_path = os.environ.get("ASC_KEY_PATH_CI")
    if not key_path:
        print("ASC_KEY_PATH_CI is not set", file=sys.stderr)
        return 4

    with open(key_path, "w", encoding="utf-8") as f:
        f.write(pem)

    os.chmod(key_path, 0o600)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
