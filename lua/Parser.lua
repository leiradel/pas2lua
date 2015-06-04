local M = class.new()

function M:new( source, path, outpath, datadir )
  self.path = path
  self.outpath = outpath
  self.datadir = datadir
  self.pos = 1
  self.spaces = 0
  self.units = {}
  self.filters = {}
  self.tokens = self:tokenize( source, path )
  
  local outfile, err = io.open( outpath, 'w' )
  
  if not outfile then
    self:error( 'Error opening output file: %s', err )
  end
  
  self.outfile = outfile
  
  self.builtin = {
    boolean = 'false',
    integer = '0',
    word = '0',
    tdatetime = '0'
  }
  
  self.supertypes = {
    boolean = 'boolean',
    integer = 'integer',
    word = 'integer',
    tdatetime = 'integer'
  }
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
    'abs',
    'and',
    'array',
    'begin',
    'case',
    'chr',
    'class',
    'const',
    'dec',
    'decodedate',
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
    'odd',
    'of',
    'or',
    'ord',
    'power',
    'procedure',
    'record',
    'repeat',
    'self',
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
    'tdatetime'
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
  local dfms = {}
  
  repeat
    local la, err = lex:next()
    
    if not la then
      errorout( err )
    end
    
    if la.token ~= 'comment' then
      if la.token == 'initialization' then
        for _, dfm in ipairs( dfms ) do
          for _, la in ipairs( dfm.implementation ) do
            tokens[ i ] = la
            i = i + 1
          end
        end
        
        tokens[ i ] = la
        i = i + 1
        
        for _, dfm in ipairs( dfms ) do
          for _, la in ipairs( dfm.initialization ) do
            tokens[ i ] = la
            i = i + 1
          end
        end
      else
        tokens[ i ] = la
        i = i + 1
      end
    elseif la.lexeme:lower() == '{$r *.dfm}' then
      tokens[ i ] = la
      i = i + 1
      
      local dfm = path:gsub( '(.*)%.pas', '%1.dfm' )
      
      local file, err = io.open( dfm )
      
      if not file then
        self:error( '%s not found', dfm )
      end
      
      local d2p = dfm2pas( file:read( '*a' ), dfm, self.datadir )
      file:close()
      local pas = d2p:parse()
      dfms[ #dfms + 1 ] =  pas
    end
  until la.token == 'eof'
  
  return tokens
end

function M:error( ... )
  local args = { ... }
  local format = args[ 1 ]
  table.remove( args, 1 )
  --io.stderr:write( string.format( '%s:%d: %s\n', self.tokens[ self.pos ].source, self.tokens[ self.pos ].line, string.format( format, unpack( args ) ) ) )
  --os.exit( 1 )
  error( string.format( '%s:%d: %s\n', self.tokens[ self.pos ].source, self.tokens[ self.pos ].line, string.format( format, unpack( args ) ) ) )
end

function M:pushFilter( pattern, sub )
  self.filters[ #self.filters + 1 ] = { pattern = pattern, sub = sub }
end

function M:popFilter()
  self.filters[ #self.filters ] = nil
end

function M:format( format, args )
  local str = string.format( format, unpack( args ) )
  
  for i = #self.filters, 1, -1 do
    str = str:gsub( self.filters[ i ].pattern, self.filters[ i ].sub )
  end
  
  return str
end

function M:out( ... )
  local args = { ... }
  local format = args[ 1 ]
  table.remove( args, 1 )
  self.outfile:write( self:format( format, args ) )
end

function M:outln( ... )
  local args = { ... }
  local format = args[ 1 ]
  
  if format then
    table.remove( args, 1 )
    self.outfile:write( string.rep( ' ', self.spaces * 2 ), self:format( format, args ), '\n' )
  else
    self.outfile:write( '\n' )
  end
end

function M:outindent( ... )
  local args = { ... }
  local format = args[ 1 ]
  
  if format then
    table.remove( args, 1 )
    self.outfile:write( string.rep( ' ', self.spaces * 2 ), self:format( format, args ) )
  end
end

function M:indent()
  self.spaces = self.spaces + 1
end

function M:unindent()
  self.spaces = self.spaces - 1
end

function M:skipComments()
  while self.tokens[ self.pos ].token == 'comment' do
    local lexeme = self.tokens[ self.pos ].lexeme
    
    if lexeme:sub( 1, 2 ) == '//' then
      self:out( '--%s\n', lexeme:sub( 3, -1 ) )
    else
      self:outln( '--[[ %s ]]', lexeme:sub( 2, -2 ) )
    end
    
    self.pos = self.pos + 1
  end
end

function M:token( offset )
  offset = offset or 1
  self:skipComments()
  return self.tokens[ self.pos + offset - 1 ].token
end

function M:lexeme( offset )
  offset = offset or 1
  self:skipComments()
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
  
  self:skipComments()
  
  if token == nil or self.tokens[ self.pos ].token == token then
    self.pos = self.pos + 1
    return self.tokens[ self.pos - 1 ].lexeme
  end
  
  self:error( 'Expected: %s, found %s', token, self.tokens[ self.pos ].token )
end

-- scopes
-- [ '@' ] = previous scope
-- [ '#' ] = how to access identifiers declared in this scope
-- [ '!' ] = how to declare identifiers belonging to this scope

function M:newScope( declare, access )
  local scope = { [ '@' ] = self.scope, [ '!' ] = declare, [ '#' ] = access }
  self.scope = scope
end

function M:pushScope( scope )
  scope[ '@' ] = self.scope
  self.scope = scope
end

function M:popScope()
  local scope = self.scope[ '@' ]
  self.scope = scope
  return scope
end

function M:declare( id, def )
  if self.scope[ id ] then
    self:error( 'Duplicate identifier: %s', id )
  end
  
  self.scope[ id ] = def
end

function M:declared( id )
  local scope = self.scope
  
  while scope do
    if scope[ id ] then
      return scope[ '#' ], scope[ id ]
    end
    
    scope = scope[ '@' ]
  end
  
  return false
end

function M:declaration()
  return self.scope[ '!' ]
end

function M:access()
  return self.scope[ '#' ]
end

function M:parse()
  self:outln( 'local class = system.loadunit \'class\'' )
  self:outln()
  
  self:newScope( '', 'system.' )
  local unit = loadunit( 'system' )
  
  for id, def in pairs( unit ) do
    self:declare( id, def )
  end
  
  self:parseUnit()
end

function M:parseUnit()
  self:match( 'unit' )
  self:match( 'id' )
  self:match( ';' )
  
  self:newScope( 'unit.', 'unit.' )
  self:outln( 'local unit = {}' )
  self:outln()
  
  self:parseInterface()
  self:parseImplementation()
  self:parseInitialization()
  
  self:match( 'eof' )
  self:outln( 'return unit' )
end

function M:parseInterface()
  self:match( 'interface' )
  self:newScope( 'unit.', 'unit.' )
  
  while true do
    local what = self:token()
    
    if what == 'uses' then
      self:parseUsesSection()
    elseif what == 'type' then
      self:parseTypeSection()
    elseif what == 'const' then
      self:parseConstSection( true )
    elseif what == 'var' then
      self:parseVarSection( true )
    else
      break
    end
  end
end

function M:parseUsesSection()
  self:match( 'uses' )
  
  local scopes = {}
  
  repeat
    local scope = self:popScope()
    scopes[ #scopes + 1 ] = scope
  until scope == nil
  
  while true do
    local name = self:lexeme()
    self:match( 'id' )
    
    self:outln( 'local %s = system.loadunit \'%s\'', name, name )
    
    self:newScope( '', name .. '.' )
    local unit = loadunit( name )
    self.units[ name ] = unit
    
    for id, def in pairs( unit ) do
      self:declare( id, def )
    end
    
    if self:token() ~= ',' then
      break
    end
    
    self:match()
  end
  
  self:match( ';' )
  self:outln()
  
  for i = #scopes, 1, -1 do
    self:pushScope( scopes[ i ] )
  end
end

function M:parseTypeSection()
  self:match( 'type' )
  
  while true do
    local id = self:lexeme()
    self:match( 'id' );
    self:match( '=' )
    
    local what = self:token()
    
    if what == 'class' then
      local def = self:parseClass( id )
      self:declare( id, def )
    end
    
    self:match( ';' )
    
    if self:token() ~= 'id' then
      break
    end
  end
end

function M:consolidate( def )
  if def.consolidated then
    return
  end
  
  def.consolidated = true
  
  if not def.fields then
    def.fields = {}
  end
  
  local super = def.super
  
  while super do
    for id2, def2 in pairs( super.fields ) do
      def.fields[ id2 ] = def2
    end
    
    super = super.super
  end
  
  for name, unit in pairs( self.units ) do
    if unit[ def.type ] then
      for id2, def2 in pairs( unit[ def.type ].fields ) do
        def.fields[ id2 ] = def2
      end
      
      break
    end
  end
  
  for _, def2 in pairs( def.fields ) do
    self:consolidate( def2 )
  end
end

function M:parseClass( id )
  self:match( 'class' )
  local def = { type = id, fields = { __initdfm = { type = 'procedure' } } }
  local super
  
  self:outindent( '%s%s = class.new', self:declaration(), id )

  if self:token() == '(' then
    self:match()
    super = self:lexeme()
    def.super = self:parseType()
    self:match( ')' )
    
    self:out( '( %s%s )', self:declared( super ), super )
    self:consolidate( def )
  else
    self:out( '()' )
  end
  
  self:outln()
  self:outln()
  self:outln( '%s%s.new = function( self )', self:access(), id )
  self:indent()
  
  if super then
    self:outln( '%s%s.new( self )', self:declared( super ), super )
  end
  
  while self:token() ~= 'end' do
    local ids, def2 = self:parseDecl()
    self:consolidate( def2 )
    
    for _, prop in ipairs( ids ) do
      def.fields[ prop ] = def2
      
      if def2.type == 'procedure' or def2.type == 'function' then
        self:outln( '-- self.%s -- %s', prop, def2.type )
      else
        local value = self.builtin[ def2.type ]
        
        if value then
          self:outln( 'self.%s = %s -- %s', prop, value, def2.type )
        else
          self:outln( 'self.%s = %s%s()', prop, self:declared( def2.type ), def2.type )
        end
      end
    end
  end
  
  self:unindent()
  self:outln( 'end' )
  self:outln()
  
  self:match( 'end' )
  return def
end

function M:parseIdList()
  local list = {}
  
  list[ #list + 1 ] = self:lexeme()
  self:match( 'id' )
  
  while self:token() == ',' do
    self:match()
    list[ #list + 1 ] = self:lexeme()
    self:match( 'id' )
  end
  
  return list
end

function M:parseDecl()
  local what = self:token()
  
  if what == 'id' then
    local ids = self:parseIdList()
    self:match( ':' )
    local def = self:parseType()
    self:match( ';' )
    
    return ids, def
  elseif what == 'procedure' then
    return self:parseProcedureDecl()
  elseif what == 'function' then
    return self:parseFunctionDecl()
  end
end

function M:parseProcedureDecl()
  self:match( 'procedure' )
  local id = self:lexeme()
  self:match( 'id' )
  
  local params = {}
  
  if self:token() == '(' then
    self:match()
    
    if self:token() == 'var' then
      self:match()
    end
    
    local ids = self:parseIdList()
    self:match( ':' )
    local def = self:parseType()
    
    params[ #params + 1 ] = { ids = ids, def = def }
    
    while self:token() == ';' do
      self:match()
      
      if self:token() == 'var' then
        self:match()
      end
      
      local ids = self:parseIdList()
      self:match( ':' )
      local def = self:parseType()
      
      params[ #params + 1 ] = { ids = ids, def = def }
    end
    
    self:match( ')' )
  end
  
  self:match( ';' )
  return { id }, { type = 'procedure', params = params }
end

function M:parseFunctionDecl()
  self:match( 'function' )
  local id = self:lexeme()
  self:match( 'id' )
  
  local params = {}
  
  if self:token() == '(' then
    self:match()
    
    if self:token() == 'var' then
      self:match()
    end
    
    local ids = self:parseIdList()
    self:match( ':' )
    local def = self:parseType()
    
    params[ #params + 1 ] = { ids = ids, def = def }
    
    while self:token() == ';' do
      self:match()
      
      if self:token() == 'var' then
        self:match()
      end
      
      local ids = self:parseIdList()
      self:match( ':' )
      local def = self:parseType()
      
      params[ #params + 1 ] = { ids = ids, def = def }
    end
    
    self:match( ')' )
  end
  
  self:match( ':' )
  local ret = self:parseType()
  
  self:match( ';' )
  return { id }, { type = 'function', params = params, ret = ret }
end

function M:parseConstSection()
  self:match( 'const' )
  
  while self:token() == 'id' do
    local id = self:lexeme()
    self:match()
    self:match( '=' )
    local value = self:parseExpr()
    self:match( ';' )
    
    self:declare( id, { type = 'const', value = value } )
    self:outln( '%s%s = %s', self:declaration(), id, value )
  end
end

function M:parseVarSection()
  self:match( 'var' )
  
  while self:token() == 'id' do
    local ids = self:parseIdList()
    self:match( ':' )
    local def = self:parseType()
    self:match( ';' )
    
    for _, id in ipairs( ids ) do
      self:declare( id, def )
    
      if def.value then
        self:outln( '%s%s = %s -- %s', self:declaration(), id, def.value, def.type )
      elseif def.type == 'array' then
        self:outln()
        self:outln( '%s%s = {}', self:declaration(), id )
        local vars = { 'i', 'j', 'k', 'l', 'm', 'n' }
        local sub = def
        local k = 0
        
        while sub.type == 'array' do
          k = k + 1
          sub = sub.subtype
        end
        
        sub = def
        
        for i = 1, k - 1 do
          self:outln( 'for %s = %s, %s do', vars[ i ], sub.i, sub.j )
          self:indent()
          self:outindent( '%s%s', self:access(), id )
          
          for j = 1, i do
            self:out( '[ %s ]', vars[ j ] )
          end
          
          self:out( ' = {}' )
          self:outln()
          
          sub = sub.subtype
        end
        
        self:outln( 'for %s = %s, %s do', vars[ k ], sub.i, sub. j )
        self:indent()
        self:outindent( '%s%s', self:access(), id )
        sub = sub.subtype
        
        for j = 1, k do
          self:out( '[ %s ]', vars[ j ] )
        end
        
        self:out( ' = ' )
        
        if sub.value then
          self:out( '%s -- %s', sub.value, sub.type )
        elseif sub.type == 'record' then
          self:out( '{} -- record' )
        else
          self:out( '%s%s()', self:declared( sub.type ), sub.type )
        end
        
        self:outln()
        self:unindent()
        self:outln( 'end' )
        
        for i = 1, k - 1 do
          self:unindent()
          self:outln( 'end' )
        end
        
        self:outln()
      else
        self:outln( '%s%s = %s%s()', self:declaration(), id, self:declared( def.type ), def.type )
      end
    end
  end
end

function M:parseType()
  if self:token() == 'array' then
    self:match()
    local def = { type = 'array' }
    local def2 = def
    
    self:match( '[' )
    
    def.i = self:parseExpr()
    self:match( '..' )
    def.j = self:parseExpr()
    
    while self:token() == ',' do
      self:match()
      def2.subtype = {}
      def2.subtype.type = 'array'
      def2.subtype.i = self:parseExpr()
      self:match( '..' )
      def2.subtype.j = self:parseExpr()
      
      def2 = def2.subtype
    end
    
    self:match( ']' )
    self:match( 'of' )
    def2.subtype = self:parseType()
    return def
  elseif self:token() == 'record' then
    self:match()
    local def = { type = 'record', fields = {} }
    
    while self:token() ~= 'end' do
      local ids, def2 = self:parseDecl()
      self:consolidate( def2 )
      
      for _, prop in ipairs( ids ) do
        def.fields[ prop ] = def2
      end
    end
    
    self:match( 'end' )
    return def
  else
    local lexeme = self:lexeme()
    
    if self.builtin[ lexeme ] then
      self:match()
      return { type = self.supertypes[ lexeme ], value = self.builtin[ lexeme ] }
    elseif self:declared( lexeme ) then
      self:match( 'id' )
      local _, def = self:declared( lexeme )
      return def
    else
      self:error( 'Unknown identifier: %s', lexeme )
    end
  end
end

function M:parseImplementation()
  self:match( 'implementation' )
  self:newScope( 'local ', '' )
  
  while true do
    local what = self:token()
    
    if what == 'uses' then
      self:parseUsesSection()
    elseif what == 'type' then
      self:parseTypeSection()
    elseif what == 'const' then
      self:parseConstSection( true )
    elseif what == 'var' then
      self:parseVarSection( true )
    elseif what == 'procedure' then
      self:parseProcedure()
    elseif what == 'function' then
      self:parseFunction()
    else
      break
    end
  end
end

function M:parseProcedure()
  self:match( 'procedure' )
  local id = self:lexeme()
  self:match( 'id' )
  
  local access = 'local '
  local scopes = 1
  
  if self:token() == '.' then
    self:match()
    
    local def
    access, def = self:declared( id )
    
    self:newScope( '', 'self.' )
    scopes = 2
    
    for id2, def2 in pairs( def.fields ) do
      self:declare( id2, def2 )
    end
      
    id = id .. '.' .. self:lexeme()
    self:match( 'id' )
  end
  
  self:outindent( '%s%s = function( self', access, id )
  self:indent()
  self:newScope( 'local ', '' )
  
  if self:token() == '(' then
    self:match()
    
    if self:token() == 'var' then
      self:match()
    end
    
    local ids = self:parseIdList()
    self:match( ':' )
    local def = self:parseType()
    
    for _, id in ipairs( ids ) do
      self:declare( id, def )
      self:out( ', %s', id )
    end
    
    while self:token() == ';' do
      self:match()
      
      if self:token() == 'var' then
        self:match()
      end
      
      local ids = self:parseIdList()
      self:match( ':' )
      local def = self:parseType()
      
      for _, id in ipairs( ids ) do
        self:declare( id, def )
        self:out( ', %s', id )
      end
    end
    
    self:match( ')' )
  end
  
  self:out( ' )' )
  self:outln()
  self:match( ';' )
  
  if self:token() == 'var' then
    self:parseVarSection()
  end
  
  self:parseCompoundStmt()
  
  self:match( ';' )
  
  self:unindent()
  self:outln( 'end' )
  self:outln()
  
  for i = 1, scopes do
    self:popScope()
  end
end

function M:parseFunction()
  self:match( 'function' )
  local funcname = self:lexeme()
  local id = funcname
  self:match( 'id' )
  
  local access = 'local '
  local scopes = 1
  
  if self:token() == '.' then
    self:match()
    
    local def
    access, def = self:declared( id )
    
    self:newScope( '', 'self.' )
    scopes = 2
    
    for id2, def2 in pairs( def.fields ) do
      self:declare( id2, def2 )
    end
      
    funcname = self:lexeme()
    id = id .. '.' .. funcname
    self:match( 'id' )
  end
  
  self:outindent( '%s%s = function( self', access, id )
  self:indent()
  self:newScope( 'local ', '' )
  
  if self:token() == '(' then
    self:match()
    
    if self:token() == 'var' then
      self:match()
    end
    
    local ids = self:parseIdList()
    self:match( ':' )
    local def = self:parseType()
    
    for _, id in ipairs( ids ) do
      self:declare( id, def )
      self:out( ', %s', id )
    end
    
    while self:token() == ';' do
      self:match()
      
      if self:token() == 'var' then
        self:match()
      end
      
      local ids = self:parseIdList()
      self:match( ':' )
      local def = self:parseType()
      
      for _, id in ipairs( ids ) do
        self:declare( id, def )
        self:out( ', %s', id )
      end
    end
    
    self:match( ')' )
  end
  
  self:out( ' )' )
  self:outln()
  self:outln( 'local __ret' )
  self:pushFilter( string.format( 'self%%.%s', funcname ), '__ret' )
  
  self:match( ':' )
  self:parseType()
  self:match( ';' )
  
  if self:token() == 'var' then
    self:parseVarSection()
  end
  
  self:parseCompoundStmt()
  
  self:match( ';' )
  
  self:popFilter()
  self:outln( 'return __ret' )
  self:unindent()
  self:outln( 'end' )
  self:outln()
  
  for i = 1, scopes do
    self:popScope()
  end
end

function M:parseCid()
  local id = self:lexeme()
  self:match( 'id' )
  local access, def = self:declared( id )
  
  if not access then
    self:error( 'Unknown identifier: %s', id )
  end
  
  local cid = { access, id }
  
  while true do
    if self:token() == '.' then
      self:match()
      id = self:lexeme()
      self:match( 'id' )
      def = def.fields[ id ]
      
      if not def then
        self:error( 'Unknown field: %s.%s', table.concat( cid ), id )
      end
      
      cid[ #cid + 1 ] = '.'
      cid[ #cid + 1 ] = id
    elseif self:token() == '[' then
      self:match()
      cid[ #cid + 1 ] = '[ '
      cid[ #cid + 1 ] = self:parseExpr()
      cid[ #cid + 1 ] = ' ]'
      def = def.subtype
      
      while self:token() == ',' do
        self:match()
        cid[ #cid + 1 ] = '[ '
        cid[ #cid + 1 ] = self:parseExpr()
        cid[ #cid + 1 ] = ' ]'
        def = def.subtype
      end
      
      self:match( ']' )
    else
      break
    end
  end
  
  return table.concat( cid ), def
end

function M:parseStatement()
  local token = self:token()
  
  if token == 'id' then
    local cid, def = self:parseCid()
    
    if self:token() == '(' or self:token() == ';' then
      self:parseCallStmt( cid )
    else
      self:parseAssignmentStmt( cid )
    end
  elseif token == 'begin' then
    self:parseCompoundStmt()
  elseif token == 'if' then
    self:parseIfStmt()
  elseif token == 'case' then
    self:parseCaseStmt()
  elseif token == 'for' then
    self:parseForStmt()
  elseif token == 'while' then
    self:parseWhileStmt()
  elseif token == 'repeat' then
    self:parseRepeatStmt()
  elseif token == 'inc' then
    self:parseIncStmt()
  elseif token == 'dec' then
    self:parseDecStmt()
  elseif token == 'decodedate' then
    -- must be a statement because passes parameters by reference
    self:parseDecodeDateStmt()
  elseif token == 'decodetime' then
    -- must be a statement because passes parameters by reference
    self:parseDecodeTimeStmt()
  elseif token == 'with' then
    self:parseWithStmt()
  else
    self:error( 'Statement expected' )
  end
  
  if self:token() == ';' then
    self:match()
  end
  
  self:outln()
end

function M:parseCallStmt( cid )
  self:outindent( '%s(', cid )
  
  if self:token() == '(' then
    self:match()
    
    if self:token() ~= ')' then
      local expr = self:parseExpr()
      
      if expr then
        self:out( ' %s', expr )
      end
      
      while self:token() == ',' do
        self:match()
        self:out( ', %s', self:parseExpr() )
      end
      
      self:out( ' ' )
    end
    
    self:match( ')' )
  end
  
  self:out( ')' )
end

function M:parseAssignmentStmt( cid, def )
  self:match( ':=' )
  self:outindent( '%s = %s', cid, self:parseExpr() )
end

function M:parseCompoundStmt()
  self:match( 'begin' )
  
  while self:token() ~= 'end' do
    self:parseStatement()
  end
  
  self:match( 'end' )
end

function M:parseIfStmt()
  self:match( 'if' )
  local cond = self:parseExpr()
  self:match( 'then' )
  
  self:outln( 'if %s then', cond )
  self:indent()
  self:parseStatement()
  self:unindent()
  
  if self:token() == 'else' then
    self:match()
    self:outln( 'else' )
    self:indent()
    self:parseStatement()
    self:unindent()
  end
  
  self:outln( 'end' )
end

function M:parseCaseStmt()
  self:match( 'case' )
  local cid, def = self:parseCid()
  self:match( 'of' )
  
  local stmt = 'if'
  
  while self:token() ~= 'end' do
    local values = { ( self:parseExpr() ) }
    
    while self:token() == ',' do
      self:match()
      values[ #values + 1 ] = self:parseExpr()
    end
    
    self:match( ':' )
    self:outindent( stmt )
    self:indent()
    local sep = ' '
    
    for _, value in ipairs( values ) do
      self:out( '%s( %s == %s )', sep, cid, value )
      sep = ' or '
    end
    
    self:out( ' then' )
    self:outln()
    stmt = 'elseif'
    
    self:parseStatement()
    
    self:unindent()
    self:outln()
  end
  
  self:outln( 'end' )
  self:match( 'end' )
end

function M:parseForStmt()
  self:match( 'for' )
  local cid, def = self:parseCid()
  self:match( ':=' )
  
  local start = self:parseExpr()
  local step = self:token()
  
  if step == 'downto' then
    self:match()
  else
    self:match( 'to' )
  end
  
  local finish = self:parseExpr()
  self:match( 'do' )
  
  self:outln( '%s = %s', cid, start )
  self:outln( 'while %s %s %s do', cid, ( step == 'to' and '<=' or '>=' ), finish )
  self:indent()
  
  self:parseStatement()
  
  self:outln( '%s = %s %s 1', cid, cid, ( step == 'to' and '+' or '-' ) )
  self:unindent()
  self:outln( 'end' )
end

function M:parseWhileStmt()
  self:match( 'while' )
  local cond = self:parseExpr()
  self:match( 'do' )
  
  self:outln( 'while %s do', cond )
  self:indent()
  self:parseStatement()
  self:unindent()
  self:outln( 'end' )
end

function M:parseRepeatStmt()
  self:match( 'repeat' )
  self:outln( 'repeat' )
  self:indent()
  
  while self:token() ~= 'until' do
    self:parseStatement()
  end
  
  self:unindent()
  self:match( 'until' )
  
  local cond = self:parseExpr()
  self:outln( 'until %s', cond )
end

function M:parseIncStmt()
  self:match( 'inc' )
  self:match( '(' )
  local cid = self:parseCid()
  local count = '1'
  
  if self:token() == ',' then
    self:match()
    count = self:parseExpr()
  end
  
  self:match( ')' )
  self:outln( '%s = %s + %s', cid, cid, count )
end

function M:parseDecStmt()
  self:match( 'dec' )
  self:match( '(' )
  local cid = self:parseCid()
  local count = '1'
  
  if self:token() == ',' then
    self:match()
    count = self:parseExpr()
  end
  
  self:match( ')' )
  self:outln( '%s = %s - %s', cid, cid, count )
end

function M:parseDecodeDateStmt()
  self:match( 'decodedate' )
  self:match( '(' )
  local time = self:parseCid()
  self:match( ',' )
  local year = self:parseCid()
  self:match( ',' )
  local month = self:parseCid()
  self:match( ',' )
  local day = self:parseCid()
  self:match( ')' )
  
  self:outln( '%s, %s, %s = sysutils.decodedate( %s )', day, month, year, time )
end

function M:parseDecodeTimeStmt()
  self:match( 'decodetime' )
  self:match( '(' )
  local time = self:parseCid()
  self:match( ',' )
  local hour = self:parseCid()
  self:match( ',' )
  local min = self:parseCid()
  self:match( ',' )
  local sec = self:parseCid()
  self:match( ',' )
  local msec = self:parseCid()
  self:match( ')' )
  
  self:outln( '%s, %s, %s, %s = sysutils.decodetime( %s )', hour, min, sec, msec, time )
end

function M:parseWithStmt()
  self:error( 'Statement expected' )
end

function M:parseInitialization()
  self:match( 'initialization' )
  self:newScope( 'local ', '' )
  
  while self:token() ~= 'end' do
    self:parseStatement()
  end
  
  self:match( 'end' )
  self:match( '.' )
end

function M:parseExpr()
  return self:parseRelational()
end

function M:parseRelational()
  local ops = { [ '=' ] = '==', [ '<>' ] = '~=', [ '<' ] = '<', [ '>' ] = '>', [ '<=' ] = '<=', [ '>=' ] = '>=' }
  
  local value1, def1 = self:parseAdd()
  local token = self:token()
  
  while ops[ token ] do
    self:match()
    
    local value2, def2 = self:parseAdd()
    value1 = string.format( '( %s %s %s )', value1, ops[ token ], value2 )
    def1 = { type = 'boolean' }
    
    token = self:token()
  end
  
  return value1, def1
end

function M:parseAdd()
  local ops = { [ '+' ] = '+', [ '-' ] = '-', [ 'or' ] = true, [ 'xor' ] = true }
  
  local value1, def1 = self:parseMultiply()
  local token = self:token()
  
  while ops[ token ] do
    self:match()
    
    local value2, def2 = self:parseMultiply()
    
    if token == 'or' then
      if def1.type == 'integer' and def2.type == 'integer' then
        value1 = string.format( '( %s | %s )', value1, value2 )
        def1 = { type = 'integer' }
      else
        value1 = string.format( '( %s or %s )', value1, value2 )
        def1 = { type = 'boolean' }
      end
    elseif token == 'xor' then
      if def1.type == 'integer' and def2.type == 'integer' then
        value1 = string.format( '( %s ~ %s )', value1, value2 )
        def1 = { type = 'integer' }
      else
        value1 = string.format( '( ( %s and not %s ) or ( not %s and %s ) )', value1, value2, value1, value2 )
        def1 = { type = 'boolean' }
      end
    elseif token == '+' then
      if ( def1.type == 'string' or def1.type == 'char' ) and ( def2.type == 'string' or def2.type == 'char' ) then
        value1 = string.format( '( %s .. %s )', value1, value2 )
        def1 = { type = 'string' }
      else
        value1 = string.format( '( %s + %s )', value1, value2 )
        def1 = { type = ( def1.type == 'fp' or def2.type == 'fp' ) and 'fp' or 'integer' }
      end
    else
      value1 = string.format( '( %s %s %s )', value1, ops[ token ], value2 )
      def1 = { type = 'integer' }
    end
    
    token = self:token()
  end
  
  return value1, def1
end

function M:parseMultiply()
  local ops = { [ '*' ] = '*', [ '/' ] = '/', [ 'div' ] = '//', [ 'mod' ] = '%', [ 'and' ] = true }
  
  local value1, def1 = self:parseUnary()
  local token = self:token()
  
  while ops[ token ] do
    self:match()
    
    local value2, def2 = self:parseUnary()
    
    if token == 'and' then
      if def1.type == 'integer' and def2.type == 'integer' then
        value1 = string.format( '( %s & %s )', value1, value2 )
        def1 = { type = 'integer' }
      else
        value1 = string.format( '( %s and %s )', value1, value2 )
        def1 = { type = 'boolean' }
      end
    else
      value1 = string.format( '( %s %s %s )', value1, ops[ token ], value2 )
      def1 = { type = 'integer' }
    end
    
    token = self:token()
  end
  
  return value1, def1
end

function M:parseUnary()
  local token = self:token()
  
  if token == 'not' then
    self:match()
    local value, def = self:parseTerminal()
    return string.format( '( not %s )', value ), def
  elseif token == '-' then
    self:match()
    local value, def = self:parseTerminal()
    return string.format( '( -%s )', value ), def
  else
    return self:parseTerminal()
  end
end

function M:parseTerminal()
  local token = self:token()
  
  if token == 'integer' then
    local value = self:lexeme()
    self:match()
    return value, { type = 'integer' }
  elseif token == 'fp' then
    local value = self:lexeme()
    self:match()
    return value, { type = 'fp' }
  elseif token == 'nil' then
    self:match()
    return 'nil', { type = 'nil' }
  elseif token == 'true' or token == 'false' then
    local value = self:lexeme()
    self:match()
    return value, { type = 'boolean' }
  elseif token == 'string' then
    local value = self.tokens[ self.pos ].lexeme
    self:match()
    return string.format( '[[%s]]', value ), { type = 'string' }
  elseif token == 'char' then
    local value = self:lexeme()
    self:match()
    return string.format( '[[%s]]', value ), { type = 'char' }
  elseif token == 'ord' then
    self:match()
    self:match( '(' )
    local value, def = self:parseExpr()
    self:match( ')' )
    
    if def.type == 'boolean' then
      return string.format( '( %s and 1 or 0 )', value ), { type = 'integer' }
    else
      return value, def
    end
  elseif token == 'odd' then
    self:match()
    self:match( '(' )
    local value = self:parseExpr()
    self:match( ')' )
    return string.format( '( %s & 1 ~= 0 )', value ), { type = 'boolean' }
  elseif token == 'chr' then
    self:match()
    self:match( '(' )
    local value = self:parseExpr()
    self:match( ')' )
    return string.format( 'string.char%s', value ), { type = 'char' }
  elseif token == 'trunc' then
    self:match()
    self:match( '(' )
    local value = self:parseExpr()
    self:match( ')' )
    return string.format( 'math.floor%s', value ), { type = 'integer' }
  elseif token == 'abs' then
    self:match()
    self:match( '(' )
    local value = self:parseExpr()
    self:match( ')' )
    return string.format( 'math.abs%s', value ), { type = 'integer' }
  elseif token == 'power' then
    self:match()
    self:match( '(' )
    local base = self:parseExpr()
    self:match( ',' )
    local exp = self:parseExpr()
    self:match( ')' )
    return string.format( '( %s ^ %s )', base, exp ), { type = 'fp' }
  elseif token == 'self' then
    self:match()
    return
  elseif token == 'id' then
    local cid, def = self:parseCid()
    
    if self:token() == 'in' then
      self:match()
      local cid2, def2 = self:parseCid()
      return string.format( '%s[ %s%s ]', cid2, self:declared( cid2 ), cid ), { type = 'boolean' }
    elseif self:token() == '(' then
      self:match()
      local args = { ( self:parseExpr() ) }
      
      while self:token() == ',' do
        self:match()
        args[ #args + 1 ] = self:parseExpr()
      end
      
      self:match( ')' )
      return string.format( '%s( %s )', cid, table.concat( args, ', ' ) ), { type = def.type }
    elseif def.type == 'function' then
      return string.format( '%s()', cid ), def
    else
      return cid, def
    end
  elseif token == '[' then
    self:match()
    local value = {}
    
    if self:token() ~= ']' then
      value[ #value + 1 ] = self:parseCid()
      
      while self:token() == ',' do
        self:match()
        value[ #value + 1 ] = self:parseCid()
      end
    end
    
    self:match( ']' )
    return string.format( '{ %s }', table.concat( value, ', ' ) ), { type = 'set' }
  elseif token == '(' then
    self:match()
    local value, def = self:parseExpr()
    self:match( ')' )
    return value, def
  end
  
  self:error( '%s is invalid in expressions', token )
end

return M
