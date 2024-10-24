QUAND(1)

# NAME

*quand* - simple calendar

# SYNOPSIS

*quand* [OPTIONS]

# DESCRIPTION

*quand* is a simple calendar for the command line.

# OPTIONS

e, edit
	Edit the calendar file.

c, cal [_n_]
	Print a calendar with 1 or _n_ months.

*-c*, *--calendar* _path_
	Temporarily change the calendar file used.

*-d*, *--date* _date_
	Print events for a specific date of format: YYYY/MM/DD.

*-p*, *--past* _n_
	Temporarily change past to _n_.

*-f*, *--future* _n_
	Temporarily change future to _n_.

*-h*, *--help*
	Display an help message to stderr and exit.

*-v*, *--version*
	Display version information to stderr and exit.

# CONFIGURATION
$XDG_CONFIG_HOME/quand/config - Default config file. If XDG_CONFIG_HOME is not
set, $HOME/.config/ is used.

Default configuration:
```
language = en_US.UTF-8
calendar = /home/username/.local/share/quand/calendar
editor = vi
header = true
past = -1
future = 14
yesterday = "yesterday"
today = "\x1b[1mtoday"
tomorrow = "tomorrow"
special = "special"
mondayfirst = false
```

# EXAMPLE
$XDG_DATA_HOME/quand/calendar - Default calendar file. If XDG_DATA_HOME is not
set, $HOME/.local/share is used.

Example of calendar file:
```
# Don't forget the 0 behind month or day
2023 04 28, 07:30 -> 09:30 English
2023 03 12, Dentist

# For events that happen once a week:
# The name of each day depends on your locale
Mon, don't forget to update with emerge -uDN @world
Fri, it's friday!

# Use a star for events that happen once a year:
* 08 10, Mum's anniversary
* 07 14, Bastille Day

# Use 2 stars for events that happen once a month:
* * 01, Happy New Month!

# Use 3 stars to always show an event:
* * * Good Morning :)
* * * 2023 03 31, URGENT don't forget your meeting
```
