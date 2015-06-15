--
--  SDL.t
--
--  Copyright 2015 Gilbert Bernstein
--
--  Licensed under the Apache License, Version 2.0 (the "License");
--  you may not use this file except in compliance with the License.
--  You may obtain a copy of the License at
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
--  Unless required by applicable law or agreed to in writing, software
--  distributed under the License is distributed on an "AS IS" BASIS,
--  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--  See the License for the specific language governing permissions and
--  limitations under the License.
--

local SDL = {}
package.loaded['SDL'] = SDL

---------------------------------------------

local ffi = require 'ffi'
local bit = require 'bit'
local function isbitset(flag, word)
  return bit.band(flag, word) == flag
end
local function setbit(flag, bool_val, word)
  if bool_val then
    return bit.bor(flag, word)
  else
    return bit.band(b.bnot(flag), word)
  end
end

local function exec2str(cmd)
  local file    = io.popen(cmd)
  local output  = file:read('*line')
  file:close()
  return output
end
local function exec2code(cmd)
  local code = os.execute(cmd)
  return code
end

if ffi.os ~= 'OSX' then
  print('sorry, this script only supports mac loading of SDL right now')
end

-- link the SDL library
local sdl_libflags    = exec2str('sdl2-config --libs')
local sdl_libdir      = sdl_libflags:match('-L([^%s]*)')
local sdl_libname     = sdl_libflags:match('-l([^%s]*)')
local sdl_libpath     = sdl_libdir..'/lib'..sdl_libname..'.dylib'
local sdl_gfxlibpath  = sdl_libdir..'/libSDL2_gfx.dylib'
local sdl_imglibpath  = sdl_libdir..'/libSDL2_image.dylib'
local sdl_ttflibpath  = sdl_libdir..'/libSDL2_ttf.dylib'
-- on mac use dylib
--print('linking sdl library found at '..sdl_libpath)
terralib.linklibrary(sdl_libpath)
--print('linking sdl gfx library found at '..sdl_gfxlibpath)
terralib.linklibrary(sdl_gfxlibpath)
--print('linking sdl image library found at '..sdl_imglibpath)
terralib.linklibrary(sdl_imglibpath)
--print('linking sdl ttf library found at '..sdl_ttflibpath)
terralib.linklibrary(sdl_ttflibpath)

-- Link the Cairo Library
local cairo_libpath   = '/usr/local/lib/libcairo.dylib'
if exec2code('test -f '..cairo_libpath) ~= 0 then
  error('Could not find cairo shared library at '..cairo_libpath)
end
--print('linking cairo library found at '..cairo_libpath)
terralib.linklibrary(cairo_libpath)


-- put the SDL header files on the path
local sdl_cflags      = exec2str('sdl2-config --cflags')
local sdl_includedir  = sdl_cflags:match('-I([^%s]*)')
local cairo_includedir = '/usr/local/include/cairo'
--print('setting sdl include directory to '..sdl_includedir)
--print('setting cairo include directory to '..cairo_includedir)
terralib.includepath  = terralib.includepath .. ';' .. sdl_includedir
                                             .. ';' .. cairo_includedir

local C = terralib.includecstring [[
#include "stdlib.h"
#include "stdio.h"
#include "SDL.h"
#include "cairo.h"
#include "SDL2_gfxPrimitives.h"
#include "SDL_image.h"
#include "SDL_ttf.h"

FILE * __get__stdout() { return stdout; }
FILE * __get__stdin()  { return stdin; }
FILE * __get__stderr() { return stderr; }

uint __get__sdl_button_lmask()  { return SDL_BUTTON_LMASK;  }
uint __get__sdl_button_mmask()  { return SDL_BUTTON_MMASK;  }
uint __get__sdl_button_rmask()  { return SDL_BUTTON_RMASK;  }
uint __get__sdl_button_x1mask() { return SDL_BUTTON_X1MASK; }
uint __get__sdl_button_x2mask() { return SDL_BUTTON_X2MASK; }

uint __get__kmod_ctrl()  { return KMOD_CTRL; }
uint __get__kmod_shift() { return KMOD_SHIFT; }
uint __get__kmod_alt()   { return KMOD_ALT; }
uint __get__kmod_gui()   { return KMOD_GUI; }
]]

rawset(C, 'stdout', C.__get__stdout())
rawset(C, 'stdin',  C.__get__stdin())
rawset(C, 'stderr', C.__get__stderr())

rawset(C, 'SDL_BUTTON_LMASK',  C.__get__sdl_button_lmask())
rawset(C, 'SDL_BUTTON_MMASK',  C.__get__sdl_button_mmask())
rawset(C, 'SDL_BUTTON_RMASK',  C.__get__sdl_button_rmask())
rawset(C, 'SDL_BUTTON_X1MASK', C.__get__sdl_button_x1mask())
rawset(C, 'SDL_BUTTON_X2MASK', C.__get__sdl_button_x2mask())

rawset(C, 'KMOD_CTRL',  C.__get__kmod_ctrl())
rawset(C, 'KMOD_SHIFT', C.__get__kmod_shift())
rawset(C, 'KMOD_ALT',   C.__get__kmod_alt())
rawset(C, 'KMOD_GUI',   C.__get__kmod_gui())


local function SafeHeapAlloc(ttype, finalizer)
  if not finalizer then finalizer = C.free end
  local ptr = terralib.cast( &ttype, C.malloc(terralib.sizeof(ttype)) )
  ffi.gc( ptr, finalizer )
  return ptr
end



---------------------------------------------
-- SDL ERROR HANDLING
---------------------------------------------

local error_buffer_size = 2048
local error_buffer = global(int8[error_buffer_size])
local function terror_body (basemsg, file, line)
  local prelude = file..':'..tostring(line)..': Error\n'
  return quote do
    var sdlerr = C.SDL_GetError()
    if sdlerr ~= nil and @sdlerr ~= 0 then
      C.snprintf(error_buffer, error_buffer_size,
                 [prelude..'%s\n%s\n'], basemsg, sdlerr)
      C.SDL_ClearError()
    else
      C.snprintf(error_buffer, error_buffer_size,
                 [prelude..'%s\n'], basemsg)
    end
    C.fprintf(C.stderr, error_buffer)
    C.exit(1)
  end end
end

SDL.error = macro(
-- Terra interpretation
function( basemsg )
  if not basemsg then error('SDL.error() requires SOME argument') end
  local filename = basemsg.tree.filename
  local linenumber = basemsg.tree.linenumber
  return terror_body(basemsg, filename, linenumber)
end,
-- Lua interpretation
function( basemsg, level )
  level = (level or 1) + 1
  local sdlerr = ffi.string(C.SDL_GetError())
  if sdlerr and #sdlerr > 0 then
    C.SDL_ClearError()
    error(basemsg..':\n'..sdlerr, level)
  else
    error(basemsg, level)
  end
end)

SDL.assert = macro(
-- Terra interpretation
function(test)
  return quote
    if not test then
      [terror_body('Assert Failed',
                   test.tree.filename,
                   test.tree.linenumber)]
    end
  end
end,
-- Lua interpretation
function ( test, level )
  level = (level or 1) + 1
  if not test then
    SDL.error('SDL Assert Failure')
  end
end)





---------------------------------------------
-- Cairo Context Wrapper and Error Handling
---------------------------------------------

local terra CairoStatus( code : C.cairo_status_t ) : rawstring
  if code == C.CAIRO_STATUS_SUCCESS then
    return nil
  else
    return C.cairo_status_to_string(code)
  end
end

local CairoAssert = macro(
-- Terra interpretation
function( code )
  local filename = code.tree.filename
  local linenumber = code.tree.linenumber
  local prefix = filename..':'..tostring(linenumber)..': Assert Fail\n'
  return quote do
    var stat_str = CairoStatus(code)
    if stat_str ~= nil then
      C.fprintf(C.stderr, [prefix..'%s\n'], stat_str)
      C.exit(1)
    end
  end end
end,
-- Lua Interpretation
function( code )
  local stat_str = CairoStatus(code)
  if stat_str ~= nil then
    local str = ffi.string(stat_str)
    error(str, 2)
  end
end)


local terratimer = terralib.cast({}->double, terralib.currenttimeinseconds)

-- ARGB layout masks
local A_MASK = 0xff000000
local R_MASK = 0x00ff0000
local G_MASK = 0x0000ff00
local B_MASK = 0x000000ff
local struct CairoContext {
  _ptr      : &C.cairo_t,
  _surface  : &C.cairo_surface_t,
  _texture  : &C.SDL_Texture,
  _sdlsurf  : &C.SDL_Surface,
  _isopen   : bool,
  _w        : int,
  _h        : int
}

