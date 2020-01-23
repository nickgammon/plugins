-- black is true (ham) and red is false (spam)

-- in other words, a marker assigned black IS the sort of line, and one assigned red IS NOT the sort of line

-- these are the types of lines we are trying to classify as a certain line IS or IS NOT that type
line_types = {
  description = { },
  exits = { },
  room_name = { },
  prompt = { },
}  -- end of line_types table

require "tprint"

function f_first_style_run_foreground (line)
  return GetStyleInfo(line, 1, 14)
end -- f_first_style_run_foreground

-- things we are looking for, like colour of first style run
markers = {

  {
  desc = "Foreground colour of first style run",
  func = f_first_style_run_foreground,
  marker = "m_first_style_run_foreground",

  },


  } -- end of markers

-- this table has the counters
corpus = {


} -- end of corpus table

STATUS_BACKGROUND_COLOUR = "#333333"


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
        WindowText (win, font_id, line .. ": " .. GetLineInfo (line, 1), 0, top,
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
                700, -- left
                0,  -- top
                400, -- width
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
-- Plugin Install
-- -----------------------------------------------------------------
function OnPluginInstall ()
  -- DEBUGGING -- assert (loadstring (GetVariable ("corpus") or "")) ()

  -- make sure each line type is in the corpus

  for k, v in pairs (line_types) do
    if not corpus [k] then
      corpus [k] = {}
    end -- not there yet

    for k2, v2 in ipairs (markers) do
      if not corpus [k] [v2.marker] then  -- if that marker not there, add it
         corpus [k] [v2.marker] = { }
      end -- marker not there ;yet

    end -- for each marker type
  end -- for each line type

  tprint (corpus)

  OnPluginWorldOutputResized ()

end -- OnPluginInstall

-- -----------------------------------------------------------------
-- Plugin Save State
-- -----------------------------------------------------------------
require "serialize"
function OnPluginSaveState ()
  SetVariable ("corpus", "corpus = " .. serialize.save_simple (corpus))
end -- OnPluginSaveState

-- -----------------------------------------------------------------
-- update_corpus
--  add one to red or black for a certain value, for a certain type of line, for a certain marker type
-- -----------------------------------------------------------------
function update_corpus (which, marker, value, black)
  local which_corpus = corpus [which] [marker]
  -- make new one for this value if necessary
  if not which_corpus [value] then
     which_corpus [value] = { red = 0, black = 0 }
  end -- end of this value not there yet
  if black then
     which_corpus [value].black = which_corpus [value].black + 1
  else
     which_corpus [value].red = which_corpus [value].red + 1
  end -- if
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
      value = v.func (line) -- call handler to get value
      update_corpus (which, v.marker, value, black)

      -- other line types do NOT match this, if it was black
      if black then
        for linetype in pairs (line_types) do
          if linetype ~= which then -- don't do the one which it IS
            update_corpus (linetype, v.marker, value, red)
          end -- if not the learning type
        end -- each line type
      end -- black learning

    end -- for each type of marker
  end -- for each line

  -- INFO (string.format ("Selection is from %d to %d", start_line, end_line))

  local s = ":"
  if not black then
    s = ": NOT"
  end -- if

  -- INFO ("Selected lines " .. s .. " " .. which)

  tprint (corpus)

end -- learn_line_type

