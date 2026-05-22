from pathlib import Path
import os
import tempfile
import time
import unittest


class StorageCleanupTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)

        from app.core.config import settings

        self.original_paths = {
            "storage_dir": settings.storage_dir,
            "upload_dir": settings.upload_dir,
            "crop_dir": settings.crop_dir,
        }
        object.__setattr__(settings, "storage_dir", self.root / "storage")
        object.__setattr__(settings, "upload_dir", self.root / "storage" / "uploads")
        object.__setattr__(settings, "crop_dir", self.root / "storage" / "crops")
        settings.upload_dir.mkdir(parents=True)
        settings.crop_dir.mkdir(parents=True)

    def tearDown(self) -> None:
        from app.core.config import settings

        for key, value in self.original_paths.items():
            object.__setattr__(settings, key, value)
        self.temp_dir.cleanup()

    def test_cleanup_orphan_storage_files_respects_references_and_dry_run(self) -> None:
        from app.core.config import settings
        from app.services.storage_cleanup import cleanup_orphan_storage_files

        referenced = settings.upload_dir / "referenced.jpg"
        orphan = settings.upload_dir / "orphan.jpg"
        crop_orphan = settings.crop_dir / "orphan-crop.jpg"
        referenced.write_bytes(b"referenced")
        orphan.write_bytes(b"orphan")
        crop_orphan.write_bytes(b"crop")
        old_time = time.time() - 7200
        for path in (referenced, orphan, crop_orphan):
            os.utime(path, (old_time, old_time))

        dry_run_plan = cleanup_orphan_storage_files(
            referenced_paths={"uploads/referenced.jpg"},
            max_age_hours=1,
            dry_run=True,
        )
        self.assertEqual(
            set(dry_run_plan.orphan_paths),
            {"uploads/orphan.jpg", "crops/orphan-crop.jpg"},
        )
        self.assertEqual(dry_run_plan.deleted_paths, [])
        self.assertTrue(orphan.exists())
        self.assertTrue(crop_orphan.exists())

        delete_plan = cleanup_orphan_storage_files(
            referenced_paths={"uploads/referenced.jpg"},
            max_age_hours=1,
            dry_run=False,
        )
        self.assertEqual(
            set(delete_plan.deleted_paths),
            {"uploads/orphan.jpg", "crops/orphan-crop.jpg"},
        )
        self.assertTrue(referenced.exists())
        self.assertFalse(orphan.exists())
        self.assertFalse(crop_orphan.exists())

    def test_recent_orphan_storage_files_are_kept(self) -> None:
        from app.core.config import settings
        from app.services.storage_cleanup import cleanup_orphan_storage_files

        recent = settings.upload_dir / "recent.jpg"
        recent.write_bytes(b"recent")

        plan = cleanup_orphan_storage_files(
            referenced_paths=set(),
            max_age_hours=24,
            dry_run=False,
        )
        self.assertEqual(plan.orphan_paths, [])
        self.assertTrue(recent.exists())


if __name__ == "__main__":
    unittest.main()
