#!/usr/bin/env python3
"""Regenerate the fuzz seeds under mayhem/<target>/testsuite/ from files in this repo.

Usage (from the repo root): python3 mayhem/test/gen_seeds.py
"""
import os, re, sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
mh = os.path.join(root, 'mayhem')


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(data)


# fuzz_ataioctl: selector byte (index into option_sets) + a replay file
fx = os.path.join(mh, 'test', 'fixtures')
for sel, name in [(0, 'disk_ok'), (0, 'disk_failing'), (0, 'disk_ssd'), (1, 'disk_ok'), (2, 'disk_failing'),
                  (3, 'disk_ssd'), (4, 'disk_ok'), (6, 'disk_ssd'), (7, 'disk_failing')]:
    with open(os.path.join(fx, name + '.txt'), 'rb') as f:
        write(os.path.join(mh, 'fuzz_ataioctl', 'testsuite', '%s_opt%d.txt' % (name, sel)), bytes([sel]) + f.read())

# fuzz_drivedb: slices of upstream's own drive database
with open(os.path.join(root, 'drivedb', 'drivedb.h'), 'rb') as f:
    db = f.read().decode('latin-1')
start = db.index('  { "VERSION')
end = db.rindex('};')
entries = re.split(r'(?m)^(?=  \{ ")', db[start:end])
entries = [e for e in entries if e.strip()]
usb = [e for e in entries if e.startswith('  { "USB:')]
warn = [e for e in entries if re.search(r'\n    "[^"-].*\n    "', e) or 'Warning' in e][:40]
pres = [e for e in entries if '-v 1' in e and not e.startswith('  { "USB')]
slices = {
    'head': entries[:8],
    'usb': usb[:12],
    'warnings': warn[:6],
    'presets': pres[:10],
    'mid': entries[len(entries) // 2:len(entries) // 2 + 6],
    'tail': entries[-6:],
}
for name, es in slices.items():
    write(os.path.join(mh, 'fuzz_drivedb', 'testsuite', name + '.drivedb'), ''.join(es).encode('latin-1'))

# fuzz_smartd_conf: upstream's sample smartd.conf plus hand-written directive lines
with open(os.path.join(root, 'src', 'smartd.conf'), 'rb') as f:
    write(os.path.join(mh, 'fuzz_smartd_conf', 'testsuite', 'sample.conf'), f.read())
conf = {
    'devices.conf': "/dev/sda -a -I 194 -W 4,45,55 -R 5 -m root@localhost -M daily\n"
                    "/dev/sdb -d sat -H -l error -l selftest -f -s (S/../.././02|L/../../6/03)\n"
                    "/dev/nvme0 -d nvme -a -n standby,q -C 197+ -U 198+\n",
    'default.conf': "DEFAULT -a -m admin -M exec /usr/share/smartmontools/smartd-runner\n"
                    "/dev/hda\n/dev/hdb -d scsi -s S/../.././03\nDEFAULT\n/dev/sdc -p -u\n",
    'scan.conf': "DEVICESCAN -d removable -d sat -a -o on -S on \\\n  -m root -M test -s (O/../.././(00|06|12|18)|S/../.././02) # comment\n",
    'attr.conf': "/dev/sda -v 9,minutes -v 190,tempminmax -v 5,raw16(raw16) -F xerrorlba -r 187! -t -i 3 -e standby,on\n",
}
for name, text in conf.items():
    write(os.path.join(mh, 'fuzz_smartd_conf', 'testsuite', name), text.encode())
