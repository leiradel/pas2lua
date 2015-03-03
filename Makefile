CC=gcc
CPP=g++

CFLAGS+=-O2 -I/c/Users/aleirade/dropbox/MinGW_home/lua-5.2.0/src
LFLAGS+=/c/Users/aleirade/dropbox/MinGW_home/lua-5.2.0/src/liblua.a

.c.o:
	$(CC) $(CFLAGS) -o $@ -c $<

.cpp.o:
	$(CPP) $(CFLAGS) -o $@ -c $<

all: pas2lua.exe

pas2lua.exe: lexer.o main.o
	$(CPP) -o $@ $+ $(LFLAGS)

main.o: main_lua.h

main_lua.h: main.lua file2c.exe
	file2c.exe $< main_lua > $@

file2c.exe: file2c.o
	$(CPP) -o $@ $+ $(LFLAGS)

clean:
	rm -f pas2lua.exe lexer.o main.o main_lua.h file2c.exe file2c.o
