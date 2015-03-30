local function dump( v, i )
  i = i or 0
  local j = string.rep( '  ', i )
  
  if type( v ) == 'table' then
    io.write( j, '{\n' )
    for k, v in pairs( v ) do
      io.write( j, '  ', tostring( k ), ' = ' )
      dump( v, i + 1 )
    end
    io.write( j, '}\n' )
  elseif type( v ) == 'number' then
    io.write( j, v, '\n' )
  elseif type( v ) == 'string' then
    io.write( j, '"', v, '"\n' )
  end
end

local M = class.new()

function M:new( source, path, datadir )
  self:tokenize( source, path )
  self.path = path
  self.datadir = datadir
  self.pos = 1
  self.pascal = {}
  self.cid = {}
end

function M:tokenize( source, path )
  local reserved = {
    -- symbols
    '(',
    ')',
    '*',
    '+',
    ',',
    '-',
    '.',
    '..',
    '/',
    ':',
    ':=',
    ';',
    '<',
    '<=',
    '<>',
    '=',
    '>',
    '>=',
    '[',
    ']',
    -- keywords
    'and',
    'array',
    'begin',
    'case',
    'chr',
    'class',
    'const',
    'dec',
    'decodetime',
    'div',
    'do',
    'downto',
    'else',
    'end',
    'false',
    'for',
    'function',
    'if',
    'implementation',
    'in',
    'inc',
    'initialization',
    'interface',
    'mod',
    'nil',
    'not',
    'object',
    'odd',
    'of',
    'or',
    'ord',
    'power',
    'procedure',
    'repeat',
    'then',
    'to',
    'true',
    'trunc',
    'type',
    'unit',
    'until',
    'uses',
    'var',
    'while',
    -- builtin types
    'boolean',
    'integer',
    'word',
  }
  
  local tokens = {}
  
  for _, token in ipairs( reserved ) do
    tokens[ token ] = lexer.token
  end
  
  tokens[ '//' ] = lexer.lineCommentStart
  tokens[ '{' ] = lexer.blockCommentStart
  tokens[ '}' ] = lexer.blockCommentEnd

  local lex = lexer.new( source, path, tokens, "'", false, false )
  
  tokens = {}
  local i = 1
  
  repeat
    local la, err = lex:next()
    
    if not la then
      errorout( err )
    end
    
    --if la.token ~= 'comment' then
      tokens[ i ] = la
      i = i + 1
    --end
  until la.token == 'eof'
  
  self.tokens = tokens
end

function M:error( ... )
  local args = { ... }
  local format = args[ 1 ]
  table.remove( args, 1 )
  io.stderr:write( string.format( '%s:%d: %s\n', self.tokens[ self.pos ].source, self.tokens[ self.pos ].line, string.format( format, unpack( args ) ) ) )
  os.exit( 1 )
end

function M:out( token, lexeme )
  local la = self.tokens[ self.pos ]
  local nla = {}
  
  nla.source = la.source
  nla.line = la.line
  nla.pos = la.pos
  nla.lexeme = lexeme or la.lexeme
  nla.token = token or la.token
  
  self.pascal[ #self.pascal + 1 ] = nla
end

function M:outId()
  for i = 1, #self.cid do
    self:out( 'id', self.cid[ i ] )
    self:out( '.', '.' )
  end
end

function M:token( offset )
  offset = offset or 1
  return self.tokens[ self.pos + offset - 1 ].token
end

function M:lexeme( offset )
  offset = offset or 1
  return self.tokens[ self.pos + offset - 1 ].lexeme:lower()
end

function M:match( token )
  if false then
    local info = debug.getinfo( 2, 'nl' )
    io.write( '--[[', info.currentline or 'noline', ' ', info.name or 'noname', ' ', token or 'notoken', ' |', self:lexeme(), '|', self:lexeme( 2 ), '|', self:lexeme( 3 ), '| ' )
    for i = 3, 5 do
      local info = debug.getinfo( i, 'nl' )
      io.write( i == 2 and '' or ' | ', info.currentline or 'noline', ' ', info.name or 'noname' )
    end
    io.write( ']]\n' )
  end
  
  if token == nil or self.tokens[ self.pos ].token == token then
    self.pos = self.pos + 1
    return self.tokens[ self.pos - 1 ].lexeme
  end
  
  self:error( 'Expected: %s, found %s', token, self.tokens[ self.pos ].token )
end

function M:pushId( id )
  self.cid[ #self.cid + 1 ] = id
end

function M:popId()
  table.remove( self.cid )
end

function M:parse()
  local instance = self:lexeme( 2 )
  local type = self:lexeme( 4 )
  self:out( 'procedure', 'procedure' )
  self:out( 'id', type )
  self:out( '.', '.' )
  self:out( 'id', '__initdfm' )
  self:out( ';', ';' )
  self:out( 'begin', 'begin' )
  
  self:parseObject( true )
  
  self:out( 'end', 'end' )
  self:out( ';', ';' )
  
  local implementation = self.pascal
  self.pascal = {}
  
  self:out( 'id', instance )
  self:out( '.', '.' )
  self:out( 'id', '__initdfm' )
  self:out( ';', ';' )
  
  local initialization = self.pascal
  self.pascal = {}
  
  return { implementation = implementation, initialization = initialization }
end

function M:parseObject( dontpush )
  self:match( 'object' )
  
  if not dontpush then
    self:pushId( self:lexeme() )
  end
  
  self:match( 'id' )
  self:match( ':' )
  self:match( 'id' )
  
  while true do
    if self:token() == 'object' then
      self:parseObject()
    elseif self:token() == 'end' then
      break
    else
      self:outId()
      self:out()
      self:match( 'id' )
      
      while self:token() == '.' do
        self:out()
        self:match()
        self:out()
        self:match( 'id' )
      end
      
      self:out( ':=', ':=' )
      self:match( '=' )
      self:parseExpr()
      self:out( ';', ';' )
    end
  end
  
  self:match( 'end' )
  
  if not dontpush then
    self:popId()
  end
end

function M:parseExpr()
  local token = self:token()
  
  if token == 'integer' or token == 'fp' or token == 'true' or token == 'false' or token == 'string' then
    self:out()
    self:match()
    return
  elseif token == 'comment' then
    local value = self.tokens[ self.pos ].lexeme:sub( 2, -2 ):gsub( '%s+', '' )
    local data = value:gsub( '%x%x', function( hex ) return string.char( tonumber( hex, 16 ) ) end )
    local name = table.concat( self.cid, '_' ) .. '.bin'
    
    local file, err = io.open( self.datadir .. '/' .. name, 'wb' )
    
    if not file then
      self:error( 'Error opening data file: %s', err )
    end
    
    file:write( data )
    file:close()
    
    self:out( 'id', 'loadbin' )
    self:out( '(', '(' )
    self:out( 'string', name )
    self:out( ')', ')' )
    
    self:match()
    return
  elseif token == '-' then
    self:out()
    self:match()
    self:parseExpr()
    return
  elseif token == '[' then
    self:out()
    self:match()
    
    if self:token() ~= ']' then
      self:parseExpr()
    
      while self:token() == ',' do
        self:out()
        self:match()
        self:parseExpr()
      end
    end
    
    self:out()
    self:match( ']' )
    return
  elseif token == 'id' then
    self:out()
    self:match()
    
    while self:token() == '.' do
      self:out()
      self:match()
      self:out()
      self:match( 'id' )
    end
    
    return
  end
  
  self:error( '%s is invalid in expressions', self:lexeme() )
end

return M
