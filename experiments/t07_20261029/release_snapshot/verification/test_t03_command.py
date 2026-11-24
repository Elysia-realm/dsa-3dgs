import tempfile
import unittest
from pathlib import Path

from model.io.dma_workload import CAMERA_DESCRIPTOR_TAG
from scripts.build_t03_command import read_camera_descriptor, register_writes


class T03CommandTests(unittest.TestCase):
    def descriptor(self) -> list[int]:
        words = [0] * 28
        words[19], words[20] = 1, 2
        words[22], words[23], words[24] = 3, 4, 5
        words[25], words[26] = 1920, 1080
        words[27] = (CAMERA_DESCRIPTOR_TAG << 32) | 17
        return words

    def test_read_and_build_register_sequence(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "camera.memh"
            path.write_text("".join(f"{word:016x}\n" for word in self.descriptor()), encoding="ascii")
            words = read_camera_descriptor(path)
        writes = register_writes(words, 0x1000, 0x2000, 0x4000, 0x100000, True, False)
        by_name = {entry["name"]: entry["value"] for entry in writes}
        self.assertEqual(by_name["IMAGE_SIZE"], (1080 << 16) | 1920)
        self.assertEqual(by_name["GAUSSIAN_COUNT"], 17)
        self.assertEqual(by_name["CONTROL.START"], 0x9)

    def test_bad_tag_is_rejected(self):
        words = self.descriptor()
        words[27] &= 0xFFFFFFFF
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "camera.memh"
            path.write_text("".join(f"{word:016x}\n" for word in words), encoding="ascii")
            with self.assertRaisesRegex(ValueError, "tag/version"):
                read_camera_descriptor(path)


if __name__ == "__main__":
    unittest.main()
