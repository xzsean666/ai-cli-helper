#!/usr/bin/env python3
"""
Codex Workspace Synchronizer

Synchronizes sessions, rollouts, threads, databases, config, and skills
between an alias-isolated CODEX_HOME and a shared data pool (e.g. shared-data).
Ensures that all aliases (e.g. codexa, codexb, codexh) share the exact same
workspace and session history while preserving per-alias authentication isolation.
"""

import os
import sys
import glob
import json
import shutil
import sqlite3
import tomllib


def is_file_open_by_process(path: str) -> bool:
    """Check if a file or directory is actively opened by any process."""
    if not os.path.exists(path):
        return False
    try:
        real_p = os.path.realpath(path)
        for proc in os.listdir("/proc"):
            if not proc.isdigit():
                continue
            fd_dir = os.path.join("/proc", proc, "fd")
            if not os.path.isdir(fd_dir):
                continue
            try:
                for fd in os.listdir(fd_dir):
                    fd_path = os.path.join(fd_dir, fd)
                    try:
                        if os.path.islink(fd_path) and os.path.realpath(fd_path) == real_p:
                            return True
                    except Exception:
                        pass
            except Exception:
                pass
    except Exception:
        pass
    return False


def read_toml(path: str) -> dict:
    if not os.path.exists(path):
        return {}
    try:
        with open(path, "rb") as f:
            return tomllib.load(f)
    except Exception:
        return {}


def write_toml(data: dict, path: str):
    lines = []
    # Scalar values first
    for k, v in data.items():
        if isinstance(v, dict):
            continue
        if isinstance(v, bool):
            lines.append(f"{k} = {'true' if v else 'false'}")
        elif isinstance(v, (int, float)):
            lines.append(f"{k} = {v}")
        elif isinstance(v, str):
            lines.append(f'{k} = "{v}"')

    # Tables / sections
    for k, v in data.items():
        if isinstance(v, dict):
            if k == "projects":
                for proj_path, proj_conf in v.items():
                    lines.append(f'\n[projects."{proj_path}"]')
                    if isinstance(proj_conf, dict):
                        for pk, pv in proj_conf.items():
                            if isinstance(pv, str):
                                lines.append(f'{pk} = "{pv}"')
                            elif isinstance(pv, bool):
                                lines.append(f"{pk} = {'true' if pv else 'false'}")
                            elif isinstance(pv, (int, float)):
                                lines.append(f"{pk} = {pv}")
            else:
                lines.append(f"\n[{k}]")
                if isinstance(v, dict):
                    for subk, subv in v.items():
                        if isinstance(subv, bool):
                            lines.append(f"{subk} = {'true' if subv else 'false'}")
                        elif isinstance(subv, (int, float)):
                            lines.append(f"{subk} = {subv}")
                        elif isinstance(subv, str):
                            lines.append(f'{subk} = "{subv}"')

    tmp_path = path + f".tmp.{os.getpid()}"
    with open(tmp_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines).strip() + "\n")
    os.replace(tmp_path, path)


def merge_config_toml(src_path: str, dst_path: str):
    dst_data = read_toml(dst_path)
    src_data = read_toml(src_path)
    if not dst_data and not src_data:
        return

    merged = dst_data.copy()
    for k, v in src_data.items():
        if k == "projects" and isinstance(v, dict):
            if "projects" not in merged or not isinstance(merged["projects"], dict):
                merged["projects"] = {}
            merged["projects"].update(v)
        elif k not in merged:
            merged[k] = v

    write_toml(merged, dst_path)


