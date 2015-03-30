--[[
Copyright (c) 2010–2014 André Leiradella

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

* The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE. 
]]

local M = {}

local pairs = pairs
local type = type
local sub = string.sub
local unpack = unpack
local setmetatable = setmetatable
local _G = _G

function M.new( ... )
  local arg = { ... }
  -- create an empty class
  local new_class = {}
  
  -- copy all methods from the super classes
  for index = 1, #arg do
    for name, method in pairs( arg[ index ] ) do
      if not new_class[ name ] then
        new_class[ name ] = method
      end
    end
  end
  
  -- insert an additional method to check the class of the instance
  new_class.instanceOf = function( self, klass )
    if klass == new_class then
      return true
    end
    
    for index = 1, #arg do
      if arg[ index ].instanceOf( self, klass ) then
        return true
      end
    end
    
    return false
  end
  
  -- insert an additional method to clone the instance
  new_class.clone = function( self )
    local function dup( obj, dupped )
      if type( obj ) == 'table' then
        if dupped[ obj ] then
          return dupped[ obj ]
        end
        
        local tab = {}
        dupped[ obj ] = tab
        
        for key, value in pairs( obj ) do
          tab[ dup( key, dupped ) ] = dup( value, dupped )
        end
        
        return tab
      end
      
      return obj
    end
    
    local clone, dupped = new_class(), {}
    for key, value in pairs( self ) do
      clone[ key ] = dup( value, dupped )
    end
    
    return clone
  end
  
  -- insert an additional method to return the class of an instance
  new_class.getClass = function()
    return new_class
  end
  
  -- insert an additional method to return the class name of an instance (only works if the class is accessible from the global space)
  new_class.getClassName = function()
    local function find( space, name, visited )
      if visited[ space ] then
        return nil
      end
      
      visited[ space ] = true
      
      for key, value in pairs( space ) do
        if value == new_class then
          return name .. '.' .. key
        end
        
        if type( value ) == 'table' then
          local found = find( value, name .. '.' .. key, visited )
          
          if found ~= nil then
            return found
          end
        end
      end
      
      return nil
    end
    
    local found = find( _G, '_G', {} )
    
    if found then
      return sub( found, 4, -1 )
    end
    
    return nil
  end
  
  -- serialize the instance into a string which can be used to get the instance back
  new_class.tostring = function( self, indent )
    local function ser( tab, indent )
      indent = indent or 0
      local spaces = ( ' ' ):rep( indent )
      local str = { '{\n' }
      
      for _, value in ipairs( tab ) do
        str[ #str + 1 ] = spaces
        str[ #str + 1 ] = '  '
        
        local t = type( value )
        
        if t == 'string' then
          str[ #str + 1 ] = string.format( '%q', value )
        elseif t == 'table' then
          if value.tostring then
            str[ #str + 1 ] = value:tostring( indent + 2 )
          else
            str[ #str + 1 ] = ser( value, indent + 2 )
          end
        elseif t == 'boolean' then
          str[ #str + 1 ] = value and 'true' or 'false'
        else
          str[ #str + 1 ] = tostring( value )
        end
        
        str[ #str + 1 ] = ',\n'
      end
      
      for key, value in pairs( tab ) do
        if type( key ) ~= 'number' then
          str[ #str + 1 ] = spaces
          str[ #str + 1 ] = '  '
          
          if key:match( '^[A-Za-z_][[A-Za-z_0-9]*$' ) then
            str[ #str + 1 ] = key
          else
            str[ #str + 1 ] = '[ '
            str[ #str + 1 ] = string.format( '%q', key )
            str[ #str + 1 ] = ' ]'
          end
          
          str[ #str + 1 ] = ' = '
          
          local t = type( value )
          
          if t == 'string' then
            str[ #str + 1 ] = string.format( '%q', value )
          elseif t == 'table' then
            if value.tostring then
              str[ #str + 1 ] = value:tostring( indent + 2 )
            else
              str[ #str + 1 ] = ser( value, indent + 2 )
            end
          elseif t == 'boolean' then
            str[ #str + 1 ] = value and 'true' or 'false'
          else
            str[ #str + 1 ] = tostring( value )
          end
          
          str[ #str + 1 ] = ',\n'
        end
      end
      
      str[ #str + 1 ] = spaces
      str[ #str + 1 ] = '}'
      
      return table.concat( str )
    end
    
    local str = { self:getClassName(), '.makeInstance(', ser( self, indent ), ')' }
    return table.concat( str )
  end
  
  -- an alias for __tostring
  new_class.__tostring = new_class.tostring

  -- the metatable of the instances
  local self_meta = { __index = new_class }
  
  -- turn the self table into an instance of the class
  new_class.makeInstance = function( self )
    -- set the metatable
    setmetatable( self, self_meta )
    return self
  end

  -- create a __call metamethod that creates a new instance of the class
  local class_meta = {}
  
  class_meta.__call = function( ... )
    local arg = { ... }
    
    -- create an empty instance
    local self = {}
    new_class.makeInstance( self )
    
    -- the first argument is the class, shift left all other arguments
    for i = 2, #arg do
      arg[ i - 1 ] = arg[ i ]
    end
    
    arg[ #arg ] = nil
    
    -- call the new method to initialize the instance
    if new_class.new then
      new_class.new( self, unpack( arg ) )
    end
    
    -- return the newly created instance
    return self
  end

  -- set the metatable of the class
  setmetatable( new_class, class_meta )
  
  -- return it
  return new_class
end

function M.instanceOf( instance, class )
  return type( instance ) == 'table' and instance.instanceOf and instance.instanceOf( class )
end

function M.abstract()
  local proxy = {}
  
  proxy.__call =  function( proxy, self )
    local klass = self:getClass()
    local methodName = '?'
    
    for name, method in pairs( klass ) do
      if method == proxy then
        methodName = name
        break
      end
    end
    
    error( 'The method ' .. ( self:getClassName() or '?' ) .. '.' .. methodName .. ' is abstract, please implement it.' )
  end
  
  setmetatable( proxy, proxy )
  return proxy
end

return M
