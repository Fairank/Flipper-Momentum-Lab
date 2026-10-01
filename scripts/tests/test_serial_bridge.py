"""Compile the actual firmware request validator; no device or radio is needed."""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SerialBridgeTests(unittest.TestCase):
    def test_wire_validation_and_bounds(self):
        compiler = shutil.which("cc")
        if not compiler:
            self.skipTest("host C compiler not installed")
        source = r"""
#include <assert.h>
#include "applications/main/lab_bridge/bridge_protocol.h"
int main(void) {
    uint8_t packet[LAB_BRIDGE_REQUEST_HEADER + LAB_BRIDGE_CHUNK + 1] =
        {70, 76, 66, 1, 52, 18, LabBridgeHello};
    assert(!lab_bridge_valid_request(NULL, 0));
    for(size_t n = 0; n < 7; ++n) assert(!lab_bridge_valid_request(packet, n));
    assert(lab_bridge_valid_request(packet, 7));
    for(size_t n = 8; n <= sizeof(packet); ++n) assert(!lab_bridge_valid_request(packet, n));
    for(size_t i = 0; i < 4; ++i) {
        packet[i] ^= 0xff;
        assert(!lab_bridge_valid_request(packet, 7));
        packet[i] ^= 0xff;
    }
    packet[6] = LabBridgeOpen;
    const uint32_t rates[] = {9600, 19200, 38400, 57600, 115200, 230400};
    for(uint8_t port = 0; port < 2; ++port) {
        packet[7] = port;
        for(size_t i = 0; i < sizeof(rates) / sizeof(rates[0]); ++i) {
            lab_bridge_write_u32(packet + 8, rates[i]);
            assert(lab_bridge_read_u32(packet + 8) == rates[i]);
            assert(lab_bridge_valid_request(packet, 12));
            assert(!lab_bridge_valid_request(packet, 11));
            assert(!lab_bridge_valid_request(packet, 13));
        }
    }
    packet[7] = 2;
    assert(!lab_bridge_valid_request(packet, 12));
    packet[7] = 0;
    lab_bridge_write_u32(packet + 8, 0);
    assert(!lab_bridge_valid_request(packet, 12));
    packet[6] = LabBridgeWrite;
    assert(!lab_bridge_valid_request(packet, 7));
    for(size_t n = 8; n < sizeof(packet); ++n) assert(lab_bridge_valid_request(packet, n));
    assert(!lab_bridge_valid_request(packet, sizeof(packet)));
    packet[6] = LabBridgeRead;
    assert(lab_bridge_valid_request(packet, 7));
    packet[6] = LabBridgeClose;
    assert(lab_bridge_valid_request(packet, 7));
    for(int operation = 5; operation <= 255; ++operation) {
        packet[6] = operation;
        assert(!lab_bridge_valid_request(packet, 7));
    }
    uint8_t word[4];
    lab_bridge_write_u32(word, UINT32_MAX);
    assert(lab_bridge_read_u32(word) == UINT32_MAX);
    return 0;
}
"""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            program = path / "bridge_test.c"
            program.write_text(source, encoding="utf-8")
            executable = path / "bridge_test.exe"
            subprocess.run(
                [
                    compiler,
                    "-std=c11",
                    "-Wall",
                    "-Wextra",
                    "-Werror",
                    "-I",
                    str(ROOT),
                    str(program),
                    "-o",
                    str(executable),
                ],
                check=True,
                timeout=120,
            )
            subprocess.run([str(executable)], check=True, timeout=30)


if __name__ == "__main__":
    unittest.main()
