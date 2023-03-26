<h1 align="center">Quand</h1>

## Description
Quand is a simple calendar written in POSIX sh that take some inspiration from [when](http://www.lightandmatter.com/when/when.html), it's easily hackable and blazingly fast!

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
Quand can be configured with a config file (~/.config/quand/config).

Quand follow the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html) and uses $EDITOR and $LANG to specify the default editor and language.

Default configuration:
```
language=en_US.UTF-8
calendar=/home/username/.local/share/quand/calendar
editor=vi
header=1
past=-1
future=14
yesterday="yesterday  "
# \033[1m is for bold, it's also possible to add color with for example \033[34m
today="\033[1mtoday      "
tomorrow="tomorrow   "
mondayfirst=0
```

## TODO
- add a ICS file converter or handle ICS files
- add a man page
- add a PKGBUILD