local terra zero_out_cairo_ctxt( ctxt : &CairoContext )
  ctxt._ptr     = nil
  ctxt._surface = nil
  ctxt._texture = nil
  ctxt._sdlsurf = nil
  ctxt._isopen  = false
end
terra CairoContext:init( w : int, h : int )
  -- Create Cairo Surface
  self._surface = C.cairo_image_surface_create(C.CAIRO_FORMAT_ARGB32, w, h)
    CairoAssert(C.cairo_surface_status(self._surface))

  -- Bind the Cairo surface into an SDL surface
  var pixels    = C.cairo_image_surface_get_data(self._surface)
  var rowstride = C.cairo_image_surface_get_stride(self._surface) -- in Bytes
  self._sdlsurf = C.SDL_CreateRGBSurfaceFrom( pixels, w, h, 32, rowstride,
                                              R_MASK, G_MASK, B_MASK, A_MASK )
    SDL.assert(self._sdlsurf ~= nil)

  self._w  = w
  self._h  = h
end
terra CairoContext:deinit()
  if self:isOpen() then self:close() end

  C.SDL_FreeSurface(self._sdlsurf)
  self._sdlsurf = nil
  C.cairo_surface_destroy(self._surface)
  self._surface = nil
end
terra CairoContext:isInitialized()
  return self._surface ~= nil
end

terra CairoContext:open()
  -- open the Cairo context
  self._ptr     = C.cairo_create(self._surface)
    CairoAssert(C.cairo_status(self._ptr))
end
terra CairoContext:close()
  -- close the Cairo context
  C.cairo_destroy(self._ptr)
  self._ptr = nil
end
terra CairoContext:isOpen()
  return self._ptr ~= nil
end
terra CairoContext:flushAndClose(
  win : &C.SDL_Window
)
  if not self:isOpen() then
    SDL.error('Cannot Flush Un-opened Context')
  end

  -- get the window target
  var winsurf = C.SDL_GetWindowSurface(win)
    SDL.assert(winsurf ~= nil)

  -- Blit from the cairo-backed surface to the window
  var dstrect = C.SDL_Rect { x=0, y=0, w=self._w, h=self._h }
  SDL.assert(C.SDL_UpperBlit( self._sdlsurf, nil, winsurf, &dstrect ) == 0)

  -- refresh window
  SDL.assert(C.SDL_UpdateWindowSurface(win) == 0)

  self:close()
end




---------------------------------------------
-- MAIN INITIALIZATION AND TEARDOWN
---------------------------------------------

local sdl_flags = 0
sdl_flags = bit.bor(sdl_flags, C.SDL_INIT_VIDEO)
sdl_flags = bit.bor(sdl_flags, C.SDL_INIT_TIMER)

terra SDL.Init()
  -- do initialization and check for errors
  SDL.assert(C.SDL_Init(sdl_flags) == 0)
  -- register the corresponding cleanup function
  C.atexit(C.SDL_Quit)

  -- GFX extension does not need initialization

  -- IMG extension initialization is just an optimization...

  -- init TTF extension and register cleanup
  SDL.assert(C.TTF_Init() == 0)
  C.atexit(C.TTF_Quit)
end

--terra SDL.Version()
--  -- get the SDL version...
--  var version : C.SDL_version
--  C.SDL_GetVersion(&version)
--  return version.major, version.minor, version.patch
--end


---
-- SDL Display Functions
----

terra SDL.GetDisplayBounds()
  var rect : C.SDL_Rect
  SDL.assert(C.SDL_GetDisplayBounds(0, &rect) == 0)
  return rect.x, rect.y, rect.w, rect.h
end

terra SDL.HasOnlyOneDisplay()
  return C.SDL_GetNumVideoDisplays() == 1
end


---------------------------------------------
-- SDL Window Basics
---------------------------------------------

-- Declare window object
--local Window = {}
--Window.__index = Window

local struct Window {
  _ptr            : &C.SDL_Window,
  _color          : struct { r : uint8, g : uint8, b : uint8, a : uint8 },
  _cairo          : CairoContext,
  _renderer       : &C.SDL_Renderer
  _cursor_hidden  : struct {
    x              : int32,
    y              : int32,
    is_hidden      : bool,
  },
}
SDL.Window = Window

local WINDOW_POS_UNDEFINED  = C.SDL_WINDOWPOS_UNDEFINED_MASK
local DEFAULT_WINDOW_WIDTH  = 640
local DEFAULT_WINDOW_HEIGHT = 480
local DEFAULT_WINDOW_NAME = 'unnamed SDL window'
function SDL.NewWindow(params)
  params = params or {}

  local x = params.x or WINDOW_POS_UNDEFINED
  local y = params.y or WINDOW_POS_UNDEFINED
  local w = params.w or DEFAULT_WINDOW_WIDTH
  local h = params.h or DEFAULT_WINDOW_HEIGHT
  local name = params.name or DEFAULT_WINDOW_NAME

  local flags = 0
  if params.hidden then flags = bit.bor(flags, C.SDL_WINDOW_HIDDEN)
                   else flags = bit.bor(flags, C.SDL_WINDOW_SHOWN) end
  if params.noborder then flags = bit.bor(flags, C.SDL_WINDOW_BORDERLESS) end
  if params.resizable then flags = bit.bor(flags, C.SDL_WINDOW_RESIZABLE) end
  if params.focus  then flags = bit.bor(flags, C.SDL_WINDOW_INPUT_FOCUS) end
  --flags = bit.bor(flags, C.SDL_WINDOW_OPENGL)

  local window = SafeHeapAlloc(Window, function(ptr)
    ptr:destroy()
    C.free(ptr)
  end)
  --local window = terralib.new(Window)
  window._ptr = C.SDL_CreateWindow(name, x,y,w,h, flags)
  SDL.assert(window._ptr ~= nil)
  zero_out_cairo_ctxt(window._cairo)

  --window._renderer = C.SDL_CreateRenderer(window._ptr, -1, 0)
  --SDL.assert(window._renderer ~= nil)

  --print('INIT: ', w, h)
  window._cairo:init( w, h )

  --C.SDL_GL_SetAttribute(C.SDL_GL_SHARE_WITH_CURRENT_CONTEXT, 1)
  --local glcontext      = SDL_GL_CreateContext(window._ptr)
  --SDL.assert(glcontext ~= nil)

  --SDL_GL_MakeCurrent(window._ptr, nil);
  --SDL.assert(SDL_GL_MakeCurrent(window._ptr, glcontext) == 0)


  if params.minw and params.minh then
    window:setMinWH(params.minw, params.minh)
  end
  if params.maxw and params.maxh then
    window:setMaxWH(params.maxw, params.maxh)
  end

  -- hide this window in the SDL window
  C.SDL_SetWindowData(window._ptr, 'wrapper_window', window)

  return window
end
local terra GetWindowFromID(id : uint32) : &Window
  var win_ptr   = C.SDL_GetWindowFromID(id)
  var window    = [&Window](C.SDL_GetWindowData(win_ptr, 'wrapper_window'))
  SDL.assert(window._ptr == win_ptr)
  return window
end
-- will get called at start because of resize event
local terra handleWindowResize( win : &Window, w : int, h : int )
  --C.printf('\n***\n*** DOING window resize %p %d %d\n***\n', win, w, h)
  win._cairo:deinit()
  win._cairo:init( w, h )-- win._renderer )
end
terra Window:destroy()
    --C.SDL_GL_MakeCurrent(self._ptr, nil);
    --C.SDL_GL_DeleteContext(glcontext)
  if self._cairo:isInitialized() then self._cairo:deinit() end
  --C.SDL_DestroyRenderer(self._renderer)
  C.SDL_DestroyWindow(self._ptr)
  self._ptr = nil
end

-- Title
terra Window:getTitle()
  return C.SDL_GetWindowTitle(self._ptr)
end
terra Window:setTitle( str : rawstring )
  C.SDL_SetWindowTitle(self._ptr, str)
end

-- Hidden or Shown Window State/Toggle
terra Window:isHidden()
  return (C.SDL_GetWindowFlags(self._ptr) and C.SDL_WINDOW_SHOWN) ~= 0
end
terra Window:isShown()
  return (C.SDL_GetWindowFlags(self._ptr) and C.SDL_WINDOW_HIDDEN) ~= 0
end
terra Window:show()
  C.SDL_ShowWindow(self._ptr)
