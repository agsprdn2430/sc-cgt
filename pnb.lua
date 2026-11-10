local Cfg = {
  BackgroundID     = 12840,
  VerticalPNB      = false,
  PublicPNB        = false,
  BypassPaywall    = false,
  BypassWayBlock   = false,
  pnbX             = 23,
  pnbY             = 194,
  TelX             = 0,
  TelY             = 0,
  AutoBuyWL        = false,
  ConvertBGL       = false,
  ConvertDLBGL     = false,
  MaxGems          = 200000,
  ConsumeArroz     = false,
  ConsumeClover    = false,
  ConsumeSongpyeon = false,
  TakeConsumable   = false,
  WorldConsume     = "",
  DelayTake        = 1000,
  AutoBuff         = false,
  AutoRemote       = true,
  AutoBuyCheats    = true,
  SuckBgems        = false,
  NoGemsDrop       = false,
  IgnoreOther      = false,
  MirrorPNB        = false,
  WebhookPNB       = true,
  WebhookUrl       = "https://discord.com/api/webhooks/1532060254970445845/A1-9I43FIVQ-_T6-qRG9QVZU8gRaUAkEE38oXkO4-SRNjUnfOFfFBYxBbMdRfOIoUhkb",
  DiscordID        = "460068402631933989",
}

EditToggle("Indexed sprite rendering", true)

local Defaults = {}
for k, v in pairs(Cfg) do Defaults[k] = v end

-- state
local Mag, Now = {}, 1
local ScriptRunning, StartRequested = false, false
local WorldName, Nick = "", "Unknown"
local GetRemote, MagW, Taking = false, false, false
local CheatOn, CheatOff, CheatStopped, PendingCheatOn = false, false, true, false
local Ghost, ghost, BlockSB = false, true, false
local reconnect, ReconnectWebhook, AllMagEmpty = false, false, false
local arroz, clover, cheat = false, false, false
local JoinRequested = false
local LastTime, LastJoin, IsJoining = 0, -8000, false
local JoinDelay = 8000
local StartTime, StartTotalLocks = 0, 0
local EarnedBGLTotal, EarnedDLTotal = 0, 0
local PinkGems, BlackGems, InfinityGems = 0, 0, 0
local PGems, BGems, IGems = 0, 0, 0
local CheckBuff, CheckRemote, CheckGems, CheckIgnore = 0, 0, 0, 0
local ConsumableID = {}
local PASSED_BLOCKS = {}

-- helpers
local function toint(v)
  return math.floor(tonumber(v) or 0)
end

local function truthy(v)
  return v == true or v == 1 or v == "1" or v == "true"
end

local function Say(msg)
  LogToConsole("`b[PNB]`` " .. msg)
end

function TextOverlay(text)
  SendVariantList({[0] = "OnTextOverlay", [1] = text})
end

local function WorldInfo()
  local ok, w = pcall(GetWorld)
  if ok and type(w) == "table" and w.name and w.name ~= "" then return w end
  return nil
end

local function InWorld()
  return WorldInfo() ~= nil
end

local function MyPos()
  local ok, me = pcall(GetLocal)
  if not ok or type(me) ~= "table" or not me.pos then return nil end
  return math.floor(me.pos.x / 32), math.floor(me.pos.y / 32)
end

local function SafeTile(x, y)
  local ok, t = pcall(GetTile, x, y)
  if ok then return t end
  return nil
end

-- state di Bothax = flags di packet Libre
local function Raw(p)
  if p.state ~= nil then
    p.flags = p.state
    p.state = nil
  end
  SendPacketRaw(false, p)
end

local function GetGems()
  local ok, info = pcall(GetPlayerInfo)
  if ok and type(info) == "table" then return info.gems or 0 end
  return 0
end

