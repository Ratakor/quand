#include "utils.h"

#include <algorithm>

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
