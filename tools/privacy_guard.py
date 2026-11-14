"""Review a release tree or all staged/history blobs; never print matched secrets."""
import argparse
import io
import json
from pathlib import Path
import re
import subprocess
import sys
import zipfile
import xml.etree.ElementTree as ET

CHECKS = [
    re.compile(r"[A-Za-z]:[\\/]Users[\\/](?!Public(?:[\\/]|$)|Default(?:[\\/]|$))[^\\/\s]+", re.I),
    re.compile("(?:gh" + "p_|github_" + "pat_)[A-Za-z0-9_]{20,}"),
    re.compile("-----BEGIN " + "(?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    re.compile(r"\bBearer\s+[A-Za-z0-9._-]{24,}"),
    re.compile(r"\bwxid_[a-zA-Z0-9_]{5,}"),
    re.compile(r"\b[A-Za-z0-9._%+-]+@(?:163|126|qq|gmail|outlook)\.com\b", re.I),
]


def git(*args):
    return subprocess.check_output(["git", *args])


def scan(path, data):
    errors = []
    lower = path.lower()
    if any(x in Path(lower).parts for x in ("runs", "data", "outputs", "local-app", "node_modules", ".python-packages")):
        errors.append("unapproved data directory")
    if Path(lower).name in {"settings.json", "history.json", "last-run.json", "last-success.json", "run.lock"}:
        errors.append("local state file")
    if lower.endswith(".xlsx"):
        try:
            with zipfile.ZipFile(io.BytesIO(data)) as archive:
                for name in archive.namelist():
                    if "externallinks/" in name.lower():
                        errors.append("external workbook link")
                    value = archive.read(name)
                    if name == "docProps/core.xml":
                        for element in ET.fromstring(value).iter():
                            if element.tag.rsplit("}", 1)[-1] in {"creator", "lastModifiedBy"} and element.text not in {None, "BondSentimentAutomation"}:
                                errors.append("personal workbook metadata")
                    errors.extend(scan(name, value))
        except (zipfile.BadZipFile, ET.ParseError):
            errors.append("invalid workbook archive")
    elif not lower.endswith((".exe", ".ico", ".otf")) and not lower.startswith("licenses/"):
        value = data.decode("utf-8", errors="replace")
        if any(pattern.search(value) for pattern in CHECKS):
            errors.append("sensitive content pattern")
    return sorted(set(errors))


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--staged", action="store_true")
    parser.add_argument("--history", action="store_true")
    options = parser.parse_args()
    root = options.root.resolve()
    policy = json.loads((root / "release-files.json").read_text(encoding="utf-8")) if (root / "release-files.json").exists() else None
    approved = set(policy["runtime"] + policy["source"] + policy["templates"]) if policy else None
    records = []
    if options.staged or options.history:
        commits = git("rev-list", "--all").decode().splitlines() if options.history else [None]
        for commit in commits:
            names = git("ls-tree", "-rz", "--name-only", commit) if commit else git("diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z")
            for name in names.decode().split("\0"):
                if name:
                    records.append((name, git("show", (commit or "") + ":" + name)))
    else:
        for file in root.rglob("*"):
            if file.is_file() and ".git" not in file.relative_to(root).parts:
                records.append((file.relative_to(root).as_posix(), file.read_bytes()))
    failed = []
    for name, data in records:
        errors = scan(name, data)
        if approved is not None and name not in approved:
            errors.append("outside source allowlist")
        if errors:
            failed.append((name, errors))
    for name, errors in failed:
        print(name + ": " + ", ".join(errors))
    print(json.dumps({"checked": len(records), "failed": len(failed)}, ensure_ascii=False))
    return bool(failed)


if __name__ == "__main__":
    sys.exit(main())
