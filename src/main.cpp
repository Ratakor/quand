#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <fstream>
#include <getopt.h>
#include <iomanip>
#include <iostream>
#include <optional>
#include <regex>
#include <sstream>
#include <string>
#include <string_view>
#include <unistd.h>
#include <vector>

#include "utils.h"

using std::chrono::system_clock;

#define SEC_PER_DAY 86400

constexpr static const struct option long_options[] = {
    {"calendar", required_argument, 0, 'c'},
    {"config", required_argument, 0, 'C'},
    {"date", required_argument, 0, 'd'},
    {"past", required_argument, 0, 'p'},
    {"future", required_argument, 0, 'f'},
    {"help", no_argument, 0, 'h'},
    {"version", no_argument, 0, 'v'},
    {0, 0, 0, 0},
};

class DateValue {
public:
  int value;
  bool repeat;

  DateValue() = default;
  DateValue(int value, bool repeat = false) : value(value), repeat(repeat) {}

  std::string toString(int width = 2) const {
    if (value < 0) {
      return repeat ? "*" : "";
    } else {
      std::ostringstream oss;
      oss << std::setw(width) << std::setfill('0') << value;
      return oss.str() + (repeat ? "*" : "");
    }
  }

  bool operator==(const DateValue other) const {
    return value == other.value || repeat || other.repeat;
  }
};

class Year : public DateValue {
public:
  using DateValue::DateValue;

  Year(std::string s) {
    if (s.back() == '*') {
      s.pop_back();
      repeat = true;
    } else {
      repeat = false;
    }

    if (s.empty()) {
      value = -1;
    } else {
      value = stoi(s);
    }
  }

  std::string toString() const { return DateValue::toString(4); }
};

class Month : public DateValue {
private:
  constexpr static std::string_view long_names[] = {
      "January", "February", "March",     "April",   "May",      "June",
      "July",    "August",   "September", "October", "November", "December",
  };

public:
  using DateValue::DateValue;

  Month(std::string s) {
    if (s.back() == '*') {
      s.pop_back();
      repeat = true;
    } else {
      repeat = false;
    }

    if (s.empty()) {
      value = -1;
      return;
    }

    if (s.length() >= 3) {
      // std::transform(s.begin(), s.end(), s.begin(),
      //                [](char c) { return tolower(c); });
      std::for_each(s.begin(), s.end(), [](char &c) { c = tolower(c); });
      s[0] = std::toupper(s[0]);
      int i = 1;
      for (auto name : long_names) {
        if (name.starts_with(s)) {
          value = i;
          return;
        }
        i++;
      }
    }

    value = std::stoi(s);
    if (value < 1 || value > 12) {
      throw std::exception{}; // TODO
    }
  }

  // hopefully value is positive
  std::string long_name() const { return std::string{long_names[value - 1]}; }
  std::string short_name() const { return long_name().substr(0, 3); }
};

class Day : public DateValue {
private:
  // start with sunday?
  constexpr static std::string_view long_names[] = {
      "Monday", "Tuesday",  "Wednesday", "Thursday",
      "Friday", "Saturday", "Sunday",
  };

public:
  using DateValue::DateValue;

  Day(std::string s) {
    if (s.back() == '*') {
      s.pop_back();
      repeat = true;
    } else {
      repeat = false;
    }

    if (s.empty()) {
      value = -1;
      return;
    }

    if (s.length() >= 3) {
      // idk transform didn't work
      std::for_each(s.begin(), s.end(), [](char &c) { c = tolower(c); });
      s[0] = std::toupper(s[0]);
      int i = 1;
      for (auto name : long_names) {
        if (name.starts_with(s)) {
          value = i;
          return;
        }
        i++;
      }
    }

    value = std::stoi(s);
    // TODO: better check based on month?
    if (value < 1 || value > 31) {
      throw std::exception{}; // TODO
    }
  }

  // hopefully value is positive
  std::string long_name() const { return std::string{long_names[value - 1]}; }
  std::string short_name() const { return long_name().substr(0, 3); }
};

class Date {
public:
  Year year;
  Month month;
  Day day;

