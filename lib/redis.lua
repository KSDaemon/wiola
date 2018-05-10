--
-- Project: wiola
-- User: Konstantin Burkalev
-- Date: 02.11.17
--

local _M = {}

local json = require('wiola.serializers.json_serializer')
local redis
local config

--- Format NUMBER for using in strings
local formatNumber = function(n)
    return string.format("%.0f", n)
end

---
--- Return index of obj in array t
---
--- @param t table array table
--- @param obj any object to search
--- @return index of obj or -1 if not found
---------------------------------------------------
local arrayIndexOf = function(t, obj)
    if type(t) == 'table' then
        for i = 1, #t do
            if t[i] == obj then
                return i
            end
        end

        return -1
    else
        error("table.indexOf expects table for first argument, " .. type(t) .. " given")
    end
end

---
--- Find URI in pattern based (prefix and wildcard) uri list
---
---
--- @param uriList table URI list (RPCs or Topics)
--- @param uri string Uri to find
--- @param all boolean Return all matches or just first
--- @return table array of matched URIs
---
local findPatternedUri = function(uriList, uri, all)
    local matchedUris = {}

    local comp = function(p1,p2)
        local _, p1c, p2c

        _, p1c = string.gsub(p1, "%.", "")
        _, p2c = string.gsub(p2, "%.", "")

        if p1c > p2c then -- reverse sort
            return true
        else
            return false
        end
    end
    table.sort(uriList, comp)

    -- trying to find prefix matched uri
    for _, value in ipairs(uriList) do
        if string.match(uri, "^" .. string.gsub(value, "%.", "%%.") .. "%.") then
            if all then
                table.insert(matchedUris, value)
            else
                return { value }
            end
        end
    end

    local compWldCrd
    compWldCrd = function(p1,p2)
        local _, p1c, p2c, p1v, p2v, p1dots, p2dots, p1l, p2l

        p1l = string.len(p1)
        p2l = string.len(p2)

        if p1l == 0 and p2l > 0 then
            return false
        elseif p2l == 0 and p1l > 0 then
            return true
        elseif p1l == 0 and p2l == 0 then
            return true
        end

        p1dots = string.find(p1, "..", 1, true) or p1l
        p2dots = string.find(p2, "..", 1, true) or p2l
        p1v = string.sub(p1, 1, p1dots)
        p2v = string.sub(p2, 1, p2dots)
        _, p1c = string.gsub(p1v, "%.", "")
        _, p2c = string.gsub(p2v, "%.", "")

        if p1c > p2c then -- reverse sort
            return true
        elseif p1c < p2c then
            return false
        else
            return compWldCrd(string.sub(p1, p1dots+2), string.sub(p2, p2dots+2))
        end
    end
    table.sort(uriList, compWldCrd)

    -- trying to find wildcard matched uri
    for _, value in ipairs(uriList) do
        local replUri, c = string.gsub(value, "%.%.", ".[0-9a-zA-Z_]+.")

        if c ~= nil then    -- it's wildcard uri
            local re = "^" .. string.gsub(replUri, "%.", "%%.") .. "$"

            if string.match(uri, re) then
                if all then
                    table.insert(matchedUris, value)
                else
                    return { value }
                end
            end
        end
    end

    return matchedUris
end

---
--- Initialize store connection
---
--- @param cfg table store configuration
--- @return boolean, string is Ok flag, error description
---
function _M:init(cfg)
    local redisOk, redisErr

    local redisLib = require "resty.redis"
    redis = redisLib:new()
    config = cfg

    if config.storeConfig.port == nil then
        redisOk, redisErr = redis:connect(config.storeConfig.host)
    else
        redisOk, redisErr = redis:connect(config.storeConfig.host, config.storeConfig.port)
    end

    if redisOk and config.storeConfig.db ~= nil then
        redis:select(config.storeConfig.db)
    end

    return redisOk, redisErr
end

---
--- Generate unique Id
---
--- @return number unique Id
---
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

---
--- Add new session Id to active list
---
--- @param regId number session registration Id
--- @param session table Session information
---
function _M:addSession(regId, session)
    session.sessId = formatNumber(session.sessId)
    redis:sadd("wiolaIds", formatNumber(regId))
    redis:hmset("wiSes" .. formatNumber(regId), session)