end
terra Window:hide()
  C.SDL_HideWindow(self._ptr)
end

-- Window Size and Position
terra Window:getBounds()
  var x : int, y : int, w : int, h : int
  C.SDL_GetWindowPosition(self._ptr, &x, &y)
  C.SDL_GetWindowSize(self._ptr, &w, &h)
  return x,y,w,h
end
-- pass -1 to default to existing value
terra Window:setBounds( x:int, y:int, w:int, h:int )
  if x < 0 or y < 0 or w < 0 or h < 0 then
    var bx,by,bw,bh = self:getBounds()
    if x < 0 then x = bx end
    if y < 0 then y = by end
    if w < 0 then w = bw end
    if h < 0 then h = bh end
  end
  C.SDL_SetWindowPosition(self._ptr, x, y)
  C.SDL_SetWindowSize(self._ptr, w, h)
end

terra Window:getMinWH()
  var w : int
  var h : int
  C.SDL_GetWindowMinimumSize(self._ptr, &w, &h)
  return w, h
end
terra Window:getMaxWH()
  var w : int
  var h : int
  C.SDL_GetWindowMaximumSize(self._ptr, &w, &h)
  return w, h
end
terra Window:setMinWH( w : int, h : int )
  C.SDL_SetWindowMinimumSize(self._ptr, w, h)
end
terra Window:setMaxWH( w : int, h : int )
  C.SDL_SetWindowMaximumSize(self._ptr, w, h)
end



-- Alerts
--local function mboxflags(params)
--  if params.error then
--    return C.SDL_MESSAGEBOX_ERROR
--  elseif params.warning then
--    return C.SDL_MESSAGEBOX_WARNING
--  else
--    return C.SDL_MESSAGEBOX_INFORMATION
--  end
--end
-- Window-specific alert
terra Window:alert( title : rawstring, msg : rawstring )
  SDL.assert(C.SDL_ShowSimpleMessageBox(C.SDL_MESSAGEBOX_INFORMATION,
                                        title, msg, self._ptr) == 0)
end
-- General alert
terra SDL.alert( title : rawstring, msg : rawstring )
  SDL.assert(C.SDL_ShowSimpleMessageBox(C.SDL_MESSAGEBOX_INFORMATION,
                                        title, msg, nil) == 0)
end

-- Not worrying about the following, but maybe I should?
-- SDL_SetWindowHitTest


-----------------------------------------------------------------
-- Cairo State
-----------------------------------------------------------------

terra Window:cairoAssertOk()
  CairoAssert(C.cairo_status(self._cairo._ptr))
end

terra Window:cairoBegin()
  --var x,y,w,h = self:getBounds()
  --self._cairo:init(w,h, self._renderer)
  self._cairo:open()
  self:setColor(0,0,0)
end
terra Window:cairoEnd()
  self._cairo:flushAndClose( self._ptr)--, self._renderer )
  --var x,y,w,h = self:getBounds()
  --self._cairo:flushAndDestroy(self._ptr, self._renderer, w,h)
end
terra Window:isCairoOpen()
  return self._cairo:isOpen()
end

terra Window:cairoSave()
  C.cairo_save(self._cairo._ptr)
end
terra Window:cairoRestore()
  C.cairo_restore(self._cairo._ptr)
end



-----------------------------------------------------------------
-- Cairo Drawing State
-----------------------------------------------------------------

local terra rgba_0_1( r : uint8, g : uint8, b : uint8, a : uint8 )
  return [double](r)/255.0, [double](g)/255.0,
         [double](b)/255.0, [double](a)/255.0
end
local terra set_color_helper(
  win : &Window, r : uint8, g : uint8, b : uint8, a : uint8
)
  win._color.r=r
  win._color.g=g
  win._color.b=b
  win._color.a=a
  var dr,dg,db,da = rgba_0_1(r,g,b,a)
  C.cairo_set_source_rgba(win._cairo._ptr, dr,dg,db,da)
end
terra Window:setColor( r : uint8, g : uint8, b : uint8, a : uint8 )
  set_color_helper(self, r,g,b,a)
end
terra Window:setColor( r : uint8, g : uint8, b : uint8 )
  set_color_helper(self, r,g,b,255)
end
terra Window:getColor()
  var c = self._color
  return c.r, c.g, c.b, c.a
end

-- measurements correspond to user-space at time of stroking not of call
terra Window:setDash( dashes : &double, n_dashes : uint )
  C.cairo_set_dash(self._cairo._ptr, dashes, n_dashes, 0)
end

terra Window:setLineCapTo_Butt()
  C.cairo_set_line_cap(self._cairo._ptr, C.CAIRO_LINE_CAP_BUTT)
end
terra Window:setLineCapTo_Round()
  C.cairo_set_line_cap(self._cairo._ptr, C.CAIRO_LINE_CAP_ROUND)
end
terra Window:setLineCapTo_Square()
  C.cairo_set_line_cap(self._cairo._ptr, C.CAIRO_LINE_CAP_SQUARE)
end

terra Window:setLineJoinTo_Miter()
  C.cairo_set_line_join(self._cairo._ptr, C.CAIRO_LINE_JOIN_MITER)
end
terra Window:setLineJoinTo_Round()
  C.cairo_set_line_join(self._cairo._ptr, C.CAIRO_LINE_JOIN_ROUND)
end
terra Window:setLineJoinTo_Bevel()
  C.cairo_set_line_join(self._cairo._ptr, C.CAIRO_LINE_JOIN_BEVEL)
end

-- measurements correspond to user-space at time of stroking not of call
terra Window:setLineWidth( w : double )
  C.cairo_set_line_width(self._cairo._ptr, w)
end

-- miter while   miter_length / line_width <= limit
terra Window:setLineMiterLimit( limit : double )
  C.cairo_set_miter_limit(self._cairo._ptr, limit)
end

--function Window:setCompositing(mode)
--end



-----------------------------------------------------------------
-- Paths and Drawing Commands
-----------------------------------------------------------------

terra Window:beginPath()
  C.cairo_new_path(self._cairo._ptr)
end
-- can close multiple times for a beginPath call to
-- create multiple sub-paths
terra Window:closePath()
  C.cairo_close_path(self._cairo._ptr)
end

terra Window:rectangle( x:double, y:double, w:double, h:double )
  C.cairo_rectangle(self._cairo._ptr, x,y,w,h)
end

terra Window:moveTo( x:double, y:double )
  C.cairo_move_to(self._cairo._ptr, x,y)
end
terra Window:curveTo(
  x1:double,y1:double, x2:double,y2:double, x3:double,y3:double
)
  C.cairo_curve_to(self._cairo._ptr, x1,y1, x2,y2, x3,y3)
end
terra Window:lineTo( x:double, y:double )
  C.cairo_line_to(self._cairo._ptr, x,y)
end
terra Window:moveRel( dx:double, dy:double )
  C.cairo_rel_move_to(self._cairo._ptr, dx,dy)
end
terra Window:curveRel(
  dx1:double,dy1:double, dx2:double,dy2:double, dx3:double,dy3:double
)
  C.cairo_rel_curve_to(self._cairo._ptr, dx1,dy1, dx2,dy2, dx3,dy3)
end
terra Window:lineRel( dx:double, dy:double )
  C.cairo_rel_line_to(self._cairo._ptr, dx,dy)
end

-- Do the stroking or filling
terra Window:stroke()
  C.cairo_stroke(self._cairo._ptr)
end
terra Window:fill()
  C.cairo_fill(self._cairo._ptr)
end
terra Window:strokeAndKeepPath()
  C.cairo_stroke_preserve(self._cairo._ptr)
end
terra Window:fillAndKeepPath()
  C.cairo_fill_preserve(self._cairo._ptr)
end
terra Window:clear()
  C.cairo_paint(self._cairo._ptr)
end

-- Alternately, we can use paths to create clipping shapes
terra Window:clip()
  C.cairo_clip(self._cairo._ptr)
end
terra Window:resetClip()
  C.cairo_reset_clip(self._cairo._ptr)
end


-----------------------------------------------------------------
-- Fonts and Text
-----------------------------------------------------------------

local Font = {}
Font.__index = Font

local struct Font { _ptr : &C.TTF_Font }
SDL.Font = Font

terra SDL.OpenFont( font_file : rawstring, font_size : int )
  var font = Font {
    _ptr = C.TTF_OpenFont(font_file, font_size)
  }
  SDL.assert(font._ptr ~= nil)

  return font
end

terra Font:close()
  C.TTF_CloseFont(self._ptr)
  self._ptr = nil
