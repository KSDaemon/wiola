--
-- Project: wiola
-- User: Konstantin Burkalev
-- Date: 02.11.17
--

local _M = {}

local redis
local config

-- Format NUMBER for using in strings
local formatNumber = function(n)
    return string.format("%.0f", n)
end


--
-- Initialize store connection
--
-- config - store configuration
--
function _M:init(cfg)
    local redisOk, redisErr

    local redisLib = require "resty.redis"
    redis = redisLib:new()
    config = cfg

    if config.port == nil then
        redisOk, redisErr = redis:connect(config.host)
    else
        redisOk, redisErr = redis:connect(config.host, config.port)
    end

    if redisOk and config.db ~= nil then
        redis:select(config.db)
    end

    return redisOk, redisErr
end

--
-- Generate unique Id
--
function _M:getRegId()
    local regId
    local max = 2 ^ 53
    local time = redis:time()

    --    math.randomseed( os.time() ) -- Precision - only seconds, which is not acceptable
    math.randomseed(time[1] * 1000000 + time[2])

    repeat
        regId = math.random(max)
    --        regId = math.random(100000000000000)
    until redis:sismember("wiolaIds", formatNumber(regId))

    return regId
end

--
-- Add new session Id to active list
--
-- regId - session registration Id
-- session - Session information
--
function _M:addSession(regId, session)

    session.sessId = formatNumber(session.sessId)
    redis:sadd("wiolaIds", formatNumber(regId))
    redis:hmset("wiSes" .. formatNumber(regId), session)

end

--
-- Get session info
--
-- regId - session registration Id
--
function _M:getSession(regId)
    local session = redis:array_to_hash(redis:hgetall("wiSes" .. formatNumber(regId)))
    session.isWampEstablished = tonumber(session.isWampEstablished)
    session.sessId = tonumber(session.sessId)
    return session
end

--
-- Change session info
--
-- regId - session registration Id
-- session - Session information
--
function _M:changeSession(regId, session)
    session.isWampEstablished = formatNumber(session.isWampEstablished)
    session.sessId = formatNumber(session.sessId)
    redis:hmset("wiSes" .. formatNumber(regId), session)

end

--
-- Remove session data from runtime store
--
-- regId - session registration Id
--
function _M:removeSession(regId)
    local regIdStr = formatNumber(regId)

    local session = redis:array_to_hash(redis:hgetall("wiSes" .. regIdStr))
    session.realm = session.realm or ""

    local subscriptions = redis:array_to_hash(redis:hgetall("wiRealm" .. session.realm .. "Subs"))

    for k, v in pairs(subscriptions) do
        redis:srem("wiRealm" .. session.realm .. "Sub" .. k .. "Sessions", regIdStr)
        if redis:scard("wiRealm" .. session.realm .. "Sub" .. k .. "Sessions") == 0 then
            redis:del("wiRealm" .. session.realm .. "Sub" .. k .. "Sessions")
            redis:hdel("wiRealm" .. session.realm .. "Subs",k)
            redis:hdel("wiRealm" .. session.realm .. "RevSubs",v)
        end
    end

    local rpcs = redis:array_to_hash(redis:hgetall("wiSes" .. regIdStr .. "RPCs"))

    for k, v in pairs(rpcs) do
        redis:srem("wiRealm" .. session.realm .. "RPCs",k)
        redis:del("wiRealm" .. session.realm .. "RPC" .. k)
    end

    redis:del("wiSes" .. regIdStr .. "RPCs")
    redis:del("wiSes" .. regIdStr .. "RevRPCs")
    redis:del("wiSes" .. regIdStr .. "Challenge")

    redis:srem("wiRealm" .. session.realm .. "Sessions", regIdStr)
    if redis:scard("wiRealm" .. session.realm .. "Sessions") == 0 then
        redis:srem("wiolaRealms",session.realm)
    end

    redis:del("wiSes" .. regIdStr .. "Data")
    redis:del("wiSes" .. regIdStr)
    redis:srem("wiolaIds",regIdStr)
end

-- Prepare data for sending to client
--
-- session - Session information
-- data - data for client
--
function _M:putData(session, data)
    redis:rpush("wiSes" .. formatNumber(session.sessId) .. "Data", data)
end

--
-- Retrieve data, available for session
--
-- regId - session registration Id
--
function _M:getPendingData(regId)
    return redis:lpop("wiSes" .. formatNumber(regId) .. "Data")
end

--
-- Get Challenge info
--
-- regId - session registration Id
--
function _M:getChallenge(regId)
    local challenge = redis:array_to_hash(redis:hgetall("wiSes" .. formatNumber(regId) .. "Challenge"))
    challenge.session = tonumber(challenge.session)
    return challenge
end

