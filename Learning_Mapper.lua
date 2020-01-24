--[[

LEARNING MAPPER

Author: Nick Gammon
Date:   24th January 2020

 PERMISSION TO DISTRIBUTE

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software
 and associated documentation files (the "Software"), to deal in the Software without restriction,
 including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
 and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
 subject to the following conditions:

 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.


 LIMITATION OF LIABILITY

 The software is provided "as is", without warranty of any kind, express or implied,
 including but not limited to the warranties of merchantability, fitness for a particular
 purpose and noninfringement. In no event shall the authors or copyright holders be liable
 for any claim, damages or other liability, whether in an action of contract,
 tort or otherwise, arising from, out of or in connection with the software
 or the use or other dealings in the software.


--]]



--STATUS_BACKGROUND_COLOUR = "#333333"
STATUS_BACKGROUND_COLOUR = "black"


-- black is true (ham) and red is false (spam)

-- in other words, a marker assigned black IS the sort of line, and one assigned red IS NOT the sort of line


function f_handle_description ()
  local lines = { }
  for line = last_deduced_start_line, last_deduced_end_line do
    table.insert (lines, GetLineInfo (line, 1)) -- get text of line
  end -- for each line
  description = table.concat (lines, "\n")
end -- f_handle_description

function f_handle_exits ()
  local lines = { }
  for line = last_deduced_start_line, last_deduced_end_line do
    table.insert (lines, GetLineInfo (line, 1)) -- get text of line
  end -- for each line
  exits_str = table.concat (lines, " ")
  process_exit_line ()
end -- f_handle_exits

function f_handle_name ()
  local lines = { }
  for line = last_deduced_start_line, last_deduced_end_line do
    table.insert (lines, GetLineInfo (line, 1)) -- get text of line
  end -- for each line
  room_name = table.concat (lines, " ")
end -- f_handle_name

function f_handle_prompt ()
  local lines = { }
  for line = last_deduced_start_line, last_deduced_end_line do
    table.insert (lines, GetLineInfo (line, 1)) -- get text of line
  end -- for each line
  prompt = table.concat (lines, " ")
end -- f_handle_prompt


-- these are the types of lines we are trying to classify as a certain line IS or IS NOT that type
line_types = {
  description = { short = "Desc", handler = f_handle_description },
  exits = { short = "Ex", handler = f_handle_exits },
  room_name = { short =  "Name", handler = f_handle_name },
  prompt = { short = "Prompt", handler = f_handle_prompt },
}  -- end of line_types table

function f_first_style_run_foreground (line)
  return GetStyleInfo(line, 1, 14) or -1
end -- f_first_style_run_foreground

function f_first_word (line)
  if not GetLineInfo(line, 1) then
    return ""
  end -- no line available
  return string.match (GetLineInfo(line, 1), "^%a+") or ""
end -- f_first_word

function f_first_character (line)
  if not GetLineInfo(line, 1) then
    return ""
  end -- no line available
  return string.match (GetLineInfo(line, 1), "^.") or ""
end -- f_first_character

-- things we are looking for, like colour of first style run
markers = {

  {
  desc = "Foreground colour of first style run",
  func = f_first_style_run_foreground,
  marker = "m_first_style_run_foreground",

  },

  {
  desc = "First word in the line",
  func = f_first_word,
  marker = "m_first_word",

  },

--[[

 {
  desc = "First character in the line",
  func = f_first_character,
  marker = "m_first_character",

  },

--]]

  } -- end of markers

-- this table has the counters
corpus = {


} -- end of corpus table


local MAX_NAME_LENGTH = 60

require "mapper"
require "serialize"
require "copytable"
require "commas"
require "tprint"

