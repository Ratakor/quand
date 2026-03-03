#include <chrono>
#include <getopt.h>
#include <iostream>
#include <optional>
#include <regex>
#include <string>
#include <string_view>
#include <unistd.h>
#include <vector>

#include "calendar.h"
#include "config.h"
#include "utils.h"

using std::chrono::system_clock;

#define SEC_PER_DAY 86400

constexpr static struct option long_options[] = {
    {"calendar", required_argument, 0, 'c'},
    {"config", required_argument, 0, 'C'},
    {"date", required_argument, 0, 'd'},
    {"past", required_argument, 0, 'p'},
    {"future", required_argument, 0, 'f'},
    {"help", no_argument, 0, 'h'},
    {"version", no_argument, 0, 'v'},
    {0, 0, 0, 0},
};

static auto usage(std::ostream &stream) -> void {
  stream
      << "Usage: quand [command] [options]\n\n"
      << "Command:\n"
      << "no command            | Default behavior\n"
      << "e|edit                | Edit the calendar file\n"
      << "c|cal [n]             | Print a calendar with 1 or n months\n"
      << "                      |\n"
      << "Flags:                |\n"
      << "-c|--calendar [path]  | Temporarily change the calendar file used\n"
      << "-C|--config [path]    | Temporarily change the config file used\n"
      << "-d|--date [date]      | Print events for a specific date, format: "
         "YYYY/MM/DD\n"
      << "-p|--past [n]         | Temporarily change past (n is negative)\n"
      << "-f|--future [n]       | Temporarily change future (n is positive)\n"
      << "-h|--help             │ Print this help message\n"
      << "-v|--version          | Print version information\n\n"
      << "Have a look at the man page for more information about the "
         "configuration."
      << std::endl;
}

static auto edit(const Config &config) -> void {
  // auto command = config.editor + " " + config.calendar_path;
  // std::system(command.c_str());
  execlp(config.editor.c_str(), config.editor.c_str(),
         config.calendar_path.c_str(), NULL);
  std::exit(1);
}

static auto cal(const Config &config, std::optional<std::string> arg) -> void {
  if (config.mondayfirst) {
    execlp("cal", "cal", "-m", "-n", arg.value_or("1").c_str());
  } else {
    execlp("cal", "cal", "-s", "-n", arg.value_or("1").c_str());
  }
  std::exit(1);
}

static auto print(const std::vector<Line> &lines, const Date &date,
                  std::optional<std::string> prefix) -> void {
  // std::cout << prefix.value_or("") << date.toString() << std::endl;
  for (auto l : lines) {
    if (l.date == date) {
      // print day short name?
      std::cout << prefix.value_or(date.to_string()) << ": ";

      auto age_re = std::regex{"([^\\\\]|^)\\\\age"};
      auto age = "\\1" + std::to_string(date.year.value - l.date.year.value);
      std::regex_replace(std::ostreambuf_iterator<char>(std::cout),
                         l.text.begin(), l.text.end(), age_re, age,
                         std::regex_constants::format_sed);
      // std::regex_replace(l.text, age_re, age,
      // std::regex_constants::format_sed);

      std::cout << '\n';
    }
  }
}

int main(int argc, char **argv) {
  auto args = Args{};
  int opt;
  while ((opt = getopt_long(argc, argv, "c:C:d:p:f:hv", long_options,
                            nullptr)) != -1) {
    switch (opt) {
    case 'c':
      args.calendar_path = optarg;
      break;
    case 'C':
      args.config_path = optarg;
      break;
    case 'd':
      // TODO: args.date
      std::cerr << "Warning: unsupported flag -- 'd'" << std::endl;
      break;
    case 'p':
      args.past = -std::abs(std::stoi(optarg));
      break;
    case 'f':
      args.future = std::stoi(optarg);
      break;
    case 'h':
      usage(std::cout);
      return 0;
    case 'v':
      std::cout << "quand " << VERSION << std::endl;
      return 0;
    default:
      usage(std::cerr);
      return 1;
    }
  }

  auto config = Config{args};

  if (optind == argc) {
    // clang-format off
    auto lines = readlines(config.calendar_path)
      | std::views::transform(trim)
      | std::views::filter([](const auto& s) { return !s.empty() && s[0] != '#'; })
      // sort :)
      | std::views::transform([](const auto& s) { return Line{s}; })
      | std::ranges::to<std::vector>();
    // clang-format on

    auto now = system_clock::to_time_t(system_clock::now());

    if (config.print_header) {
      std::cout << std::ctime(&now) << '\n';
    }

    for (; config.past < -1; config.past++) {
      print(lines, {now + config.past * SEC_PER_DAY}, std::nullopt);
    }
    if (config.past == -1) {
      print(lines, {now - SEC_PER_DAY}, config.yesterday);
    }
    {
      print(lines, {now}, config.today);
    }
    if (config.future >= 1) {
      print(lines, {now + SEC_PER_DAY}, config.tomorrow);
    }
    for (int i = 2; config.future > 1; config.future--, i++) {
      print(lines, {now + i * SEC_PER_DAY}, std::nullopt);
    }

    return 0;
  }

  auto cmd = std::string_view{argv[optind++]};

  if (cmd == "e" || cmd == "edit") {
    if (optind != argc) {
      std::cerr << "Error: too many arguments\n";
      usage(std::cerr);
      return 1;
    }
    edit(config);
    return 0;
  }

  if (cmd == "c" || cmd == "cal") {
    auto arg = (optind == argc)
                   ? std::nullopt
                   : std::make_optional<std::string>(argv[optind++]);
    if (optind != argc) {
      std::cerr << "Error: too many arguments\n";
      usage(std::cerr);
      return 1;
    }
    cal(config, arg);
    return 0;
  }

  std::cerr << "Error: invalid command -- '" << cmd << "'\n";
  usage(std::cerr);
  return 1;
}