--
-- Change Challenge info
--
-- regId - session registration Id
-- challenge - Challenge information
--
function _M:changeChallenge(regId, challenge)
    if challenge.session then
        challenge.session = formatNumber(challenge.session)
    end
    redis:hmset("wiSes" .. formatNumber(regId) .. "Challenge", challenge)
end

--
-- Remove Challenge data from runtime store
--
-- regId - session registration Id
--
function _M:removeChallenge(regId)
    redis:del("wiSes" .. formatNumber(regId) .. "Challenge")
end

--
-- Add session to realm (creating one if needed)
--
-- regId - session registration Id
-- realm - session realm
--
function _M:addSessionToRealm(regId, realm)

    if redis:sismember("wiolaRealms", realm) == 0 then
        ngx.log(ngx.DEBUG, "No realm ", realm, " found. Creating...")
        redis:sadd("wiolaRealms", realm)
    end
    redis:sadd("wiRealm" .. realm .. "Sessions", formatNumber(regId))

end

--
-- Get subscription id
--
-- realm - realm
-- uri - subscription uri
--
function _M:getSubscriptionId(realm, uri)
    return tonumber(redis:hget("wiRealm" .. realm .. "Subs", uri))
end

--
-- Subscribe session to topic (also create topic if it doesn't exist)
--
-- realm - realm
-- uri - subscription uri
-- regId - session registration Id
--
function _M:subscribeSession(realm, uri, regId)
    local subscriptionId = tonumber(redis:hget("wiRealm" .. realm .. "Subs", uri))
    local isNewSubscription = false

    if not subscriptionId then
        subscriptionId = self:getRegId()
        isNewSubscription = true
        local subscriptionIdStr = formatNumber(subscriptionId)
        redis:hset("wiRealm" .. realm .. "Subs", uri, subscriptionIdStr)
        redis:hset("wiRealm" .. realm .. "RevSubs", subscriptionIdStr, uri)
    end

    redis:sadd("wiRealm" .. realm .. "Sub" .. uri .. "Sessions", formatNumber(regId))

    return subscriptionId, isNewSubscription
end

--
-- Unsubscribe session from topic (also remove topic if there is no more subscribers)
--
-- realm - realm
-- subscId - subscription Id
-- regId - session registration Id
--
-- Returns flag was session subscribed to requested topic
--
function _M:unsubscribeSession(realm, subscId, regId)
    local subscIdStr = formatNumber(subscId)
    local regIdStr = formatNumber(regId)
    local subscr = redis:hget("wiRealm" .. realm .. "RevSubs", subscIdStr)
    local isSesSubscrbd = redis:sismember("wiRealm" .. realm .. "Sub" .. subscr .. "Sessions", regIdStr)
    local wasTopicRemoved = false

    redis:srem("wiRealm" .. realm .. "Sub" .. subscr .. "Sessions", regIdStr)
    if redis:scard("wiRealm" .. realm .. "Sub" .. subscr .. "Sessions") == 0 then
        redis:del("wiRealm" .. realm .. "Sub" .. subscr .. "Sessions")
        redis:hdel("wiRealm" .. realm .. "Subs", subscr)
        redis:hdel("wiRealm" .. realm .. "RevSubs", subscIdStr)
        wasTopicRemoved = true
    end

    return isSesSubscrbd, wasTopicRemoved
end

--
-- Get sessions subscribed to topic
--
-- realm - realm
-- uri - subscription uri
--
function _M:getTopicSessions(realm, uri)
    return redis:smembers("wiRealm" .. realm .. "Sub" .. uri .. "Sessions")
end

--
-- Get sessions to deliver event
--
-- realm - realm
-- uri - subscription uri
-- regId - session registration Id
-- options - advanced profile options
--
function _M:getEventRecipients(realm, uri, regId, options)

    local regIdStr = formatNumber(regId)
    local recipients = {}
    local tmpK = "wiSes" .. regIdStr .. "TmpSetK"
    local tmpL = "wiSes" .. regIdStr .. "TmpSetL"

    redis:sdiffstore(tmpK, "wiRealm" .. realm .. "Sub" .. uri .. "Sessions")

    if options.eligible then -- There is eligible list
        ngx.log(ngx.DEBUG, "PUBLISH: There is eligible list")
        for k, v in ipairs(options.eligible) do
            redis:sadd(tmpL, formatNumber(v))
        end

        redis:sinterstore(tmpK, tmpK, tmpL)
        redis:del(tmpL)
    end

    if options.eligible_authid then -- There is eligible authid list
        ngx.log(ngx.DEBUG, "PUBLISH: There is eligible authid list")

        for k, v in ipairs(redis:smembers(tmpK)) do
            local s = redis:array_to_hash(redis:hgetall("wiSes" .. formatNumber(v)))

            for i = 1, #options.eligible_authid do
                if s.wampFeatures.authid == options.eligible_authid[i] then
                    redis:sadd(tmpL, formatNumber(s.sessId))
                end
            end
        end

        redis:sinterstore(tmpK, tmpK, tmpL)
        redis:del(tmpL)
    end

    if options.eligible_authrole then -- There is eligible authrole list
        ngx.log(ngx.DEBUG, "PUBLISH: There is eligible authrole list")

        for k, v in ipairs(redis:smembers(tmpK)) do
            local s = redis:array_to_hash(redis:hgetall("wiSes" .. formatNumber(v)))

            for i = 1, #options.eligible_authrole do
                if s.wampFeatures.authrole == options.eligible_authrole[i] then
                    redis:sadd(tmpL, formatNumber(s.sessId))
                end
            end
        end

        redis:sinterstore(tmpK, tmpK, tmpL)
        redis:del(tmpL)
    end

    if options.exclude then -- There is exclude list
        ngx.log(ngx.DEBUG, "PUBLISH: There is exclude list")
        for k, v in ipairs(options.exclude) do
            redis:sadd(tmpL, formatNumber(v))
        end

        redis:sdiffstore(tmpK, tmpK, tmpL)
        redis:del(tmpL)
    end

    if options.exclude_authid then -- There is exclude authid list
        ngx.log(ngx.DEBUG, "PUBLISH: There is exclude authid list")

        for k, v in ipairs(redis:smembers(tmpK)) do
            local s = redis:array_to_hash(redis:hgetall("wiSes" .. formatNumber(v)))

            for i = 1, #options.exclude_authid do
                if s.wampFeatures.authid == options.exclude_authid[i] then
                    redis:sadd(tmpL, formatNumber(s.sessId))
                end
            end
        end

        redis:sdiffstore(tmpK, tmpK, tmpL)
        redis:del(tmpL)
    end

    if options.exclude_authrole then -- There is exclude authrole list
        ngx.log(ngx.DEBUG, "PUBLISH: There is exclude authrole list")

        for k, v in ipairs(redis:smembers(tmpK)) do
            local s = redis:array_to_hash(redis:hgetall("wiSes" .. formatNumber(v)))

            for i = 1, #options.exclude_authrole do
                if s.wampFeatures.authrole == options.exclude_authrole[i] then
                    redis:sadd(tmpL, formatNumber(s.sessId))
                end
            end
        end

        redis:sdiffstore(tmpK, tmpK, tmpL)
        redis:del(tmpL)
    end

    if options.exclude_me == nil or options.exclude_me == true then
        redis:sadd(tmpL, regId)
        redis:sdiffstore(tmpK, tmpK, tmpL)
        redis:del(tmpL)
    end

    recipients = redis:smembers(tmpK)
    redis:del(tmpK)

    return recipients
end

--
-- Get subscription info
--
-- regId - subscription registration Id
--
function _M:getSubscription(regId)
    local subscription = redis:array_to_hash(redis:hgetall("wiSes" .. formatNumber(regId)))
    subscription.isWampEstablished = tonumber(subscription.isWampEstablished)
    return subscription
end

--
-- Remove subscription data from runtime store
--
-- regId - subscription registration Id
--
function _M:removeSubscription(regId)
    local regIdStr = formatNumber(regId)

    local subscription = redis:array_to_hash(redis:hgetall("wiSes" .. regIdStr))
    subscription.realm = subscription.realm or ""

    local subscriptions = redis:array_to_hash(redis:hgetall("wiRealm" .. subscription.realm .. "Subs"))

    for k, v in pairs(subscriptions) do
        redis:srem("wiRealm" .. subscription.realm .. "Sub" .. k .. "Subscriptions", regIdStr)
        if redis:scard("wiRealm" .. subscription.realm .. "Sub" .. k .. "Subscriptions") == 0 then
            redis:del("wiRealm" .. subscription.realm .. "Sub" .. k .. "Subscriptions")
            redis:hdel("wiRealm" .. subscription.realm .. "Subs",k)
            redis:hdel("wiRealm" .. subscription.realm .. "RevSubs",v)
        end
    end

    local rpcs = redis:array_to_hash(redis:hgetall("wiSes" .. regIdStr .. "RPCs"))

    for k, v in pairs(rpcs) do
        redis:srem("wiRealm" .. subscription.realm .. "RPCs",k)
        redis:del("wiRPC" .. k)
    end

    redis:del("wiSes" .. regIdStr .. "RPCs")
    redis:del("wiSes" .. regIdStr .. "RevRPCs")
    redis:del("wiSes" .. regIdStr .. "Challenge")

    redis:srem("wiRealm" .. subscription.realm .. "Subscriptions", regIdStr)
    if redis:scard("wiRealm" .. subscription.realm .. "Subscriptions") == 0 then
        redis:srem("wiolaRealms",subscription.realm)
    end

    redis:del("wiSes" .. regIdStr .. "Data")
    redis:del("wiSes" .. regIdStr)
    redis:srem("wiolaIds",regIdStr)
end

--
-- Get registered RPC info (if exists)
--
-- realm - realm
-- uri - RPC registration uri
--
function _M:getRPC(realm, uri)
    local rpc = redis:array_to_hash(redis:hgetall("wiRealm" .. realm .. "RPC" .. uri))
    rpc.calleeSesId = tonumber(rpc.calleeSesId)
    rpc.registrationId = tonumber(rpc.registrationId)
    return rpc
end

--
-- Register session RPC
--
-- realm - realm
-- uri - RPC registration uri
-- options - registration options
-- regId - session registration Id
--
function _M:registerSessionRPC(realm, uri, options, regId)
    local registrationId, registrationIdStr
    local regIdStr = formatNumber(regId)

    if redis:sismember("wiRealm" .. realm .. "RPCs", uri) ~= 1 then
        registrationId = self:getRegId()
        registrationIdStr = formatNumber(registrationId)

        redis:sadd("wiRealm" .. realm .. "RPCs", uri)
        redis:hmset("wiRealm" .. realm .. "RPC" .. uri, "calleeSesId", regIdStr, "registrationId", registrationIdStr)

        if options.disclose_caller ~= nil and options.disclose_caller == true then
            redis:hmset("wiRPC" .. uri, "disclose_caller", true)
        end

        redis:hset("wiSes" .. regIdStr .. "RPCs", uri, registrationIdStr)
        redis:hset("wiSes" .. regIdStr .. "RevRPCs", registrationIdStr, uri)
    end

    return registrationId
end

--
-- Unregister session RPC
--
-- realm - realm
-- registrationId - RPC registration Id
-- regId - session registration Id
--
-- Returns flag was session registerd to requested topic
--
function _M:unregisterSessionRPC(realm, registrationId, regId)
    local regIdStr = formatNumber(regId)
    local registrationIdStr = formatNumber(registrationId)

    local rpc = redis:hget("wiSes" .. regIdStr .. "RevRPCs", registrationIdStr)
    if rpc ~= ngx.null then
        redis:hdel("wiSes" .. regIdStr .. "RPCs", rpc)
        redis:hdel("wiSes" .. regIdStr .. "RevRPCs", registrationIdStr)
        redis:del("wiRealm" .. realm .. "RPC" .. rpc)
        redis:srem("wiRealm" .. realm .. "RPCs", rpc)
    end

    return rpc
end

--
-- Get invocation info
--
-- invocReqId - invocation request Id
--
function _M:getInvocation(invocReqId)
    local invoc = redis:array_to_hash(redis:hgetall("wiInvoc" .. formatNumber(invocReqId)))
    invoc.CallReqId = tonumber(invoc.CallReqId)
    invoc.CallReqId = tonumber(invoc.CallReqId)
    return invoc
end

--
-- Remove invocation
--
-- invocReqId - invocation request Id
--
function _M:removeInvocation(invocReqId)
    redis:del("wiInvoc" .. formatNumber(invocReqId))
end

--
-- Get call info
--
-- callReqId - call request Id
--
function _M:getCall(callReqId)
    local call = redis:array_to_hash(redis:hgetall("wiCall" .. formatNumber(callReqId)))
    call.calleeSesId = tonumber(call.calleeSesId)
    call.wiInvocId = tonumber(call.wiInvocId)
    return call
end

--
-- Remove call
--
-- callReqId - call request Id
--
function _M:removeCall(callReqId)
    redis:del("wiCall" .. formatNumber(callReqId))
end

--
-- Add RPC Call & invocation
--
-- callReqId - call request Id
-- callerSessId - caller session registration Id
-- invocReqId - invocation request Id
-- calleeSessId - callee session registration Id
--
function _M:addCallInvocation(callReqId, callerSessId, invocReqId, calleeSessId)
    local callReqIdStr = formatNumber(callReqId)
    local callerSessIdStr = formatNumber(callerSessId)
    local invocReqIdStr = formatNumber(invocReqId)
    local calleeSessIdStr = formatNumber(calleeSessId)

    redis:hmset("wiCall" .. callReqIdStr, "callerSesId", callerSessIdStr, "calleeSesId", calleeSessIdStr, "wiInvocId", invocReqIdStr)
    redis:hmset("wiInvoc" .. invocReqIdStr, "CallReqId", callReqIdStr, "callerSesId", callerSessIdStr)
end

return _M
