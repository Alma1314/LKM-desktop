#!/usr/bin/env python3
"""Check the business HAP's CRC, native ABI, dependencies and FFI/N-API exports."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import tempfile
from zipfile import ZipFile


def verify(hap: Path, require_aot: bool = False) -> dict:
    ndk = Path(os.environ["OHOS_NDK_HOME"])
    system = ndk / "sysroot/usr/lib/aarch64-linux-ohos"
    required = {
        "libflutter.so", "libwebf.so", "libquickjs.so", "libsqlite3.so",
        "libopenmls_frb.so", "libsuper_native_extensions.so",
        "libinappwebview.so", "libc++_shared.so",
    }
    if require_aot:
        required.add("libapp.so")
    libraries = {}
    with ZipFile(hap) as archive, tempfile.TemporaryDirectory() as directory:
        corrupt = archive.testzip()
        if corrupt:
            raise ValueError(f"HAP CRC failed: {corrupt}")
        entries = [item for item in archive.infolist() if item.filename.endswith(".so")]
        names = {Path(item.filename).name for item in entries}
        if missing := required - names:
            raise ValueError(f"Missing runtime libraries: {sorted(missing)}")
        for item in entries:
            data = archive.read(item)
            if (data[:6] != b"\x7fELF\x02\x01" or
                    struct.unpack_from("<H", data, 18)[0] != 183 or
                    not item.filename.startswith("libs/arm64-v8a/")):
                raise ValueError(f"Expected OHOS ARM64 ELF: {item.filename}")
            library = Path(directory) / Path(item.filename).name
            library.write_bytes(data)
            dynamic = subprocess.check_output(["readelf", "-d", library], text=True)
            needed = re.findall(r"\(NEEDED\).*?\[([^]]+)\]", dynamic)
            for dependency in needed:
                if dependency in {"libc.so.6", "libstdc++.so.6", "libgcc_s.so.1"}:
                    raise ValueError(f"GNU/Linux dependency in {library.name}: {dependency}")
                if dependency not in names and not (system / dependency).is_file():
                    raise ValueError(f"Unbundled dependency in {library.name}: {dependency}")
            if library.name == "libsuper_native_extensions.so":
                symbols = subprocess.check_output(
                    ["readelf", "--dyn-syms", "--wide", library], text=True,
                )
                defined = {line.split()[-1] for line in symbols.splitlines()
                           if len(line.split()) >= 8 and line.split()[6] != "UND"}
                for symbol in ["napi_register_module_v1",
                               "super_native_extensions_init_message_channel_context"]:
                    if symbol not in defined:
                        raise ValueError(f"Missing runtime export: {symbol}")
            libraries[library.name] = {"bytes": len(data), "needed": needed}
    with hap.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    return {
        "path": str(hap.resolve()), "bytes": hap.stat().st_size, "sha256": digest,
        "zip_crc_ok": True, "architecture": "arm64", "libraries": libraries,
        "dart_code": "aot" if "libapp.so" in libraries else "kernel",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("hap", nargs="?", type=Path,
                        default=Path("build/ohos/hap/entry-default-unsigned.hap"))
    parser.add_argument("--require-aot", action="store_true")
    args = parser.parse_args()
    print(json.dumps(verify(args.hap, args.require_aot), indent=2))