end

local terra test_bit( bit : int, flags : int )
  return flags and bit == bit
end
local terra set_bit( val : bool, bit : int, flags : int )
  if val then return flags or bit
         else return flags and (not bit) end
end
terra Font:isBold()
  return test_bit(C.TTF_STYLE_BOLD, C.TTF_GetFontStyle(self._ptr))
end
terra Font:isItalic()
  return test_bit(C.TTF_STYLE_ITALIC, C.TTF_GetFontStyle(self._ptr))
end
terra Font:isUnderline()
  return test_bit(C.TTF_STYLE_UNDERLINE, C.TTF_GetFontStyle(self._ptr))
end
terra Font:isStrikethrough()
  return test_bit(C.TTF_STYLE_STRIKETHROUGH, C.TTF_GetFontStyle(self._ptr))
end
terra Font:setBold( val : bool )
  var flags = set_bit(val, C.TTF_STYLE_BOLD, C.TTF_GetFontStyle(self._ptr))
  C.TTF_SetFontStyle(self._ptr, flags)
end
terra Font:setItalic( val : bool )
  var flags = set_bit(val, C.TTF_STYLE_ITALIC, C.TTF_GetFontStyle(self._ptr))
  C.TTF_SetFontStyle(self._ptr, flags)
end
terra Font:setUnderline( val : bool )
  var flags = set_bit(val, C.TTF_STYLE_UNDERLINE,
                           C.TTF_GetFontStyle(self._ptr))
  C.TTF_SetFontStyle(self._ptr, flags)
end
terra Font:setStrikethrough( val : bool )
  var flags = set_bit(val, C.TTF_STYLE_STRIKETHROUGH,
                          C.TTF_GetFontStyle(self._ptr))
  C.TTF_SetFontStyle(self._ptr, flags)
end

terra Font:getOutline()
  return C.TTF_GetFontOutline(self._ptr)
end
terra Font:setOutline( pixel_width : int )
  C.TTF_SetFontOutline(self._ptr, pixel_width)
end

-- Omitting hooks for hinting and kerning

-- all measurements here are in pixels
-- maximum height of all glyphs in the font
terra Font:maxHeight()
  return C.TTF_FontHeight(self._ptr)
end
-- maximum ascent above baseline of all glyphs in the font
terra Font:maxAscent()
  return C.TTF_FontAscent(self._ptr)
end
-- maximum descent below baseline of all glyphs in the font
terra Font:maxDescent()
  return C.TTF_FontDescent(self._ptr)
end
-- recommended line height
terra Font:lineSkip()
  return C.TTF_FontLineSkip(self._ptr)
end

terra Font:hasGlyph( character : uint16 )
  return C.TTF_GlyphIsProvided(self._ptr, character) ~= 0
end
terra Font:sizeText( txt : rawstring )
  var w : int, h : int
  SDL.assert(C.TTF_SizeText(self._ptr, txt, &w, &h) == 0)
  return w,h
end



local terra convert_surface( surf : &&C.SDL_Surface, fmt : uint32 )
  var new_surf = C.SDL_ConvertSurfaceFormat( @surf, fmt, 0 )
  SDL.assert(new_surf ~= nil)
  C.SDL_FreeSurface(@surf)
  @surf = new_surf
end
-- NOTE THIS LEAVES THE TEXT AS THE SOURCE PATTERN
-- CALLER MUST SET THE SOURCE PATTERN AS DESIRED
-- FOR THE NEXT OPERATION
local terra render_text_helper(
  cairo_ctxt  : &C.cairo_t,
  font        : &C.TTF_Font,
  x           : double,
  y           : double,
  message     : rawstring
)
  -- render text to an SDL surface
  var color = C.SDL_Color { r = 255, g = 255, b = 255, a = 128 }
  var sdl_surf = C.TTF_RenderText_Blended(font, message, color)
  SDL.assert(sdl_surf ~= nil)
  -- make sure the surface has the desired pixel format, or
  -- else we'll have to convert it
  if sdl_surf.format.format ~= C.SDL_PIXELFORMAT_ARGB8888 then
    convert_surface(&sdl_surf, C.SDL_PIXELFORMAT_ARGB8888)
  end
  -- and lock that surface
  SDL.assert(C.SDL_LockSurface(sdl_surf) == 0)

  -- Get info about the surface here
  var w         : int = sdl_surf.w
  var h         : int = sdl_surf.h
  var rowstride : int = sdl_surf.pitch

--  var ptr = [&uint8](sdl_surf.pixels)
--  for py = 0,15 do
--    var base = py*rowstride
--    var off  = 3
--    C.printf(' %3d %3d %3d %3d %3d %3d %3d %3d %3d %3d %3d %3d\n',
--      ptr[base+0*4+off], ptr[base+1*4+off],
--      ptr[base+2*4+off], ptr[base+3*4+off],
--      ptr[base+4*4+off], ptr[base+5*4+off],
--      ptr[base+6*4+off], ptr[base+7*4+off],
--      ptr[base+8*4+off], ptr[base+9*4+off],
--      ptr[base+10*4+off], ptr[base+11*4+off]
--    )
--  end
--  C.printf('wh: %3d %3d %3d\n', w, h, rowstride)

  -- Wrap the SDL surface in a Cairo surface
  var cairo_surf =
    C.cairo_image_surface_create_for_data( [&uint8](sdl_surf.pixels),
                                           C.CAIRO_FORMAT_ARGB32,
                                           w, h, rowstride )
  CairoAssert(C.cairo_surface_status(cairo_surf))

  -- Draw the current source color using the text image as a mask
  -- (alpha-channel only!)
  -- (this avoids the pre-multiply inconsistency between Cairo and SDL,
  --  by not using the RGB channels from SDL at all)
  C.cairo_mask_surface(cairo_ctxt, cairo_surf, x, y)

  -- Clean up
  C.cairo_surface_destroy(cairo_surf)
  C.SDL_UnlockSurface(sdl_surf)
  C.SDL_FreeSurface(sdl_surf)
  return 0
end

terra Window:drawText( font : &Font, msg : rawstring, x:double, y:double )
  render_text_helper(self._cairo._ptr, font._ptr, x, y, msg)
end


-----------------------------------------------------------------
-- Clipboard and TextInput and Dropping Files
-----------------------------------------------------------------

function SDL.HasClipboardText()
  return C.SDL_HasClipboardText()
end

function SDL.GetClipboardText()
  local txt = C.SDL_GetClipboardText()
  local str = ffi.string(txt)
  C.SDL_free(txt)
end

function SDL.SetClipboardText(txt)
  SDL.assert(C.SDL_SetClipboardText(txt) == 0)
end

-- Also, you can turn on file drop onto the application window
terra SDL.EnableDropfileEvent()
  C.SDL_EventState(C.SDL_DROPFILE, C.SDL_ENABLE)
end

terra SDL.IsTextInputActive()
  return C.SDL_IsTextInputActive() == C.SDL_TRUE
end

terra SDL.StartTextInput()
  C.SDL_StartTextInput()
end

terra SDL.StopTextInput()
  C.SDL_StopTextInput()
end



-----------------------------------------------------------------
-- Event Processing
-----------------------------------------------------------------

-- IO State

local struct IOState {
  --curr_time   : uint32,
  btn_state   : uint32,
  mouse_x     : int32,
  mouse_y     : int32,
  scan_state  : uint8[C.SDL_NUM_SCANCODES],
  caps_lock   : bool,
}


terra IOState:initialize()
  C.memset(self, 0, terralib.sizeof(IOState))
  self:refreshCapsLock()
end

terra IOState:refreshCapsLock()
  self.caps_lock = ( (C.SDL_GetModState() and C.KMOD_CAPS) ~= 0)
end
terra IOState:setMouse( x:int32, y:int32 )
  self.mouse_x = x
  self.mouse_y = y
end

terra IOState:setScancode( scankey : C.SDL_Scancode, val : bool )
  self.scan_state[scankey] = [uint8](val)
end
terra IOState:getScancode( scankey : C.SDL_Scancode ) : bool
  return [bool](self.scan_state[scankey])
end
terra IOState:setKeycode( key : C.SDL_Keycode, val : bool )
  self:setScancode( C.SDL_GetScancodeFromKey(key), val )
end
terra IOState:getKeycode( key : C.SDL_Keycode ) : bool
  return self:getScancode( C.SDL_GetScancodeFromKey(key) )
end

