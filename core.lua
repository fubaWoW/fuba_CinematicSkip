local addonName, addon = ...

-- ===== Chat & Debug =====
local ADDON_TAG = "|cff0080ff[fuba's Cancel Cinematic]|r "
local function AddonPrint(msg)
  DEFAULT_CHAT_FRAME:AddMessage(ADDON_TAG .. (msg or ""))
end

local function DebugPrint(msg)
  if fubaSkipCinematicDB and fubaSkipCinematicDB.options and fubaSkipCinematicDB.options.debug then
    DEFAULT_CHAT_FRAME:AddMessage("|cFF0080FFfubaDebug[|r" .. tostring(msg) .. "|cFF0080FF]|r")
  end
end

-- ===== Defaults (immutable) =====
local DefaultDB = {
  options = {
    debug = false,
    skipAlreadySeen = true,
    skipOnlyInInstance = false,
    skipInScenario = false,
    respectUncancellable = false,  -- NEW: honor canBeCancelled=false by default
  },
  skipThisCinematic = {},
  skipThisMovie = {},
  neverSkipMovie = {}, -- Reserved for future use
  lastMovieID = 0,
  version = 3, -- bump because of new option
}

-- ===== Deep copy / defaults =====
local function CopyTableDeep(src)
  if type(src) ~= "table" then return src end
  local t = {}
  for k, v in pairs(src) do
    t[k] = CopyTableDeep(v)
  end
  return t
end

local function ApplyDefaults(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then
        dst[k] = CopyTableDeep(v)
      else
        ApplyDefaults(dst[k], v)
      end
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

-- ===== DB init / migration =====
local function CreateOrLoadDB()
  if type(fubaSkipCinematicDB) ~= "table" then
    fubaSkipCinematicDB = {}
  end
  ApplyDefaults(fubaSkipCinematicDB, DefaultDB)
  if fubaSkipCinematicDB.version ~= DefaultDB.version then
    fubaSkipCinematicDB = CopyTableDeep(DefaultDB)
    AddonPrint("Database version mismatch detected. Database has been reset to defaults.")
  end
end

-- === Key helpers ===
-- === Key helpers ===
local function SanitizeKeyComponent(s)
  s = tostring(s or ""):lower()
  s = s:gsub("%s+", " ")
  s = s:gsub("^%s*(.-)%s*$", "%1")
  s = s:gsub("[^%w%-%_ ]+", "")
  s = s:gsub("%s", "_")
  if s == "" then s = "none" end
  return s
end

-- Always build a 4-part key: mapID:instanceID:zone:subzone (sanitized)
local function CinematicKey(mapID, instanceID)
  local mapPart  = tonumber(mapID) or -1
  local instPart = tonumber(instanceID) or 0

  local zoneName    = (GetZoneText and GetZoneText()) or ""
  local subZoneName = (GetSubZoneText and GetSubZoneText()) or ""

  local zonePart    = SanitizeKeyComponent(zoneName)
  local subZonePart = SanitizeKeyComponent(subZoneName)

  return string.format("%d:%d:%s:%s", mapPart, instPart, zonePart, subZonePart)
end


local function ShouldSkip()
  if IsModifierKeyDown() then
    DebugPrint("Modifier key held -> do not skip")
    return false
  end
  local opts = fubaSkipCinematicDB.options
  if not opts.skipAlreadySeen then
    DebugPrint("Global skip disabled")
    return false
  end
  local inInstance, instType = IsInInstance()
  if opts.skipOnlyInInstance and not inInstance then
    DebugPrint("Skip only in instance -> currently not in instance")
    return false
  end
  if instType == "scenario" and not opts.skipInScenario then
    DebugPrint("Scenario detected but skipInScenario is false")
    return false
  end
  return true
end


-- ===== Safe wrappers (Blizzard-conform) =====
-- Mirrors MovieFrame_StopMovie flow including subtitles + cinematic finished.
local function StopGameMovieSafe()
  local mf = MovieFrame
  if not mf then return end

  -- Stop actual playback (audio/video)
  if type(mf.StopMovie) == "function" then
    pcall(mf.StopMovie, mf)
  end

  -- Ensure frame hidden (MovieFrame_OnHide defensively calls StopMovie too)
  if mf:IsShown() then
    pcall(mf.Hide, mf)
  end

  -- Finish cinematic lifecycle for game movie
  if type(CinematicFinished) == "function" and Enum and Enum.CinematicType then
    pcall(CinematicFinished, Enum.CinematicType.GameMovie)
  end

  -- Stop subtitles, as Blizzard does in MovieFrame_StopMovie
  if EventRegistry and EventRegistry.TriggerEvent then
    pcall(EventRegistry.TriggerEvent, EventRegistry, "Subtitles.OnMovieCinematicStop")
  end

  DebugPrint("StopGameMovieSafe() executed")
end

-- Blizzard-style cancel for in-game cinematics (with fallbacks).
local function CancelCinematicSafe()
  if type(CinematicFrame_CancelCinematic) == "function" then
    pcall(CinematicFrame_CancelCinematic)
    DebugPrint("CinematicFrame_CancelCinematic() used")
    return
  end
  local used = false
  if type(StopCinematic) == "function" then
    used = pcall(StopCinematic)
  end
  if not used and type(CanCancelScene) == "function" and CanCancelScene() and type(CancelScene) == "function" then
    used = pcall(CancelScene)
  end
  if not used and type(CanExitVehicle) == "function" and CanExitVehicle() and type(VehicleExit) == "function" then
    used = pcall(VehicleExit)
  end
  DebugPrint("Cancel fallback used")
end

-- ===== Events =====
local evt = CreateFrame("Frame")
evt:RegisterEvent("PLAY_MOVIE")
evt:RegisterEvent("STOP_MOVIE")
evt:RegisterEvent("CINEMATIC_START")
evt:RegisterEvent("CINEMATIC_STOP")
evt:RegisterEvent("PLAYER_LOGIN")

evt:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    CreateOrLoadDB()

  elseif event == "PLAY_MOVIE" then
    local movieID = ...
    if not movieID then return end
    fubaSkipCinematicDB.lastMovieID = movieID
    DebugPrint("PLAY_MOVIE id=" .. tostring(movieID))

    if not ShouldSkip() then return end
    if fubaSkipCinematicDB.neverSkipMovie[movieID] then
      DebugPrint("Movie [" .. tostring(movieID) .. "] in neverSkipMovie, -> do not skip")
      return
    end
    if fubaSkipCinematicDB.skipThisMovie[movieID] then
      StopGameMovieSafe()
      DebugPrint("Movie [" .. tostring(movieID) .. "] skipped")
    else
      fubaSkipCinematicDB.skipThisMovie[movieID] = true
      DebugPrint("Marked movie [" .. tostring(movieID) .. "] as seen")
    end

  elseif event == "STOP_MOVIE" then
    DebugPrint("STOP_MOVIE")

  elseif event == "CINEMATIC_START" then
    -- Payload: canBeCancelled (bool), forcedAspectRatio (enum)
    local canBeCancelled = ...
    DebugPrint("CINEMATIC_START canBeCancelled=" .. tostring(canBeCancelled))

    if not ShouldSkip() then return end

    -- NEW: optionally respect the flag; if respected and cannot be cancelled, do nothing.
    local respect = (fubaSkipCinematicDB.options and fubaSkipCinematicDB.options.respectUncancellable) ~= false
    if (canBeCancelled == false) and respect then
      DebugPrint("Cinematic flagged non-cancellable and setting respects that -> do not skip")
      return
    end

    local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then
      DebugPrint("No mapID -> bail")
      return
    end
	
    local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
	local key = CinematicKey(mapID, instanceID)
	DebugPrint(("Key: %s"):format(key))
	DebugPrint(("MapID: %s"):format(tostring(mapID)))
	DebugPrint(("Instance: %s"):format(tostring(instanceID)))
	DebugPrint(("Zone: %s"):format(tostring(GetZoneText())))
	DebugPrint(("SubZone: %s"):format(tostring(GetSubZoneText())))

	if fubaSkipCinematicDB.skipThisCinematic[key] then
		-- Tiny deferral helps if cancel is called before frame fully shown
		if C_Timer and C_Timer.After then
			C_Timer.After(0.01, CancelCinematicSafe)
		else
			CancelCinematicSafe()
		end
		DebugPrint("Cinematic skipped")
	else
		fubaSkipCinematicDB.skipThisCinematic[key] = true
		DebugPrint("Marked cinematic as seen")
	end

  elseif event == "CINEMATIC_STOP" then
    DebugPrint("CINEMATIC_STOP")
  end
end)

