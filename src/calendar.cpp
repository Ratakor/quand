#include "calendar.h"
#include "utils.h"
#include <iomanip>
#include <sstream>

template <std::size_t N>
DateValue::DateValue(std::string s,
                     const std::array<std::string, N> &long_names) {
  if (s.empty()) {
    throw std::invalid_argument{"Invalid date value format"};
  }

  if (s.back() == '*') {
    repeat = true;
    if (s.size() == 1) {
      value = -1;
      return;
    }
    s.pop_back();
  } else {
    repeat = false;
  }

  if (!long_names.empty() && s.length() >= 3) {
    std::transform(s.begin(), s.end(), s.begin(),
                   [](char c) { return std::tolower(c); });
    s[0] = std::toupper(s[0]);
    for (std::size_t i = 0; i < long_names.size(); i++) {
      if (long_names[i].starts_with(s)) {
        value = static_cast<int>(i) + 1;
        return;
      }
    }
  }

  value = std::stoi(s);
}

auto DateValue::to_string(int width) const -> std::string {
  if (value < 0) {
    return repeat ? "*" : "";
  } else {
    std::ostringstream oss;
    oss << std::setw(width) << std::setfill('0') << value;
    return oss.str() + (repeat ? "*" : "");
  }
}

auto DateValue::operator==(const DateValue &other) const -> bool {
  return value == other.value || repeat || other.repeat;
}

Year::Year(std::string s) : DateValue(s, std::array<std::string, 0>{}) {}
Month::Month(std::string s) : DateValue(s, long_names) {}
Day::Day(std::string s) : DateValue(s, long_names) {}

auto Month::long_name() const -> std::string {
  // assert value > 0
  return std::string{long_names[value - 1]};
}

auto Month::short_name() const -> std::string {
  // assert value > 0
  return std::string{long_names[value - 1].substr(0, 3)};
}

auto Day::long_name() const -> std::string {
  // assert value > 0
  return std::string{long_names[value - 1]};
}

auto Day::short_name() const -> std::string {
  // assert value > 0
  return std::string{long_names[value - 1].substr(0, 3)};
}

Date::Date(time_t t) {
  auto tm = *std::localtime(&t);
  year = {tm.tm_year + 1900};
  month = {tm.tm_mon + 1};
  day = {tm.tm_mday};
}

Date::Date(std::string s) {
  auto pos = s.find_first_not_of("0123456789*");
  if (pos == std::string::npos) {
    throw std::invalid_argument{"Invalid date format"};
  }
  year = {s.substr(0, pos)};
  s.erase(0, pos);
  ltrim(s);

  pos = s.find_first_not_of(
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789*");
  if (pos == std::string::npos) {
    throw std::invalid_argument{"Invalid date format"};
  }
  month = {s.substr(0, pos)};
  s.erase(0, pos);
  ltrim(s);

  day = {s};
  // pos = s.find_first_not_of(
  //     "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789*");
  // if (pos == std::string::npos) {
  //   throw std::invalid_argument{"Invalid date format"};
  // }
  // day = Day{s.substr(0, pos)};
  // s.erase(0, pos);

  // TODO: check day / month values
  // if (value < 1 || value > 12) {
  //   throw std::invalid_argument{"Month must be between 1 and 12"};
  // }
}

auto Date::to_string() const -> std::string {
  return year.to_string() + " " + month.to_string() + " " + day.to_string();
}

auto Date::operator==(const Date &other) const -> bool {
  return year == other.year && month == other.month && day == other.day;
}

Line::Line(std::string s) {
  size_t pos = s.find_first_not_of("0123456789*");
  if (pos == std::string::npos) {
    throw std::invalid_argument{"Invalid date format"};
  }
  date.year = {s.substr(0, pos)};
  s.erase(0, pos);
  ltrim(s);

  pos = s.find_first_not_of(
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789*");
  if (pos == std::string::npos) {
    throw std::invalid_argument{"Invalid date format"};
  }
  date.month = {s.substr(0, pos)};
  s.erase(0, pos);
  ltrim(s);

  pos = s.find_first_not_of(
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789*");
  if (pos == std::string::npos) {
    throw std::invalid_argument{"Invalid date format"};
  }
  date.day = {s.substr(0, pos)};
  s.erase(0, pos);

  text = trim(s); // rtrim should already be done but you never know

  // TODO: check day / month values
  // if (value < 1 || value > 12) {
  //   throw std::invalid_argument{"Month must be between 1 and 12"};
  // }
}