local IOSTATE_LMOUSE = 1
local IOSTATE_MMOUSE = 2
local IOSTATE_RMOUSE = 4
terra IOState:getBtn( flag : uint32 ) : bool
  return (self.btn_state and flag) ~= 0
end
terra IOState:setBtn( flag : uint32 ) : bool
  self.btn_state = (self.btn_state and not flag) or flag
end

local _iostate_global = global(IOState)
local _iostate = _iostate_global:get()
_iostate:initialize()


-----------------------
-- Timer Events and User Events

local USER_EVENT_TIMEOUT = 1
local USER_EVENT_DISABLE_MOUSEMOVE = 4
local USER_EVENT_ENABLE_MOUSEMOVE  = 8

-- insert these events into the queue to bracket the event to ignore
local terra DisableMousemoveEvents()
  var event : C.SDL_Event
  event.type        = C.SDL_USEREVENT
  event.user.type   = C.SDL_USEREVENT
  event.user.code   = USER_EVENT_DISABLE_MOUSEMOVE
  C.SDL_PushEvent(&event)
end
local terra EnableMousemoveEvents()
  var event : C.SDL_Event
  event.type        = C.SDL_USEREVENT
  event.user.type   = C.SDL_USEREVENT
  event.user.code   = USER_EVENT_ENABLE_MOUSEMOVE
  C.SDL_PushEvent(&event)
end

local terra on_timeout_schedule_event(
  interval : uint32, param : &opaque
) : uint32

  var event : C.SDL_Event
  event.type        = C.SDL_USEREVENT
  event.user.type   = C.SDL_USEREVENT
  event.user.code   = USER_EVENT_TIMEOUT
  event.user.data1  = param
  event.user.data2  = nil

  C.SDL_PushEvent(&event)
  return interval
end

local VoidFuncPtr = &({}->{})

local terra execute_timeout_event_callback( event : &C.SDL_Event )
  SDL.assert(event.type == C.SDL_USEREVENT)
  var fptr = [VoidFuncPtr](event.user.data1)
  if fptr ~= nil then fptr() end
end

-- if clbk, the second parameter is not provided, then we can
terra SDL.SetTimeout( ms_delay : uint32, clbk : VoidFuncPtr )
  return C.SDL_AddTimer( ms_delay, on_timeout_schedule_event, clbk )
end
terra SDL.SetTimeout( ms_delay : uint32 )
  return C.SDL_AddTimer( ms_delay, on_timeout_schedule_event, nil )
end

terra SDL.ClearTimeout( timer : C.SDL_TimerID )
  C.SDL_RemoveTimer( timer )
end

-----------------------

local Event = {}
Event.__index = Event

local function NewEvent(contents)
  contents = contents or {}
  return setmetatable(contents, Event)
end
function Event:derive(new_type)
  return NewEvent {
    type      = new_type,
    timestamp = self.timestamp,
    window_id = self.window_id,
  }
end

SDL.Event     = Event -- expose the event prototype
SDL.NewEvent  = NewEvent

-- handle queries about key states and modifier key states
local function key_query_helper(keyname)
  local keycode = C.SDL_GetKeyFromName(keyname)
  if keycode == C.SDLK_UNKNOWN then
    error('unrecognized key name: '..keyname, 3)
  end
  return _iostate:getKeycode(keycode)
end
function Event:wasKeyDown(keyname)
  return key_query_helper(keyname)
end
function Event:wasKeyUp(key)
  return not key_query_helper(keyname)
end
function Event:wasShiftDown()
  return _iostate:getScancode(C.SDL_SCANCODE_LSHIFT)
      or _iostate:getScancode(C.SDL_SCANCODE_RSHIFT)
end
function Event:wasCtrlDown()
  return _iostate:getScancode(C.SDL_SCANCODE_LCTRL)
      or _iostate:getScancode(C.SDL_SCANCODE_RCTRL)
end
function Event:wasAltDown()
  return _iostate:getScancode(C.SDL_SCANCODE_LALT)
      or _iostate:getScancode(C.SDL_SCANCODE_RALT)
end
function Event:wasGuiDown()
  return _iostate:getScancode(C.SDL_SCANCODE_LGUI)
      or _iostate:getScancode(C.SDL_SCANCODE_RGUI)
end
function Event:wasCapsLockDown()
  return _iostate.capslock
end

-- handle queries about buttons

function Event:wasLeftButtonDown()
  return _iostate:getBtn(IOSTATE_LMOUSE)
end
function Event:wasMiddleButtonDown()
  return _iostate:getBtn(IOSTATE_MMOUSE)
end
function Event:wasRightButtonDown()
  return _iostate:getBtn(IOSTATE_RMOUSE)
end

-- handle querying for the mouse position
function Event:mousePos()
  return _iostate.mouse_x , _iostate.mouse_y
end

-- handle queries for specific kinds of events
function Event:isKeyPress()
  return self.type == 'KEYDOWN' and self.n_repeats == 0
end


local function update_key(keyevent)
  if keyevent.key['repeat'] > 0 then return end
  local scancode = keyevent.key.keysym.scancode
  local is_down  = keyevent.type == C.SDL_KEYDOWN
  _iostate:setScancode(scancode, is_down)
  if scancode == C.SDL_SCANCODE_CAPSLOCK then
    _iostate:refreshCapsLock()
  end
end

local function update_button(btnevent)
  local mstate = btnevent.button.button
      if mstate == C.SDL_BUTTON_LEFT    then _iostate:setBtn(IOSTATE_LMOUSE)
  elseif mstate == C.SDL_BUTTON_MIDDLE  then _iostate:setBtn(IOSTATE_MMOUSE)
  elseif mstate == C.SDL_BUTTON_RIGHT   then _iostate:setBtn(IOSTATE_RMOUSE)
  end
end

local function unpack_key_event(sdlevent)
  local keysym = sdlevent.key.keysym
  update_key(sdlevent)
  return NewEvent {
    timestamp     = sdlevent.key.timestamp,
    window_id     = sdlevent.key.windowID,
    n_repeats     = sdlevent.key['repeat'],
    key           = ffi.string(C.SDL_GetKeyName(keysym.sym)),
    scancode      = ffi.string(C.SDL_GetScancodeName(keysym.scancode)),
  }
end
local function unpack_mouse_button_event(sdlevent)
  local btncode = sdlevent.button.button
  local btn
      if btncode == C.SDL_BUTTON_LEFT    then btn = 'left'
  elseif btncode == C.SDL_BUTTON_MIDDLE  then btn = 'middle'
  elseif btncode == C.SDL_BUTTON_RIGHT   then btn = 'right'
  elseif btncode == C.SDL_BUTTON_X1      then btn = 'x1'
  elseif btncode == C.SDL_BUTTON_X2      then btn = 'x2'
  end

  update_button(sdlevent)
  return NewEvent {
    timestamp = sdlevent.button.timestamp,
    window_id = sdlevent.button.windowID,
    button    = btn,
    clicks    = sdlevent.button.clicks,
    x         = sdlevent.button.x,
    y         = sdlevent.button.y,
  }
end


