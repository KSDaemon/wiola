--
-- Project: wiola
-- User: Konstantin Burkalev
-- Date: 16.03.14
--

ngx.header["Server"] = "wiola/Lua v0.5.0"

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
