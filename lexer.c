#include <stdint.h>
#include <string.h>
#include <ctype.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#define MY_NAME "lexer_t"

#define TOOBIG            -2
#define INVALIDCHAR       -1
#define TOKEN              1
#define LINECOMMENTSTART   2
#define BLOCKCOMMENTSTART  3
#define BLOCKCOMMENTEND    4

#if 0
static void dump_stack( lua_State* L )
{
  int top = lua_gettop( L );
  int i;
  
  for ( i = 1; i <= top; i++ )
  {
    printf( "%2d %3d ", i, i - top - 1 );
    
    lua_pushvalue( L, i );
    
    switch ( lua_type( L, -1 ) )
    {
    case LUA_TNIL:
      printf( "nil\n" );
      break;
    case LUA_TNUMBER:
      printf( "%e\n", lua_tonumber( L, -1 ) );
      break;
    case LUA_TBOOLEAN:
      printf( "%s\n", lua_toboolean( L, -1 ) ? "true" : "false" );
      break;
    case LUA_TSTRING:
      printf( "\"%s\"\n", lua_tostring( L, -1 ) );
      break;
    case LUA_TTABLE:
      printf( "table\n" );
      break;
    case LUA_TFUNCTION:
      printf( "function\n" );
      break;
    case LUA_TUSERDATA:
      printf( "userdata\n" );
      break;
    case LUA_TTHREAD:
      printf( "thread\n" );
      break;
    case LUA_TLIGHTUSERDATA:
      printf( "light userdata\n" );
      break;
    default:
      printf( "?\n" );
      break;
    }
  }
}
#endif

typedef struct
{
  int  source_ref;
  int  source_name_ref;
  int  line_number;
  int  keywords_ref;
  char quote;
  int  case_sensitive;
  int  octals;
  
  const char* begin;
  const char* start;
  const char* current;
  const char* end;
}
lexer_t;

static const uint8_t char_classes[ 256 ] =
{
  0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x41, 0x00, 0x00, 0x01, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x3c, 0x3c, 0x2c, 0x2c, 0x2c, 0x2c, 0x2c, 0x2c, 0x0c, 0x0c, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02,
  0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x00, 0x00, 0x00, 0x00, 0x02,
  0x00, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02,
  0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};

enum
{
  CC_SPACE   = 1 << 0,
  CC_ALPHA   = 1 << 1,
  CC_DECIMAL = 1 << 2,
  CC_HEXA    = 1 << 3,
  CC_BINARY  = 1 << 4,
  CC_OCTAL   = 1 << 5,
  CC_EOS     = 1 << 6,
  CC_ALNUM   = CC_ALPHA | CC_DECIMAL
};

static char is_space( char k )
{
  return char_classes[ (unsigned char)k ] & CC_SPACE;
}

static char is_alpha( char k )
{
  return char_classes[ (unsigned char)k ] & CC_ALPHA;
}

static char is_alnum( char k )
{
  return char_classes[ (unsigned char)k ] & CC_ALNUM;
}

static char is_decimal( char k )
{
  return char_classes[ (unsigned char)k ] & CC_DECIMAL;
}

static char is_hexa( char k )
{
  return char_classes[ (unsigned char)k ] & CC_HEXA;
}

static char is_binary( char k )
{
  return char_classes[ (unsigned char)k ] & CC_BINARY;
}

static char is_octal( char k )
{
  return char_classes[ (unsigned char)k ] & CC_OCTAL;
}

static char is_eos( char k )
{
  return char_classes[ (unsigned char)k ] & CC_EOS;
}

static lexer_t* check_lexer( lua_State* L, int index )
{
  return (lexer_t*)luaL_checkudata( L, index, MY_NAME );
}

static void skip( lexer_t* lexer )
{
  if ( lexer->current < lexer->end )
  {
    lexer->current++;
  }
}