default_config = {
  -- assorted colours
  BACKGROUND_COLOUR       = { name = "Background",        colour =  ColourNameToRGB "lightseagreen", },
  ROOM_COLOUR             = { name = "Room",              colour =  ColourNameToRGB "cyan", },
  EXIT_COLOUR             = { name = "Exit",              colour =  ColourNameToRGB "darkgreen", },
  EXIT_COLOUR_UP_DOWN     = { name = "Exit up/down",      colour =  ColourNameToRGB "darkmagenta", },
  EXIT_COLOUR_IN_OUT      = { name = "Exit in/out",       colour =  ColourNameToRGB "#3775E8", },
  OUR_ROOM_COLOUR         = { name = "Our room",          colour =  ColourNameToRGB "black", },
  UNKNOWN_ROOM_COLOUR     = { name = "Unknown room",      colour =  ColourNameToRGB "#00CACA", },
  DIFFERENT_AREA_COLOUR   = { name = "Another area",      colour =  ColourNameToRGB "#009393", },
  SHOP_FILL_COLOUR        = { name = "Shop",              colour =  ColourNameToRGB "darkolivegreen", },
  POSTOFFICE_FILL_COLOUR  = { name = "Post Office",       colour =  ColourNameToRGB "yellowgreen", },
  BANK_FILL_COLOUR        = { name = "Bank",              colour =  ColourNameToRGB "gold", },
  NEWSROOM_FILL_COLOUR    = { name = "Newsroom",          colour =  ColourNameToRGB "lightblue", },
  MAPPER_NOTE_COLOUR      = { name = "Messages",          colour =  ColourNameToRGB "lightgreen" },

  ROOM_NAME_TEXT          = { name = "Room name text",    colour = ColourNameToRGB "#BEF3F1", },
  ROOM_NAME_FILL          = { name = "Room name fill",    colour = ColourNameToRGB "#105653", },
  ROOM_NAME_BORDER        = { name = "Room name box",     colour = ColourNameToRGB "black", },

  AREA_NAME_TEXT          = { name = "Area name text",    colour = ColourNameToRGB "#BEF3F1",},
  AREA_NAME_FILL          = { name = "Area name fill",    colour = ColourNameToRGB "#105653", },
  AREA_NAME_BORDER        = { name = "Area name box",     colour = ColourNameToRGB "black", },

  FONT = { name =  get_preferred_font {"Dina",  "Lucida Console",  "Fixedsys", "Courier", "Sylfaen",} ,
           size = 8
         } ,

  -- size of map window
  WINDOW = { width = 400, height = 400 },

  -- how far from where we are standing to draw (rooms)
  SCAN = { depth = 30 },

  -- speedwalk delay
  DELAY = { time = 0.3 },

  -- how many seconds to show "recent visit" lines (default 3 minutes)
  LAST_VISIT_TIME = { time = 60 * 3 },

  }

rooms = {}

valid_direction = {
  n = "n",
  s = "s",
  e = "e",
  w = "w",
  u = "u",
  d = "d",
  ne = "ne",
  sw = "sw",
  nw = "nw",
  se = "se",
  north = "n",
  south = "s",
  east = "e",
  west = "w",
  up = "u",
  down = "d",
  northeast = "ne",
  northwest = "nw",
  southeast = "se",
  southwest = "sw",
  ['in'] = "in",
  out = "out",
  }  -- end of valid_direction

-- -----------------------------------------------------------------
-- OnPluginDrawOutputWindow
--  Update our debugging info
-- -----------------------------------------------------------------
function OnPluginDrawOutputWindow (firstline, offset, notused)
  local background_colour = ColourNameToRGB (STATUS_BACKGROUND_COLOUR)
  local text_colour = ColourNameToRGB ("palegreen")
  local main_height = GetInfo (263)
  local font_height = GetInfo (212)

  -- clear window
  WindowRectOp (win, miniwin.rect_fill, 0, 0, 0, 0, background_colour)

  -- allow for scrolling position
  local top =  (((firstline - 1) * font_height) - offset) - 2

  -- how many lines to draw

  local lastline = firstline + (main_height / font_height)

  for line = firstline, lastline do
    if line >= 1 and GetLineInfo (line, 1) then
      if GetLineInfo (line, 4) or GetLineInfo (line, 5) then
        -- note or input line, ignore it
      else
        local linetype = analyse_line (line)
        if linetype then
          line_type_info = "<- " .. linetype
        else
          line_type_info = ""
        end -- if
        WindowText (win, font_id, line_type_info, 0, top,
                    0, 0, text_colour)
      end -- if
      top = top + font_height
    end -- if line exists
  end -- for each line

