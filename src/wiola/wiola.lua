--
-- Project: this project
-- User: kostik
-- Date: 16.03.14
--

local redisLib = require "resty.redis"
local redis = redisLib:new()

local ok, err = redis:connect("unix:/tmp/redis.sock")
if not ok then
	ngx.log(ngx.DEBUG, "Failed to connect to redis: ", err)
	return
end

local _M = {
	_VERSION = '0.1'
}

_M.__index = _M

local wamp_features = {
	agent = "wiola/Lua v0.1",
	roles = {
		broker = {},
		dealer = {}
	}
}

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

-- Generate unique Id
local function getRegId()
	local regId

	math.randomseed( os.time() )
	-- can use redis:time()

	repeat
--		regId = math.random(9007199254740992)
		regId = math.random(100000000000000)
	until redis:sismember("wiolaIds",regId)

	return regId
end

-- Validate uri for WAMP requirements
local function validateURI(uri)
	local m, err = ngx.re.match(uri, "^([0-9a-z_]{2,}\\\\.)*([0-9a-z_]{2,})$")
	if not m or string.find(uri, 'wamp') == 1 then
		return false
	else
		return true
	end
end

-- Convert redis hgetall array to lua table
local function redisArr2table(ra)
	local t = {}
	local i = 1

	while i < #ra do
		t[ra[i]] = ra[i+1]
		i = i + 2
	end

	return t
end

-- Add connection to wiola
function _M.addConnection(sid, wampProto)
	local regId = getRegId()
	local wProto, dataType

	redis:sadd("wiolaIds",regId)

	if wampProto == nil or wampProto == "" then
		wampProto = 'wamp.2.json'   -- Setting default protocol for encoding/decodig use
	end

	if wampProto == 'wamp.2.msgpack' then
		dataType = 'binary'
	else
		dataType = 'text'
	end

	redis:hmset("wiolaSession" .. regId,
		{ connId = sid,
		sessId = regId,
		isWampEstablished = 0,
--		realm = nil,
--		wamp_features = nil,
		wamp_protocol = wampProto,
		dataType = dataType }
	)

	return regId, dataType
end

-- Remove connection from wiola
function _M.removeConnection(regId)
	local session = redisArr2table(redis:hgetall("wiolaSession" .. regId))

	var_dump(session)

	ngx.log(ngx.DEBUG, "Removing session: ", regId)

	if session.realm then
		redis:srem("wiolaRealm" .. session.realm .. "Sessions",regId)

		local rs = redis:scard("wiolaRealm" .. session.realm .. "Sessions")

		if rs == 0 then
			redis:del("wiolaRealm" .. session.realm .. "Sessions")
		end

		ngx.log(ngx.DEBUG, "Realm ", session.realm, " sessions count now is ", rs)
	end

	local subscriptions = redisArr2table(redis:hgetall("wiolaSession" .. regId .. "Subscriptions"))

	for k, v in pairs(subscriptions) do
		redis:srem("wiolaRealm" .. session.realm .. "Subscription" .. k .. "Sessions", regId)
		if redis:scard("wiolaRealm" .. session.realm .. "Subscription" .. k .. "Sessions") == 0 then
			redis:srem("wiolaRealm" .. session.realm .. "Subscriptions",k)
		end
	end

	redis:del("wiolaSession" .. regId .. "Subscriptions")
	redis:del("wiolaSession" .. regId .. "RevSubscriptions")
	redis:del("wiolaSession" .. regId .. "Data")
	redis:del("wiolaSession" .. regId)
	redis:srem("wiolaIds",regId)
end

-- Prepare data for sending to client
local function putData(session, data)
	local dataObj

	if session.wamp_protocol == 'wamp.2.msgpack' then
		local mp = require 'MessagePack'
		dataObj = mp.pack(data)
	else --if session.wamp_protocol == 'wamp.2.json'
		local cjson = require "cjson"
		dataObj = cjson.encode(data)
	end

	ngx.log(ngx.DEBUG, "Preparing data for client: ", dataObj);

	redis:rpush("wiolaSession" .. session.sessId .. "Data", dataObj)
end

-- Receive data from client
function _M.receiveData(regId, data)
	local session = redisArr2table(redis:hgetall("wiolaSession" .. regId))
	session.isWampEstablished = tonumber(session.isWampEstablished)
	local cjson = require "cjson"
	local dataObj

