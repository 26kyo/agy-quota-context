#!/usr/bin/env python3
"""Fetch Antigravity local language_server quota and active conversation context as JSON."""
import glob
import json
import os
import re
import ssl
import subprocess
import urllib.request
from datetime import datetime
from pathlib import Path

import context_report

CATALOG_PATH = Path.home() / ".gemini" / "config" / "plugins" / "desktop-context" / "sidecars" / "context" / ".data" / "model-catalog.json"
CONV_DIR = Path.home() / ".gemini" / "antigravity" / "conversations"


def find_ls_target():
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


def ls_post(ports, token, method, payload, ctx):
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
            with urllib.request.urlopen(req, context=ctx, timeout=2) as resp:
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


def get_context_info(ports, token, ctx):
    traj = ls_post(ports, token, "GetAllCascadeTrajectories", {}, ctx)
    summaries = (traj or {}).get("trajectorySummaries") or {}
    candidates = [
        (v.get("lastModifiedTime", ""), cid, " ".join((v.get("summary") or "").split()))
        for cid, v in summaries.items()
        if (v.get("summary") or "").strip() and (CONV_DIR / f"{cid}.db").exists()
    ]
    if not candidates:
        return None
    _, conv_id, title = max(candidates)
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
    ports, token = find_ls_target()
    if not ports:
        print(json.dumps({"ok": False, "err": "AGY 未运行"}))
        return

    ctx = ssl._create_unverified_context()
    summary = ls_post(ports, token, "RetrieveUserQuotaSummary", {}, ctx)
    if not summary:
        print(json.dumps({"ok": False, "err": "连接失败"}))
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
        "h": h_pct,
        "hReset": h_reset,
        "w": w_pct,
        "wReset": w_reset,
        "a": a_pct,
        "aReset": a_reset,
    }
    try:
        ctx_info = get_context_info(ports, token, ctx)
        if ctx_info:
            result.update(ctx_info)
    except Exception:
        pass

    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
