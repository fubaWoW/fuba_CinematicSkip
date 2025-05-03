local addonName, addon = ...

local DefaultDB = {
  options = {
    debug = false,
    skipAlreadySeen = true,
    skipOnlyInInstance = false,
    skipInScenario = false,
  },
  skipThisCinematic = {},
  skipThisMovie = {},
  neverSkipMovie = {},
  lastMovieID = 0,
  version = 2,
}

-- hopefully fixed for Classic and Wrath -- thanks to Road-block!
local MovieFrame_StopMovie = MovieFrame_StopMovie or function(frame)
  if MovieFrame_OnMovieFinished then
    MovieFrame_OnMovieFinished(MovieFrame)
  else
    GameMovieFinished()
    MovieFrameSubtitleString:Hide()
    MovieFrame:StopMovie()
    WorldFrame:Show()
    if ( MovieFrame.uiParentShown ) then
      UIParent:Show()
      SetUIVisibility(true)
    end
  end
end

local function CreateDatabase()
  if (not fubaSkipCinematicDB) or (fubaSkipCinematicDB == nil) then fubaSkipCinematicDB = DefaultDB end
end

local function ReCreateDatabase()
  fubaSkipCinematicDB = DefaultDB
end

local function DebugPrint(debugtext)
  if fubaSkipCinematicDB and fubaSkipCinematicDB.options.debug then
    DEFAULT_CHAT_FRAME:AddMessage("|cFF0080FFfubaDebug\[|r"..debugtext.."|cFF0080FF\]")
  end
end

if not fubaSkipCinematicDB then
  CreateDatabase()
  DebugPrint("Database: Set Default Database because empty")
end

if fubaSkipCinematicDB.version and fubaSkipCinematicDB.version ~= DefaultDB.version then
  -- do something if "Database Version" is an older version and maybe need attention?!
  DebugPrint("\nDatabase: unsupported Database Version detected.\nDatabase will be resetted now.\This will result in some Cinematics will play again \"once\" but will work properly again after!")
	ReCreateDatabase()
end

MovieFrame:HookScript("OnEvent", function(self, event, ...)
  if event == "PLAY_MOVIE" then
    -- event PLAY_MOVIE has triggered
    if IsModifierKeyDown() then return end -- DO NOT SKIP if any ModifierKey is pressed (ALT, CTRL or SHIFT)
    local movieID = ...
    if (not movieID) then return end
    fubaSkipCinematicDB.lastMovieID = movieID -- save last MovieID for further actions maybe?!
    DebugPrint("Event: PLAY_MOVIE with ID: "..movieID);

    local skipScenario = true
    local isInstance, instanceType = IsInInstance()
    if instanceType == "scenario" then skipScenario = fubaSkipCinematicDB.options.skipInScenario end
    if (not fubaSkipCinematicDB.options.skipAlreadySeen) or (fubaSkipCinematicDB.options.skipOnlyInInstance and (not isInstance)) or (not skipScenario) then return end

    if fubaSkipCinematicDB.skipThisMovie[movieID] then
      MovieFrame_StopMovie(self)
    else
      fubaSkipCinematicDB.skipThisMovie[movieID] = true
    end

  elseif event == "STOP_MOVIE" then
  -- event STOP_MOVIE has triggered
  end
end)

