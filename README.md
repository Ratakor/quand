<h1 align="center">Quand</h1>

## Description
Quand is a simple calendar written in POSIX sh that take some inspiration from [when](http://www.lightandmatter.com/when/when.html), it's easily hackable and blazingly fast*! (*with small past/future)
<br/>
Quand default configuration uses environment variables (LANG, EDITOR and XDG_CONFIG_HOME), but it can be configured with a config file (in $XDG_CONFIG_HOME/quand/config otherwise it won't be detected, if you don't know what $XDG_CONFIG_HOME is have a look at the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)). It is also possible and easy to directly modify 'quand' because the config is at the top of the file.

## Example of calendar file:
Any line that does not respect the 'yyyy mm dd' format will simply be ignored.
```
# Don't forget the 0 behind month or day
2023 04 28, 07:30 -> 09:30 English
2023 03 12, Dentist

# use a start for events that happen once a year
* 08 10, Mum's anniversary
* 07 14, Bastille Day
```

## Exhaustive config file
This is just an example, not the default config.
<br/>
The spaces between each '=' are important.
<br/>
There is no need to specify everthing.
<br/>
It is necessary to put absolute path of the calendar in the config file for it to work.
```
language = fr_FR.UTF-8
calendar = /home/foo/.config/quand/calendar
editor = nvim
header = 1
past = 2
future = 5
yesterday = hier
today = auhourd'hui
tomorrow = demain
```

## Options
- -v : check the version
- -h : get help
- e : edit calendar
- c : get calendar

## TODO
- add an ICS parser or handle ICS files
- add help command
- add a man page
