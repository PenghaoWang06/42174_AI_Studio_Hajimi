import unittest

from app.services.detector import clamp_box


class DetectorTest(unittest.TestCase):
    def test_clamp_box_limits_coordinates_to_image_bounds(self) -> None:
        self.assertEqual(
            clamp_box((-20.2, 5.7, 1200.9, 700.1), width=640, height=480),
            (0, 6, 640, 480),
        )

    def test_clamp_box_preserves_minimum_size(self) -> None:
        self.assertEqual(
            clamp_box((20.1, 30.1, 20.2, 30.2), width=640, height=480),
            (20, 30, 21, 31),
        )


if __name__ == "__main__":
    unittest.main()