static int get_escape_char( lexer_t* lexer )
{
  skip( lexer );
  char k = *lexer->current;
  skip( lexer );
  
  switch ( k )
  {
  case 'a':  return '\a';
  case 'b':  return '\b';
  case 'f':  return '\f';
  case 'n':  return '\n';
  case 'r':  return '\r';
  case 't':  return '\t';
  case '\\': return '\\';
  case '\'': return '\'';
  case '"':  return '"';
  
  case '0': case '1': case '2': case '3': case '4': case '5': case '6': case '7':
    {
      int n = k - '0';
      int i;
      
      for ( i = 0; i < 2; i++ )
      {
        if ( !is_octal( *lexer->current ) )
        {
          return -1;
        }
      
        n = n * 8 + *lexer->current - '0';
        skip( lexer );
      }
      
      return n;
    }
  
  case 'x':
    {
      int n = 0;
      int i;
      
      for ( i = 0; i < 2; i++ )
      {
        if ( !is_hexa( *lexer->current ) )
        {
          return -1;
        }
      
        char d = *lexer->current;
        skip( lexer );
        
        if ( d <= '9' )
        {
          d -= '0';
        }
        else
        {
          d = tolower( d ) - 'a' + 10;
        }
        
        n = n * 16 + d;
      }
      
      return n;
    }
  
  default:
    return -1;
  }
}

static int push_result( lua_State* L, lexer_t* lexer, int lexeme_index, int token_index )
{
  lua_rawgeti( L, LUA_REGISTRYINDEX, lexer->source_name_ref );
  lua_setfield( L, 2, "source" );
  
  lua_pushinteger( L, lexer->line_number );
  lua_setfield( L, 2, "line" );
  
  lua_pushinteger( L, lexer->start - lexer->begin + 1 );
  lua_setfield( L, 2, "pos" );

  lua_pushvalue( L, lexeme_index );
  lua_setfield( L, 2, "lexeme" );
  
  lua_pushvalue( L, token_index );
  lua_setfield( L, 2, "token" );
  
  lua_pushvalue( L, 2 );
  return 1;
}

static int raise_error( lua_State* L, lexer_t* lexer, const char* format, const char* extra )
{
  lua_pushnil( L );
  
  lua_rawgeti( L, LUA_REGISTRYINDEX, lexer->source_name_ref );
  lua_pushliteral( L, ":" );
  lua_pushnumber( L, lexer->line_number );
  lua_pushliteral( L, ": " );
  lua_pushfstring( L, format, extra );
  lua_concat( L, 5 );
  
  return 2;
}

static int parse_symbol( lua_State* L, lexer_t* lexer, size_t* length )
{
  char symbol[ 8 ];
  size_t len = 0;
  int type = 0;
  int top = lua_gettop( L );
  
  lua_rawgeti( L, LUA_REGISTRYINDEX, lexer->keywords_ref );
  
  for ( ;; )
  {
    if ( len == sizeof( symbol ) - 1 )
    {
      type = TOOBIG;
      break;
    }
    
    symbol[ len++ ] = *lexer->current;
    
    lua_pushlstring( L, symbol, len );
    lua_gettable( L, -2 );
    int typ = lua_tointeger( L, -1 );
    lua_pop( L, 1 );
    
    if ( typ != 0 ) // valid symbol
    {
      type = typ;
      skip( lexer );
    }
    else // invalid symbol
    {
      if ( --len == 0 )
      {
        type = INVALIDCHAR;
        break;
      }
      
      *length = len;
      break;
    }
  }
  
  lua_settop( L, top );
  return type;
}

