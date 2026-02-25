#!/usr/bin/env python3
"""
PicoClaw Manager Server
──────────────────────────
Lightweight HTTP API to manage PicoClaw process lifecycle.

Endpoints:
  POST /api/picoclaw/restart      → Kill & restart PicoClaw gateway
  POST /api/picoclaw/start        → Start PicoClaw gateway
  POST /api/picoclaw/stop         → Stop PicoClaw gateway
  POST /api/picoclaw/update       → Download & install latest version
  GET  /api/picoclaw/status       → Check if PicoClaw gateway is running
  GET  /api/picoclaw/check-update → Check for newer version on GitHub
  GET  /api/health                → Health check

Usage:
  python3 picoclaw_manager.py                          # default port 8321
  python3 picoclaw_manager.py --port 9000              # custom port
  python3 picoclaw_manager.py --token mysecretkey      # with auth token
  python3 picoclaw_manager.py --picoclaw-bin /path/bin  # custom binary path
"""

import argparse
import json
import logging
import os
import platform
import re
import signal
import subprocess
import sys
import time
import urllib.request
from http.server import HTTPServer, BaseHTTPRequestHandler
from threading import Thread, Lock
from datetime import datetime

# ── Config ────────────────────────────────────────
DEFAULT_PORT = 8321
DEFAULT_PICOCLAW_BIN = os.path.expanduser("~/.local/bin/picoclaw")
DEFAULT_CONFIG_PATH = os.path.expanduser("~/.picoclaw/config.json")
DEFAULT_REPO = "muava12/picoclaw-fork"

# ── Logging ───────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s │ %(levelname)-7s │ %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("picoclaw-manager")