end

---
--- Get session info
---
--- @param regId number session registration Id
--- @return table session object or nil
---
function _M:getSession(regId)
    local sessArr = redis:hgetall("wiSes" .. formatNumber(regId))
    if #sessArr > 0 then
        local session = redis:array_to_hash(sessArr)
        session.isWampEstablished = tonumber(session.isWampEstablished)
        session.sessId = tonumber(session.sessId)
        if session.wampFeatures then
            session.wampFeatures = json.decode(session.wampFeatures)

        end
        if session.authInfo then
            session.authInfo = json.decode(session.authInfo)
        end

        return session
    else
        return nil
    end
end

---
--- Change session info
---
--- @param regId number session registration Id
--- @param session table Session information
---
function _M:changeSession(regId, session)
    session.isWampEstablished = formatNumber(session.isWampEstablished)
    session.sessId = formatNumber(session.sessId)
    session.wampFeatures = json.encode(session.wampFeatures)
    if session.authInfo then
        session.authInfo = json.encode(session.authInfo)
    end
    redis:hmset("wiSes" .. formatNumber(regId), session)
end

---
--- Remove session data from runtime store
---
--- @param regId number session registration Id
---
function _M:removeSession(regId)
    local regIdStr = formatNumber(regId)

    local session = redis:array_to_hash(redis:hgetall("wiSes" .. regIdStr))
    session.realm = session.realm or ""

    local subscriptions = redis:array_to_hash(redis:hgetall("wiRealm" .. session.realm .. "Subs"))

    for k, v in pairs(subscriptions) do
        redis:srem("wiRealm" .. session.realm .. "Sub" .. k .. "Sessions", regIdStr)
        redis:del("wiRealm" .. session.realm .. "Sub" .. k .. "Session" .. regIdStr)
        if redis:scard("wiRealm" .. session.realm .. "Sub" .. k .. "Sessions") == 0 then
            redis:del("wiRealm" .. session.realm .. "Sub" .. k .. "Sessions")
            redis:hdel("wiRealm" .. session.realm .. "Subs",k)
            redis:hdel("wiRealm" .. session.realm .. "RevSubs",v)
        end
    end

    local rpcs = redis:array_to_hash(redis:hgetall("wiSes" .. regIdStr .. "RPCs"))

    for k, _ in pairs(rpcs) do
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

---
--- Get session count in realm
---
--- @param realm string realm to count sessions
--- @param authroles table optional authroles list
--- @return number, table session count, session Ids array
---
function _M:getSessionCount(realm, authroles)
    local count = 0
    local sessionsIdList = {}
    local allSessions = redis:smembers("wiRealm" .. realm .. "Sessions")

    if type(authroles) == 'table' and #authroles > 0 then

        for _, sessId in ipairs(allSessions) do
            local sessionInfo = self:getSession(sessId)

            if sessionInfo.authInfo and arrayIndexOf(authroles, sessionInfo.authInfo.authrole) > 0 then
                count = count + 1
                table.insert(sessionsIdList, sessId)
            end
        end
    else
        count = redis:scard("wiRealm" .. realm .. "Sessions")
        sessionsIdList = allSessions
    end

    return count, sessionsIdList
end

---
--- Prepare data for sending to client
---
--- @param session table Session information
--- @param data table data for client
---
function _M:putData(session, data)
    redis:rpush("wiSes" .. formatNumber(session.sessId) .. "Data", data)
end

---
--- Retrieve data, available for session
---
--- @param regId number session registration Id
--- @param last boolean return from the end of a queue
--- @return any client data
---
function _M:getPendingData(regId, last)
    if last == true then
        return redis:rpop("wiSes" .. formatNumber(regId) .. "Data")
    else
        return redis:lpop("wiSes" .. formatNumber(regId) .. "Data")
    end
end

---
--- Set connection handler flags for session
---
--- @param regId number session registration Id
--- @param flags table flags data
---
function _M:setHandlerFlags(regId, flags)
    return redis:hmset("wiSes" .. formatNumber(regId) .. "HandlerFlags", flags)
end

