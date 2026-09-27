"""Print the version of a named package pinned in a uv.lock file, or nothing
if the file is missing/unparsable/has no such package."""
import sys
import tomllib


def main(path: str, package: str) -> None:
    try:
        with open(path, "rb") as f:
            data = tomllib.load(f)
    except Exception:
        return
    for pkg in data.get("package", []):
        if pkg.get("name") == package:
            print(pkg.get("version", ""))
            return


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
