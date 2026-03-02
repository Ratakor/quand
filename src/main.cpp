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

std::string getenv_or(const char *key, const std::string &value_or) {
  auto value = getenv(key);
  if (value == nullptr) {
    return value_or;
  } else {
    return value;
  }
}

// in place
std::string ltrim(std::string &s) {
  s.erase(s.begin(), std::find_if(s.begin(), s.end(),
                                  [](auto c) { return !std::isspace(c); }));
  return s;
}

// in place
std::string rtrim(std::string &s) {
  s.erase(std::find_if(s.rbegin(), s.rend(),
                       [](auto c) { return !std::isspace(c); })
              .base(),
          s.end());
  return s;
}

// in place
std::string trim(std::string &s) {
  ltrim(s);
  rtrim(s);
  return s;
}

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
  std::string yesterday;
  std::string today;
  std::string tomorrow;
  std::string special;

  Config() {
    config_path =
        getenv_or("XDG_CONFIG_HOME", std::string(getenv("HOME")) + "/.config") +
        "/quand/calendar";
    calendar_path = getenv_or("XDG_DATA_HOME",
                              std::string(getenv("HOME")) + "/.local/share") +
                    "/quand/calendar";
    editor = getenv_or("EDITOR", "vi");
    header = true;
    mondayfirst = false;
    past = -1;
    future = 14;
    yesterday = "yesterday";
    today = "today";
    tomorrow = "tomorrow";
    special = "special";
  }

  std::string toString() const {
    std::stringstream ss;
    ss << "Config {\n";
    ss << "  config_path: \"" << config_path << "\",\n";
    ss << "  calendar_path: \"" << calendar_path << "\",\n";
    ss << "  editor: \"" << editor << "\",\n";
    ss << "  header: " << (header ? "true" : "false") << ",\n";
    ss << "  mondayfirst: " << (mondayfirst ? "true" : "false") << ",\n";
    ss << "  past: " << past << ",\n";
    ss << "  future: " << future << ",\n";
    ss << "  yesterday: \"" << yesterday << "\",\n";
    ss << "  today: \"" << today << "\",\n";
    ss << "  tomorrow: \"" << tomorrow << "\",\n";
    ss << "  special: \"" << special << "\"\n";
    ss << "}";
    return ss.str();
  }
};

class DateValue {
public:
  int value;
  bool repeat;

  DateValue() {}
  DateValue(int value) : value(value) { repeat = false; }

  std::string toString(int width = 2) const {
    if (value < 0) {
      return repeat ? "*" : "";
    } else {
      std::ostringstream oss;
      oss << std::setw(width) << std::setfill('0') << value;
      return oss.str() + (repeat ? "*" : "");
    }
  }

  bool operator==(const DateValue &other) const {
    return value == other.value || repeat || other.repeat;
  }
};

class Year : public DateValue {
public:
  Year() {}
  Year(int value) : DateValue(value) {}
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
  constexpr static const std::string_view long_names[] = {
      "January", "February", "March",     "April",   "May",      "June",
      "July",    "August",   "September", "October", "November", "December",
  };

public:
  Month() {}
  Month(int value) : DateValue(value) {}
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
      throw new std::exception; // TODO
    }
  }

  // hopefully value is positive
  std::string long_name() const { return std::string(long_names[value - 1]); }
  std::string short_name() const { return long_name().substr(0, 3); }
};

class Day : public DateValue {
private:
  // start with sunday?
  constexpr static const std::string_view long_names[] = {
      "Monday", "Tuesday",  "Wednesday", "Thursday",
      "Friday", "Saturday", "Sunday",
  };

public:
  Day() {}
  Day(int value) : DateValue(value) {}
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
      throw new std::exception; // TODO
    }
  }
};

class Date {
public:
  Year year;
  Month month;
  Day day;

