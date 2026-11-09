"""Publish a complete HTML snapshot using only the Python standard library.

Existing server-only pages are retained. Each version is immutable after switching.
Run as root (or sudo) on the server; no build/install commands are executed.
"""
import os
import pathlib
import shutil
import stat
import sys
import uuid
import zipfile


def checked_entries(archive):
    entries = archive.infolist()
    for entry in entries:
        name = entry.filename
        path = pathlib.PurePosixPath(name)
        if (not name or "\\" in name or name.startswith("/") or
                any(part in (".", "..") for part in name.split("/") if part) or
                stat.S_ISLNK(entry.external_attr >> 16)):
            raise ValueError("Unsafe HTML archive entry")
        if not path.parts:
            raise ValueError("Empty HTML archive path")
    return entries


def copy_tree(source, destination):
    for directory, folders, files in os.walk(source, followlinks=False):
        for name in folders + files:
            if (pathlib.Path(directory) / name).is_symlink():
                raise ValueError("HTML source contains a symbolic link")
        relative = pathlib.Path(directory).relative_to(source)
        target = destination / relative
        target.mkdir(parents=True, exist_ok=True)
        for name in files:
            shutil.copyfile(pathlib.Path(directory) / name, target / name)


def publish(source, data_directory, user, group):
    import pwd
    import grp
    data = pathlib.Path(data_directory).resolve()
    if not data.is_absolute() or data == pathlib.Path("/"):
        raise ValueError("Invalid data directory")
    uid, gid = pwd.getpwnam(user).pw_uid, grp.getgrnam(group).gr_gid
    versions = data / "html-releases"
    versions.mkdir(parents=True, exist_ok=True)
    if versions.is_symlink():
        raise ValueError("HTML versions directory must not be a symlink")
    current = data / "html"
    if current.is_symlink() and versions.resolve() not in current.resolve().parents:
        raise ValueError("HTML link points outside the managed versions directory")
    snapshot = versions / uuid.uuid4().hex
    snapshot.mkdir()
    link = data / (".html-next-" + uuid.uuid4().hex)
    try:
        if current.exists():
            copy_tree(current.resolve(), snapshot)
        source_path = pathlib.Path(source)
        if source_path.is_dir():
            copy_tree(source_path, snapshot)
        else:
            with zipfile.ZipFile(source_path) as archive:
                entries = checked_entries(archive)
                for entry in entries:
                    target = snapshot.joinpath(*pathlib.PurePosixPath(entry.filename).parts)
                    if entry.is_dir():
                        target.mkdir(parents=True, exist_ok=True)
                    else:
                        target.parent.mkdir(parents=True, exist_ok=True)
                        with archive.open(entry) as incoming, target.open("wb") as outgoing:
                            shutil.copyfileobj(incoming, outgoing, 256 * 1024)
        for directory, folders, files in os.walk(snapshot):
            os.chown(directory, uid, gid)
            os.chmod(directory, 0o755)
            for name in files:
                file = pathlib.Path(directory) / name
                os.chown(file, uid, gid)
                os.chmod(file, 0o644)
        os.symlink(snapshot, link)
        if current.exists() and not current.is_symlink():
            legacy = versions / ("legacy-" + uuid.uuid4().hex)
            current.rename(legacy)
            try:
                os.replace(link, current)
            except BaseException:
                legacy.rename(current)
                raise
        else:
            os.replace(link, current)
        print("HTML pages updated; no service restart was needed.")
    except BaseException:
        if link.is_symlink():
            link.unlink()
        shutil.rmtree(snapshot)
        raise


if __name__ == "__main__":
    if len(sys.argv) != 5:
        raise SystemExit("Usage: publish-html-remote.py SOURCE DATA_DIR APP_USER APP_GROUP")
    publish(*sys.argv[1:])