---
--- Retrieve connection handler flags, set up for session
---
--- @param regId number session registration Id
--- @return table flags data
---
function _M:getHandlerFlags(regId)
    local flarr = redis:hgetall("wiSes" .. formatNumber(regId) .. "HandlerFlags")
    if #flarr > 0 then
        local fl = redis:array_to_hash(flarr)

        return fl
    else
        return nil
    end
end

---
--- Get Challenge info
---
--- @param regId number session registration Id
--- @return table challenge info object
---
function _M:getChallenge(regId)
    local challenge = redis:array_to_hash(redis:hgetall("wiSes" .. formatNumber(regId) .. "Challenge"))
    challenge.session = tonumber(challenge.session)
    return challenge
end

---
--- Change Challenge info
---
--- @param regId number session registration Id
--- @param challenge table Challenge information
---
function _M:changeChallenge(regId, challenge)
    if challenge.session then
        challenge.session = formatNumber(challenge.session)
    end
    redis:hmset("wiSes" .. formatNumber(regId) .. "Challenge", challenge)
end

---
--- Remove Challenge data from runtime store
---
--- @param regId number session registration Id
---
function _M:removeChallenge(regId)
    redis:del("wiSes" .. formatNumber(regId) .. "Challenge")
end

---
--- Add session to realm (creating one if needed)
---
--- @param regId number session registration Id
--- @param realm string session realm
---
function _M:addSessionToRealm(regId, realm)

    if redis:sismember("wiolaRealms", realm) == 0 then
        redis:sadd("wiolaRealms", realm)
        self:registerMetaRpc(realm)
    end
    redis:sadd("wiRealm" .. realm .. "Sessions", formatNumber(regId))
end

---
--- Get subscription id
---
--- @param realm string session realm
--- @param uri string subscription uri
--- @return number subscription Id
---
function _M:getSubscriptionId(realm, uri)
    return tonumber(redis:hget("wiRealm" .. realm .. "Subs", uri))
end

