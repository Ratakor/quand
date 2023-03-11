<h1 align="center">Quand</h1>

## Description
Quand is a simple calendar written in POSIX sh that take some inspiration from [when](http://www.lightandmatter.com/when/when.html), it's easily hackable and blazingly fast*!

(*with small past/future)

## Installation
```
$ git clone https://git.ratakor.com/quand.git
$ cd quand
# make install
```

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

## Configuration
Quand can be configured with a config file (~/.config/quand/config) or by directly modifying the source code. If you do the latter, be sure to comment `getsettings` in main() as it will increase performance a little.

Quand follow the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html) and uses $EDITOR and $LANG to specify the default editor and language.

Default configuration:
```
language = en_US.UTF-8
calendar = /home/username/.config/quand/calendar
editor = vi
header = 0
past = 0
future = 1
yesterday = yesterday
today = today
tomorrow = tomorrow
mondayfirst = 0
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
