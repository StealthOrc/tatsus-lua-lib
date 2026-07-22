local utf8 = require("utf8")

local TextEditor = {}
TextEditor.__index = TextEditor

local function characters(value)
    local result = {}
    for _, codepoint in utf8.codes(tostring(value or "")) do
        result[#result + 1] = utf8.char(codepoint)
    end
    return result
end

local function join(chars)
    return table.concat(chars)
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function class(character)
    if character == nil or character == "" then
        return "none"
    elseif character:match("%s") then
        return "space"
    elseif character:match("[%w_]") then
        return "word"
    end
    return "separator"
end

function TextEditor.new(options)
    options = options or {}
    local chars = characters(options.value)
    local cursor = clamp(options.cursor or #chars, 0, #chars)
    return setmetatable({
        chars = chars,
        cursor = cursor,
        anchor = cursor,
        max_length = options.max_length,
        filter = options.filter,
    }, TextEditor)
end

function TextEditor:value()
    return join(self.chars)
end

function TextEditor:length()
    return #self.chars
end

function TextEditor:set_value(value, select_all)
    self.chars = characters(value)
    self.cursor = #self.chars
    self.anchor = select_all and 0 or self.cursor
end

function TextEditor:selection()
    return math.min(self.anchor, self.cursor), math.max(self.anchor, self.cursor)
end

function TextEditor:has_selection()
    return self.anchor ~= self.cursor
end

function TextEditor:selected_text()
    local first, last = self:selection()
    return join({unpack(self.chars, first + 1, last)})
end

function TextEditor:select_all()
    self.anchor = 0
    self.cursor = #self.chars
end

function TextEditor:clear_selection()
    self.anchor = self.cursor
end

function TextEditor:replace_selection(value)
    local incoming = characters(value)
    if self.filter then
        local accepted = self.filter(join(incoming), self:value())
        if accepted == false or accepted == nil then
            return false
        end
        if type(accepted) == "string" then
            incoming = characters(accepted)
        end
    end

    local first, last = self:selection()
    local room = self.max_length and math.max(0, self.max_length - (#self.chars - (last - first))) or #incoming
    while #incoming > room do
        table.remove(incoming)
    end

    local next_chars = {}
    for index = 1, first do
        next_chars[#next_chars + 1] = self.chars[index]
    end
    for _, character in ipairs(incoming) do
        next_chars[#next_chars + 1] = character
    end
    for index = last + 1, #self.chars do
        next_chars[#next_chars + 1] = self.chars[index]
    end

    local changed = join(next_chars) ~= self:value()
    self.chars = next_chars
    self.cursor = first + #incoming
    self.anchor = self.cursor
    return changed
end

function TextEditor:insert(value)
    return self:replace_selection(value)
end

function TextEditor:delete_backward(by_word)
    if self:has_selection() then
        return self:replace_selection("")
    end
    if self.cursor == 0 then
        return false
    end
    self.anchor = self.cursor - 1
    if by_word then
        while self.anchor > 0 and class(self.chars[self.anchor + 1]) == "space" do
            self.anchor = self.anchor - 1
        end
        local target_class = class(self.chars[self.anchor + 1])
        while self.anchor > 0 and class(self.chars[self.anchor]) == target_class do
            self.anchor = self.anchor - 1
        end
    end
    return self:replace_selection("")
end

function TextEditor:delete_forward(by_word)
    if self:has_selection() then
        return self:replace_selection("")
    end
    if self.cursor >= #self.chars then
        return false
    end
    self.anchor = self.cursor + 1
    if by_word then
        self.anchor = self.cursor
        while self.anchor < #self.chars and class(self.chars[self.anchor + 1]) == "space" do
            self.anchor = self.anchor + 1
        end
        local target_class = class(self.chars[self.anchor + 1])
        while self.anchor < #self.chars and class(self.chars[self.anchor + 1]) == target_class do
            self.anchor = self.anchor + 1
        end
    end
    return self:replace_selection("")
end

function TextEditor:move_to(position, selecting)
    self.cursor = clamp(position, 0, #self.chars)
    if not selecting then
        self.anchor = self.cursor
    end
end

function TextEditor:move(direction, selecting, by_word)
    local target = self.cursor + direction
    if not selecting and self:has_selection() and not by_word then
        local first, last = self:selection()
        target = direction < 0 and first or last
    elseif by_word then
        if direction < 0 then
            target = self.cursor
            while target > 0 and class(self.chars[target]) == "space" do
                target = target - 1
            end
            local target_class = class(self.chars[target])
            while target > 0 and class(self.chars[target]) == target_class do
                target = target - 1
            end
        else
            target = self.cursor
            while target < #self.chars and class(self.chars[target + 1]) == "space" do
                target = target + 1
            end
            local target_class = class(self.chars[target + 1])
            while target < #self.chars and class(self.chars[target + 1]) == target_class do
                target = target + 1
            end
        end
    end
    self:move_to(target, selecting)
end

function TextEditor:prefix(position)
    return join({unpack(self.chars, 1, clamp(position, 0, #self.chars))})
end

return TextEditor