-- ===== Slash command =====
_G.SLASH_FUBACANCELCINEMATIC1 = "/fcc"
SlashCmdList.FUBACANCELCINEMATIC = function(msg)
  msg = (type(msg) == "string" and msg or ""):lower():trim()
  local cmd, arg = strsplit(" ", msg)

  local function ToggleOpt(flag, label)
    local cur = fubaSkipCinematicDB.options[flag]
    fubaSkipCinematicDB.options[flag] = not cur
    AddonPrint(label .. (fubaSkipCinematicDB.options[flag] and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r"))
  end

  if msg == "" or cmd == "help" then
    print('|cff0080ff\nfuba\'s Cancel Cinematic Usage:\n|r============================================================\n' ..
      '|cff0080ff/fcc|r or |cff0080ff/fcc help|r - Show this message\n' ..
      '|cff0080ff/fcc all|r - Toggle "Addon functionality"\n' ..
      '|cff0080ff/fcc instance|r - Toggle "Instance Only"\n' ..
      '|cff0080ff/fcc scenario|r - Toggle "Skip also in Scenario"\n' ..
      '|cff0080ff/fcc respect|r - Toggle "Respect non-cancellable (canBeCancelled=false)"\n' ..
      '|cff0080ff/fcc debug|r - Toggle "Debug Messages"\n\n' ..
      'Press & Hold any Modifier Key (SHIFT, ALT or CTRL)\n'..
	  'will "temporarily" disable ANY Skip!\n' ..
      '|r============================================================')
    return

  elseif cmd == "all" then
    ToggleOpt("skipAlreadySeen", "Overall: ")
  elseif cmd == "instance" then
    ToggleOpt("skipOnlyInInstance", "Skip ONLY inside an Instance: ")
  elseif cmd == "scenario" then
    ToggleOpt("skipInScenario", "Skip also in Scenario: ")
  elseif cmd == "respect" then
    ToggleOpt("respectUncancellable", "Respect non-cancellable flag: ")
  elseif cmd == "debug" then
    ToggleOpt("debug", "Debug Messages: ")
  elseif cmd == "dev" and arg == "reset" then
    fubaSkipCinematicDB = CopyTableDeep(DefaultDB)
    AddonPrint("Reset database to defaults.")
  else
    AddonPrint("Unknown command. Type |cff0080ff/fcc help|r.")
  end
end