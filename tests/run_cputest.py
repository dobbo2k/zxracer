#!/usr/bin/env python3
"""Run tests/cputest.asm in zxsim and compare results against expectations."""
import subprocess, sys

ZXSIM, SNA = sys.argv[1], sys.argv[2]
out = subprocess.run([ZXSIM, SNA, "-n", "10", "-q", "-d", "0xA000:256"],
                     capture_output=True, text=True, check=True).stdout
data = [int(x, 16) for x in out.split()]
fails = n = 0
for i in range(0, len(data), 4):
    a, f, ea, ef = data[i:i + 4]
    if a == 0xEE and f == 0xEE:
        break
    n += 1
    if a != ea or (f & 0xD7) != (ef & 0xD7):
        fails += 1
        print(f"test {n}: got A={a:02X} F={f:02X}, expected A={ea:02X} F={ef:02X}")
else:
    print("end marker not reached - test program crashed or hung")
    sys.exit(1)
print(f"cputest: {n - fails}/{n} passed")
sys.exit(1 if fails else 0)
