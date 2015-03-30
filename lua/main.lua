local entrySearcher = function( modname )
  local contents, entryName = loadEntry( modname )
  
  if contents then
    local main, err = load( contents, entryName )
    
    if main then
      return main, entryName
    end
    
    return nil, err
  end
  
  return nil, entryName -- the error returned by loadEntry
end

--table.insert( package.searchers, 2, entrySearcher )

local function errorout( ... )
  local args = { ... }
  local format = args[ 1 ]
  table.remove( args, 1 )
  io.stderr:write( string.format( format, args ), '\n' )
  os.exit( 1 )
end

return function( args )
  if #args ~= 3 then
    io.write( 'Usage: pas2lua <input.pas> <output.lua> <datadir>\n' )
    return 0
  end
  
  local file, err = io.open( args[ 1 ] )
  
  if not file then
    errorout( 'Error reading from %s', args[ 1 ] )
  end
  
  local source = file:read( '*a' )
  file:close()
  
  if not source then
    errorout( 'Could not read from %s', args[ 1 ] )
  end
  
  local parser = Parser( source, args[ 1 ], args[ 2 ], args[ 3 ] )
  parser:parse()
  
  os.exit( 0 )
end
