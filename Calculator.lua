-- WADAMESH Scientific Calculator

local app = {}

local ui = wada.ui
local colors = ui.colors

local W = 320
local H = 240

local display
local mode_label

local expression = ""
local ans = 0
local angle_mode = "DEG"

-- After a calculation, C/AC starts in AC mode.
local clear_mode = "C"

-- ============================================================
-- DISPLAY / UTILITY
-- ============================================================

local function refresh_display()
    if not display then
        return
    end

    local text = expression

    if text == "" then
        text = "0"
    end

    display:set(text)
    display:color(colors.text)
end


local function format_number(x)

    if x ~= x then
        return "NaN"
    end

    if x == math.huge then
        return "Inf"
    end

    if x == -math.huge then
        return "-Inf"
    end

    local ax = math.abs(x)

    -- Scientific notation for very large/small numbers.
    if ax ~= 0 and (ax >= 1e10 or ax < 1e-8) then
        return string.format("%.10g", x)
    end

    -- Otherwise remove unnecessary trailing zeroes.
    local s = string.format("%.10f", x)

    s = s:gsub("0+$", "")
    s = s:gsub("%.$", "")

    if s == "-0" then
        s = "0"
    end

    return s
end


local function show_error(message)

    expression = ""

    if display then
        display:set(message)
        display:color(colors.bad)
    end

    wada.sys.beep()
end


local function append_text(text)

    expression = expression .. text
    clear_mode = "C"

    refresh_display()
end


-- ============================================================
-- TRIGONOMETRY
-- ============================================================

local function to_radians(x)

    if angle_mode == "DEG" then
        return x * math.pi / 180
    end

    return x
end


local function from_radians(x)

    if angle_mode == "DEG" then
        return x * 180 / math.pi
    end

    return x
end


local functions = {}


functions.sin = function(x)
    return math.sin(to_radians(x))
end


functions.cos = function(x)
    return math.cos(to_radians(x))
end


functions.tan = function(x)

    local r = to_radians(x)

    -- Avoid returning a huge meaningless number at
    -- 90, 270, etc.
    if math.abs(math.cos(r)) < 1e-12 then
        error("undefined")
    end

    return math.tan(r)
end


functions.asin = function(x)

    if x < -1 or x > 1 then
        error("domain")
    end

    return from_radians(math.asin(x))
end


functions.acos = function(x)

    if x < -1 or x > 1 then
        error("domain")
    end

    return from_radians(math.acos(x))
end


functions.atan = function(x)
    return from_radians(math.atan(x))
end


functions.sqrt = function(x)

    if x < 0 then
        error("domain")
    end

    return math.sqrt(x)
end


functions.ln = function(x)

    if x <= 0 then
        error("domain")
    end

    return math.log(x)
end


functions.log = function(x)

    if x <= 0 then
        error("domain")
    end

    return math.log10(x)
end


functions.exp = function(x)
    return math.exp(x)
end


functions.abs = function(x)
    return math.abs(x)
end


-- ============================================================
-- FACTORIAL
-- ============================================================

local function factorial(n)

    if n < 0 then
        error("factorial domain")
    end

    if n ~= math.floor(n) then
        error("integer required")
    end

    -- 171! exceeds normal Lua floating-point range.
    if n > 170 then
        error("overflow")
    end

    local result = 1

    for i = 2, n do
        result = result * i
    end

    return result
end


-- ============================================================
-- EXPRESSION PARSER
-- ============================================================

local Parser = {}
Parser.__index = Parser


function Parser.new(text)

    return setmetatable({
        text = text,
        pos = 1,
        len = #text
    }, Parser)

end


function Parser:skip()

    while self.pos <= self.len do

        local c = self.text:sub(self.pos, self.pos)

        if c == " " or c == "\t" then
            self.pos = self.pos + 1
        else
            break
        end

    end

end


function Parser:consume(c)

    self:skip()

    if self.text:sub(self.pos, self.pos) == c then
        self.pos = self.pos + 1
        return true
    end

    return false
end