CinematicFrame:HookScript("OnEvent", function(self, event, ...)
  if event == "CINEMATIC_START" then
    -- event CINEMATIC_START has triggered
    if IsModifierKeyDown() then return end -- DO NOT SKIP if any ModifierKey is pressed (ALT, CTRL or SHIFT)
    DebugPrint("Event: CINEMATIC_START");

    local MapID = C_Map.GetBestMapForUnit("player")
    if not MapID then return end
    local subZoneText = GetSubZoneText() or ""
		local Name, instanceType, difficultyID, difficultyName, maxPlayers, dynamicDifficulty, isDynamic, instanceID, instanceGroupSize, LfgDungeonID = GetInstanceInfo()

    local skipScenario = true
    local isInstance, instanceType = IsInInstance()
    if instanceType == "scenario" then skipScenario = fubaSkipCinematicDB.options.skipInScenario end
    if (not fubaSkipCinematicDB.options.skipAlreadySeen) or (fubaSkipCinematicDB.options.skipOnlyInInstance and (not isInstance)) or (not skipScenario) then return end

    --if fubaSkipCinematicDB.skipThisCinematic[MapID..subZoneText] then
    if fubaSkipCinematicDB.skipThisCinematic[MapID..instanceID] then
      CinematicFrame_CancelCinematic()
    else
      --fubaSkipCinematicDB.skipThisCinematic[MapID..subZoneText] = true
      fubaSkipCinematicDB.skipThisCinematic[MapID..instanceID] = true
    end

  elseif event == "CINEMATIC_STOP" then
  -- event CINEMATIC_STOP has triggered
  end
end)

-- Slash Commands for "Config" until i maybe or not add an Optionsframe ;)
_G.SLASH_FUBACANCELCINEMATIC1 = '/fcc'
SlashCmdList.FUBACANCELCINEMATIC = function(msg)
  if not msg or type(msg) ~= "string" or msg == "" or msg == "help" then
    print("|cff0080ff\nfuba's Cancel Cinematic Usage:\n|r============================================================\n|cff0080ff/fcc|r or |cff0080ff/fcc help|r - Show this message\n|cff0080ff/fcc all|r - Toggle \"Addon fuctionality\"\n|cff0080ff/fcc instance|r - Toggle \"Instance Only\"\n|cff0080ff/fcc scenario|r - Toggle \"Skip also in Scenario\"\n\n\"Hold Down\" a Modifier Key (SHIFT, ALT or CTRL)\nwill \"temporary\" disable ANY Skip!\n|r============================================================")
    return
  end
  local cmd, arg = strsplit(" ", msg:trim():lower()) -- Try splitting by space

  if cmd == "all" then
    if fubaSkipCinematicDB.options.skipAlreadySeen then
      fubaSkipCinematicDB.options.skipAlreadySeen = false
      print("|cff0080ff[fuba's Cancel Cinematic]|r Overall: |cffFF0000Disabled|r")
    else
      fubaSkipCinematicDB.options.skipAlreadySeen = true
      print("|cff0080ff[fuba's Cancel Cinematic]|r Overall: |cff00FF00Enabled|r")
    end
  elseif cmd == "instance" then
    if fubaSkipCinematicDB.options.skipOnlyInInstance then
      fubaSkipCinematicDB.options.skipOnlyInInstance = false
      print("|cff0080ff[fuba's Cancel Cinematic]|r Skip ONLY in Instance: |cffFF0000Disabled|r")
    else
      fubaSkipCinematicDB.options.skipOnlyInInstance = true
      print("|cff0080ff[fuba's Cancel Cinematic]|r Skip ONLY in Instance: |cff00FF00Enabled|r")
    end
  elseif cmd == "scenario" then
    if fubaSkipCinematicDB.options.skipInScenario then
      fubaSkipCinematicDB.options.skipInScenario = false
      print("|cff0080ff[fuba's Cancel Cinematic]|r Skip also in Scenario: |cffFF0000Disabled|r")
    else
      fubaSkipCinematicDB.options.skipInScenario = true
      print("|cff0080ff[fuba's Cancel Cinematic]|r Skip also in Scenario: |cff00FF00Enabled|r")
    end
  elseif cmd == "debug" then
    if fubaSkipCinematicDB.options.debug then
      fubaSkipCinematicDB.options.debug = false
      print("|cff0080ff[fuba's Cancel Cinematic]|r Debug Messages: |cffFF0000Disabled|r")
    else
      fubaSkipCinematicDB.options.debug = true
      print("|cff0080ff[fuba's Cancel Cinematic]|r Debug Messages: |cff00FF00Enabled|r")
    end
  elseif cmd == "developer" and arg and arg == "rdb" then
    ReCreateDatabase()
    print("|cff0080ff[fuba's Cancel Cinematic]|r Reseted Databse to Default")
  end
end