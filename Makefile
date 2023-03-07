PREFIX = /usr/local
#MANDIR = ${PREFIX}/share/man

all:
	@printf "Run 'sudo make install' to install quand.\n"

install:
	mkdir -p ${DESTDIR}${PREFIX}/bin
	cp -f quand ${DESTDIR}${PREFIX}/bin
	chmod 755 ${DESTDIR}${PREFIX}/bin/quand
	@#mkdir -p ${DESTDIR}${MANDIR}/man1
	@#cp -f quand.1 ${DESTDIR}${MANDIR}/man1
	@#chmod 644 ${DESTDIR}${MANDIR}/man1/quand.1

uninstall:
	rm -rf ${DESTDIR}${PREFIX}/bin/quand
		@#${DESTDIR}${MANDIR}/man1/quand.1

.PHONY: all install uninstall
