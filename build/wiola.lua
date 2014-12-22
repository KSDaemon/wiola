--
-- Project: wiola
-- User: Konstantin Burkalev
-- Date: 16.03.14
--

local _M = {
	_VERSION = '0.3.2',
}

_M.__index = _M

setmetatable(_M, {
	__call = function (cls, ...)
		return cls.new(...)
	end })

local wamp_features = {
	agent = "wiola/Lua v0.3.2",
	roles = {
		broker = {
			features = {
				subscriber_blackwhite_listing = true,
				publisher_exclusion = true,
				publisher_identification = true
			}
		},
		dealer = {
			features = {
				callee_blackwhite_listing = true,
				caller_exclusion = true,
				caller_identification = true
			}
		}
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

--
-- Create a new instance
--
-- returns wiola instance
--
function _M.new()
	local self = setmetatable({}, _M)
	return self
end

-- Generate unique Id
function _M:_getRegId()
	local regId
	local time = self.redis:time()

--	math.randomseed( os.time() ) -- Precision - only seconds, which is not acceptable
	math.randomseed( time[1] * 1000000 + time[2] )

	repeat
--		regId = math.random(9007199254740992)
		regId = math.random(100000000000000)
	until self.redis:sismember("wiolaIds", regId)

	return regId
end

-- Validate uri for WAMP requirements
function _M:_validateURI(uri)
	local m, err = ngx.re.match(uri, "^([0-9a-z_]{2,}\\.)*([0-9a-z_]{2,})$")
	if not m or string.find(uri, 'wamp') == 1 then
		return false
	else
		return true
	end
end

--
-- Configure Redis connection
--
-- host - redis host or unix socket
-- port - redis port in case of network use or nil
-- db   - redis database to select
--
-- returns connection flag, error description
--
function _M:setupRedis(host, port, db)
	local redisOk, redisErr

	local redisLib = require "resty.redis"
	self.redis = redisLib:new()

	if port == nil then
		redisOk, redisErr = self.redis:connect(host)
	else
		redisOk, redisErr = self.redis:connect(host, port)
	end

	if redisOk and db ~= nil then
		self.redis:select(db)
	end

	return redisOk, redisErr
end

--
-- Add connection to wiola
--
-- sid - nginx session connection ID
-- wampProto - chosen WAMP protocol
--
-- returns WAMP session registration ID, connection data type
--
function _M:addConnection(sid, wampProto)
	local regId = self:_getRegId()
	local wProto, dataType

	self.redis:sadd("wiolaIds",regId)

	if wampProto == nil or wampProto == "" then
		wampProto = 'wamp.2.json'   -- Setting default protocol for encoding/decodig use
	end

	if wampProto == 'wamp.2.msgpack' then
		dataType = 'binary'
	else
		dataType = 'text'
	end

	self.redis:hmset("wiSes" .. regId,
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

--
-- Remove connection from wiola
--
-- regId - WAMP session registration ID
--
function _M:removeConnection(regId)
	local session = self.redis:array_to_hash(self.redis:hgetall("wiSes" .. regId))

	local subscriptions = self.redis:array_to_hash(self.redis:hgetall("wiSes" .. regId .. "Subs"))

	for k, v in pairs(subscriptions) do
		self.redis:srem("wiRealm" .. session.realm .. "Sub" .. k .. "Sessions", regId)
		if self.redis:scard("wiRealm" .. session.realm .. "Sub" .. k .. "Sessions") == 0 then
			self.redis:srem("wiRealm" .. session.realm .. "Subs",k)
		end
	end

	self.redis:del("wiSes" .. regId .. "Subs")
	self.redis:del("wiSes" .. regId .. "RevSubs")

	local rpcs = self.redis:array_to_hash(self.redis:hgetall("wiSes" .. regId .. "RPCs"))

	for k, v in pairs(rpcs) do
		self.redis:srem("wiRealm" .. session.realm .. "RPCs",k)
		self.redis:del("wiRPC" .. k)
	end

	self.redis:del("wiSes" .. regId .. "RPCs")
	self.redis:del("wiSes" .. regId .. "RevRPCs")

	self.redis:srem("wiRealm" .. session.realm .. "Sessions", regId)
	self.redis:srem("wiolaRealms",session.realm)

	self.redis:del("wiSes" .. regId .. "Data")
	self.redis:del("wiSes" .. regId)
	self.redis:srem("wiolaIds",regId)
end

-- Prepare data for sending to client
function _M:_putData(session, data)
	local dataObj

	if session.wamp_protocol == 'wamp.2.msgpack' then
		local mp = require 'MessagePack'
		dataObj = mp.pack(data)
	else --if session.wamp_protocol == 'wamp.2.json'
		local cjson = require "cjson"
		dataObj = cjson.encode(data)
	end

	self.redis:rpush("wiSes" .. session.sessId .. "Data", dataObj)
end

-- Publish event to sessions
function _M:_publishEvent(sessIds, topic, pubId, details, args, argsKW)
	-- WAMP SPEC: [EVENT, SUBSCRIBED.Subscription|id, PUBLISHED.Publication|id, Details|dict]
	-- WAMP SPEC: [EVENT, SUBSCRIBED.Subscription|id, PUBLISHED.Publication|id, Details|dict, PUBLISH.Arguments|list]
	-- WAMP SPEC: [EVENT, SUBSCRIBED.Subscription|id, PUBLISHED.Publication|id, Details|dict, PUBLISH.Arguments|list, PUBLISH.ArgumentKw|dict]
	for k, v in ipairs(sessIds) do
		local session = self.redis:array_to_hash(self.redis:hgetall("wiSes" .. v))
		local subId = tonumber(self.redis:hget("wiSes" .. v .. "Subs", topic))

		if not args and not argsKW then
			self:_putData(session, { WAMP_MSG_SPEC.EVENT, subId, pubId, details })
		elseif args and not argsKW then
			self:_putData(session, { WAMP_MSG_SPEC.EVENT, subId, pubId, details, args })
		else
			self:_putData(session, { WAMP_MSG_SPEC.EVENT, subId, pubId, details, args, argsKW })
		end
	end
end

--
-- Receive data from client
--
-- regId - WAMP session registration ID
-- data - data, received through websocket
--
function _M:receiveData(regId, data)
	local session = self.redis:array_to_hash(self.redis:hgetall("wiSes" .. regId))
	session.isWampEstablished = tonumber(session.isWampEstablished)
	local cjson = require "cjson"
	local dataObj

	if session.wamp_protocol == 'wamp.2.msgpack' then
		local mp = require 'MessagePack'
		dataObj = mp.unpack(data)
	else --if session.wamp_protocol == 'wamp.2.json'
		dataObj = cjson.decode(data)
	end

	-- Analyze WAMP message ID received
	if dataObj[1] == WAMP_MSG_SPEC.HELLO then   -- WAMP SPEC: [HELLO, Realm|uri, Details|dict]
		if session.isWampEstablished == 1 then
			-- Protocol error: received second hello message - aborting
			-- WAMP SPEC: [GOODBYE, Details|dict, Reason|uri]
			self:_putData(session, { WAMP_MSG_SPEC.GOODBYE, {}, "wamp.error.system_shutdown" })
		else
			local realm = dataObj[2]
			if self:_validateURI(realm) then
				session.isWampEstablished = 1
				session.realm = realm
				session.wampFeatures = cjson.encode(dataObj[3])
				self.redis:hmset("wiSes" .. regId, session)

				if self.redis:sismember("wiolaRealms",realm) == 0 then
					self.redis:sadd("wiolaRealms",realm)
				end

				self.redis:sadd("wiRealm" .. realm .. "Sessions", regId)

				-- WAMP SPEC: [WELCOME, Session|id, Details|dict]
				self:_putData(session, { WAMP_MSG_SPEC.WELCOME, regId, wamp_features })
			else
				-- WAMP SPEC: [ABORT, Details|dict, Reason|uri]
				self:_putData(session, { WAMP_MSG_SPEC.ABORT, {}, "wamp.error.invalid_uri" })
			end
		end
	elseif dataObj[1] == WAMP_MSG_SPEC.ABORT then   -- WAMP SPEC: [ABORT, Details|dict, Reason|uri]
		-- No response is expected
	elseif dataObj[1] == WAMP_MSG_SPEC.GOODBYE then   -- WAMP SPEC: [GOODBYE, Details|dict, Reason|uri]
		if session.isWampEstablished == 1 then
			self:_putData(session, { WAMP_MSG_SPEC.GOODBYE, {}, "wamp.error.goodbye_and_out" })
		else
			self:_putData(session, { WAMP_MSG_SPEC.GOODBYE, {}, "wamp.error.system_shutdown" })
		end
	elseif dataObj[1] == WAMP_MSG_SPEC.ERROR then
		-- WAMP SPEC: [ERROR, REQUEST.Type|int, REQUEST.Request|id, Details|dict, Error|uri]
		-- WAMP SPEC: [ERROR, REQUEST.Type|int, REQUEST.Request|id, Details|dict, Error|uri, Arguments|list]
		-- WAMP SPEC: [ERROR, REQUEST.Type|int, REQUEST.Request|id, Details|dict, Error|uri, Arguments|list, ArgumentsKw|dict]
		if session.isWampEstablished == 1 then
			if dataObj[2] == WAMP_MSG_SPEC.INVOCATION then
				-- WAMP SPEC: [ERROR, INVOCATION, INVOCATION.Request|id, Details|dict, Error|uri]
				-- WAMP SPEC: [ERROR, INVOCATION, INVOCATION.Request|id, Details|dict, Error|uri, Arguments|list]
				-- WAMP SPEC: [ERROR, INVOCATION, INVOCATION.Request|id, Details|dict, Error|uri, Arguments|list, ArgumentsKw|dict]

				local invoc = self.redis:array_to_hash(self.redis:hgetall("wiInvoc" .. dataObj[3]))
				local callerSess = self.redis:array_to_hash(self.redis:hgetall("wiSes" .. invoc.callerSesId))

				if #dataObj == 6 then
					-- WAMP SPEC: [ERROR, CALL, CALL.Request|id, Details|dict, Error|uri, Arguments|list]
					self:_putData(callerSess, { WAMP_MSG_SPEC.ERROR, WAMP_MSG_SPEC.CALL, invoc.CallReqId, {}, dataObj[5], dataObj[6] })
				elseif #dataObj == 7 then
					-- WAMP SPEC: [ERROR, CALL, CALL.Request|id, Details|dict, Error|uri, Arguments|list, ArgumentsKw|dict]
					self:_putData(callerSess, { WAMP_MSG_SPEC.ERROR, WAMP_MSG_SPEC.CALL, invoc.CallReqId, {}, dataObj[5], dataObj[6], dataObj[7] })
				else
					-- WAMP SPEC: [ERROR, CALL, CALL.Request|id, Details|dict, Error|uri]
					self:_putData(callerSess, { WAMP_MSG_SPEC.ERROR, WAMP_MSG_SPEC.CALL, invoc.CallReqId, {}, dataObj[5] })
				end

				self.redis:del("wiInvoc" .. dataObj[3])
--			elseif dataObj[2] == WAMP_MSG_SPEC. then
--
--			else

			end
		else

		end
	elseif dataObj[1] == WAMP_MSG_SPEC.PUBLISH then
		-- WAMP SPEC: [PUBLISH, Request|id, Options|dict, Topic|uri]
		-- WAMP SPEC: [PUBLISH, Request|id, Options|dict, Topic|uri, Arguments|list]
		-- WAMP SPEC: [PUBLISH, Request|id, Options|dict, Topic|uri, Arguments|list, ArgumentsKw|dict]
		if session.isWampEstablished == 1 then
			if self:_validateURI(dataObj[4]) then
				local pubId = self:_getRegId()
				local ss = {}
				local tmpK = "wiSes" .. regId .. "TmpSet"

				if dataObj[3].exclude then  -- There is exclude list
					for k, v in ipairs(dataObj[3].exclude) do
						self.redis:sadd(tmpK, v)
					end

					if dataObj[3].exclude_me == nil or dataObj[3].exclude_me == true then
						self.redis:sadd(tmpK, regId)
					end

					ss = self.redis:sdiff("wiRealm" .. session.realm .. "Sub" .. dataObj[4] .. "Sessions", tmpK)
					self.redis:del(tmpK)
				elseif dataObj[3].eligible then -- There is eligible list
					for k, v in ipairs(dataObj[3].eligible) do
						self.redis:sadd(tmpK, v)
					end

					self.redis:sinterstore("wiSes" .. regId .. "TmpSetInter", "wiRealm" .. session.realm .. "Sub" .. dataObj[4] .. "Sessions", tmpK)

					self.redis:del(tmpK)
					if dataObj[3].exclude_me == nil or dataObj[3].exclude_me == true then
						self.redis:sadd(tmpK, regId)
					end

					ss = self.redis:sdiff("wiSes" .. regId .. "TmpSetInter", tmpK)
					self.redis:del(tmpK)
					self.redis:del("wiSes" .. regId .. "TmpSetInter")
				elseif dataObj[3].exclude_me ~= nil and dataObj[3].exclude_me == false then    -- Do not exclude me
					ss = self.redis:smembers("wiRealm" .. session.realm .. "Sub" .. dataObj[4] .. "Sessions")
				else -- Usual behaviour
					self.redis:sadd(tmpK, regId)
					ss = self.redis:sdiff("wiRealm" .. session.realm .. "Sub" .. dataObj[4] .. "Sessions", tmpK)
					self.redis:del(tmpK)
				end

				local details = {}

				if dataObj[3].disclose_me ~= nil and dataObj[3].disclose_me == true then
					details.publisher = regId
				end

				self:_publishEvent(ss, dataObj[4], pubId, details, dataObj[5], dataObj[6])

				if dataObj[3].acknowledge and dataObj[3].acknowledge == true then
					-- WAMP SPEC: [PUBLISHED, PUBLISH.Request|id, Publication|id]
					self:_putData(session, { WAMP_MSG_SPEC.PUBLISHED, dataObj[2], pubId })
				end
			else
				self:_putData(session, { WAMP_MSG_SPEC.ERROR, WAMP_MSG_SPEC.PUBLISH, dataObj[2], {}, "wamp.error.invalid_uri" })
			end
		else
			self:_putData(session, { WAMP_MSG_SPEC.GOODBYE, {}, "wamp.error.system_shutdown" })
		end
	elseif dataObj[1] == WAMP_MSG_SPEC.SUBSCRIBE then   -- WAMP SPEC: [SUBSCRIBE, Request|id, Options|dict, Topic|uri]
		if session.isWampEstablished == 1 then
			if self:_validateURI(dataObj[4]) then
				self.redis:sadd("wiRealm" .. session.realm .. "Subs", dataObj[4])

				if self.redis:hget("wiSes" .. regId .. "Subs", dataObj[4]) ~= ngx.null then
					self:_putData(session, { WAMP_MSG_SPEC.ERROR, WAMP_MSG_SPEC.SUBSCRIBE, dataObj[2], {}, "wamp.error.already_subscribed" })
				else
					local subscriptionId = self:_getRegId()
					self.redis:hset("wiSes" .. regId .. "Subs", dataObj[4], subscriptionId)
					self.redis:hset("wiSes" .. regId .. "RevSubs", subscriptionId, dataObj[4])
					self.redis:sadd("wiRealm" .. session.realm .. "Sub" .. dataObj[4] .. "Sessions",regId)

					-- WAMP SPEC: [SUBSCRIBED, SUBSCRIBE.Request|id, Subscription|id]
					self:_putData(session, { WAMP_MSG_SPEC.SUBSCRIBED, dataObj[2], subscriptionId })
				end
			else
				self:_putData(session, { WAMP_MSG_SPEC.ERROR, WAMP_MSG_SPEC.SUBSCRIBE, dataObj[2], {}, "wamp.error.invalid_uri" })
			end
		else
			self:_putData(session, { WAMP_MSG_SPEC.GOODBYE, {}, "wamp.error.system_shutdown" })
		end
	elseif dataObj[1] == WAMP_MSG_SPEC.UNSUBSCRIBE then   -- WAMP SPEC: [UNSUBSCRIBE, Request|id, SUBSCRIBED.Subscription|id]
		if session.isWampEstablished == 1 then
			local subscr = self.redis:hget("wiSes" .. regId .. "RevSubs", dataObj[3])
			if subscr ~= ngx.null then
				self.redis:hdel("wiSes" .. regId .. "Subs", subscr)
				self.redis:hdel("wiSes" .. regId .. "RevSubs", dataObj[3])

				self.redis:srem("wiRealm" .. session.realm .. "Sub" .. subscr .. "Sessions", regId)
				if self.redis:scard("wiRealm" .. session.realm .. "Sub" .. subscr .. "Sessions") == 0 then
					self.redis:srem("wiRealm" .. session.realm .. "Subs",subscr)
				end

				-- WAMP SPEC: [UNSUBSCRIBED, UNSUBSCRIBE.Request|id]
				self:_putData(session, { WAMP_MSG_SPEC.UNSUBSCRIBED, dataObj[2] })
			else
				self:_putData(session, { WAMP_MSG_SPEC.ERROR, WAMP_MSG_SPEC.UNSUBSCRIBE, dataObj[2], {}, "wamp.error.no_such_subscription" })
			end
		else
			self:_putData(session, { WAMP_MSG_SPEC.GOODBYE, {}, "wamp.error.system_shutdown" })
		end
	elseif dataObj[1] == WAMP_MSG_SPEC.CALL then
		-- WAMP SPEC: [CALL, Request|id, Options|dict, Procedure|uri]
		-- WAMP SPEC: [CALL, Request|id, Options|dict, Procedure|uri, Arguments|list]
		-- WAMP SPEC: [CALL, Request|id, Options|dict, Procedure|uri, Arguments|list, ArgumentsKw|dict]
		if session.isWampEstablished == 1 then
			if self:_validateURI(dataObj[4]) then
				if self.redis:sismember("wiRealm" .. session.realm .. "RPCs", dataObj[4]) == 0 then
					self:_putData(session, { WAMP_MSG_SPEC.ERROR, WAMP_MSG_SPEC.REGISTER, dataObj[2], {}, "wamp.error.no_such_procedure" })
				else
					local callee = tonumber(self.redis:get("wiRPC" .. dataObj[4]))
					local tmpK = "wiSes" .. regId .. "TmpSet"
					local allOk = false

					if dataObj[3].exclude then  -- There is exclude list
						local flag = false
						for k, v in ipairs(dataObj[3].exclude) do
							if v == callee then
								flag = true
								break
							end
						end

						if flag == false then
							allOk = true
						end
					elseif dataObj[3].eligible then -- There is eligible list
						local flag = false
						for k, v in ipairs(dataObj[3].eligible) do
							if v == callee then
								allOk = true
								break
							end
						end
					elseif dataObj[3].exclude_me == nil or dataObj[3].exclude_me == true then    -- Exclude me by default
						if callee ~= regId then
							allOk = true
						end
					else
						allOk = true
					end

					if allOk == true then

						local details = {}

						if dataObj[3].disclose_me ~= nil and dataObj[3].disclose_me == true then
							details.caller = regId
						end

						local calleeSess = self.redis:array_to_hash(self.redis:hgetall("wiSes" .. callee))
						local rpcRegId = self.redis:hget("wiSes" .. callee .. "RPCs", dataObj[4])
						local invReqId = self:_getRegId()
						self.redis:hmset("wiInvoc" .. invReqId, "CallReqId", dataObj[2], "callerSesId", regId)

						if #dataObj == 5 then
							-- WAMP SPEC: [INVOCATION, Request|id, REGISTERED.Registration|id, Details|dict, CALL.Arguments|list]
							self:_putData(calleeSess, { WAMP_MSG_SPEC.INVOCATION, invReqId, rpcRegId, details, dataObj[5] })
						elseif #dataObj == 6 then
							-- WAMP SPEC: [INVOCATION, Request|id, REGISTERED.Registration|id, Details|dict, CALL.Arguments|list, CALL.ArgumentsKw|dict]
							self:_putData(calleeSess, { WAMP_MSG_SPEC.INVOCATION, invReqId, rpcRegId, details, dataObj[5], dataObj[6] })
						else
							-- WAMP SPEC: [INVOCATION, Request|id, REGISTERED.Registration|id, Details|dict]
							self:_putData(calleeSess, { WAMP_MSG_SPEC.INVOCATION, invReqId, rpcRegId, details })
						end

					else
						-- WAMP SPEC: [ERROR, CALL, CALL.Request|id, Details|dict, Error|uri]
						self:_putData(session, { WAMP_MSG_SPEC.ERROR, WAMP_MSG_SPEC.CALL, dataObj[2], {}, "wamp.error.no_suitable_callee" })
					end
				end
			else
				self:_putData(session, { WAMP_MSG_SPEC.ERROR, WAMP_MSG_SPEC.CALL, dataObj[2], {}, "wamp.error.invalid_uri" })
			end
		else
			self:_putData(session, { WAMP_MSG_SPEC.GOODBYE, {}, "wamp.error.system_shutdown" })
		end
	elseif dataObj[1] == WAMP_MSG_SPEC.REGISTER then   -- WAMP SPEC: [REGISTER, Request|id, Options|dict, Procedure|uri]
		if session.isWampEstablished == 1 then
			if self:_validateURI(dataObj[4]) then
				if self.redis:sismember("wiRealm" .. session.realm .. "RPCs", dataObj[4]) == 1 then
					self:_putData(session, { WAMP_MSG_SPEC.ERROR, WAMP_MSG_SPEC.REGISTER, dataObj[2], {}, "wamp.error.procedure_already_exists" })
				else
					local registrationId = self:_getRegId()

					self.redis:sadd("wiRealm" .. session.realm .. "RPCs", dataObj[4])
					self.redis:set("wiRPC" .. dataObj[4], regId)
					self.redis:hset("wiSes" .. regId .. "RPCs", dataObj[4], registrationId)
					self.redis:hset("wiSes" .. regId .. "RevRPCs", registrationId, dataObj[4])

					-- WAMP SPEC: [REGISTERED, REGISTER.Request|id, Registration|id]
					self:_putData(session, { WAMP_MSG_SPEC.REGISTERED, dataObj[2], registrationId })
				end
			else
				self:_putData(session, { WAMP_MSG_SPEC.ERROR, WAMP_MSG_SPEC.REGISTER, dataObj[2], {}, "wamp.error.invalid_uri" })
			end
		else
			self:_putData(session, { WAMP_MSG_SPEC.GOODBYE, {}, "wamp.error.system_shutdown" })
		end
	elseif dataObj[1] == WAMP_MSG_SPEC.UNREGISTER then   -- WAMP SPEC: [UNREGISTER, Request|id, REGISTERED.Registration|id]
		if session.isWampEstablished == 1 then
			local rpc = self.redis:hget("wiSes" .. regId .. "RevRPCs", dataObj[3])
			if rpc ~= ngx.null then
				self.redis:hdel("wiSes" .. regId .. "RPCs", rpc)
				self.redis:hdel("wiSes" .. regId .. "RevRPCs", dataObj[3])
				self.redis:srem("wiRealm" .. session.realm .. "RPCs",rpc)

				-- WAMP SPEC: [UNREGISTERED, UNREGISTER.Request|id]
				self:_putData(session, { WAMP_MSG_SPEC.UNREGISTERED, dataObj[2] })
			else
				self:_putData(session, { WAMP_MSG_SPEC.ERROR, WAMP_MSG_SPEC.UNREGISTER, dataObj[2], {}, "wamp.error.no_such_registration" })
			end
		else
			self:_putData(session, { WAMP_MSG_SPEC.GOODBYE, {}, "wamp.error.system_shutdown" })
		end
	elseif dataObj[1] == WAMP_MSG_SPEC.YIELD then
		-- WAMP SPEC: [YIELD, INVOCATION.Request|id, Options|dict]
		-- WAMP SPEC: [YIELD, INVOCATION.Request|id, Options|dict, Arguments|list]
		-- WAMP SPEC: [YIELD, INVOCATION.Request|id, Options|dict, Arguments|list, ArgumentsKw|dict]
		if session.isWampEstablished == 1 then
			local invoc = self.redis:array_to_hash(self.redis:hgetall("wiInvoc" .. dataObj[2]))
			local callerSess = self.redis:array_to_hash(self.redis:hgetall("wiSes" .. invoc.callerSesId))

			if #dataObj == 4 then
				-- WAMP SPEC: [RESULT, CALL.Request|id, Details|dict, YIELD.Arguments|list]
				self:_putData(callerSess, { WAMP_MSG_SPEC.RESULT, invoc.CallReqId, {}, dataObj[4] })
			elseif #dataObj == 5 then
				-- WAMP SPEC: [RESULT, CALL.Request|id, Details|dict, YIELD.Arguments|list, YIELD.ArgumentsKw|dict]
				self:_putData(callerSess, { WAMP_MSG_SPEC.RESULT, invoc.CallReqId, {}, dataObj[4], dataObj[5] })
			else
				-- WAMP SPEC: [RESULT, CALL.Request|id, Details|dict]
				self:_putData(callerSess, { WAMP_MSG_SPEC.RESULT, invoc.CallReqId, {} })
			end

			self.redis:del("wiInvoc" .. dataObj[2])
		else
			self:_putData(session, { WAMP_MSG_SPEC.GOODBYE, {}, "wamp.error.system_shutdown" })
		end
	else

	end
end

--
-- Retrieve data, available for session
--
-- regId - WAMP session registration ID
--
-- returns first WAMP message from the session data queue
--
function _M:getPendingData(regId)
	return self.redis:lpop("wiSes" .. regId .. "Data")
end

--
-- Process lightweight publish POST data from client
--
-- sid - nginx session connection ID
-- realm - WAMP Realm to operate in
-- data - data, received through POST
--
function _M:processPostData(sid, realm, data)

	local cjson = require "cjson"
	local dataObj = cjson.decode(data)
	local res
	local httpCode

	if dataObj[1] == WAMP_MSG_SPEC.PUBLISH then
		local regId, dataType = self.addConnection(sid, nil)

		-- Make a session legal :)
		self.redis:hset("wiSes" .. regId, "isWampEstablished", 1)
		self.redis:hset("wiSes" .. regId, "realm", realm)

		self.receiveData(regId, data)

		local cliData, cliErr = self.getPendingData(regId)
		if cliData ~= ngx.null then
			res = cliData
			httpCode = ngx.HTTP_FORBIDDEN
		else
			res = cjson.encode({ result = true, error = nil })
			httpCode = ngx.HTTP_OK
		end

		self.removeConnection(regId)
	else
		res = cjson.encode({ result = false, error = "Message type not supported" })
		httpCode = ngx.HTTP_FORBIDDEN
	end

	return res, httpCode
end

return _M
