--
-- Project: this project
-- User: kostik
-- Date: 16.03.14
--

ngx.header["Server"] = "wiola v0.1"
--ngx.header.sec_webSocket_protocol = 'wamp.2.json'

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
			i = #wsProtos + 1
		end

		i = i + 1
	end
end
