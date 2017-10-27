local _M = { }

_M.protocol = 'msgpack';

local mp = require 'MessagePack'
local orig_map = mp.packers['map']
local orig_array = mp.packers['array']

mp.packers['array'] = function(buffer, tbl, n)
    if type(tbl.__jsontype) == 'string' and tbl.__jsontype == 'object' then
        orig_map(buffer, tbl, n)
    else
        orig_array(buffer, tbl, n)
    end
end

mp.packers['map'] = function(buffer, tbl, n)
    if type(tbl.__jsontype) == 'string' and tbl.__jsontype == 'array' then
        orig_array(buffer, tbl, n)
    else
        orig_map(buffer, tbl, n)
    end
end

function _M.encode(data)
    return mp.pack(data)
end

function _M.decode(data)
    return mp.unpack(data)
end

return _M
