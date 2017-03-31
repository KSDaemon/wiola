--
-- Project: wiola
-- User: Konstantin Burkalev
-- Date: 16.03.14
--

ngx.header["Server"] = "wiola/Lua v0.6.0"

function has(tab, val)
    for index, value in ipairs (tab) do
        if value == val then
            return true
        end
    end

    return false
end

local wiola_config = require "wiola.config"
local conf = wiola_config.config()

if conf.cookieAuth.authType ~= "none" then

    local cookieValue = ngx.unescape_uri(ngx.var["cookie_" .. conf.cookieAuth.cookieName])

    if not cookieValue then
        return ngx.exit(ngx.HTTP_FORBIDDEN)
    end

    if conf.cookieAuth.authType == "static" then

        if not has(conf.cookieAuth.staticCredentials, cookieValue) then
            return ngx.exit(ngx.HTTP_FORBIDDEN)
        end

    elseif conf.cookieAuth.authType == "dynamic" then

        if not conf.cookieAuth.authCallback(cookieValue) then
            return ngx.exit(ngx.HTTP_FORBIDDEN)
        end
    end
end

local wsProto = ngx.req.get_headers()["Sec-WebSocket-Protocol"]

if wsProto then
    local wsProtos = {}
    local i = 1

    for p in string.gmatch(wsProto, '([^, ]+)') do
        wsProtos[#wsProtos+1] = p
    end

    while i <= #wsProtos do
        if wsProtos[i] == 'wamp.2.json' or wsProtos[i] == 'wamp.2.msgpack' then
            ngx.header["Sec-WebSocket-Protocol"] = wsProtos[i]
            break
        end
        i = i + 1
    end
end
