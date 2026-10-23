"""Exercise the phone's actual C recovery engine with public and synthetic offline samples."""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "mobile/FlipperLab/Sources/ClassicRecovery"


class ClassicRecoveryTests(unittest.TestCase):
    def test_known_answer_negative_synthetic_and_cancellation(self):
        compiler = shutil.which("cc")
        if not compiler:
            self.skipTest("host C compiler not installed")
        source = r"""
#undef NDEBUG
#include <assert.h>
#include <stdio.h>
#include "recovery.c"

static bool cancel(void* context) {
    unsigned* remaining = context;
    return (*remaining)-- == 0;
}
static Cipher from_key(uint64_t key) {
    Cipher s = {0};
    for(int i = 47; i > 0; i -= 2) {
        s.odd = s.odd << 1 | ((key >> ((i - 1) ^ 7)) & 1);
        s.even = s.even << 1 | ((key >> (i ^ 7)) & 1);
    }
    return s;
}
static void make_exchange(uint32_t* words, uint64_t key, unsigned i, uint32_t nr) {
    Cipher s = from_key(key);
    word(&s, words[0] ^ words[i], false);
    words[i + 1] = nr ^ word(&s, nr, false);
    words[i + 2] = successor(words[i]) ^ word(&s, 0, false);
}
int main(void) {
    // Independent expected answer from Proxmark3 tools/pm3_tests.sh mfkey32v2 test.
    uint32_t words[7] = {0x12345678, 0x1AD8DF2B, 0x1D316024, 0x620EF048,
                         0x30D6CB07, 0xC52077E2, 0x837AC61A};
    uint64_t key = 0;
    int result = fl_classic_recover(words, &key, NULL, NULL);
    printf("known answer status=%d key=%012llX\n", result, (unsigned long long)key);
    assert(result == 1 && key == 0xA0A1A2A3A4A5ULL);
    words[6] ^= 1;
    assert(fl_classic_recover(words, &key, NULL, NULL) == 0);
    assert(key == 0);
    words[6] ^= 1;
    unsigned countdown = 0;
    assert(fl_classic_recover(words, &key, cancel, &countdown) == -1);
    countdown = 300;
    assert(fl_classic_recover(words, &key, cancel, &countdown) == -1);
    assert(key == 0);
    assert(fl_classic_recover(NULL, &key, NULL, NULL) == -3);
    assert(fl_classic_recover(words, NULL, NULL, NULL) == -3);
    const uint64_t keys[] = {0, 0xFFFFFFFFFFFFULL, 0x123456789ABCULL, 0x000000000001ULL};
    for(unsigned i = 0; i < sizeof(keys) / sizeof(keys[0]); ++i) {
        words[0] = 0x98abcdef ^ i;
        words[1] = 0x31415926 ^ i;
        words[4] = 0x27182818 ^ i;
        make_exchange(words, keys[i], 1, 0x98765432);
        make_exchange(words, keys[i], 4, 0xabcdef01);
        result = fl_classic_recover(words, &key, NULL, NULL);
        printf("synthetic %u status=%d\n", i, result);
        assert(result == 1 && key == keys[i]);
    }
    words[4] = words[1]; words[5] = words[2];
    assert(fl_classic_recover(words, &key, NULL, NULL) == -3);
    return 0;
}
"""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            program = path / "recovery_test.c"
            program.write_text(source, encoding="utf-8")
            executable = path / "recovery_test.exe"
            flags = ["-O2", "-std=c11", "-Wall", "-Wextra", "-Werror"]
            if os.name != "nt":
                flags += ["-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
            subprocess.run(
                [
                    compiler,
                    *flags,
                    "-I",
                    str(CORE),
                    "-I",
                    str(CORE / "include"),
                    str(program),
                    "-o",
                    str(executable),
                ],
                check=True,
                timeout=120,
            )
            subprocess.run([str(executable)], check=True, timeout=90)


if __name__ == "__main__":
    unittest.main()
