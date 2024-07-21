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

 -------------------------------------------------------------------------

 EXPOSED FUNCTIONS

  set_line_type (linetype, contents) --> set this current line to be definitely linetype with option contents
  set_line_type_contents (linetype, contents)  --> sets the content for <linetype> to be <contents>
                                                   (for example, if you get a room name on a prompt line)
  set_not_line_type (linetype)       --> set this current line to be definitely not linetype (can call for multiple line types)
  set_area_name (name)               --> sets the name of the area you are in
  set_uid (uid)                      --> sets a string to be hashed as the UID for this room
  do_not_deduce_line_type (linetype) --> do not deduce (do Bayesian analysis) on this type of line - has to be set by set_line_type
  deduce_line_type (linetype)        --> deduce this line type (cancels do_not_deduce_line_type)
  get_last_line_type ()              --> get the previous line type as deduced or set by set_line_type
  get_this_line_type ()              --> get the current overridden line type (from set_line_type)
  set_config_option (name, value)    --> set a mapper configuration value of <name> to <value>
  get_config_option (name)           --> get the current configuration value of <name>
  get_corpus ()                      --> get the corpus (serialized table)
  get_stats ()                       --> get the training stats (serialized table)
  get_database ()                    --> get the mapper database (rooms table) (serialized table)
  get_config ()                      --> get the configuration options (serialized table)
  get_current_room ()                --> gets the current room's UID and room information (serialized table)
  set_room_extras (uid, extras)      --> sets extra information for the room (user-supplied)
                                          extras must be a string which serializes into a variable including a table
                                          eg. " { a = 42, b = 666, c = 'Kobold' } "


  eg. config = CallPlugin ("99c74b2685e425d3b6ed6a7d", "get_config")
               CallPlugin ("99c74b2685e425d3b6ed6a7d", "set_line_type", "exits")
               CallPlugin ("99c74b2685e425d3b6ed6a7d", "do_not_deduce_line_type", "exits")

  Note: The plugin ID is fixed as it is set in the Learning_Mapper.xml file near the top:
       id="99c74b2685e425d3b6ed6a7d"

--]]

LEARNING_MAPPER_LUA_VERSION = 2.1 -- version must agree with plugin version

-- The probability (in the range 0.0 to 1.0) that a line has to meet to be considered a certain line type.
-- The higher, the stricter the requirement.
-- Default of 0.7 seems to work OK, but you could tweak that.

PROBABILITY_CUTOFF = 0.7

-- other modules needed by this plugin
require "mapper"
require "serialize"
require "copytable"
require "commas"
require "tprint"
require "pairsbykeys"

-- our two windows
win = "window_type_info_" .. GetPluginID ()
learn_window = "learn_dialog_" .. GetPluginID ()

-- -----------------------------------------------------------------
-- Handlers for when a line-type changes
-- -----------------------------------------------------------------

description_styles = { }
exits_styles = { }
room_name_styles = { }

UNKNOWN_DUPLICATE_ROOM = string.rep ("F", 25)  -- dummy UID

DEBUGGING = false

function set_last_direction_moved (where)
  last_direction_moved = where
  DEBUG ("SET: last_direction_moved: " .. tostring (where))
end  -- set_last_direction_moved
function get_last_direction_moved ()
  DEBUG ("get: last_direction_moved: " .. tostring (last_direction_moved))
  return last_direction_moved
end  -- get_last_direction_moved
function set_from_room (where)
  from_room = where
  DEBUG ("SET: from_room: " .. fixuid (tostring (where)))
end  -- set_from_room
function get_from_room (f)
  if f then
    DEBUG ("get: from_room: " .. fixuid (tostring (from_room)) .. " (" .. f .. ")")
  else
    DEBUG ("get: from_room: " .. fixuid (tostring (from_room)))
  end -- if
  return from_room
end  -- get_from_room
function set_current_room (where)
  current_room = where
  DEBUG ("SET: current_room: " .. fixuid (tostring (where)))
end  -- set_current_room
function get_current_room_ (f)
  if f then
    DEBUG ("get: current_room: " .. fixuid (tostring (current_room)) .. " (" .. f .. ")")
  else
    DEBUG ("get: current_room: " .. fixuid (tostring (current_room)))
  end -- if
  return current_room
end  -- get_current_room_

-- -----------------------------------------------------------------
-- description
-- -----------------------------------------------------------------
function f_handle_description (saved_lines)

  if description and ignore_received then
    return
  end -- if

  -- if the description follows the exits, then ignore descriptions that don't follow exits
  if config.ACTIVATE_DESCRIPTION_AFTER_EXITS then
    if not exits_str then
      return
    end -- if
  end -- if

  -- if the description follows the room name, then ignore descriptions that don't follow the room name
  if config.ACTIVATE_DESCRIPTION_AFTER_ROOM_NAME then
    if not room_name then
      return
    end -- if
  end -- if

  local lines = { }
  description_styles = { }
  for _, line_info in ipairs (saved_lines) do
    table.insert (lines, line_info.line) -- get text of line
    table.insert (description_styles, line_info.styles [1])  -- remember first style run
  end -- for each line
  description = table.concat (lines, "\n")

  if config.WHEN_TO_DRAW_MAP == DRAW_MAP_ON_DESCRIPTION then
    process_new_room ()
  end -- if
end -- f_handle_description

-- -----------------------------------------------------------------
-- exits
-- -----------------------------------------------------------------
function f_handle_exits ()
  local lines = { }
  exits_styles = { }
  for _, line_info in ipairs (saved_lines) do
    table.insert (lines, line_info.line) -- get text of line
    table.insert (exits_styles, line_info.styles [1])  -- remember first style run
  end -- for each line
  exits_str = table.concat (lines, " "):lower ()

  if config.WHEN_TO_DRAW_MAP == DRAW_MAP_ON_EXITS then
    process_new_room ()
  end -- if
end -- f_handle_exits

-- -----------------------------------------------------------------
-- room name
-- -----------------------------------------------------------------
function f_handle_name ()
  local lines = { }
  room_name_styles = { }
  for _, line_info in ipairs (saved_lines) do
    table.insert (lines, line_info.line) -- get text of line
    table.insert (room_name_styles, line_info.styles [1])  -- remember first style run
  end -- for each line
  room_name = table.concat (lines, " ")

  -- a bit of a hack, but look for: Room name [N, S, W]
  if config.EXITS_ON_ROOM_NAME then
    local name, exits = string.match (room_name, "^([^%[]+)(%[.*%])%s*$")
    if name then
      room_name = name
      exits_str = exits:lower ()
    end -- if that sort of line found
  end -- if exits on room name wanted

  if config.WHEN_TO_DRAW_MAP == DRAW_MAP_ON_ROOM_NAME then
    process_new_room ()
  end -- if
end -- f_handle_name

-- -----------------------------------------------------------------
-- prompt
-- -----------------------------------------------------------------
function f_handle_prompt ()
  local lines = { }
  for _, line_info in ipairs (saved_lines) do
    table.insert (lines, line_info.line) -- get text of line
  end -- for each line
  prompt = table.concat (lines, " ")
  if config.WHEN_TO_DRAW_MAP == DRAW_MAP_ON_PROMPT then
    if override_contents ['description'] then
      description = override_contents ['description']
    end -- if
    if override_contents ['exits'] then
      exits_str = override_contents ['exits']:lower ()
    end -- if
    if override_contents ['room_name'] then
      room_name = override_contents ['room_name']
    end -- if
    if description and exits_str then
      process_new_room ()
    end -- if
  end -- if time to draw the map
end -- f_handle_prompt

-- -----------------------------------------------------------------
-- ignore this line type
-- -----------------------------------------------------------------
function f_handle_ignore ()
  ignore_received = true
end -- f_handle_ignore

-- -----------------------------------------------------------------
-- cannot move - cancel speedwalk
-- -----------------------------------------------------------------
function f_cannot_move ()
  mapper.cancel_speedwalk ()
  set_last_direction_moved (nil)  -- therefore we haven't moved anywhere
end -- f_cannot_move

-- -----------------------------------------------------------------
-- Handlers for getting the wanted value for a marker for the nominated line
-- -----------------------------------------------------------------

-- these are the types of lines we are trying to classify as a certain line IS or IS NOT that type
line_types = {
  room_name   = { short = "Room name",    handler = f_handle_name,        seq = 1 },
  description = { short = "Description",  handler = f_handle_description, seq = 2 },
  exits       = { short = "Exits",        handler = f_handle_exits,       seq = 3 },
  prompt      = { short = "Prompt",       handler = f_handle_prompt,      seq = 4 },
  ignore      = { short = "Ignore",       handler = f_handle_ignore,      seq = 5 },
  cannot_move = { short = "Can't move",   handler = f_cannot_move,        seq = 6 },
}  -- end of line_types table

function f_first_style_run_foreground (line)
  return { GetStyleInfo(line, 1, 14) or -1 }
end -- f_first_style_run_foreground

function f_show_colour (which, value)
  mapper.mapprint (string.format ("    %20s %5d %5d %7.2f", RGBColourToName (which), value.black, value.red, value.score))
end -- f_show_colour

function f_show_word (which, value)
  if #which > 20 then
    mapper.mapprint (string.format ("%s\n    %20s %5d %5d %7.2f", which, '', value.black, value.red, value.score))
  else
    mapper.mapprint (string.format ("    %20s %5d %5d %7.2f", which, value.black, value.red, value.score))
  end -- if
end -- f_show_colour

function f_first_word (line)
  if not GetLineInfo(line, 1) then
    return {}
  end -- no line available
  return { (string.match (GetLineInfo(line, 1), "^%s*(%a+)") or ""):lower () }
end -- f_first_word

function f_exact_line (line)
  if not GetLineInfo(line, 1) then
    return {}
  end -- no line available
  return { GetLineInfo(line, 1) }
end -- f_exact_line

function f_first_two_words (line)
  if not GetLineInfo(line, 1) then
    return {}
  end -- no line available
  return { (string.match (GetLineInfo(line, 1), "^%s*(%a+%s+%a+)") or ""):lower () }
end -- f_first_two_words

function f_first_three_words (line)
  if not GetLineInfo(line, 1) then
    return {}
  end -- no line available
  return { (string.match (GetLineInfo(line, 1), "^%s*(%a+%s+%a+%s+%a+)") or ""):lower () }
end -- f_first_three_words

function f_all_words (line)
  if not GetLineInfo(line, 1) then
    return {}
  end -- no line available
  local words = { }
  for w in string.gmatch (GetLineInfo(line, 1), "%a+") do
    table.insert (words, w:lower ())
  end -- for
  return words
end -- f_all_words

function f_first_character (line)
  if not GetLineInfo(line, 1) then
    return {}
  end -- no line available
  return { string.match (GetLineInfo(line, 1), "^.") or "" }
end -- f_first_character

-- -----------------------------------------------------------------
-- markers: things we are looking for, like colour of first style run
-- You could add others, for example:
--   * colour of the last style run
--   * number of words on the line
--   * number of style runs on the line
--  Whether that would help or not remains to be seen.

-- The functions above return the value(s) for the corresponding marker, for the nominated line.
-- -----------------------------------------------------------------
markers = {

  {
  desc = "Foreground colour of first style run",
  func = f_first_style_run_foreground,
  marker = "first_style_run_foreground",
  show = f_show_colour,
  accessing_function = pairs,
  },

  {
  desc = "First word in the line",
  func = f_first_word,
  marker = "first_word",
  show = f_show_word,
  accessing_function = pairsByKeys,

  },

 {
  desc = "First two words in the line",
  func = f_first_two_words,
  marker = "first_two_words",
  show = f_show_word,
  accessing_function = pairsByKeys,

  },

 {
  desc = "First three words in the line",
  func = f_first_three_words,
  marker = "first_three_words",
  show = f_show_word,
  accessing_function = pairsByKeys,

  },

  {
  desc = "All words in the line",
  func = f_all_words,
  marker = "all_words",
  show = f_show_word,
  accessing_function = pairsByKeys,

  },

 {
  desc = "Exact line",
  func = f_exact_line,
  marker = "exact_line",
  show = f_show_word,
  accessing_function = pairsByKeys,
  },

--[[

 {
  desc = "First character in the line",
  func = f_first_character,
  marker = "first_character",
  show = f_show_word,

  },

--]]

  } -- end of markers

inverse_markers = { }
for k, v in ipairs (markers) do
  inverse_markers [v.marker] = v
end -- for

local MAX_NAME_LENGTH = 60

-- when to update the map
DRAW_MAP_ON_ROOM_NAME = 1
DRAW_MAP_ON_DESCRIPTION = 2
DRAW_MAP_ON_EXITS = 3
DRAW_MAP_ON_PROMPT = 4


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
  TRAINER_FILL_COLOUR     = { name = "Trainer",           colour =  ColourNameToRGB "yellowgreen", },
  BANK_FILL_COLOUR        = { name = "Bank",              colour =  ColourNameToRGB "gold", },
  DUPLICATE_FILL_COLOUR   = { name = "Duplicate",         colour =  ColourNameToRGB "lightgoldenrodyellow", },
  BOOKMARK_FILL_COLOUR    = { name = "Notes",             colour =  ColourNameToRGB "lightskyblue", },
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

  -- config for learning mapper

  STATUS_BACKGROUND_COLOUR  = "black",       -- the background colour of the status window
  STATUS_FRAME_COLOUR       = "#1B1B1B",     -- the frame colour of the status window
  STATUS_TEXT_COLOUR        = "lightgreen",   -- palegreen is more visible

  UID_SIZE = 4,  -- how many characters of the UID to show

  -- learning configuration
  WHEN_TO_DRAW_MAP = DRAW_MAP_ON_EXITS,        -- we need to have name/description/exits to draw the map
  ACTIVATE_DESCRIPTION_AFTER_EXITS = false,    -- descriptions are activated *after* an exit line (used for MUDs with exits then descriptions)
  ACTIVATE_DESCRIPTION_AFTER_ROOM_NAME = false,-- descriptions are activated *after* a room name line
  BLANK_LINE_TERMINATES_LINE_TYPE = false,     -- if true, a blank line terminates the previous line type
  ADD_NEWLINE_TO_PROMPT = false,               -- if true, attempts to add a newline to a prompt at the end of a packet
  SHOW_LEARNING_WINDOW = true,                 -- if true, show the learning status and training windows on startup
  EXITS_ON_ROOM_NAME = false,                  -- if true, exits are listed on the room name line (eg. Starter Inventory and Shops [E, U])
  INCLUDE_EXITS_IN_HASH = true,                -- if true, exits are included in the description hash (UID)
  INCLUDE_ROOM_NAME_IN_HASH = false,           -- if true, the room name is included in the description hash (UID)
  EXITS_IS_SINGLE_LINE = false,                -- if true, exits are assumed to be only a single line
  PROMPT_IS_SINGLE_LINE = true,                -- if true, prompts are assumed to be only a single line
  EXIT_LINES_START_WITH_DIRECTION = false,     -- if true, exit lines must start with a direction (north, south, etc.)
  SORT_EXITS = false,                          -- if true, exit lines are extracted into words and sorted, excluding any other characters on the line
  SAVE_LINE_INFORMATION = true,                -- if true, we save to the database the colour of the first style run for name/description/exits

  -- other stuff

  SHOW_INFO = false,              -- if true, information messages are displayed
  SHOW_WARNINGS = true,           -- if true, warning messages are displayed
  SHOW_ROOM_AND_EXITS = false,    -- if true, exact deduced room name and exits are shown (needs SHOW_INFO)

  }

-- -----------------------------------------------------------------
-- Handlers for validating configuration values (eg. colour, boolean)
-- -----------------------------------------------------------------

