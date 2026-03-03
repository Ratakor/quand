#include "calendar.h"
#include "utils.h"
#include <iomanip>
#include <sstream>

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

auto DateValue::parse_repeat(std::string &s, bool &repeat) -> void {
  if (!s.empty() && s.back() == '*') {
    s.pop_back();
    repeat = true;
  } else {
    repeat = false;
  }
}

Year::Year(std::string s) {
  parse_repeat(s, repeat);
  value = s.empty() ? -1 : std::stoi(s);
}

Month::Month(std::string s) {
  parse_repeat(s, repeat);

  if (s.empty()) {
    value = -1;
    return;
  }

  if (s.length() >= 3) {
    std::transform(s.begin(), s.end(), s.begin(),
                   [](char c) { return std::tolower(c); });
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
    throw std::invalid_argument{"Month must be between 1 and 12"};
  }
}

auto Month::long_name() const -> std::string {
  // assert value > 0
  return std::string{long_names[value - 1]};
}

auto Month::short_name() const -> std::string {
  // assert value > 0
  return std::string{long_names[value - 1].substr(0, 3)};
}

Day::Day(std::string s) {
  parse_repeat(s, repeat);

  if (s.empty()) {
    value = -1;
    return;
  }

  if (s.length() >= 3) {
    std::transform(s.begin(), s.end(), s.begin(),
                   [](char c) { return std::tolower(c); });
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
  // TODO: check in date based on year/month for better accuracy
  if (value < 1 || value > 31) {
    throw std::invalid_argument{"Day must be between 1 and 31"};
  }
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
  auto tm = std::localtime(&t);
  year = {tm->tm_year + 1900};
  month = {tm->tm_mon + 1};
  day = {tm->tm_mday};
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
}