function Parser:expect(c)

    if not self:consume(c) then
        error("expected " .. c)
    end

end


function Parser:identifier()

    self:skip()

    local start = self.pos

    while self.pos <= self.len do

        local c = self.text:sub(self.pos, self.pos)

        if c:match("%a") then
            self.pos = self.pos + 1
        else
            break
        end

    end

    if self.pos == start then
        return nil
    end

    return self.text:sub(start, self.pos - 1):lower()
end


function Parser:number()

    self:skip()

    local start = self.pos
    local saw_digit = false

    -- Integer portion.
    while self.pos <= self.len do

        local c = self.text:sub(self.pos, self.pos)

        if c >= "0" and c <= "9" then
            saw_digit = true
            self.pos = self.pos + 1
        else
            break
        end

    end

    -- Decimal portion.
    if self.text:sub(self.pos, self.pos) == "." then

        self.pos = self.pos + 1

        while self.pos <= self.len do

            local c = self.text:sub(self.pos, self.pos)

            if c >= "0" and c <= "9" then
                saw_digit = true
                self.pos = self.pos + 1
            else
                break
            end

        end

    end

    if not saw_digit then
        self.pos = start
        return nil
    end

    -- Scientific notation.
    local c = self.text:sub(self.pos, self.pos)

    if c == "e" or c == "E" then

        local save = self.pos

        self.pos = self.pos + 1

        local sign = self.text:sub(self.pos, self.pos)

        if sign == "+" or sign == "-" then
            self.pos = self.pos + 1
        end

        local exp_start = self.pos

        while self.pos <= self.len do

            local d = self.text:sub(self.pos, self.pos)

            if d >= "0" and d <= "9" then
                self.pos = self.pos + 1
            else
                break
            end

        end

        -- If there were no exponent digits, treat the e as
        -- belonging to the following expression instead.
        if self.pos == exp_start then
            self.pos = save
        end

    end

    local n = tonumber(
        self.text:sub(start, self.pos - 1)
    )

    if not n then
        error("bad number")
    end

    return n
end


-- expression = term { + term | - term }

function Parser:expression()

    local value = self:term()

    while true do

        if self:consume("+") then

            value = value + self:term()

        elseif self:consume("-") then

            value = value - self:term()

        else
            break
        end

    end

    return value
end


-- term = unary { * unary | / unary }

function Parser:term()

    local value = self:unary()

    while true do

        if self:consume("*") then

            value = value * self:unary()

        elseif self:consume("/") then

            local divisor = self:unary()

            if divisor == 0 then
                error("divide by zero")
            end

            value = value / divisor

        else
            break
        end

    end

    return value
end


-- unary = +unary | -unary | power

function Parser:unary()

    if self:consume("+") then
        return self:unary()
    end

    if self:consume("-") then
        return -self:unary()
    end

    return self:power()
end


-- power = postfix [ ^ unary ]

function Parser:power()

    local value = self:postfix()

    if self:consume("^") then

        local exponent = self:unary()

        value = value ^ exponent

        if value ~= value then
            error("invalid power")
        end

    end

    return value
end


-- postfix = primary { ! | % }

function Parser:postfix()

    local value = self:primary()

    while true do

        if self:consume("!") then

            value = factorial(value)

        elseif self:consume("%") then

            value = value / 100

        else
            break
        end

    end

    return value
end


-- primary = number | constant | function | (expression)

function Parser:primary()

    self:skip()

    -- Parentheses.
    if self:consume("(") then

        local value = self:expression()

        self:expect(")")

        return value
    end

    -- Number.
    local save = self.pos

    local n = self:number()

    if n ~= nil then
        return n
    end

    self.pos = save

    -- Identifier.
    local name = self:identifier()

    if not name then
        error("expected value")
    end

    if name == "pi" then
        return math.pi
    end

    if name == "e" then
        return math.exp(1)
    end

    if name == "ans" then
        return ans
    end

    local fn = functions[name]

    if fn then
        return fn(self:primary())
    end

    error("unknown " .. name)