end -- OnPluginDrawOutputWindow

-- -----------------------------------------------------------------
-- OnPluginWorldOutputResized
--  On world window resize, remake the miniwindow to fit the size correctly
-- -----------------------------------------------------------------
function OnPluginWorldOutputResized ()

  win = "A" .. GetPluginID ()
  font_id = "f"

  font_name = GetInfo (20) -- output window font
  font_size = GetOption "output_font_height"

  -- make window so I can grab the font info
  WindowCreate (win,
                650, -- left
                0,  -- top
                500, -- width
                GetInfo (263),   -- world window client height
                miniwin.pos_top_left,   -- position (irrelevant)
                miniwin.create_absolute_location,   -- flags
                ColourNameToRGB (STATUS_BACKGROUND_COLOUR))   -- background colour

  -- add font
  WindowFont (win, font_id, font_name, font_size,
              false, false, false, false,  -- normal
              miniwin.font_charset_ansi, miniwin.font_family_any)

  -- find height of font for future calculations
  font_height = WindowFontInfo (win, font_id, 1)  -- height

  WindowSetZOrder(win, -5)

  WindowShow (win)


end -- OnPluginWorldOutputResized

-- -----------------------------------------------------------------
-- INFO helper function for debugging the plugin (information messages)
-- -----------------------------------------------------------------
function INFO (...)
  ColourNote ("orange", "", table.concat ( { ... }, " "))
end -- INFO

-- -----------------------------------------------------------------
-- WARNING helper function for debugging the plugin (warning/error messages)
-- -----------------------------------------------------------------
function WARNING (...)
  ColourNote ("red", "", table.concat ( { ... }, " "))
end -- WARNING

-- -----------------------------------------------------------------
-- DEBUG helper function for debugging the plugin to a notepad window
-- -----------------------------------------------------------------
function DEBUG (...)

  do return end

  if GetNotepadLength("Debug") > 5000 then
    return
  end -- if too big

  AppendToNotepad ("Debug", table.concat ( { ... }, " ") .. "\r\n")
end -- DEBUG

-- -----------------------------------------------------------------
-- Plugin Install
-- -----------------------------------------------------------------
function OnPluginInstall ()

  config = {}  -- in case not found

  -- get saved configuration
  assert (loadstring (GetVariable ("config") or "")) ()

  -- allow for additions to config
  for k, v in pairs (default_config) do
    config [k] = config [k] or v
  end -- for

  -- and rooms
  assert (loadstring (GetVariable ("rooms") or "")) ()

  -- initialize mapper

  mapper.init { config = config, get_room = get_room  }
  mapper.mapprint (string.format ("MUSHclient mapper installed, version %0.1f", mapper.VERSION))

  -- load corpus
  assert (loadstring (GetVariable ("corpus") or "")) ()

  -- make sure each line type is in the corpus

  for k, v in pairs (line_types) do
    if not corpus [k] then
      corpus [k] = {}
    end -- not there yet

    for k2, v2 in ipairs (markers) do
      if not corpus [k] [v2.marker] then  -- if that marker not there, add it
         corpus [k] [v2.marker] = { } -- table of values for this marker
      end -- marker not there ;yet

    end -- for each marker type
  end -- for each line type

--  tprint (corpus)

  OnPluginWorldOutputResized ()

  -- clear debugging window
  if GetNotepadLength("Debug") > 0 then
    SendToNotepad ("Debug", "")
  end -- if
end -- OnPluginInstall

-- -----------------------------------------------------------------
-- Plugin Save State
-- -----------------------------------------------------------------
function OnPluginSaveState ()
  mapper.save_state ()
  SetVariable ("corpus", "corpus = " .. serialize.save_simple (corpus))
  SetVariable ("config", "config = " .. serialize.save_simple (config))
  SetVariable ("rooms",  "rooms = "  .. serialize.save_simple (rooms))