function config_validate_colour (which)
  local colour = ColourNameToRGB (which)
  if colour == -1 then
    mapper.maperror (string.format ('Colour name "%s" not a valid HTML colour name or code.', which))
    mapper.mapprint ("  You can use HTML colour codes such as '#ab34cd' or names such as 'green'.")
    mapper.mapprint ("  See the Colour Picker (Edit menu -> Colour Picker: Ctrl+Alt+P).")
    return nil, nil
  end -- if bad
  return which, colour
end -- config_validate_colour

function config_validate_uid_size (which)
  local size = tonumber (which)
  if not size then
    mapper.maperror ("Bad UID size: " .. which)
    return nil
  end -- if

  if size < 3 or size > 25 then
    mapper.maperror ("UID size must be in the range 3 to 25")
    return nil
  end -- if

  return size
end -- config_validate_uid_size

-- -----------------------------------------------------------------
-- when we draw the map (after what sort of line)
-- -----------------------------------------------------------------
local when_types = {
    ["room name"]   = DRAW_MAP_ON_ROOM_NAME,
    ["description"] = DRAW_MAP_ON_DESCRIPTION,
    ["exits"]       = DRAW_MAP_ON_EXITS,
    ["prompt"]      = DRAW_MAP_ON_PROMPT,
    } -- end of table

function config_validate_when_to_draw (which)
  local when = which:lower ()

  local w = when_types [when]
  if not w then
    mapper.maperror ("Unknown time to draw the map: " .. which)
    mapper.mapprint ("Valid times are:")
    local t = { }
    for k, v in ipairs (when_types) do
      table.insert (t, k)
    end
    mapper.mapprint ("    " .. table.concat (t, ", "))
    return nil
  end -- if type not found

  return w
end -- when_to_draw

function convert_when_to_draw_to_name (which)
  local when = "Unknown"
  for k, v in pairs (when_types) do
    if which == v then
      when = k
      break
    end -- if
  end -- for
  return when
end -- convert_when_to_draw_to_name

local bools = {
  yes = true,
  y = true,
  no = false,
  n = false
} -- end of bools

function config_validate_boolean (which)
  local which = which:lower ()
  local yesno = bools [which]
  if yesno == nil then
    mapper.maperror ("Invalid option: must be YES or NO")
    return
  end -- not in bools table
  return yesno
end -- config_validate_boolean

-- -----------------------------------------------------------------
-- Handlers for displaying configuration values (eg. colour, boolean)
-- -----------------------------------------------------------------

function config_display_colour (which)
  return which
end -- config_display_colour

function config_display_number (which)
  return tostring (which)
end -- config_display_number

function config_display_when_to_draw (which)
  return convert_when_to_draw_to_name (which)
end -- config_display_when_to_draw

function config_display_boolean (which)
  if which then
    return "Yes"
  else
    return "No"
  end -- if
end -- config_display_boolean

-- -----------------------------------------------------------------
-- Configuration options (ie. mapper config <option>) and their handlers and internal option name
-- -----------------------------------------------------------------

config_control = {
  { option = 'WHEN_TO_DRAW_MAP',                  name = 'when_to_draw',                     validate = config_validate_when_to_draw, show = config_display_when_to_draw },
  { option = 'ACTIVATE_DESCRIPTION_AFTER_EXITS',  name = 'activate_description_after_exits', validate = config_validate_boolean,      show = config_display_boolean },
  { option = 'ACTIVATE_DESCRIPTION_AFTER_ROOM_NAME',  name = 'activate_description_after_room_name', validate = config_validate_boolean,      show = config_display_boolean },
  { option = 'ADD_NEWLINE_TO_PROMPT',             name = 'add_newline_to_prompt',            validate = config_validate_boolean,      show = config_display_boolean },
  { option = 'BLANK_LINE_TERMINATES_LINE_TYPE',   name = 'blank_line_terminates_line_type',  validate = config_validate_boolean,      show = config_display_boolean },
  { option = 'EXITS_ON_ROOM_NAME',                name = 'exits_on_room_name',               validate = config_validate_boolean,      show = config_display_boolean },
  { option = 'INCLUDE_EXITS_IN_HASH',             name = 'include_exits_in_hash',            validate = config_validate_boolean,      show = config_display_boolean },
  { option = 'INCLUDE_ROOM_NAME_IN_HASH',         name = 'include_room_name_in_hash',        validate = config_validate_boolean,      show = config_display_boolean },
  { option = 'EXITS_IS_SINGLE_LINE',              name = 'exits_is_single_line',             validate = config_validate_boolean,      show = config_display_boolean },
  { option = 'PROMPT_IS_SINGLE_LINE',             name = 'prompt_is_single_line',            validate = config_validate_boolean,      show = config_display_boolean },
  { option = 'EXIT_LINES_START_WITH_DIRECTION',   name = 'exit_lines_start_with_direction',  validate = config_validate_boolean,      show = config_display_boolean },
  { option = 'SORT_EXITS',                        name = 'sort_exits',                       validate = config_validate_boolean,      show = config_display_boolean },
  { option = 'STATUS_BACKGROUND_COLOUR',          name = 'status_background',                validate = config_validate_colour,       show = config_display_colour },
  { option = 'STATUS_FRAME_COLOUR',               name = 'status_border',                    validate = config_validate_colour,       show = config_display_colour },
  { option = 'STATUS_TEXT_COLOUR',                name = 'status_text',                      validate = config_validate_colour,       show = config_display_colour },
  { option = 'UID_SIZE',                          name = 'uid_size',                         validate = config_validate_uid_size,     show = config_display_number },
  { option = 'SAVE_LINE_INFORMATION',             name = 'save_line_info',                   validate = config_validate_boolean,      show = config_display_boolean },
  { option = 'SHOW_INFO',                         name = 'show_info',                        validate = config_validate_boolean,      show = config_display_boolean },
  { option = 'SHOW_WARNINGS',                     name = 'show_warnings',                    validate = config_validate_boolean,      show = config_display_boolean },
  { option = 'SHOW_ROOM_AND_EXITS',               name = 'show_room_and_exits',              validate = config_validate_boolean,      show = config_display_boolean },

}

-- make a table keyed on the name the user uses
config_control_names = { }
for k, v in ipairs (config_control) do
  config_control_names [v.name] = v
end -- for

-- -----------------------------------------------------------------
-- valid_direction - for detecting movement between rooms, and validating exit lines
-- -----------------------------------------------------------------

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
-- inverse_direction - if we go north then the inverse direction is south, and so on.
-- -----------------------------------------------------------------

inverse_direction = {
  n = "s",
  s = "n",
  e = "w",
  w = "e",
  u = "d",
  d = "u",
  ne = "sw",
  sw = "ne",
  nw = "se",
  se = "nw",
  ['in'] = "out",
  out = "in",
  }  -- end of inverse_direction

-- -----------------------------------------------------------------
-- OnPluginDrawOutputWindow
--  Update our line information info
-- -----------------------------------------------------------------
function OnPluginDrawOutputWindow (firstline, offset, notused)

  -- don't bother if window not visible
  if not WindowInfo (win, 5) then
    return
  end -- if

  local background_colour = ColourNameToRGB (config.STATUS_BACKGROUND_COLOUR)
  local frame_colour = ColourNameToRGB (config.STATUS_FRAME_COLOUR)
  local text_colour = ColourNameToRGB (config.STATUS_TEXT_COLOUR)
  local main_height = GetInfo (280)
  local font_height = GetInfo (212)

  -- clear window
  WindowRectOp (win, miniwin.rect_fill, 0, 0, 0, 0, background_colour)

  -- frame it
  WindowRectOp(win, miniwin.rect_frame, 0, 0, 0, 0, frame_colour)

  -- allow for scrolling position
  local top =  (((firstline - 1) * font_height) - offset) - 2

  -- how many lines to draw

  local lastline = firstline + (main_height / font_height)

  for line = firstline, lastline do
    if line >= 1 and GetLineInfo (line, 1) then
      if GetLineInfo (line, 4) or GetLineInfo (line, 5) then
        -- note or input line, ignore it
      else
        local linetype, probability, x_offset
        local ded = deduced_line_types [GetLineInfo (line, 10)]
        if ded and ded.lt then
          if ded.ov then
            line_type_info = string.format ("<- %s (certain)", line_types [ded.lt].short)
          else
            line_type_info = string.format ("<- %s (%0.0f%%)", line_types [ded.lt].short, (ded.con or 0) * 100)
          end -- if overridden or not
          local x_offset = WindowText (win, font_id, line_type_info, 1, top, 0, 0, text_colour)
          if (not GetLineInfo (line, 3)) and (line >= lastline - 1) then
            x_offset = x_offset + WindowText (win, font_id, " (partial line)", 1 + x_offset, top, 0, 0, ColourNameToRGB ("darkgray"))
          end -- if
          if ded.draw then
            x_offset = x_offset + WindowText (win, font_id,
                      string.format (" (draw room %s)", fixuid (ded.uid)), 1 + x_offset, top, 0, 0, ColourNameToRGB ("darkgray"))
          end -- if
        end -- if in deduced_line_types table
      end -- if output line
      top = top + font_height
    end -- if line exists
  end -- for each line

end -- OnPluginDrawOutputWindow

-- -----------------------------------------------------------------
-- OnPluginWorldOutputResized
--  On world window resize, remake the miniwindow to fit the size correctly
-- -----------------------------------------------------------------
function OnPluginWorldOutputResized ()

  font_name = GetInfo (20) -- output window font
  font_size = GetOption "output_font_height"

  local output_width  = GetInfo (240)  -- average width of pixels per character
  local wrap_column   = GetOption ('wrap_column')
  local pixel_offset  = GetOption ('pixel_offset')

  -- make window so I can grab the font info
  WindowCreate (win,
                (output_width * wrap_column) + pixel_offset + 10, -- left
                0,  -- top
                400, -- width
                GetInfo (263),   -- world window client height
                miniwin.pos_top_left,   -- position (irrelevant)
                miniwin.create_absolute_location,   -- flags
                ColourNameToRGB (config.STATUS_BACKGROUND_COLOUR))   -- background colour

  -- add font
  WindowFont (win, font_id, font_name, font_size,
              false, false, false, false,  -- normal
              miniwin.font_charset_ansi, miniwin.font_family_any)

  -- find height of font for future calculations
  font_height = WindowFontInfo (win, font_id, 1)  -- height

  WindowSetZOrder(win, -5)

   if WindowInfo (learn_window, 5) then
     WindowShow (win)
   end -- if

end -- OnPluginWorldOutputResized

-- -----------------------------------------------------------------
-- INFO helper function for debugging the plugin (information messages)
-- -----------------------------------------------------------------
function INFO (...)
  if config.SHOW_INFO then
    ColourNote ("orange", "", table.concat ( { ... }, " "))
  end -- if
end -- INFO

-- -----------------------------------------------------------------
-- WARNING helper function for debugging the plugin (warning/error messages)
-- -----------------------------------------------------------------
function WARNING (...)
  if config.SHOW_WARNINGS then
    ColourNote ("red", "", table.concat ( { ... }, " "))
  end -- if
end -- WARNING

-- -----------------------------------------------------------------
-- DEBUG helper function for debugging the plugin
-- -----------------------------------------------------------------
function DEBUG (...)
  if DEBUGGING then
    ColourNote ("cornflowerblue", "", table.concat ( { ... }, " "))
  end -- if
end -- DEBUG


-- -----------------------------------------------------------------
-- corpus_reset - throw away the learned corpus
-- -----------------------------------------------------------------
function corpus_reset (empty)
  if empty then
    corpus = { }
    stats  = { }
  end -- if

  -- make sure each line type is in the corpus

  for k, v in pairs (line_types) do
    if not corpus [k] then
      corpus [k] = {}
    end -- not there yet

    if not stats [k] then
      stats [k] = { is = 0, isnot = 0 }
    end -- not there yet

    for k2, v2 in ipairs (markers) do
      if not corpus [k] [v2.marker] then  -- if that marker not there, add it
         corpus [k] [v2.marker] = { } -- table of values for this marker
      end -- marker not there yet

    end -- for each marker type
  end -- for each line type

end -- corpus_reset

LEARN_WINDOW_WIDTH = 300
LEARN_WINDOW_HEIGHT = 270
LEARN_BUTTON_WIDTH = 80
LEARN_BUTTON_HEIGHT = 30

hotspots = { }
button_down = false

-- -----------------------------------------------------------------
-- button_mouse_down - generic mouse-down handler
-- -----------------------------------------------------------------
function button_mouse_down (flags, hotspot_id)
  local hotspot_info = hotspots [hotspot_id]
  if not hotspot_info then
    WARNING ("No info found for hotspot", hotspot_id)
    return
  end

  -- no button state change if no selection
  if GetSelectionStartLine () == 0 then
    return
  end -- if

  button_down = true
  WindowRectOp (hotspot_info.window, miniwin.rect_draw_edge,
                hotspot_info.x1, hotspot_info.y1, hotspot_info.x2, hotspot_info.y2,
                miniwin.rect_edge_sunken,
                miniwin.rect_edge_at_all + miniwin.rect_option_fill_middle)  -- sunken, filled
  WindowText   (hotspot_info.window, hotspot_info.font, hotspot_info.text, hotspot_info.text_x + 1, hotspot_info.y1 + 8 + 1, 0, 0, ColourNameToRGB "black", true)
  Redraw ()

end -- button_mouse_down

-- -----------------------------------------------------------------
-- button_cancel_mouse_down - generic cancel-mouse-down handler
-- -----------------------------------------------------------------
function button_cancel_mouse_down (flags, hotspot_id)
  local hotspot_info = hotspots [hotspot_id]
  if not hotspot_info then
    WARNING ("No info found for hotspot", hotspot_id)
    return
  end

  button_down = false
  buttons_active = nil

  WindowRectOp (hotspot_info.window, miniwin.rect_draw_edge,
                hotspot_info.x1, hotspot_info.y1, hotspot_info.x2, hotspot_info.y2,
                miniwin.rect_edge_raised,
                miniwin.rect_edge_at_all + miniwin.rect_option_fill_middle)  -- raised, filled
  WindowText   (hotspot_info.window, hotspot_info.font, hotspot_info.text, hotspot_info.text_x, hotspot_info.y1 + 8, 0, 0, ColourNameToRGB "black", true)

  Redraw ()
end -- button_cancel_mouse_down

-- -----------------------------------------------------------------
-- button_mouse_up - generic mouse-up handler
-- -----------------------------------------------------------------
function button_mouse_up (flags, hotspot_id)
  local hotspot_info = hotspots [hotspot_id]
  if not hotspot_info then
    WARNING ("No info found for hotspot", hotspot_id)
    return
  end

  button_down = false
  buttons_active = nil

  -- call the handler
  hotspot_info.handler ()

  WindowRectOp (hotspot_info.window, miniwin.rect_draw_edge,
                hotspot_info.x1, hotspot_info.y1, hotspot_info.x2, hotspot_info.y2,
                miniwin.rect_edge_raised,
                miniwin.rect_edge_at_all + miniwin.rect_option_fill_middle)  -- raised, filled
  WindowText   (hotspot_info.window, hotspot_info.font, hotspot_info.text, hotspot_info.text_x, hotspot_info.y1 + 8, 0, 0, ColourNameToRGB "black", true)

  Redraw ()
end -- button_mouse_up

