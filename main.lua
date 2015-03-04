local luatype = type

local function errorout( ... )
  local args = { ... }
  local msg = table.concat( args )
  error( debug.traceback( msg ) )
  io.stderr:write( msg, '\n' )
  os.exit( 1 )
end

local spaces = ''

local function out( ... )
  local args = { ... }
  local what = table.concat( args )
  
  for i = 1, #what do
    local k = what:byte( i )
    
    if k == 10 then
      io.write( '\n', spaces )
    else
      io.write( string.char( k ) )
    end
  end
end

local function ident()
  spaces = spaces .. '  '
end

local function unident()
  spaces = spaces:sub( 1, -3 )
end

local function tokenize( lex )
  local tokens = {}
  local i = 1
  
  repeat
    local la, err = lex:next()
    
    if not la then
      errorout( err )
    end
    
    if la.token ~= 'comment' then
      tokens[ i ] = la
      i = i + 1
    end
  until la.token == 'eof'
  
  return tokens
end

local function newLexer( source, path )
  -- http://www.w3.org/TR/xmlschema-2/#built-in-datatypes
  
  local reserved = {
    'unit', ';', 'interface', 'uses', ',', 'type', '=', 'class', '(', ')',
    ':', 'procedure', 'function', 'var', 'repeat', 'until', 'trunc',
    'end', 'const', 'array', '[', ']', '..', 'power',
    'of', 'implementation', '.', 'begin', ':=', '-', 'nil', 'true', 'false',
    'if', 'then', 'else', 'for', 'to', 'downto', 'do', 'case', 'while', 'div', 'mod',
    'not', 'initialization', '+', '*', '/', '<', '<=', '>', '>=', '<>', '$',
    'randomize', 'ord', 'inc', 'dec', 'in', '$', 'vk_left', 'vk_right',
    'or', 'and', 'now', 'decodetime', 'random', 'chr', 'vk_up', 'vk_down',
    'odd'
  }
  
  local tokens = {}
  
  for _, token in ipairs( reserved ) do
    tokens[ token ] = lexer.token
  end
  
  tokens[ '//' ] = lexer.lineCommentStart
  tokens[ '{' ] = lexer.blockCommentStart
  tokens[ '}' ] = lexer.blockCommentEnd

  return lexer.new( source, path, tokens, "'", false, false )
end