local IS_MOUSEMOVE_DISABLED = false
local function extract_event(sdlevent)
  local ev = NewEvent()
  if      sdlevent.type == C.SDL_QUIT               then
    ev.type = 'QUIT'
  elseif  sdlevent.type == C.SDL_WINDOWEVENT        then
    if      sdlevent.window.event == C.SDL_WINDOWEVENT_SHOWN        then
      ev.type = 'WINDOW_SHOWN'
    elseif  sdlevent.window.event == C.SDL_WINDOWEVENT_HIDDEN       then
      ev.type = 'WINDOW_HIDDEN'
    elseif  sdlevent.window.event == C.SDL_WINDOWEVENT_MOVED        then
      ev.type = 'MOVE_WINDOW'
      ev.x    = sdlevent.window.data1
      ev.y    = sdlevent.window.data2
    elseif  sdlevent.window.event == C.SDL_WINDOWEVENT_SIZE_CHANGED then
      ev.type = 'RESIZE_WINDOW'
      ev.w    = sdlevent.window.data1
      ev.h    = sdlevent.window.data2
      local win = GetWindowFromID(sdlevent.window.windowID)
      handleWindowResize(win, ev.w, ev.h)
    elseif  sdlevent.window.event == C.SDL_WINDOWEVENT_RESIZED      then
      -- do nothing, other call handles
    elseif  sdlevent.window.event == C.SDL_WINDOWEVENT_ENTER        then
      ev.type = 'MOUSE_ENTER'
    elseif  sdlevent.window.event == C.SDL_WINDOWEVENT_LEAVE        then
      ev.type = 'MOUSE_LEAVE'
    elseif  sdlevent.window.event == C.SDL_WINDOWEVENT_FOCUS_GAINED then
      ev.type = 'KEY_FOCUS_GAINED'
    elseif  sdlevent.window.event == C.SDL_WINDOWEVENT_FOCUS_LOST   then
      ev.type = 'KEY_FOCUS_LOST'
    elseif  sdlevent.window.event == C.SDL_WINDOWEVENT_CLOSE        then
      ev.type = 'WINDOW_CLOSE'
    elseif  sdlevent.window.event == C.SDL_WINDOWEVENT_MINIMIZED    then
      ev.type = 'WINDOW_MINIMIZED'
    elseif  sdlevent.window.event == C.SDL_WINDOWEVENT_MAXIMIZED    then
      ev.type = 'WINDOW_MAXIMIZED'
    -- HUH?? on these last two
    elseif  sdlevent.window.event == C.SDL_WINDOWEVENT_EXPOSED      then
    elseif  sdlevent.window.event == C.SDL_WINDOWEVENT_RESTORED     then
    else
      error('unhandled window event type: ', tostring(sdlevent.window.event))
    end
    -- add the timestamp
    if ev.type then
      ev.timestamp = sdlevent.window.timestamp
      ev.window_id = sdlevent.window.windowID
    end
  elseif  sdlevent.type == C.SDL_TEXTINPUT          then
    ev = NewEvent {
      type        = 'TEXTINPUT',
      timestamp   = sdlevent.text.timestamp,
      window_id   = sdlevent.text.windowID,
      text        = ffi.string(sdlevent.text.text),
    }
  elseif  sdlevent.type == C.SDL_KEYDOWN            then
    ev = unpack_key_event(sdlevent)
    ev.type = 'KEYDOWN'
  elseif  sdlevent.type == C.SDL_KEYUP              then
    ev = unpack_key_event(sdlevent)
    ev.type = 'KEYUP'
  elseif  sdlevent.type == C.SDL_MOUSEMOTION        then
    if not IS_MOUSEMOVE_DISABLED then
      _iostate:setMouse(sdlevent.motion.x, sdlevent.motion.y)
      ev = NewEvent {
        type      = 'MOUSEMOVE',
        timestamp = sdlevent.motion.timestamp,
        window_id = sdlevent.motion.windowID,
        x         = sdlevent.motion.x,
        y         = sdlevent.motion.y,
        dx        = sdlevent.motion.xrel,
        dy        = sdlevent.motion.yrel,
      }
    end
  elseif  sdlevent.type == C.SDL_MOUSEBUTTONDOWN    then
    ev = unpack_mouse_button_event(sdlevent)
    ev.type = 'MOUSEDOWN'
  elseif  sdlevent.type == C.SDL_MOUSEBUTTONUP      then
    ev = unpack_mouse_button_event(sdlevent)
    ev.type = 'MOUSEUP'
  elseif  sdlevent.type == C.SDL_MOUSEWHEEL         then
    ev = NewEvent {
      type      = 'MOUSEWHEEL',
      timestamp = sdlevent.wheel.timestamp,
      window_id = sdlevent.wheel.windowID,
      x         = sdlevent.wheel.x,
      y         = sdlevent.wheel.y,
    }
  elseif  sdlevent.type == C.SDL_DROPFILE           then
    local filename = ffi.string(sdlevent.drop.file)
    C.SDL_free(sdlevent.drop.file)
    ev = NewEvent {
      type      = 'DROPFILE',
      timestamp = sdlevent.drop.timestamp,
      filename  = filename,
    }
  elseif  sdlevent.type == C.SDL_USEREVENT          then
    if sdlevent.user.code == USER_EVENT_TIMEOUT then
      ev.type       = 'TIMEOUT'
      ev.timestamp  = sdlevent.user.timestamp
      ev.window_id  = sdlevent.user.windowID
      execute_timeout_event_callback(sdlevent)
    elseif sdlevent.user.code == USER_EVENT_DISABLE_MOUSEMOVE then
      IS_MOUSEMOVE_DISABLED = true
    elseif sdlevent.user.code == USER_EVENT_ENABLE_MOUSEMOVE then
      IS_MOUSEMOVE_DISABLED = false
    end
  else
    -- passthrough on other events
    --error('unhandled event type: ', sdlevent.type)
  end

  -- convert to nil for unhandled events
  if not ev.type then return nil else return ev end
end

local event_buffer = global(C.SDL_Event) -- only holds 1 event
function SDL.WaitForEvents()
  -- create an iterator to process events...
  SDL.assert(C.SDL_WaitEvent(event_buffer:getpointer()) == 1)
  local init_ev = extract_event(event_buffer:get())
  return function()
    -- start with the initial event and then nil on every subsequent call
    local ev = init_ev
    init_ev = nil
    -- extra loop here skips any unhandled events...
    while not ev do
      if C.SDL_PollEvent(event_buffer:getpointer()) == 1 then
        ev = extract_event(event_buffer:get())
      else
        return nil -- actually exit here
      end
    end
    return ev
  end
end


-----------------------------------------------------------------
-- Changing Mouse and Keyboard Interaction in Exceptional Ways
-----------------------------------------------------------------


-- It's a little kludgy, but it does kind of work...
terra Window:showCursor()
  if self:isCursorHidden() then
    self._cursor_hidden.is_hidden   = false
    -- have to release the mouse cursor from confinement
    -- before we fix the position
    SDL.assert(C.SDL_SetRelativeMouseMode(C.SDL_FALSE) == 0)

    -- move the cursor back to where it was when we hid it
    -- make sure this generates no events
    DisableMousemoveEvents()
    C.printf('warping to %d %d\n',
        self._cursor_hidden.x, self._cursor_hidden.y)
    C.SDL_WarpMouseInWindow(self._ptr,
                            self._cursor_hidden.x, self._cursor_hidden.y)
    EnableMousemoveEvents()

    -- finally reveal the cursor which has been repositioned
    -- to the right place
    C.SDL_ShowCursor(C.SDL_ENABLE)
  end
end
terra Window:hideCursor()
  if not self:isCursorHidden() then
    self._cursor_hidden.is_hidden   = true
    self._cursor_hidden.x           = _iostate.mouse_x
    self._cursor_hidden.y           = _iostate.mouse_y

    -- make the cursor (i) disappear, (ii) be confined to the window
    C.SDL_ShowCursor(C.SDL_DISABLE)
    SDL.assert(C.SDL_SetRelativeMouseMode(C.SDL_TRUE) == 0)
  end
end
terra Window:isCursorHidden() : bool
  return self._cursor_hidden.is_hidden
end


-----------------------------------------------------------------
-- Documentation
-----------------------------------------------------------------

local function helpfunc_gen(doc_table)
  local bigmsg = ''
  for _,str in pairs(doc_table) do
    bigmsg = bigmsg .. str .. '\n\n'
  end
  return function(sym)
    if sym then
      if doc_table[sym] then print(doc_table[sym])
                        else print('could not find symbol "'..
                                   tostring(sym)..'"') end
    else
      print(bigmsg)
    end
  end
end
local function help_apicheck(doc_table, api, prefix, ignores)
  ignores = ignores or {}
  local undocumented = ''
  for k,_ in pairs(api) do
    if not doc_table[k] and not ignores[k] then
      undocumented = undocumented..'  '..prefix..tostring(k)..'\n'
    end
  end
  if #undocumented > 0 then
    undocumented = 'The following symbols were not documented:\n'..
                   undocumented
  end

  local missing = ''
  for k,_ in pairs(doc_table) do
    if not api[k] then
      missing = missing..'  '..prefix..tostring(k)..'\n'
    end
  end
  if #missing > 0 then
    missing = 'The following symbols were missing from the API:\n'..missing
  end

  if #undocumented > 0 or #missing > 0 then
    error('INTERNAL: API inconsistencies detected\n'..undocumented..missing, 2)
  end
end

