-- Pong: player (left) vs CPU (right). First to 5 wins.
-- Controls: W/S or up/down keys, trackball/swipe up/down, or drag on touch.
-- Start/restart: Enter, space, or tap.

local app = {}
local C = wada.ui.colors

local cv, W, H
local pw, ph, pad, br
local py, cy
local bx, by, vx, vy
local ps, cs = 0, 0
local state = "ready"
local last = 0
local resume_at = 0
local wins = 0
local swiped = false
local WIN = 5

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function serve(dir)
  bx, by = W / 2, H / 2
  local ang = (wada.sys.random(1, 100) - 50) / 100 * 0.6
  local sp = W * 0.55
  vx = dir * sp * math.cos(ang)
  vy = sp * math.sin(ang)
  resume_at = wada.sys.millis() + 700
end

local function start()
  ps, cs = 0, 0
  py = (H - ph) / 2
  cy = py
  serve(wada.sys.random(1, 2) == 1 and 1 or -1)
  state = "play"
  last = wada.sys.millis()
end

local function finish(player_won)
  state = "over"
  if player_won then
    wins = wins + 1
    wada.store.set("wins", tostring(wins))
  end
  wada.sys.beep()
end

local function bounce(side)
  -- side: 1 = left paddle (ball goes right), -1 = right paddle (ball goes left)
  local top = side == 1 and py or cy
  local off = clamp((by - (top + ph / 2)) / (ph / 2), -1, 1)
  local sp = math.sqrt(vx * vx + vy * vy) * 1.07
  sp = math.min(sp, W * 1.1)
  local ang = off * 0.9
  vx = side * sp * math.cos(ang)
  vy = sp * math.sin(ang)
  wada.sys.beep()
end

local function update(dt)
  -- CPU paddle: slower than the ball so it can be beaten
  local target = H / 2 - ph / 2
  if vx > 0 then target = by - ph / 2 end
  local maxmove = H * 0.5 * dt
  cy = clamp(cy + clamp(target - cy, -maxmove, maxmove), 0, H - ph)

  if wada.sys.millis() < resume_at then return end

  bx = bx + vx * dt
  by = by + vy * dt

  if by < br then by = br; vy = -vy end
  if by > H - br then by = H - br; vy = -vy end

  local lx = pad + pw
  local rx = W - pad - pw
  if vx < 0 and bx - br <= lx and bx + br >= pad and by >= py - br and by <= py + ph + br then
    bx = lx + br
    bounce(1)
  elseif vx > 0 and bx + br >= rx and bx - br <= W - pad and by >= cy - br and by <= cy + ph + br then
    bx = rx - br
    bounce(-1)
  end

  if bx < 0 then
    cs = cs + 1
    if cs >= WIN then finish(false) else serve(1) end
  elseif bx > W then
    ps = ps + 1
    if ps >= WIN then finish(true) else serve(-1) end
  end
end

local function center(s, y, size, col)
  cv:text(math.floor((W - wada.ui.text_w(s, size)) / 2), math.floor(y), s, col, size)
end

local function draw()
  cv:fill(C.bg)
  local seg = math.floor(H / 16)
  local mid = W // 2
  for i = 0, 7 do
    cv:rect(mid - 1, i * seg * 2 + seg // 2, 2, seg, C.sub)
  end
  cv:rect(pad, math.floor(py), pw, ph, C.text, true, 2)
  cv:rect(W - pad - pw, math.floor(cy), pw, ph, C.accent, true, 2)
  cv:text(mid - 40 - wada.ui.text_w(tostring(ps), 24), 4, tostring(ps), C.text, 24)
  cv:text(mid + 40, 4, tostring(cs), C.accent, 24)
  if state == "play" then
    cv:circle(math.floor(bx), math.floor(by), br, C.text)
  elseif state == "ready" then
    center("PONG", H * 0.3, 24, C.text)
    center("W/S, swipe or drag to move", H * 0.5, 12, C.sub)
    center("Enter or tap to start", H * 0.6, 12, C.sub)
    center("Wins: " .. wins, H * 0.75, 12, C.good)
  else
    local won = ps > cs
    center(won and "YOU WIN!" or "CPU WINS", H * 0.3, 24, won and C.good or C.bad)
    center("Wins: " .. wins, H * 0.5, 14, C.sub)
    center("Enter or tap to play again", H * 0.65, 12, C.sub)
  end
end

local function move(d)
  py = clamp(py + d, 0, H - ph)
end

function app.on_open(w, h)
  W, H = w, h
  pw = math.max(6, math.floor(W * 0.025))
  ph = math.floor(H * 0.22)
  pad = 8
  br = math.max(3, math.floor(H * 0.025))
  py = (H - ph) / 2
  cy = py
  bx, by, vx, vy = W / 2, H / 2, 0, 0
  wins = tonumber(wada.store.get("wins")) or 0
  cv = wada.ui.canvas(W, H)
  cv:pos(0, 0)
  last = wada.sys.millis()
  wada.timer.every(33)
  draw()
end

function app.on_tick()
  local now = wada.sys.millis()
  local dt = clamp((now - last) / 1000, 0, 0.05)
  last = now
  if state == "play" then update(dt) end
  draw()
end

function app.on_input(ev)
  local step = H * 0.12
  if ev.type == "key" then
    local k = ev.key
    if k == "w" or k == "up" then
      move(-step)
    elseif k == "s" or k == "down" then
      move(step)
    elseif (k == "enter" or k == " ") and state ~= "play" then
      start()
    end
  elseif ev.type == "swipe" then
    swiped = true
    if ev.dir == "up" then move(-step) elseif ev.dir == "down" then move(step) end
  elseif ev.type == "down" then
    if state == "play" then py = clamp(ev.y - ph / 2, 0, H - ph) end
  elseif ev.type == "up" then
    if swiped then
      swiped = false
    elseif state ~= "play" then
      start()
    end
  end
end

return app