  Date() = default;
  Date(Year year, Month month, Day day) : year(year), month(month), day(day) {}
  Date(time_t t) {
    auto tm = *localtime(&t);
    year = {tm.tm_year + 1900};
    month = {tm.tm_mon + 1};
    day = {tm.tm_mday};
  }
  Date(std::string s) {
    auto pos = s.find_first_not_of("0123456789*");
    if (pos == std::string::npos) {
      throw std::exception{}; // idk
    }
    year = {s.substr(0, pos)};
    s.erase(0, pos);
    ltrim(s);

    pos = s.find_first_not_of(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789*");
    if (pos == std::string::npos) {
      throw std::exception{}; // idk
    }
    month = {s.substr(0, pos)};
    s.erase(0, pos);
    ltrim(s);

    day = {s};
    // pos = s.find_first_not_of(
    //     "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789*");
    // if (pos == std::string::npos) {
    //   throw std::exception{}; // idk
    // }
    // day = Day{s.substr(0, pos)};
    // s.erase(0, pos);
  }

  std::string toString() const {
    return year.toString() + " " + month.toString() + " " + day.toString();
  }

  bool operator==(const Date &other) const {
    return year == other.year && month == other.month && day == other.day;
  }
};

class Line {
public:
  Date date;
  std::string text;

  Line(std::string s) {
    size_t pos = s.find_first_not_of("0123456789*");
    if (pos == std::string::npos) {
      throw std::exception{}; // idk
    }
    date.year = {s.substr(0, pos)};
    s.erase(0, pos);
    ltrim(s);

    pos = s.find_first_not_of(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789*");
    if (pos == std::string::npos) {
      throw std::exception{}; // idk
    }
    date.month = {s.substr(0, pos)};
    s.erase(0, pos);
    ltrim(s);

    pos = s.find_first_not_of(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789*");
    if (pos == std::string::npos) {
      throw std::exception{}; // idk
    }
    date.day = {s.substr(0, pos)};
    s.erase(0, pos);

    text = trim(s); // rtrim should already be done but you never know
  }
};

class Config {
public:
  // TODO: lang
  std::string config_path;
  std::string calendar_path;
  std::string editor;
  bool header; // TODO: rename print_header
  bool mondayfirst;
  int past;
  int future;
  std::optional<Date> date; // not in config file
  std::string yesterday;
  std::string today;
  std::string tomorrow;
  std::string special;

  Config() {
    config_path =
        getenv_or("XDG_CONFIG_HOME", std::string{getenv("HOME")} + "/.config") +
        "/quand/calendar";
    calendar_path = getenv_or("XDG_DATA_HOME",
                              std::string{getenv("HOME")} + "/.local/share") +
                    "/quand/calendar";
    editor = getenv_or("EDITOR", "vi");
    header = true;
    mondayfirst = false;
    past = -1;
    future = 14;
    date = {};
    yesterday = "yesterday";
    today = "today";
    tomorrow = "tomorrow";
    special = "special";
  }
};

static void usage(std::ostream &stream) {
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

static void edit(const Config &config) {
  // auto command = config.editor + " " + config.calendar_path;
  // std::system(command.c_str());
  execlp(config.editor.c_str(), config.editor.c_str(),
         config.calendar_path.c_str(), NULL);
  exit(1);
}

static void cal(const Config &config, std::optional<std::string> arg) {
  if (config.mondayfirst) {
    execlp("cal", "cal", "-m", "-n", arg.value_or("1").c_str());
  } else {
    execlp("cal", "cal", "-s", "-n", arg.value_or("1").c_str());
  }
  exit(1);
}

static std::vector<std::string> readlines(const std::string &filename) {
  auto file = std::ifstream{filename};
  auto lines = std::vector<std::string>{};
  for (auto line = std::string{}; std::getline(file, line);) {
    lines.push_back(line);
  }
  return lines;
}

void print(const std::vector<Line> &lines, const Date &date,
           std::optional<std::string> prefix) {
  // std::cout << prefix.value_or("") << date.toString() << std::endl;
  for (auto l : lines) {
    if (l.date == date) {
      // print day short name?
      std::cout << prefix.value_or(date.toString()) << ": ";

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
  auto config = Config{};

  int opt;
  while ((opt = getopt_long(argc, argv, "c:C:d:p:f:hv", long_options,
                            nullptr)) != -1) {
    switch (opt) {
    case 'c':
      config.calendar_path = optarg;
      break;
    case 'C':
      config.config_path = optarg;
      break;
    case 'd':
      // TODO
      std::cerr << "Unsupported flag detected" << std::endl;
      break;
    case 'p':
      config.past = -std::abs(std::stoi(optarg));
      break;
    case 'f':
      config.future = std::stoi(optarg);
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

  // TODO: handle config_path & config overall

  if (optind == argc) {
    auto lines = readlines(config.calendar_path)
      | std::views::transform(trim)
      | std::views::filter([](const auto& s) { return !s.empty() && s[0] != '#'; })
      // sort :)
      | std::views::transform([](const auto& s) { return Line{s}; })
      | std::ranges::to<std::vector>();

    auto now = system_clock::to_time_t(system_clock::now());

    if (config.header) {
      // TODO: print header
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