  Date() {}
  Date(Year year, Month month, Day day) : year(year), month(month), day(day) {}
  Date(time_t t) {
    auto tm = *localtime(&t);
    year = Year(tm.tm_year + 1900);
    month = Month(tm.tm_mon + 1);
    day = Day(tm.tm_mday);
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
    std::cout << s << std::endl;
    size_t pos = s.find_first_not_of("0123456789*");
    if (pos == std::string::npos) {
      throw new std::exception; // idk
    }
    std::cout << s.substr(0, pos) << std::endl;
    date.year = Year(s.substr(0, pos));
    s.erase(0, pos);
    ltrim(s);

    pos = s.find_first_not_of(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789*");
    if (pos == std::string::npos) {
      throw new std::exception; // idk
    }
    std::cout << s.substr(0, pos) << std::endl;
    date.month = Month(s.substr(0, pos));
    s.erase(0, pos);
    ltrim(s);

    pos = s.find_first_not_of(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789*");
    if (pos == std::string::npos) {
      throw new std::exception; // idk
    }
    std::cout << s.substr(0, pos) << std::endl;
    date.day = Day(s.substr(0, pos));
    s.erase(0, pos);

    text = trim(s); // rtrim should already be done but you never know
  }

  std::string toString() const { return date.toString() + text; }
};

static void usage(std::ostream &stream) {
  stream << "Usage: quand [command] [options]" << std::endl;
  stream << std::endl;
  stream << "Command:" << std::endl;
  stream << "no command            | Default behavior" << std::endl;
  stream << "e|edit                | Edit the calendar file" << std::endl;
  stream << "c|cal [n]             | Print a calendar with 1 or n months"
         << std::endl;
  stream << "                      |" << std::endl;
  stream << "Flags:                |" << std::endl;
  stream << "-c|--calendar [path]  | Temporarily change the calendar file used"
         << std::endl;
  stream << "-C|--config [path]    | Temporarily change the config file used"
         << std::endl;
  stream << "-d|--date [date]      | Print events for a specific date, format: "
            "YYYY/MM/DD"
         << std::endl;
  stream << "-p|--past [n]         | Temporarily change past (n is negative)"
         << std::endl;
  stream << "-f|--future [n]       | Temporarily change future (n is positive)"
         << std::endl;
  stream << "-h|--help             │ Print this help message" << std::endl;
  stream << "-v|--version          | Print version information" << std::endl;
  stream << std::endl;
  stream << "Have a look at the man page for more information about the "
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

static void cal(const Config &config, const std::optional<std::string> &arg) {
  if (config.mondayfirst) {
    execlp("cal", "cal", "-m", "-n", arg.value_or("1").c_str());
  } else {
    execlp("cal", "cal", "-s", "-n", arg.value_or("1").c_str());
  }
  exit(1);
}

static std::vector<std::string> readlines(const std::string &filename) {
  std::ifstream file(filename);
  std::vector<std::string> lines;
  for (std::string line; std::getline(file, line);) {
    lines.push_back(line);
  }
  return lines;
}

void print(const std::vector<Line> &lines, const Date &date,
           const std::optional<std::string> &prefix) {
  // std::cout << prefix.value_or("") << date.toString() << std::endl;
  for (auto l : lines) {
    if (l.date == date) {
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
  auto config = Config();

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

  if (optind + 1 < argc) {
    std::cerr << "Error: multiple commands provided\n";
    usage(std::cerr);
    return 1;
  }

  // TODO: handle config_path & config overall
  // std::cout << config.toString() << std::endl;

  if (optind == argc) {
    // TODO: handle default command
    auto raw_lines = readlines(config.calendar_path);
    std::for_each(raw_lines.begin(), raw_lines.end(), trim);
    std::vector<std::string> lines;
    std::copy_if(raw_lines.begin(), raw_lines.end(), std::back_inserter(lines),
                 [](auto s) { return !s.empty() && s[0] != '#'; });
    std::sort(lines.begin(), lines.end());

    std::vector<Line> lines_;
    std::transform(lines.begin(), lines.end(), std::back_inserter(lines_),
                   [](auto s) { return Line(s); });

    auto now = system_clock::to_time_t(system_clock::now());

    if (config.header) {
      // TODO: print header
    }

    for (; config.past < -1; config.past++) {
      print(lines_, Date(now + config.past * SEC_PER_DAY), std::nullopt);
    }
    if (config.past == -1) {
      print(lines_, Date(now - SEC_PER_DAY), config.yesterday);
    }
    {
      print(lines_, Date(now), config.today);
    }
    if (config.future >= 1) {
      print(lines_, Date(now + SEC_PER_DAY), config.tomorrow);
    }
    for (int i = 2; config.future > 1; config.future--, i++) {
      print(lines_, Date(now + i * SEC_PER_DAY), std::nullopt);
    }

    // TODO: print special (deprecate this shit imo)

  } else if (std::string_view{argv[optind]} == "edit" ||
             std::string_view{argv[optind]} == "e") {
    edit(config);
  } else if (std::string_view{argv[optind]} == "cal" ||
             std::string_view{argv[optind]} == "c") {
    std::cout << "got " << argv[optind] << std::endl;
    // TODO: handle cal arg
    cal(config, std::nullopt);
  } else {
    std::cerr << "Error: invalid command -- '" << argv[optind] << "'\n";
    usage(std::cerr);
    return 1;
  }

  return 0;
}
