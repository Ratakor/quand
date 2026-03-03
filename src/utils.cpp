#include "utils.h"

#include <algorithm>
#include <fstream>

auto getenv_or(const char *key, const std::string &value_or) -> std::string {
  auto value = getenv(key);
  if (value == nullptr) {
    return value_or;
  } else {
    return value;
  }
}

// in place
auto ltrim(std::string &s) -> std::string {
  s.erase(s.begin(), std::find_if(s.begin(), s.end(),
                                  [](auto c) { return !std::isspace(c); }));
  return s;
}

// in place
auto rtrim(std::string &s) -> std::string {
  s.erase(std::find_if(s.rbegin(), s.rend(),
                       [](auto c) { return !std::isspace(c); })
              .base(),
          s.end());
  return s;
}

// in place
auto trim(std::string &s) -> std::string {
  ltrim(s);
  rtrim(s);
  return s;
}

auto readlines(const std::string &filename) -> std::vector<std::string> {
  auto file = std::ifstream{filename};
  auto lines = std::vector<std::string>{};
  for (auto line = std::string{}; std::getline(file, line);) {
    lines.push_back(line);
  }
  return lines;
}
