#include "config.h"

#include "utils.h"
#include <ranges>
#include <sstream>

static inline auto xdg_config_home() -> std::string {
  return getenv_or("XDG_CONFIG_HOME", std::string{getenv("HOME")} + "/.config");
}

static inline auto xdg_data_home() -> std::string {
  return getenv_or("XDG_DATA_HOME",
                   std::string{getenv("HOME")} + "/.local/share");
}

Config::Config()
    : config_path(xdg_config_home() + "/quand/config"),
      calendar_path(xdg_data_home() + "/quand/calendar"),
      editor(getenv_or("EDITOR", "vi")), header(true), mondayfirst(false),
      past(-1), future(14), date(std::nullopt), yesterday("yesterday"),
      today("\x1b[1mtoday"), tomorrow("tomorrow") {
  parse_config(); // TODO this shouldn't be here
}

auto Config::parse_config() -> void {
  // clang-format off
  auto lines = readlines(config_path)
    | std::views::transform(trim)
    | std::views::filter([](const auto& s) { return !s.empty() && s[0] != '#'; });
    // | std::ranges:;to<std::vector>();
  // clang-format on

  std::size_t n = 1;
  for (auto line : lines) {
    auto pos = line.find("=");
    if (pos == std::string::npos) {
      throw std::invalid_argument{"config file line " + std::to_string(n)};
    }
    auto key = line.substr(0, pos);
    trim(key); // that's ugly
    auto value = line.substr(pos + 1);
    trim(value);

    if (key == "calendar") {
      calendar_path = value;
    } else if (key == "editor") {
      editor = value;
    } else if (key == "header") {
      // overkill? noooo
      // std::istringstream{value} >> std::boolalpha >> header;
      std::istringstream{value} >> header;
    } else if (key == "past") {
      past = -std::abs(std::stoi(value));
    } else if (key == "future") {
      past = std::stoi(value);
    } else if (key == "mondayfirst") {
      // std::istringstream{value} >> std::boolalpha >> mondayfirst;
      std::istringstream{value} >> mondayfirst;
    } else if (key == "yesterday") {
      yesterday = value;
    } else if (key == "today") {
      today = value;
    } else if (key == "tomorrow") {
      tomorrow = value;
    } else {
      // std::cerr << "Found invalid key " << std::quoted(key) << " with value "
      //           << std::quoted(value) << " on line " << n << '\n';
    }

    n++;
  }
}
