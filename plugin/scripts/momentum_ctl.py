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

CODEC_PRETTY = {
    "aptx_hd": "aptX HD",
    "aptx_adaptive": "aptX Adaptive",
    "aptx_ll": "aptX LL",
    "aptx": "aptX",
    "ldac": "LDAC",
    "aac": "AAC",
    "sbc": "SBC",
    "sbc_xq": "SBC-XQ",
    "lc3": "LC3",
    "opus": "Opus",
}

def format_codec(codec_raw):
    if not codec_raw:
        return None
    raw = codec_raw.strip().lower()
    if raw in CODEC_PRETTY:
        return CODEC_PRETTY[raw]
    return codec_raw.replace("_", " ").upper()

def detect_codec(mac):
    if not mac:
        return None
    mac_under = mac.replace(":", "_").lower()
    mac_colon = mac.lower()
    # 1. Try pactl
    try:
        out = subprocess.check_output(["pactl", "list", "sinks"], text=True, stderr=subprocess.DEVNULL)
        current_sink_mac = False
        for line in out.splitlines():
            line_str = line.strip()
            if line_str.startswith("Name:"):
                current_sink_mac = (mac_under in line_str.lower() or mac_colon in line_str.lower())
            elif current_sink_mac and "api.bluez5.codec" in line_str:
                m = re.search(r"=\s*\"?([^\"]+)\"?", line_str)
                if m:
                    return format_codec(m.group(1))
    except Exception:
        pass
    # 2. Try pw-dump
    try:
        out = subprocess.check_output(["pw-dump"], text=True, stderr=subprocess.DEVNULL)
        data = json.loads(out)
        for item in data:
            props = item.get("info", {}).get("props", {})
            addr = props.get("api.bluez5.address", "").lower()
            if addr == mac_colon and "api.bluez5.codec" in props:
                return format_codec(props["api.bluez5.codec"])
    except Exception:
        pass
    return None

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

        codec = dev.get("codec")
        if not codec and connected:
            codec = detect_codec(dev.get("mac", ""))

        return {
            "connected": connected,
            "device_name": dev.get("name", "Sennheiser Momentum"),
            "mac": dev.get("mac", ""),
            "codec": codec,
            "battery": dev.get("battery", 100),
            "charging": False,
            "noise_mode": noise_mode,
            "anc_enabled": anc_enabled,
            "transparency": transparency,
            "bass_boost": settings.get("bass_boost", False),
            "sidetone": settings.get("sidetone", 0),
            "wear_detection": settings.get("wear_detection", True),
            "paired_devices": resp.get("paired_devices", []),
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
            "codec": detect_codec(mac),
            "battery": bat,
            "charging": False,
            "noise_mode": "off",
            "anc_enabled": False,
            "transparency": 50,
            "bass_boost": False,
            "sidetone": 0,
            "wear_detection": True,
            "paired_devices": [],
        }

    return {
        "connected": False,
        "device_name": "Sennheiser Momentum",
        "mac": "",
        "codec": None,
        "battery": -1,
        "charging": False,
        "noise_mode": "off",
        "anc_enabled": False,
        "transparency": 0,
        "bass_boost": False,
        "sidetone": 0,
        "wear_detection": True,
        "paired_devices": [],
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

def cmd_devices():
    res = send_daemon_cmd("devices")
    return res or {"status": "ok", "devices": []}

def cmd_switch_device(target):
    if not target:
        return {"status": "error", "message": "missing device index or name"}
    res = send_daemon_cmd(f"switch-device {target}")
    return res or {"status": "error", "message": "failed to switch device"}

def cmd_disconnect_device(target):
    if not target:
        return {"status": "error", "message": "missing device index or name"}
    res = send_daemon_cmd(f"disconnect-device {target}")
    return res or {"status": "error", "message": "failed to disconnect device"}

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
    elif sub in ("devices", "get-devices"):
        print(json.dumps(cmd_devices()))
    elif sub in ("switch-device", "switch", "connect-device"):
        arg = " ".join(sys.argv[2:]) if len(sys.argv) > 2 else ""
        print(json.dumps(cmd_switch_device(arg)))
    elif sub in ("disconnect-device", "disconnect"):
        arg = " ".join(sys.argv[2:]) if len(sys.argv) > 2 else ""
        print(json.dumps(cmd_disconnect_device(arg)))
    else:
        print(json.dumps({"status": "unknown_command"}))

if __name__ == "__main__":
    main()
