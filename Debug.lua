-- InnHopper developer tools. Excluded from releases. Inactive until /ih debug.
local ADDON, ns = ...

local function Print(text)
  DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[InnHopper dev]|r " .. text)
end

function ns.Dbg(text)
  if QuickTeleportDB and QuickTeleportDB.debug then Print(text) end
end

local function S(v)
  if issecretvalue and issecretvalue(v) then return "<secret>" end
  return tostring(v)
end

-- Beacon prototype: addon message test.
local PREFIX = "IHBTEST"
local registerPrefix = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
local sendAddon = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
if registerPrefix then registerPrefix(PREFIX) end

local rx = CreateFrame("Frame")
rx:RegisterEvent("CHAT_MSG_ADDON")
rx:SetScript("OnEvent", function(_, _, prefix, text, channel, sender)
  if prefix == PREFIX then
    Print("received: text=" .. S(text) .. " channel=" .. S(channel) .. " sender=" .. S(sender))
  end
end)

-- Lists the player's own buffs (name and spell id).
local function ListBuffs()
  local n = 0
  for i = 1, 40 do
    local name, id
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
      local data = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
      if not data then break end
      name, id = data.name, data.spellId
    elseif UnitBuff then
      local _
      name, _, _, _, _, _, _, _, _, id = UnitBuff("player", i)
      if not name then break end
    else
      break
    end
    n = n + 1
    Print("buff " .. i .. ": " .. S(name) .. " (" .. S(id) .. ")")
  end
  Print(n .. " buff(s)")
end

-- Returns true when the command was handled.
function ns.Command(msg)
  local target = string.match(msg, "^msgtest%s*(.*)$")
  if msg == "rest" then
    Print("IsResting: " .. S(IsResting()))
    Print("zone: " .. S(GetZoneText()) .. " | real zone: " .. S(GetRealZoneText()) .. " | sub-zone: " .. S(GetSubZoneText()))
    ListBuffs()
    return true

  elseif string.match(msg, "^beaconmode") then
    local mode = string.match(msg, "^beaconmode%s+(%a+)$")
    if mode then
      ns.RequestBeaconMode(mode, function(changed)
        Print("beacon mode: " .. ns.GetBeaconMode() .. (changed and "" or " (unchanged)"))
      end)
    else
      Print("beacon mode: " .. ns.GetBeaconMode() .. "  (usage: beaconmode on|off)")
    end
    return true

  elseif string.match(msg, "^beaconautoinvite") then
    local arg = string.match(msg, "^beaconautoinvite%s+(%a+)$")
    if arg == "on" or arg == "off" then ns.SetBeaconAutoInvite(arg == "on") end
    Print("beacon auto-invite: " .. tostring(ns.GetBeaconAutoInvite()))
    return true

  elseif string.match(msg, "^beaconjoin%s+.+") then
    local name = string.match(msg, "^beaconjoin%s+(.+)$")
    Print("beacon join request " .. (ns.BeaconJoin(name) and "sent" or "not sent") .. ": " .. name)
    return true

  elseif string.match(msg, "^beaconfake%s+.+") then
    local name = string.match(msg, "^beaconfake%s+(.+)$")
    ns.QT.beacons[name] = true
    ns.RefreshMain()
    Print("marked as beacon in the list: " .. name)
    return true

  elseif string.match(msg, "^beaconscan%s+.+") then
    local arg = string.match(msg, "^beaconscan%s+(.+)$")
    local names = {}
    local count = string.match(arg, "^fake%s+(%d+)$")
    if count then
      for i = 1, tonumber(count) do names[i] = "Zzbeacontest" .. i end
    else
      for part in string.gmatch(arg, "[^,]+") do
        local trimmed = string.match(part, "^%s*(.-)%s*$")
        if trimmed ~= "" then names[#names + 1] = trimmed end
      end
    end
    local started = ns.BeaconScan(names, function(name, found, auto)
      if found then Print("beacon found: " .. name .. " (auto-invite " .. (auto and "on" or "off") .. ")") end
    end, function(st)
      Print(string.format("scan done: total %d, sent %d, cached %d, found %d, throttle pauses %d, over cap %d, %.1f s",
        st.total, st.sent, st.cached, st.found, st.throttled, st.skipped, st.elapsed))
    end)
    if not started then Print("scan not started (no addon message API)") end
    return true

  elseif string.match(msg, "^beaconquery%s+.+") then
    local name = string.match(msg, "^beaconquery%s+(.+)$")
    local sent = ns.BeaconQuery(name, function(found, auto)
      Print("beacon query " .. name .. ": " .. (found and ("beacon, auto-invite " .. (auto and "on" or "off")) or "no reply"))
    end)
    if not sent then Print("beacon query not sent (query pending or no addon message API)") end
    return true

  elseif msg == "beacon" then
    local ok, reason = ns.BeaconEligible()
    Print("beacon eligible: " .. tostring(ok) .. " (" .. reason .. "), mode: " .. ns.GetBeaconMode() .. ", active: " .. tostring(ns.BeaconActive()) .. ", party open: " .. tostring(ns.BeaconPartyOpen()) .. ", auto-invite: " .. tostring(ns.GetBeaconAutoInvite()))
    return true

  elseif target then
    if target == "" then target = UnitName("player") end
    if not sendAddon then Print("no addon message API available") return true end
    local ok, result = pcall(sendAddon, PREFIX, "ping", "WHISPER", target)
    Print("sent to " .. target .. ": ok=" .. S(ok) .. " result=" .. S(result))
    return true

  elseif msg == "debug" then
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
