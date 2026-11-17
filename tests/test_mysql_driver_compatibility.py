"""Exercise the linked MySQL driver through each packaged Toolbox adapter."""

from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import platform
import socket
import subprocess

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]
DATABASE = yaml.safe_load((ROOT / "extension.yaml").read_text())["extension_id"].rsplit("-", 1)[-1]
TARGETS = ("linux-amd64", "linux-arm64")


def startup(tmp_path, target, port, **options):
    source = {
        "kind": "source",
        "name": "driver-compatibility",
        "type": DATABASE,
        "host": "127.0.0.1",
        "port": str(port),
        "database": "fixture",
        "user": "fixture",
        "password": "fixture",
        "queryTimeout": "1s",
        **options,
    }
    config = tmp_path / "driver.yaml"
    config.write_text(yaml.safe_dump(source))
    return subprocess.run(
        [
            str(ROOT / "bin" / target / "toolbox"),
            "--config",
            str(config),
            "--stdio",
            "--disable-version-check",
        ],
        input="",
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
    )


def truncated_greeting(server, payload):
    connection, _ = server.accept()
    with connection:
        connection.settimeout(3)
        connection.sendall(len(payload).to_bytes(3, "little") + b"\x00" + payload)


@pytest.mark.packaged
@pytest.mark.skipif(platform.system() != "Linux", reason="Linux native payloads")
@pytest.mark.parametrize("target", TARGETS)
@pytest.mark.parametrize("greeting", [b"\x0a\x00", b"\x0a8.0\x00\x01"])
def test_truncated_initial_greeting_is_an_error_not_a_panic(tmp_path, target, greeting):
    binary = ROOT / "bin" / target / "toolbox"
    if (ROOT / ".fs-package.yaml").exists() and not binary.exists():
        pytest.skip("other architecture is excluded from this package")
    with socket.socket() as server, ThreadPoolExecutor(max_workers=1) as executor:
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        server.settimeout(15)
        sent = executor.submit(truncated_greeting, server, greeting)
        result = startup(tmp_path, target, server.getsockname()[1])
        sent.result(timeout=15)
    diagnostic = result.stdout + result.stderr
    assert result.returncode != 0, diagnostic
    assert "malformed packet" in diagnostic.lower(), diagnostic
    assert "panic:" not in diagnostic.lower(), diagnostic


@pytest.mark.packaged
@pytest.mark.skipif(platform.system() != "Linux", reason="Linux native payloads")
@pytest.mark.parametrize("target", TARGETS)
@pytest.mark.parametrize("charset", ["big5", "sjis", "gbk", "cp932", "gb18030"])
def test_mysql_rejects_unsafe_interpolation_charset_before_dial(tmp_path, target, charset):
    if DATABASE != "mysql":
        pytest.skip("only the MySQL adapter accepts queryParams")
    binary = ROOT / "bin" / target / "toolbox"
    if (ROOT / ".fs-package.yaml").exists() and not binary.exists():
        pytest.skip("other architecture is excluded from this package")
    result = startup(
        tmp_path, target, 9, queryParams={"interpolateParams": "true", "charset": charset}
    )
    diagnostic = result.stdout + result.stderr
    assert result.returncode != 0, diagnostic
    assert "interpolateParams cannot be used with unsafe charsets" in diagnostic, diagnostic


@pytest.mark.packaged
@pytest.mark.skipif(platform.system() != "Linux", reason="Linux native payloads")
@pytest.mark.parametrize("target", TARGETS)
@pytest.mark.parametrize(
    "charset,collation", [("utf8mb4", "utf8mb4_unicode_ci"), ("gb2312", "gb2312_bin")]
)
def test_mysql_safe_interpolation_charset_reaches_the_handshake(
    tmp_path, target, charset, collation
):
    if DATABASE != "mysql":
        pytest.skip("only the MySQL adapter accepts queryParams")
    binary = ROOT / "bin" / target / "toolbox"
    if (ROOT / ".fs-package.yaml").exists() and not binary.exists():
        pytest.skip("other architecture is excluded from this package")
    with socket.socket() as server, ThreadPoolExecutor(max_workers=1) as executor:
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        server.settimeout(15)
        sent = executor.submit(truncated_greeting, server, b"\x0a\x00")
        result = startup(
            tmp_path,
            target,
            server.getsockname()[1],
            queryParams={
                "interpolateParams": "true",
                "charset": charset,
                "collation": collation,
            },
        )
        sent.result(timeout=15)
    diagnostic = result.stdout + result.stderr
    assert result.returncode != 0, diagnostic
    assert "malformed packet" in diagnostic.lower(), diagnostic
    assert "unsafe charsets" not in diagnostic, diagnostic
    assert "panic:" not in diagnostic.lower(), diagnostic