class PicoClawManager:
    """Manages the PicoClaw gateway process lifecycle."""

    def __init__(self, picoclaw_bin: str, config_path: str, repo: str = DEFAULT_REPO):
        self.picoclaw_bin = picoclaw_bin
        self.config_path = config_path
        self.repo = repo
        self._process = None
        self._lock = Lock()
        self._started_at = None
        self._log_tail = []
        self._max_log_lines = 100

    @property
    def is_running(self) -> bool:
        with self._lock:
            if self._process is None:
                return False
            return self._process.poll() is None

    def status(self) -> dict:
        running = self.is_running
        info = {
            "running": running,
            "pid": self._process.pid if self._process and running else None,
            "started_at": self._started_at,
            "uptime_seconds": None,
            "binary": self.picoclaw_bin,
            "recent_logs": self._log_tail[-20:],
        }
        if running and self._started_at:
            delta = datetime.now() - datetime.fromisoformat(self._started_at)
            info["uptime_seconds"] = int(delta.total_seconds())
        return info

    def start(self) -> dict:
        with self._lock:
            if self._process and self._process.poll() is None:
                return {
                    "success": False,
                    "message": "PicoClaw gateway sudah berjalan",
                    "pid": self._process.pid,
                }

            return self._start_process()

    def stop(self) -> dict:
        with self._lock:
            if self._process is None or self._process.poll() is not None:
                return {
                    "success": True,
                    "message": "PicoClaw gateway tidak sedang berjalan",
                }

            return self._stop_process()

    def restart(self) -> dict:
        with self._lock:
            # Stop if running
            if self._process and self._process.poll() is None:
                self._stop_process()
                time.sleep(1)  # brief cooldown

            return self._start_process()

    def _start_process(self) -> dict:
        """Internal: start the picoclaw gateway (must hold lock)."""
        if not os.path.isfile(self.picoclaw_bin):
            return {
                "success": False,
                "message": f"Binary tidak ditemukan: {self.picoclaw_bin}",
            }

        cmd = [self.picoclaw_bin, "gateway"]

        env = os.environ.copy()
        # Load .env file if exists alongside the binary or in cwd
        for env_path in [".env", os.path.join(os.path.dirname(self.picoclaw_bin), ".env")]:
            if os.path.isfile(env_path):
                self._load_env_file(env_path, env)
                log.info("Loaded env from: %s", env_path)
                break

        try:
            self._log_tail.clear()
            self._process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                env=env,
                preexec_fn=os.setsid,  # new process group for clean kill
            )
            self._started_at = datetime.now().isoformat()

            # Background thread to capture logs
            log_thread = Thread(
                target=self._read_output,
                args=(self._process,),
                daemon=True,
            )
            log_thread.start()

            log.info(
                "✓ PicoClaw gateway started (PID: %d)", self._process.pid
            )
            return {
                "success": True,
                "message": "PicoClaw gateway berhasil dijalankan",
                "pid": self._process.pid,
            }
        except Exception as e:
            log.error("✗ Gagal menjalankan PicoClaw: %s", e)
            return {
                "success": False,
                "message": f"Gagal menjalankan PicoClaw: {str(e)}",
            }

    def _stop_process(self) -> dict:
        """Internal: stop the running process (must hold lock)."""
        pid = self._process.pid
        try:
            # Send SIGTERM to the entire process group
            os.killpg(os.getpgid(pid), signal.SIGTERM)
            # Wait up to 5 seconds for graceful shutdown
            for _ in range(50):
                if self._process.poll() is not None:
                    break
                time.sleep(0.1)
            else:
                # Force kill if still alive
                os.killpg(os.getpgid(pid), signal.SIGKILL)
                self._process.wait(timeout=3)

            log.info("✓ PicoClaw gateway stopped (PID: %d)", pid)
            self._process = None
            self._started_at = None
            return {
                "success": True,
                "message": f"PicoClaw gateway berhasil dihentikan (PID: {pid})",
            }
        except Exception as e:
            log.error("✗ Gagal menghentikan PicoClaw: %s", e)
            return {
                "success": False,
                "message": f"Gagal menghentikan process: {str(e)}",
            }

    def _read_output(self, process: subprocess.Popen):
        """Capture process stdout in background."""
        try:
            for line in iter(process.stdout.readline, b""):
                decoded = line.decode("utf-8", errors="replace").rstrip()
                self._log_tail.append(decoded)
                if len(self._log_tail) > self._max_log_lines:
                    self._log_tail.pop(0)
                log.info("[picoclaw] %s", decoded)
        except Exception:
            pass

    @staticmethod
    def _load_env_file(path: str, env: dict):
        """Parse a simple .env file into env dict."""
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    key, _, value = line.partition("=")
                    env[key.strip()] = value.strip()

    def _get_installed_version(self) -> str:
        """Get currently installed picoclaw version."""
        try:
            result = subprocess.run(
                [self.picoclaw_bin, "--version"],
                capture_output=True, text=True, timeout=5
            )
            match = re.search(r'v?[0-9]+\.[0-9]+\.[0-9]+[^ )*]*', result.stdout)
            return match.group(0).lstrip('v') if match else "unknown"
        except Exception:
            return "unknown"

    def _get_latest_release(self) -> dict:
        """Query GitHub API for latest release."""
        url = f"https://api.github.com/repos/{self.repo}/releases/latest"
        req = urllib.request.Request(url, headers={"User-Agent": "picoclaw-manager"})
        resp = urllib.request.urlopen(req, timeout=10)
        return json.loads(resp.read().decode())

    def _detect_arch(self) -> str:
        """Detect system architecture for download."""
        machine = platform.machine().lower()
        if machine in ("x86_64", "amd64"):
            return "x86_64"
        elif machine in ("aarch64", "arm64"):
            return "arm64"
        return machine

    def check_update(self) -> dict:
        """Check if a newer version is available."""
        try:
            installed = self._get_installed_version()
            release = self._get_latest_release()
            latest = release.get("tag_name", "").lstrip("v")
            update_available = installed != latest and latest != ""
            return {
                "installed_version": installed,
                "latest_version": latest,
                "update_available": update_available,
                "release_url": release.get("html_url", ""),
            }
        except Exception as e:
            return {
                "installed_version": self._get_installed_version(),
                "latest_version": None,
                "update_available": False,
                "error": str(e),
            }

    def update(self) -> dict:
        """Download and install latest version. Stops gateway first."""
        try:
            check = self.check_update()
            if not check.get("update_available"):
                return {
                    "success": True,
                    "message": f"Sudah versi terbaru ({check.get('installed_version')})",
                    "updated": False,
                }

            latest = check["latest_version"]
            arch = self._detect_arch()
            download_url = (
                f"https://github.com/{self.repo}/releases/latest/download/"
                f"picoclaw_Linux_{arch}.tar.gz"
            )

            log.info("Downloading picoclaw %s (%s)...", latest, arch)

            # Download to temp
            tmp_tar = "/tmp/picoclaw_update.tar.gz"
            urllib.request.urlretrieve(download_url, tmp_tar)

            # Extract binary
            subprocess.run(
                ["tar", "-xzf", tmp_tar, "picoclaw", "-C", "/tmp"],
                check=True, capture_output=True
            )
            os.chmod("/tmp/picoclaw", 0o755)

            # Stop gateway if running
            was_running = self.is_running
            if was_running:
                log.info("Stopping gateway before update...")
                self.stop()
                time.sleep(1)

            # Replace binary
            import shutil
            shutil.move("/tmp/picoclaw", self.picoclaw_bin)
            os.remove(tmp_tar)

            new_version = self._get_installed_version()
            log.info("✓ Updated picoclaw: %s → %s", check["installed_version"], new_version)

            return {
                "success": True,
                "message": f"Berhasil update: {check['installed_version']} → {new_version}",
                "updated": True,
                "previous_version": check["installed_version"],
                "new_version": new_version,
                "was_running": was_running,
            }

        except Exception as e:
            log.error("✗ Update gagal: %s", e)
            return {
                "success": False,
                "message": f"Update gagal: {str(e)}",
                "updated": False,
            }


# ── HTTP Handler ──────────────────────────────────