-- -----------------------------------------------------------------
-- make_button - make a button for the dialog window and remember its handler
-- -----------------------------------------------------------------
function make_button (window, font, x, y, text, tooltip, handler)

  WindowRectOp (window, miniwin.rect_draw_edge, x, y, x + LEARN_BUTTON_WIDTH, y + LEARN_BUTTON_HEIGHT,
            miniwin.rect_edge_raised,
            miniwin.rect_edge_at_all + miniwin.rect_option_fill_middle)  -- raised, filled

  local width = WindowTextWidth (window, font, text, true)
  local text_x = x + (LEARN_BUTTON_WIDTH - width) / 2

  WindowText   (window, font, text, text_x, y + 8, 0, 0, ColourNameToRGB "black", true)

  local hotspot_id = string.format ("HS_learn_%d,%d", x, y)
  -- remember handler function
  hotspots [hotspot_id] = { handler = handler,
                            window = window,
                            x1 = x, y1 = y,
                            x2 = x + LEARN_BUTTON_WIDTH, y2 = y + LEARN_BUTTON_HEIGHT,
                            font = font,
                            text = text,
                            text_x = text_x }

  WindowAddHotspot(window,
                  hotspot_id,
                   x, y, x + LEARN_BUTTON_WIDTH, y + LEARN_BUTTON_HEIGHT,
                   "",                          -- MouseOver
                   "",                          -- CancelMouseOver
                   "button_mouse_down",         -- MouseDown
                   "button_cancel_mouse_down",  -- CancelMouseDown
                   "button_mouse_up",           -- MouseUp
                   tooltip,                     -- tooltip text
                   miniwin.cursor_hand,         -- mouse cursor shape
                   0)                           -- flags


end -- make_button

-- -----------------------------------------------------------------
-- update_buttons - grey-out buttons if nothing selected
-- -----------------------------------------------------------------

buttons_active = nil


-- stuff for warning them to save their file
time_last_saved = os.time ()
time_last_warned = nil

TIME_BETWEEN_SAVES = 15 * 60    -- warn if they haven't saved for 30 minutes
TIME_BETWEEN_WARNINGS = 1 * 60  -- warn every 1 minute
ADDED_ROOMS_COUNT = 10          -- warn if they have added this many rooms

function update_buttons (name)

  -- to save memory, throw away info for lines more than 1000 further back in the buffer
  local this_line = GetLinesInBufferCount()         -- which line in the output buffer
  local line_number = GetLineInfo (this_line, 10)   -- which line this was overall
  local wanted_line_number = line_number - 1000     -- keep info for 1000 lines

  if line_number then
    for k in pairs (deduced_line_types) do
       if k < wanted_line_number then
         deduced_line_types [k] = nil
        end -- for
    end -- for
  end -- if we have any lines

  -- warn user if database not saved after adding rooms

  -- how long since the last save
  local time_since_save = os.difftime (os.time (), time_last_saved)

  -- if they have added a few rooms and not saved then warn them
  if rooms_added >= ADDED_ROOMS_COUNT and     -- added a few rooms
    time_since_save > TIME_BETWEEN_SAVES and  -- not saved for a while
    (time_last_warned == nil or os.difftime (os.time (), time_last_warned) >= TIME_BETWEEN_WARNINGS) then  -- warn quite often after that time elapsed
    mapper.maperror (string.format ("WARNING: You have added %d rooms, but have not saved your world file recently.", rooms_added))
    mapper.mapprint ("Recommended: Save your world file (Ctrl+S) which will also save the mapper database.")
    time_last_warned = os.time ()
  end -- if

  -- do nothing if button pressed
  if button_down then
    return
  end -- if

  local have_selection = GetSelectionStartLine () ~= 0

  -- do nothing if the state hasn't changed
  if have_selection == buttons_active then
    return
  end -- if

  buttons_active = have_selection

  for hotspot_id, hotspot_info in pairs (hotspots) do
    if string.match (hotspot_id, "^HS_learn_") then
      local wanted_colour = ColourNameToRGB "black"
      if not buttons_active then
        wanted_colour = ColourNameToRGB "silver"
      end -- if
      WindowText   (hotspot_info.window, hotspot_info.font, hotspot_info.text, hotspot_info.text_x, hotspot_info.y1 + 8, 0, 0, wanted_colour, true)
    end -- if a learning button
  end -- for

  Redraw ()

end -- update_buttons

-- -----------------------------------------------------------------
-- mouseup_close_configure - they hit the close box in the learning window
-- -----------------------------------------------------------------
function mouseup_close_configure  (flags, hotspot_id)
  WindowShow (learn_window, false)
  WindowShow (win, false)
  mapper.mapprint ('Type: "mapper learn" to show the training window again')
  config.SHOW_LEARNING_WINDOW = false
end -- mouseup_close_configure

-- -----------------------------------------------------------------
-- toggle_learn_window - toggle the window: called from "mapper learn"
-- -----------------------------------------------------------------
function toggle_learn_window (name, line, wildcards)
  if WindowInfo (learn_window, 5) then
    WindowShow (win, false)
    WindowShow (learn_window, false)
    config.SHOW_LEARNING_WINDOW = false
  else
    WindowShow (win, true)
    WindowShow (learn_window, true)
    config.SHOW_LEARNING_WINDOW = true
  end -- if
end -- toggle_learn_window

-- -----------------------------------------------------------------
-- Plugin Install
-- -----------------------------------------------------------------
function OnPluginInstall ()

  font_id = "f"

  -- this table has the counters
  corpus = { }

  -- stats
  stats = { }

  -- load corpus
  assert (loadstring (GetVariable ("corpus") or "")) ()
  -- load stats
  assert (loadstring (GetVariable ("stats") or "")) ()

  config = {}  -- in case not found

  -- get saved configuration
  assert (loadstring (GetVariable ("config") or "")) ()

  corpus_reset ()

  -- allow for additions to config
  for k, v in pairs (default_config) do
    config [k] = config [k] or v
  end -- for


  -- and rooms
  rooms = {}
  assert (loadstring (GetVariable ("rooms") or "")) ()

  -- fix up in case I bugger up the exits
  for uid, room in pairs (rooms) do
    if not room.exits then
      room.exits = { }
    end -- if
  end -- if

  -- and duplicate rooms
  duplicates = {}
  assert (loadstring (GetVariable ("duplicates") or "")) ()

  -- initialize mapper

  mapper.init {
              config = config,            -- our configuration table
              get_room = get_room,        -- get info about a room
              room_click = room_click,    -- called on RH click on room square
              show_other_areas = true,    -- show all areas
              show_help = OnHelp,         -- to show help
  }
  mapper.mapprint (string.format ("[%s version %0.1f]", GetPluginName(), GetPluginInfo (GetPluginID (), 19)))
  mapper.mapprint (string.format ("MUSHclient mapper installed, version %0.1f", mapper.VERSION))

  local rooms_count = 0
  local explored_exits_count = 0
  local unexplored_exits_count = 0

  for uid, room in pairs (rooms) do
    rooms_count = rooms_count + 1
    for dir, exit_uid in pairs (room.exits) do
      if exit_uid == '0' then
        unexplored_exits_count = unexplored_exits_count + 1
      else
        explored_exits_count = explored_exits_count + 1
      end -- if
    end -- for each exit
  end -- for each room

  mapper.mapprint (string.format (
        "Mapper database loaded: %d rooms, %d explored exits, %d unexplored exits.",
         rooms_count, explored_exits_count, unexplored_exits_count))

  OnPluginWorldOutputResized ()

 -- find where window was last time

  windowinfo = movewindow.install (learn_window, miniwin.pos_center_right)

  learnFontName = get_preferred_font {"Dina",  "Lucida Console",  "Fixedsys", "Courier", "Sylfaen",}
  learnFontId = "f"
  learnFontSize = 9

  WindowCreate (learn_window,
                 windowinfo.window_left,
                 windowinfo.window_top,
                 LEARN_WINDOW_WIDTH,
                 LEARN_WINDOW_HEIGHT,
                 windowinfo.window_mode,   -- top right
                 windowinfo.window_flags,
                 ColourNameToRGB "lightcyan")

  WindowFont (learn_window, learnFontId, learnFontName, learnFontSize,
              true, false, false, false,  -- bold
              miniwin.font_charset_ansi, miniwin.font_family_any)

  -- find height of font for future calculations
  learn_font_height = WindowFontInfo (learn_window, font_id, 1)  -- height

  -- let them move it around
  movewindow.add_drag_handler (learn_window, 0, 0, 0, learn_font_height + 5)
  WindowRectOp (learn_window, miniwin.rect_fill, 0, 0, 0, learn_font_height + 5, ColourNameToRGB "darkblue", 0)
  draw_3d_box  (learn_window, 0, 0, LEARN_WINDOW_WIDTH, LEARN_WINDOW_HEIGHT)
  DIALOG_TITLE = "Learn line type"
  local width = WindowTextWidth (learn_window, learnFontId, DIALOG_TITLE, true)
  local x = (LEARN_WINDOW_WIDTH - width) / 2
  WindowText   (learn_window, learnFontId, DIALOG_TITLE, x, 3, 0, 0, ColourNameToRGB "white", true)

 -- close box
  local box_size = learn_font_height - 2
  local GAP = 5
  local y = 3
  local x = 1

  WindowRectOp (learn_window,
                miniwin.rect_frame,
                x + LEARN_WINDOW_WIDTH - box_size - GAP * 2,
                y + 1,
                x + LEARN_WINDOW_WIDTH - GAP * 2,
                y + 1 + box_size,
                0x808080)
  WindowLine (learn_window,
              x + LEARN_WINDOW_WIDTH - box_size - GAP * 2 + 3,
              y + 4,
              x + LEARN_WINDOW_WIDTH - GAP * 2 - 3,
              y - 2 + box_size,
              0x808080,
              miniwin.pen_solid, 1)
  WindowLine (learn_window,
              x - 4 + LEARN_WINDOW_WIDTH - GAP * 2,
              y + 4,
              x - 1 + LEARN_WINDOW_WIDTH - box_size - GAP * 2 + 3,
              y - 2 + box_size,
              0x808080,
              miniwin.pen_solid, 1)

  -- close configuration hotspot
  WindowAddHotspot(learn_window, "close_learn_dialog",
                   x + LEARN_WINDOW_WIDTH - box_size - GAP * 2,
                   y + 1,
                   x + LEARN_WINDOW_WIDTH - GAP * 2,
                   y + 1 + box_size,   -- rectangle
                   "", "", "", "", "mouseup_close_configure",  -- mouseup
                   "Click to close",
                   miniwin.cursor_hand, 0)  -- hand cursor


  -- the buttons for learning
  local LABEL_LEFT = 10
  local YES_BUTTON_LEFT = 100
  local NO_BUTTON_LEFT = YES_BUTTON_LEFT + LEARN_BUTTON_WIDTH + 20

  -- get the line types into my preferred order
  local sorted_line_types = { }
  for type_name in pairs (line_types) do
    table.insert (sorted_line_types, type_name)
  end -- for
  table.sort (sorted_line_types, function (a, b) return line_types [a].seq < line_types [b].seq end)

  local y = learn_font_height + 10
  for _, type_name in ipairs (sorted_line_types) do
    local type_info = line_types [type_name]
    WindowText   (learn_window, learnFontId, type_info.short, LABEL_LEFT, y + 8, 0, 0, ColourNameToRGB "black", true)

    make_button (learn_window, learnFontId, YES_BUTTON_LEFT, y, "Yes", "Learn selection IS " .. type_info.short,
                  function () learn_line_type (type_name, true) end)
    make_button (learn_window, learnFontId, NO_BUTTON_LEFT,  y, "No",  "Learn selection is NOT " .. type_info.short,
                  function () learn_line_type (type_name, false) end)

    y = y + LEARN_BUTTON_HEIGHT + 10

  end -- for

  WindowShow (learn_window, config.SHOW_LEARNING_WINDOW)
  WindowShow (win, config.SHOW_LEARNING_WINDOW)

  time_last_saved = os.time ()
  rooms_added = 0

end -- OnPluginInstall

-- -----------------------------------------------------------------
-- OnPluginClose
-- -----------------------------------------------------------------
function OnPluginClose ()
  WindowShow (learn_window, false)
  WindowShow (win, false)
  mapper.hide ()  -- hide the map
end -- OnPluginClose

-- -----------------------------------------------------------------
-- Plugin Save State
-- -----------------------------------------------------------------
function OnPluginSaveState ()
  mapper.save_state ()
  SetVariable ("corpus", "corpus = " .. serialize.save_simple (corpus))
  SetVariable ("stats", "stats = " .. serialize.save_simple (stats))
  SetVariable ("config", "config = " .. serialize.save_simple (config))
  SetVariable ("rooms",  "rooms = "  .. serialize.save_simple (rooms))
  SetVariable ("duplicates",  "duplicates = "  .. serialize.save_simple (duplicates))
  movewindow.save_state (learn_window)

  time_last_saved = os.time ()
  rooms_added = 0

  mapper.mapprint ("Mapping database saved.")

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
     WARNING ("No line(s) selected - select one or more lines (or part lines)")
     return
  end -- if

  if black then
    stats [which].is = stats [which].is + 1
  else
    stats [which].isnot = stats [which].isnot + 1
  end -- if

  -- do all lines in the selection
  for line = start_line, end_line do
    -- process all the marker types, and add 1 to the red/black counter for that particular marker
    for k, v in ipairs (markers) do
      local values = v.func (line) -- call handler to get values
      for _, value in ipairs (values) do
        update_corpus (which, v.marker, value, black)
      end -- for each value

    end -- for each type of marker
  end -- for each line

  -- INFO (string.format ("Selection is from %d to %d", start_line, end_line))

  local s = ":"
  if not black then
    s = ": NOT"
  end -- if

  -- INFO ("Selected lines " .. s .. " " .. which)

  -- tprint (corpus)

  Pause (false)

end -- learn_line_type

--   See:
--     http://www.paulgraham.com/naivebayes.html
--   For a good explanation of the background, see:
--     http://www.mathpages.com/home/kmath267.htm.

-- -----------------------------------------------------------------
-- SetProbability
-- calculate the probability a bunch of markers are ham (black)
--  using an array of probabilities, get an overall one
-- -----------------------------------------------------------------
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
-- -----------------------------------------------------------------
-- analyse_line
-- work out type of line by comparing its markers to the corpus
-- -----------------------------------------------------------------
function analyse_line (line)
  local result = {}
  local line_type_probs = {}
  local marker_values = { }

  if Trim (GetLineInfo (line, 1)) == "" then
    return nil
  end -- if blank line

  -- get the values first, they will stay the same for all line types
  for _, m in ipairs (markers) do
    marker_values [m.marker] = m.func (line) -- call handler to get values
  end -- for each type of marker

  for line_type, line_type_info in pairs (line_types) do
     -- don't if they don't want Bayesian deduction for this type
    if not do_not_deduce_linetypes [line_type] and not line_is_not_line_type [line_type] then
      local probs = { }
      for _, m in ipairs (markers) do
        marker_probs = { }  -- probability for this marker
        local values = marker_values [m.marker] -- get previously-retrieved values
        for _, value in ipairs (values) do
          local corpus_value = corpus [line_type] [m.marker] [value]
          if corpus_value then
            assert (type (corpus_value) == 'table', 'corpus_value not a table')
            --table.insert (probs, corpus_value.score)
            table.insert (marker_probs, corpus_value.score)
          end -- of having a value
        end -- for each value
        table.insert (probs, SetProbability (marker_probs))
      end -- for each type of marker
      local score = SetProbability (probs)
      table.insert (result, string.format ("%s: %3.2f", line_type_info.short, score))
      local first_word = (string.match (GetLineInfo(line, 1), "^%s*(%a+)") or ""):lower ()

      if line_type ~= 'exits' or
        (not config.EXIT_LINES_START_WITH_DIRECTION) or
        valid_direction [first_word] then
          table.insert (line_type_probs, { line_type = line_type, score = score } )
      end -- if
    end -- allowed to deduce this line type
  end -- for each line type
  table.sort (line_type_probs, function (a, b) return a.score > b.score end)
  if line_type_probs [1].score > PROBABILITY_CUTOFF then
    return line_type_probs [1].line_type, line_type_probs [1].score
  else
    return nil
  end -- if
