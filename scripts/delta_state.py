#!/usr/bin/env python3
"""Cross-platform canonical URL delta state and safe run cleanup."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit


DROP_QUERY_KEYS = {"fbclid", "gclid", "igshid", "si", "feature", "ref", "from"}


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat()


def canonical_url(value: str | None) -> str | None:
    if not value or not value.strip():
        return None
    value = value.strip()
    try:
        parts = urlsplit(value)
    except ValueError:
        return value
    if not parts.netloc:
        return value
    host = (parts.hostname or "").lower()
    path = parts.path
    video_id = None
    if host == "youtu.be":
        video_id = path.strip("/").split("/")[0]
    elif host == "youtube.com" or host.endswith(".youtube.com"):
        match = re.match(r"^/shorts/([^/?]+)", path)
        if match:
            video_id = match.group(1)
        elif path == "/watch":
            video_id = dict(parse_qsl(parts.query)).get("v")
    if video_id:
        return f"https://www.youtube.com/watch?v={video_id}"
    kept = [
        (key, val)
        for key, val in parse_qsl(parts.query, keep_blank_values=True)
        if not key.lower().startswith("utm_") and key.lower() not in DROP_QUERY_KEYS
    ]
    normalized_path = "/" if path == "/" else path.rstrip("/")
    return urlunsplit(("https", host, normalized_path, urlencode(sorted(kept)), ""))


def empty_state() -> dict:
    return {
        "version": 1,
        "updated_at": None,
        "last_successful_run": None,
        "platform_cursors": {},
        "items": {},
    }


def read_json(path: Path, default=None):
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=path.name, suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            json.dump(value, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        os.replace(temp_name, path)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)


def snapshot_items(path: Path) -> list[dict]:
    data = read_json(path)
    if data is None:
        raise ValueError(f"Snapshot not found: {path}")
    return list(data.get("items", [])) if isinstance(data, dict) else list(data)


def metric(item: dict, name: str):
    metrics = item.get("metrics") or {}
    return metrics.get(name, item.get(name))


def safe_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def canonical_groups(items: list[dict]) -> tuple[dict[str, list[int]], list[dict]]:
    groups: dict[str, list[int]] = {}
    rejected = []
    for index, item in enumerate(items):
        url = canonical_url(item.get("url"))
        if not url:
            rejected.append(item)
            continue
        groups.setdefault(url, []).append(index)
    return groups, rejected


def build_diff(state: dict, items: list[dict]) -> dict:
    known = state.get("items") or {}
    groups, rejected = canonical_groups(items)
    delta = {
        "generated_at": now_iso(),
        "baseline_required": not bool(known) and bool(groups),
        "duplicate_canonical_urls": [
            {"url": url, "snapshot_indexes": indexes}
            for url, indexes in groups.items()
            if len(indexes) > 1
        ],
        "new_items": [],
        "metric_changes": [],
        "comment_changes": [],
        "transcript_rechecks": [],
        "unchanged_urls": [],
        "rejected_missing_url": rejected,
    }
    seen = set()
    for original in items:
        item = dict(original)
        url = canonical_url(item.get("url"))
        if not url:
            continue
        if url in seen:
            continue
        seen.add(url)
        old = known.get(url)
        if old is None:
            item["canonical_url"] = url
            delta["new_items"].append(item)
            delta["transcript_rechecks"].append({"url": url, "reason": "new_item"})
            continue
        changes = {}
        for name in ("views", "likes", "comments"):
            new_value, old_value = metric(item, name), metric(old, name)
            if new_value is not None and str(new_value) != str(old_value):
                changes[name] = {"old": old_value, "new": new_value}
        if changes:
            delta["metric_changes"].append({"url": url, "changes": changes})
        old_count, new_count = metric(old, "comments"), metric(item, "comments")
        old_ids = set(old.get("comment_ids") or [])
        new_ids = [value for value in (item.get("comment_ids") or []) if value and value not in old_ids]
        if (new_count is not None and str(new_count) != str(old_count)) or new_ids:
            old_num, new_num = safe_int(old_count), safe_int(new_count)
            delta["comment_changes"].append(
                {
                    "url": url,
                    "old_count": old_count,
                    "new_count": new_count,
                    "new_comment_ids": new_ids,
                    "requires_full_audit": old_num is not None and new_num is not None and new_num < old_num,
                }
            )
        old_fp, new_fp = old.get("transcript_fingerprint"), item.get("transcript_fingerprint")
        old_status = old.get("transcript_status")
        transcript_recheck = old_status == "gap" or not old_fp or (new_fp and new_fp != old_fp)
        if transcript_recheck:
            reason = "previous_gap" if old_status == "gap" else "missing_fingerprint" if not old_fp else "fingerprint_changed"
            delta["transcript_rechecks"].append({"url": url, "reason": reason})
        if not changes and not new_ids and str(new_count) == str(old_count) and not transcript_recheck:
            delta["unchanged_urls"].append(url)
    delta["summary"] = {
        "scanned": len(items),
        "new": len(delta["new_items"]),
        "metric_changed": len(delta["metric_changes"]),
        "comments_changed": len(delta["comment_changes"]),
        "transcript_recheck": len(delta["transcript_rechecks"]),
        "unchanged": len(delta["unchanged_urls"]),
        "duplicates": len(delta["duplicate_canonical_urls"]),
        "rejected_missing_url": len(delta["rejected_missing_url"]),
    }
    return delta


def commit_state(state: dict, items: list[dict], replace: bool = False) -> dict:
    stamp = now_iso()
    known = {} if replace else dict(state.get("items") or {})
    for original in items:
        item = dict(original)
        url = canonical_url(item.get("url"))
        if not url:
            continue
        item["canonical_url"] = url
        item["last_checked"] = stamp
        known[url] = item
    return {
        "version": 1,
        "updated_at": stamp,
        "last_successful_run": stamp,
        "platform_cursors": state.get("platform_cursors") or {},
        "items": known,
    }


def under_root(path: Path, root: Path) -> Path:
    resolved, resolved_root = path.resolve(), root.resolve()
    if resolved != resolved_root and resolved_root not in resolved.parents:
        raise ValueError(f"Path escapes monitoring root: {resolved}")
    return resolved


def cleanup_runs(root: Path, success_days: int, failure_hours: int, max_mb: int, apply: bool) -> dict:
    root = under_root(root, root)
    now = datetime.now().astimezone()
    actions = []
    for run_dir in (path for path in root.rglob("run-*") if path.is_dir()):
        run_dir = under_root(run_dir, root)
        summary_path = run_dir / "run-summary.json"
        text = summary_path.read_text(encoding="utf-8-sig") if summary_path.exists() else ""
        failure = bool(re.search(r'"result"\s*:\s*"(?:partial|blocked|blocked_without_mutation)"|"feishu_(?:verified|updated)"\s*:\s*false', text))
        success = not failure and bool(re.search(r'"(?:result|status)"\s*:\s*"(?:success|completed)"|"site_deployment"\s*:\s*"succeeded"|"itemsRechecked"\s*:', text))
        modified = datetime.fromtimestamp(run_dir.stat().st_mtime).astimezone()
        cutoff = now - (timedelta(days=success_days) if success else timedelta(hours=failure_hours))
        if modified < cutoff:
            actions.append({"action": "remove_run", "path": str(run_dir), "reason": "successful_retention" if success else "failed_retention"})
        elif success:
            for child in run_dir.iterdir():
                if child.name not in {"manifest.json", "run-summary.json"}:
                    actions.append({"action": "remove_intermediate", "path": str(under_root(child, root)), "reason": "successful_run_compaction"})
    if apply:
        for entry in actions:
            target = under_root(Path(entry["path"]), root)
            if target.is_dir():
                shutil.rmtree(target)
            elif target.exists():
                target.unlink()
    remaining = sum(path.stat().st_size for path in root.rglob("*") if path.is_file())
    return {
        "mode": "cleanup",
        "applied": apply,
        "planned_actions": actions,
        "remaining_mb": round(remaining / (1024 * 1024), 2),
        "cap_mb": max_mb,
        "cap_exceeded": remaining > max_mb * 1024 * 1024,
    }


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("mode", choices=("init", "diff", "commit", "reconcile", "cleanup"))
    result.add_argument("--snapshot", type=Path)
    result.add_argument("--delta", type=Path)
    result.add_argument("--state", type=Path, default=Path(__file__).with_name("state.json"))
    result.add_argument("--runs-root", type=Path, default=Path(__file__).parent)
    result.add_argument("--successful-retention-days", type=int, default=7)
    result.add_argument("--failed-retention-hours", type=int, default=48)
    result.add_argument("--max-size-mb", type=int, default=500)
    result.add_argument("--apply", action="store_true")
    result.add_argument("--verified", action="store_true", help="Confirms exact tracker readback before state mutation.")
    return result


def main() -> int:
    args = parser().parse_args()
    if args.mode == "init":
        if not args.state.exists():
            write_json(args.state, empty_state())
        output = {"mode": "init", "state": str(args.state), "exists": True}
    elif args.mode in {"diff", "commit", "reconcile"}:
        if args.snapshot is None:
            raise ValueError("--snapshot is required")
        state = read_json(args.state, empty_state())
        items = snapshot_items(args.snapshot)
        if args.mode == "diff":
            output = build_diff(state, items)
            if args.delta:
                write_json(args.delta, output)
        else:
            if not args.verified:
                raise ValueError("--verified is required for persistent state mutation")
            if args.mode == "commit" and not (state.get("items") or {}) and items:
                raise ValueError("baseline_required: use verified reconcile with a full tracker snapshot")
            groups, rejected = canonical_groups(items)
            duplicates = [url for url, indexes in groups.items() if len(indexes) > 1]
            if duplicates or rejected:
                raise ValueError(
                    f"snapshot_invalid: duplicate_canonical_urls={len(duplicates)}, rejected_missing_url={len(rejected)}"
                )
            updated = commit_state(state, items, replace=args.mode == "reconcile")
            write_json(args.state, updated)
            output = {"mode": args.mode, "items": len(updated["items"]), "state": str(args.state)}
    else:
        output = cleanup_runs(args.runs_root, args.successful_retention_days, args.failed_retention_hours, args.max_size_mb, args.apply)
    print(json.dumps(output, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(json.dumps({"error": str(exc)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(1)
