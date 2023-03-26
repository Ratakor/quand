.POSIX:

#VERSION = 1.0.2
PREFIX = /usr/local
#MANPREFIX = ${PREFIX}/share/man

all:
	@printf "Run 'sudo make install' to install quand.\n"

install:
	mkdir -p ${DESTDIR}${PREFIX}/bin
	cp -f quand ${DESTDIR}${PREFIX}/bin
	chmod 755 ${DESTDIR}${PREFIX}/bin/quand
	@#mkdir -p ${DESTDIR}${MANPREFIX}/man1
	@#sed "s/VERSION/${VERSION}/g" < quand.1 > ${DESTDIR}${MANPREFIX}/man1/quand.1
	@#chmod 644 ${DESTDIR}${MANPREFIX}/man1/quand.1

uninstall:
	rm -f ${DESTDIR}${PREFIX}/bin/quand
		@#${DESTDIR}${MANPREFIX}/man1/quand.1

.PHONY: all install uninstall
