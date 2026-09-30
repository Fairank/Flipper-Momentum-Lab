# Synthetic NFC comparison fixtures

These two files contain invented identifiers and data. They are parser regression
fixtures, not device captures, access credentials, or hardware validation evidence.
They replace dependencies on ignored external application directories. The seven
existing public NTAG/Ultralight dumps remain at their tracked repository paths.

The file envelope and field layout follow these protocol implementations at
`Fairank/Flipper-Momentum-Lab` revision
`c05884a048b3d71402d37107393d841fce0511c1`:

- `lib/nfc/nfc_device.c`: version 4 file envelope, Device type and UID fields.
- `lib/nfc/protocols/iso14443_3a/iso14443_3a.c`: UID, ATQA and SAK fields.
- `lib/nfc/protocols/iso14443_4a/iso14443_4a.c`, `iso14443_4a_save/load`:
  optional T0, TA(1), TB(1), TC(1) and T1...Tk components; a separate ATS field is
  not required. T0 `78` selects all three saved optional interface components.
- `lib/nfc/protocols/st25tb/st25tb.c`, `st25tb_save/load` and the feature table:
  512AT uses an eight-byte UID, numbered Block 0...15 with four known bytes each,
  and a four-byte System OTP Block. The block bytes here are a synthetic counter.

The referenced protocol implementation is part of the Flipper Zero/Momentum
project and is distributed under the repository's GNU GPL version 3 license
(`LICENSE`). These newly authored synthetic fixtures and their documentation use
the same repository license. No third-party application file or code was copied.

The Swift tests find these tracked files by repository-relative paths derived
from `#filePath`. The directory is outside the `FlipperCoreTests` SwiftPM target,
so no copied resources, package dependencies, or `Package.swift` change is needed.
