#!/usr/bin/env python3
"""Generate smartctl '-r ataioctl,2' replay files describing a small synthetic ATA disk.

Usage: gen_fixtures.py OUTDIR
"""
import struct, sys, os

def cksum(b):
    b = bytearray(b)
    b[511] = 0
    b[511] = (-sum(b)) & 0xFF
    return bytes(b)

def ata_str(s, n):
    s = s.ljust(n).encode()
    out = bytearray(n)
    for i in range(0, n, 2):
        out[i], out[i + 1] = s[i + 1], s[i]
    return bytes(out)

def identify(model, serial, fw, sectors, rpm=7200):
    w = [0] * 256
    w[0] = 0x0040
    w[49] = 0x2F00
    w[60] = sectors & 0xFFFF; w[61] = (sectors >> 16) & 0xFFFF
    w[80] = 0x01F0
    w[82] = 0x7C6B; w[83] = 0x7D01 | 0x0400; w[84] = 0x4163
    w[85] = 0x7C69; w[86] = 0x3C01 | 0x0400; w[87] = 0x4163
    w[100] = sectors & 0xFFFF; w[101] = (sectors >> 16) & 0xFFFF
    w[106] = 0x4000
    w[217] = rpm
    b = bytearray(512)
    for i, v in enumerate(w):
        struct.pack_into('<H', b, 2 * i, v)
    b[20:40] = ata_str(serial, 20)
    b[46:54] = ata_str(fw, 8)
    b[54:94] = ata_str(model, 40)
    b[510] = 0xA5
    b[511] = 0
    b[511] = (-sum(b)) & 0xFF
    return bytes(b)

def values(attrs):
    b = bytearray(512)
    struct.pack_into('<H', b, 0, 0x0010)
    for i, (aid, flags, cur, worst, raw) in enumerate(attrs):
        o = 2 + 12 * i
        b[o] = aid
        struct.pack_into('<H', b, o + 1, flags)
        b[o + 3] = cur; b[o + 4] = worst
        b[o + 5:o + 11] = raw.to_bytes(6, 'little')
    b[362] = 0x00
    b[364] = 0x84; b[365] = 0x00
    b[367] = 0x7B
    b[368] = 0x03
    b[370] = 0x01
    b[372] = 2; b[373] = 40; b[374] = 5
    return cksum(b)

def thresholds(attrs):
    b = bytearray(512)
    struct.pack_into('<H', b, 0, 0x0010)
    for i, (aid, thr) in enumerate(attrs):
        o = 2 + 12 * i
        b[o] = aid; b[o + 1] = thr
    return cksum(b)

def errlog(n_errors=0):
    b = bytearray(512)
    b[0] = 1
    b[1] = 0
    struct.pack_into('<H', b, 452, n_errors)
    return cksum(b)

def stlog(entries):
    b = bytearray(512)
    struct.pack_into('<H', b, 0, 1)
    for i, (typ, status, hours) in enumerate(entries):
        o = 2 + 24 * i
        b[o] = typ; b[o + 1] = status
        struct.pack_into('<H', b, o + 2, hours)
    b[508] = len(entries)
    return cksum(b)

def hexdump(name, data):
    out = ['===== [%s] DATA START (BASE-16) =====' % name]
    for j in range(32):
        out.append('%03d-%03d: %s' % (j * 16, j * 16 + 15, ' '.join('%02x' % x for x in data[j * 16:j * 16 + 16])))
    out.append('===== [%s] DATA END (512 Bytes) =====' % name)
    return '\n'.join(out) + '\n'

def cmd(name, ret=0, sel=None, data=None):
    p = ' InputParameter=%d' % sel if sel is not None else ''
    s = 'REPORT-IOCTL: DeviceFD=3 Command=%s%s\n' % (name, p)
    s += 'REPORT-IOCTL: DeviceFD=3 Command=%s returned %d\n' % (name, ret)
    if data is not None:
        s += hexdump(name, data)
    return s

def disk(model, serial, fw, sectors, rpm, attrs, thr, errs, tests, status=0):
    s = cmd('IDENTIFY DEVICE', data=identify(model, serial, fw, sectors, rpm))
    s += cmd('SMART ENABLE', sel=0)
    s += cmd('SMART READ ATTRIBUTE VALUES', data=values(attrs))
    s += cmd('SMART READ ATTRIBUTE THRESHOLDS', data=thresholds(thr))
    s += cmd('SMART STATUS', ret=status, sel=0)
    s += cmd('SMART STATUS CHECK', ret=status, sel=0)
    s += cmd('SMART READ LOG', sel=1, data=errlog(errs))
    s += cmd('SMART READ LOG', sel=6, data=stlog(tests))
    return s

if __name__ == '__main__':
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    A = [(1, 0x002F, 100, 100, 0), (3, 0x0027, 97, 97, 0), (4, 0x0032, 100, 100, 123),
         (5, 0x0033, 100, 100, 0), (9, 0x0032, 99, 99, 2112), (12, 0x0032, 100, 100, 77),
         (194, 0x0022, 36, 45, 36), (197, 0x0012, 100, 100, 0), (198, 0x0010, 100, 100, 0)]
    T = [(1, 51), (3, 21), (4, 0), (5, 36), (9, 0), (12, 0), (194, 0), (197, 0), (198, 0)]
    files = {
        'disk_ok.txt': disk('MAYHEMTEST HDD 1TB', 'MH-SN-0001', 'FW1.00', 1953525168, 7200, A, T, 0, [(1, 0x00, 100)]),
        'disk_failing.txt': disk('MAYHEMTEST HDD FAIL', 'MH-SN-0002', 'FW2.01', 976773168, 5400,
                                 [(5, 0x0033, 1, 1, 65535), (9, 0x0032, 90, 90, 40000), (197, 0x0012, 50, 50, 8)],
                                 [(5, 36), (9, 0), (197, 0)], 3, [(2, 0x30, 1000), (1, 0x00, 900)], status=1),
        'disk_ssd.txt': disk('MAYHEMTEST SSD 256GB', 'MH-SN-0003', 'SF3.3', 500118192, 0,
                             [(5, 0x0032, 100, 100, 0), (9, 0x0032, 98, 98, 5000), (177, 0x0013, 90, 90, 150), (231, 0x0013, 88, 88, 0)],
                             [(5, 10), (9, 0), (177, 10), (231, 10)], 0, []),
    }
    for n, c in files.items():
        with open(os.path.join(out, n), 'w') as f:
            f.write(c)
