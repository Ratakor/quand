#pragma once

#include "calendar.h"
#include <optional>
#include <string>

class Args {
public:
  std::optional<std::string> config_path;
  std::optional<std::string> calendar_path;
  std::optional<Date> date;
  std::optional<int> past;
  std::optional<int> future;
};

class Config {
public:
  // TODO: lang
  std::string calendar_path;
  std::string editor;
  bool print_header;
  bool mondayfirst;
  int past;
  int future;
  std::optional<Date> date;
  std::string yesterday;
  std::string today;
  std::string tomorrow;

  Config();
  Config(const Args &args);
};