local sdl_help_table = {
['Init'] = [[
void                          --  Call this function to initialize the SDL
SDL.Init()                        subsystem (Also initializes CairoGraphics
                                  and any other needed libraries)]],
['HasOnlyOneDisplay'] = [[
bool                          --  Only exists to check this assumption
SDL.HasOnlyOneDisplay()           If the function returns false, that
                                  could be why something is breaking?]],
['GetDisplayBounds'] = [[
x, y, w, h =                  --  Get the size of the display.
SDL.GetDisplayBounds()            We expect x=0, y=0 but return them for
                                  consistency with other GetBounds() calls]],
['Window'] = [[
SDL.Window                    --  A struct representing a window.
                                  (This wrapper has not been tested for
                                   multiple windows though...)]],
['NewWindow'] = [[
window = SDL.NewWindow {      --  Construct a new window with named params:
  x = #, y = #,                   - (optional) display position of top left
  w = #, h = #,                   - (optional) initial window size
  name = 'string',                - (optional) text for title bar
  hidden = bool,                  - if true, the window is initially hidden
  noborder = bool,                - if true, remove chrome from the window
  resizable = bool,               - if true, user can change window size
  focus = bool                    - if true, give the window focus immediately
  minw = #, minh = #,             - set minimum window dimensions
  maxw = #, maxh = #,             - set maximum window dimensions
}]],
['Font'] = [[
SDL.Font                      --  A struct representing a font]],
['OpenFont'] = [[
font = SDL.OpenFont(          --  Load a TTF font in from the specified file
  file : rawstring,               and with the specified font size
  font_size : int
)]],
['Event'] = [[
SDL.Event                     --  A Lua Prototype object for SDL events]],
['NewEvent'] = [[
event =                       --  A function to allow client code to
SDL.NewEvent(init_fields)         generate its own events, similar to
                                  the SDL originating ones]],
['WaitForEvents'] = [[
for e in SDL.WaitForEvents()  --  a Lua generator function to poll the event
do                                queue.  This call will block until an event
  ...                             is available, so make sure to schedule a
end                               timeout if you want to be interrupted. The
                                  loop will consume all available events and
                                  then exit the loop.  You can either handle
                                  everything (including drawing) using events
                                  or you can flip-flop between emptying the
                                  event queue and doing drawing]],
['EnableDropfileEvent'] = [[
SDL.EnableDropfileEvent()     --  call this function if you want SDL to
                                  generate events whenever a user tries to
                                  drop a file onto the application or
                                  application window]],
['HasClipboardText'] = [[
bool                          --  check whether there's some text on the
SDL.HasClipboardText()            system clipboard that we can consume]],
['GetClipboardText'] = [[
textstring =                  --  retreive text from the system clipboard
SDL.GetClipboardText()]],
['SetClipboardText'] = [[
SDL.SetClipboardText(         --  put text onto the system clipboard
  textstring
)]],
['IsTextInputActive'] =[[
bool                          --  Test whether 'TextInput' is turned on.
SDL.IsTextInputActive()           If it is, then TEXTINPUT events will be
                                  generated from keyboard events, providing
                                  appropriate character codes rather than
                                  just key events]],
['StartTextInput'] =[[
SDL.StartTextInput()          --  Turn TextInput on]],
['StopTextInput'] =[[
SDL.StopTextInput()           --  Turn TextInput off]],
['SetTimeout'] = [[
timer =                       --  schedule a timeout event for 'ms' 
SDL.SetTimeout(ms, callback)      milliseconds in the future.  At that time,
SDL.SetTimeout(ms)                call the callback if provided, and
                                  generate a TIMEOUT event regardless]],
['ClearTimeout'] = [[
SDL.ClearTimeout(timer)       --  cancel a timeout]],
['alert'] = [[
SDL.alert(title, msg)         --  This call will create a popup with
                                  the provided title and message]],
['assert'] = [[
SDL.assert(expr)              --  Explode if expr is false.
                                  Works in both Lua and Terra code; will
                                  also print any SDL errors encountered.
                                  (This may be completely unnecessary
                                   for clients)]],
['error']  = [[
SDL.error(msg)                --  Explode and print msg.
                                  Works in both Lua and Terra code; will
                                  also print any SDL errors encountered.
                                  (This may be completely unnecessary
                                   for clients)]],
['Help'] = [[
SDL.Help()                    --  Print this message; alternately if you
SDL.Help(symbol)                  supply a string, it will print help for
                                  only that one symbol/entry
                          ALSO: PLEASE NOTE
        There are three more useful Help functions for this module,
        all of which follow a similar pattern.  They are:
          SDL.Window.Help()       -- general window functions
          SDL.Window.HelpDraw()   -- window functions for drawing
          SDL.Font.Help()         -- font object functions
]],
}

SDL.Help = helpfunc_gen(sdl_help_table)
help_apicheck(sdl_help_table, SDL, 'SDL.', {'methods',  'metamethods'})

local font_help_table = {
['close'] = [[
SDL.Font:close()              --  Cleanup and release font resources.
                                  Make sure to call this!]],

['isBold'] = [[
bool                          --  test if the font is set to be bold
SDL.Font:isBold() ]],
['isItalic'] = [[
bool                          --  test if the font is set to be italic
SDL.Font:isItalic() ]],
['isUnderline'] = [[
bool                          --  test if the font is set to underline
SDL.Font:isUnderline() ]],
['isStrikethrough'] = [[
bool                          --  test if the font is set to strikethrough
SDL.Font:isStrikethrough() ]],
['setBold'] = [[
SDL.Font:setBold(bool)        --  set/un-set the font to be bold]],
['setItalic'] = [[
SDL.Font:setItalic(bool)      --  set/un-set the font to be italic]],
['setUnderline'] = [[
SDL.Font:setUnderline(bool)   --  set/un-set the font to underline]],
['setStrikethrough'] = [[
SDL.Font:setStrikethrough(bool) --  set/un-set the font to strikethrough]],

['getOutline'] = [[
pixel_width =                 --  get the outline width (0 means no outline)
SDL.Font:getOutline() ]],
['setOutline'] = [[
SDL.Font:setOutline(px_width) --  set the outline width (0 means no outline)]],

['hasGlyph'] = [[
SDL.Font:hasGlyph(char)       --  see if this font supports this glyph]],

['maxHeight'] = [[
int                           --  the maximum height of a glyph in the font
SDL.Font:maxHeight() ]],
['maxAscent'] = [[
int                           --  the maximum height of a glyph in the font
SDL.Font:maxAscent()              measured as ascending above the baseline]],
['maxDescent'] = [[
int                           --  the maximum height of a glyph in the font
SDL.Font:maxDescent()             measured as descending below the baseline]],
['lineSkip'] = [[
int                           --  unit-length reference spacing between lines
SDL.Font:lineSkip() ]],

['sizeText'] = [[
w, h =                        --  predict the size of some text based on
SDL.Font:sizeText(txt)            the current assumptions]],
}
help_apicheck(font_help_table, SDL.Font.methods, 'SDL.Font:')
font_help_table['Help'] = [[
SDL.Font.Help()               --  Print this message; alternately if you
SDL.Help(symbol)                  supply a string, it will print help for
                                  only that one symbol/entry
]]
SDL.Font.Help = helpfunc_gen(font_help_table)

