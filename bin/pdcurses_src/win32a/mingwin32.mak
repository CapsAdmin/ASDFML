# GNU MAKE Makefile for PDCurses library - WIN32 MinGW GCC
#
# Usage: make -f [path\]mingwin32.mak [DEBUG=Y] [DLL=Y] [WIDE=Y] [UTF8=Y] [tgt]
#
# where tgt can be any of:
# [all|demos|pdcurses.a|testcurs.exe...]

O = o

ifndef PDCURSES_SRCDIR
	PDCURSES_SRCDIR = ..
endif

include $(PDCURSES_SRCDIR)/version.mif
include $(PDCURSES_SRCDIR)/libobjs.mif

# When using this in Windows,  the commands should be 'type' and 'copy';
# in Linux, 'cat' and 'cp'.  And in Windows,  the slash must be a backslash
# in order to avoid having it treated as a flag.  I think the following will
# make sure the proper lines are selected, but lack a Linux/MinGW platform.

ifdef _linux
	CAT = cat
	CP = -cp
	BASEDEF      = $(PDCURSES_SRCDIR)/exp-base.def
	WIDEDEF      = $(PDCURSES_SRCDIR)/exp-wide.def
else
	CAT = type
	CP  = -copy
	BASEDEF      = $(PDCURSES_SRCDIR)\exp-base.def
	WIDEDEF      = $(PDCURSES_SRCDIR)\exp-wide.def
endif

osdir      = $(PDCURSES_SRCDIR)/win32a

PDCURSES_WIN_H   = $(osdir)/pdcwin.h

CC      = gcc

ifeq ($(DEBUG),Y)
	CFLAGS  = -g -Wall -DPDCDEBUG
	LDFLAGS = -g
else
	CFLAGS  = -O4 -Wall
	LDFLAGS =
endif

CFLAGS += -I$(PDCURSES_SRCDIR)


DEFDEPS      = $(BASEDEF)

ifeq ($(WIDE),Y)
	CFLAGS += -DPDC_WIDE
	DEFDEPS += $(WIDEDEF)
	DEFFILE      = pdcursew.def
else
	DEFFILE      = pdcurses.def
endif

ifeq ($(UTF8),Y)
	CFLAGS += -DPDC_FORCE_UTF8
endif

LINK      = gcc

ifeq ($(DLL),Y)
	CFLAGS += -DPDC_DLL_BUILD
	LIBEXE = gcc $(DEFFILE)
	LIBFLAGS = -Wl,--out-implib,pdcurses.a -shared -o
	LIBCURSES = pdcurses.dll
	LIBDEPS = $(LIBOBJS) $(PDCOBJS) $(DEFFILE)
	LIBSADDED = -lgdi32 -lcomdlg32
	EXELIBS =
	CLEAN = $(LIBCURSES) *.a $(DEFFILE)
else
	LIBEXE = ar
	LIBFLAGS = rcv
	LIBCURSES = pdcurses.a
	LIBDEPS = $(LIBOBJS) $(PDCOBJS)
	LIBSADDED =
	EXELIBS = -lgdi32 -lcomdlg32
	CLEAN = *.a
endif

.PHONY: all libs clean demos dist

all:   libs demos

libs:   $(LIBCURSES)

clean:
	-del *.o
	-del *.exe
	-del $(CLEAN)

demos:   $(DEMOS)
	strip *.exe

$(DEFFILE): $(DEFDEPS)
	echo LIBRARY pdcurses > $@
	echo EXPORTS >> $@
	$(CAT) $(BASEDEF) >> $@
ifeq ($(WIDE),Y)
	$(CAT) $(WIDEDEF) >> $@
endif

$(LIBCURSES) : $(LIBDEPS)
	$(LIBEXE) $(LIBFLAGS) $@ $? $(LIBSADDED)
	$(CP) pdcurses.a panel.a

$(LIBOBJS) $(PDCOBJS) : $(PDCURSES_HEADERS)
$(PDCOBJS) : $(PDCURSES_WIN_H)
$(DEMOS) : $(PDCURSES_CURSES_H) $(LIBCURSES)
panel.o : $(PANEL_HEADER)
terminfo.o: $(TERM_HEADER)

$(LIBOBJS) : %.o: $(srcdir)/%.c
	$(CC) -c $(CFLAGS) $<

$(PDCOBJS) : %.o: $(osdir)/%.c
	$(CC) -c $(CFLAGS) $<

firework.exe newdemo.exe rain.exe testcurs.exe worm.exe xmas.exe \
newtest.exe ptest.exe: %.exe: $(demodir)/%.c
	$(CC) $(CFLAGS) -o$@ $< $(LIBCURSES) $(EXELIBS)

tuidemo.exe: tuidemo.o tui.o
	$(LINK) $(LDFLAGS) -o$@ tuidemo.o tui.o $(LIBCURSES) $(EXELIBS)

tui.o: $(demodir)/tui.c $(demodir)/tui.h $(PDCURSES_CURSES_H)
	$(CC) -c $(CFLAGS) -I$(demodir) -o$@ $<

tuidemo.o: $(demodir)/tuidemo.c $(PDCURSES_CURSES_H)
	$(CC) -c $(CFLAGS) -I$(demodir) -o$@ $<

PLATFORM1 = MinGW Win32
PLATFORM2 = MinGW for Win32
ARCNAME = pdc$(VER)_ming_w32

include $(PDCURSES_SRCDIR)/makedist.mif
