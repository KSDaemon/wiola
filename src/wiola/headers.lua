--
-- Project: this project
-- User: kostik
-- Date: 16.03.14
--

ngx.header["Server"] = "wiola/Lua v0.1"
--ngx.header.sec_webSocket_protocol = 'wamp.2.json'

local wsProto = ngx.req.get_headers()["Sec-WebSocket-Protocol"]

ngx.log(ngx.DEBUG, "Client Sec-WebSocket-Protocol: ", wsProto)
ngx.log(ngx.DEBUG, "Client SID: ", ngx.var.connection)

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
			wampServer.setWampProtocol(wsProtos[i], ngx.var.connection)
			break
		end

		i = i + 1
	end
end
