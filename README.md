# pas2lua

**pas2lua** is a hackish Pascal to Lua translator. I made it just to translate the source code of MADrigals's Game & Watch [simulators](http://www.madrigaldesign.it/sim/), which are written in Delphi.

**pas2lua** adds a number of things by itself to the output code to reduce the amount of hand-editing required to have an working simulator.

Even the Makefile is hackish and won't do the right thing on Linux. You have been warned.

## Usage

pas2lua inputfile.pas > outputfile.lua