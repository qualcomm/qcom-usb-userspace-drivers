#!/usr/bin/env python3
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause
#
# Package driver files into a self-extracting installer EXE.
#
# Usage: package.py <input_exe> <driver_dir> <output_exe>
#
# This script:
#   1. Copies the input EXE to the output path
#   2. Creates an in-memory ZIP archive containing all *.inf and *.cat files
#      from the driver directory
#   3. Appends the ZIP data to the EXE
#   4. Appends a 32-byte trailer with magic, offset, size, and CRC32

import sys
import os
import shutil
import struct
import zipfile
import io
import zlib
import glob

PAYLOAD_MAGIC = b'QUSBPK01'
TRAILER_FORMAT = '<8sQQII'  # magic(8) + offset(u64) + size(u64) + crc32(u32) + reserved(u32)
TRAILER_SIZE = struct.calcsize(TRAILER_FORMAT)

def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <input_exe> <driver_dir> <output_exe>")
        sys.exit(1)

    input_exe = sys.argv[1]
    driver_dir = sys.argv[2]
    output_exe = sys.argv[3]

    if not os.path.isfile(input_exe):
        print(f"ERROR: Input EXE not found: {input_exe}")
        sys.exit(1)

    if not os.path.isdir(driver_dir):
        print(f"ERROR: Driver directory not found: {driver_dir}")
        sys.exit(1)

    # Collect driver files (INF + CAT)
    driver_files = []
    for pattern in ('*.inf', '*.cat'):
        driver_files.extend(glob.glob(os.path.join(driver_dir, pattern)))

    if not driver_files:
        print(f"ERROR: No .inf or .cat files found in {driver_dir}")
        sys.exit(1)

    print(f"Found {len(driver_files)} driver file(s):")
    for f in driver_files:
        print(f"  {os.path.basename(f)}")

    # Create ZIP archive in memory
    zip_buffer = io.BytesIO()
    with zipfile.ZipFile(zip_buffer, 'w', zipfile.ZIP_DEFLATED) as zf:
        for filepath in driver_files:
            arcname = os.path.basename(filepath)
            zf.write(filepath, arcname)
            print(f"  Added to ZIP: {arcname}")

    zip_data = zip_buffer.getvalue()
    zip_crc = zlib.crc32(zip_data) & 0xFFFFFFFF

    print(f"\nZIP payload: {len(zip_data)} bytes, CRC32: 0x{zip_crc:08X}")

    # Copy input EXE to output
    shutil.copy2(input_exe, output_exe)

    # Get EXE size (payload starts here)
    exe_size = os.path.getsize(output_exe)

    # Append ZIP data + trailer
    trailer = struct.pack(TRAILER_FORMAT,
                          PAYLOAD_MAGIC,
                          exe_size,           # payloadOffset
                          len(zip_data),      # payloadSize
                          zip_crc,            # crc32
                          0)                  # reserved

    with open(output_exe, 'ab') as f:
        f.write(zip_data)
        f.write(trailer)

    final_size = os.path.getsize(output_exe)
    print(f"\nPackaged installer: {output_exe}")
    print(f"  EXE size:     {exe_size} bytes")
    print(f"  Payload size: {len(zip_data)} bytes")
    print(f"  Trailer size: {TRAILER_SIZE} bytes")
    print(f"  Total size:   {final_size} bytes")

if __name__ == '__main__':
    main()