--
-- Project: this project
-- User: kostik
-- Date: 16.03.14
--

local webSocket, err = wsServer:new({
	timeout = 5000,
	max_payload_len = 65535
})

if not webSocket then
	ngx.log(ngx.ERR, "Failed to create new websocket: ", err)
	return ngx.exit(444)
end

ngx.log(ngx.DEBUG, "Created websocket")
ngx.log(ngx.DEBUG, "Client SID: ", ngx.var.connection)

local sessionId, dataType = wampServer.addConnection(webSocket, ngx.var.connection)
ngx.log(ngx.DEBUG, "Adding connection to list. Session Id: ", sessionId)

--ngx.log(ngx.DEBUG, "Sending SID to client")
--local cjson = require "cjson"
--local msg = {}
--msg[1] = { eventType = 'wsInit', wsid = ngx.var.connection }
--local bytes, err = webSocket:send_text(cjson.encode(msg))
--if not bytes then
--	ngx.log(ngx.ERR, "failed to send data: ", err)
--end
--		local cjson = require "cjson"
--		local dataObj = cjson.decode(data)
--
--		if dataObj.eventType == 'modelUpdate' and tonumber(dataObj.wsid) > 0 then
--			putAdminClientsDataToNotify(dataObj, dataObj.wsid)
--		else
--			putAdminClientsDataToNotify(dataObj)
--		end


while true do
	local data, typ, err = webSocket:recv_frame()

	local cliData = wampServer.getPendingData(sessionId)

	while #cliData > 0 do
		ngx.log(ngx.DEBUG, "Get data for client. Sending...")

		if dataType == 'binary' then
			local bytes, err = webSocket:send_binary(table.remove(cliData, 1))
		else
			local bytes, err = webSocket:send_text(table.remove(cliData, 1))
		end

		if not bytes then
			ngx.log(ngx.ERR, "Failed to send data: ", err)
		end
	end

	if webSocket.fatal then
		ngx.log(ngx.ERR, "Failed to receive frame: ", err)
		wampServer.removeConnection(sessionId)
		return ngx.exit(444)
	end

	if not data then

		local bytes, err = webSocket:send_ping()
		if not bytes then
			ngx.log(ngx.ERR, "Failed to send ping: ", err)
			wampServer.removeConnection(sessionId)
			return ngx.exit(444)
		end

	elseif typ == "close" then

		ngx.log(ngx.DEBUG, "Normal closing websocket. SID: ", ngx.var.connection)
		local bytes, err = webSocket:send_close(1000, "Closing connection")
			if not bytes then
				ngx.log(ngx.ERR, "Failed to send the close frame: ", err)
				return
			end
		wampServer.removeConnection(sessionId)
		break

	elseif typ == "ping" then

		local bytes, err = webSocket:send_pong()
		if not bytes then
			ngx.log(ngx.ERR, "Failed to send pong: ", err)
			wampServer.removeConnection(sessionId)
			return ngx.exit(444)
		end

	elseif typ == "pong" then

--		ngx.log(ngx.DEBUG, "client ponged")

	elseif typ == "text" then -- Received something texty

		ngx.log(ngx.DEBUG, "Received text data: ", data)
		wampServer.receiveData(sessionId, data)

	elseif typ == "binary" then -- Received something binary

		ngx.log(ngx.DEBUG, "Received binary data")
		wampServer.receiveData(sessionId, data)

	end
end

-- Just for clearance
webSocket:send_close()
wampServer.removeConnection(sessionId)