end


function Parser:parse()

    local result = self:expression()

    self:skip()

    if self.pos <= self.len then
        error("unexpected input")
    end

    return result
end


-- ============================================================
-- CALCULATE
-- ============================================================

local function calculate()

    if expression == "" then
        return
    end

    local parser = Parser.new(expression)

    local ok, result = pcall(function()
        return parser:parse()
    end)

    if not ok then

        local message = tostring(result)

        -- Remove Lua's source location when present.
        message = message:gsub("^.-:%d+: ", "")

        show_error(message)

        return
    end

    if result ~= result or
       result == math.huge or
       result == -math.huge then

        show_error("Math error")

        return
    end

    ans = result

    expression = format_number(result)

    -- A displayed result means the next clear operation
    -- is effectively AC.
    clear_mode = "AC"

    display:set(expression)
    display:color(colors.good)

    wada.sys.beep()
end


-- ============================================================
-- C / AC
-- ============================================================

local function clear_button()

    if clear_mode == "AC" then

        -- Full reset.
        expression = ""
        ans = 0
        clear_mode = "C"

    else

        -- Clear current expression.
        expression = ""
        clear_mode = "C"

    end

    refresh_display()

    wada.sys.beep()
end


-- ============================================================
-- BACKSPACE
-- ============================================================

local function backspace()

    if expression ~= "" then
        expression = expression:sub(1, -2)
    end

    clear_mode = "C"

    refresh_display()
end


-- ============================================================
-- ANGLE MODE
-- ============================================================

local function toggle_angle()

    if angle_mode == "DEG" then
        angle_mode = "RAD"
    else
        angle_mode = "DEG"
    end

    if mode_label then
        mode_label:set(angle_mode)
    end

    wada.sys.toast("Angle: " .. angle_mode)
end


-- ============================================================
-- BUTTON ACTIONS
-- ============================================================

local function press(label)

    -- Clear / All Clear.
    if label == "C/AC" then
        clear_button()
        return
    end

    -- Equals.
    if label == "=" then
        calculate()
        return
    end

    -- Backspace.
    if label == "BACK" then
        backspace()
        return
    end

    -- Square.
    if label == "x^2" then
        append_text("^2")
        return
    end

    -- Square root.
    if label == "SQRT" then
        append_text("sqrt(")
        return
    end

    -- Reciprocal.
    if label == "1/x" then
        append_text("1/(")
        return
    end

    -- Pi.
    if label == "PI" then
        append_text("pi")
        return
    end

    -- Trigonometry.
    if label == "SIN" then
        append_text("sin(")
        return
    end

    if label == "COS" then
        append_text("cos(")
        return
    end

    if label == "TAN" then
        append_text("tan(")
        return
    end

    if label == "ASIN" then
        append_text("asin(")
        return
    end

    if label == "ACOS" then
        append_text("acos(")
        return
    end

    if label == "ATAN" then
        append_text("atan(")
        return
    end

    -- Logs.
    if label == "LN" then
        append_text("ln(")
        return
    end

    if label == "LOG" then
        append_text("log(")
        return
    end

    -- Sign.
    if label == "±" then

        if expression == "" then
            append_text("-")
        else
            expression = "-(" .. expression .. ")"
            refresh_display()
        end

        return
    end

    -- Angle mode.
    if label == "DEG/RAD" then
        toggle_angle()
        return
    end

    -- Everything else is literal input.
    append_text(label)
end


-- ============================================================
-- USER INTERFACE
-- ============================================================