int next_token( lua_State* L )
{
  lexer_t* self = check_lexer( L, 1 );
  
  if ( lua_isnoneornil( L, 2 ) )
  {
    lua_settop( L, 1 );
    lua_newtable( L );
  }
  else
  {
    luaL_checktype( L, 2, LUA_TTABLE );
    lua_settop( L, 2 );
  }
  
  // skip spaces.
  for ( ;; )
  {
    if ( is_space( *self->current ) )
    {
      if ( *self->current == '\n' )
      {
        self->line_number++;
      }
      
      skip( self );
    }
    else if ( *self->current != 0 )
    {
      break;
    }
    else
    {
      // Return EOF if we've reached the end of the input.
      
      lua_pushliteral( L, "<eof>" );
      lua_pushliteral( L, "eof" );
      return push_result( L, self, -2, -1 );
    }
  }
  
  const char* start = self->start = self->current;
  
  // If the character is alphabetic or '_', the token is an identifier.
  if ( is_alpha( *self->current ) )
  {
    // Get all alphanumeric and '_' and '.' characters.
    do
    {
      skip( self );
    }
    while ( is_alnum( *self->current ) );
    
    size_t length = self->current - start;
    lua_rawgeti( L, LUA_REGISTRYINDEX, self->keywords_ref );
    lua_pushlstring( L, start, length );

    if ( self->case_sensitive )
    {
      lua_pushvalue( L, -1 );
    }
    else
    {
      luaL_Buffer lower;
      /*luaL_buffinitsize( L, &lower, length );*/
      luaL_buffinit( L, &lower );
      
      while ( start < self->current )
      {
        luaL_addchar( &lower, tolower( *start++ ) );
      }

      luaL_pushresult( &lower );
    }
  
    lua_pushvalue( L, -1 );
    lua_gettable( L, -4 );
    
    if ( lua_toboolean( L, -1 ) )
    {
      return push_result( L, self, -3, -2 );
    }

    lua_pushliteral( L, "id" );
    return push_result( L, self, -4, -1 );
  }

  // If the character is a digit, the token is a number.
  if ( is_decimal( *self->current ) )
  {
    int real = *self->current == '.' && self->current[ 1 ] != '.';

    do
    {
      skip( self );
    }
    while ( is_decimal( *self->current ) );
    
    if ( !real && *self->current == '.' && self->current[ 1 ] != '.' )
    {
      real = 1;
      
      do
      {
        skip( self );
      }
      while ( is_decimal( *self->current ) );
    }
    
    if ( tolower( *self->current ) == 'e' )
    {
      real = 1;
      skip( self );
      
      if ( *self->current == '-' || *self->current == '+' )
      {
        skip( self );
      }
      
      if ( !is_decimal( *self->current ) )
      {
        char string[ 2 ] = { *self->current, 0 };
        return raise_error( L, self, "Invalid digit in exponent: %c", string );
      }
    }
    
    lua_pushlstring( L, start, self->current - start );
    
    if ( real )
    {
      lua_pushliteral( L, "fp" );
    }
    else
    {
      lua_pushliteral( L, "integer" );
    }
    
    return push_result( L, self, -2, -1 );
  }
  
  // Hexadecimal constants.
  if ( *self->current == '$' )
  {
    int x = 0;
    skip( self );

    if ( is_hexa( *self->current ) )
    {
      do
      {
        int d = tolower( *self->current ) - '0';
        
        if ( d > 9 )
        {
          d -= 'a' - '0' + 10;
        }
        
        x = x * 16 + d;
        skip( self );
      }
      while ( is_hexa( *self->current ) );
    }
    else
    {
      char string[ 2 ] = { *self->current, 0 };
      return raise_error( L, self, "Invalid hexadecimal digit: '%c'", string );
    }
    
    lua_pushfstring( L, "%d", x );
    lua_pushliteral( L, "integer" );
    return push_result( L, self, -2, -1 );
  }

  // If the character is a quote, it's a string.
  if ( *self->current == self->quote )
  {
    skip( self );
    
    luaL_Buffer string;
    luaL_buffinit( L, &string );

    // Get anything until another quote.
    for ( ;; )
    {
      if ( *self->current == self->quote )
      {
        if ( self->current[ 1 ] == self->quote )
        {
          luaL_addchar( &string, self->quote );
          skip( self );
        }
        else
        {
          break;
        }
      }
      else
      {
        luaL_addchar( &string, *self->current );
      }
      
      skip( self );
    }
    
#if 0
    if ( !is_eos( *self->current ) && *self->current != self->quote )
    {
      do
      {
        /*
        if ( *self->current == '\\' )
        {
          int k = get_escape_char( self );
          
          if ( k == -1 )
          {
            char string[ 3 ] = { '\\', *self->current, 0 };
            return raise_error( L, self, "Invalid escape sequence: %s", string );
          }
          
          luaL_addchar( &string, k );
        }
        else
        {
          if ( *self->current >= 0 && *self->current <= 31 )
          {
            const char hex[] = "0123456789abcdef";
            char string[ 3 ] = { hex[ ( *self->current >> 4 ) & 15 ], hex[ *self->current & 15 ], 0 };
            return raise_error( L, self, "Invalid character in string: 0x%s", string );
          }
          
          luaL_addchar( &string, *self->current );
          skip( self );
        }
        */
        
        if ( *self->current == '\'' && self->current[ 1 ] == '\'' )
        {
          luaL_addchar( &string, '\'' );
          skip( self );
        }
        else
        {
          luaL_addchar( &string, *self->current );
        }
        
        skip( self );
      }
      while ( !is_eos( *self->current ) && *self->current != self->quote );
    }
#endif

    if ( *self->current != self->quote )
    {
      return raise_error( L, self, "Unterminated literal", NULL );
    }
    
    skip( self );

    luaL_pushresult( &string );
    lua_pushliteral( L, "string" );
    return push_result( L, self, -2, -1 );
  }
  
  // If the character is #, it's a directive.
  if ( *self->current == '#' )
  {
    luaL_Buffer directive;
    luaL_buffinit( L, &directive );
    
    // Directives end at the end of the line.
    while ( *self->current != '\n' && *self->current != 0 )
    {
      luaL_addchar( &directive, *self->current );
      skip( self );
    }
    
    luaL_pushresult( &directive );
    const char* aux = lua_tostring( L, -1 );
    
    if ( !strncmp( aux, "#line ", 6 ) )
    {
      // Process a #line directive from the preprocessor so we keep track of
      // the current file name and line.
      aux += 6;
      
      // skip spaces.
      while ( is_space( *aux ) )
      {
        aux++;
      }
      
      // Get the line number.
      self->line_number = 0;

      while ( is_decimal( *aux ) )
      {
        self->line_number = self->line_number * 10 + *aux++ - '0';
      }
      
      // Decrement because the end of the directive line will increment it.
      self->line_number--;
      
      // skip spaces.
      while ( is_space( *aux ) )
      {
        aux++;
      }
      
      // skip the opening double quote.
      aux++;
      // Get the file name.
      const char* source_name = aux;

      while ( *aux != '"' )
      {
        aux++;
      }
      
      luaL_unref( L, LUA_REGISTRYINDEX, self->source_name_ref );
      lua_pushlstring( L, source_name, aux - source_name );
      self->source_name_ref = luaL_ref( L, LUA_REGISTRYINDEX );
    }

    // Pass unprocessed directives to the parser.
    lua_pushliteral( L, "directive" );
    return push_result( L, self, -2, -1 );
  }
  
  // If the character is a ', it's a character
  if ( *self->current == '\'' )
  {
    skip( self );
    int k = get_escape_char( self );
    
    if ( k != -1 && *self->current == '\'' )
    {
      skip( self );
      char string = k;
      lua_pushlstring( L, &string, 1 );
      lua_pushliteral( L, "character" );
      return push_result( L, self, -2, -1 );
    }
    
    return raise_error( L, self, "Invalid character constant", NULL );
  }

  // Otherwise the token is a symbol.
  {
    size_t length;
    
    switch ( parse_symbol( L, self, &length ) )
    {
    case TOOBIG:
      return raise_error( L, self, "Symbol too big", NULL );
      
    case INVALIDCHAR:
      {
        char string[ 2 ] = { *self->current, 0 };
        return raise_error( L, self, "Invalid character in input: '%s'", string );
      }
      
    case TOKEN:
      lua_pushlstring( L, start, length );
      return push_result( L, self, -1, -1 );
      
    case LINECOMMENTSTART:
      while ( *self->current != '\n' && *self->current != 0 )
      {
        skip( self );
      }
      
      lua_pushlstring( L, start, self->current - start );
      lua_pushliteral( L, "comment" );
      return push_result( L, self, -2, -1 );
      
    case BLOCKCOMMENTSTART:
      {
        int linenumber = self->line_number;
        
        for ( ;; )
        {
          int type = parse_symbol( L, self, &length );
          
          if ( type == INVALIDCHAR )
          {
            if ( *self->current == 0 )
            {
              self->line_number = linenumber;
              return raise_error( L, self, "Unterminated comment", NULL );
            }
            
            if ( *self->current == '\n' )
            {
              self->line_number++;
            }
            
            skip( self );
          }
          
          if ( type == BLOCKCOMMENTEND )
          {
            lua_pushlstring( L, start, self->current - start );
            lua_pushliteral( L, "comment" );
            return push_result( L, self, -2, -1 );
          }
        }
      }
    }
  }
  
  return 0; /* never reached */
}