end -- analyse_line

-- -----------------------------------------------------------------
-- fixuid
-- shorten a UID for display purposes
-- -----------------------------------------------------------------
function fixuid (uid)
  if not uid then
    return "NO_UID"
  end -- if nil
  return uid:sub (1, config.UID_SIZE)
end -- fixuid

function get_unique_styles (styles)
  local t = { }
  for k, v in ipairs (styles) do
    local s = string.format ("%d/%d/%d", v.textcolour, v.backcolour, v.style)
    if not t[s] then
      t [s] = v
    end -- if not there
  end -- for each supplied style

  local result = { }
  for k, v in pairs (t) do
    if v.textcolour == nil then
      tprint (v)
    end -- if
    table.insert (result, { fore = v.textcolour, back = v.backcolour, style = v.style } )
  end -- for each unique style
  return result
end -- get_unique_styles

-- -----------------------------------------------------------------
-- process_new_room
-- we have an exit line - work out where we are and what the exits are
-- -----------------------------------------------------------------
function process_new_room ()

  local from_room = get_from_room ("process_new_room")

  if override_contents ['description'] then
    description = override_contents ['description']
    description_styles = { }
  end -- if
  if override_contents ['exits'] then
    exits_str = override_contents ['exits']:lower ()
    exits_styles = { }
  end -- if
  if override_contents ['room_name'] then
    room_name = override_contents ['room_name']
    room_name_styles = { }
  end -- if

  if not description then
    if override_uid then
      description = "(none)"
    else
      WARNING "No description for this room"
      return
    end -- if
  end -- if no description

  if not exits_str then
    WARNING "No exits for this room"
    return
  end -- if no exits string

  if from_room and get_last_direction_moved () then
    local last_desc = "Unknown"
    if rooms [from_room] then
      desc = rooms [from_room].desc
    end -- if
    if last_desc == description then
      mapper.mapprint ("Warning: You have moved from a room to one with an identical description - the mapper may get confused.")
    end -- if

  end -- if moved from somewhere

  if config.SORT_EXITS then
    -- get all the exit words, exclude other crap, put them in a table, and sort it
    -- this is for MUDs that put markers after exit words to show if you have explored that way or not
    -- it is also to deal with MUDs that might sort the exits into different orders for some reason
    local t_exits = { }
    for exit in string.gmatch (exits_str, "%w+") do
      local ex = valid_direction [exit]
      if ex then
        table.insert (t_exits, ex)
      end -- if
    end -- for
    table.sort (t_exits)
    exits_str = table.concat (t_exits, " ")
  end -- if

  -- generate a "room ID" by hashing the room description and possibly the exits
  -- or, if supplied the override UID
  if override_uid then
    uid = utils.tohex (utils.md5 (override_uid))
  -- description / name / exits
  elseif config.INCLUDE_EXITS_IN_HASH and config.INCLUDE_ROOM_NAME_IN_HASH and room_name then
    uid = utils.tohex (utils.md5 (description .. exits_str .. room_name))
  -- description / exits
  elseif config.INCLUDE_EXITS_IN_HASH then
    uid = utils.tohex (utils.md5 (description .. exits_str))
  -- description / name
  elseif config.INCLUDE_ROOM_NAME_IN_HASH and room_name then
    uid = utils.tohex (utils.md5 (description .. room_name))
  else
  -- description only
    uid = utils.tohex (utils.md5 (description))
  end -- if

  uid = uid:sub (1, 25)
  local duplicate = nil

  current_room_hash = uid   -- in case of duplicate rooms

  -- is this a known duplicate room?
  if duplicates [current_room_hash] then
    INFO ("<<This is a duplicate room identified by hash " .. fixuid (uid) .. ">>")
    -- yes, so disregard the uid and work out where we came from

    if not (from_room and get_last_direction_moved ()) then
      -- make up some non-existent UID and give up
      uid = UNKNOWN_DUPLICATE_ROOM
      INFO ("Hit a duplicate room, but don't know where we came from, giving up.")
    else
      -- the UID is known to the room that led to this
      uid = rooms [from_room].exits [get_last_direction_moved ()]
      if not uid or uid == "0" then
        uid = UNKNOWN_DUPLICATE_ROOM
        INFO ("No exit known going " .. get_last_direction_moved ()  .. " from " .. fixuid (from_room))
      elseif duplicates [uid] then
        uid = UNKNOWN_DUPLICATE_ROOM
        INFO ("Hit a duplicate room, disregarding " .. get_last_direction_moved ()  .. " exit from " .. fixuid (from_room))
      end -- if
    end -- if we don't know where we came from

  end -- if

  if uid == UNKNOWN_DUPLICATE_ROOM and from_room and get_last_direction_moved () then
    INFO ("Entering unknown duplicate room - querying whether to make a new room here")
    local a, b, c = get_last_direction_moved (), fixuid (from_room), fixuid (current_room_hash)
    local answer = utils.msgbox (string.format ("Entering duplicate room %s, make new room leading %s from %s?",
                    fixuid (current_room_hash), get_last_direction_moved (), fixuid (from_room)),
            "Duplicate room", "yesno", "?", 1)
    INFO (string.format ("Response to query: Make a new room leading %s from %s to %s (duplicate)?: %s",
          a, b, c, answer))
    if answer == "yes" then
      uid = utils.tohex (utils.md5 (string.format ("%0.9f/%0.9f/%0.9f/%d",
                              math.random (), math.random (), math.random (), os.time ()))):sub (1, 25)
      rooms [from_room].exits [get_last_direction_moved ()] = uid
      INFO (string.format ("Adding new room with random UID (%s) leading %s from %s", fixuid (uid), get_last_direction_moved (), fixuid (from_room)))
      duplicate = current_room_hash
    end -- if

  end -- if

  if uid == UNKNOWN_DUPLICATE_ROOM then
    set_from_room (nil)
    from_room = nil  -- local copy
  end -- if we don't know where we are

  if config.SHOW_ROOM_AND_EXITS then
    INFO (string.format ("Description:\n'%s'\nExits: '%s'\nHash: %s", description, exits_str, fixuid (uid)))
  end -- if config.SHOW_ROOM_AND_EXITS

  if uid == UNKNOWN_DUPLICATE_ROOM then
    desc = "Unknown duplicate room"
    exits_str = ""
    room_name = "Unknown duplicate of " .. fixuid (current_room_hash)
  end -- if

  -- break up exits into individual directions
  local exits = {}

  -- for each word in the exits line, which happens to be an exit name (eg. "north") add to the table
  for exit in string.gmatch (exits_str, "%w+") do
    local ex = valid_direction [exit]
    if ex then
      exits [ex] = "0"  -- don't know where it goes yet
    end -- if
  end -- for


  -- add room to rooms table if not already known
  if not rooms [uid] then
    INFO ("Mapper adding room " .. fixuid (uid))
    rooms [uid] = {
        desc = description,
        exits = exits,
        area = area_name or WorldName (),
        name = room_name or fixuid (uid),
        duplicate = duplicate,   -- which UID, if any, this is a duplicate of
        } -- end of new room table

    if config.SAVE_LINE_INFORMATION then
      rooms [uid].styles = {
                           name   = get_unique_styles (room_name_styles),
                           exits  = get_unique_styles (exits_styles),
                           desc   = get_unique_styles (description_styles),
                           } -- end of styles
    end -- if

    rooms_added = rooms_added + 1
  else
    -- room there - add exits not known
    for dir in pairs (exits) do
      if not rooms [uid].exits [dir] then
        rooms [uid].exits [dir]  = "0"
        INFO ("Adding exit", dir)
      end -- if exit not there
    end -- for each exit we now about *now*

    -- remove exits that don't exist
    for dir in pairs (rooms [uid].exits) do
      if not exits [dir] then
        INFO ("Removing exit", dir)
        rooms [uid].exits [dir] = nil
      end -- if
    end -- for each exit in the existing room
  end -- if

  -- update room name if possible
  if room_name then
    rooms [uid].name = room_name
  end -- if

  INFO ("We are now in room " .. fixuid (uid))
  -- INFO ("Description: ", description)

  -- save so we know current room later on
  set_current_room (uid)

  -- show what we believe the current exits to be
  for dir, dest in pairs (rooms [uid].exits) do
    local probable = ''
    if dest == '0' then
      exit_uid = find_probable_room (uid, dir)
      if exit_uid then
        probable = ' (Probably ' .. fixuid (exit_uid) .. ')'
      end -- if
    end -- if
    INFO ("Exit: " .. dir .. " -> " .. fixuid (dest) .. probable)
  end -- for

  -- try to work out where previous room's exit led
  if get_last_direction_moved () and
     expected_exit ~= uid and
     from_room and uid ~= UNKNOWN_DUPLICATE_ROOM then
    fix_up_exit ()
  end -- exit was wrong

  -- warn them to explore nearby rooms
  if rooms [uid].duplicate then
    local unexplored = { }
    for dir, dest in pairs (rooms [uid].exits) do
      if dest == "0" then
        table.insert (unexplored, dir:upper ())
      end -- not explored
    end -- for each exit
    if #unexplored > 0 then
      local s = 's'
      local u = ' until none left'
      if #unexplored == 1 then
        s = ''
        u = ''
      end -- if
      mapper.mapprint ("Inside duplicated room. Please explore exit" .. s .. ": " ..
                      table.concat (unexplored, ", ") ..
                      " and then return here" .. u)
    end -- if
  end -- if

  -- call mapper to draw this room
  mapper.draw (uid)
  last_drawn_id = uid    -- in case they change the window size

  -- emergency fallback to stop lots of errors
  if not deduced_line_types [line_number] then
    deduced_line_types [line_number] = { }
  end -- if

  deduced_line_types [line_number].draw = true
  deduced_line_types [line_number].uid = get_current_room_ ("process_new_room")

  DEBUG "Finished processing new room"

  room_name = nil
  exits_str = nil
  description = nil
  set_last_direction_moved (nil)
  ignore_received = false
  override_line_type = nil
  override_line_contents = nil
  override_uid = nil
  line_is_not_line_type = { }
  override_contents = { }
  description_styles = { }
  exits_styles = { }
  room_name_styles = { }

end -- process_new_room


-- -----------------------------------------------------------------
-- mapper 'get_room' callback - it wants to know about room uid
-- -----------------------------------------------------------------

