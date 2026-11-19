#!/usr/bin/env python3
"""Fetch Antigravity local language_server quota and active conversation context as JSON."""
import glob
import json
import os
import re
import ssl
import subprocess
import sys
import tempfile
import urllib.request
from datetime import datetime
from pathlib import Path

import context_report

CATALOG_PATH = Path.home() / ".gemini" / "config" / "plugins" / "desktop-context" / "sidecars" / "context" / ".data" / "model-catalog.json"
CONV_DIR = Path.home() / ".gemini" / "antigravity" / "conversations"
ACTIVE_STATE_PATH = Path(tempfile.gettempdir()) / "agy_ring_active.json"
NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)


def detect_mode():
    if os.name == "nt":
        return "windows"
    try:
        if "microsoft" in Path("/proc/version").read_text(encoding="utf-8", errors="ignore").lower():
            return "wsl"
    except OSError:
        pass
    return "linux"


def _find_ls_target_windows():
    ps_cmd = (
        "Get-CimInstance Win32_Process -Filter \"Name LIKE 'language_server%'\" "
        "| Select-Object ProcessId, CommandLine | ConvertTo-Json -Compress"
    )
    try:
        raw_out = subprocess.check_output(
            ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", ps_cmd],
            text=True,
            encoding="utf-8",
            errors="replace",
            stderr=subprocess.DEVNULL,
            creationflags=NO_WINDOW,
        ).strip()
    except OSError:
        return [], None
    except subprocess.CalledProcessError:
        return [], None
    if not raw_out:
        return [], None

    try:
        procs = json.loads(raw_out)
    except ValueError:
        return [], None
    if isinstance(procs, dict):
        procs = [procs]

    try:
        net_out = subprocess.check_output(
            ["netstat", "-ano", "-p", "TCP"],
            text=True,
            encoding="utf-8",
            errors="replace",
            stderr=subprocess.DEVNULL,
            creationflags=NO_WINDOW,
        )
    except (OSError, subprocess.CalledProcessError):
        return [], None

    for p in procs:
        cmdline = p.get("CommandLine") or ""
        m = re.search(r"--csrf_token(?:=|\s+)([^\s\"']+)", cmdline)
        if not m:
            continue
        pid = p.get("ProcessId")
        if not pid:
            continue
        ports = re.findall(rf"127\.0\.0\.1:(\d+)\s+\S+\s+LISTENING\s+{pid}\b", net_out)
        if ports:
            return ports, m.group(1)
    return [], None


def _find_ls_target_linux():
    for cmd_path in glob.glob("/proc/[0-9]*/cmdline"):
        try:
            raw = open(cmd_path, "rb").read().decode("utf-8", "ignore").split("\0")
        except OSError:
            continue
        if not raw or "language_server" not in raw[0]:
            continue
        token = None
        for i, arg in enumerate(raw):
            if arg == "--csrf_token" and i + 1 < len(raw):
                token = raw[i + 1]
                break
        if not token:
            continue
        pid = cmd_path.split("/")[2]
        out = subprocess.check_output(["ss", "-tlnp"], text=True, stderr=subprocess.DEVNULL)
        ports = re.findall(rf"127\.0\.0\.1:(\d+)\b.*pid={pid}\b", out)
        if ports:
            return ports, token
    return [], None


def find_ls_target():
    if os.name == "nt":
        return _find_ls_target_windows()
    return _find_ls_target_linux()


def ls_post(ports, token, method, payload, opener):
    body = json.dumps(payload).encode()
    headers = {
        "Content-Type": "application/json",
        "Connect-Protocol-Version": "1",
        "X-Codeium-Csrf-Token": token,
    }
    for port in ports:
        req = urllib.request.Request(
            f"https://127.0.0.1:{port}/exa.language_server_pb.LanguageServerService/{method}",
            data=body,
            headers=headers,
            method="POST",
        )
        try:
            with opener.open(req, timeout=2) as resp:
                return json.loads(resp.read().decode())
        except Exception:
            continue
    return None


def fmt_local_time(iso_str, with_date=False):
    if not iso_str:
        return ""
    dt = datetime.fromisoformat(iso_str.replace("Z", "+00:00")).astimezone()
    return dt.strftime("%m-%d %H:%M" if with_date else "%H:%M")


def fmt_tokens(n):
    if n >= 1_000_000:
        return f"{n / 1_048_576:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.0f}k"
    return str(n)


