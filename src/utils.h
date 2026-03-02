#pragma once

#include <string>

std::string getenv_or(const char *key, const std::string &value_or);

std::string ltrim(std::string &s);
std::string rtrim(std::string &s);
std::string trim(std::string &s);
