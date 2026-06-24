import argparse
import shutil
import sqlite3
from datetime import datetime, timezone
from pathlib import Path


DATA_TABLES = [
    "control_commands",
    "device_states",
    "llm_usage_events",
    "review_events",
    "memory_profiles",
    "memory_events",
    "asset_documents",
    "teaching_visualizations",
    "qa_events",
    "report_events",
    "mistake_items",
    "learning_items",
    "session_observations",
    "analyses",
    "images",
    "task_runs",
    "logs",
    "sessions",
]

AUTH_TABLES = [
    "model_configs",
    "identity_profiles",
    "account_members",
    "users",
    "accounts",
]

DATA_DIRS = ["images", "thumbnails", "visualizations"]


def timestamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")


def backup_data_dir(data_dir: Path, backup_dir: Path) -> Path:
    target = backup_dir / f"history-reset-{timestamp()}"
    target.mkdir(parents=True, exist_ok=False)
    db_path = data_dir / "xue.sqlite3"
    if db_path.exists():
        shutil.copy2(db_path, target / db_path.name)
    for name in DATA_DIRS:
        source = data_dir / name
        if source.exists():
            shutil.copytree(source, target / name)
    return target


def clear_table(conn: sqlite3.Connection, table: str) -> None:
    exists = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        (table,),
    ).fetchone()
    if exists:
        conn.execute(f"DELETE FROM {table}")


def clear_files(data_dir: Path) -> None:
    for name in DATA_DIRS:
        path = data_dir / name
        if path.exists():
            shutil.rmtree(path)
        path.mkdir(parents=True, exist_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="Backup and clear xue operational history data.")
    parser.add_argument("--data-dir", default="backend/data", help="Data directory containing xue.sqlite3")
    parser.add_argument("--backup-dir", default="", help="Backup output directory; defaults to <data-dir>/backups")
    parser.add_argument("--include-users", action="store_true", help="Also remove accounts/users/profiles/model configs")
    parser.add_argument("--yes", action="store_true", help="Actually clear data")
    args = parser.parse_args()

    data_dir = Path(args.data_dir).resolve()
    backup_dir = Path(args.backup_dir).resolve() if args.backup_dir else data_dir / "backups"
    db_path = data_dir / "xue.sqlite3"
    if not db_path.exists():
        raise SystemExit(f"Database not found: {db_path}")
    backup_path = backup_data_dir(data_dir, backup_dir)
    if not args.yes:
        print(f"Backup created at {backup_path}")
        print("Dry run only. Re-run with --yes to clear operational data.")
        return 0

    conn = sqlite3.connect(db_path)
    try:
        conn.execute("PRAGMA foreign_keys = OFF")
        for table in DATA_TABLES:
            clear_table(conn, table)
        if args.include_users:
            for table in AUTH_TABLES:
                clear_table(conn, table)
        conn.commit()
        conn.execute("VACUUM")
    finally:
        conn.close()
    clear_files(data_dir)
    print(f"Backup created at {backup_path}")
    print("Operational history cleared.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
