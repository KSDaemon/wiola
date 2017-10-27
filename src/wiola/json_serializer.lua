local _M = { }

_M.protocol = 'json';

local json = require "rapidjson"

function _M.encode(data)
    return json.encode(data)
end

function _M.decode(data)
    return json.decode(data)
end

return _M
