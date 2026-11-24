-- InnHopper developer tools. Excluded from releases. Inactive until /innhopper debug.
local ADDON, ns = ...

local function Print(text)
  DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[InnHopper dev]|r " .. text)
end

function ns.Dbg(text)
  if QuickTeleportDB and QuickTeleportDB.debug then Print(text) end
end

-- Returns true when the command was handled.
function ns.Command(msg)
  if msg == "debug" then
    QuickTeleportDB.debug = not QuickTeleportDB.debug
    Print("debug messages " .. (QuickTeleportDB.debug and "ON" or "OFF"))
    return true

  elseif msg == "state" then
    local stage, dest = ns.GetState()
    Print("window step: " .. tostring(stage) .. ", town: " .. tostring(dest))
    Print("in party: " .. tostring(IsInGroup()) .. ", resting: " .. tostring(IsResting()))
    Print("last whispered: " .. tostring(ns.QT.lastTarget))
    Print("macro: " .. string.gsub(tostring(ns.useBtn:GetAttribute("macrotext")), "\n", " | "))
    return true

  elseif msg == "frames" then
    -- frames listening for who results
    local fr, n = EnumerateFrames(), 0
    while fr do
      local ok, registered = pcall(fr.IsEventRegistered, fr, "WHO_LIST_UPDATE")
      if ok and not (issecretvalue and issecretvalue(registered)) and registered then
        n = n + 1
        Print(n .. ": " .. (fr:GetName() or tostring(fr)))
      end
      fr = EnumerateFrames(fr)
    end
    Print(n .. " frame(s) listening for WHO_LIST_UPDATE")
    return true
  end
  return false
end