--	var_dump(session)

	if session.wamp_protocol == 'wamp.2.msgpack' then
		local mp = require 'MessagePack'
		dataObj = mp.unpack(data)
	else --if session.wamp_protocol == 'wamp.2.json'
		dataObj = cjson.decode(data)
	end

	ngx.log(ngx.DEBUG, "Cli regId: ", regId, " Received data decoded. WAMP msg Id: ", dataObj[1])

	-- Analyze WAMP message ID received
	if dataObj[1] == WAMP_MSG_SPEC.HELLO then   -- WAMP SPEC: [HELLO, Realm|uri, Details|dict]
		if session.isWampEstablished == 1 then
			-- Protocol error: received second hello message - aborting
			-- WAMP SPEC: [GOODBYE, Details|dict, Reason|uri]
			putData(session, { WAMP_MSG_SPEC.GOODBYE, {}, "wamp.error.system_shutdown" })
		else
			local realm = dataObj[2]
			if validateURI(realm) then
				session.isWampEstablished = 1
				session.realm = realm
				session.wampFeatures = cjson.encode(dataObj[3])
				redis:hmset("wiolaSession" .. regId, session)

				if not redis:sismember("wiolaRealms",realm) then
					ngx.log(ngx.DEBUG, "No realm ", realm, " found. Creating...")
					redis:sadd("wiolaIds",regId)
				end

				redis:sadd("wiolaRealm" .. realm .. "Sessions", regId)

				-- WAMP SPEC: [WELCOME, Session|id, Details|dict]
				putData(session, { WAMP_MSG_SPEC.WELCOME, regId, wamp_features })
			else
				-- WAMP SPEC: [ABORT, Details|dict, Reason|uri]
				putData(session, { WAMP_MSG_SPEC.ABORT, {}, "wamp.error.invalid_realm" })
			end
		end
	elseif dataObj[1] == WAMP_MSG_SPEC.ABORT then   -- WAMP SPEC: [ABORT, Details|dict, Reason|uri]
		-- No response is expected
	elseif dataObj[1] == WAMP_MSG_SPEC.GOODBYE then   -- WAMP SPEC: [GOODBYE, Details|dict, Reason|uri]
		if session.isWampEstablished == 1 then
			putData(session, { WAMP_MSG_SPEC.GOODBYE, {}, "wamp.error.goodbye_and_out" })
		else
			putData(session, { WAMP_MSG_SPEC.GOODBYE, {}, "wamp.error.system_shutdown" })
		end
	elseif dataObj[1] == WAMP_MSG_SPEC.ERROR then
		-- WAMP SPEC: [ERROR, REQUEST.Type|int, REQUEST.Request|id, Details|dict, Error|uri]
		-- WAMP SPEC: [ERROR, REQUEST.Type|int, REQUEST.Request|id, Details|dict, Error|uri, Arguments|list]
		-- WAMP SPEC: [ERROR, REQUEST.Type|int, REQUEST.Request|id, Details|dict, Error|uri, Arguments|list, ArgumentsKw|dict]
		if session.isWampEstablished == 1 then

		else

		end
	elseif dataObj[1] == WAMP_MSG_SPEC.PUBLISH then
		-- WAMP SPEC: [PUBLISH, Request|id, Options|dict, Topic|uri]
		-- WAMP SPEC: [PUBLISH, Request|id, Options|dict, Topic|uri, Arguments|list]
		-- WAMP SPEC: [PUBLISH, Request|id, Options|dict, Topic|uri, Arguments|list, ArgumentsKw|dict]
		if session.isWampEstablished == 1 then

		else
			putData(session, { WAMP_MSG_SPEC.GOODBYE, {}, "wamp.error.system_shutdown" })
		end
	elseif dataObj[1] == WAMP_MSG_SPEC.SUBSCRIBE then   -- WAMP SPEC: [SUBSCRIBE, Request|id, Options|dict, Topic|uri]
		if session.isWampEstablished == 1 then
			if validateURI(dataObj[4]) then
				redis:sadd("wiolaRealm" .. session.realm .. "Subscriptions",dataObj[4])

				if redis:hget("wiolaSession" .. regId .. "Subscriptions", dataObj[4]) ~= ngx.null then
					putData(session, { WAMP_MSG_SPEC.ERROR, WAMP_MSG_SPEC.SUBSCRIBE, dataObj[2], {}, "wamp.error.already_subscribed" })
				else
					local subscriptionId = getRegId()
					redis:hset("wiolaSession" .. regId .. "Subscriptions", dataObj[4], subscriptionId)
					redis:hset("wiolaSession" .. regId .. "RevSubscriptions", subscriptionId, dataObj[4])
					redis:sadd("wiolaRealm" .. session.realm .. "Subscription" .. dataObj[4] .. "Sessions",regId)

					-- WAMP SPEC: [SUBSCRIBED, SUBSCRIBE.Request|id, Subscription|id]
					putData(session, { WAMP_MSG_SPEC.SUBSCRIBED, dataObj[2], subscriptionId })
				end
			else
				putData(session, { WAMP_MSG_SPEC.ERROR, WAMP_MSG_SPEC.SUBSCRIBE, dataObj[2], {}, "wamp.error.invalid_topic" })
			end
		else
			putData(session, { WAMP_MSG_SPEC.GOODBYE, {}, "wamp.error.system_shutdown" })
		end
	elseif dataObj[1] == WAMP_MSG_SPEC.UNSUBSCRIBE then   -- WAMP SPEC: [UNSUBSCRIBE, Request|id, SUBSCRIBED.Subscription|id]
		if session.isWampEstablished == 1 then
			local subscr = redis:hget("wiolaSession" .. regId .. "RevSubscriptions", dataObj[3])
			if subscr ~= ngx.null then
				redis:hdel("wiolaSession" .. regId .. "Subscriptions", subscr)
				redis:hdel("wiolaSession" .. regId .. "RevSubscriptions", dataObj[3])

				redis:srem("wiolaRealm" .. session.realm .. "Subscription" .. subscr .. "Sessions", regId)
				if redis:scard("wiolaRealm" .. session.realm .. "Subscription" .. subscr .. "Sessions") == 0 then
					redis:srem("wiolaRealm" .. session.realm .. "Subscriptions",subscr)
				end

				-- WAMP SPEC: [UNSUBSCRIBED, UNSUBSCRIBE.Request|id]
				putData(session, { WAMP_MSG_SPEC.UNSUBSCRIBED, dataObj[2] })
			else
				putData(session, { WAMP_MSG_SPEC.ERROR, WAMP_MSG_SPEC.UNSUBSCRIBE, dataObj[2], {}, "wamp.error.no_such_subscription" })
			end
		else
			putData(session, { WAMP_MSG_SPEC.GOODBYE, {}, "wamp.error.system_shutdown" })
		end
	elseif dataObj[1] == WAMP_MSG_SPEC.CALL then
		-- WAMP SPEC: [CALL, Request|id, Options|dict, Procedure|uri]
		-- WAMP SPEC: [CALL, Request|id, Options|dict, Procedure|uri, Arguments|list]
		-- WAMP SPEC: [CALL, Request|id, Options|dict, Procedure|uri, Arguments|list, ArgumentsKw|dict]
		if session.isWampEstablished == 1 then

		else
			putData(session, { WAMP_MSG_SPEC.GOODBYE, {}, "wamp.error.system_shutdown" })
		end
	elseif dataObj[1] == WAMP_MSG_SPEC.REGISTER then   -- WAMP SPEC: [REGISTER, Request|id, Options|dict, Procedure|uri]
		if session.isWampEstablished == 1 then

		else
			putData(session, { WAMP_MSG_SPEC.GOODBYE, {}, "wamp.error.system_shutdown" })
		end
	elseif dataObj[1] == WAMP_MSG_SPEC.UNREGISTER then   -- WAMP SPEC: [UNREGISTER, Request|id, REGISTERED.Registration|id]
		if session.isWampEstablished == 1 then

		else
			putData(session, { WAMP_MSG_SPEC.GOODBYE, {}, "wamp.error.system_shutdown" })
		end
	elseif dataObj[1] == WAMP_MSG_SPEC.YIELD then
		-- WAMP SPEC: [YIELD, INVOCATION.Request|id, Options|dict]
		-- WAMP SPEC: [YIELD, INVOCATION.Request|id, Options|dict, Arguments|list]
		-- WAMP SPEC: [YIELD, INVOCATION.Request|id, Options|dict, Arguments|list, ArgumentsKw|dict]
		if session.isWampEstablished == 1 then

		else
			putData(session, { WAMP_MSG_SPEC.GOODBYE, {}, "wamp.error.system_shutdown" })
		end
	else

	end
end

-- Retrieve data, available for session
function _M.getPendingData(regId)
	return redis:lpop("wiolaSession" .. regId .. "Data")
end

return _M
