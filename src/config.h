#pragma once

#include "calendar.h"
#include <optional>
#include <string>

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

  Config();
  auto parse_config() -> void;
};
