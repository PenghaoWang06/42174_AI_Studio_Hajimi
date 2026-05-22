import unittest

from app.services.ocr.parser import parse_contact_fields


class ParserTest(unittest.TestCase):
    def test_parse_contact_fields_extracts_email_phone_company_and_name(self) -> None:
        fields = parse_contact_fields(
            "\n".join(
                [
                    "John Smith",
                    "Example Pty Ltd",
                    "Senior Consultant",
                    "john.smith@example.com",
                    "+61 400 000 000",
                ]
            )
        )

        self.assertEqual(fields.name, "John Smith")
        self.assertEqual(fields.company, "Example Pty Ltd")
        self.assertEqual(fields.email, "john.smith@example.com")
        self.assertEqual(fields.phone, "+61 400 000 000")

    def test_parse_contact_fields_prefers_strong_company_signal(self) -> None:
        fields = parse_contact_fields(
            "\n".join(
                [
                    "Mohammad Zeeshan Moeed",
                    "Electrical Engineer",
                    "Member ol Group",
                    "Empower Contracting Company Limited",
                    "M: +966 59 545 4233",
                ]
            )
        )

        self.assertEqual(fields.company, "Empower Contracting Company Limited")


if __name__ == "__main__":
    unittest.main()