def parse_ts(iso_str):
    if not iso_str:
        return 0.0
    s = re.sub(r"(\.\d{6})\d+", r"\1", iso_str.replace("Z", "+00:00"))
    try:
        return datetime.fromisoformat(s).timestamp()
    except ValueError:
        return 0.0


def pick_conversation(summaries):
    candidates = []
    for cid, v in summaries.items():
        title = " ".join((v.get("summary") or "").split())
        if not title or not (CONV_DIR / f"{cid}.db").exists():
            continue
        ann = v.get("annotations") or {}
        view_ts = parse_ts(ann.get("lastUserViewTime"))
        input_ts = parse_ts(v.get("lastUserInputTime"))
        mod_ts = parse_ts(v.get("lastModifiedTime"))
        focus_ts = max(view_ts, input_ts) or mod_ts
        candidates.append((focus_ts, mod_ts, cid, title))
    if not candidates:
        return None, ""

    top_ts = max(c[0] for c in candidates)
    tied = sorted((c for c in candidates if abs(c[0] - top_ts) < 1e-3), key=lambda c: c[1], reverse=True)
    chosen = tied[0]

    prev = {}
    try:
        prev = json.loads(ACTIVE_STATE_PATH.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        pass

    if len(tied) > 1 and prev.get("cid"):
        prev_cid, prev_ts = prev["cid"], float(prev.get("ts") or 0.0)
        if abs(top_ts - prev_ts) < 1e-3:
            chosen = next((c for c in tied if c[2] == prev_cid), chosen)
        else:
            chosen = next((c for c in tied if c[2] != prev_cid), chosen)

    try:
        ACTIVE_STATE_PATH.write_text(json.dumps({"cid": chosen[2], "ts": top_ts}), encoding="utf-8")
    except OSError:
        pass
    return chosen[2], chosen[3]


def get_context_info(ports, token, opener):
    traj = ls_post(ports, token, "GetAllCascadeTrajectories", {}, opener)
    summaries = (traj or {}).get("trajectorySummaries") or {}
    conv_id, title = pick_conversation(summaries)
    if not conv_id:
        return None
    db_path = CONV_DIR / f"{conv_id}.db"

    steps, gen = context_report.load(db_path)
    catalog_entry = {}
    if CATALOG_PATH.exists():
        try:
            catalog_entry = json.loads(CATALOG_PATH.read_text(encoding="utf-8")).get(context_report.model_id(gen)) or {}
        except OSError:
            pass
    limit = int(catalog_entry.get("maxTokens") or 0) or context_report.context_limit(gen)
    st = context_report.collect_stats(steps, gen, limit)
    used_pct = round(min(100.0, context_report.pct(st["total"], limit)), 1)
    return {
        "ctx": used_pct,
        "ctxUsed": fmt_tokens(st["total"]),
        "ctxLimit": fmt_tokens(limit),
        "ctxTitle": title,
    }


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    mode = detect_mode()
    ports, token = find_ls_target()
    if not ports:
        print(json.dumps({"ok": False, "mode": mode, "err": "AGY 未运行"}, ensure_ascii=False))
        return

    ctx = ssl._create_unverified_context()
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}),
        urllib.request.HTTPSHandler(context=ctx),
    )
    summary = ls_post(ports, token, "RetrieveUserQuotaSummary", {}, opener)
    if not summary:
        print(json.dumps({"ok": False, "mode": mode, "err": "连接失败"}, ensure_ascii=False))
        return

    buckets = {}
    for g in (summary.get("response") or {}).get("groups", []):
        for b in g.get("buckets", []):
            buckets[b.get("bucketId", "")] = b

    def read_bucket(bid, with_date=False):
        b = buckets.get(bid) or {}
        frac = b.get("remainingFraction")
        if frac is None:
            return None, ""
        return round(float(frac) * 100, 1), fmt_local_time(b.get("resetTime"), with_date=with_date)

    h_pct, h_reset = read_bucket("gemini-5h", with_date=False)
    w_pct, w_reset = read_bucket("gemini-weekly", with_date=True)
    a_pct, a_reset = read_bucket("gemini-argon-wtu-weekly", with_date=True)

    result = {
        "ok": True,
        "mode": mode,
        "h": h_pct,
        "hReset": h_reset,
        "w": w_pct,
        "wReset": w_reset,
        "a": a_pct,
        "aReset": a_reset,
    }
    try:
        ctx_info = get_context_info(ports, token, opener)
        if ctx_info:
            result.update(ctx_info)
    except Exception:
        pass

    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
