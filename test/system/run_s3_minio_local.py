#!/usr/bin/env python3
"""Run opt-in S3 tests against an owned local MinIO process."""

import os
import secrets
import select
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_TEST = "test/system/services/minio/s3_pressure_test.exs"


def free_port():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def await_ready(process, url):
    deadline = time.monotonic() + 30
    output = b""

    while time.monotonic() < deadline:
        remaining = deadline - time.monotonic()
        readable, _, _ = select.select([process.stdout], [], [], remaining)

        if not readable:
            break

        chunk = os.read(process.stdout.fileno(), 4096)
        if not chunk:
            break
        output += chunk

        if b"API:" in output:
            with urllib.request.urlopen(url + "/minio/health/live", timeout=5) as response:
                if response.status != 200:
                    raise RuntimeError("MinIO did not pass its health check")
            return

        if process.poll() is not None:
            break

    raise RuntimeError("MinIO did not report readiness within 30 seconds")


def main():
    minio = shutil.which("minio")
    if minio is None:
        print("Local MinIO is required on PATH", file=sys.stderr)
        return 1

    tests = sys.argv[1:] or [DEFAULT_TEST]
    version = subprocess.check_output([minio, "--version"], text=True).splitlines()[0]
    print(f"Using {version}", flush=True)

    with tempfile.TemporaryDirectory(prefix="jido-s3-minio-") as directory:
        port = free_port()
        console_port = free_port()
        endpoint = f"http://127.0.0.1:{port}"
        env = os.environ.copy()
        user = "jido" + secrets.token_hex(6)
        password = secrets.token_hex(18)
        env.update(
            MINIO_ROOT_USER=user,
            MINIO_ROOT_PASSWORD=password,
            JIDO_SYSTEM_MINIO_URL=endpoint,
            JIDO_SYSTEM_MINIO_ACCESS_KEY=user,
            JIDO_SYSTEM_MINIO_SECRET_KEY=password,
        )

        process = subprocess.Popen(
            [
                minio,
                "server",
                str(Path(directory) / "data"),
                "--address",
                f"127.0.0.1:{port}",
                "--console-address",
                f"127.0.0.1:{console_port}",
            ],
            cwd=ROOT,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )

        try:
            await_ready(process, endpoint)
            return subprocess.run(
                ["mix", "test", *tests, "--only", "service", "--seed", "0"],
                cwd=ROOT,
                env=env,
                check=False,
            ).returncode
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError) as error:
        print(f"Local MinIO test failed: {error}", file=sys.stderr)
        sys.exit(1)
