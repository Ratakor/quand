#pragma once

#include <string>

class DateValue {
public:
  int value;
  bool repeat;

  DateValue() = default;
  DateValue(int value, bool repeat = false) : value(value), repeat(repeat) {}
  auto to_string(int width = 2) const -> std::string;
  auto operator==(const DateValue &other) const -> bool;

protected:
  static auto parse_repeat(std::string &s, bool &repeat) -> void;
};

class Year : public DateValue {
public:
  using DateValue::DateValue;

  Year(std::string s);
  auto to_string() const -> std::string { return DateValue::to_string(4); }
};

class Month : public DateValue {
private:
  constexpr static std::string_view long_names[] = {
      "January", "February", "March",     "April",   "May",      "June",
      "July",    "August",   "September", "October", "November", "December",
  };

public:
  using DateValue::DateValue;

  Month(std::string s);
  auto long_name() const -> std::string;
  auto short_name() const -> std::string;
};

class Day : public DateValue {
private:
  // start with sunday?
  constexpr static std::string_view long_names[] = {
      "Monday", "Tuesday",  "Wednesday", "Thursday",
      "Friday", "Saturday", "Sunday",
  };

public:
  using DateValue::DateValue;

  Day(std::string s);
  auto long_name() const -> std::string;
  auto short_name() const -> std::string;
};

class Date {
public:
  Year year;
  Month month;
  Day day;

  Date() = default;
  Date(Year year, Month month, Day day) : year(year), month(month), day(day) {}
  Date(time_t t);
  Date(std::string s);
  auto to_string() const -> std::string;
  auto operator==(const Date &other) const -> bool;
};

class Line {
public:
  Date date;
  std::string text;

  Line(std::string s);
};
