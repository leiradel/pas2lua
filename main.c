#include <stdio.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include "lexer.h"

#include "lua/class.h"
#include "lua/parser.h"
#include "lua/dfm2pas.h"
#include "lua/main.h"

#include "units/classes.h"
#include "units/controls.h"
#include "units/dialogs.h"
#include "units/extctrls.h"
#include "units/fmod.h"
#include "units/fmodtypes.h"
#include "units/forms.h"
#include "units/graphics.h"
#include "units/jpeg.h"
#include "units/math.h"
#include "units/messages.h"
#include "units/registry.h"
#include "units/stdctrls.h"
#include "units/system.h"
#include "units/sysutils.h"
#include "units/windows.h"

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
  
  lua_settop( L, top );
}

static unsigned djb2( const char* str )
{
  const unsigned char* aux = (const unsigned char*)str;
  unsigned hash = 5381;
  
  while ( *aux )
  {
    hash = ( hash << 5 ) + hash + *aux++;
  }
  
  return hash;
}

static int do_buffer( lua_State* L, const char* buffer, size_t buffer_size, const char* chunk_name, int ret_count )
{
  if ( luaL_loadbuffer( L, buffer, buffer_size, chunk_name ) != 0 )
  {
    return lua_error( L );
  }
  
  lua_call( L, 0, ret_count );
  return ret_count;
}

static int load_unit( lua_State* L )
{
  const char* name = luaL_checkstring( L, 1 );
  
  switch ( djb2( name ) )
  {
  case 0xcb8e8f13U: // classes
    return do_buffer( L, units_classes_lua, sizeof( units_classes_lua ), name, 1 );
  case 0x42b3ee19U: // controls
    return do_buffer( L, units_controls_lua, sizeof( units_controls_lua ), name, 1 );
  case 0x11856a88U: // dialogs
    return do_buffer( L, units_dialogs_lua, sizeof( units_dialogs_lua ), name, 1 );
  case 0xdcd0335eU: // extctrls
    return do_buffer( L, units_extctrls_lua, sizeof( units_extctrls_lua ), name, 1 );
  case 0x7c96dc8bU: // fmod
    return do_buffer( L, units_fmod_lua, sizeof( units_fmod_lua ), name, 1 );
  case 0x45f4c9a0U: // fmodtypes
    return do_buffer( L, units_fmodtypes_lua, sizeof( units_fmodtypes_lua ), name, 1 );
  case 0x0f73950cU: // forms
    return do_buffer( L, units_forms_lua, sizeof( units_forms_lua ), name, 1 );
  case 0xbc08ef36U: // graphics
    return do_buffer( L, units_graphics_lua, sizeof( units_graphics_lua ), name, 1 );
  case 0x7c99198bU: // jpeg
    return do_buffer( L, units_jpeg_lua, sizeof( units_jpeg_lua ), name, 1 );
  case 0x7c9a80cfU: // math
    return do_buffer( L, units_math_lua, sizeof( units_math_lua ), name, 1 );
  case 0x870e1c9dU: // messages
    return do_buffer( L, units_messages_lua, sizeof( units_messages_lua ), name, 1 );
  case 0x07ae803eU: // registry
    return do_buffer( L, units_registry_lua, sizeof( units_registry_lua ), name, 1 );
  case 0x6f2e5a98U: // stdctrls
    return do_buffer( L, units_stdctrls_lua, sizeof( units_stdctrls_lua ), name, 1 );
  case 0x1ceee48aU: // system
    return do_buffer( L, units_system_lua, sizeof( units_system_lua ), name, 1 );
  case 0x14547e95U: // sysutils
    return do_buffer( L, units_sysutils_lua, sizeof( units_sysutils_lua ), name, 1 );
  case 0xc8feca70U: // windows
    return do_buffer( L, units_windows_lua, sizeof( units_windows_lua ), name, 1 );
  }
  
  return luaL_error( L, "unit %s not found", name );
}

static int lua_main( lua_State* L )
{
  /* Register the builtin searcher */
  lua_pushcfunction( L, load_unit );
  lua_setglobal( L, "loadunit" );
  
  /* Load lexer. */
  /*luaL_requiref( L, "lexer", luaopen_lexer, 1 );*/
  luaopen_lexer( L );
  lua_setglobal( L, "lexer" );
  
  do_buffer( L, lua_class_lua, sizeof( lua_class_lua ), "class.lua", 1 );
  lua_setglobal( L, "class" );
  
  do_buffer( L, lua_dfm2pas_lua, sizeof( lua_dfm2pas_lua ), "dfm2pas.lua", 1 );
  lua_setglobal( L, "dfm2pas" );
  
  do_buffer( L, lua_parser_lua, sizeof( lua_parser_lua ), "parser.lua", 1 );
  lua_setglobal( L, "Parser" );
  
  /* Run required files, main.lua returns a function which is the main function. */
  do_buffer( L, lua_main_lua, sizeof( lua_main_lua ), "main.lua", 1 );

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