---
--- Subscribe session to topic (also create topic if it doesn't exist)
---
--- @param realm string session realm
--- @param uri string subscription uri
--- @param options table subscription options
--- @param regId number session registration Id
---
function _M:subscribeSession(realm, uri, options, regId)
    local subscriptionIdStr = redis:hget("wiRealm" .. realm .. "Subs", uri)
    local subscriptionId = tonumber(subscriptionIdStr)
    local isNewSubscription = false
    local regIdStr = formatNumber(regId)

    if not subscriptionId then
        subscriptionId = self:getRegId()
        isNewSubscription = true
        subscriptionIdStr = formatNumber(subscriptionId)
        redis:hset("wiRealm" .. realm .. "Subs", uri, subscriptionIdStr)
        redis:hset("wiRealm" .. realm .. "RevSubs", subscriptionIdStr, uri)
        redis:hset("wiRealm" .. realm .. "Sub" .. uri, "exact", 0, "prefix", 0, "wildcard", 0)
    end

    redis:hmset("wiRealm" .. realm .. "Sub" .. uri .. "Session" .. regIdStr,
        "subscriptionId", subscriptionIdStr,
        "matchPolicy", options.match or "exact")
    redis:sadd("wiRealm" .. realm .. "Sub" .. uri .. "Sessions", regIdStr)

    return subscriptionId, isNewSubscription
end

---
--- Unsubscribe session from topic (also remove topic if there is no more subscribers)
---
--- @param realm string session realm
--- @param subscId number subscription Id
--- @param regId number session registration Id
---
--- @return boolean, boolean was session unsubscribed from topic, was topic removed
---
function _M:unsubscribeSession(realm, subscId, regId)
    local subscIdStr = formatNumber(subscId)
    local regIdStr = formatNumber(regId)
    local subscr = redis:hget("wiRealm" .. realm .. "RevSubs", subscIdStr)
    local isSesSubscrbd = redis:sismember("wiRealm" .. realm .. "Sub" .. subscr .. "Sessions", regIdStr)
    local wasTopicRemoved = false

    redis:srem("wiRealm" .. realm .. "Sub" .. subscr .. "Sessions", regIdStr)
    redis:del("wiRealm" .. realm .. "Sub" .. subscr .. "Session" .. regIdStr)
    if redis:scard("wiRealm" .. realm .. "Sub" .. subscr .. "Sessions") == 0 then
        redis:del("wiRealm" .. realm .. "Sub" .. subscr .. "Sessions")
        redis:hdel("wiRealm" .. realm .. "Subs", subscr)
        redis:hdel("wiRealm" .. realm .. "RevSubs", subscIdStr)
        redis:del("wiRealm" .. realm .. "Sub" .. subscr)
        wasTopicRemoved = true
    end

    return isSesSubscrbd, wasTopicRemoved
end

---
--- Get sessions subscribed to topic
---
--- @param realm string realm
--- @param subscId number subscription Id
--- @return table array of session Ids subscribed to subscription
---
function _M:getTopicSessionsBySubId(realm, subscId)
    local uri = redis:hget("wiRealm" .. realm .. "RevSubs", formatNumber(subscId))
    if uri ~= ngx.null then
        return redis:smembers("wiRealm" .. realm .. "Sub" .. uri .. "Sessions")
    else
        return nil
    end
end

---
--- Get count of sessions subscribed to topic
---
--- @param realm string realm
--- @param subscId number subscription Id
--- @return table array of session Ids subscribed to subscription
---
function _M:getTopicSessionsCountBySubId(realm, subscId)
    local uri = redis:hget("wiRealm" .. realm .. "RevSubs", formatNumber(subscId))
    if uri ~= ngx.null then
        return redis:scard("wiRealm" .. realm .. "Sub" .. uri .. "Sessions")
    else
        return nil
    end
end

---
--- Get sessions subscribed to topic
---
--- @param realm string realm
--- @param uri string subscription uri
--- @return table array of session Ids subscribed to topic
---
function _M:getTopicSessions(realm, uri)
    return redis:smembers("wiRealm" .. realm .. "Sub" .. uri .. "Sessions")
end

---
--- Get sessions to deliver event
---
--- @param realm string realm
--- @param uri string subscription uri
--- @param regId number session registration Id
--- @param options table advanced profile options
--- @return table array of session Ids to deliver event
---
function _M:getEventRecipients(realm, uri, regId, options)

    local regIdStr = formatNumber(regId)
    local recipients = {}
    local details = {}

    local exactSubsIdStr = redis:hget("wiRealm" .. realm .. "Subs", uri)
    local exactSubsId = tonumber(exactSubsIdStr)

    if options.disclose_me ~= nil and options.disclose_me == true then
        details.publisher = regId
    end

    if options.trustlevel ~= nil then
        details.trustlevel = options.trustlevel
    end

    if type(exactSubsId) == "number" and exactSubsId > 0 then

        -- we need to find sessions with exact subscription
        local ss = redis:smembers("wiRealm" .. realm .. "Sub" .. uri .. "Sessions")
        local exactSessions = {}

        for _, sesValue in ipairs(ss) do
            local matchPolicy = redis:hget("wiRealm" .. realm .. "Sub" .. uri .. "Session" .. sesValue,
                    "matchPolicy")
            if matchPolicy == "exact" then
                table.insert(exactSessions, sesValue)
            end
        end

        if #exactSessions > 0 then

            table.insert(recipients, {
                subId = exactSubsId,
                sessions = self:filterEventRecipients(regIdStr, options, exactSessions),
                details = details
            })
        end
    end

    -- Now lets find all patternBased subscriptions and their sessions
    local allSubs = redis:hkeys("wiRealm" .. realm .. "Subs")
    local matchedUris = findPatternedUri(allSubs, uri)

    details.topic = uri

    -- now we need to find sessions within matched Subs with pattern based subscription
    for _, uriValue in ipairs(matchedUris) do
        local ss = redis:smembers("wiRealm" .. realm .. "Sub" .. uriValue .. "Sessions")
        local patternSessions = {}

        for _, sesValue in ipairs(ss) do
            local matchPolicy = redis:hget("wiRealm" .. realm .. "Sub" .. uriValue .. "Session" .. sesValue,
                    "matchPolicy")
            if matchPolicy ~= "exact" then
                table.insert(patternSessions, sesValue)
            end
        end

        if #patternSessions > 0 then

            table.insert(recipients, {
                subId = tonumber(redis:hget("wiRealm" .. realm .. "Subs", uriValue)),
                sessions = self:filterEventRecipients(regIdStr, options, patternSessions),
                details = details
            })
        end
    end

    return recipients
end

---
--- Filter subscribers in subscription for event
---
--- @param regIdStr string session registration Id (as string)
--- @param options table advanced profile options
--- @param sessionsIdList table subscribers sessions Id list
--- @return table array of session Ids to deliver event
---
function _M:filterEventRecipients(regIdStr, options, sessionsIdList)
    local recipients

    local tmpK = "wiSes" .. regIdStr .. "TmpSetK"
    local tmpL = "wiSes" .. regIdStr .. "TmpSetL"

    for _, v in ipairs(sessionsIdList) do
        redis:sadd(tmpK, formatNumber(v))
    end

    if options.eligible then -- There is eligible list
        for _, v in ipairs(options.eligible) do
            redis:sadd(tmpL, formatNumber(v))
        end

        redis:sinterstore(tmpK, tmpK, tmpL)
        redis:del(tmpL)
    end

    if options.eligible_authid then -- There is eligible authid list

        for _, v in ipairs(redis:smembers(tmpK)) do
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

        for _, v in ipairs(redis:smembers(tmpK)) do
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
        for _, v in ipairs(options.exclude) do
            redis:sadd(tmpL, formatNumber(v))
        end

        redis:sdiffstore(tmpK, tmpK, tmpL)
        redis:del(tmpL)
    end

    if options.exclude_authid then -- There is exclude authid list

        for _, v in ipairs(redis:smembers(tmpK)) do
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

        for _, v in ipairs(redis:smembers(tmpK)) do
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
        redis:sadd(tmpL, regIdStr)
        redis:sdiffstore(tmpK, tmpK, tmpL)
        redis:del(tmpL)
    end

    recipients = redis:smembers(tmpK)
    redis:del(tmpK)

    return recipients
end

---
--- Get subscriptions ids list
---
--- @param realm string realm
--- @return table array of subscriptions Ids
---
function _M:getSubscriptions(realm)
    local subsIds = { exact = {}, prefix = {}, wildcard = {} }
    -- TODO Make count of prefix/wildcard subscriptions
    local allSubs = redis:array_to_hash(redis:hgetall("wiRealm" .. realm .. "Subs"))

    --for k, v in pairs(allSubs) do
    --
    --end

    return subsIds
end

---
--- Get registered RPC info (if exists)
---
--- @param realm string realm
--- @param uri string RPC registration uri
--- @return table RPC object
---
function _M:getRPC(realm, uri)
    local rpc = redis:hgetall("wiRealm" .. realm .. "RPC" .. uri)

    if #rpc < 2 then -- no exactly matched rpc uri found
        local allRPCs = redis:smembers("wiRealm" .. realm .. "RPCs")
        local patternRPCs = {}

        for _, value in ipairs(allRPCs) do
            local rp = redis:hget("wiRealm" .. realm .. "RPC" .. value, "matchPolicy")
            if rp ~= ngx.null and rp ~= "exact" then
                table.insert(patternRPCs, value)
            end
        end
        local matchedUri = findPatternedUri(patternRPCs, uri, false)[1]
        if matchedUri then
            rpc = redis:array_to_hash(redis:hgetall("wiRealm" .. realm .. "RPC" .. matchedUri))
            rpc.options = { procedure = uri }
        else
            return nil
        end
    else
        rpc = redis:array_to_hash(rpc)
    end

    rpc.calleeSesId = tonumber(rpc.calleeSesId)
    rpc.registrationId = tonumber(rpc.registrationId)
    return rpc
end

---
--- Register session RPC
---
--- @param realm string realm
--- @param uri string RPC registration uri
--- @param options table registration options
--- @param regId number session registration Id
--- @return number RPC registration Id
---
function _M:registerSessionRPC(realm, uri, options, regId)
    local registrationId, registrationIdStr
    local regIdStr = formatNumber(regId)

    if redis:sismember("wiRealm" .. realm .. "RPCs", uri) ~= 1 then
        registrationId = self:getRegId()
        registrationIdStr = formatNumber(registrationId)

        redis:sadd("wiRealm" .. realm .. "RPCs", uri)
        redis:hmset("wiRealm" .. realm .. "RPC" .. uri,
            "calleeSesId", regIdStr,
            "registrationId", registrationIdStr,
            "matchPolicy", options.match or "exact")

        if options.disclose_caller ~= nil and options.disclose_caller == true then
            redis:hmset("wiRPC" .. uri, "disclose_caller", true)
        end

        redis:hset("wiSes" .. regIdStr .. "RPCs", uri, registrationIdStr)
        redis:hset("wiSes" .. regIdStr .. "RevRPCs", registrationIdStr, uri)
    end

    return registrationId
end

---
--- Register Meta API RPCs, which are defined in config
---
--- @param realm string realm
---
function _M:registerMetaRpc(realm)

    local uris = {}

    if config.metaAPI.session == true then
        table.insert(uris, 'wamp.session.count')
        table.insert(uris, 'wamp.session.list')
        table.insert(uris, 'wamp.session.get')
    end

    if config.metaAPI.subscription == true then
        table.insert(uris, 'wamp.subscription.list')
        table.insert(uris, 'wamp.subscription.lookup')
        table.insert(uris, 'wamp.subscription.match')
        table.insert(uris, 'wamp.subscription.get')
        table.insert(uris, 'wamp.subscription.list_subscribers')
        table.insert(uris, 'wamp.subscription.count_subscribers')
    end

    if config.metaAPI.registration == true then
        table.insert(uris, 'wamp.registration.list')
        table.insert(uris, 'wamp.registration.lookup')
        table.insert(uris, 'wamp.registration.match')
        table.insert(uris, 'wamp.registration.get')
        table.insert(uris, 'wamp.registration.list_callees')
        table.insert(uris, 'wamp.registration.count_callees')
    end

    local registrationId, registrationIdStr
    for _, uri in ipairs(uris) do

        if redis:sismember("wiRealm" .. realm .. "RPCs", uri) ~= 1 then
            registrationId = self:getRegId()
            registrationIdStr = formatNumber(registrationId)

            redis:sadd("wiRealm" .. realm .. "RPCs", uri)
            redis:hmset("wiRealm" .. realm .. "RPC" .. uri,
                "calleeSesId", "0",
                "registrationId", registrationIdStr)
        end

    end
end

---
--- Unregister session RPC
---
--- @param realm string realm
--- @param registrationId number RPC registration Id
--- @param regId number session registration Id
--- @return table RPC object
---
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

---
--- Get invocation info
---
--- @param invocReqId number invocation request Id
--- @return table Invocation object
---
function _M:getInvocation(invocReqId)
    local invoc = redis:array_to_hash(redis:hgetall("wiInvoc" .. formatNumber(invocReqId)))
    invoc.CallReqId = tonumber(invoc.CallReqId)
    invoc.CallReqId = tonumber(invoc.CallReqId)
    return invoc
end

---
--- Remove invocation
---
--- @param invocReqId number invocation request Id
---
function _M:removeInvocation(invocReqId)
    redis:del("wiInvoc" .. formatNumber(invocReqId))
end

---
--- Get call info
---
--- @param callReqId number call request Id
--- @return table Call object
---
function _M:getCall(callReqId)
    local call = redis:array_to_hash(redis:hgetall("wiCall" .. formatNumber(callReqId)))
    call.calleeSesId = tonumber(call.calleeSesId)
    call.wiInvocId = tonumber(call.wiInvocId)
    return call
end

---
--- Remove call
---
--- @param callReqId number call request Id
---
function _M:removeCall(callReqId)
    redis:del("wiCall" .. formatNumber(callReqId))
end

---
--- Add RPC Call & invocation
---
--- @param callReqId number call request Id
--- @param callerSessId number caller session registration Id
--- @param invocReqId number invocation request Id
--- @param calleeSessId number callee session registration Id
---
function _M:addCallInvocation(callReqId, callerSessId, invocReqId, calleeSessId)
    local callReqIdStr = formatNumber(callReqId)
    local callerSessIdStr = formatNumber(callerSessId)
    local invocReqIdStr = formatNumber(invocReqId)
    local calleeSessIdStr = formatNumber(calleeSessId)

    redis:hmset("wiCall" .. callReqIdStr,
        "callerSesId", callerSessIdStr,
        "calleeSesId", calleeSessIdStr,
        "wiInvocId", invocReqIdStr)
    redis:hmset("wiInvoc" .. invocReqIdStr,
        "CallReqId", callReqIdStr,
        "callerSesId", callerSessIdStr)
end

return _M