static int lexer_gc( lua_State* L )
{
  lexer_t* self = (lexer_t*)lua_touserdata( L, 1 );
  
  luaL_unref( L, LUA_REGISTRYINDEX, self->source_ref );
  luaL_unref( L, LUA_REGISTRYINDEX, self->source_name_ref );
  luaL_unref( L, LUA_REGISTRYINDEX, self->keywords_ref );
  
  return 0;
}

static int create_lexer( lua_State* L )
{
  static const luaL_Reg methods[] =
  {
    { "next", next_token },
    { "__gc", lexer_gc },
    { NULL, NULL }
  };
  
  luaL_checktype( L, 1, LUA_TSTRING );  /* source code */
  luaL_checktype( L, 2, LUA_TSTRING );  /* source file name */
  luaL_checktype( L, 3, LUA_TTABLE );   /* keywords table */
  luaL_checktype( L, 4, LUA_TSTRING );  /* string quote */
  luaL_checktype( L, 5, LUA_TBOOLEAN ); /* case sensitive */
  luaL_checktype( L, 6, LUA_TBOOLEAN ); /* octal constants */

  lexer_t* self = (lexer_t*)lua_newuserdata( L, sizeof( lexer_t ) );
  
  if ( luaL_newmetatable( L, MY_NAME ) != 0 )
  {
    lua_pushvalue( L, -1 );
    lua_setfield( L, -2, "__index" );
    /*luaL_setfuncs( L, methods, 0 );*/
    luaL_setfuncs( L, methods, 0 );
  }
  
  lua_setmetatable( L, -2 );
  
  size_t length;
  lua_pushvalue( L, 1 );
  self->begin = lua_tolstring( L, -1, &length );
  self->source_ref = luaL_ref( L, LUA_REGISTRYINDEX );
  self->current = self->begin;
  self->end = self->begin + length;
  
  lua_pushvalue( L, 2 );
  self->source_name_ref = luaL_ref( L, LUA_REGISTRYINDEX );
  
  self->line_number = 1;
  
  lua_pushvalue( L, 3 );
  self->keywords_ref = luaL_ref( L, LUA_REGISTRYINDEX );
  
  const char* quote = lua_tostring( L, 4 );
  self->quote = quote[ 0 ];
  
  self->case_sensitive = lua_toboolean( L, 5 ) != 0;
  self->octals = lua_toboolean( L, 6 ) != 0;
  
  return 1;
}

LUALIB_API int luaopen_lexer( lua_State* L )
{
  static const luaL_Reg statics[] =
  {
    { "new", create_lexer },
    { NULL, NULL }
  };

  /*luaL_newlib( L, statics );*/
  lua_createtable( L, 0, sizeof( statics ) / sizeof( statics[ 0 ] ) - 1 );
  luaL_newlib( L, statics );
  
  lua_pushinteger( L, 1 );
  lua_setfield( L, -2, "token" );
  
  lua_pushinteger( L, 2 );
  lua_setfield( L, -2, "lineCommentStart" );
  
  lua_pushinteger( L, 3 );
  lua_setfield( L, -2, "blockCommentStart" );
  
  lua_pushinteger( L, 4 );
  lua_setfield( L, -2, "blockCommentEnd" );
  
  return 1;
}
