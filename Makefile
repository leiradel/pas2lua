.SUFFIXES:.lua

CC=gcc
CPP=g++

CFLAGS+=-O0 -g -I/c/Users/aleirade/Desktop/MinGW_home/lua-5.2.0/src
LFLAGS+=-g -L/c/Users/aleirade/Desktop/MinGW_home/lua-5.2.0/src

.c.o:
	$(CC) $(CFLAGS) -o $@ -c $<

.lua.h:
	xxd -i $< | sed "s/unsigned/const/g" > $@

all: pas2lua.exe

pas2lua.exe: lexer.o main.o
	$(CC) $(LFLAGS) -o $@ $+ -llua

main.o: lua/class.h lua/parser.h lua/dfm2pas.h lua/main.h units/classes.h units/controls.h units/dialogs.h units/extctrls.h units/fmod.h units/fmodtypes.h units/forms.h units/graphics.h units/jpeg.h units/math.h units/messages.h units/registry.h units/stdctrls.h units/system.h units/sysutils.h units/windows.h

clean:
	rm -f pas2lua.exe lexer.o main.o lua/class.h lua/parser.h lua/dfm2pas.h lua/main.h units/classes.h units/controls.h units/dialogs.h units/extctrls.h units/fmod.h units/fmodtypes.h units/forms.h units/graphics.h units/jpeg.h units/math.h units/messages.h units/registry.h units/stdctrls.h units/system.h units/sysutils.h units/windows.h
