#pragma once

#include <string>
#include <vector>

auto getenv_or(const char *key, const std::string &value_or) -> std::string;

auto ltrim(std::string &s) -> std::string;
auto rtrim(std::string &s) -> std::string;
auto trim(std::string &s) -> std::string;

auto readlines(const std::string &filename) -> std::vector<std::string>;
