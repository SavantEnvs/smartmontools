// Fuzzes the drive database parser (the format of drivedb.h / "smartctl -B FILE"): tokenizer,
// entry state machine, model/firmware regular expressions, preset option strings and the USB
// entries. The parser is static to lib/knowndrives.cpp, so the file is compiled into this
// translation unit; entries go into a local drive_database, so runs do not accumulate state.
#include "../../lib/knowndrives.cpp"

using namespace smartmon;

namespace {
class quiet_hook : public lib_global_hook
{
public:
  void lib_vprintf(const char *, va_list) override {}
};
quiet_hook the_hook;
}

extern "C" int LLVMFuzzerInitialize(int *, char ***)
{
  lib_global_hook::set(the_hook);
  return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t * data, size_t size)
{
  if (!size)
    return -1;
  FILE * f = fmemopen(const_cast<uint8_t *>(data), size, "r");
  if (!f)
    return -1;

  {
    drive_database db;
    parse_drive_database(parse_ptr(f), db, "<fuzz>");

    static const char * const models[] = {
      "WDC WD10EZEX-00BN5A0", "SAMSUNG SSD 860 EVO 500GB", "INTEL SSDSC2BW120A4", "0x152d:0x0578"
    };
    unsigned n = db.custom_size();
    if (n > 256)
      n = 256;
    for (unsigned i = 0; i < n; i++) {
      const drive_settings & e = db[i];
      for (const char * model : models)
        if (match(e.modelregexp, model) && *e.firmwareregexp)
          match(e.firmwareregexp, "01.01A01");
      usb_dev_info info;
      parse_usb_names(e.modelfamily, info);
      showonepreset(&e);
    }
  }
  fclose(f);
  return 0;
}