def merge_session_index(src_path: str, dst_path: str):
    records = {}
    for fpath in [dst_path, src_path]:
        if os.path.isfile(fpath):
            try:
                with open(fpath, "r", encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            data = json.loads(line)
                            sid = data.get("id")
                            if sid:
                                if sid in records:
                                    cur_time = records[sid].get("updated_at", "")
                                    new_time = data.get("updated_at", "")
                                    if new_time >= cur_time:
                                        if new_time == cur_time and not data.get("thread_name") and records[sid].get("thread_name"):
                                            pass
                                        else:
                                            records[sid] = data
                                else:
                                    records[sid] = data
                        except Exception:
                            pass
            except Exception:
                pass

    sorted_records = sorted(records.values(), key=lambda x: x.get("updated_at", ""))
    tmp_path = dst_path + f".tmp.{os.getpid()}"
    with open(tmp_path, "w", encoding="utf-8") as f:
        for r in sorted_records:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    os.replace(tmp_path, dst_path)


def merge_history_jsonl(src_path: str, dst_path: str):
    seen = set()
    lines = []
    for fpath in [dst_path, src_path]:
        if os.path.isfile(fpath):
            try:
                with open(fpath, "r", encoding="utf-8") as f:
                    for line in f:
                        line_stripped = line.strip()
                        if line_stripped and line_stripped not in seen:
                            seen.add(line_stripped)
                            lines.append(line_stripped)
            except Exception:
                pass
    tmp_path = dst_path + f".tmp.{os.getpid()}"
    with open(tmp_path, "w", encoding="utf-8") as f:
        for l in lines:
            f.write(l + "\n")
    os.replace(tmp_path, dst_path)


def merge_sqlite(src_path: str, dst_path: str):
    if not os.path.isfile(src_path) or not os.path.isfile(dst_path):
        return
    try:
        if os.path.samefile(src_path, dst_path):
            return
    except Exception:
        pass

    try:
        conn = sqlite3.connect(dst_path, timeout=15.0)
        cur = conn.cursor()
        cur.execute("PRAGMA journal_mode=WAL;")
        cur.execute("PRAGMA synchronous=NORMAL;")
        cur.execute("ATTACH DATABASE ? AS src;", (src_path,))

        tables = [r[0] for r in cur.execute("SELECT name FROM src.sqlite_master WHERE type='table'").fetchall()]
        for table in tables:
            if table in ("sqlite_sequence", "_sqlx_migrations"):
                continue

            if table == "threads":
                try:
                    cur.execute("""
                        INSERT INTO main.threads SELECT * FROM src.threads WHERE true
                        ON CONFLICT(id) DO UPDATE SET
                            rollout_path = excluded.rollout_path,
                            created_at = excluded.created_at,
                            updated_at = excluded.updated_at,
                            title = excluded.title,
                            tokens_used = excluded.tokens_used,
                            has_user_event = excluded.has_user_event,
                            archived = excluded.archived,
                            archived_at = excluded.archived_at,
                            git_sha = excluded.git_sha,
                            git_branch = excluded.git_branch,
                            git_origin_url = excluded.git_origin_url,
                            model = excluded.model,
                            reasoning_effort = excluded.reasoning_effort,
                            created_at_ms = excluded.created_at_ms,
                            updated_at_ms = excluded.updated_at_ms,
                            recency_at = excluded.recency_at,
                            recency_at_ms = excluded.recency_at_ms,
                            name = excluded.name,
                            is_pinned = excluded.is_pinned
                        WHERE excluded.updated_at >= main.threads.updated_at;
                    """)
                    continue
                except Exception:
                    pass

            # Generic table merge with INSERT OR IGNORE
            try:
                cur.execute(f'INSERT OR IGNORE INTO main."{table}" SELECT * FROM src."{table}";')
            except Exception:
                try:
                    cur.execute(f'PRAGMA main.table_info("{table}")')
                    dst_cols = set(r[1] for r in cur.fetchall())
                    cur.execute(f'PRAGMA src.table_info("{table}")')
                    src_cols = [r[1] for r in cur.fetchall()]
                    common_cols = [c for c in src_cols if c in dst_cols]
                    if common_cols:
                        cols_str = ", ".join(f'"{c}"' for c in common_cols)
                        cur.execute(f'INSERT OR IGNORE INTO main."{table}" ({cols_str}) SELECT {cols_str} FROM src."{table}";')
                except Exception:
                    pass

        conn.commit()
        conn.close()
    except Exception as e:
        sys.stderr.write(f"[WARN] Failed to merge sqlite {src_path} into {dst_path}: {e}\n")


def safe_symlink(target: str, link_name: str):
    try:
        if os.path.islink(link_name):
            if os.path.realpath(link_name) == os.path.realpath(target):
                return
            os.unlink(link_name)
        elif os.path.lexists(link_name):
            if os.path.isdir(link_name):
                shutil.rmtree(link_name)
            else:
                os.unlink(link_name)
        os.symlink(target, link_name)
    except Exception as e:
        sys.stderr.write(f"[WARN] Failed to link {link_name} -> {target}: {e}\n")


def sync_workspace(pool_dir: str, codex_home: str):
    pool_dir = os.path.abspath(pool_dir)
    codex_home = os.path.abspath(codex_home)
    if pool_dir == codex_home:
        return

    os.makedirs(pool_dir, exist_ok=True)
    os.makedirs(codex_home, exist_ok=True)

    # 1. Shared directories
    shared_dirs = ["rollouts", "archived_rollouts", "sessions", "skills", "thread-writer-locks", "shell_snapshots"]
    for d in shared_dirs:
        p_dir = os.path.join(pool_dir, d)
        c_dir = os.path.join(codex_home, d)
        os.makedirs(p_dir, exist_ok=True)

        if os.path.islink(c_dir):
            if os.path.realpath(c_dir) != os.path.realpath(p_dir):
                safe_symlink(p_dir, c_dir)
        elif os.path.isdir(c_dir):
            try:
                shutil.copytree(c_dir, p_dir, dirs_exist_ok=True)
                shutil.rmtree(c_dir)
            except Exception as e:
                sys.stderr.write(f"[WARN] Error moving dir {c_dir} to {p_dir}: {e}\n")
            safe_symlink(p_dir, c_dir)
        else:
            safe_symlink(p_dir, c_dir)

    # 2. session_index.jsonl
    p_sidx = os.path.join(pool_dir, "session_index.jsonl")
    c_sidx = os.path.join(codex_home, "session_index.jsonl")
    if not os.path.exists(p_sidx):
        open(p_sidx, "a").close()

    if os.path.islink(c_sidx):
        if os.path.realpath(c_sidx) != os.path.realpath(p_sidx):
            safe_symlink(p_sidx, c_sidx)
    elif os.path.isfile(c_sidx):
        merge_session_index(c_sidx, p_sidx)
        try:
            os.unlink(c_sidx)
        except Exception:
            pass
        safe_symlink(p_sidx, c_sidx)
    else:
        safe_symlink(p_sidx, c_sidx)

    # 3. history.jsonl
    p_hist = os.path.join(pool_dir, "history.jsonl")
    c_hist = os.path.join(codex_home, "history.jsonl")
    if not os.path.exists(p_hist):
        open(p_hist, "a").close()

    if os.path.islink(c_hist):
        if os.path.realpath(c_hist) != os.path.realpath(p_hist):
            safe_symlink(p_hist, c_hist)
    elif os.path.isfile(c_hist):
        merge_history_jsonl(c_hist, p_hist)
        try:
            os.unlink(c_hist)
        except Exception:
            pass
        safe_symlink(p_hist, c_hist)
    else:
        safe_symlink(p_hist, c_hist)

    # 4. config.toml
    p_cfg = os.path.join(pool_dir, "config.toml")
    c_cfg = os.path.join(codex_home, "config.toml")
    if os.path.islink(c_cfg):
        if os.path.realpath(c_cfg) != os.path.realpath(p_cfg):
            safe_symlink(p_cfg, c_cfg)
    elif os.path.isfile(c_cfg):
        if os.path.exists(p_cfg):
            merge_config_toml(c_cfg, p_cfg)
        else:
            try:
                shutil.copy2(c_cfg, p_cfg)
            except Exception:
                pass
        try:
            os.unlink(c_cfg)
        except Exception:
            pass
        safe_symlink(p_cfg, c_cfg)
    else:
        if os.path.exists(p_cfg):
            safe_symlink(p_cfg, c_cfg)

    # 5. installation_id & .sandbox_migration
    for meta_file in ["installation_id", ".sandbox_migration"]:
        p_meta = os.path.join(pool_dir, meta_file)
        c_meta = os.path.join(codex_home, meta_file)
        if os.path.islink(c_meta):
            if os.path.realpath(c_meta) != os.path.realpath(p_meta):
                safe_symlink(p_meta, c_meta)
        elif os.path.isfile(c_meta):
            if not os.path.exists(p_meta):
                try:
                    shutil.copy2(c_meta, p_meta)
                except Exception:
                    pass
            try:
                os.unlink(c_meta)
            except Exception:
                pass
            safe_symlink(p_meta, c_meta)
        else:
            if os.path.exists(p_meta):
                safe_symlink(p_meta, c_meta)

    # 6. SQLite databases (*.sqlite)
    all_dbs = set()
    for f in glob.glob(os.path.join(pool_dir, "*.sqlite")):
        all_dbs.add(os.path.basename(f))
    for f in glob.glob(os.path.join(codex_home, "*.sqlite")):
        all_dbs.add(os.path.basename(f))

    for db_name in sorted(all_dbs):
        p_db = os.path.join(pool_dir, db_name)
        c_db = os.path.join(codex_home, db_name)

        if os.path.islink(c_db):
            if os.path.realpath(c_db) != os.path.realpath(p_db):
                safe_symlink(p_db, c_db)
        elif os.path.isfile(c_db):
            is_open = is_file_open_by_process(c_db)
            if os.path.exists(p_db):
                merge_sqlite(c_db, p_db)
                if not is_open:
                    try:
                        os.unlink(c_db)
                        for ext in ["-wal", "-shm"]:
                            wal_f = c_db + ext
                            if os.path.exists(wal_f):
                                os.unlink(wal_f)
                    except Exception as e:
                        sys.stderr.write(f"[WARN] Error removing local db {c_db}: {e}\n")
                    safe_symlink(p_db, c_db)
            else:
                if not is_open:
                    try:
                        shutil.move(c_db, p_db)
                        for ext in ["-wal", "-shm"]:
                            wal_f = c_db + ext
                            if os.path.exists(wal_f):
                                shutil.move(wal_f, p_db + ext)
                    except Exception as e:
                        sys.stderr.write(f"[WARN] Error moving db {c_db} to {p_db}: {e}\n")
                    safe_symlink(p_db, c_db)
                else:
                    try:
                        shutil.copy2(c_db, p_db)
                        for ext in ["-wal", "-shm"]:
                            wal_f = c_db + ext
                            if os.path.exists(wal_f):
                                shutil.copy2(wal_f, p_db + ext)
                    except Exception:
                        pass
        else:
            if os.path.exists(p_db):
                safe_symlink(p_db, c_db)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: codex_sync.py <pool_dir> <codex_home>")
        sys.exit(1)
    sync_workspace(sys.argv[1], sys.argv[2])
