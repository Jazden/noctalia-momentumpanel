#!/usr/bin/env python3
"""
momentum_ctl.py
CLI and IPC bridge for Sennheiser Momentum headphones communicating with momentumd via Unix socket.
"""

import sys
import os
import json
import socket
import subprocess
import time
import shutil

RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
DAEMON_SOCKET = os.path.join(RUNTIME_DIR, "momentum.sock")

def send_daemon_cmd(cmd_str, timeout=2.0):
    if not os.path.exists(DAEMON_SOCKET):
        return None
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(timeout)
        s.connect(DAEMON_SOCKET)
        s.sendall(f"{cmd_str.strip()}\n".encode("utf-8"))
        data = b""
        while not data.endswith(b"\n"):
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
        s.close()
        if data:
            return json.loads(data.decode("utf-8").strip())
    except Exception:
        pass
    return None

def find_fallback_device():
    env_mac = os.environ.get("MOMENTUM_MAC")
    if env_mac:
        return env_mac.strip(), "Sennheiser Momentum"
    try:
        out = subprocess.check_output(["bluetoothctl", "devices", "Connected"], text=True, stderr=subprocess.DEVNULL)
        for line in out.strip().split("\n"):
            parts = line.split(" ", 2)
            if len(parts) >= 3:
                mac, name = parts[1], parts[2]
                if any(x in name.lower() for x in ["momentum", "sennheiser", "accentum"]):
                    return mac, name
    except Exception:
        pass
    return None, None

def get_status():
    resp = send_daemon_cmd("status")
    if resp and resp.get("status") == "ok":
        dev = resp.get("device", {})
        settings = resp.get("settings", {})
        connected = dev.get("connected", False)
        anc_enabled = settings.get("anc_enabled", False)
        transparency = settings.get("transparency", 0)

        # Derive 3-state noise_mode
        if not anc_enabled:
            noise_mode = "off"
        elif transparency >= 50:
            noise_mode = "aware"
        else:
            noise_mode = "active"

        return {
            "connected": connected,
            "device_name": dev.get("name", "Sennheiser Momentum"),
            "mac": dev.get("mac", ""),
            "battery": dev.get("battery", 100),
            "charging": False,
            "noise_mode": noise_mode,
            "anc_enabled": anc_enabled,
            "transparency": transparency,
            "bass_boost": settings.get("bass_boost", False),
            "sidetone": settings.get("sidetone", 0),
            "wear_detection": settings.get("wear_detection", True),
        }

    # Fallback if daemon is not running or starting
    mac, name = find_fallback_device()
    if mac:
        bat = 100
        try:
            info_out = subprocess.check_output(["bluetoothctl", "info", mac], text=True, stderr=subprocess.DEVNULL)
            for l in info_out.splitlines():
                if "Battery Percentage:" in l:
                    bat = int(l.split(":")[-1].strip().strip("()"))
        except Exception:
            pass
        return {
            "connected": True,
            "device_name": name or "Sennheiser Momentum",
            "mac": mac,
            "battery": bat,
            "charging": False,
            "noise_mode": "off",
            "anc_enabled": False,
            "transparency": 50,
            "bass_boost": False,
            "sidetone": 0,
            "wear_detection": True,
        }

    return {
        "connected": False,
        "device_name": "Sennheiser Momentum",
        "mac": "",
        "battery": -1,
        "charging": False,
        "noise_mode": "off",
        "anc_enabled": False,
        "transparency": 0,
        "bass_boost": False,
        "sidetone": 0,
        "wear_detection": True,
    }

def cmd_anc(arg):
    arg = (arg or "").lower()
    if arg in ("active", "anc", "on"):
        send_daemon_cmd("set-anc on")
        send_daemon_cmd("set-transparency 0")
        return {"status": "ok", "mode": "active", "anc_enabled": True, "transparency": 0}
    elif arg in ("aware", "transparency"):
        send_daemon_cmd("set-anc on")
        send_daemon_cmd("set-transparency 100")
        return {"status": "ok", "mode": "aware", "anc_enabled": True, "transparency": 100}
    elif arg in ("off",):
        send_daemon_cmd("set-anc off")
        return {"status": "ok", "mode": "off", "anc_enabled": False}
    elif arg in ("cycle",):
        st = get_status()
        cur_mode = st.get("noise_mode", "off")
        if cur_mode == "active":
            return cmd_anc("aware")
        elif cur_mode == "aware":
            return cmd_anc("off")
        else:
            return cmd_anc("active")
    else:
        # Generic toggle
        res = send_daemon_cmd("cycle-anc")
        return res or {"status": "error"}

def cmd_transparency(val_str):
    try:
        val = max(0, min(100, int(val_str)))
        res = send_daemon_cmd(f"set-transparency {val}")
        return res or {"status": "ok", "transparency": val}
    except Exception as e:
        return {"status": "error", "message": str(e)}

def cmd_bass(arg):
    arg = (arg or "").lower()
    if arg in ("on", "true", "1"):
        res = send_daemon_cmd("set-bass-boost on")
        return res or {"status": "ok", "bass_boost": True}
    elif arg in ("off", "false", "0"):
        res = send_daemon_cmd("set-bass-boost off")
        return res or {"status": "ok", "bass_boost": False}
    elif arg in ("toggle", "cycle"):
        st = get_status()
        new_val = "off" if st.get("bass_boost") else "on"
        res = send_daemon_cmd(f"set-bass-boost {new_val}")
        return res or {"status": "ok", "bass_boost": (new_val == "on")}
    else:
        res = send_daemon_cmd("get-bass-boost")
        return res or {"status": "ok"}

def cmd_connect(mac=None):
    if not mac:
        st = get_status()
        mac = st.get("mac")
    if not mac:
        mac, _ = find_fallback_device()
    if mac:
        subprocess.Popen(["bluetoothctl", "connect", mac], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return {"status": "ok", "connecting": mac}
    return {"status": "error", "message": "No MAC address available"}

def main():
    if len(sys.argv) < 2 or sys.argv[1] == "status":
        print(json.dumps(get_status()))
        return

    sub = sys.argv[1].lower()
    if sub == "anc":
        arg = sys.argv[2] if len(sys.argv) > 2 else "cycle"
        print(json.dumps(cmd_anc(arg)))
    elif sub == "transparency":
        arg = sys.argv[2] if len(sys.argv) > 2 else "50"
        print(json.dumps(cmd_transparency(arg)))
    elif sub in ("bass", "bass-boost"):
        arg = sys.argv[2] if len(sys.argv) > 2 else "toggle"
        print(json.dumps(cmd_bass(arg)))
    elif sub == "connect":
        arg = sys.argv[2] if len(sys.argv) > 2 else None
        print(json.dumps(cmd_connect(arg)))
    else:
        print(json.dumps({"status": "unknown_command"}))

if __name__ == "__main__":
    main()
