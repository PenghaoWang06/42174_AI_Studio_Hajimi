import argparse

from app.db import crud
from app.db.database import get_connection
from app.services.storage_cleanup import cleanup_orphan_storage_files


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Clean unreferenced uploaded and cropped business card images.",
    )
    parser.add_argument(
        "--max-age-hours",
        type=float,
        default=24,
        help="Only clean files older than this many hours.",
    )
    parser.add_argument(
        "--delete",
        action="store_true",
        help="Delete files. Without this flag the command only prints a dry run.",
    )
    return parser


def main() -> int:
    args = build_parser().parse_args()
    with get_connection() as connection:
        referenced_paths = crud.list_referenced_asset_paths(connection)

    plan = cleanup_orphan_storage_files(
        referenced_paths=referenced_paths,
        max_age_hours=args.max_age_hours,
        dry_run=not args.delete,
    )

    mode = "delete" if args.delete else "dry-run"
    print(f"Mode: {mode}")
    print(f"Referenced files: {len(referenced_paths)}")
    print(f"Orphan files: {len(plan.orphan_paths)}")
    for path in plan.orphan_paths:
        print(path)

    if args.delete:
        print(f"Deleted files: {len(plan.deleted_paths)}")
    else:
        print("No files were deleted. Pass --delete to remove listed files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