function get_room (uid)

  if not rooms [uid] then
   return nil
  end -- if

  local room = copytable.deep (rooms [uid])

  local texits = {}
  for dir,dest in pairs (room.exits) do
    table.insert (texits, dir .. " -> " .. fixuid (dest))
  end -- for
  table.sort (texits)

  -- get first sentence of description
  local desc = room.desc
  if desc:sub (1, #room.name) == room.name then
    desc = desc:sub (#room.name + 1)
  end -- if
  desc = Trim ((string.match (desc, "^[^.]+") or desc) .. ".")
  if room.name and not string.match (room.name, "^%x+$") then
    -- desc = room.name
  end -- if

  local textras = { }
  if room.Bank then
    table.insert (textras, "Bank")
  end -- if
  if room.Shop then
    table.insert (textras, "Shop")
  end -- if
  if room.Trainer then
    table.insert (textras, "Trainer")
  end -- if
  local extras = ""
  if #textras then
    extras = "\n" .. table.concat (textras, ", ")
  end -- if extras

  local notes = ""
  if room.notes then
    notes = "\nNotes: " .. room.notes
  end -- if notes

  room.hovermessage = string.format (
       "%s\tExits: %s\nRoom: %s%s\n%s\n%s",
        room.name or "unknown",
        table.concat (texits, ", "),
        fixuid (uid),
        extras,
        desc,
        notes
      )

  room.borderpenwidth = 1 -- default

  if uid == current_room then
    room.bordercolour = config.OUR_ROOM_COLOUR.colour
    room.borderpenwidth = 2
  end -- not in this area

  room.fillbrush = miniwin.brush_null -- no fill

  -- special room fill colours

  if room.notes and room.notes ~= "" then
    room.fillcolour = config.BOOKMARK_FILL_COLOUR.colour
    room.fillbrush = miniwin.brush_solid
  elseif room.Shop then
    room.fillcolour = config.SHOP_FILL_COLOUR.colour
    room.fillbrush = miniwin.brush_fine_pattern
  elseif room.Trainer then
    room.fillcolour = config.TRAINER_FILL_COLOUR.colour
    room.fillbrush = miniwin.brush_fine_pattern
  elseif room.Bank then
    room.fillcolour = config.BANK_FILL_COLOUR.colour
    room.fillbrush = miniwin.brush_fine_pattern
  end -- if

  if room.duplicate then
    room.fillcolour = config.DUPLICATE_FILL_COLOUR.colour
    room.fillbrush = miniwin.brush_fine_pattern
  end -- if

  return room
end -- get_room

-- -----------------------------------------------------------------
-- We have changed rooms - work out where the previous room led to
-- -----------------------------------------------------------------

function fix_up_exit ()

  local current_room = get_current_room_ ("fix_up_exit")
  local from_room = get_from_room ("fix_up_exit")
  local last_direction_moved = get_last_direction_moved ("fix_up_exit")

  -- where we were before
  local room = rooms [from_room]

  INFO ("Exit from " .. fixuid (from_room) .. " in the direction " .. last_direction_moved .. " was previously " .. (fixuid (room.exits [last_direction_moved]) or "nowhere"))
  -- leads to here

  if from_room == current_room then
    WARNING ("Declining to set the exit " .. last_direction_moved .. " from this room to be itself")
  else
    room.exits [last_direction_moved] = current_room
    INFO ("Exit from " .. fixuid (from_room) .. " in the direction " .. last_direction_moved .. " is now " .. fixuid (current_room))
  end -- if

  -- do inverse direction as a guess
  local inverse = inverse_direction [last_direction_moved]
  if inverse and current_room then
    if duplicates [rooms [current_room].exits [inverse]] then
      rooms [current_room].exits [inverse] = '0'
    end -- if
    if rooms [current_room].exits [inverse] == '0' then
      rooms [current_room].exits [inverse] = from_room
      INFO ("Added inverse direction from " .. fixuid (current_room) .. " in the direction " .. inverse .. " to be " .. fixuid (from_room))
    end -- if
  end -- of having an inverse


  -- clear for next time
  set_last_direction_moved (nil)
  set_from_room (nil)

end -- fix_up_exit

-- -----------------------------------------------------------------
-- try to detect when we send a movement command
-- -----------------------------------------------------------------

function OnPluginSent (sText)

  local current_room = get_current_room_ ("OnPluginSent")

  if valid_direction [sText] then
    set_last_direction_moved (valid_direction [sText])
    INFO ("current_room =", fixuid (current_room))
    INFO ("Just moving", get_last_direction_moved ())
    if current_room and rooms [current_room] then
      expected_exit = rooms [current_room].exits [get_last_direction_moved ()]
      if expected_exit then
        set_from_room (current_room)
      end -- if
    INFO ("Expected exit for this in direction " .. get_last_direction_moved () .. " is to room", fixuid (expected_exit))
    end -- if
  end -- if
end -- function

-- -----------------------------------------------------------------
-- Plugin just connected to world
-- -----------------------------------------------------------------

function OnPluginConnect ()
  mapper.cancel_speedwalk ()
  set_from_room (nil)
  room_name = nil
  exits_str = nil
  description = nil
  set_last_direction_moved (nil)
  ignore_received = false
  override_line_type = nil
  override_line_contents = nil
  override_contents = { }
  line_is_not_line_type = { }
  set_current_room (nil)
end -- OnPluginConnect

-- -----------------------------------------------------------------
-- Plugin just disconnected from world
-- -----------------------------------------------------------------

function OnPluginDisconnect ()
  mapper.cancel_speedwalk ()
end -- OnPluginDisconnect

-- -----------------------------------------------------------------
-- Callback to show part of the room description/name/notes, used by map_find
-- -----------------------------------------------------------------

FIND_OFFSET = 33

function show_find_details (uid)
  local this_room = rooms [uid]
  local target = this_room.desc
  local label = "Description: "
  local st, en = string.find (target:lower (), wanted, 1, true)
  -- not in description, try the name
  if not st then
    target = this_room.name
    label = "Room name: "
    st, en = string.find (target:lower (), wanted, 1, true)
    if not st then
      target = this_room.notes
      label = "Notes: "
      if target then
        st, en = string.find (target:lower (), wanted, 1, true)
      end -- if any notes
    end -- not found in the name
  end -- can't find the wanted text anywhere, odd


  local first, last
  local first_dots = ""
  local last_dots = ""

  for i = 1, #target do

    -- find a space before the wanted match string, within the FIND_OFFSET range
    if not first and
       target:sub (i, i) == ' ' and
       i < st and
       st - i <= FIND_OFFSET then
      first = i
      first_dots = "... "
    end -- if

    -- find a space after the wanted match string, within the FIND_OFFSET range
    if not last and
      target:sub (i, i) == ' ' and
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
    last = #target
  end -- if

  mapper.mapprint (label .. first_dots .. Trim (string.gsub (target:sub (first, last), "\n", " ")) .. last_dots)

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
     local name = v.name:lower ()
     local notes = ""
     if v.notes then
       notes = v.notes:lower ()
      end -- if notes
     if string.find (desc, wanted, 1, true) or
        string.find (name, wanted, 1, true) or
        string.find (notes, wanted, 1, true) then
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
-- mapper_show_bookmarked_room - callback to show a bookmark
-- -----------------------------------------------------------------
function mapper_show_bookmarked_room (uid)
  local this_room = rooms [uid]
  mapper.mapprint (this_room.notes)
end -- mapper_show_bookarked_room

-- -----------------------------------------------------------------
-- Find bookmarked rooms
-- -----------------------------------------------------------------
function map_bookmarks (name, line, wildcards)

  local room_ids = {}
  local count = 0

  -- scan all rooms looking for a simple match
  for k, v in pairs (rooms) do
    if v.notes and v.notes ~= "" then
      room_ids [k] = true
      count = count + 1
    end -- if
  end   -- finding room

  -- find such places
  mapper.find (
    function (uid)
      local room = room_ids [uid]
      if room then
        room_ids [uid] = nil
      end -- if
      return room, next (rooms) == nil  -- room will be type of info (eg. shop)
    end,  -- function
    show_vnums,  -- show vnum?
    count,       -- how many to expect
    false,       -- don't auto-walk
    mapper_show_bookmarked_room  -- callback function to show the room bookmark
    )

end -- map_bookmarks

-- -----------------------------------------------------------------
-- Go to a room
-- -----------------------------------------------------------------

function map_goto (name, line, wildcards)

  if not mapper.check_we_can_find () then
    return
  end -- if

  local wanted = wildcards [1]

  if not string.match (wanted, "^%x+$") then
    mapper.mapprint ("Room IDs are hex strings (eg. FC758) - you can specify a partial string")
    return
  end -- if

  local goto_uid, room = find_room_partial_uid (wanted)
  if not goto_uid then
    return
  end -- if not found

  local current_room = get_current_room_ ("map_goto")
  if current_room and goto_uid == current_room then
    mapper.mapprint ("You are already in that room.")
    return
  end -- if

  -- find desired room
  mapper.find (
    function (uid)
      return uid == goto_uid, uid == goto_uid
    end,  -- function
    show_vnums,  -- show vnum?
    1,          -- how many to expect
    true        -- just walk there
    )

end -- map_goto

-- -----------------------------------------------------------------
-- line_received - called by a trigger on all lines
--   work out its line type, and then handle a line-type change
-- -----------------------------------------------------------------

last_deduced_type = nil
saved_lines = { }
deduced_line_types = { }

function line_received (name, line, wildcards, styles)

  -- these need to be global, for use later on
  this_line = GetLinesInBufferCount()         -- which line in the output buffer
  line_number = GetLineInfo (this_line, 10)   -- which line this was overall

  local deduced_type, probability

  -- see if a plugin has overriden the line type
  if override_line_type then
    deduced_type = override_line_type
    if override_line_contents then
      line = override_line_contents
    end -- if new contents wanted
  else
    if (not config.BLANK_LINE_TERMINATES_LINE_TYPE) and Trim (line) == "" then
      return
    end -- if empty line

    if config.BLANK_LINE_TERMINATES_LINE_TYPE and Trim (line) == "" then
      deduced_type = nil
    else
      deduced_type, probability = analyse_line (this_line)
    end -- if

  end -- if

  -- record for scrollback buffer
  if deduced_type then
    deduced_line_types [line_number] = {
        lt = deduced_type,  -- what type we assigned to it
        con = probability,  -- with what probability
        draw = false,       -- did we draw on this line?
        ov = override_line_type,  -- was it overridden?
        }
  end -- if not nil type

  -- INFO ("This line is", deduced_type, "last type was", last_deduced_type)

  if deduced_type ~= last_deduced_type then

    -- deal with previous line type
    -- INFO ("Now handling", last_deduced_type)

    if last_deduced_type then
      line_types [last_deduced_type].handler (saved_lines)  -- handle the line(s)
    end -- if we have a type

    last_deduced_type = deduced_type
    saved_lines = { }
  end -- if line type has changed


  table.insert (saved_lines, { line = line, styles = styles } )

  -- if exits are on a single line, then we can process them as soon as we get them
  if config.EXITS_IS_SINGLE_LINE and deduced_type == 'exits' then
      -- INFO ("Now handling", deduced_type)
      line_types.exits.handler (saved_lines)  -- handle the line
      saved_lines = { }
      last_deduced_type = nil
  end -- if

  -- if prompt are on a single line, then we can process it as soon as we get it
  if config.PROMPT_IS_SINGLE_LINE and deduced_type == 'prompt' then
      -- INFO ("Now handling", deduced_type)
      line_types.prompt.handler (saved_lines)  -- handle the line
      saved_lines = { }
      last_deduced_type = nil
  end -- if

  -- reset back ready for next line
  line_is_not_line_type = { }
  override_line_type = nil

end -- line_received

-- -----------------------------------------------------------------
-- corpus_info - show how many times we trained the corpus
-- -----------------------------------------------------------------

function corpus_info ()
  mapper.mapprint  (string.format ("%20s %5s %5s", "Line type", "is", "not"))
  mapper.mapprint  (string.format ("%20s %5s %5s", string.rep ("-", 15), string.rep ("-", 5), string.rep ("-", 5)))
  for k, v in pairs (stats) do
    mapper.mapprint  (string.format ("%20s %5d %5d", k, v.is, v.isnot))
  end -- for each line type
  mapper.mapprint ("There are " .. count_values (corpus) .. " entries in the corpus.")
end -- corpus_info

-- -----------------------------------------------------------------
-- OnHelp - show help
-- -----------------------------------------------------------------
function OnHelp ()
  local p = mapper.mapprint
	mapper.mapprint (string.format ("[MUSHclient mapper, version %0.1f]", mapper.VERSION))
  p (string.format ("[%s version %0.1f]", GetPluginName(), GetPluginInfo (GetPluginID (), 19)))
  p (string.rep ("-", 78))
	p (GetPluginInfo (GetPluginID (), 3))
  p (string.rep ("-", 78))

  -- Tell them where to get the latest mapper plugin
  local old_note_colour = GetNoteColourFore ()
  SetNoteColourFore(config.MAPPER_NOTE_COLOUR.colour)

  Tell ("Lastest mapper plugin: ")
  Hyperlink ("https://github.com/nickgammon/plugins/blob/master/Learning_Mapper.xml",
             "Learning_Mapper.xml", "Click to see latest plugin", "darkorange", "", true)
  Tell (" and ")
  Hyperlink ("https://github.com/nickgammon/plugins/blob/master/Learning_Mapper.lua",
             "Learning_Mapper.lua", "Click to see latest plugin", "darkorange", "", true)
  p ""
  p ('You need both files. RH-click the "Raw" button on those pages to download the files.')
  Tell ('Save them to the folder: ')
  ColourNote ("orange", "", GetPluginInfo (GetPluginID (), 20))
  p (string.rep ("-", 78))
  SetNoteColourFore (old_note_colour)

end

-- -----------------------------------------------------------------
-- map_where - where is the specified room? (by uid)
-- -----------------------------------------------------------------
function map_where (name, line, wildcards)

  if not mapper.check_we_can_find () then
    return
  end -- if

  local wanted = wildcards [1]:upper ()

  if not string.match (wanted, "^%x+$") then
    mapper.mapprint ("Room IDs are hex strings (eg. FC758) - you can specify a partial string")
    return
  end -- if

  local where_uid, room = find_room_partial_uid (wanted)
  if not where_uid then
    return
  end -- if not found

  local current_room = get_current_room_ ("map_where")

  if current_room and where_uid == current_room then
    mapper.mapprint ("You are already in that room.")
    return
  end -- if

  local paths = mapper.find_paths (current_room,
           function (uid)
            return uid == where_uid, uid == where_uid
            end)

  local uid, item = next (paths, nil) -- extract first (only) path

  -- nothing? room not found
  if not item then
    mapper.mapprint (string.format ("Room %s not found", wanted))
    return
  end -- if

  -- turn into speedwalk
  local path = mapper.build_speedwalk (item.path)

  -- display it
  mapper.mapprint (string.format ("Path to %s (%s) is: %s", wanted, rooms [where_uid].name, path))

end -- map_where

-- -----------------------------------------------------------------
-- OnPluginPacketReceived - try to add newlines to prompts if wanted
-- -----------------------------------------------------------------
function OnPluginPacketReceived (pkt)

  if not config.ADD_NEWLINE_TO_PROMPT then
    return pkt
  end -- if

  -- add a newline to the end of a packet if it appears to be a simple prompt
  -- (just a ">" sign at the end of a line optionally followed by one space)
  if GetInfo (104) then  -- if MXP enabled
    if string.match (pkt, "&gt; ?$") then
      return pkt .. "\n"
    end -- if
  else
    if string.match (pkt, "> ?$") then  -- > symbol at end of packet
      return pkt .. "\n"
    elseif string.match (pkt, "> ?\027%[0m ?$") then -- > symbol at end of packet followed by ESC [0m
      return pkt .. "\n"
    end -- if
  end -- if MXP or not

  return pkt
end -- OnPluginPacketReceived

-- -----------------------------------------------------------------
-- show_corpus - show all values in the corpus, printed nicely
-- -----------------------------------------------------------------
function show_corpus ()

  -- start with each line type (eg. exits, descriptions)
  for name, type_info in pairs (line_types) do
    mapper.mapprint (string.rep ("=", 72))
    mapper.mapprint (type_info.short)
    mapper.mapprint (string.rep ("=", 72))
    corpus_line_type = corpus [name]
    -- for each one show each marker type (eg. first word, all words, colour)
    for _, marker in ipairs (markers) do
      mapper.mapprint ("  " .. string.rep ("-", 70))
      mapper.mapprint ("  " .. marker.desc)
      mapper.mapprint ("  " .. string.rep ("-", 70))
      local f = marker.show
      local accessing_function  = marker.accessing_function  -- pairs for numbers or pairsByKeys for strings
      if f then
        mapper.mapprint (string.format ("    %20s %5s %5s %7s", "Value", "Yes", "No", "Score"))
        mapper.mapprint (string.format ("    %20s %5s %5s %7s", "-------", "---", "---", "-----"))
        -- for each marker show each value, along with its counts for and against, and its calculated score
        for k, v in accessing_function (corpus_line_type [marker.marker], function (a, b) return a:lower () < b:lower () end ) do
          f (k, v)
        end -- for each value
      end -- if function exists
    end -- for each marker type
  end -- for each line type

end -- show_corpus

-- -----------------------------------------------------------------
-- show_styles - show a set of style runs summary
-- -----------------------------------------------------------------
function show_styles (name, styles)
  local p = mapper.mapprint

  p ""
  p (string.format ("%s styles:", name))
  p (string.format ("%-20s %-20s %-30s %s", "Foreground", "Background", "Styles", "Count"))
  p (string.format ("%-20s %-20s %-30s %s", "----------", "----------", "------", "-----"))
  for k, v in pairs (styles) do
    local fore, back, style = string.match (k, "^(%d+)/(%d+)/(%d+)$")
    local t = { }
    if bit.band (style, 1) ~= 0 then
      table.insert (t, "bold")
    end
    if bit.band (style, 2) ~= 0 then
      table.insert (t, "underline")
    end
    if bit.band (style, 4) ~= 0 then
      table.insert (t, "italic")
    end

    p (string.format ("%-20s %-20s %-30s %5d", RGBColourToName (fore), RGBColourToName (back), table.concat (t, ","), v))
  end -- for

end -- show_styles


-- -----------------------------------------------------------------
-- mapper_analyse - analyse the map database
-- -----------------------------------------------------------------
function mapper_analyse (name, line, wildcards)
  local min_name_length = 1e20
  local max_name_length = 0
  local total_name_length = 0
  local room_count = 0
  local min_name = ""
  local max_name = ""
  local name_styles = { }
  local desc_styles = { }
  local exits_styles = { }

  local function get_styles (this_style, all)
    if this_style then
      for k, v in ipairs (this_style) do
        local s = string.format ("%d/%d/%d", v.fore, v.back, v.style)
        if all [s] then
          all [s] = all [s] + 1
        else
          all [s] = 1
        end -- if
      end -- for
    end -- if styles exits
  end -- get_styles

  for uid, room in pairs (rooms) do
    -- don't bother getting the length of hex uids - that doesn't prove much
    if not string.match (room.name, "^%x+$") then
      local len = #room.name
      room_count = room_count + 1
      min_name_length = math.min (min_name_length, len)
      max_name_length = math.max (max_name_length, len)
      if len == min_name_length then
        min_name = room.name
      end
      if len == max_name_length then
        max_name = room.name
      end
      total_name_length = total_name_length + len
      end -- if not a hex room name

    -- now get the colours
    if room.styles then
      get_styles (room.styles.name, name_styles)
      get_styles (room.styles.desc, desc_styles)
      get_styles (room.styles.exits, exits_styles)
    end -- if we have some styles

  end -- for each room

  local p = mapper.mapprint
  mapper.mapprint (string.rep ("-", 78))

  p (string.format ("%20s %4d (%s)", "Minimum room name length", min_name_length, min_name))
  p (string.format ("%20s %4d (%s)", "Maximum room name length", max_name_length, max_name))
  if room_count > 0 then  -- no divide by zero
    p (string.format ("%20s %4d",      "Average room name length", total_name_length / room_count))
  end -- if

  if not config.SAVE_LINE_INFORMATION then
    mapper.mapprint ("WARNING: Option 'save_line_info' is not set.")
  end -- if

  show_styles ("Room name",   name_styles)
  show_styles ("Description", desc_styles)
  show_styles ("Exits",       exits_styles)

  mapper.mapprint (string.rep ("-", 78))

end -- mapper_analyse

-- -----------------------------------------------------------------
-- mapper_delete - delete a room from the database
-- -----------------------------------------------------------------
function mapper_delete (name, line, wildcards)
  local uid = wildcards [1]
  if #uid < 4 then
    mapper.maperror ("UID length must be at least 4 characters for deleting rooms")
    return
  end -- if too short

  delete_uid, room = find_room_partial_uid (uid)
  if not delete_uid then
    return
  end -- if not found

  mapper_show (delete_uid)
  rooms [delete_uid] = nil  -- delete it
  mapper.mapprint ("Room", delete_uid, "deleted.")

  -- remove any exit references to this room
  for uid, room in pairs (rooms) do
    for dir, dest in pairs (room.exits) do
      if dest == delete_uid then
        mapper.mapprint (string.format ("Setting exit %s from room %s to be unknown",
                          dest, fixuid (uid)))
        room.exits [dir] = '0'
      end -- if that exit pointed to the deleted room
    end -- for each exit
  end -- for each room

  -- redraw map
  if last_drawn_id then
    mapper.draw (last_drawn_id)
  end -- if

end -- mapper_delete

-- -----------------------------------------------------------------
-- uid_hyperlink - displays (with no newline) a hyperlink to a UID
-- -----------------------------------------------------------------
function uid_hyperlink (uid)
  Hyperlink ("!!" .. GetPluginID () .. ":mapper_show(" .. uid .. ")",
            fixuid (uid), "Click to show room details for " .. fixuid (uid), RGBColourToName (config.MAPPER_NOTE_COLOUR.colour), "", false)
end -- uid_hyperlink

-- -----------------------------------------------------------------
-- list_rooms_table - displays a list of rooms from the supplied table of uid/room pairs
-- -----------------------------------------------------------------
function list_rooms_table (t)
  table.sort (t, function (a, b) return a.room.name:upper () < b.room.name:upper () end )

  for _, v in ipairs (t) do
    local room = v.room
    local uid = v.uid
    uid_hyperlink (uid)
    mapper.mapprint (" ", room.name)
  end -- for each room

  if #t == 0 then
    mapper.mapprint "No matches."
  else
    local s = ""
    if #t > 1 then
      s = "es"
    end -- if
    mapper.mapprint (string.format ("%d match%s.", #t, s))
  end -- if

end -- list_rooms_table

-- -----------------------------------------------------------------
-- find_orphans - finds all rooms nothing leads to
-- -----------------------------------------------------------------
function find_orphans ()
  local orphans = { }
  -- add all rooms to orphans table
  for uid, room in pairs (rooms) do
    orphans [uid] = room
  end -- for

  -- now eliminate rooms which others point to
  for uid, room in pairs (rooms) do
    for dir, exit_uid in pairs (room.exits) do
      if exit_uid ~= "0" then
        orphans [exit_uid] = nil  -- not an orphan
      end -- if
    end -- for each exit
  end -- for
  local t = { }
  for uid, room in pairs (orphans) do
    table.insert (t, { uid = uid, room = room })
  end -- for
  list_rooms_table (t)
end -- find_orphans

-- -----------------------------------------------------------------
-- find_connect - finds all rooms that this one eventually leads to
-- -----------------------------------------------------------------
function find_connect (uid, room)
  local found = {  }
  local unexplored = { [uid] = true }

  while next (unexplored) do
    local new_ones= { }
    for uid in pairs (unexplored) do
      if not found [uid] then
        local room = rooms [uid]
        if room then
          found [uid] = true
          unexplored [uid] = nil  -- remove from unexplored list
          for dir, exit_uid in pairs (room.exits) do
            if not found [exit_uid] and not unexplored [exit_uid] then
              table.insert (new_ones, exit_uid)
            end -- if not noticed yet
          end -- for
        else
          unexplored [uid] = nil  -- doesn't exist, remove from list
        end -- if room exists
      end -- if not yet found
    end -- for each unexplored room
    for _, uid in ipairs (new_ones) do
      unexplored [uid] = true
    end -- for
  end -- while still some to go

  local t = { }

  for uid in pairs (found) do
    table.insert (t, { uid = uid, room = rooms [uid] } )
  end -- for each found room

  list_rooms_table (t)
end -- find_connect

-- -----------------------------------------------------------------
-- colour_finder - generic finder for name/description/exits
--                 foreground or background colours
-- -----------------------------------------------------------------
function  colour_finder (wanted_colour, which_styles, fore_or_back)
  local colour, colourRGB = config_validate_colour (wanted_colour)
  if not colour then
    return
  end -- if
  mapper_list_finder (function (uid, room)
    if room [which_styles] then
      for _, style in ipairs (room [which_styles]) do
        if style [fore_or_back] == colourRGB then
          return true
        end -- if wanted colour
      end -- for each style
    end -- if any style
    return false
   end)
end -- colour_finder

-- -----------------------------------------------------------------
-- find_room_partial_uid - find a room by partial ID
-- if multiples found, advises what they are
-- if none, gives an error and returns nil
-- otherwise returns the UID and the room info for that room
-- -----------------------------------------------------------------
function find_room_partial_uid (which)
  local t = { }
  which = which:upper ()
  for uid, room in pairs (rooms) do
    if string.match (uid, "^" .. which) then
      table.insert (t, { uid = uid, room = room })
    end -- if a partial match
  end -- for
  if #t == 0 then
    mapper.maperror ("Room UID", which, "is not known.")
    return nil, nil
  end -- if

  if #t > 1 then
    mapper.maperror ("Multiple matches for UID", which .. ":")
    list_rooms_table (t)
    return nil, nil
  end -- if

  return t [1].uid, t [1].room
end -- find_room_partial_uid

-- -----------------------------------------------------------------
-- mapper_list_finder - generic finder which adds a room if f() returns true
-- -----------------------------------------------------------------
function mapper_list_finder (f)
  local t = { }

  for uid, room in pairs (rooms) do
    if not f or f (uid, room) then
      table.insert (t, { uid = uid, room = room } )
    end -- if room wanted
  end -- for

  list_rooms_table (t)
end -- mapper_list_finder

-- -----------------------------------------------------------------
-- mapper_list - show or search the map database
-- -----------------------------------------------------------------
function mapper_list (name, line, wildcards)
  local first_wildcard = Trim (wildcards [1]):lower ()
  local name     = string.match (first_wildcard, "^name%s+(.+)$")
  local desc     = string.match (first_wildcard, "^desc%s+(.+)$")
  local notes    = string.match (first_wildcard, "^notes?%s+(.+)$")
  local area     = string.match (first_wildcard, "^areas?%s+(.+)$")
  local any_notes= string.match (first_wildcard, "^notes?$")
  local orphans  = string.match (first_wildcard, "^orphans?$")
  local lead_to  = string.match (first_wildcard, "^dest%s+(%x+)$")
  local connect  = string.match (first_wildcard, "^connect%s+(%x+)$")
  local shops    = string.match (first_wildcard, "^shops?$")
  local banks    = string.match (first_wildcard, "^banks?$")
  local trainers = string.match (first_wildcard, "^trainers?$")
  local dups     = string.match (first_wildcard, "^duplicates?$")
  local colour_name_fore  = string.match (first_wildcard, "^colou?r%s+name%s+fore%s+(.*)$")
  local colour_name_back  = string.match (first_wildcard, "^colou?r%s+name%s+back%s+(.*)$")
  local colour_desc_fore  = string.match (first_wildcard, "^colou?r%s+desc%s+fore%s+(.*)$")
  local colour_desc_back  = string.match (first_wildcard, "^colou?r%s+desc%s+back%s+(.*)$")
  local colour_exits_fore = string.match (first_wildcard, "^colou?r%s+exits?%s+fore%s+(.*)$")
  local colour_exits_back = string.match (first_wildcard, "^colou?r%s+exits?%s+back%s+(.*)$")
  local p = mapper.mapprint

  -- no wildcard? list all rooms
  if first_wildcard == "" then
    p ("All rooms")
    mapper_list_finder ()

  -- wildcard consists of hex digits and spaces? must be a uid list
  elseif string.match (first_wildcard, "^[%x ]+$") then
    first_wildcard = first_wildcard:upper ()  -- UIDs are in upper case
    if not string.match (first_wildcard, ' ') then
      local uid, room = find_room_partial_uid (first_wildcard)
      if not uid then
        return
      end -- if not found

      mapper_show (uid)
    else
      -- hex strings? room uids
      mapper_list_finder (function (uid, room)
        for w in string.gmatch (first_wildcard, "%x+") do
          if string.match (uid, "^" .. w) then
            return true
          end -- if
        end -- for each uid they wanted
        return false
      end )  -- function
    end -- if more than one uid

  -- wildcard is: name xxx
  elseif name then
    p (string.format ('Rooms whose name match "%s"', name))
    mapper_list_finder (function (uid, room) return string.find (room.name:lower (), name, 1, true) end)

  -- wildcard is: desc xxx
  elseif desc then
    p (string.format ('Rooms whose description matches "%s"', desc))
    mapper_list_finder (function (uid, room) return string.find (room.desc:lower (), desc, 1, true) end)

  -- wildcard is: notes xxx
  elseif notes then
    p (string.format ('Rooms whose notes match "%s"', notes))
    mapper_list_finder (function (uid, room) return room.notes and string.find (room.notes:lower (), notes, 1, true) end)

  -- wildcard is: area xxx
  elseif area then
    p (string.format ('Rooms whose area matches "%s"', area))
    mapper_list_finder (function (uid, room) return room.area and string.find (room.area:lower (), area, 1, true) end)

  -- wildcard is: notes
  -- (show all rooms with notes)
  elseif any_notes then
    p ("Rooms with notes")
    mapper_list_finder (function (uid, room) return room.notes end)

  -- wildcard is: shops
  elseif shops then
    p ("Rooms with shops")
    mapper_list_finder (function (uid, room) return room.Shop end)

  -- wildcard is: trainers
  elseif trainers then
    p ("Rooms with trainers")
    mapper_list_finder (function (uid, room) return room.Trainer end)

  -- wildcard is: banks
  elseif banks then
    p ("Rooms with banks")
    mapper_list_finder (function (uid, room) return room.Bank end)
  elseif dups then
    p ("Duplicate rooms")
    for duplicate_uid in pairs (duplicates) do
      p (string.rep ("-", 10))
      p ("Marked duplicate: " .. fixuid (duplicate_uid))
      mapper_list_finder (function (uid, room) return room.duplicate == duplicate_uid end)
    end -- for

  -- find orphan rooms (rooms no other room leads to)
  elseif orphans then
    p ("Orphaned rooms")
    find_orphans ()

  -- find rooms which this one eventually connects to
  elseif connect then
    local connect_uid, room = find_room_partial_uid (connect)
    if not connect_uid then
      return
    end -- if not found
    p (string.format ('Rooms which can be reached from "%s" (%s)', connect, room.name))
    t = find_connect (connect_uid, room)

  -- find rooms which have an exit leading to this one
  elseif lead_to then
    local lead_to_uid, room = find_room_partial_uid (lead_to)
    if not lead_to_uid then
      return
    end -- if not found
    p (string.format ("Rooms which have an exit to %s:", lead_to))
    mapper_list_finder (function (uid, room)
      for dir, exit_uid in pairs (room.exits) do
        if exit_uid == lead_to_uid then
          return true
        end -- if exit leads to this room
      end -- for each exit
      return false
      end)  -- finding function

  -- colour finding
  elseif colour_name_fore then
    p (string.format ("Rooms who have a name foreground style of %s:", colour_name_fore))
    colour_finder (colour_name_fore, 'name_styles', 'fore')
  elseif colour_name_back then
    p (string.format ("Rooms who have a name background style of %s:", colour_name_back))
    colour_finder (colour_name_back, 'name_styles', 'back')
  elseif colour_desc_fore then
    p (string.format ("Rooms who have a description foreground style of %s:", colour_desc_fore))
    colour_finder (colour_desc_fore, 'desc_styles', 'fore')
  elseif colour_desc_back then
    p (string.format ("Rooms who have a description background style of %s:", colour_desc_back))
    colour_finder (colour_desc_back, 'desc_styles', 'back')
  elseif colour_exits_fore then
    p (string.format ("Rooms who have a exits foreground style of %s:", colour_exits_fore))
    colour_finder (colour_exits_fore, 'exits_styles', 'fore')
  elseif colour_exits_back then
    p (string.format ("Rooms who have a exits background style of %s:", colour_exits_back))
    colour_finder (colour_exits_back, 'exits_styles', 'back')

  else
    mapper.maperror ("Do not understand 'list' command:", first_wildcard)
    p ("Options are:")
    p ("  mapper list")
    p ("  mapper list uid ...")
    p ("  mapper list name <name>")
    p ("  mapper list desc <description>")
    p ("  mapper list note <note>")
    p ("  mapper list area <area>")
    p ("  mapper list notes")
    p ("  mapper list orphans")
    p ("  mapper list dest <uid>")
    p ("  mapper list connect <uid>")
    p ("  mapper list shop")
    p ("  mapper list trainer")
    p ("  mapper list bank")
    p ("  mapper list colour name  fore <colour>")
    p ("  mapper list colour name  back <colour>")
    p ("  mapper list colour desc  fore <colour>")
    p ("  mapper list colour desc  back <colour>")
    p ("  mapper list colour exits fore <colour>")
    p ("  mapper list colour exits back <colour>")
    return
  end -- if

end -- mapper_list

-- -----------------------------------------------------------------
-- mapper_show - show one room
-- -----------------------------------------------------------------
function mapper_show (uid)
  local room = rooms [uid]
  if not room then
    mapper.maperror ("Room", uid, "is not known.")
    return
  end -- if

  local old_note_colour = GetNoteColourFore ()
  SetNoteColourFore(config.MAPPER_NOTE_COLOUR.colour)

  Note (string.rep ("-", 78))
  Note (string.format ("Room:  %s -> %s.", fixuid (uid), room.name))
  if room.duplicate then
    Note (string.format ("(Duplicate of %s)", fixuid (room.duplicate)))
  end -- if a duplicate
  Note (string.rep ("-", 78))
  Note (room.desc)
  Note (string.rep ("-", 78))
  Tell ("Exits: ")
  for dir,dest in pairs (room.exits) do
    Tell (dir:upper () .. " -> ")
    if dest == "0" then
      Tell "(Not explored)"
    else
      local dest_room = rooms [dest]
      if dest_room then
        uid_hyperlink (dest)
        Tell (" (" .. dest_room.name .. ")")
      else
        Tell (fixuid (dest) .. " (unknown)")
      end -- if dest_room
    end -- if
    Tell " "
  end -- for
  Note "" -- finish line
  if room.notes then
    Note (string.rep ("-", 78))
    Note (room.notes)
  end -- of having notes
  if room.Trainer or room.Shop or room.Bank then
    Note (string.rep ("-", 78))
    local t = { }
    if room.Bank then
      table.insert (t, "Bank")
    end -- if
    if room.Shop then
      table.insert (t, "Shop")
    end -- if
    if room.Trainer then
      table.insert (t, "Trainer")
    end -- if
    Note (table.concat (t, ", "))
  end -- of having notes
  Note (string.rep ("-", 78))

  SetNoteColourFore (old_note_colour)
end -- mapper_show

-- -----------------------------------------------------------------
-- mapper_config - display or change configuration options
-- Format is: mapper config <name> <value>  <-- change option <name> to <value>
--            mapper config                 <-- show all options
--            mapper config <name>          <-- show setting for one option
-- -----------------------------------------------------------------
function mapper_config (name, line, wildcards)
  local name = Trim (wildcards.name:lower ())
  local value = Trim (wildcards.value)

  -- no config item - show all existing ones
  if name == "" then
    mapper.mapprint ("All mapper configuration options")
    mapper.mapprint (string.rep ("-", 60))
    mapper.mapprint ("")
    for k, v in ipairs (config_control) do
      mapper.mapprint (string.format ("mapper config %-40s %s", v.name, v.show (config [v.option])))
    end
    mapper.mapprint ("")
    mapper.mapprint (string.rep ("-", 60))
    mapper.mapprint ('Type "mapper help" for more information about the above options.')

    -- training counts
    local count = 0
    for k, v in pairs (stats) do
      count = count + v.is + v.isnot
    end -- for each line type
    mapper.mapprint (string.format ("%s: %s.", "Number of times line types trained", count))

    -- hints on corpus info
    mapper.mapprint ('Type "mapper corpus info" for more information about line training.')
    mapper.mapprint ('Type "mapper learn" to toggle the training windows.')
    return false
  end -- no item given

  -- config name given - look it up in the list
  local config_item = validate_option (name, 'mapper config')
  if not config_item then
    return false
  end -- if no such option

  -- no value given - display the current setting of this option
  if value == "" then
    mapper.mapprint ("Current value for " .. name .. ":")
    mapper.mapprint ("")
    mapper.mapprint (string.format ("mapper config %s %s", config_item.name, config_item.show (config [config_item.option])))
    mapper.mapprint ("")
    return false
  end -- no value given

  -- validate new option value
  local new_value = config_item.validate (value)
  if new_value == nil then    -- it might be false, so we have to test for nil
    mapper.maperror ("Configuration option not changed.")
    return false
  end -- bad value

  -- set the new value and confirm it was set
  config [config_item.option] = new_value
  mapper.mapprint ("Configuration option changed. New value is:")
  mapper.mapprint (string.format ("mapper config %s %s", config_item.name, config_item.show (config [config_item.option])))
  return true
end -- mapper_config

-- -----------------------------------------------------------------
-- count_rooms - count how many rooms are in the database
-- -----------------------------------------------------------------
function count_rooms ()
  local count = 0
  for k, v in pairs (rooms) do
    count = count + 1
  end -- for
  return count
end -- count_rooms

-- -----------------------------------------------------------------
-- mapper_export - writes the rooms table to a file
-- -----------------------------------------------------------------
function mapper_export (name, line, wildcards)
  local filter = { lua = "Lua files" }

  local filename = utils.filepicker ("Export mapper map database", "Map_database " .. WorldName () .. ".lua", "lua", filter, true)
  if not filename then
    return
  end -- if cancelled
  local f, err = io.open (filename, "w")
  if not f then
    mapper.maperror ("Cannot open " .. filename .. " for output: " .. err)
    return
  end -- if not open

  local status, err = f:write ("rooms = "  .. serialize.save_simple (rooms) .. "\n")
  if not status then
    mapper.maperror ("Cannot write database to " .. filename .. ": " .. err)
  end -- if cannot write
  f:close ()
  mapper.mapprint ("Database exported, " .. count_rooms () .. " rooms.")
end -- mapper_export

-- -----------------------------------------------------------------
-- set_window_width - sets the mapper window width
-- -----------------------------------------------------------------
function set_window_width (name, line, wildcards)
  local size = tonumber (wildcards [1])
  if not size then
    mapper.maperror ("Bad size: " .. size)
    return
  end -- if

  if size < 200 or size > 1000 then
    mapper.maperror ("Size must be in the range 200 to 1000 pixels")
    return
  end -- if

  config.WINDOW.width = size
  mapper.mapprint ("Map window width set to", size, "pixels")
  if last_drawn_id then
    mapper.draw (last_drawn_id)
  end -- if
end -- set_window_width

-- -----------------------------------------------------------------
-- set_window_height - sets the mapper window height
-- -----------------------------------------------------------------
function set_window_height (name, line, wildcards)
  local size = tonumber (wildcards [1])
  if not size then
    mapper.maperror ("Bad size: " .. size)
    return
  end -- if

  if size < 200 or size > 1000 then
    mapper.maperror ("Size must be in the range 200 to 1000 pixels")
    return
  end -- if

  config.WINDOW.height = size
  mapper.mapprint ("Map window height set to", size, "pixels")
  if last_drawn_id then
    mapper.draw (last_drawn_id)
  end -- if
end -- set_window_height

-- -----------------------------------------------------------------
-- mapper_import - imports the rooms table from a file
-- -----------------------------------------------------------------
function mapper_import (name, line, wildcards)

  if count_rooms () > 0 then
    mapper.maperror ("Mapper database is not empty (there are " .. count_rooms () .. " rooms in it)")
    mapper.maperror ("Before importing another database, clear this one out with: mapper reset database")
    return
  end -- if

  local filter = { lua = "Lua files" }

  local filename = utils.filepicker ("Import mapper map database", "Map_database " .. WorldName () .. ".lua", "lua", filter, false)
  if not filename then
    return
  end -- if cancelled
  local f, err = io.open (filename, "r")
  if not f then
    mapper.maperror ("Cannot open " .. filename .. " for input: " .. err)
    return
  end -- if not open

  local s, err = f:read ("*a")
  if not s then
    mapper.maperror ("Cannot read database from " .. filename .. ": " .. err)
  end -- if cannot write
  f:close ()

  -- make a sandbox so they can't put Lua functions into the import file

  local t = {} -- empty environment table
  f = assert (loadstring (s))
  setfenv (f, t)
  -- load it
  f ()

  -- move the rooms table into our rooms table
  rooms = t.rooms
  mapper.mapprint ("Database imported, " .. count_rooms () .. " rooms.")

end -- mapper_import


-- -----------------------------------------------------------------
-- count_values - count how many values are in the database
-- -----------------------------------------------------------------
function count_values (t, done)
  local count = count or 0
  done = done or {}
  for key, value in pairs (t) do
    if type (value) == "table" and not done [value] then
      done [value] = true
      count = count + count_values (value, done)
    elseif key == 'score' then
      count = count + 1
    end
  end
  return count
end -- count_values

-- -----------------------------------------------------------------
-- corpus_export - writes the corpus table to a file
-- -----------------------------------------------------------------
function corpus_export (name, line, wildcards)
  local filter = { lua = "Lua files" }

  local filename = utils.filepicker ("Export map corpus", "Map_corpus " .. WorldName () .. ".lua", "lua", filter, true)
  if not filename then
    return
  end -- if cancelled
  local f, err = io.open (filename, "w")
  if not f then
    corpus.maperror ("Cannot open " .. filename .. " for output: " .. err)
    return
  end -- if not open

  local status, err = f:write ("corpus = "  .. serialize.save_simple (corpus) .. "\n")
  if not status then
    mapper.maperror ("Cannot write corpus to " .. filename .. ": " .. err)
  end -- if cannot write
  f:close ()
  mapper.mapprint ("Corpus exported, " .. count_values (corpus) .. " entries.")
end -- corpus_export


-- -----------------------------------------------------------------
-- corpus_import - imports the corpus table from a file
-- -----------------------------------------------------------------
function corpus_import (name, line, wildcards)

  if count_values (corpus) > 0 then
    mapper.maperror ("Corpus is not empty (there are " .. count_values (corpus) .. " entries in it)")
    mapper.maperror ("Before importing another corpus, clear this one out with: mapper reset corpus")
    return
  end -- if

  local filter = { lua = "Lua files" }

  local filename = utils.filepicker ("Import map corpus", "Map_corpus " .. WorldName () .. ".lua", "lua", filter, false)
  if not filename then
    return
  end -- if cancelled
  local f, err = io.open (filename, "r")
  if not f then
    mapper.maperror ("Cannot open " .. filename .. " for input: " .. err)
    return
  end -- if not open

  local s, err = f:read ("*a")
  if not s then
    mapper.maperror ("Cannot read corpus from " .. filename .. ": " .. err)
  end -- if cannot write
  f:close ()

  -- make a sandbox so they can't put Lua functions into the import file

  local t = {} -- empty environment table
  f = assert (loadstring (s))
  setfenv (f, t)
  -- load it
  f ()

  -- move the corpus table into our corpus table
  corpus = t.corpus
  mapper.mapprint ("Corpus imported, " .. count_values (corpus) .. " entries.")

end -- corpus_import

-- -----------------------------------------------------------------
-- room_toggle_trainer /  room_toggle_shop / room_toggle_bank
-- menu handlers to toggle trainers, shops, banks
-- -----------------------------------------------------------------
function room_toggle_trainer (room, uid)
  room.Trainer = not room.Trainer
  mapper.mapprint ("Trainer here: " .. config_display_boolean (room.Trainer))
end -- room_toggle_trainer

function room_toggle_shop (room, uid)
  room.Shop = not room.Shop
  mapper.mapprint ("Shop here: " .. config_display_boolean (room.Shop))
end -- room_toggle_shop

function room_toggle_bank (room, uid)
  room.Bank = not room.Bank
  mapper.mapprint ("Bank here: " .. config_display_boolean (room.Bank))
end -- room_toggle_bank

-- -----------------------------------------------------------------
-- room_edit_bookmark - menu handler to add, edit or remove a note
-- -----------------------------------------------------------------
function room_edit_bookmark (room, uid)

  local notes = room.notes
  local found = room.notes and room.notes ~= ""


  if found then
    newnotes = utils.inputbox ("Modify room comment (clear it to delete it)", room.name, notes)
  else
    newnotes = utils.inputbox ("Enter room comment (creates a note for this room)", room.name, notes)
  end -- if

  if not newnotes then
    return
  end -- if cancelled

  if newnotes == "" then
    if not found then
      mapper.mapprint ("Nothing, note not saved.")
      return
    else
      mapper.mapprint ("Note for room", uid, "deleted. Was previously:", notes)
      rooms [uid].notes = nil
      return
    end -- if
  end -- if

  if notes == newnotes then
    return -- no change made
  end -- if

  if found then
     mapper.mapprint ("Note for room", uid, "changed to:", newnotes)
   else
     mapper.mapprint ("Note added to room", uid, ":", newnotes)
   end -- if

   rooms [uid].notes = newnotes

end -- room_edit_bookmark

-- -----------------------------------------------------------------
-- room_edit_area - menu handler to edit the room area
-- -----------------------------------------------------------------
function room_edit_area (room, uid)

  local area = room.area


  newarea = utils.inputbox ("Modify room area name", room.name, area)

  if not newarea then
    return
  end -- if cancelled

  if newarea == "" then
    mapper.mapprint ("Area not changed.")
    return
  end -- if

  if area == newarea then
    return -- no change made
  end -- if

   mapper.mapprint ("Area name for room", uid, "changed to:", newarea)

   rooms [uid].area = newarea

end -- room_edit_area


-- -----------------------------------------------------------------
-- room_delete_exit - menu handler to delete an exit
-- -----------------------------------------------------------------
function room_delete_exit (room, uid)

local available =  {
  n = "North",
  s = "South",
  e = "East",
  w = "West",
  u = "Up",
  d = "Down",
  ne = "Northeast",
  sw = "Southwest",
  nw = "Northwest",
  se = "Southeast",
  ['in'] = "In",
  out = "Out",
  }  -- end of available

  -- remove non-existent exits
  for k in pairs (available) do
    if room.exits [k] then
      available [k] = available [k] .. " --> " .. fixuid (room.exits [k])
    else
      available [k] = nil
    end -- if not a room exit
  end -- for

  if next (available) == nil then
    utils.msgbox ("There are no exits from this room.", "No exits!", "ok", "!", 1)
    return
  end -- not known

  local chosen_exit = utils.listbox ("Choose exit to delete", "Exits ...", available )
  if not chosen_exit then
    return
  end

  mapper.mapprint ("Deleted exit", available [chosen_exit], "from room", uid, "from mapper.")

  -- update in-memory table
  rooms [uid].exits [chosen_exit] = nil

  local current_room = get_current_room_ ("room_delete_exit")

  mapper.draw (current_room)
  last_drawn_id = current_room    -- in case they change the window size

end -- room_delete_exit

-- -----------------------------------------------------------------
-- room_show_description - menu handler to show the room description
-- -----------------------------------------------------------------
function room_show_description (room, uid)

  local font_name = GetInfo (20) -- output window font
  local font_size = GetOption "output_font_height"
  local output_width  = GetInfo (240)  -- average width of pixels per character
  local wrap_column   = GetOption ('wrap_column')
  local _, lines = string.gsub (room.desc, "\n", "x") -- count lines

  local font_height = WindowFontInfo (win, font_id, 1)  -- height

  utils.editbox ("", "Description of " .. room.name, string.gsub (room.desc, "\n", "\r\n"), font_name, font_size,
                { read_only = true,
                box_width  = output_width * wrap_column + 100,
                box_height  = font_height * (lines + 1) + 120,
                reply_width = output_width * wrap_column + 10,
                -- cancel_button_width = 1,
                prompt_height = 1,
                 } )

end -- room_show_description

-- -----------------------------------------------------------------
-- room_connect_exit - menu handler to connect an exit to another room
-- -----------------------------------------------------------------
function room_connect_exit  (room, uid, dir)
  -- find what room they want to connect to
  local response = utils.inputbox ("Enter UID of room which is " .. dir:upper () .. " of here", "Connect exit")
  if not response then
    return
  end -- cancelled

  -- get rid of spaces, make upper-case
  response = Trim (response):upper ()

  -- validate
  if not string.match (response, "^%x%x%x+$") then
    mapper.maperror ("Destination room UID must be a hexadecimal string")
    return
  end -- if

  -- check it exists
  dest_uid = find_room_partial_uid (response)

  if not dest_uid then
    return  -- doesn't exist
  end -- if

  if duplicates [dest_uid] then
    mapper.maperror ("Cannot connect to a room marked as a duplicate")
    return
  end -- if

  if uid == dest_uid then
    mapper.maperror ("Cannot connect to a room to itself")
    return
  end -- if

  room.exits [dir] = dest_uid

  INFO (string.format ("Exit %s from %s now connects to %s",
      dir:upper (), fixuid (uid), fixuid (dest_uid)))

  local inverse = inverse_direction [dir]
  if inverse then
    rooms [dest_uid].exits [inverse] = uid
    INFO ("Added inverse direction from " .. fixuid (dest_uid) .. " in the direction " .. inverse .. " to be " .. fixuid (uid))
  end -- of having an inverse


end -- room_connect_exit

function room_copy_uid (room, uid)
  SetClipboard (uid)
  mapper.mapprint (string.format ("UID %s (in full: %s) now on the clipboard", fixuid (uid), uid))
end -- room_copy_uid

-- -----------------------------------------------------------------
-- room_click - RH-click on a room
-- -----------------------------------------------------------------
function room_click (uid, flags)

  -- check we got room at all
  if not uid then
    return nil
  end -- if

  -- look it up
  local room = rooms [uid]

  if not room then
    return
  end -- if still not there

  local notes_desc = "Add note"
  if room.notes then
    notes_desc = "Edit note"
  end -- if

  local handlers = {
      { name = notes_desc, func = room_edit_bookmark} ,
      { name = "Edit area", func = room_edit_area } ,
      { name = "Show description", func = room_show_description} ,
      { name = "-", } ,
      { name = "Trainer", func = room_toggle_trainer, check_item = true} ,
      { name = "Shop",    func = room_toggle_shop,    check_item = true} ,
      { name = "Bank",    func = room_toggle_bank,    check_item = true} ,
      { name = "-", } ,
      { name = "Copy UID", func = room_copy_uid } ,
      { name = "-", } ,
      } -- handlers

  local count = 0
  for dir, dest in pairs (room.exits) do
    if dest == '0' then
      table.insert (handlers, { name = "Connect " .. dir:upper () .. " exit",
        func = function ()
          return room_connect_exit (room, uid, dir)
        end -- factory function
      } )
      count = count + 1
    end -- if not known
  end -- for
  if count > 0 then
    table.insert (handlers, { name = "-" })
  end --if we had any

  table.insert (handlers, { name = "Delete an exit", func = room_delete_exit} )

  local t, tf = {}, {}
  for _, v in pairs (handlers) do
    local name = v.name
    if v.check_item then
      if room [name] then
        name = "+" .. name
      end -- if
    end -- if need to add a checkmark
    table.insert (t, name)
    tf [v.name] = v.func
  end -- for

  local choice = WindowMenu (mapper.win,
                            WindowInfo (mapper.win, 14),
                            WindowInfo (mapper.win, 15),
                            table.concat (t, "|"))

  -- find their choice, if any (empty string if cancelled)
  local f = tf [choice]

  if f then
    f (room, uid)
    current_room = get_current_room_ ("room_click")
    mapper.draw (current_room)
    last_drawn_id = current_room    -- in case they change the window size
  end -- if handler found


end -- room_click

-- -----------------------------------------------------------------
-- Find a with a special attribute which f(room) will return true if it exists
-- -----------------------------------------------------------------

function map_find_special (f)

  local room_ids = {}
  local count = 0

  -- scan all rooms looking for a match
  for uid, room in pairs (rooms) do
     if f (room) then
       room_ids [uid] = true
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
    false       -- don't auto-walk
    )

end -- map_find_special

-- -----------------------------------------------------------------
-- mapper_peek - draw the map as if you were at uid
-- -----------------------------------------------------------------
function mapper_peek (name, line, wildcards)
  local uid = wildcards [1]

  peek_uid, room = find_room_partial_uid (uid)
  if not peek_uid then
    return
  end -- if not found

  mapper.draw (peek_uid)
  last_drawn_id = peek_uid    -- in case they change the window size

end -- mapper_peek

-- -----------------------------------------------------------------
-- map_shops - find nearby shops
-- -----------------------------------------------------------------
function map_shops (name, line, wildcards)
  map_find_special (function (room) return room.Shop end)
end -- map_shops

-- -----------------------------------------------------------------
-- map_trainers - find nearby trainers
-- -----------------------------------------------------------------
function map_trainers (name, line, wildcards)
  map_find_special (function (room) return room.Trainer end)
end -- map_trainers


-- -----------------------------------------------------------------
-- map_banks - find nearby banks
-- -----------------------------------------------------------------
function map_banks (name, line, wildcards)
  map_find_special (function (room) return room.Bank end)
end -- map_banks

-- -----------------------------------------------------------------
-- mark_duplicate_room - mark the current room as a duplicate UID
-- -----------------------------------------------------------------
function mark_duplicate_room (name, line, wildcards)
  if not current_room_hash then
   mapper.maperror ("We don't know where we are, try LOOK")
   return
  end -- if

  if rooms [current_room_hash] then
    rooms [current_room_hash] = nil  -- delete it
    mapper.mapprint ("Room", current_room_hash, "deleted.")
  end -- if

  duplicates [current_room_hash] = true -- this is a duplicated room
  mapper.mapprint (string.format ("Room %s now marked as being a duplicated one", fixuid (current_room_hash)))
  set_current_room (nil)  -- throw away incorrect UID
  set_from_room (nil)
  set_last_direction_moved (nil)

  mapper.draw (UNKNOWN_DUPLICATE_ROOM)  -- draw with unknown room

end -- mark_duplicate_room

-- -----------------------------------------------------------------
-- mapper_integrity - integrity check of exits
-- -----------------------------------------------------------------
function mapper_integrity (name, line, wildcards)
  local p = mapper.mapprint
  local repair = Trim (wildcards [1]) == 'repair'

  p("Mapper integrity check")
  local t = { }  -- table of rooms that have connections
  for uid, room in pairs (rooms) do
    for dir, dest in pairs (room.exits) do
      if rooms [dest] then
        -- check for inverse exits
        local dest_room = rooms [dest]
        local inverse = inverse_direction [dir]
        if inverse then
          if dest_room.exits [inverse] ~= uid then
            p(string.format ("Room %s exit %s leads to %s, however room %s exit %s leads to %s",
                fixuid (uid), dir, fixuid (dest), fixuid (dest), inverse, fixuid (dest_room.exits [inverse])))
            if repair then
              dest_room.exits [inverse] = uid
              p (string.format ("Changed %s exit %s to be %s", fixuid (dest), inverse, fixuid (uid)))
            end -- repair
          end -- if

        end -- if inverse exists

        -- add to table for exits that lead to this room
        if not t [dest] then
         t [dest] = { }
        end -- if destination not in table
        local dest_room = t [dest]
        if not dest_room [dir] then
          dest_room [dir] = { }
        end -- if not one from this direction yet
        table.insert (dest_room [dir], uid)
      end -- of the exit existing
    end -- for each exit

    -- see if duplicate UID not recorded
    if duplicates [uid] and not room.duplicate then
      p ("Room " .. fixuid (uid) .. " in duplicates list but we don't know what it is a duplicate of.")
    end -- if

  end -- for each room

  for dest, exits in pairs (t) do
    for dir, from in pairs (exits) do
      if #from > 1 then
        p(string.format ("Problem with exit %s leading to %s",
                         dir:upper (), fixuid (dest)))
        for _, v in ipairs (from) do
          p(string.format ("Room %s leads there",
                          fixuid (v)))
        end -- for each one
      end -- if more than one leads here
    end -- for each direction
  end -- for each destination room

  p "Done."

end -- mapper_integrity


-- based on mapper.find_paths
-- the intention of this is to find a room which is probably the one we want
-- for example, a room directly north of where we are

function find_probable_room (uid, dir)

  local function make_particle (curr_loc, prev_path)
    local prev_path = prev_path or {}
    return {current_room=curr_loc, path=prev_path}
  end

  local depth = 0
  local explored_rooms, particles = {}, {}

  local relative_location = {
    n  = { x =  0, y = -1 },
    s  = { x =  0, y =  1 },
    e  = { x =  1, y =  0 },
    w  = { x = -1, y =  0 },
    ne = { x =  1, y = -1 },
    se = { x =  1, y =  1 },
    nw = { x = -1, y = -1 },
    sw = { x = -1, y =  1 },
  } -- end of relative_location

  local offsets = relative_location [dir]
  if not offsets then
    return false
  end -- if not a n/s/e/w/ne/sw/se/sw
  local x_offset, y_offset = offsets.x, offsets.y

  -- create particle for the initial room
  table.insert (particles, make_particle (uid))

  while #particles > 0 and depth < config.SCAN.depth do

    -- create a new generation of particles
    local new_generation = {}
    depth = depth + 1

    -- process each active particle
    for i, part in ipairs (particles) do

      if not rooms [part.current_room] then
        rooms [part.current_room] = get_room (part.current_room)
      end -- if not in memory yet

      -- if room doesn't exist, forget it
      if rooms [part.current_room] then

        -- get a list of exits from the current room
        exits = rooms [part.current_room].exits

        -- create one new particle for each exit
        for dir, dest in pairs(exits) do

          -- if we've been in this room before, drop it
          if not explored_rooms[dest] then
            explored_rooms[dest] = true
            rooms [dest] = get_room (dest)  -- make sure this room in table
            if rooms [dest] then
              new_path = copytable.deep (part.path)
              table.insert(new_path, { dir = dir, uid = dest } )

              -- see if this is the wanted room
              local x, y = 0, 0
              for _, v in ipairs (new_path) do
                local this_offset = relative_location [v.dir]
                if not this_offset then  -- can't handle up/down/in/out
                  -- DEBUG ("Can't handle " .. v.dir)
                  break
                end -- if
                x = x + this_offset.x
                y = y + this_offset.y
                --DEBUG (string.format ("UID: %s, looking for %d, %d, got %d, %d",
                --       fixuid (v.uid), x_offset, y_offset, x, y))
                -- see if we got where we want to go
                if x == x_offset and y == y_offset then
                  return v.uid
                end -- if found
              end -- for each direction

              -- make a new particle in the new room
              table.insert(new_generation, make_particle(dest, new_path))
            end -- if room exists
          end -- not explored this room

        end  -- for each exit

      end -- if room exists

    end  -- for each particle

    particles = new_generation
  end   -- while more particles

  return false
end -- find_probable_room



-- -----------------------------------------------------------------
-- validate_linetype and  validate_option
-- helper functions for validating line types and option names
-- -----------------------------------------------------------------

function validate_linetype (which, func_name)
  if not line_types [which] then
    mapper.maperror ("Invalid line type '" .. which .. "' given to '" .. func_name .. "'")
    mapper.mapprint ("  Line types are:")
    for k, v in pairs (line_types) do
      mapper.mapprint ("    " .. k)
    end
    return false
  end -- not valid
  return true
end -- validate_linetype

function validate_option (which, func_name)
  -- config name given - look it up in the list
  local config_item = config_control_names [which]
  if not config_item then
    mapper.maperror ("Invalid config item name '" .. which .. "' given to '" .. func_name .. "'")
    mapper.mapprint ("  Configuration items are:")
    for k, v in ipairs (config_control) do
      mapper.mapprint ("    " .. v.name)
    end
    return false
  end -- config item not found
  return config_item
end -- validate_option

-- =================================================================
-- EXPOSED FUNCTIONS FOR OTHER PLUGINS TO CALL
-- =================================================================

-- -----------------------------------------------------------------
-- set_line_type - the current line is of type: linetype
-- linetype is one of: description, exits, room_name, prompt, ignore
-- optional contents lets you change what the contents are (eg. from "You are standing in a field" to "in a field")
-- -----------------------------------------------------------------
override_line_type = nil
override_line_contents = nil
function set_line_type (linetype, contents)
  if not validate_linetype (linetype, 'set_line_type') then
    return nil
  end -- not valid
  override_line_type = linetype
  override_line_contents = contents
  this_line = GetLinesInBufferCount()         -- which line in the output buffer
  line_number = GetLineInfo (this_line, 10)   -- which line this was overall

  -- if line type not recorded for this line yet, record it
  if not deduced_line_types [line_number] then
    deduced_line_types [line_number] = {
        lt = override_line_type,  -- what type we assigned to it
        con = 100,  -- with what probability
        draw = false,       -- did we draw on this line?
        ov = override_line_type,  -- was it overridden? (yes)
        }
  end -- if

  return true
end -- set_line_type

-- -----------------------------------------------------------------
-- set_line_type_contents - set the contents of <linetype> to be <contents>
-- linetype is one of: description, exits, room_name, prompt, ignore
-- This lets you set something (like the room name) from another line (eg. the prompt)
-- -----------------------------------------------------------------
override_contents = { }
function set_line_type_contents (linetype, contents)
  if not validate_linetype (linetype, 'set_line_type_contents') then
    return nil
  end -- not valid
  override_contents [linetype] = contents
  return true
end -- set_line_type_contents

-- -----------------------------------------------------------------
-- set_not_line_type - the current line is NOT of type: linetype
-- linetype is one of: description, exits, room_name, prompt, ignore
-- -----------------------------------------------------------------
line_is_not_line_type = { }
function set_not_line_type (linetype)
  if not validate_linetype (linetype, 'set_not_line_type') then
    return nil
  end -- not valid
  line_is_not_line_type [linetype] = true
  return true
end -- set_not_line_type

-- -----------------------------------------------------------------
-- set_area_name - set the name of the current area (used at the bottom of the map)
-- -----------------------------------------------------------------
area_name = nil
function set_area_name (name)
  area_name = name
end -- set_area_name

-- -----------------------------------------------------------------
-- set_uid - set the uid for the current room
-- -----------------------------------------------------------------
override_uid = nil
function set_uid (uid)
  override_uid = uid
end -- set_uid

-- -----------------------------------------------------------------
-- do_not_deduce_line_type - do not use the Bayesian deduction on linetype
-- linetype is one of: description, exits, room_name, prompt, ignore

-- Used to make sure that lines which we have not explicitly set (eg. to an exit)
-- are never deduced to be an exit. Useful for making sure that set_line_type is
-- the only way we know a certain line is a certain type (eg. an exit line)
-- -----------------------------------------------------------------
do_not_deduce_linetypes = { }
function do_not_deduce_line_type (linetype)
  if not validate_linetype (linetype, 'do_not_deduce_line_type') then
    return nil
  end -- not valid
  do_not_deduce_linetypes [linetype] = true
  return true
end -- do_not_deduce_line_type

-- -----------------------------------------------------------------
-- deduce_line_type - use the Bayesian deduction on linetype
--   (undoes do_not_deduce_line_type for that type of line)
-- linetype is one of: description, exits, room_name, prompt, ignore
-- -----------------------------------------------------------------
function deduce_line_type (linetype)
  if not validate_linetype (linetype, 'deduce_line_type') then
    return nil
  end -- not valid
  do_not_deduce_linetypes [linetype] = nil
  return true
end -- do_not_deduce_line_type

-- -----------------------------------------------------------------
-- get the previous line type (deduced or not)
-- returns nil if no last deduced type
-- -----------------------------------------------------------------
function get_last_line_type ()
  return last_deduced_type
end -- get_last_line_type

-- -----------------------------------------------------------------
-- get the current overridden line type
-- returns nil if no last overridden type
-- -----------------------------------------------------------------
function get_this_line_type ()
  return override_line_type
end -- get_last_line_type

-- -----------------------------------------------------------------
-- set_config_option - set a configuration option
-- name: which option (eg. when_to_draw)
-- value: new setting (string) (eg. 'description')
-- equivalent in behaviour to: mapper config <name> <value>
-- returns nil if option name not given or invalid
-- returns true on success
-- -----------------------------------------------------------------
function set_config_option (name, value)
  if type (value) == 'boolean' then
    if value then
      value = 'yes'
    else
      value = 'no'
    end -- if
  end -- they supplied a boolean
  return mapper_config (name, 'mapper config whatever', { name = name or '', value = value or '' } )
end -- set_config_option

-- -----------------------------------------------------------------
-- get_config_option - get a configuration option
-- name: which option (eg. when_to_draw)
-- returns (string) (eg. 'description')
-- returns nil if option name not given or invalid
-- -----------------------------------------------------------------
function get_config_option (name)
  if not name or name == '' then
    mapper.mapprint ("No option name given to 'get_config_option'")
    return nil
  end -- if no name
  local config_item = validate_option (name, 'get_config_option')
  if not config_item then
    return nil
  end -- if not valid
  return config_item.show (config [config_item.option])
end -- get_config_option

-- -----------------------------------------------------------------
-- get_corpus - gets the corpus (serialized)
-- -----------------------------------------------------------------
function get_corpus ()
  return "corpus = " .. serialize.save_simple (corpus)
end -- get_corpus_count

-- -----------------------------------------------------------------
-- get_stats - gets the training stats (serialized)
-- -----------------------------------------------------------------
function get_stats ()
  return "stats = " .. serialize.save_simple (stats)
end -- get_stats

-- -----------------------------------------------------------------
-- get_database - gets the mapper database (rooms) (serialized)
-- -----------------------------------------------------------------
function get_database ()
  return "rooms = " .. serialize.save_simple (rooms)
end -- get_database

-- -----------------------------------------------------------------
-- get_config - gets the mapper database (rooms) (serialized)
-- -----------------------------------------------------------------
function get_config ()
  return "config = " .. serialize.save_simple (config)
end -- get_config

-- -----------------------------------------------------------------
-- get_current_room_ - gets the current room's data (serialized)
-- returns uid, room
-- -----------------------------------------------------------------
function get_current_room ()
  local current_room = get_current_room_ ("get_current_room")
  if not current_room or not rooms [current_room] then
    return nil
  end -- if
  return uid, "room = " .. serialize.save_simple (rooms [current_room])
end -- get_current_room

-- -----------------------------------------------------------------
-- set_room_extras - sets extra information for the nominated UID
-- returns true if UID exists, false if not
-- extras must be a serialized table. eg. "{a = 'nick', b = 666 }"
-- -----------------------------------------------------------------
function set_room_extras (uid, extras)
  if not uid  or not rooms [uid] or type (extras) ~= 'string' then
    return false
  end -- if

  -- make a sandbox so they can't put Lua functions into the import data
  local t = {} -- empty environment table
  f = assert (loadstring ('extras =  ' .. extras))
  setfenv (f, t)
  -- load it
  f ()

  -- move the rooms table into our rooms table
  rooms [uid].extras = t.extras
  return true
end -- set_room_extras