class PicoClawHandler(BaseHTTPRequestHandler):
    """REST API handler for PicoClaw management."""

    manager: PicoClawManager = None
    auth_token: str = None

    def do_GET(self):
        if self.path == "/api/health":
            self._json_response(200, {
                "status": "ok",
                "service": "picoclaw-manager",
                "timestamp": datetime.now().isoformat(),
            })
        elif self.path == "/api/picoclaw/status":
            if not self._check_auth():
                return
            self._json_response(200, self.manager.status())
        elif self.path == "/api/picoclaw/check-update":
            if not self._check_auth():
                return
            self._json_response(200, self.manager.check_update())
        else:
            self._json_response(404, {"error": "Not found"})

    def do_POST(self):
        if not self._check_auth():
            return

        routes = {
            "/api/picoclaw/start": self.manager.start,
            "/api/picoclaw/stop": self.manager.stop,
            "/api/picoclaw/restart": self.manager.restart,
            "/api/picoclaw/update": self.manager.update,
        }

        handler = routes.get(self.path)
        if handler:
            result = handler()
            code = 200 if result.get("success", True) else 500
            self._json_response(code, result)
        else:
            self._json_response(404, {"error": "Not found"})

    def _check_auth(self) -> bool:
        """Validate Bearer token if auth is configured."""
        if not self.auth_token:
            return True

        auth_header = self.headers.get("Authorization", "")
        if auth_header == f"Bearer {self.auth_token}":
            return True

        self._json_response(401, {"error": "Unauthorized"})
        return False

    def _json_response(self, code: int, data: dict):
        body = json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        """Handle CORS preflight."""
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()

    def log_message(self, format, *args):
        """Route HTTP logs through our logger."""
        log.debug("%s %s", self.client_address[0], format % args)


# ── Main ──────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="PicoClaw Manager — Process Lifecycle Server",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Contoh penggunaan:
  python3 picoclaw_manager.py
  python3 picoclaw_manager.py --port 9000 --token rahasia123
  
Contoh request (curl):
  curl http://localhost:8321/api/picoclaw/status
  curl -X POST http://localhost:8321/api/picoclaw/start
  curl -X POST http://localhost:8321/api/picoclaw/stop
  curl -X POST http://localhost:8321/api/picoclaw/restart
  
Dengan auth token:
  curl -H "Authorization: Bearer rahasia123" http://localhost:8321/api/picoclaw/status
        """,
    )
    parser.add_argument(
        "--port", type=int, default=DEFAULT_PORT,
        help=f"Port untuk API server (default: {DEFAULT_PORT})",
    )
    parser.add_argument(
        "--host", default="0.0.0.0",
        help="Bind address (default: 0.0.0.0)",
    )
    parser.add_argument(
        "--token",
        default=os.environ.get("PICOCLAW_MANAGER_TOKEN"),
        help="Bearer token untuk autentikasi (opsional, bisa via env PICOCLAW_API_TOKEN)",
    )
    parser.add_argument(
        "--picoclaw-bin", default=DEFAULT_PICOCLAW_BIN,
        help=f"Path ke binary picoclaw (default: {DEFAULT_PICOCLAW_BIN})",
    )
    parser.add_argument(
        "--config", default=DEFAULT_CONFIG_PATH,
        help=f"Path ke config.json (default: {DEFAULT_CONFIG_PATH})",
    )
    parser.add_argument(
        "--auto-start", action="store_true",
        help="Otomatis start PicoClaw gateway saat server dimulai",
    )

    args = parser.parse_args()

    # Wire up the manager
    manager = PicoClawManager(args.picoclaw_bin, args.config)
    PicoClawHandler.manager = manager
    PicoClawHandler.auth_token = args.token

    server = HTTPServer((args.host, args.port), PicoClawHandler)

    # Banner
    print()
    print("  ┌─────────────────────────────────────────┐")
    print("  │       🦀 PicoClaw Manager Server        │")
    print("  └─────────────────────────────────────────┘")
    print()
    print(f"  Listening   → http://{args.host}:{args.port}")
    print(f"  Binary      → {args.picoclaw_bin}")
    print(f"  Auth        → {'✓ enabled' if args.token else '✗ disabled'}")
    print()
    print("  Endpoints:")
    print("    GET  /api/health               → Health check")
    print("    GET  /api/picoclaw/status       → Status PicoClaw")
    print("    GET  /api/picoclaw/check-update → Cek versi terbaru")
    print("    POST /api/picoclaw/start        → Start gateway")
    print("    POST /api/picoclaw/stop         → Stop gateway")
    print("    POST /api/picoclaw/restart      → Restart gateway")
    print("    POST /api/picoclaw/update       → Update binary")
    print()

    if args.auto_start:
        log.info("Auto-starting PicoClaw gateway...")
        result = manager.start()
        log.info("Auto-start: %s", result["message"])

    # Graceful shutdown
    def shutdown_handler(signum, frame):
        log.info("Shutting down...")
        # Run cleanup in a separate thread to avoid deadlock
        # (signal handler runs in main thread, same as serve_forever)
        def _cleanup():
            if manager.is_running:
                manager.stop()
            server.shutdown()
        Thread(target=_cleanup, daemon=True).start()

    signal.signal(signal.SIGINT, shutdown_handler)
    signal.signal(signal.SIGTERM, shutdown_handler)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass

    log.info("Server stopped.")


if __name__ == "__main__":
    main()
