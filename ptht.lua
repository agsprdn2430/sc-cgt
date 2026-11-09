-- DRSV | PTHT Main v2 (LibreGrowtopia)
-- Ubah default di tabel Cfg atau lewat window UI. Tidak ada save/load file (io tidak tersedia).

local Cfg = {
  SeedID        = 16707,
  BackgroundID  = 3734,
  VerticalPlant = true,
  PlantY        = 196,
  StartCount    = 0,
  TotalPTHT     = 100,
  DelayPlant    = 100,
  DelayHarvest  = 200,
  DelayFindPath = 100,
  DelayStepPath = 130,
  UseMRAY       = true,
  MirrorPlant   = false,
  UseUWS        = true,
  DelayUWS      = 10500,
  TakeUWS       = false,
  UseVending    = false,
  VendingX      = 0,
  VendingY      = 0,
  DelayTake     = 1000,
  AutoRespawn   = true,
  PointX        = 1,
  PointY        = 196,
  MissTree      = 1000,
  ConsumeLucky  = true,
  Radio         = true,
  Lonely        = false,
  AutoBuyCheats = true,
  AssumeReady   = true,  -- pohon yang sudah ada saat start dianggap siap panen
  GrowTimeSec   = 0,     -- 0 = ambil growtime dari GetItemInfo(SeedID)
  WebhookPTHT   = false,
  WebhookUrl    = "",
  DiscordID     = "0",
}

local Defaults = {}
for k, v in pairs(Cfg) do Defaults[k] = v end

-- state
local Mag, Now = {}, 1
local ScriptRunning, StartRequested = false, false
local WorldName, Nick = "", "Unknown"
local Plant, Harvest = false, true
local Missed, SprayUWS, PTHT = 0, 0, 0
local RemoteEmpty, PendingLoop, Sukses = true, false, true
local PauseAfterKick, ReconnectWebhook = false, false
local CheckTreeHarvest = false
local CheckLonely = 0
local LastConsume, StartTime, PTHT_startTime = 0, 0, 0
local DelayEntering = 8000
local ghost = true
local last_col = nil
local Tiles = {}
local PlantX, PlantFar, StartY = 0, 10, 0
local FindDelay = 50
local PlantedAt, SprayAt = {}, nil
local GrowMs = 0
local ConsumableID = {12600}

-- helpers
local function toint(v)
  return math.floor(tonumber(v) or 0)
end

local function truthy(v)
  return v == true or v == 1 or v == "1" or v == "true"
end

local function sign(v)
  return (v > 0 and 1) or (v < 0 and -1) or 0
end

local function Say(msg)
  LogToConsole("`b[PTHT]`` " .. msg)
end

function TextOverlay(text)
  SendVariantList({[0] = "OnTextOverlay", [1] = text})
end

local function WorldInfo()
  local ok, w = pcall(GetWorld)
  if ok and type(w) == "table" and w.name and w.name ~= "" then return w end
  return nil
end

function InWorld()
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

-- Kirim packet raw dengan mempertahankan state dan flags
local function Raw(p)
  local copy = {}
  for k, v in pairs(p) do copy[k] = v end
  if copy.flags == nil and copy.state ~= nil then
    copy.flags = copy.state
  end
  SendPacketRaw(false, copy)
end

local function GetGems()
  local ok, info = pcall(GetPlayerInfo)
  if ok and type(info) == "table" then return info.gems or 0 end
  return 0
end