local function build_ui()

    ui.clear()

    -- --------------------------------------------------------
    -- Header
    -- --------------------------------------------------------

    ui.label(
        "SCIENTIFIC CALCULATOR",
        5,
        3,
        12,
        colors.accent
    )

    mode_label = ui.label(
        angle_mode,
        W - 45,
        3,
        12,
        colors.good
    )

    -- --------------------------------------------------------
    -- Display
    -- --------------------------------------------------------

    display = ui.label(
        "0",
        5,
        25,
        18,
        colors.text
    )

    display:width(W - 10, "right")

    -- --------------------------------------------------------
    -- Keypad
    --
    -- The previous version used fixed button heights.
    -- That allowed the sixth row to reach the physical edge.
    --
    -- Here the available vertical space is calculated first,
    -- then divided between the six rows.
    -- --------------------------------------------------------

    local keys = {

        {"SIN",  "COS",  "TAN",  "C/AC", "LN",   "LOG"},

        {"7",    "8",    "9",    "/",    "(",    ")"},

        {"4",    "5",    "6",    "*",    "-",    "+"},

        {"1",    "2",    "3",    "^",    "x^2",  "="},

        {"0",    ".",    "PI",   "E",    "!",    "%"},

        {"SIN", "COS",  "TAN", "SQRT", "1/x",  "BACK"}
    }

    local margin_x = 4

    -- Explicit bottom safety margin.
    local margin_bottom = 5

    local gap_x = 3
    local gap_y = 2

    -- Display ends around y=43.
    -- Start buttons at 67 to leave comfortable separation.
    local top = 67

    local column_count = 6
    local row_count = 6

    -- --------------------------------------------------------
    -- Width
    -- --------------------------------------------------------

    local button_w = math.floor(
        (
            W
            - (margin_x * 2)
            - (gap_x * (column_count - 1))
        ) / column_count
    )

    -- --------------------------------------------------------
    -- Height
    -- --------------------------------------------------------

    local available_height =
        H
        - top
        - margin_bottom

    local button_h = math.floor(
        (
            available_height
            - (gap_y * (row_count - 1))
        ) / row_count
    )

    -- Prevent an unexpectedly small display from creating
    -- unusable buttons.
    if button_h < 20 then
        button_h = 20
    end

    -- --------------------------------------------------------
    -- Create buttons
    -- --------------------------------------------------------

    for row = 1, row_count do

        local y =
            top
            + ((row - 1) * (button_h + gap_y))

        for col = 1, column_count do

            local label = keys[row][col]

            local x =
                margin_x
                + ((col - 1) * (button_w + gap_x))

            ui.button(
                label,
                x,
                y,
                button_w,
                button_h,
                function()
                    press(label)
                end
            )

        end
    end
end


-- ============================================================
-- KEYBOARD INPUT
-- ============================================================

local keymap = {

    ["0"] = "0",
    ["1"] = "1",
    ["2"] = "2",
    ["3"] = "3",
    ["4"] = "4",
    ["5"] = "5",
    ["6"] = "6",
    ["7"] = "7",
    ["8"] = "8",
    ["9"] = "9",

    ["."] = ".",

    ["+"] = "+",
    ["-"] = "-",
    ["*"] = "*",
    ["/"] = "/",

    ["^"] = "^",
    ["("] = "(",
    [")"] = ")",

    ["!"] = "!",
    ["%"] = "%"
}


local function key_press(key)

    if key == "enter" or key == "=" then
        calculate()
        return
    end

    if key == "backspace" then
        backspace()
        return
    end

    if key == "escape" or key == "esc" then
        clear_button()
        return
    end

    if key == "d" or key == "D" then
        toggle_angle()
        return
    end

    if key == "c" or key == "C" then
        clear_button()
        return
    end

    if key == "s" or key == "S" then
        press("SIN")
        return
    end

    if key == "q" or key == "Q" then
        press("SQRT")
        return
    end

    if key == "l" or key == "L" then
        press("LN")
        return
    end

    if key == "p" or key == "P" then
        press("PI")
        return
    end

    if key == "e" or key == "E" then
        append_text("e")
        return
    end

    local mapped = keymap[key]

    if mapped then
        append_text(mapped)
    end
end


-- ============================================================
-- APP LIFECYCLE
-- ============================================================

function app.on_open(w, h)

    if w then
        W = w
    end

    if h then
        H = h
    end

    build_ui()
end


function app.on_input(ev)

    if ev.type == "key" then
        key_press(ev.key)
    end
end


function app.on_close()
end


return app
