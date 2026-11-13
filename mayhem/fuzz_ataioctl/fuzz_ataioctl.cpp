// Drives the real smartctl entry point (renamed smartctl_original_main by build.sh) in "smartctl -
// <options>" mode: smartctl parses a "smartctl -r ataioctl,2" capture from stdin into a command
// table (lib/dev_parse_debug.cpp) and replays it through the full ATA print code (IDENTIFY, SMART
// attributes/thresholds, error/self-test/selective logs, ...).
//
// Input = 1 selector byte (picks the command-line option set) followed by the replay text. Each
// call is independent: the option sets avoid the options that set smartctl's file-static state
// (-b, -q, -r, --json), so nothing but the already-loaded builtin drive database persists.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>

int smartctl_original_main(int argc, char ** argv);

static const size_t max_replay = 64 * 1024 - 1; // lib/dev_parse_debug.cpp rejects larger input

static const char * const option_sets[][12] = {
  {"-x", nullptr},
  {"-a", "-f", "brief", nullptr},
  {"-i", "-H", "-c", "-A", "-l", "error", "-l", "selftest", "-l", "selective", nullptr},
  {"-x", "-F", "xerrorlba", "-v", "5,raw48", "-v", "9,minutes", "-v", "197,increasing", nullptr},
  {"-A", "-f", "hex,id", "-l", "xerror,error", "-l", "xselftest,selftest", nullptr},
  {"-a", "-t", "short", "-s", "on", "-o", "on", nullptr},
  {"-x", "-F", "swapid", "-n", "never", nullptr},
};
static const unsigned num_option_sets = sizeof(option_sets) / sizeof(option_sets[0]);

extern "C" int LLVMFuzzerInitialize(int *, char ***)
{
  if (!freopen("/dev/null", "w", stdout))
    abort();
  return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t * data, size_t size)
{
  if (size < 2 || size - 1 > max_replay)
    return -1;
  const char * const * opts = option_sets[data[0] % num_option_sets];

  char * argv[16];
  int argc = 0;
  char prog[] = "smartctl", dash[] = "-";
  argv[argc++] = prog;
  for (unsigned i = 0; opts[i]; i++)
    argv[argc++] = const_cast<char *>(opts[i]);
  argv[argc++] = dash;
  argv[argc] = nullptr;

  FILE * f = fmemopen(const_cast<uint8_t *>(data + 1), size - 1, "r");
  if (!f)
    return -1;
  FILE * old_stdin = stdin;
  stdin = f;
  optind = 0;
  smartctl_original_main(argc, argv);
  stdin = old_stdin;
  fclose(f);
  return 0;
}
