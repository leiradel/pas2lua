# pas2lua

**pas2lua** is a hackish Pascal to Lua translator. I made it just to translate the source code of MADrigals's Game & Watch [simulators](http://www.madrigaldesign.it/sim/), which are written in Delphi.

**pas2lua** doesn't pretend to be a general Pascal to Lua translator, just enough to ease the porting of the games.

Even the Makefile is hackish and won't do the right thing on Linux. You have been warned.

## Usage

`pas2lua pas2lua <input.pas> <output.lua> <datadir>`

`<datadir>` is the directory where data extracted from .dfm files will be created.
