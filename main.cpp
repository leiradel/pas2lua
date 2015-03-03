#include <stdio.h>

extern "C"
{
  #include "lexer.h"
  #include <lua.h>
  #include <lauxlib.h>
  #include <lualib.h>
}

#include "main_lua.h"

static int do_buffer( lua_State* L, const char* buffer, size_t buffer_size, const char* chunk_name, int ret_count )
{
  if ( luaL_loadbuffer( L, buffer, buffer_size, chunk_name ) != 0 )
  {
    return lua_error( L );
  }
  
  lua_call( L, 0, ret_count );
  return 0;
}

static int lua_main( lua_State* L )
{
  /* Load lexer. */
  /*luaL_requiref( L, "lexer", luaopen_lexer, 1 );*/
  luaopen_lexer( L );
  lua_setglobal( L, "lexer" );
  
  /* Run required files, main.lua returns a function which is the main function. */
  do_buffer( L, main_lua, sizeof( main_lua ), "main.lua", 1 );

  /* Get the upvalues and create a table with the arguments passed on the command line. */
  int argc = (int)lua_tonumber( L, lua_upvalueindex( 1 ) );
  const char** argv = (const char**)lua_touserdata( L, lua_upvalueindex( 2 ) );
  
  lua_newtable( L );
  
  int i;
  
  for ( i = 1; i < argc; i++ )
  {
    lua_pushstring( L, argv[ i ] );
    lua_rawseti( L, -2, i );
  }
  
  /* Run the main function and return. */
  lua_call( L, 1, 1 );
  luaL_checkinteger( L, -1 );
  return 1;
}

static int traceback( lua_State* L )
{
  /* Change the error into a detailed stack trace. */
  luaL_traceback( L, L, lua_tostring( L, -1 ), 1 );
  return 1;
}

int main( int argc, const char* argv[] )
{
  /* Create the state. */
  lua_State* L = luaL_newstate();
  
  /* Open the standard libraries and clean the stack. */
  int top = lua_gettop( L );
  luaL_openlibs( L );
  lua_settop( L, top );
  
  /* Put the traceback function on the stack. */
  lua_pushcfunction( L, traceback );
  
  /* Create a closure with argc and argv. */
  lua_pushnumber( L, argc );
  lua_pushlightuserdata( L, (void*)argv );
  lua_pushcclosure( L, lua_main, 2 );
  
  /* Call main_lua. */
  int ret = 0;

  if ( lua_pcall( L, 0, 1, -2 ) == /*LUA_OK*/ 0 )
  {
    ret = lua_tointeger( L, -1 );
  }
  else
  {
    fprintf( stderr, "%s", lua_tostring( L, -1 ) );
    ret = 1;
  }
  
  return ret;
}