local win_draw_help_table = {
['cairoBegin'] = [[
SDL.Window:cairoBegin()       --  Open up a Cairo drawing context.
                                  All of the drawing calls must happen
                                  while the Cairo context is open.]],
['cairoEnd'] = [[
SDL.Window:cairoEnd()         --  Close the Cairo drawing context.
                                  All of the drawing calls must happen
                                  while the Cairo context is open.]],
['isCairoOpen'] = [[
bool                          --  Test whether the Cairo context is open.
SDL.Window:isCairoOpen()          All of the drawing calls must happen
                                  while the Cairo context is open.]],
['cairoAssertOk'] = [[
SDL.Window:cairoAssertOk()    --  Check whether any Cairo drawing calls
                                  have failed and explode if so.]],
['cairoSave'] = [[
SDL.Window:cairoSave()        --  Push a copy of the current Cairo state
                                  onto a stack, and set it
                                  as the current state.]],
['cairoRestore'] = [[
SDL.Window:cairoRestore()     --  Pop the top of the Cairo state stack.]],
['beginPath'] = [[
SDL.Window:beginPath()        --  Give cairo the signal to start a new path.
                                  Clears any existing path.]],
['closePath'] = [[
SDL.Window:closePath()        --  Close the current sub-path into a loop
                                  using a straight line.  You can close
                                  multiple sub-paths per beginPath() call.]],
['lineTo'] = [[
SDL.Window:lineTo(            --  draw a line from the current point (cx,cy)
  x,y : double                    to the point (x,y)
)]],
['lineRel'] = [[
SDL.Window:lineRel(           --  draw a line from the current point (cx,cy)
  dx,dy : double                  to the point (cx+dx, cy+dy)
)]],
['moveTo'] = [[
SDL.Window:moveTo(            --  move the current point from (cx,cy)
  x,y : double                    to the point (x,y)
)                                 (starts a new sub-path)]],
['moveRel'] = [[
SDL.Window:moveRel(           --  move the current point from (cx,cy)
  dx,dy : double                  to the point (cx+dx, cy+dy)
)                                 (starts a new sub-path)]],
['curveTo'] = [[
SDL.Window:curveTo(           --  draw a cubic bezier curve starting from
  x1,y1 : double                  the current point (cx,cy) and ending at
  x2,y2 : double                  the point (x3,y3) with the two control
  x3,y3 : double                  points (x1,y1) and (x2,y2)
)]],
['curveRel'] = [[
SDL.Window:curveRel(          --  draw a cubic bezier curve starting from
  dx1,dy1 : double                the current point (cx,cy) and ending at
  dx2,dy2 : double                the point (cx+dx3, cy+dy3) with two
  dx3,dy3 : double                control points (cx+dx1, cy+dy1) and
)                                 (cx+dx2, cy+dy2)]],
['rectangle'] = [[
SDL.Window:rectangle(         --  draw a complete, closed subpath rectangle
  x,y,w,h : double                with top left (x,y) and dimensions w,h
)]],
['stroke'] = [[
SDL.Window:stroke()           --  render the current path as a stroke
                                  and clear the path state]],
['fill'] = [[
SDL.Window:fill()             --  render the current path filled
                                  and clear the path state]],
['strokeAndKeepPath'] = [[
SDL.Window:strokeAndKeepPath()  --  render the current path as a stroke
                                    but don't clear the path state]],
['fillAndKeepPath'] = [[
SDL.Window:fillAndKeepPath()  --  render the current path filled
                                  but don't clear the path state]],
['clip'] = [[
SDL.Window:clip()             --  clip all future calls by the current path
                                  and clear the path state]],
['resetClip'] = [[
SDL.Window:resetClip()        --  reset the clip state to nothing clipped]],
['drawText'] = [[
SDL.Window:drawText(          --  render msg with the current color and
   font : &Font,                  the provided font object at point (x,y)
   msg  : rawstring,
   x,y  : double
)]],
['clear'] = [[
SDL.Window:clear()            --  fill the screen with the current color]],
['getColor'] = [[
r,g,b,a =                     --  get the current rgba color in [0,255] units
SDL.Window:getColor()]],
['setColor'] = [[
SDL.Window:setColor(r,g,b,a)  --  set the current rgba color in [0,255] units
SDL.Window:setColor(r,g,b)        if alpha is omitted we assume a=255]],
['setLineCapTo_Butt'] = [[
SDL.Window:setLineCapTo_Butt()    --  when stroking, use abrupt line caps]],
['setLineCapTo_Round'] = [[
SDL.Window:setLineCapTo_Round()   --  when stroking, use round line caps]],
['setLineCapTo_Square'] = [[
SDL.Window:setLineCapTo_Square()  --  when stroking, use square line caps]],
['setLineJoinTo_Miter'] = [[
SDL.Window:setLineJoinTo_Miter()  --  when stroking, use mitered joints]],
['setLineJoinTo_Round'] = [[
SDL.Window:setLineJoinTo_Round()  --  when stroking, use round joints]],
['setLineJoinTo_Bevel'] = [[
SDL.Window:setLineJoinTo_Bevel()  --  when stroking, use beveled joints]],
['setDash'] = [[
SDL.Window:setDash(           --  set the dash pattern to use when stroking.
  dashes    : &double,            need to provide a C-array and its length.
  n_dashes  : uint                the dashes specifies pos/neg lengths
)]],
['setLineWidth'] = [[
SDL.Window:setLineWidth(      --  specify the width of stroked lines
  w : double
)]],
['setLineMiterLimit'] = [[
SDL.Window:setLineMiterLimit( --  when mitering a joint, Cairo will switch
  limit : double                  to beveling if the miter sticks out too
)                                 much.  Mitering is only done when
                                    miter_length / line_width <= limit
                                  is true, with this limit specified]],
}
local win_help_table = {
['destroy'] = [[
SDL.Window:destroy()          --  cleanup resources used by this window
                                  object]],
['getTitle'] = [[
str =                         --  get the current displayed title of the
SDL.Window:getTitle()             window]],
['setTitle'] = [[
SDL.Window:setTitle(str)      --  set the current displayed title of this
                                  window]],
['getBounds'] = [[
x,y,w,h        =              --  retreive the size and position of this
SDL.Window:getBounds()            window from the perspective of the
                                  display's coordinate space]],
['setBounds'] = [[
SDL.Window:setBounds(         --  reposition and possibly resize the window
  x,y,w,h : int                   coordinates are given in display space
)                                 any parameter with a negative value will
                                  be replaced by the current value instead]],
['isShown'] = [[
bool                          --  is the window visible?
SDL.Window:isShown()]],
['isHidden'] = [[
bool                          --  is the window not visible?
SDL.Window:isHidden() ]],
['show'] = [[
SDL.Window:show()             --  make sure the window is visible]],
['hide'] = [[
SDL.Window:hide()             --  make sure the window is not visible]],
['isCursorHidden'] = [[
bool                          --  is the cursor hidden/inactive?
SDL.Window:isCursorHidden()]],
['hideCursor'] = [[
SDL.Window:hideCursor()       --  hide and trap the cursor.  While hidden,
                                  the cursor's current position is
                                  unreliable, but the relative motions
                                  of the cursor can be used.
                                  (remember the current position too)]],
['showCursor'] = [[
SDL.Window:showCursor()       --  reveal the cursor at the position at
                                  which it was originally hidden.
                                  The cursor is now allowed to move outside
                                  the window without consequence]],
['getMinWH'] = [[
w,h : int =                   --  get the minimum bounds on the allowable
SDL.Window:getMinWH()             dimensions for this window]],
['getMaxWH'] = [[
w,h : int =                   --  get the maximum bounds on the allowable
SDL.Window:getMaxWH()             dimensions for this window]],
['setMinWH'] = [[
SDL.Window:setMinWH(          --  set the minimum bounds on the allowable
  w,h : int                       dimensions for this window
)]],
['setMaxWH'] = [[
SDL.Window:setMaxWH(          --  set the maximum bounds on the allowable
  w,h : int                       dimensions for this window
)]],
['alert'] = [[
SDL.Window:alert(title, msg)  --  This call will create a popup with
                                  the provided title and message that
                                  is tied to this specific window.]],
}
local joint_window_help_table = {}
for k,v in pairs(win_help_table) do joint_window_help_table[k] = v end
for k,v in pairs(win_draw_help_table) do joint_window_help_table[k] = v end

win_draw_help_table['Help'] = [[
SDL.Window.HelpDraw()         --  Print this message; alternately if you
SDL.Window.HelpDraw(symbol)       supply a string, it will print help for
                                  only that one symbol/entry
]]
win_help_table['Help'] = [[
SDL.Window.Help()             --  Print this message; alternately if you
SDL.Window.Help(symbol)           supply a string, it will print help for
                                  only that one symbol/entry
]]

help_apicheck(joint_window_help_table, SDL.Window.methods, 'SDL.Window:')
SDL.Window.Help = helpfunc_gen(win_help_table)
SDL.Window.HelpDraw = helpfunc_gen(win_draw_help_table)


local EVENT_TYPES_HELP = [[
'QUIT'
'WINDOW_SHOWN'
'WINDOW_HIDDEN'
'MOVE_WINDOW'
'RESIZE_WINDOW'
'MOUSE_ENTER'
'MOUSE_LEAVE'
'KEY_FOCUS_GAINED'
'KEY_FOCUS_LOST'
'WINDOW_CLOSE'
'WINDOW_MINIMIZED'
'WINDOW_MAXIMIZED'
  -- all have timestamp and window_id; nothing else

'KEYDOWN'
'KEYUP'
  -- timestamp and window_id
  -- 'key' holds a string of which key; 'scancode' is lower level name
  -- n_repeats has the number of times this event has sequentially repeated

'MOUSEMOVE'
  -- timestamp and window_id
  -- x,y,dx,dy

'MOUSEDOWN'
'MOUSEUP'
  -- timestamp and window_id
  -- button is from ['left','middle','right','x1','x2']
  -- x,y position
  -- clicks gives a measurement of whether this is a double/triple/... click

'MOUSEWHEEL'
  -- timestamp and window_id
  -- x,y are measurements of wheel movement

'DROPFILE',
  -- timestamp (no window_id ???)
  -- filename string

'TIMEOUT'
  -- timestamp and window_id
  -- is returned after any registered callbacks have executed

]]


