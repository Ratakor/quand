#include "config.h"

#include "utils.h"

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
      today("today"), tomorrow("tomorrow") {}