local function newParser( path, tokens )
  return {
    path = path,
    tokens = tokens,
    pos = 1,
    types = {
      boolean = true, integer = true, tform1 = true, treginifile = true,
      pfsoundsample = true, timage = true, ttimer = true, word = true,
      tobject = true, tcloseaction = true, tmousebutton = true,
      tshiftstate = true, tdatetime = true
    },
    class = nil,
    globals = {},
    locals = nil,
    
    error = function( self, ... )
      local args = { ... }
      errorout( self.path, ':', self.tokens[ self.pos ].line, ': ', unpack( args ) )
    end,
    
    token = function( self, offset )
      offset = offset or 1
      return self.tokens[ self.pos + offset - 1 ].token
    end,
    
    lexeme = function( self, offset )
      offset = offset or 1
      return self.tokens[ self.pos + offset - 1 ].lexeme
    end,
    
    match = function( self, token )
      if false then
        local info = debug.getinfo( 2, 'nl' )
        io.write( '--[[', info.currentline or 'nil', ' ', info.name or 'nil', ' ', token or 'nil', ' ', self.tokens[ self.pos ].lexeme )
        for i = 3, 5 do
          local info = debug.getinfo( i, 'nl' )
          io.write( i == 2 and '' or ' | ', info.currentline or 'nil', ' ', info.name or 'nil' )
        end
        io.write( ']]' )
      end
      
      if token == nil or self.tokens[ self.pos ].token == token then
        self.pos = self.pos + 1
        return self.tokens[ self.pos - 1 ].lexeme
      end
      
      self:error( 'Expected: ', token, ', found ', self.tokens[ self.pos ].token )
    end,
    
    maybe = function( self, token )
      if self:token() == token then
        self:match()
      end
    end,
    
    getVariable = function( self, id )
      id = id:lower()
      
      --[[
      io.write( 'looking for ', id, '\n' )
      io.write( '\tlocals\n' )
      
      if self.locals then
        for k in pairs( self.locals ) do io.write( '\t\t', k, '\n' ) end
      end
      
      io.write( '\tglobals\n' )
      
      if self.globals then
        for k in pairs( self.globals ) do io.write( '\t\t', k, '\n' ) end
      end
      -- ]]
      
      local def = self.locals and self.locals[ id ]
      
      if def then
        return ( def.prop and def.prop or '' ) .. id, def
      end
      
      if self.globals[ id ] then
        return id, self.globals[ id ]
      end
      
      return id
    end,
    
    parseId = function( self )
      local id = self:lexeme()
      self:match( 'id' )
      
      local id, def = self:getVariable( id )
      local final = { id }
      
      while self:token() == '.' or self:token() == '[' do
        while self:token() == '.' do
          self:match()
          final[ #final + 1 ] = '.'
          final[ #final + 1 ] = self:lexeme():lower()
          self:match( 'id' )
        end
        
        if self:token() == '[' then
          self:match()
          
          while true do
            final[ #final + 1 ] = '[ '
            final[ #final + 1 ] = self:parseExpression()
            final[ #final + 1 ] = ' ]'
            
            if self:token() == ',' then
              self:match()
            else
              break
            end
          end
          
          self:match( ']' )
        end
      end
      
      return table.concat( final ), def
    end,
    
    parseArgs = function( self )
      local args = { '(' }
      
      if self:token() == '(' then
        self:match( '(' )
        args[ #args + 1 ] = ' '
        
        while true do
          args[ #args + 1 ] = self:parseExpression()
          
          if self:token() == ',' then
            self:match()
            args[ #args + 1 ] = ', '
          else
            break
          end
        end
        
        self:match( ')' )
        args[ #args + 1 ] = ' '
      end
      
      args[ #args + 1 ] = ')'
      return table.concat( args )
    end,
    
    parseExpression = function( self )
      local parseExp = function()
        return self:parseExpression()
      end
      
      local parseTerminal = function()
        local terms = { integer = true, fp = true, [ 'nil' ] = true, [ 'true' ] = true, [ 'false' ] = true }
        local token = self:token()
        local value
        
        if terms[ token ] then
          value = self:lexeme()
          self:match()
        elseif token == 'string' then
          value = '[[' .. self:lexeme() .. ']]'
          self:match()
        elseif token == 'id' then
          local id, def = self:parseId()
          
          if self:token() == 'in' then
            self:match()
            local id2, def2 = self:parseId()
            value = id2 .. '[ ' .. id .. ' ]'
          elseif self:token() == '(' then
            value = id .. self:parseArgs()
          else
            value = id
          end
        elseif token == '$' then
          local keys = { [ '31' ] = 'l1', [ '32' ] = 'r1', [ '33' ] = 'l2', [ '35' ] = 'r2' }
          self:match()
          value = '\'' .. ( keys[ self:lexeme() ] or self:lexeme() ) .. '\''
          self:match( 'integer' )
        elseif token == 'vk_left' or token == 'vk_right' or token == 'vk_up' or token == 'vk_down' then
          self:match()
          value = token == 'vk_left' and '\'left\'' or ( token == 'vk_right' and '\'right\'' or ( token == 'vk_up' and '\'up\'' or '\'down\'' ) )
        elseif token == 'now' then
          self:match()
          value = 'gw.now()'
        elseif token == 'ord' then
          self:match()
          self:match( '(' )
          local exp = parseExp()
          self:match( ')' )
          value = 'compat_ord( ' .. exp .. ' )'
        elseif token == 'odd' then
          self:match()
          self:match( '(' )
          local exp = parseExp()
          self:match( ')' )
          value = '( ( ' .. exp .. ' ) & 1 ~= 0 )'
        elseif token == 'chr' then
          self:match()
          self:match( '(' )
          local exp = parseExp()
          self:match( ')' )
          value = 'string.char( ' .. exp .. ' )'
        elseif token == 'trunc' then
          self:match()
          self:match( '(' )
          local exp = parseExp()
          self:match( ')' )
          value = 'math.floor( ' .. exp .. ' )'
        elseif token == 'power' then
          self:match()
          self:match( '(' )
          local base = parseExp()
          self:match( ',' )
          local exp = parseExp()
          self:match( ')' )
          value = '( ( ' .. base .. ' ) ^ ( ' .. exp .. ' ) )'
        elseif token == 'random' then
          self:match()
          self:match( '(' )
          local exp = parseExp()
          self:match( ')' )
          value = 'gw.random( ' .. exp .. ' )'
        elseif token == '(' then
          self:match()
          value = parseExp()
          self:match( ')' )
        else
          self:error( token, ' is invalid in expressions' )
        end
        
        return value
      end
      
      local parseUnary = function()
        local token = self:token()
        
        if token == 'not' then
          self:match()
          return '( not ' .. parseTerminal() .. ' )'
        elseif token == '-' then
          self:match()
          return '( -( ' .. parseTerminal() .. ' ) )'
        else
          return parseTerminal()
        end
      end
      
      local parseMultiply = function()
        local ops = { [ '*' ] = '*', [ '/' ] = '/', [ 'div' ] = '//', [ 'mod' ] = '%', [ 'and' ] = true }
        local value = parseUnary()
        local token = self:token()
        
        while ops[ token ] do
          local op = token
          self:match()
          
          if op == 'and' then
            value = 'compat_and( ' .. value .. ', ' .. parseUnary() .. ' )'
          else
            value = '( ' .. value .. ' ' .. ops[ token ] .. ' ' .. parseUnary() .. ' )'
          end
          
          token = self:token()
        end
        
        return value
      end
      
      local parseAdd = function()
        local ops = { [ '+' ] = '+', [ '-' ] = '-', [ 'or' ] = true, [ 'xor' ] = '~' }
        local value = parseMultiply()
        local token = self:token()
        
        while ops[ token ] do
          local op = token
          self:match()
          
          if op == 'or' then
            value = 'compat_or( ' .. value .. ', ' .. parseMultiply() .. ' )'
          else
            value = '( ' .. value .. ' ' .. ops[ token ] .. ' ' .. parseMultiply() .. ' )'
          end
          
          token = self:token()
        end
        
        return value
      end
      
      local parseRelational = function()
        local ops = { [ '=' ] = '==', [ '<>' ] = '~=', [ '<' ] = '<', [ '>' ] = '>', [ '<=' ] = '<=', [ '>=' ] = '>=' }
        local value = parseAdd()
        local token = self:token()
        
        while ops[ token ] do
          self:match()
          value = '( ' .. value .. ' ' .. ops[ token ] .. ' ' .. parseAdd() .. ' )'
          token = self:token()
        end
        
        return value
      end
      
      local value = parseRelational()
      return value
    end,
    
    parseVarDecls = function( self )
      local ids = {}
      self:match( 'var' )
      
      while self:token() == 'id' do
        local temp = {}
        temp[ self:lexeme() ] = true
        self:match()
        
        while self:token() == ',' do
          self:match()
          temp[ self:lexeme() ] = true
          self:match( 'id' )
        end
        
        self:match( ':' )
        
        if self:token() == 'array' then
          self:match( 'array' )
          self:match( '[' )
          local array = { dims = {} }
          
          while true do
            local i = self:lexeme()
            self:match( 'integer' )
            self:match( '..' )
            local j = self:lexeme()
            self:match( 'integer' )
            
            array.dims[ #array.dims + 1 ] = { i = i, j = j }
            
            if self:token() == ',' then
              self:match()
            else
              break
            end
          end
            
          self:match( ']' )
          self:match( 'of' )
          local type = self:lexeme():lower()
          self:match( 'id' )
          
          if type == 'record' then
            --array.dims[ #array.dims + 1 ] = { i = 1, j = 1 }
            
            while self:token() ~= 'end' do
              self:match( 'id' )
              
              while self:token() == ',' do
                self:match()
                self:match( 'id' )
              end
              
              self:match( ':' )
              self:match( 'id' )
              self:maybe( ';' )
            end
            
            self:match( 'end' )
            
            for id in pairs( temp ) do
              ids[ id:lower() ] = { id = id, type = type, array = array }
            end
          elseif self.types[ type ] then
            for id in pairs( temp ) do
              ids[ id:lower() ] = { id = id, type = type, array = array }
            end
          else
            self:error( 'Unknown type ', type )
          end
        else
          local type = self:lexeme():lower()
          self:match( 'id' )
          
          if self.types[ type ] then
            for id in pairs( temp ) do
              ids[ id:lower() ] = { type = type }
            end
          else
            self:error( 'Unknown type ', type )
          end
        end
        
        self:match( ';' )
      end
      
      return ids
    end,
    
    parseStatement = function( self )
      local token = self:token()
      
      if token == 'begin' then
        self:match()
        self:parseStatements()
        self:match( 'end' )
        self:maybe( ';' )
        return
      end
      
      if token == 'id' then
        local id, def = self:parseId()
        
        if self:token() == ':=' then
          -- assignment
          self:match()
          out( id, ' = ', self:parseExpression(), '\n' )
        else
          -- procedure call
          out( id, self:parseArgs(), '\n' )
        end
      elseif token == 'randomize' then
        self:match()
        out( 'gw.randomize()\n' )
      elseif token == 'if' then
        self:match()
        local cond = self:parseExpression()
        self:match( 'then' )
        
        ident()
        out( 'if ', cond, ' then\n' )
        self:parseStatement()
        unident()
        
        if self:token() == 'else' then
          self:match()
          out( '\nelse' )
          ident()
          out( '\n' )
          self:parseStatement()
          unident()
        end
        
        out( '\nend\n' )
      elseif token == 'for' then
        self:match()
        
        local id, def = self:getVariable( self:lexeme() )
        self:match( 'id' )
        
        self:match( ':=' )
        local start = self:parseExpression()
        local step = self:token()
        
        if step == 'downto' then
          self:match()
        else
          self:match( 'to' )
        end
        
        local finish = self:parseExpression()
        self:match( 'do' )
        
        out( id, ' = ', start, '\n' )
        ident()
        out( 'while ', id, ( step == 'to' and ' <= ' or ' >= ' ), finish, ' do\n' )
        
        self:parseStatement()
        
        if step == 'to' then
          out( id, ' = ', id, ' + 1\n' )
        else
          out( id, ' = ', id, ' - 1\n' )
        end
        
        unident()
        out( '\nend\n' )
      elseif token == 'case' then
        self:match()
        local id, def = self:parseId()
        self:match( 'of' )
        
        local stmt = 'if'
        
        while self:token() ~= 'end' do
          local values = { self:parseExpression() }
          
          while self:token() == ',' do
            self:match()
            values[ #values + 1 ] = self:parseExpression()
          end
          
          self:match( ':' )
          ident()
          out( stmt )
          local sep = ' '
          
          for _, value in ipairs( values ) do
            out( sep, '( ', id, ' == ', value, ' )' )
            sep = ' or '
          end
          
          out( ' then\n' )
          stmt = 'elseif'
          
          self:parseStatement()
          
          unident()
          out( '\n' )
        end
        
        out( 'end\n' )
        self:match( 'end' )
        self:maybe( ';' )
      elseif token == 'while' then
        self:match()
        local cond = self:parseExpression()
        self:match( 'do' )
        
        ident()
        out( 'while ', cond, ' do\n' )
        self:parseStatement()
        unident()
        out( '\nend\n' )
      elseif token == 'repeat' then
        self:match()
        ident()
        out( 'repeat\n' )
        while self:token() ~= 'until' do
          self:parseStatement()
        end
        unident()
        self:match( 'until' )
        local cond = self:parseExpression()
        out( '\nuntil ', cond, '\n' )
      elseif token == 'inc' or token == 'dec' then
        self:match()
        self:match( '(' )
        local id, def = self:parseId()
        
        local step = '1'
        
        if self:token() == ',' then
          self:match()
          step = self:parseExpression()
        end
        
        self:match( ')' )
        
        out( id, ' = ', id, ' ', ( token == 'inc' and '+' or '-' ), ' ', step, '\n' )
      elseif token == 'decodetime' then
        self:match()
        self:match( '(' )
        local time = self:parseId()
        self:match( ',' )
        local hour = self:parseId()
        self:match( ',' )
        local min = self:parseId()
        self:match( ',' )
        local sec = self:parseId()
        self:match( ',' )
        local msec = self:parseId()
        self:match( ')' )
        self:maybe( ';' )
        
        out( hour, ', ', min, ', ', sec, ', ', msec, ' = gw.splitTime( ', time, ' )\n' )
      else
        self:error( 'Invalid statement: ', self:token() )
      end
      
      self:maybe( ';' )
    end,
    
    parseStatements = function( self )
      while self:token() ~= 'end' do
        self:parseStatement()
      end
    end,
    
    parseProcedureOrFunction = function( self )
      local is_function = true
      
      if self:token() == 'function' then
        self:match()
      else
        self:match( 'procedure' )
        is_function = false
      end
      
      self.locals = {}
      ident()
      
      local class = self:lexeme():lower()
      self:match( 'id' )
      self:match( '.' )
      local id = self:lexeme():lower()
      self:match( 'id' )
      
      for id, def in pairs( self.globals[ class ].props ) do
        self.locals[ id ] = def
      end
      
      out( class, '_', id, ' = function' )

      if self:token() == '(' then
        out( '(' )
        self:match()
        local sep = ' '
        
        while true do
          local ids = {}
          
          if self:token() == 'var' then
            self:match()
          end
          
          local id = self:lexeme():lower()
          ids[ id ] = {}
          out( sep, id )
          sep = ', '
          self:match( 'id' )
          
          while self:token() == ',' do
            self:match()
            id = self:lexeme():lower()
            ids[ id ] = {}
            out( sep, id )
            self:match( 'id' )
          end
          
          self:match( ':' )
          
          local type = self:lexeme():lower()
          self:match( 'id' )
          
          if self.types[ type ] then
            for id, def in pairs( ids ) do
              def.type = type
              self.locals[ id:lower() ] = def
            end
          else
            self:error( 'Unknown type ', type )
          end
          
          if self:token() == ';' then
            self:match()
          else
            break
          end
        end
        
        self:match( ')' )
        out( ' )\n' )
      else
        out( '()\n' )
      end
      
      if is_function then
        self:match( ':' )
        local type = self:lexeme():lower()
        self:match( 'id' )
        
        if not self.types[ type ] then
          self:error( 'Unknown type ', type )
        end
      end
      
      self:match( ';' )
      
      if self:token() == 'var' then
        local vars = self:parseVarDecls()
        
        for id, def in pairs( vars ) do
          out( 'local ', id, ' = ', self:defValue( def.type ), ' -- ', def.type, '\n' )
          self.locals[ id:lower() ] = def
        end
      end
      
      self:match( 'begin' )
      
      self:parseStatements()
      
      self:match( 'end' )
      self:match( ';' )
      unident()
      out( '\nend\n\n' )
      self.locals = nil
    end,
    
    parseConst = function( self )
      self:match( 'const' )
      local ids = {}
      
      while self:token() == 'id' do
        local id = self:lexeme()
        self:match()
        self:match( '=' )
        local value = self:parseExpression()
        self:match( ';' )
        
        ids[ id:lower() ] = { id = id, type = 'const', value = value }
      end
      
      return ids
    end,
    
    parseClassDecls = function( self )
      while self:token() ~= 'end' do
        if self:token() == 'procedure' or self:token() == 'function' then
          local is_function = true
          
          if self:token() == 'function' then
            self:match()
          else
            self:match( 'procedure' )
            is_function = false
          end
          
          local id = self:lexeme():lower()
          self.class.props[ id ] = { prop = self.class.id .. '_', type = 'procedure' }
          out( 'local ', self.class.id, '_', id, ' -- ', ( is_function and 'function' or 'procedure' ), '\n' )
          self:match( 'id' )
          
          if self:token() == '(' then
            self:match( '(' )
            
            while true do
              if self:token() == 'var' then
                self:match()
              end
              
              self:match( 'id' )
              
              while self:token() == ',' do
                self:match()
                self:match( 'id' )
              end
              
              self:match( ':' )
              self:match( 'id' )
              
              if self:token() == ';' then
                self:match()
              else
                self:match( ')' )
                break
              end
            end
          end
          
          if is_function then
            self:match( ':' )
            local type = self:lexeme():lower()
            self:match( 'id' )
            
            if not self.types[ type ] then
              self:error( 'Unknown type ', type )
            end
          end
            
          self:match( ';' )
        else
          local ids = {}
          
          local id = self:lexeme()
          ids[ id:lower() ] = {}
          self:match( 'id' )
          
          while self:token() == ',' do
            self:match()
            local id = self:lexeme()
            ids[ id:lower() ] = {}
            self:match( 'id' )
          end
          
          self:match( ':' )
          
          local type = self:lexeme():lower()
          
          if not self.types[ type ] then
            self:error( 'Error: type expected, found ', self:lexeme() )
          end
          
          self:match( 'id' )
          self:match( ';' )
          
          for id, def in pairs( ids ) do
            def.type = type
            def.prop = self.class.id .. '_'
            self.class.props[ id ] = def
          end
          
          self:declareVars( ids )
        end
      end
    end,
    
    parseType = function( self )
      self:match( 'type' )
      
      while self:token() == 'id' do
        local id = self:lexeme()
        self.class = { id = id:lower(), props = {} }
        self.globals[ id:lower() ] = self.class
        out( '-- class ', id, '\n\n' )
        self:match( 'id' )
        
        self:match( '=' )
        self:match( 'class' )
        self:match( '(' )
        self:match( 'id' )
        self:match( ')' )
        
        self:parseClassDecls()
        
        self:match( 'end' )
        self:match( ';' )
        
        out( '\n' )
        self.class = nil
      end
    end,
    
    parseUses = function( self )
      self:match( 'uses' )
      
      while true do
        self:match( 'id' )
        
        if self:token() == ',' then
          self:match()
        else
          self:match( ';' )
          break
        end
      end
    end,
    
    defValue = function( self, type )
      if type == 'boolean' then
        return 'false'
      elseif type == 'integer' then
        return '0'
      elseif type == 'word' then
        return '0'
      else
        return 'nil'
      end
    end,
    
    declareVars = function( self, vars )
      class = self.class and ( self.class.id .. '_' ) or ''
      
      for id, def in pairs( vars ) do
        if not def.array then
          out( 'local ', class, id )
          
          if def.type == 'boolean' then
            out( ' = false' )
          elseif def.type == 'integer' then
            out( ' = 0' )
          elseif def.type == 'const' then
            out( ' = ', def.value )
          elseif def.type == 'timage' then
            out( ' = image_db.', id )
          elseif def.type == 'ttimer' then
            out( ' = gw.newTimer()' )
          elseif def.type == 'pfsoundsample' then
            out( ' = gw.loadSound( \'', id, '.pcm\' )' )
          end
          
          out ( ' -- ', def.type, '\n' )
        else
          out( 'local ', class, id, ' = {} -- array[ ' )
          
          for i, dim in ipairs( def.array.dims ) do
            if i ~= 1 then
              out( ', ' )
            end
            
            out( dim.i, '..', dim.j )
          end
          
          out( ' ] of ', def.type, '\n' )
          
          local def_value
          
          if def.type == 'boolean' then
            def_value = 'false'
          elseif def.type == 'integer' then
            def_value = '0'
          elseif def.type == 'word' then
            def_value = '0'
          elseif def.type == 'const' then
            def_value = def.value
          elseif def.type == 'record' then
            def_value = '{}'
          else
            def_value = 'nil'
          end
          
          local vars = { 'i', 'j', 'k', 'l', 'm', 'n' }
          out( '( function()\n' )
          
          for i, dim in ipairs( def.array.dims ) do
            out( '  for ', vars[ i ], ' = ', dim.i, ', ', dim.j, ' do' )
            ident()
            out( '\n' )
            
            if i ~= #def.array.dims then
              out( '  ', class, id )
              
              for j = 1, i do
                out( '[ ', vars[ j ], ' ]' )
              end
              
              out( ' = {}\n' )
            end
          end
          
          out( '  ', class, id )
          
          for i = 1, #def.array.dims do
            out( '[ ', vars[ i ], ' ]' )
          end
        
          out ( ' = ', def_value, '\n' )
          
          for i = 1, #def.array.dims do
            unident()
            out( '\n  end' )
          end
          
          out( '\n' )
          out( 'end )()\n' )
        end
      end
    end,
    
    parseUnit = function( self )
      self:match( 'unit' )
      self:match( 'id' )
      self:match( ';' )
      self:match( 'interface' )
      
      while true do
        local what = self:token()
        
        if what == 'uses' then
          self:parseUses()
        elseif what == 'type' then
          self:parseType()
        elseif what == 'const' then
          local vars = self:parseConst()
          out( '-- global constants\n\n' )
          self:declareVars( vars )
          out( '\n' )
        elseif what == 'var' then
          local vars = self:parseVarDecls()
          out( '-- global variables\n\n' )
          self:declareVars( vars )
          out( '\n' )
          
          for id, def in pairs( vars ) do
            self.globals[ id ] = def
          end
        else
          break
        end
      end
      
      --self:declareVars( self.globals )
      
      out( '-- implementation\n\n' )
      self:match( 'implementation' )
      
      while true do
        local what = self:token()
        
        if what == 'uses' then
          self:parseUses()
        elseif what == 'type' then
          self:parseType()
        elseif what == 'const' then
          self:parseConst()
        elseif what == 'var' then
          self:parseVar()
        else
          break
        end
      end
      
      while true do
        if self:token() == 'procedure' or self:token() == 'function' then
          self:parseProcedureOrFunction()
        else
          break
        end
      end
      
      self:match( 'initialization' )
      self:parseStatements()
      self:match( 'end' )
      self:match( '.' )
    end,
    
    parse = function( self )
      out( '-- activate zerobrane studio debugging when in debug mode\n' )
      out( 'if _DEBUG then\n' )
      out( '  local ok, moddebug = pcall( require, \'mobdebug\' )\n\n' )
      out( '  if ok then\n' )
      out( '    moddebug.start()\n' )
      out( '  end\n' )
      out( 'end\n\n' )
      
      out( 'local readonly = {\n' )
      out( '  __index = function( table, key )\n' )
      out( '    local value = rawget( table, key )\n' )
      out( '    if not value then\n' )
      out( '      error( \'unknown variable \' .. key )\n' )
      out( '    end\n' )
      out( '  end,\n' )
      out( '  __newindex = function( table, key, value )\n' )
      out( '    error( \'unknown variable: \' .. key )\n' )
      out( '  end,\n' )
      out( '}\n\n' )
      
      out( '-- lock global table\n' )
      out( 'setmetatable( _G, readonly )\n\n' )
      out( '-- make str1 + str2 do a concatenation\n' )
      out( 'getmetatable( \'\' ).__add = function( a, b )\n' )
      out( '  return a .. b\n' )
      out( 'end\n\n' )
      
      out( 'local gw = gw\n\n' )
      
      out( 'local treginifile = {\n' )
      out( '  create = function( arg1 )\n' )
      out( '    return {\n' )
      out( '      readinteger = function( arg1, key, arg3 )\n' )
      out( '        return gw.loadValue( key ) or 0\n' )
      out( '      end,\n' )
      out( '      writeinteger = function( arg1, key, value )\n' )
      out( '        gw.saveValue( key, value )\n' )
      out( '      end\n' )
      out( '    }\n' )
      out( '  end\n' )
      out( '}\n\n' )
      
      out( 'local compat_ord = function( x )\n' )
      out( '  if type( x ) == \'boolean\' then\n' )
      out( '    return x and 1 or 0\n' )
      out( '  elseif type( x ) == \'number\' then\n' )
      out( '    return x\n' )
      out( '  end\n' )
      out( 'end\n\n' )
      
      out( 'local compat_and = function( x, y )\n' )
      out( '  if type( x ) == \'number\' then\n' )
      out( '    return x & y\n' )
      out( '  else\n' )
      out( '    return x and y\n' )
      out( '  end\n' )
      out( 'end\n\n' )
      
      out( 'local compat_or = function( x, y )\n' )
      out( '  if type( x ) == \'number\' then\n' )
      out( '    return x | y\n' )
      out( '  else\n' )
      out( '    return x or y\n' )
      out( '  end\n' )
      out( 'end\n\n' )
      
      out( 'local fsound_all, fsound_free = {}, {}\n\n' )
      out( 'local fsound_playsound = function( arg1, sound )\n' )
      out( '  sound:play()\n' )
      out( 'end\n\n' )
      out( 'local fsound_stopsound = function( sound )\n' )
      out( '  if sound == fsound_all then\n' )
      out( '    gw.stopSounds()\n' )
      out( '  else\n' )
      out( '    error( "cannot stop one single sound" )\n' )
      out( '  end\n' )
      out( 'end\n\n' )
      
      out( 'local atlas = gw.loadPicture( \'atlas.png\' )\n\n' )
      out( 'local image_db = {\n' )
      out( '  -- paste atlas.lua here\n' )
      out( '}\n\n' )
      
      self:parseUnit()
      
      out( '\n-- set background\n' )
      out( 'gw.setBackground( background.picture ) -- set to the name of the variable that holds the background image\n' )
      out( 'background.visible = false -- set to the name of the variable that holds the background image\n\n' )

      out( '-- timers\n' )
      for id, def in pairs( self.globals ) do
        if def.props then
          for id2, def2 in pairs( def.props ) do
            if def2.type == 'ttimer' then
              out( id, '_', id2, '.onExpired = ', id, '_', id2, 'timer -- set to the name of the function that processes timeout events for this timer\n' )
            end
          end
        end
      end
      out( '\n' )
      
      out( '-- initialize\n' )
      for id, def in pairs( self.globals ) do
        if def.props and def.props[ 'formcreate' ] then
          out( id, '_formcreate() -- set to the name of the function that creates the main form\n' )
        end
      end
      out( '\n' )

      out( '-- set game to ACL mode\n' )
      out( 'imode = 1 -- set to the name of the variable that controls the game mode\n' )
      out( 'tform1_gam_set_mode() -- set to the name of the function that changes the game mode\n\n' )
      
      out( '-- get rid of the image database\n' )
      out( 'image_db = nil\n\n' )
      
      out( '-- return needed functions\n' )
      out( 'return\n' )
      out( '  function() -- tick\n' )
      out( '    -- fire timers\n' )

      for id, def in pairs( self.globals ) do
        if def.props then
          for id2, def2 in pairs( def.props ) do
            if def2.type == 'ttimer' then
              out( '    ', id, '_', id2, ':tick()\n' )
            end
          end
        end
      end

      out( '  end,\n' )
      out( '  function( button, ndx ) -- button_down\n' )
      out( '    tform1_formkeydown( nil, button, nil ) -- set to the name of the function that processes button down events\n' )
      out( '  end,\n' )
      out( '  function( button, ndx ) -- button_up\n' )
      out( '    tform1_formkeyup( nil, button, nil ) -- set to the name of the function that processes button up events\n' )
      out( '  end\n' )
    end
  }
end

-- main function
return function( args )
  if #args ~= 1 then
    io.write( 'Usage: p2l <pascal>\n' )
    return 0
  end
  
  local file, err = io.open( args[ 1 ] )
  
  if not file then
    errorout( 'Error rading from ' .. args[ 1 ] )
  end
  
  local source = file:read( '*a' )
  file:close()
  
  if not source then
    errorout( 'Could not read from ' .. args[ 1 ] )
  end
  
  local tokens = tokenize( newLexer( source, args[ 1 ] ) )
  newParser( args[ 1 ], tokens ):parse()
  
  return 0
end