end -- OnPluginSaveState

local C1 = 2   -- weightings
local C2 = 1
local weight = 1
local MAX_WEIGHT = 2.0

-- calculate the probability one word is red or black
function CalcProbability (red, black)
 local pResult = ( (black - red) * weight )
                 / (C1 * (black + red + C2) * MAX_WEIGHT)
  return 0.5 + pResult
end -- CalcProbability


-- -----------------------------------------------------------------
-- update_corpus
--  add one to red or black for a certain value, for a certain type of line, for a certain marker type
-- -----------------------------------------------------------------
function update_corpus (which, marker, value, black)
  local which_corpus = corpus [which] [marker]
  -- make new one for this value if necessary
  if not which_corpus [value] then
     which_corpus [value] = { red = 0, black = 0, score = 0 }
  end -- end of this value not there yet
  if black then
     which_corpus [value].black = which_corpus [value].black + 1
  else
     which_corpus [value].red = which_corpus [value].red + 1
  end -- if
  which_corpus [value].score = assert (CalcProbability (which_corpus [value].red, which_corpus [value].black))
end -- update_corpus


-- -----------------------------------------------------------------
-- learn_line_type
--  The user is training a line type. Update the corpus for each line type to show that this set of
--  markers is/isn't in it.
-- -----------------------------------------------------------------
function learn_line_type (which, black)

  start_line = GetSelectionStartLine ()
  end_line = GetSelectionEndLine ()

  if start_line == 0 then
     WARNING ("No lines selected")
     return
  end -- if

  -- do all lines in the selection
  for line = start_line, end_line do
    -- process all the marker types, and add 1 to the red/black counter for that particular marker
    for k, v in ipairs (markers) do
      local value = v.func (line) -- call handler to get value
      update_corpus (which, v.marker, value, black)

--[[
      -- other line types do NOT match this, if it was black
      if black then
        for linetype in pairs (line_types) do
          if linetype ~= which then -- don't do the one which it IS
            update_corpus (linetype, v.marker, value, red)
          end -- if not the learning type
        end -- each line type
      end -- black learning
--]]

    end -- for each type of marker
  end -- for each line

  -- INFO (string.format ("Selection is from %d to %d", start_line, end_line))

  local s = ":"
  if not black then
    s = ": NOT"
  end -- if

  -- INFO ("Selected lines " .. s .. " " .. which)

  -- tprint (corpus)

end -- learn_line_type

--   See:
--     http://www.paulgraham.com/naivebayes.html
--   For a good explanation of the background, see:
--     http://www.mathpages.com/home/kmath267.htm.

-- calculate the probability a bunch of markers are ham (black)
function SetProbability (probs)
  local n, inv = 1, 1
  local i = 0
  for k, v in pairs (probs) do
    n = n * v
    inv = inv * (1 - v)
    i = i + 1
  end
  return  n / (n + inv)
end -- SetProbability

-- DO NOT DEBUG TO THE OUTPUT WINDOW IN THIS FUNCTION!
function analyse_line (line)
  local result = {}
  local line_type_probs = {}
  local marker_values = { }

  -- get the values first, they will stay the same for all line types
  for _, m in ipairs (markers) do
    marker_values [m.marker] = m.func (line) -- call handler to get value
  end -- for each type of marker

  DEBUG ("Debugging line", line, ":", GetLineInfo (line, 1))
  for line_type, line_type_info in pairs (line_types) do
    DEBUG ("  Line type", line_type)
    local probs = { }
    for _, m in ipairs (markers) do
      DEBUG ("    Marker", m.marker)
      local value = marker_values [m.marker] -- get previously-retrieved value
      DEBUG ("      Value", value)
      local corpus_value = corpus [line_type] [m.marker] [value]
      if corpus_value then
        assert (type (corpus_value) == 'table', 'corpus_value not a table')
        DEBUG ("        Score", tostring (corpus_value.score))
        table.insert (probs, corpus_value.score)
      end -- of having a value
    end -- for each type of marker
    local score = SetProbability (probs)
    table.insert (result, string.format ("%s: %3.2f", line_type_info.short, score))
    table.insert (line_type_probs, { line_type = line_type, score = score } )
  end -- for each line type
  table.sort (line_type_probs, function (a, b) return a.score > b.score end)
  if line_type_probs [1].score > 0.7 then
    return line_type_probs [1].line_type
  else
    return nil
  end -- if