local function jesc(s)
  return (tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"'))
end

local function Date(fmt)
  local ok, s = pcall(os.date, fmt)
  return ok and s or ""
end

function inv(id)
  local ok, list = pcall(GetInventory)
  if not ok or type(list) ~= "table" then return 0 end
  for _, item in ipairs(list) do
    if item.id == id then return item.amount end
  end
  return 0
end

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
  if sec == nil then return "0 second" end
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

function SendWebhook(url, data)
  if not url or url == "" or type(MakeRequest) ~= "function" then return end
  pcall(MakeRequest, url, "POST", {["Content-Type"] = "application/json"}, data)
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
          if t.fg == 5638 and (Cfg.BackgroundID == 0 or t.bg == Cfg.BackgroundID) then
            table.insert(tiles, {x = t.x, y = t.y})
          end
        end
      else
        for y = cy, cy + ch - 1 do
          for x = cx, cx + cw - 1 do
            local t = SafeTile(x, y)
            if t and t.fg == 5638 and (Cfg.BackgroundID == 0 or t.bg == Cfg.BackgroundID) then
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
end

-- daftar tile farm (kolom per PlantFar, baris per 2 tile)
local function BuildTiles()
  local list = {}
  local w = WorldInfo()
  if not w then return list end

  local mirror = Cfg.MirrorPlant
  local far = PlantFar or (Cfg.UseMRAY and 10 or 1)

  local py = Cfg.PlantY
  if py <= 0 then
    local px, myY = MyPos()
    if myY and myY > 0 then
      py = myY
      Cfg.PlantY = py
      pcall(UI.Set, "f_PlantY", {value = tostring(py)})
      Say("`2Auto-detected PlantY: " .. py)
    end
  end
  if py <= 0 then return list end

  local startY = py % 2
  local x0, x1, xs = 0, PlantX, far
  local y0, y1, ys = py, startY, -2
  if mirror then
    x0, x1, xs = PlantX, 0, -far
    y0, y1, ys = startY, py, 2
  end

  for x = x0, x1, xs do
    for y = y0, y1, ys do
      local t1, t2 = SafeTile(x, y), SafeTile(x, y + 1)
      local fg1 = t1 and t1.fg or -1
      local fg2 = t2 and t2.fg or -1
      if (fg1 == Cfg.SeedID) or (fg1 == 0 and fg2 ~= 0) then
        table.insert(list, {x = x, y = y})
      end
    end
  end
  return list
end

local function RecalcDerived()
  local w = WorldInfo()
  local width = w and w.width or 100
  PlantFar = Cfg.UseMRAY and 10 or 1
  PlantX = Cfg.MirrorPlant and (width - 1) or (width - PlantFar)
  StartY = Cfg.PlantY % 2
  Tiles = BuildTiles()
  local sec = Cfg.GrowTimeSec
  if sec <= 0 then
    local ok, info = pcall(GetItemInfo, Cfg.SeedID)
    sec = ok and type(info) == "table" and info.growtime or 0
  end
  GrowMs = sec * 1000
end

-- Libre tidak mengekspos tile.extra.progress, jadi kesiapan panen diperkirakan:
-- (1) sudah di-UWS setelah ditanam, atau (2) sudah lewat growtime sejak ditanam.
local function IsGrown(key)
  local p = PlantedAt[key]
  if not p then return Cfg.AssumeReady end
  if SprayAt and p <= SprayAt then return true end
  return (Script.GetTime() - p) >= GrowMs
end

function GetTree(ready)
  local n = 0
  for _, tile in ipairs(Tiles) do
    local t = SafeTile(tile.x, tile.y)
    local fg = t and t.fg or -1
    if ready then
      if fg == Cfg.SeedID and IsGrown(tile.x .. "," .. tile.y) then n = n + 1 end
    elseif fg == 0 then
      n = n + 1
    end
  end
  return n
end

-- movement
function GoPath(t, s, v, x, y)
  if not InWorld() then return end
  Raw({type = t, state = s, value = v, px = x, py = y, x = x * 32, y = y * 32})
  if t == nil then
    pcall(SetLocalPos, x * 32, y * 32)
    local ok, me = pcall(GetLocal)
    if ok and me and me.netid and me.netid ~= -1 then
      pcall(SendVariantList, {[0] = "OnSetPos", [1] = {x = x * 32, y = y * 32}}, me.netid)
    end
  end
end

local function gOgOPath(x, y)
  GoPath(nil, nil, nil, x, y)
  GoPath(3, 1, 0, x, y)
end

local TP_TRY, TP_MAX, TP_NOPROG, TP_STEP = 5, 1000, 3, 2

local function FallbackFindPath(x, y)
  pcall(FindPath, x, y, 520)
end

local function WaitAt(x, y)
  for _ = 1, TP_TRY do
    if not InWorld() then return false end
    Sleep(Cfg.DelayStepPath)
    local px, py = MyPos()
    if px == x and py == y then return true end
  end
  return false
end

function TelePath(tx, ty)
  if not InWorld() then return end
  local cx, cy = MyPos()
  if not cx then return FallbackFindPath(tx, ty) end
  local short = (math.abs(cx - tx) + math.abs(cy - ty)) <= 10
  if short and not CheckTreeHarvest then return GoPath(nil, nil, nil, tx, ty) end
  if cx == tx and cy == ty then
    FindDelay = 0
    return
  end
  local hop = short and 0 or FindDelay
  local steps, noprog = 0, 0
  while (cx ~= tx or cy ~= ty) and InWorld() and steps < TP_MAX and ScriptRunning do
    steps = steps + 1
    local dx, dy = tx - cx, ty - cy
    local nx, ny = cx, cy
    if math.abs(dx) >= math.abs(dy) then
      nx = cx + sign(dx) * math.min(TP_STEP, math.abs(dx))
    else
      ny = cy + sign(dy) * math.min(TP_STEP, math.abs(dy))
    end
    gOgOPath(nx, ny)
    Sleep(hop)
    if WaitAt(nx, ny) then
      cx, cy = nx, ny
      noprog = 0
    else
      local alt = false
      if nx ~= cx and cy ~= ty then
        local aly = cy + sign(ty - cy) * math.min(TP_STEP, math.abs(ty - cy))
        gOgOPath(cx, aly)
        if WaitAt(cx, aly) then
          cy = aly
          alt = true
        end
      end
      if alt then
        noprog = 0
      else
        noprog = noprog + 1
        Say("`9No progress " .. noprog .. " -> " .. tx .. "," .. ty)
      end
    end
    if noprog >= TP_NOPROG then
      FallbackFindPath(tx, ty)
      return
    end
    Sleep(10)
  end
  if (cx ~= tx or cy ~= ty) and steps >= TP_MAX then
    Say("`9Max steps reached -> " .. tx .. "," .. ty)
    FallbackFindPath(tx, ty)
  end
end

local function MoveAboveAndWait(tx, ty, timeout)
  if (tx == nil or tx <= 0) and (ty == nil or ty <= 0) then return true end
  local targetY = math.max(0, ty - 1)
  pcall(TelePath, tx, targetY)
  local waited = 0
  while waited < timeout and InWorld() and ScriptRunning do
    Sleep(200)
    waited = waited + 200
    local lx, ly = MyPos()
    if lx == tx and (ly == targetY or ly == ty) then return true end
  end
  return false
end

-- consumables
function DoConsume()
  local cx, cy = MyPos()
  if not InWorld() or not cx then return end
  for _, item in ipairs({528, 1056}) do
    Raw({type = 3, value = item, px = cx, py = cy, x = cx * 32, y = cy * 32})
    Sleep(500)
  end
  LastConsume = os.time()
  Say("`1Auto Consume! X: `2" .. cx .. "`1 Y: `2" .. cy)
end

function CheckConsume()
  if os.time() - LastConsume >= 1800 then
    local cx, cy = MyPos()
    if cx then
      pcall(FindPath, cx, cy, 520)
      Sleep(500)
      DoConsume()
    end
  end
end

function AutoTakeConsumables()
  for _, cid in ipairs(ConsumableID) do
    if inv(cid) < 1 then
      local attempts = 0
      repeat
        attempts = attempts + 1
        local took = false
        if Cfg.UseVending then
          local vx, vy = Cfg.VendingX, Cfg.VendingY
          TelePath(vx, vy)
          Raw({type = 3, value = 32, px = vx, py = vy, x = vx * 32, y = vy * 32})
          Sleep(200)
          SendPacket(2, "action|dialog_return\ndialog_name|vend_edit\nx|" .. vx .. "|\ny|" .. vy .. "|\nbuttonClicked|pullstock\n\n")
          Sleep(500)
          SendPacket(2, "action|dialog_return\ndialog_name|vend_buyconfirm|\nx|" .. vx .. "|\ny|" .. vy .. "|\nbuyamount|250|\n")
          if inv(cid) > 0 then
            Say("`2Successfully Take UWS! ID=" .. cid)
            took = true
          end
          Sleep(Cfg.DelayTake)
          break
        else
          local ok, objects = pcall(Client.GetObjects)
          local foundObj = false
          for _, o in ipairs(ok and objects or {}) do
            if o.id == cid then
              foundObj = true
              Sleep(1000)
              SendPacket(2, "action|respawn\n")
              Sleep(DelayEntering)
              TelePath(math.floor(o.pos.x / 32), math.floor(o.pos.y / 32))
              Sleep(Cfg.DelayTake)
              if ghost then
                SendPacket(2, "action|input\n|text|/ghost")
                ghost = false
              end
              Sleep(Cfg.DelayTake)
              if inv(cid) > 0 then
                Say("`2Successfully Take UWS! ID=" .. cid)
                took = true
              end
              if not ghost then
                SendPacket(2, "action|input\n|text|/ghost")
                ghost = true
              end
              Sleep(Cfg.DelayTake)
              break
            end
          end
          if not foundObj then
            Say("`4No UWS drop found in world!")
            break
          end
        end
        if not took then Sleep(1000) end
        if attempts >= 3 then
          Say("`4Gagal mengambil consumable setelah 3 percobaan.")
          break
        end
      until inv(cid) >= 1 or not ScriptRunning
    end
  end
end

-- remote
function TakeRemote()
  if #Mag == 0 then
    Say("`4No magplant found!")
    return
  end
  if Now > #Mag then
    Now = 1
    Say("`1All mag used, reset to mag 1")
  end
  local m = Mag[Now]
  if not m then return end
  Say("`1Taking Remote... [" .. Now .. "/" .. #Mag .. "]")
  TelePath(m.x, m.y)
  Sleep(200)
  Raw({type = 3, value = 32, px = m.x, py = m.y, x = m.x * 32, y = m.y * 32})
  Sleep(500)
  SendPacket(2, "action|dialog_return\ndialog_name|magplant_edit\nx|" .. m.x .. "|\ny|" .. m.y .. "|\nbuttonClicked|getRemote")
  Sleep(3000)
end

-- scan / loop
function Scanning()
  if #Tiles == 0 then
    Say("`4Scanning aborted: 0 farm tiles. Check PlantY and SeedID.")
    return
  end

  if Plant then
    local land = GetTree(false)
    Say("`1Plant check: `2" .. land .. "`1 empty tiles left (threshold: " .. math.floor(Cfg.MissTree / 10) .. ")")
    if land <= Cfg.MissTree / 10 then
      SprayUWS = SprayUWS + 1
      Missed = 0
      if Cfg.UseUWS then
        Say("`2Planting selesai! Menggunakan UWS ke-" .. SprayUWS .. "...")
        SendPacket(2, "action|dialog_return\ndialog_name|ultraworldspray")
        SprayAt = Script.GetTime()
        if Cfg.AutoRespawn then
          Sleep(500)
          Say("`2AutoRespawn setelah UWS...")
          SendPacket(2, "action|respawn\n")
          Sleep(2500)
          if Cfg.PointX > 0 or Cfg.PointY > 0 then
            MoveAboveAndWait(Cfg.PointX, Cfg.PointY, 5000)
          end
        end
        Sleep(Cfg.DelayUWS)
        Plant = false
        Harvest = true
      else
        Say("`2Planting selesai! Menunggu pohon (" .. (Cfg.DelayUWS / 1000) .. "s)...")
        if Cfg.AutoRespawn then
          Sleep(500)
          Say("`2AutoRespawn...")
          SendPacket(2, "action|respawn\n")
          Sleep(2500)
          if Cfg.PointX > 0 or Cfg.PointY > 0 then
            MoveAboveAndWait(Cfg.PointX, Cfg.PointY, 5000)
          end
        end
        Sleep(Cfg.DelayUWS)
        Plant = false
        Harvest = true
      end
    else
      Plant = true
      Harvest = false
    end
    Sleep(Cfg.MirrorPlant and 2000 or 500)
  elseif Harvest then
    local ready = GetTree(true)
    Say("`1Harvest check: `2" .. ready .. "`1 ready trees left")
    if ready == 0 then
      Say("`2Harvest selesai! Beralih ke Planting...")
      PTHT = PTHT + 1
      SendPacket(2, "action|input\n|text|`b[`cEL`#Group`b] `1" .. PTHT .. " `0PTHT Is Done")
      if Cfg.WebhookPTHT then SendInfoPTHT() end
      if PTHT >= Cfg.TotalPTHT then
        Say("`2Target TotalPTHT (" .. Cfg.TotalPTHT .. ") tercapai!")
        ScriptRunning = false
        return
      end
      Harvest = false
      Plant = true
      CheckTreeHarvest = false
      SprayAt = nil
      PlantedAt = {}
      if Cfg.AutoRespawn then
        Sleep(500)
        Say("`2AutoRespawn setelah harvest...")
        SendPacket(2, "action|respawn\n")
        Sleep(2500)
        if Cfg.PointX > 0 or Cfg.PointY > 0 then
          MoveAboveAndWait(Cfg.PointX, Cfg.PointY, 5000)
        end
      end
    else
      Harvest = true
      Plant = false
      CheckTreeHarvest = true
    end
    Sleep(Cfg.MirrorPlant and 2000 or 500)
  end
end

function Loop()
  if Cfg.TakeUWS then AutoTakeConsumables() end
  if Cfg.ConsumeLucky and not Plant then CheckConsume() end

  if Cfg.VerticalPlant then
    if #Tiles == 0 then
      RecalcDerived()
      if #Tiles == 0 then
        Say("`4No farm tiles found! Check PlantY & SeedID.")
        ScriptRunning = false
        return
      end
    end
    local cols, xkeys = {}, {}
    for _, t in ipairs(Tiles) do
      if not cols[t.x] then
        cols[t.x] = {}
        table.insert(xkeys, t.x)
      end
      table.insert(cols[t.x], t)
    end
    table.sort(xkeys, function(a, b)
      if Cfg.MirrorPlant then return a > b end
      return a < b
    end)

    local sent = {}
    for idx, x in ipairs(xkeys) do
      if not InWorld() or RemoteEmpty or not ScriptRunning then return end
      local col = cols[x]
      table.sort(col, function(a, b) return a.y < b.y end)
      local down = (idx % 2 == 0)
      local ordered = {}
      if down then
        for i = 1, #col do ordered[#ordered + 1] = col[i] end
      else
        for i = #col, 1, -1 do ordered[#ordered + 1] = col[i] end
      end

      if last_col ~= x then
        local sy = down and ordered[1].y or ordered[#ordered].y
        Say("`1" .. (Plant and "Planting" or "Harvesting") .. " X:`2 " .. x .. "`1 Y:`2 " .. sy ..
            " `6(" .. (down and "top to bottom" or "bottom to top") .. ")")
        last_col = x
      end

      if Plant then
        if GetTree(false) <= Cfg.MissTree / 10 then
          Say("`1MissTree reached! Scanning...")
          Scanning()
          Sleep(1000)
          return
        end
      end

      for _, tile in ipairs(ordered) do
        if not InWorld() or RemoteEmpty or not ScriptRunning then return end
        if PauseAfterKick then
          PauseAfterKick = false
          return
        end
        local key = tile.x .. "," .. tile.y
        if not sent[key] then
          local ti = SafeTile(tile.x, tile.y)
          local fg = ti and ti.fg or -1
          local grown = fg == Cfg.SeedID and IsGrown(key)
          if (Plant and fg == 0) or (Harvest and grown) then
            TelePath(tile.x, tile.y)
            Sleep(Plant and Cfg.DelayPlant or Cfg.DelayHarvest)
            ti = SafeTile(tile.x, tile.y)
            fg = ti and ti.fg or -1
            grown = fg == Cfg.SeedID and IsGrown(key)
            if Plant and fg ~= 0 then
              sent[key] = true
            elseif Harvest and not grown then
              sent[key] = true
            else
              if Cfg.MirrorPlant then
                Raw({state = 48, x = tile.x * 32, y = tile.y * 32})
              end
              Raw({
                type = 3,
                value = Plant and 5640 or 18,
                state = Cfg.MirrorPlant and 48 or (Harvest and 18 or 32),
                x = tile.x * 32,
                y = tile.y * 32,
                px = tile.x,
                py = tile.y,
              })
              if Plant then
                PlantedAt[key] = Script.GetTime()
              elseif Harvest then
                PlantedAt[key] = nil
              end
              sent[key] = true
              Sleep(20)
            end
          else
            sent[key] = true
          end
        end
        if Missed >= 200 then
          Now = Now < #Mag and Now + 1 or 1
          Missed = 0
          RemoteEmpty = true
          return
        end
      end
    end
  end

  if not InWorld() then return end
  Scanning()
end

-- hook (tidak boleh Sleep di sini)
function onvariant(var)
  local ev, v1, v2 = var[0], var[1], var[2]
  if ev == "OnConsoleMessage" and type(v1) == "string" then
    if v1:find("boringness.") then
      if Cfg.AutoBuyCheats then
        SendPacket(2, "action|dialog_return\ndialog_name|buycheat\ndialog_name|cheats\nbuttonClicked|1\n")
      end
    elseif v1:find("Cheater") then
      SendPacket(2, "action|dialog_return\ndialog_name|cheats\ncheck_gems|1\ncheck_lonely|" .. CheckLonely .. "\n")
    elseif v1:find("for cheating of type:") then
      if v1:find(Nick, 1, true) then PauseAfterKick = true end
    end
  elseif ev == "OnTalkBubble" and type(v2) == "string" then
    if v2:find("The MAGPLANT 5000 is empty") then
      Missed = Missed + 6
    end
  elseif not InWorld() and Cfg.WebhookPTHT then
    ReconnectWebhook = true
  end
end

-- webhook info
function SendInfoPTHT()
  math.randomseed(os.time())
  local Gems = GetGems()
  local Songpyeon, Clover, UWS = inv(1056), inv(528), inv(12600)
  local duration = os.time() - PTHT_startTime
  PTHT_startTime = os.time()

  local function F(name, value)
    return '{"name":"' .. name .. '","value":"' .. value .. '","inline":false}'
  end
  local fields = {
    F("<a:online_1:1471370661137088613> Account", "<:npc:1471371280786788405> " .. jesc(Nick)),
    F("<a:worlds:1474160169817477173> World", jesc(WorldName)),
    F("<:magplant:1471371093213319273> Magplant", Now .. " / " .. #Mag),
    F("<:remote:1484086232064589846> PTHT Count", SprayUWS .. " / " .. Cfg.TotalPTHT),
    F("<:antidote:1484086483173245061> Consumables",
      Songpyeon .. " <:songpyeon:1484086773540847719> " .. Clover .. " <:clover:1471370462419488872>"),
    F("<:gems:1484087135815598100> Current Gems", Nmek(Gems)),
    F("<:uws:1471371059818270743> UWS", UWS .. " !"),
    F(":stopwatch: Avg. Time PTHT", FTime(duration)),
  }
  local payload = '{"embeds":[{"title":"<a:Tealz_verify:1471371847860883479> DRSV PTHT | PTHT LOG",' ..
    '"fields":[' .. table.concat(fields, ",") .. '],' ..
    '"footer":{"text":"Uptime : ' .. FTime(os.time() - StartTime) .. ' | ' .. Date("%d/%m/%Y %H:%M:%S") .. '"},' ..
    '"color":' .. math.random(0, 16777215) .. '}]}'
  SendWebhook(Cfg.WebhookUrl, payload)
end

function dialog(teks)
  local ok, me = pcall(GetLocal)
  local name = ok and me and tostring(me.name or ""):match("%S+") or ""
  local d = "add_label_with_icon|big|`2PTHT VIP V2|left|16224|\n" ..
            "add_spacer|small|\n" ..
            "add_textbox|GrowID : " .. name .. "|\n" ..
            "add_textbox|World : `2" .. WorldName .. "|\n" ..
            "add_textbox|Position PTHT : `60 `0, `6" .. Cfg.PlantY .. "|\n" ..
            "add_textbox|`8" .. teks .. "|\n" ..
            "add_spacer|small|\n" ..
            "add_smalltext|DRSV Scripts|\n" ..
            "add_url_button||Discord|NOFLAGS|https://discord.gg/MNgWJX2d9E|`9DR Server|0|0|\n" ..
            "add_quick_exit|\nend_dialog|ptht_info||OK|"
  pcall(Client.ShowDialog, d)
end

-- join / main cycle
function Entering()
  if not InWorld() and Cfg.WebhookPTHT and ReconnectWebhook then
    SendWebhook(Cfg.WebhookUrl, '{"content": "<@' .. Cfg.DiscordID .. '> ' .. jesc(Nick) .. ' Is Reconnecting!"}')
    ReconnectWebhook = false
  end
  if not InWorld() then
    Sukses = false
    Sleep(2000)
    SendPacket(3, "action|join_request\nname|" .. WorldName .. "|\ninvitedWorld|0")
    Sleep(DelayEntering)
    if InWorld() then
      Sleep(2000)
      if Cfg.Radio then
        SendPacket(2, "action|input\n|text|/radio")
        Sleep(DelayEntering)
      end
      RemoteEmpty = true
      Sukses = true
    end
  elseif Sukses then
    if RemoteEmpty then
      TakeRemote()
      RemoteEmpty = false
      PendingLoop = true
    end
    if Cfg.AutoRespawn and PendingLoop then
      if Cfg.PointX > 0 or Cfg.PointY > 0 then
        if MoveAboveAndWait(Cfg.PointX, Cfg.PointY, 5000) then
          Say("`1Arrived at CheckPoint, loop PTHT on")
          PendingLoop = false
          Sleep(1000)
        elseif InWorld() then
          Say("`1Finding CheckPoint XY.. (failed to arrive)")
          Sleep(2000)
        end
      else
        PendingLoop = false
      end
    end
    Loop()
  end
end

function ApplyGUI()
  for _, k in ipairs({"SeedID", "BackgroundID", "PlantY", "StartCount", "TotalPTHT", "DelayPlant",
                      "DelayHarvest", "DelayFindPath", "DelayStepPath", "DelayUWS", "VendingX",
                      "VendingY", "DelayTake", "PointX", "PointY", "MissTree", "GrowTimeSec"}) do
    Cfg[k] = toint(Cfg[k])
  end
  Cfg.WebhookUrl = tostring(Cfg.WebhookUrl or "")
  Cfg.DiscordID = tostring(Cfg.DiscordID or ""):gsub("%D", "")
  if Cfg.DiscordID == "" then Cfg.DiscordID = "0" end
  CheckLonely = Cfg.Lonely and 1 or 0
  RecalcMag()
  RecalcDerived()
end

function StartPTHT()
  local w = WorldInfo()
  if not w then
    TextOverlay("`4Join a world first")
    return
  end
  WorldName = w.name
  if Cfg.WebhookPTHT and type(MakeRequest) ~= "function" then
    Say("`4MakeRequest unavailable, webhook off")
    Cfg.WebhookPTHT = false
    UI.Set("c_WebhookPTHT", {value = false})
  end

  dialog("`8Please Wait A Moment...")
  Sleep(200)

  local ok, me = pcall(GetLocal)
  local clean = ok and me and tostring(me.name or ""):gsub("`(%S)", "") or ""
  Nick = clean:match("%S+") or "Unknown"
  LastConsume = os.time()
  StartTime = os.time()
  PTHT_startTime = StartTime
  Sukses = true
  DelayEntering = 8000
  SprayUWS, PTHT = Cfg.StartCount, Cfg.StartCount
  RemoteEmpty, PendingLoop = true, false
  Harvest, Plant = true, false
  Missed, Now = 0, 1
  FindDelay = Cfg.DelayFindPath
  PlantedAt, SprayAt = {}, nil
  PauseAfterKick, CheckTreeHarvest = false, false
  last_col = nil

  RecalcMag()
  RecalcDerived()
  Say("`2Tiles farm terdeteksi: " .. #Tiles .. " tile.")
  if #Tiles == 0 then
    Say("`40 farm tiles ditemukan!")
    Say("`4Pastikan PlantY dan SeedID sudah diatur dengan benar.")
    TextOverlay("`40 farm tiles! Set PlantY & SeedID")
    ScriptRunning = false
    return
  end

  if Cfg.ConsumeLucky then
    local cx, cy = MyPos()
    if cx then pcall(FindPath, cx, cy, 520) end
    Sleep(500)
    DoConsume()
  end
  if Cfg.AutoBuyCheats then
    SendPacket(2, "action|dialog_return\ndialog_name|buycheat\ndialog_name|cheats\nbuttonClicked|1\n")
    Sleep(2000)
  end
  AddHook("OnVariant", "ptht_variant", onvariant)
  Sleep(2000)
  SendPacket(2, "action|dialog_return\ndialog_name|cheats\ncheck_gems|1\ncheck_lonely|" .. CheckLonely .. "\n")
  Sleep(2000)
  if Cfg.Radio then
    SendPacket(2, "action|input\n|text|/radio")
  end
  Sleep(DelayEntering)
  Scanning()
  Say("`1Scanning...")
  Sleep(200)

  repeat
    Entering()
    UpdateStatus()
    Sleep(50)
  until not ScriptRunning or PTHT == Cfg.TotalPTHT

  if ScriptRunning and PTHT == Cfg.TotalPTHT then
    Say("`1ALL PTHT TOTAL " .. PTHT .. "X IS DONE!")
    Sleep(820)
    if Cfg.WebhookPTHT then
      SendWebhook(Cfg.WebhookUrl, '{"content": "<@' .. Cfg.DiscordID .. '> ALL PTHT TOTAL ' .. PTHT .. 'X Is DONE!"}')
    end
  end
  Script.Off("OnVariant", "ptht_variant")
end

-- UI
local WIN = "ptht"
local Bound, Buttons = {}, {}
local uid = 0
local function nid(p)
  uid = uid + 1
  return p .. uid
end

UI.Window(WIN, {title = "DRSV | PTHT Main v2", width = 380, height = 560})

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

local function Capture(kx, ky, label)
  local x, y = MyPos()
  if not x then
    TextOverlay("`4Can't read position")
    return
  end
  if kx then
    Cfg[kx] = x
    UI.Set("f_" .. kx, {value = tostring(x)})
  end
  if ky then
    Cfg[ky] = y
    UI.Set("f_" .. ky, {value = tostring(y)})
  end
  TextOverlay("`2" .. label .. " saved: " .. (kx and (x .. ", ") or "") .. y)
end

Btn("b_start", "Start PTHT", function()
  if ScriptRunning or StartRequested then
    TextOverlay("`9Script already running")
  else
    StartRequested = true
  end
end)
Btn("b_stop", "Stop PTHT", function()
  if ScriptRunning then
    ScriptRunning = false
    SendPacket(3, "action|join_request\nname|EXIT|\ninvitedWorld|0")
    Say("`4Stop requested")
  else
    TextOverlay("`9Script not running")
  end
end, true)
Btn("b_defaults", "Defaults", function()
  for k, v in pairs(Defaults) do Cfg[k] = v end
  RefreshUI()
  TextOverlay("`2Defaults restored")
end, true)

UI.Text("status", {parent = WIN, text = "Stopped"})

Head("Seed & Background")
Field("SeedID", "SeedID", "int")
Field("BackgroundID", "BackgroundID", "int")
Check("VerticalPlant", "VerticalPlant")

Head("Positions")
Field("PlantY", "PlantY", "int")
Btn("b_cap_y", "Save PlantY from current", function()
  local px, py = MyPos()
  if not py then
    TextOverlay("`4Can't read position")
    return
  end
  local tCurrent = SafeTile(px, py)
  local targetY = py
  if tCurrent and tCurrent.fg ~= 0 and tCurrent.fg ~= Cfg.SeedID then
    targetY = py - 1
  end
  Cfg.PlantY = targetY
  UI.Set("f_PlantY", {value = tostring(targetY)})
  RecalcDerived()
  TextOverlay("`2PlantY: " .. targetY .. " (" .. #Tiles .. " tiles)")
  Say("`2PlantY saved: " .. targetY .. " (Found " .. #Tiles .. " farm tiles)")
end)
Btn("b_detect_all", "Auto Detect Seed & PlantY", function()
  local px, py = MyPos()
  if not px then
    TextOverlay("`4Can't read position")
    return
  end
  local foundSeed = nil
  local foundY = nil
  for dy = -2, 2 do
    local t = SafeTile(px, py + dy)
    if t and t.fg > 0 and t.fg ~= 5638 and t.fg ~= 26 and t.fg ~= 3832 then
      foundSeed = t.fg
      foundY = py + dy
      break
    end
  end
  if foundSeed then
    Cfg.SeedID = foundSeed
    Cfg.PlantY = foundY or py
    UI.Set("f_SeedID", {value = tostring(Cfg.SeedID)})
    UI.Set("f_PlantY", {value = tostring(Cfg.PlantY)})
    RecalcDerived()
    TextOverlay("`2Seed: " .. foundSeed .. " | PlantY: " .. Cfg.PlantY .. " (" .. #Tiles .. " tiles)")
    Say("`2Detected SeedID=" .. foundSeed .. " PlantY=" .. Cfg.PlantY .. " (" .. #Tiles .. " farm tiles)")
  else
    TextOverlay("`4No seed found near player")
  end
end, true)

Head("PTHT Count & Timing")
Field("StartCount", "StartCount", "int")
Field("TotalPTHT", "TotalPTHT", "int")
Field("DelayPlant", "DelayPlant (ms)", "int")
Field("DelayHarvest", "DelayHarvest (ms)", "int")

Head("FindPath Timing")
Field("DelayFindPath", "DelayFindPath (ms)", "int")
Field("DelayStepPath", "DelayStepPath (ms)", "int")

Head("UWS Setting")
Check("UseUWS", "UseUWS")
Field("DelayUWS", "DelayUWS (ms)", "int")

Head("Harvest Readiness")
Check("AssumeReady", "Assume existing trees are ready")
Field("GrowTimeSec", "Grow time override (sec, 0 = auto)", "int")

Head("Auto Take UWS")
Check("TakeUWS", "TakeUWS")
Check("UseVending", "Use Vending")
Field("VendingX", "VendingX", "int")
Field("VendingY", "VendingY", "int")
Field("DelayTake", "DelayTake (ms)", "int")
Btn("b_cap_vend", "Save Vending position", function() Capture("VendingX", "VendingY", "Vending") end)

Head("Auto Respawn (CheckPoint XY)")
Check("AutoRespawn", "AutoRespawn (respawn after use uws)")
Field("PointX", "PointX", "int")
Field("PointY", "PointY", "int")
Btn("b_cap_point", "Save CheckPoint position", function() Capture("PointX", "PointY", "CheckPoint") end)

Head("Miss Tree (recommended 1000)")
Field("MissTree", "MissTree", "int")

Head("Other")
Check("ConsumeLucky", "ConsumeLucky (Clover / Songpyeon)")
Check("UseMRAY", "UseMRAY")
Check("MirrorPlant", "MirrorPlant (2acc)")
Check("Radio", "Radio")
Check("Lonely", "Lonely")
Check("AutoBuyCheats", "AutoBuyCheats")

Head("Webhook")
Check("WebhookPTHT", "Enable WebhookPTHT")
Field("WebhookUrl", "Webhook URL", "str")
Field("DiscordID", "Discord ID (mention)", "str")

AddHook("OnUI", "ptht_ui", function(id, event, value)
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
      if n then Cfg[b.key] = math.max(0, math.floor(n)) end
    else
      Cfg[b.key] = tostring(val or "")
    end
    if b.key == "Lonely" then CheckLonely = Cfg.Lonely and 1 or 0 end
  elseif event == "click" and Buttons[id] then
    Buttons[id]()
  end
end)

local lastStatus = ""
function UpdateStatus()
  local s = (ScriptRunning and "Running" or "Stopped") ..
            " | PTHT " .. PTHT .. "/" .. Cfg.TotalPTHT ..
            " | Mag " .. Now .. "/" .. #Mag ..
            " | PlantY " .. Cfg.PlantY
  if s ~= lastStatus then
    lastStatus = s
    UI.Set("status", {text = s})
  end
end

while true do
  if StartRequested then
    StartRequested = false
    if not ScriptRunning then
      ScriptRunning = true
      ApplyGUI()
      StartPTHT()
      ScriptRunning = false
    end
  end
  UpdateStatus()
  Sleep(250)
end
