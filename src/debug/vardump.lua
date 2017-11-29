--
-- Project: wiola
-- User: Konstantin Burkalev
-- Date: 16.03.14
--

local _M = { }

---------------------------------------------------
-- Recursive var dumping.
--
-- Prints a value dump
--
-- value - any value to dump
-- depth - current depth (in case of recursive dumping)
-- key - current key name (in case of recursive dumping)
---------------------------------------------------
local function printdump(value, depth, key)
    local linePrefix = ''
    local spaces = ''
    local mTable

    if key ~= nil then
        linePrefix = '[' .. key .. '] = '
    end

    if depth == nil then
        depth = 0
    else
        for _ = 1, depth do spaces = spaces .. '  ' end
        depth = depth + 1
        spaces = spaces .. ' » '
    end

    if type(value) == 'table' then
        mTable = getmetatable(value)

        print(spaces .. linePrefix .. '(table) ')
        for tableKey, tableValue in pairs(value) do
            printdump(tableValue, depth, tableKey)
        end

        if mTable ~= nil then
            print(spaces .. '(metatable) ')
            for tableKey, tableValue in pairs(mTable) do
                printdump(tableValue, depth, tableKey)
            end
        end
    elseif type(value) == 'function' or type(value) == 'thread' or type(value) == 'userdata' or value == nil then
        print(spaces .. tostring(value))
    elseif type(value) == 'string' then
        print(spaces .. linePrefix .. '(string) "' .. tostring(value) .. '"')
    else
        print(spaces .. linePrefix .. '(' .. type(value) .. ') ' .. tostring(value))
    end
end

---------------------------------------------------
-- Recursive var dumping.
--
-- Returns a multiline string
--
-- value - any value to dump
-- depth - current depth (in case of recursive dumping)
-- key - current key name (in case of recursive dumping)
-- @return string
---------------------------------------------------
local function getdump(value, depth, key)
    local linePrefix = ''
    local spaces = ''
    local result = ''
    local mTable

    if key ~= nil then
        linePrefix = '[' .. key .. '] = '
    end

    if depth == nil then
        depth = 0
    else
        for _ = 1, depth do spaces = spaces .. '  ' end
        depth = depth + 1
        spaces = spaces .. ' » '
    end

    if type(value) == 'table' then
        mTable = getmetatable(value)

        result = result .. spaces .. linePrefix .. '(table) '
        for tableKey, tableValue in pairs(value) do
            result = result .. '\n' .. getdump(tableValue, depth, tableKey)
        end
        if mTable ~= nil then
            result = result .. '\n' .. spaces .. '(metatable) '
            for tableKey, tableValue in pairs(mTable) do
                result = result .. '\n' .. getdump(tableValue, depth, tableKey)
            end
        end
    elseif type(value) == 'function' or type(value) == 'thread' or type(value) == 'userdata' or value == nil then
        result = result .. spaces .. tostring(value)
    elseif type(value) == 'string' then
        result = result .. spaces .. linePrefix .. '(' .. type(value) .. ') "' .. tostring(value) .. '"'
    else
        result = result .. spaces .. linePrefix .. '(' .. type(value) .. ') ' .. tostring(value)
    end

    return result
end

_M.printdump = printdump
_M.getdump = getdump

return _M