end -- analyse_line

function process_exit_line ()

  if not description then
    WARNING "No description for this room"
    return
  end -- if no description

  -- generate a "room ID" by hashing the room description and exits
  uid = utils.tohex (utils.md5 (description .. exits_str))
  uid = uid:sub (1, 25)

  -- break up exits into individual directions
  local exits = {}

  -- for each word in the exits line, which happens to be an exit name (eg. "north") add to the table
  for exit in string.gmatch (exits_str, "%w+") do
    local ex = valid_direction [exit]
    if ex then
      exits [ex] = "0"  -- don't know where it goes yet
    end -- if
  end -- for

  -- show what we found
  for k, v in pairs (exits) do
    INFO ("Exit:", k)
  end -- for

  -- add room to rooms table if not already known
  if not rooms [uid] then
    INFO ("Mapper adding room " .. uid)
    rooms [uid] = { desc = description, exits = exits, area = "MUD", name = room_name or uid:sub (1, 8) }
  end -- if

  -- update room name if possible
  if room_name then
    rooms [uid].name = room_name
  end -- if

  INFO ("We are now in room " .. uid)

  -- save so we know current room later on
  current_room = uid

  -- show what we believe the current exits to be
  for k, v in pairs (rooms [uid].exits) do
    INFO ("Exit: " .. k .. " -> " .. v)
  end -- for

  -- call mapper to draw this room
  mapper.draw (uid)

  -- try to work out where previous room's exit led
  if expected_exit ~= uid and from_room then
    fix_up_exit ()
  end -- exit was wrong

  room_name = nil
  exits_str = nil
  description = nil
end -- process_exit_line


-- -----------------------------------------------------------------
-- mapper 'get_room' callback - it wants to know about room uid
-- -----------------------------------------------------------------

function get_room (uid)

  if not rooms [uid] then
   return nil
  end -- if

  local room = copytable.deep (rooms [uid])

  local texits = {}
  for dir in pairs (room.exits) do
    table.insert (texits, dir)
  end -- for
  table.sort (texits)

  local desc = string.gsub (room.desc, "%. .*", ".")
  if room.name and not string.match (room.name, "^%x+$") then
    desc = room.name
  end -- if

  room.hovermessage = string.format (
       "%s\tExits: %s\nRoom: %s\n%s",
        room.name or "unknown",
        table.concat (texits, ", "),
        uid,
        desc
      )

  if uid == current_room then
    room.bordercolour = config.OUR_ROOM_COLOUR.colour
    room.borderpenwidth = 2
  end -- not in this area

  return room

end -- get_room

-- -----------------------------------------------------------------
-- We have changed rooms - work out where the previous room led to
-- -----------------------------------------------------------------

function fix_up_exit ()

  -- where we were before
  local room = rooms [from_room]

  INFO ("Exit from " .. from_room .. " in the direction " .. last_direction_moved .. " was previously " .. (room.exits [last_direction_moved] or "nowhere"))
  -- leads to here
  room.exits [last_direction_moved] = current_room

  INFO ("Exit from " .. from_room .. " in the direction " .. last_direction_moved .. " is now " .. current_room)
  -- clear for next time
  last_direction_moved = nil
  from_room = nil

end -- fix_up_exit

-- -----------------------------------------------------------------
-- try to detect when we send a movement command
-- -----------------------------------------------------------------

function OnPluginSent (sText)
  if valid_direction [sText] then
    last_direction_moved = valid_direction [sText]
    INFO ("current_room =", current_room)
    INFO ("Just moving", last_direction_moved)
    if current_room and rooms [current_room] then
      expected_exit = rooms [current_room].exits [last_direction_moved]
      if expected_exit then
        from_room = current_room
      end -- if
    INFO ("Expected exit for this in direction " .. last_direction_moved .. " is to room", expected_exit)
    end -- if
  end -- if
