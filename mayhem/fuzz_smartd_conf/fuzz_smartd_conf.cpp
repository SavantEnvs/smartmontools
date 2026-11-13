// Fuzzes smartd's configuration file parser (smartd.conf: continuation lines, DEFAULT/DEVICESCAN
// handling and every per-device directive such as -a, -d, -s REGEXP, -m, -M, -W, -R, -C, -l ...).
// ParseConfigFile() is static to src/smartd.cpp, so that file is compiled into this translation
// unit with its main() renamed; smartd reads the config from stdin when configfile is "<stdin>".
#define main smartd_original_main
#include "../../src/smartd.cpp"
#undef main

#include <stdint.h>

extern "C" int LLVMFuzzerInitialize(int *, char ***)
{
  if (!freopen("/dev/null", "w", stdout))
    abort();
  debugmode = true;
  smart_interface::init();
  return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t * data, size_t size)
{
  if (!size)
    return -1;
  FILE * f = fmemopen(const_cast<uint8_t *>(data), size, "r");
  if (!f)
    return -1;

  FILE * old_stdin = stdin;
  stdin = f;
  configfile = configfile_stdin;
  {
    dev_config_vector entries;
    smart_devtype_list scan_types;
    ParseConfigFile(entries, scan_types);
  }
  stdin = old_stdin;
  fclose(f);
  return 0;
}
