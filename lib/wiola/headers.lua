--
-- Project: wiola
-- User: Konstantin Burkalev
-- Date: 16.03.14
--

ngx.header["Server"] = "wiola/Lua v0.9.0"

local has = function(tab, val)
    for _, value in ipairs (tab) do
        if value == val then
            return true
        end
    end

    return false
end

local wiola_config = require "wiola.config"
local conf = wiola_config.config()

if conf.cookieAuth.authType ~= "none" then

    ngx.log(ngx.DEBUG, "Checking credentials. Auth type set to ", conf.cookieAuth.authType)

    local cookieValue = ngx.unescape_uri(ngx.var["cookie_" .. conf.cookieAuth.cookieName])

    if not cookieValue then
        ngx.log(ngx.ERR, "No auth cookie found!")
        return ngx.exit(ngx.HTTP_FORBIDDEN)
    end

    ngx.log(ngx.DEBUG, "Client cookie ", conf.cookieAuth.cookieName, " is set to ", cookieValue)

    if conf.cookieAuth.authType == "static" then

        if not has(conf.cookieAuth.staticCredentials, cookieValue) then
            ngx.log(ngx.ERR, "No valid credential found!")
            return ngx.exit(ngx.HTTP_FORBIDDEN)
        end

    elseif conf.cookieAuth.authType == "dynamic" then

        if not conf.cookieAuth.authCallback(cookieValue) then
            ngx.log(ngx.ERR, "No valid credential found!")
            return ngx.exit(ngx.HTTP_FORBIDDEN)
        end
    end

    ngx.log(ngx.DEBUG, "Successfully authorized client using cookie!")
end

local wsProto = ngx.req.get_headers()["Sec-WebSocket-Protocol"]

ngx.log(ngx.DEBUG, "Client Sec-WebSocket-Protocol: ", wsProto)

if wsProto then
    local wsProtos = {}
    local i = 1

    for p in string.gmatch(wsProto, '([^, ]+)') do
        wsProtos[#wsProtos+1] = p
    end

    while i <= #wsProtos do
        if wsProtos[i] == 'wamp.2.json' or wsProtos[i] == 'wamp.2.msgpack' then
            ngx.header["Sec-WebSocket-Protocol"] = wsProtos[i]
            ngx.log(ngx.DEBUG, "Server Sec-WebSocket-Protocol selected: ", wsProtos[i])
            break
        end
        i = i + 1
    end
end