end -- function



-- -----------------------------------------------------------------
-- Plugin just connected to world
-- -----------------------------------------------------------------

function OnPluginConnect ()
  from_room = nil
  last_direction_moved = nil
end -- OnPluginConnect

-- -----------------------------------------------------------------
-- Callback to show part of the room description, used by map_find
-- -----------------------------------------------------------------

FIND_OFFSET = 33

function show_find_details (uid)
  local this_room = rooms [uid]
  local desc = this_room.desc:lower ()
  local st, en = string.find (desc, wanted, 1, true)
  if not st then
    return
  end -- can't find the description, odd

  desc = this_room.desc

  local first, last
  local first_dots = ""
  local last_dots = ""

  for i = 1, #desc do

    -- find a space before the wanted match string, within the FIND_OFFSET range
    if not first and
       desc:sub (i, i) == ' ' and
       i < st and
       st - i <= FIND_OFFSET then
      first = i
      first_dots = "... "
    end -- if

    -- find a space after the wanted match string, within the FIND_OFFSET range
    if not last and
      desc:sub (i, i) == ' ' and
      i > en and
      i - en >= FIND_OFFSET then
      last = i
      last_dots = " ..."
    end -- if

  end -- for

  if not first then
    first = 1
  end -- if
  if not last then
    last = #desc
  end -- if

  mapper.mapprint (first_dots .. Trim (string.gsub (desc:sub (first, last), "\n", " ")) .. last_dots)

end -- show_find_details

-- -----------------------------------------------------------------
-- Find a room
-- -----------------------------------------------------------------

function map_find (name, line, wildcards)

  local room_ids = {}
  local count = 0
  wanted = (wildcards [1]):lower ()     -- NOT local

  -- scan all rooms looking for a simple match
  for k, v in pairs (rooms) do
     local desc = v.desc:lower ()
     if string.find (desc, wanted, 1, true) then
       room_ids [k] = true
       count = count + 1
     end -- if
  end   -- finding room

  -- see if nearby
  mapper.find (
    function (uid)
      local room = room_ids [uid]
      if room then
        room_ids [uid] = nil
      end -- if
      return room, next (room_ids) == nil
    end,  -- function
    show_vnums,  -- show vnum?
    count,      -- how many to expect
    false,      -- don't auto-walk
    show_find_details -- callback function
    )

end -- map_find

-- -----------------------------------------------------------------
-- Go to a room
-- -----------------------------------------------------------------

function map_goto (name, line, wildcards)

  local wanted = wildcards [1]

  if current_room and wanted == current_room then
    mapper.mapprint ("You are already in that room.")
    return
  end -- if

  if not string.match (wanted, "^%x+$") then
    mapper.mapprint ("Room IDs are hex strings (eg. FC758) - you can specify a partial string")
    return
  end -- if

  -- they are stored as upper-case
  wanted = wanted:upper ()

  -- find desired room
  mapper.find (
    function (uid)
      return string.match (uid, wanted), string.match (uid, wanted)
    end,  -- function
    show_vnums,  -- show vnum?
    1,          -- how many to expect
    true        -- just walk there
    )

end -- map_goto

last_deduced_type = nil
last_deduced_start_line = nil
last_deduced_end_line = nil

function line_received (name, line, wildcards, styles)
  local this_line = GetLinesInBufferCount()
  local deduced_type = analyse_line (this_line)

  if deduced_type ~= last_deduced_type then

    -- deal with previous line type
    -- INFO ("Now handling", last_deduced_type)

    if last_deduced_type then
      line_types [last_deduced_type].handler ()  -- handle the line(s)
    end -- if we have a type

    last_deduced_type = deduced_type
    last_deduced_start_line = this_line
    last_deduced_end_line = this_line
  end -- if line type has changed

  -- INFO ("This line is", deduced_type)
  last_deduced_end_line = this_line

end -- line_received