local function jesc(s)
  return (tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"'))
end

function inv(id)
  local ok, list = pcall(GetInventory)
  if not ok or type(list) ~= "table" then return 0 end
  for _, item in ipairs(list) do
    if item.id == id then return item.amount end
  end
  return 0
end

function obj(id)
  if not id then return 0 end
  local ok, list = pcall(Client.GetObjects)
  if not ok or type(list) ~= "table" then return 0 end
  local total = 0
  for _, o in ipairs(list) do
    if o.id == id then total = total + o.amount end
  end
  return total
end

function RefreshChecks()
  CheckIgnore = Cfg.IgnoreOther and 1 or 0
  CheckBuff   = Cfg.AutoBuff and 1 or 0
  CheckRemote = Cfg.AutoRemote and 1 or 0
  CheckGems   = Cfg.NoGemsDrop and 1 or 0
end

-- magplant scan
function GetMag()
  local tiles = {}
  local w = WorldInfo()
  if not w then return tiles end
  local step = 100
  for cy = 0, w.height - 1, step do
    for cx = 0, w.width - 1, step do
      local cw = math.min(step, w.width - cx)
      local ch = math.min(step, w.height - cy)
      local ok, list = pcall(Client.GetTiles, cx, cy, cw, ch)
      if ok and type(list) == "table" then
        for _, t in ipairs(list) do
          if t.fg == 5638 and t.bg == Cfg.BackgroundID then
            table.insert(tiles, {x = t.x, y = t.y})
          end
        end
      else
        for y = cy, cy + ch - 1 do
          for x = cx, cx + cw - 1 do
            local t = SafeTile(x, y)
            if t and t.fg == 5638 and t.bg == Cfg.BackgroundID then
              table.insert(tiles, {x = x, y = y})
            end
          end
        end
      end
    end
  end
  table.sort(tiles, function(a, b)
    if a.y ~= b.y then return a.y < b.y end
    return a.x < b.x
  end)
  return tiles
end

local function RecalcMag()
  Mag = GetMag()
  Now = 1
  Say("`2" .. #Mag .. " magplant (bg " .. Cfg.BackgroundID .. ")")
  return #Mag
end

-- packets
function FindTPVertical(x, y)
  Raw({state = 32, x = x * 32 - 1, y = y * 32 - 1, px = -1, py = -1})
end

function FindTPLeft(x, y)
  Raw({state = 48, x = x * 32, y = y * 32, px = x, py = y})
end

function Wrench(x, y)
  Raw({type = 3, state = 32, value = 32, px = x, py = y, x = x * 32, y = y * 32})
end

function CheatTurnOff()
  SendPacket(2, "action|dialog_return\ndialog_name|cheats\n" ..
    "check_autofarm|0\ncheck_bfg|0\ncheck_gems|1\n" ..
    "check_lonely|" .. CheckIgnore .. "\n" ..
    "check_ignoreo|" .. CheckIgnore .. "\n" ..
    "check_ignoref|" .. CheckIgnore)
end

function CheatTurnOn()
  SendPacket(2, "action|dialog_return\ndialog_name|cheats\n" ..
    "check_autofarm|1\ncheck_bfg|1\n" ..
    "check_autobuff|" .. CheckBuff .. "\n" ..
    "check_autoremote|" .. CheckRemote .. "\n" ..
    "check_gems|" .. CheckGems .. "\n" ..
    "check_lonely|" .. CheckIgnore .. "\n" ..
    "check_ignoreo|" .. CheckIgnore .. "\n" ..
    "check_ignoref|" .. CheckIgnore)
end

function SendWebhook(url, data)
  if not url or url == "" or type(MakeRequest) ~= "function" then return end
  pcall(MakeRequest, url, "POST", {["Content-Type"] = "application/json"}, data)
end

function CheckTime()
  local now = os.time()
  if now - LastTime >= 300 and InWorld() and GetRemote and Cfg.WebhookPNB then
    SendInfoPNB()
    Sleep(1000)
    LastTime = now
  end
end

function SafeJoin(world)
  local now = Script.GetTime()
  if IsJoining then return end
  if now - LastJoin < JoinDelay then return end
  IsJoining = true
  LastJoin = now
  SendPacket(3, "action|join_request\nname|" .. world .. "|\ninvitedWorld|0")
  Sleep(6000)
  IsJoining = false
end

-- movement
function GoPath(t, s, v, x, y)
  if not InWorld() then return end
  Raw({type = t, state = s, value = v, px = x, py = y, x = x * 32, y = y * 32})
  if t == nil then
    pcall(SetLocalPos, x * 32, y * 32)
  end
end

function PrivatePath(x, y)
  if not InWorld() then return end
  local delay = 100
  local iX, iY = MyPos()
  if not iX then return end
  local function step(dx, dy, n)
    for _ = 1, n do
      iX, iY = iX + dx, iY + dy
      GoPath(3, 1, 0, iX, iY)
      GoPath(nil, nil, nil, iX, iY)
      Sleep(delay)
    end
  end
  local distX, distY = x - iX, y - iY
  if distY > 1 then step(0, 1, distY) elseif distY < -1 then step(0, -1, -distY) end
  if distX > 1 then step(1, 0, distX) elseif distX < -1 then step(-1, 0, -distX) end
  local ok, has = pcall(CheckPath, x, y)
  if ok and not has then Say("`9No Path Found!") end
  FindPath(x, y, 550)
  Sleep(delay)
end

function GetWorldSize()
  local w = WorldInfo()
  if not w then return nil end
  return w.width - 1, w.height - 1
end

local PAYWALL_BLOCK = 16308
local ALLOWED_BLOCKS = {[0] = true, [3898] = true, [15858] = true}
local NOT_ALLOWED_BLOCKS = {[3796] = true}

local function UpdatePaywallBlocks(verbose)
  if Cfg.BypassPaywall then
    ALLOWED_BLOCKS[PAYWALL_BLOCK] = true
    NOT_ALLOWED_BLOCKS[PAYWALL_BLOCK] = nil
  else
    ALLOWED_BLOCKS[PAYWALL_BLOCK] = nil
    NOT_ALLOWED_BLOCKS[PAYWALL_BLOCK] = true
  end
  if Cfg.BypassWayBlock then
    ALLOWED_BLOCKS[3796] = true
    NOT_ALLOWED_BLOCKS[3796] = nil
  else
    ALLOWED_BLOCKS[3796] = nil
    NOT_ALLOWED_BLOCKS[3796] = true
  end
  if verbose then
    Say("Paywall " .. (Cfg.BypassPaywall and "`2allowed" or "`4blocked") ..
        "`` | One way " .. (Cfg.BypassWayBlock and "`2allowed" or "`4blocked"))
  end
end

local function GetTileBlockId(tile)
  if not tile then return 0 end
  if tile.fg and tile.fg ~= 0 then return tile.fg end
  if tile.bg and tile.bg ~= 0 then return tile.bg end
  return 0
end

function IsTileWalkable(x, y)
  if not InWorld() then return nil end
  local maxX, maxY = GetWorldSize()
  if x < 0 or y < 0 or x > maxX or y > maxY then return false end
  local tile = SafeTile(x, y)
  if not tile then return false end
  local blockid = GetTileBlockId(tile)
  if blockid ~= 0 and (ALLOWED_BLOCKS[blockid] or PASSED_BLOCKS[blockid]) then return true end
  if blockid ~= 0 and NOT_ALLOWED_BLOCKS[blockid] then return false end
  if tile.fg == 0 and tile.bg == 0 then return true end
  local ok, res = pcall(CheckPath, x, y)
  if ok and res then return true end
  return false
end

function FindSafePath(startX, startY, targetX, targetY, maxIterations)
  if not InWorld() then return nil end
  maxIterations = maxIterations or 2000
  local openSet, closedSet, cameFrom = {}, {}, {}
  local function heuristic(x1, y1, x2, y2)
    return math.abs(x1 - x2) + math.abs(y1 - y2)
  end
  local h0 = heuristic(startX, startY, targetX, targetY)
  openSet[startX .. "," .. startY] = {x = startX, y = startY, g = 0, h = h0, f = h0}
  local iterations = 0
  while next(openSet) and iterations < maxIterations do
    iterations = iterations + 1
    local currentKey, current = nil, nil
    for key, node in pairs(openSet) do
      if not current or node.f < current.f then
        current = node
        currentKey = key
      end
    end
    if not current then break end
    if current.x == targetX and current.y == targetY then
      local path = {}
      local temp = current
      while temp do
        table.insert(path, 1, {x = temp.x, y = temp.y})
        temp = cameFrom[temp.x .. "," .. temp.y]
      end
      return path
    end
    openSet[currentKey] = nil
    closedSet[currentKey] = true
    local neighbors = {
      {x = current.x, y = current.y - 1},
      {x = current.x, y = current.y + 1},
      {x = current.x - 1, y = current.y},
      {x = current.x + 1, y = current.y},
    }
    for _, n in ipairs(neighbors) do
      local nKey = n.x .. "," .. n.y
      if not closedSet[nKey] and IsTileWalkable(n.x, n.y) then
        local g = current.g + 1
        if not openSet[nKey] or g < openSet[nKey].g then
          local h = heuristic(n.x, n.y, targetX, targetY)
          cameFrom[nKey] = current
          openSet[nKey] = {x = n.x, y = n.y, g = g, h = h, f = g + h}
        end
      end
    end
  end
  return nil
end

local function FindNearestReachable(targetX, targetY, maxRadius, curX, curY)
  if not InWorld() then return nil end
  maxRadius = maxRadius or 5
  local maxX, maxY = GetWorldSize()
  local candidates = {}
  for dx = -maxRadius, maxRadius do
    for dy = -maxRadius, maxRadius do
      local dist = math.abs(dx) + math.abs(dy)
      if dist <= maxRadius then
        local cx, cy = targetX + dx, targetY + dy
        if cx >= 0 and cy >= 0 and cx <= maxX and cy <= maxY and IsTileWalkable(cx, cy) then
          table.insert(candidates, {x = cx, y = cy, d = dist})
        end
      end
    end
  end
  table.sort(candidates, function(a, b) return a.d < b.d end)
  for _, c in ipairs(candidates) do
    local path = FindSafePath(curX, curY, c.x, c.y, 1500)
    if path and #path > 0 then return path, c.x, c.y end
  end
  return nil
end

local function WalkPath(path, record)
  for i, pos in ipairs(path) do
    if i > 1 then
      if not ScriptRunning then return false end
      local walkable = IsTileWalkable(pos.x, pos.y)
      GoPath(3, 1, 0, pos.x, pos.y)
      GoPath(nil, nil, nil, pos.x, pos.y)
      Sleep(100)
      local cx, cy = MyPos()
      if cx ~= pos.x or cy ~= pos.y then return false end
      if record and not walkable then
        local id = GetTileBlockId(SafeTile(pos.x, pos.y))
        if id ~= 0 then PASSED_BLOCKS[id] = true end
      end
    end
  end
  return true
end

function SafeFindPath(x, y)
  if Ghost and not Cfg.PublicPNB then return end
  if not Cfg.PublicPNB then return PrivatePath(x, y) end
  if not InWorld() then return false end
  local iX, iY = MyPos()
  if not iX then return false end
  if iX == x and iY == y then return true end

  local path = FindSafePath(iX, iY, x, y, 1000)
  if path and #path > 0 then
    return WalkPath(path, true)
  end

  Say("`9No Path Found!")
  local cand = FindNearestReachable(x, y, 10, iX, iY)
  if cand and #cand > 0 then
    if not WalkPath(cand, false) then return false end
    local fx, fy = MyPos()
    if fx and math.abs(fx - x) + math.abs(fy - y) <= 10 then
      GoPath(3, 1, 0, x, y)
      GoPath(nil, nil, nil, x, y)
      Sleep(100)
      local ax, ay = MyPos()
      return ax == x and ay == y
    end
  end
  return false
end

-- convert
function AutoConvert()
  local Gems = GetGems()
  local maxg = Cfg.MaxGems
  local tel = "action|dialog_return\ndialog_name|telephone\nnum|53785|\nx|" .. Cfg.TelX ..
              "|\ny|" .. Cfg.TelY .. "|\nbuttonClicked|"
  local makeBGL = "action|dialog_return\ndialog_name|info_box\nbuttonClicked|make_bgl"

  if Cfg.SuckBgems then
    BGems = obj(BlackGems)
    if BGems >= 100000 then
      SendPacket(2, "action|dialog_return\ndialog_name|popup\nbuttonClicked|bgem_suckall\n")
    end
  end
  if Cfg.AutoBuyWL then
    if inv(242) < 100 and inv(1796) < 100 and inv(7188) < 100 and Gems >= maxg then
      SendPacket(2, "action|buy\nitem|buy_worldlockpack")
    elseif inv(242) >= 100 and inv(1796) < 100 and inv(7188) < 100 then
      Raw({type = 10, value = 242})
    elseif inv(1796) >= 100 and inv(7188) < 100 then
      SendPacket(2, tel .. "bglconvert")
    elseif inv(7188) >= 100 then
      SendPacket(2, makeBGL)
    end
  end
  if Cfg.ConvertDLBGL then
    if Gems >= maxg and inv(1796) < 100 and inv(7188) < 100 then
      SendPacket(2, tel .. "dlconvert")
    elseif inv(1796) >= 100 and inv(7188) < 100 then
      SendPacket(2, tel .. "bglconvert")
    elseif inv(7188) >= 100 then
      SendPacket(2, makeBGL)
    end
  end
  if Cfg.ConvertBGL then
    if Gems > maxg and inv(7188) < 100 then
      SendPacket(2, tel .. "bglconvert2")
    elseif inv(7188) >= 100 then
      SendPacket(2, makeBGL)
    end
  end
end

-- consumables
function AutoConsume(id)
  Raw({type = 3, value = id, px = Cfg.pnbX, py = Cfg.pnbY, x = Cfg.pnbX * 32, y = Cfg.pnbY * 32})
  Sleep(500)
end

function TakeConsumes()
  if not Cfg.TakeConsumable then return end
  local a, c, s = Cfg.ConsumeArroz, Cfg.ConsumeClover, Cfg.ConsumeSongpyeon
  if a and c then ConsumableID = {4604, 528}
  elseif a and s then ConsumableID = {4604, 1056}
  elseif a and not s and not c then ConsumableID = {4604}
  elseif c and not a and not s then ConsumableID = {528}
  elseif s and not a and not c then ConsumableID = {1056}
  end

  if not InWorld() then
    Sleep(2000)
    return
  end
  if #ConsumableID == 0 then
    Say("`4No ConsumableID configured.")
    return
  end

  for _, cid in ipairs(ConsumableID) do
    if inv(cid) < 1 then
      Taking = true
      GetRemote, CheatOn, CheatOff, MagW = false, false, false, false
      Script.Off("OnVariant", "pnb_variant")
      repeat
        local w = WorldInfo()
        if not w or w.name:upper() ~= Cfg.WorldConsume:upper() then
          SendPacket(3, "action|join_request\nname|" .. Cfg.WorldConsume .. "|\ninvitedWorld|0")
          Sleep(7000)
        else
          Sleep(800)
        end
        Say("`1Taking Consumable...")
        local ok, objects = pcall(Client.GetObjects)
        for _, o in ipairs(ok and objects or {}) do
          if o.id == cid then
            Sleep(500)
            SendPacket(2, "action|dialog_return\ndialog_name|cheats\ncheck_autofarm|0\ncheck_bfg|0\ncheck_gems|1\ncheck_lonely|0\ncheck_ignoreo|0\ncheck_ignoref|0\n")
            Sleep(5000)
            SendPacket(2, "action|respawn\n")
            Sleep(5000)
            SafeFindPath(math.floor(o.pos.x / 32), math.floor(o.pos.y / 32))
            Sleep(Cfg.DelayTake)
            if ghost then
              SendPacket(2, "action|input\n|text|/ghost")
              ghost = false
            end
            Sleep(Cfg.DelayTake)
            if inv(cid) > 0 then
              Say("`2Successfully Take Item! ID=" .. cid)
            end
            if not ghost then
              SendPacket(2, "action|input\n|text|/ghost")
              ghost = true
            end
            Sleep(Cfg.DelayTake)
            break
          end
        end
      until inv(cid) >= 1 or not ScriptRunning
      if not ScriptRunning then return end
      Say("`2Consumables ready! BFG mode active!")
      SafeJoin(WorldName)
      Sleep(7000)
      Taking = false
      Sleep(1200)
      AddHook("OnVariant", "pnb_variant", onvariant)
    end
  end
end

-- main logic
function AutoPNB()
  if not ScriptRunning then return end
  if #Mag == 0 then return false end
  if Now < 1 or Now > #Mag then Now = 1 end

  if Ghost and not Cfg.PublicPNB then
    Ghost = false
    Sleep(500)
    SendPacket(2, "action|input\n|text|/ghost")
    if Cfg.IgnoreOther then
      SafeJoin(WorldName)
      Sleep(2000)
    end
  end
  if Ghost and not Cfg.PublicPNB then return end

  if BlockSB and InWorld() then
    BlockSB = false
    Sleep(500)
    SendPacket(2, "action|input\n|text|/radio")
  end
  if AllMagEmpty then
    SendWebhook(Cfg.WebhookUrl, '{"content": "<@' .. Cfg.DiscordID .. '> ALL Magplants Are Empty!"}')
    AllMagEmpty = false
  end

  TakeConsumes()

  if reconnect then
    reconnect = false
    if ReconnectWebhook then
      ReconnectWebhook = false
      SendWebhook(Cfg.WebhookUrl, '{"content": "<@' .. Cfg.DiscordID .. '> ' .. jesc(Nick) .. ' Is Reconnecting!"}')
    end
    Sleep(2000)
    if not InWorld() then
      SafeJoin(WorldName)
      Sleep(7000)
    else
      return
    end
  elseif arroz and Cfg.ConsumeArroz and GetRemote and not Cfg.AutoBuff then
    SafeFindPath(Cfg.pnbX, Cfg.pnbY)
    Sleep(2000)
    AutoConsume(4604)
    return true
  elseif clover and Cfg.ConsumeSongpyeon and GetRemote and not Cfg.AutoBuff then
    SafeFindPath(Cfg.pnbX, Cfg.pnbY)
    Sleep(2000)
    AutoConsume(1056)
    return true
  elseif clover and Cfg.ConsumeClover and GetRemote and not Cfg.AutoBuff then
    SafeFindPath(Cfg.pnbX, Cfg.pnbY)
    Sleep(2000)
    AutoConsume(528)
    return true
  elseif cheat and Cfg.AutoBuyCheats then
    SendPacket(2, "action|dialog_return\ndialog_name|buycheat\ndialog_name|cheats\nbuttonClicked|1\n")
    Sleep(5000)
    MagW = false
    GetRemote = false
    CheatOff = true
    Sleep(2000)
    return true
  end

  if CheatOff and not GetRemote then
    Sleep(500)
    CheatOff = false
    CheatTurnOff()
    if Cfg.PublicPNB then
      Sleep(800)
      SendPacket(2, "action|respawn\n")
      Sleep(3000)
    end
    Say("`1Stop PnB! Last Magplant #" .. Now)
    CheatStopped = true
  end

  if GetRemote then
    if not Taking then
      local lx, ly = MyPos()
      if lx then
        if lx ~= Cfg.pnbX or ly ~= Cfg.pnbY then
          CheatTurnOff()
          SafeFindPath(Cfg.pnbX, Cfg.pnbY)
          PendingCheatOn = true
          CheatOn = false
        else
          if PendingCheatOn then
            PendingCheatOn = false
            CheatOn = true
            Say("`1Arrived at PnB position")
            if Cfg.VerticalPNB then
              FindTPVertical(Cfg.pnbX, Cfg.pnbY)
            elseif Cfg.MirrorPNB then
              FindTPLeft(Cfg.pnbX, Cfg.pnbY)
            end
            Sleep(2000)
          end
          if CheatOn then
            CheatOn = false
            CheatTurnOn()
            Say("`1Start PnB! X: `2" .. Cfg.pnbX .. "`1 Y: `2" .. Cfg.pnbY)
          end
          AutoConvert()
        end
      end
      CheckTime()
    end
    return true
  end

  local m = Mag[Now]
  if m and CheatStopped then
    Sleep(500)
    if Cfg.PublicPNB then
      if IsTileWalkable(m.x, m.y - 1) then
        SafeFindPath(m.x, m.y - 1)
        Wrench(m.x, m.y)
      else
        Say("`1Magplant blocked, next")
        Now = (Now == #Mag) and 1 or (Now + 1)
      end
    else
      SafeFindPath(m.x, m.y - 1)
      Wrench(m.x, m.y)
    end
    return true
  elseif m then
    Sleep(500)
  elseif not m then
    Now = (Now == #Mag) and 1 or (Now + 1)
    Say("`1Magplant missing, next")
    local nm = Mag[Now]
    if nm then
      SafeFindPath(nm.x, nm.y - 1)
      return true
    end
  end
  return false
end

-- hook (tidak boleh Sleep di sini)
function onvariant(var)
  local ev, v1, v2 = var[0], var[1], var[2]
  local s1 = type(v1) == "string" and v1 or nil

  if not InWorld() then
    reconnect = true
    if Cfg.WebhookPNB then ReconnectWebhook = true end
  elseif ev == "OnSDBroadcast" then
    SendPacket(2, "action|input\n|text|/radio")
  elseif s1 and s1:find("backpack slots.") then
    Ghost = not s1:find("Ghost in the shell")
    arroz = not s1:find("Breaking Gems")
    clover = not s1:find("Lucky!")
    cheat = not s1:find("Cheater")
    return true
  elseif ev == "OnConsoleMessage" and s1 then
    if s1:find("Radio enabled,") then BlockSB = true end
    if s1:find("Where would you like to go") then
      MagW, GetRemote = false, false
      JoinRequested = true
    end
    if s1:find("World Locked") then
      MagW, GetRemote = false, false
      if not s1:find(WorldName, 1, true) then
        Ghost = true
        JoinRequested = true
      end
    end
    if s1:find("Your luck has worn off.") then clover = true end
    if s1:find("Your stomach's rumbling.") then arroz = true end
    if s1:find("boringness.") then cheat = true end
    if s1:find("You're luckier than before!") then clover = false end
    if s1:find("chance of a gem") then arroz = false end
    if s1:find("cheater!") then cheat = false end
  end

  if not MagW and not Ghost then MagW = true end

  if ev == "OnTalkBubble" then
    if type(v2) == "string" then
      if v2:find("You received a MAGPLANT 5000 Remote") then
        GetRemote = true
        PendingCheatOn = true
        Taking = false
      elseif v2:find("The MAGPLANT 5000 is empty") and not CheatOff then
        GetRemote = false
        CheatOff = true
        MagW = false
        CheatStopped = false
        Taking = true
      end
    end
  elseif ev == "OnDialogRequest" and not GetRemote then
    if #Mag == 0 then return false end
    local cur = Mag[Now]
    if not cur or not s1 then return false end
    local atCur = s1:find(cur.x .. "\n", 1, true) and s1:find(cur.y .. "\n", 1, true)
    if s1:find("ACTIVE") and atCur then
      if s1:find("Seed") then
        Now = (Now == #Mag) and 1 or (Now + 1)
      else
        SendPacket(2, "action|dialog_return\ndialog_name|magplant_edit\nx|" .. cur.x ..
                      "|\ny|" .. cur.y .. "|\nbuttonClicked|getRemote\n")
      end
    elseif (s1:find("DISABLED") or s1:find("The machine is disabled.")) and atCur then
      if Cfg.WebhookPNB and Now == #Mag then AllMagEmpty = true end
      Now = (Now == #Mag) and 1 or (Now + 1)
    end
  end
  return false
end

-- format & webhook info
function Nmek(num)
  local formatted = tostring(math.floor(tonumber(num) or 0))
  local k
  while true do
    formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    if k == 0 then break end
  end
  return formatted
end

function FTime(sec)
  local days = math.floor(sec / 86400)
  local hours = math.floor(sec % 86400 / 3600)
  local minutes = math.floor(sec % 3600 / 60)
  local seconds = math.floor(sec % 60)
  if days > 0 then
    return string.format("%s day %s hour %s minute %s second", days, hours, minutes, seconds)
  elseif hours > 0 then
    return string.format("%s hour %s minute %s second", hours, minutes, seconds)
  elseif minutes > 0 then
    return string.format("%s minute %s second", minutes, seconds)
  end
  return string.format("%s second", seconds)
end

function SendInfoPNB()
  math.randomseed(os.time())
  PGems = obj(PinkGems)
  BGems = obj(BlackGems)
  IGems = obj(InfinityGems)
  local Gems = GetGems()
  local Songpyeon, Clover, Arroz = inv(1056), inv(528), inv(4604)
  local BLK, BGL, DL = inv(11550), inv(7188), inv(1796)

  local earned = (BGL * 100 + DL) - StartTotalLocks
  if earned < 0 then earned = 0 end
  EarnedBGLTotal = math.floor(earned / 100)
  EarnedDLTotal = earned % 100

  local function F(name, value)
    return '{"name":"' .. name .. '","value":"' .. value .. '","inline":false}'
  end
  local fields = {
    F("<a:online_1:1471370661137088613> Account", "<:npc:1471371280786788405> " .. jesc(Nick)),
    F("<a:worlds:1474160169817477173> World", jesc(WorldName)),
    F("<:magplant:1471371093213319273> Magplant", Now .. " of " .. #Mag),
    F("<:antidote:1484086483173245061> Consumables",
      Songpyeon .. " <:songpyeon:1484086773540847719> " .. Clover .. " <:clover:1471370462419488872> " ..
      Arroz .. " <:arroz:1471370410334621771> "),
    F("<a:gems:1474161068623397022> Total Locks",
      BLK .. " <a:blk_1:1471370219644784640> " .. BGL .. " <a:bgls_1:1471368364743065741> " ..
      DL .. " <a:DLS:1471368227002257490> "),
    F("<:gems:1484087135815598100> Current Gems", Nmek(Gems)),
    F("<:Bgems:1471367283376001127> Gems Drop",
      Nmek(BGems) .. " <:bgems:1412036304715120791> " .. Nmek(PGems) .. " <:pgems:1484100621614452766> " .. Nmek(IGems) .. " <:gems:1341127516894789666> IGems"),
    F("<a:cuan:1471372894134079529> Earned",
      Nmek(EarnedBGLTotal) .. " <a:bgls_1:1471368364743065741> " ..
      Nmek(EarnedDLTotal) .. " <a:DLS:1471368227002257490> "),
    F("⏱️ Uptime", FTime(os.time() - StartTime)),
  }
  local payload = '{"embeds":[{"title":"<a:Tealz_verify:1471371847860883479> DRsv PNB | PNB LOG",' ..
    '"fields":[' .. table.concat(fields, ",") .. '],' ..
    '"color":' .. math.random(0, 16777215) .. '}]}'
  SendWebhook(Cfg.WebhookUrl, payload)
end

function dialog(teks)
  local ok, me = pcall(GetLocal)
  local name = ok and me and tostring(me.name or ""):match("%S+") or ""
  local d = "add_label_with_icon|big|`cDR`#sv `9PNB `eCGT `6V3|left|16224|\n" ..
            "add_spacer|small|\n" ..
            "add_textbox|GrowID : " .. name .. "|\n" ..
            "add_textbox|World : `2" .. WorldName .. "|\n" ..
            "add_textbox|Position BFG : `6" .. Cfg.pnbX .. " `0, `6" .. Cfg.pnbY .. "|\n" ..
            "add_textbox|`8" .. teks .. "|\n" ..
            "add_spacer|small|\n" ..
            "add_smalltext|DRsv Scripts|\n" ..
            "add_url_button||`0Discord``|NOFLAGS|https://discord.gg/S5AqffW7dD|Join my server.|0|\n" ..
            "add_quick_exit|\nend_dialog|pnb_info||OK|"
  pcall(Client.ShowDialog, d)
end

function ApplyGUI()
  for _, k in ipairs({"BackgroundID", "pnbX", "pnbY", "TelX", "TelY", "MaxGems", "DelayTake"}) do
    Cfg[k] = toint(Cfg[k])
  end
  Cfg.WorldConsume = tostring(Cfg.WorldConsume or "")
  Cfg.WebhookUrl = tostring(Cfg.WebhookUrl or "")
  Cfg.DiscordID = tostring(Cfg.DiscordID or ""):gsub("%D", "")
  if Cfg.DiscordID == "" then Cfg.DiscordID = "0" end
  RefreshChecks()
  RecalcMag()
  UpdatePaywallBlocks(false)
end

function StartPNB()
  local w = WorldInfo()
  if not w then
    TextOverlay("`4Join a world first")
    return
  end
  WorldName = w.name
  if #Mag == 0 then
    dialog("`7Please Set Magplant Background")
    return
  end
  if Cfg.WebhookPNB and type(MakeRequest) ~= "function" then
    Say("`4MakeRequest unavailable, webhook off")
    Cfg.WebhookPNB = false
    UI.Set("c_WebhookPNB", {value = false})
  end

  dialog("`8Please Wait A Moment...")
  Sleep(200)

  local ok, me = pcall(GetLocal)
  local clean = ok and me and tostring(me.name or ""):gsub("`(%S)", "") or ""
  Nick = clean:match("%S+") or "Unknown"
  PinkGems = GetItemInfo("Pink Gemstone").id
  BlackGems = GetItemInfo("Black Gems").id
  InfinityGems = GetItemInfo("Infinity Gems").id
  StartTime = os.time()
  LastTime = StartTime
  StartTotalLocks = inv(7188) * 100 + inv(1796)
  EarnedBGLTotal, EarnedDLTotal = 0, 0
  RefreshChecks()

  Now = 1
  BlockSB = true
  reconnect, GetRemote = false, false
  CheatOff, CheatOn, CheatStopped = false, false, true
  Ghost, MagW, ghost = false, false, true
  PendingCheatOn, Taking, JoinRequested = false, false, false
  PASSED_BLOCKS = {}
  Script.Off("OnVariant", "pnb_variant")
  Sleep(1000)

  if Cfg.AutoBuyCheats then
    SendPacket(2, "action|dialog_return\ndialog_name|buycheat\ndialog_name|cheats\nbuttonClicked|1\n")
    Sleep(1000)
  end
  if BlockSB then
    BlockSB = false
    Sleep(500)
    SendPacket(2, "action|input\n|text|/radio")
    Sleep(1000)
  end

  AddHook("OnVariant", "pnb_variant", onvariant)
  Sleep(1000)
  CheatTurnOff()
  Say("`1PnB On Progress...")
  Sleep(1000)
  if Cfg.PublicPNB then
    SendPacket(2, "action|respawn\n")
    Sleep(3000)
  end

  while ScriptRunning do
    Sleep(500)
    UpdateStatus()
    if JoinRequested then
      JoinRequested = false
      SafeJoin(WorldName)
      Sleep(5000)
    end
    AutoPNB()
  end

  Script.Off("OnVariant", "pnb_variant")
  Say("`4Stopped")
end

-- UI
local WIN = "pnb"
local Bound, Buttons = {}, {}
local uid = 0
local function nid(p)
  uid = uid + 1
  return p .. uid
end

UI.Window(WIN, {title = "DRsv | PNB Main", width = 380, height = 560})

local function Head(text)
  UI.Separator(nid("sep"), {parent = WIN})
  UI.Text(nid("hd"), {parent = WIN, text = text})
end

local function Check(key, label)
  local id = "c_" .. key
  UI.Checkbox(id, {parent = WIN, text = label, value = Cfg[key] and true or false})
  Bound[id] = {key = key, kind = "bool"}
end

local function Field(key, label, kind)
  local id = "f_" .. key
  UI.Text(nid("lb"), {parent = WIN, text = label})
  UI.Input(id, {parent = WIN, value = tostring(Cfg[key])})
  Bound[id] = {key = key, kind = kind}
end

local function Btn(id, label, fn, same)
  if same then UI.SameLine(nid("sl"), {parent = WIN}) end
  UI.Button(id, {parent = WIN, text = label})
  Buttons[id] = fn
end

local function RefreshUI()
  for id, b in pairs(Bound) do
    if b.kind == "bool" then
      UI.Set(id, {value = Cfg[b.key] and true or false})
    else
      UI.Set(id, {value = tostring(Cfg[b.key])})
    end
  end
end

Btn("b_start", "Start PNB", function()
  if ScriptRunning or StartRequested then
    TextOverlay("`9Script already running")
  else
    StartRequested = true
  end
end)
Btn("b_stop", "Stop PNB", function()
  if ScriptRunning then
    ScriptRunning = false
    GetRemote, CheatOn = false, false
    TextOverlay("`4Stop requested")
  else
    TextOverlay("`9Script not running")
  end
end, true)
Btn("b_defaults", "Defaults", function()
  for k, v in pairs(Defaults) do Cfg[k] = v end
  RefreshChecks()
  RefreshUI()
  TextOverlay("`2Defaults restored")
end, true)

UI.Text("status", {parent = WIN, text = "Stopped"})

Head("Magplant & Background")
Field("BackgroundID", "BackgroundID", "int")

Head("Mode PNB")
Check("VerticalPNB", "VerticalPNB (Mneck)")
Check("PublicPNB", "PublicPNB")
Check("BypassPaywall", "Bypass Paywall")
Check("BypassWayBlock", "Bypass One-Way Block")
Check("MirrorPNB", "MirrorPNB")

Head("Positions (PNB / TEL)")
Field("pnbX", "pnbX", "int")
Field("pnbY", "pnbY", "int")
Field("TelX", "TelX", "int")
Field("TelY", "TelY", "int")
Btn("b_cap_pnb", "Capture PNB pos", function()
  local x, y = MyPos()
  if not x then TextOverlay("`4Can't read position") return end
  Cfg.pnbX, Cfg.pnbY = x, y
  UI.Set("f_pnbX", {value = tostring(x)})
  UI.Set("f_pnbY", {value = tostring(y)})
  TextOverlay("`2PNB pos saved: " .. x .. ", " .. y)
end)
Btn("b_cap_tel", "Capture TEL pos", function()
  local x, y = MyPos()
  if not x then TextOverlay("`4Can't read position") return end
  Cfg.TelX, Cfg.TelY = x, y
  UI.Set("f_TelX", {value = tostring(x)})
  UI.Set("f_TelY", {value = tostring(y)})
  TextOverlay("`2TEL pos saved: " .. x .. ", " .. y)
end, true)

Head("Conversion")
Check("AutoBuyWL", "Auto Buy WL")
Check("ConvertBGL", "Convert BGL")
Check("ConvertDLBGL", "Convert DL to BGL")
Field("MaxGems", "Max Earn Gems (Auto Convert)", "int")

Head("Auto Consumable")
Check("ConsumeArroz", "ConsumeArroz")
Check("ConsumeClover", "ConsumeClover")
Check("ConsumeSongpyeon", "ConsumeSongpyeon")

Head("Auto Take Consumable")
Check("TakeConsumable", "TakeConsumable")
Field("WorldConsume", "World Consume (Dropped)", "str")
Field("DelayTake", "Delay Take (ms)", "int")

Head("Auto Cheat")
Check("AutoBuff", "Auto Buff (Consume)")
Check("AutoRemote", "Auto Magplant Remote")

Head("Other")
Check("AutoBuyCheats", "AutoBuyCheats")
Check("SuckBgems", "SuckBgems")
Check("NoGemsDrop", "NoGemsDrop")
Check("IgnoreOther", "IgnoreOther")

Head("Webhook")
Check("WebhookPNB", "Enable WebhookPNB")
Field("WebhookUrl", "Webhook URL", "str")
Field("DiscordID", "Discord ID (mention)", "str")

local function OnSetting(key)
  if key == "BypassPaywall" or key == "BypassWayBlock" then
    UpdatePaywallBlocks(true)
  end
  RefreshChecks()
end

AddHook("OnUI", "pnb_ui", function(id, event, value)
  local b = Bound[id]
  if b then
    if event == "close" then return end
    local c = UI.Get(id)
    local val = c and c.value
    if val == nil then val = value end
    if b.kind == "bool" then
      Cfg[b.key] = truthy(val)
    elseif b.kind == "int" then
      local n = tonumber(val)
      if n then Cfg[b.key] = math.floor(n) end
    else
      Cfg[b.key] = tostring(val or "")
    end
    OnSetting(b.key)
  elseif event == "click" and Buttons[id] then
    Buttons[id]()
  end
end)

local lastStatus = ""
function UpdateStatus()
  local s = (ScriptRunning and "Running" or "Stopped") ..
            " | Mag " .. Now .. "/" .. #Mag ..
            " | PNB " .. Cfg.pnbX .. "," .. Cfg.pnbY ..
            " | TEL " .. Cfg.TelX .. "," .. Cfg.TelY
  if s ~= lastStatus then
    lastStatus = s
    UI.Set("status", {text = s})
  end
end

RefreshChecks()
UpdatePaywallBlocks(false)

while true do
  if StartRequested then
    StartRequested = false
    if not ScriptRunning then
      ScriptRunning = true
      ApplyGUI()
      StartPNB()
      ScriptRunning = false
    end
  end
  UpdateStatus()
  Sleep(250)
end
