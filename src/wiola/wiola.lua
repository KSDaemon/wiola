--
-- Project: this project
-- User: kostik
-- Date: 16.03.14
--

local _M = {
	_VERSION = '0.1',
	_wamp_features = {
		agent = "wiola/Lua v0.1",
		roles = {
			broker = {},
			dealer = {}
		}
	}
}

_M.__index = _M

local WAMP_MSG_SPEC = {
	HELLO = 1,
	WELCOME = 2,
	ABORT = 3,
	CHALLENGE = 4,
	AUTHENTICATE = 5,
	GOODBYE = 6,
	HEARTBEAT = 7,
	ERROR = 8,
	PUBLISH = 16,
	PUBLISHED = 17,
	SUBSCRIBE = 32,
	SUBSCRIBED = 33,
	UNSUBSCRIBE = 34,
	UNSUBSCRIBED = 35,
	EVENT = 36,
	CALL = 48,
	CANCEL = 49,
	RESULT = 50,
	REGISTER = 64,
	REGISTERED = 65,
	UNREGISTER = 66,
	UNREGISTERED = 67,
	INVOCATION = 68,
	INTERRUPT = 69,
	YIELD = 70
}

local _cache = {
	_wamp_protocol = 'wamp.2.json',
	sessions = {},
	publications = {},
	subscriptions = {},
	registrations = {},
	ids = {},
	requests = {}
}

-- Generate unique Id
local function getRegId()
	local regId
	local uniqFl = false

	math.randomseed( os.time() )

	while not uniqFl do
--		regId = math.random(9007199254740992)
		regId = math.random(100000000000000)
		local foundFl = false

		for k,v in pairs(_cache.ids) do
			if k == regId then
				foundFl = true
				break
			end
		end

		if not foundFl then
			uniqFl = true
		end
	end
	return regId
end

-- Validate uri for WAMP requirements
local function validateURI (uri)
--	var re = /^([0-9a-z_]{2,}\.)*([0-9a-z_]{2,})$/;
--	if(!re.test(uri) || uri.indexOf('wamp') === 0) {
--		return false;
--	} else {
--		return true;
--	}
end

-- Put selected wamp subprotocol for sid into temp cache
function _M.setWampProtocol(p, sid)
	_cache.requests[sid] = { wamp_protocol = p }
end

-- Add connection to wiola
function _M.addConnection(conn, sid)
	local regId = getRegId()

	_cache.ids[regId] = true
	if _cache.requests[sid] then
		local wProto = _cache.requests[sid].wamp_protocol
		_cache.requests[sid] = nil
	else
		local wProto = _cache._wamp_protocol
	end

	if wProto == 'wamp.2.msgpack' then
		local dataType = 'binary'
	else
		local dataType = 'text'
	end

	_cache.sessions[regId] = {
		ws = conn,
		sid = sid,
		isWampEstablished = false,
		realm = nil,
		wamp_features = nil,
		wamp_protocol = wProto,
		dataType = dataType,
		data = {}
	}
	return regId, dataType
end

-- Confirm WAMP session establishment (not websocket)
function _M.confirmWampEstablishment(regId)
	_cache.sessions[regId].isWampEstablished = true
end

-- Remove connection from wiola
function _M.removeConnection(regId)
	_cache.sessions[regId] = nil
	_cache.ids[regId] = nil
end

-- Receive data from client
function _M.receiveData(regId, data)
	local session = _cache.sessions[regId]
	local dataObj

	if session.wamp_protocol == 'wamp.2.msgpack' then
		local mp = require 'MessagePack'
		dataObj = mp.unpack(data)
	else --if session.wamp_protocol == 'wamp.2.json'
		local cjson = require "cjson"
		dataObj = cjson.decode(data)
	end

	ngx.log(ngx.DEBUG, "Received data decoded. WAMP msg Id: ", dataObj[1], " Realm: ", dataObj[2])
end

-- Retrieve data, available for session
function _M.getPendingData(regId)
	return _cache.sessions[regId].data
end

return _M
