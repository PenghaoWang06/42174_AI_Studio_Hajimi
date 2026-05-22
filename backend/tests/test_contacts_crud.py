import os
from pathlib import Path
import tempfile
import unittest


class ContactCrudTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.database_path = os.path.join(
            self.temp_dir.name,
            "test.sqlite3",
        )
        os.environ["SNAPFOLIO_DATABASE_PATH"] = self.database_path

        from app.core.config import settings
        from app.db.database import init_db

        self.original_database_path = settings.database_path
        object.__setattr__(settings, "database_path", Path(self.database_path))
        init_db()

    def tearDown(self) -> None:
        from app.core.config import settings

        object.__setattr__(settings, "database_path", self.original_database_path)
        self.temp_dir.cleanup()

    def test_contact_crud_flow(self) -> None:
        from app.db import crud
        from app.db.database import get_connection
        from app.db.schemas import ContactCreate, ContactUpdate

        with get_connection() as connection:
            created = crud.create_contact(
                connection,
                ContactCreate(
                    name="John Smith",
                    company="Example Pty Ltd",
                    email="john@example.com",
                    phone="+61 400 000 000",
                    raw_text="John Smith\nExample Pty Ltd\njohn@example.com",
                ),
            )

            self.assertEqual(created["name"], "John Smith")
            self.assertEqual(created["company"], "Example Pty Ltd")

            listed, total = crud.list_contacts(connection)
            self.assertEqual(total, 1)
            self.assertEqual(listed[0]["email"], "john@example.com")

            searched, search_total = crud.search_contacts(connection, "example")
            self.assertEqual(search_total, 1)
            self.assertEqual(searched[0]["id"], created["id"])

            updated = crud.update_contact(
                connection,
                created["id"],
                ContactUpdate(phone="+61 411 111 111"),
            )
            self.assertEqual(updated["phone"], "+61 411 111 111")

            deleted = crud.delete_contact(connection, created["id"])
            self.assertTrue(deleted)
            self.assertIsNone(crud.get_contact(connection, created["id"]))

    def test_asset_paths_are_only_unreferenced_after_last_contact_delete(self) -> None:
        from app.db import crud
        from app.db.database import get_connection
        from app.db.schemas import ContactCreate

        image_path = "uploads/shared.jpg"
        crop_path = "crops/shared.jpg"

        with get_connection() as connection:
            first = crud.create_contact(
                connection,
                ContactCreate(
                    name="First Contact",
                    image_path=image_path,
                    crop_path=crop_path,
                ),
            )
            second = crud.create_contact(
                connection,
                ContactCreate(
                    name="Second Contact",
                    image_path=image_path,
                    crop_path=crop_path,
                ),
            )

            self.assertTrue(crud.delete_contact(connection, first["id"]))
            self.assertEqual(
                crud.find_unreferenced_asset_paths(connection, [image_path, crop_path]),
                [],
            )

            self.assertTrue(crud.delete_contact(connection, second["id"]))
            self.assertEqual(
                set(crud.find_unreferenced_asset_paths(connection, [image_path, crop_path])),
                {image_path, crop_path},
            )


if __name__ == "__main__":
    unittest.main()
