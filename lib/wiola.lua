--
-- Project: wiola
-- User: Konstantin Burkalev
-- Date: 16.03.14
--



local _M = {
    _VERSION = '0.8.0',
}

_M.__index = _M

setmetatable(_M, {
    __call = function(cls, ...)
        return cls.new(...)
    end
})

local wamp_features = {
    agent = "wiola/Lua v" .. _M._VERSION,
    roles = {
        broker = {
            features = {
                pattern_based_subscription = true,
                publisher_exclusion = true,
                publisher_identification = true,
                subscriber_blackwhite_listing = true
                -- meta api are exposing if they are configured (see below)
                --session_meta_api = true,
                --subscription_meta_api = true
            }
        },
        dealer = {
            features = {
                call_canceling = true,
                call_timeout = true,
                caller_identification = true,
                pattern_based_registration = true,
                progressive_call_results = true
                -- meta api are exposing if they are configured (see below)
                --session_meta_api = true,
                --registration_meta_api = true
            }
        }
    }
}

local config = require("wiola.config").config()
local serializers = {
    json = require('wiola.serializers.json_serializer'),
    msgpack = require('wiola.serializers.msgpack_serializer')
}
local store = require('wiola.stores.' .. config.store)

-- Add Meta API features announcements if they are configured
if config.metaAPI.session == true then
    wamp_features.roles.broker.features.session_meta_api = true
    wamp_features.roles.dealer.features.session_meta_api = true
end
if config.metaAPI.subscription == true then
    wamp_features.roles.broker.features.subscription_meta_api = true
end
if config.metaAPI.registration == true then
    wamp_features.roles.dealer.features.registration_meta_api = true
end

local WAMP_MSG_SPEC = {
    HELLO = 1,
    WELCOME = 2,
    ABORT = 3,
    CHALLENGE = 4,
    AUTHENTICATE = 5,
    GOODBYE = 6,
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

---
--- Check for a value in table
---
--- @param tab table Source table
--- @param val any Value to search
---
local has = function(tab, val)
    for _, value in ipairs(tab) do
        if value == val then
            return true
        end
    end

    return false
end

---
--- Create a new instance
---
--- @return wiola instance
---
function _M.new()
    local self = setmetatable({}, _M)
    local ok, err = store:init(config)
    if not ok then
        return ok, err
    end

    return self

end

---
--- Generate a random string
---
--- @param length number String length
--- @return string random string
---
function _M:_randomString(length)
    local str = {};
    math.randomseed(math.floor(ngx.now()*1000))

    for _ = 1, length do
        table.insert(str, string.char(math.random(32, 126)))
    end
    return table.concat(str)
end

---
--- Validate uri for WAMP requirements
---
--- @param uri string uri to validate
--- @param patternBased boolean allow wamp pattern based syntax or no
--- @param allowWAMP boolean allow wamp special prefixed uris or no
--- @return boolean is uri valid?
---
function _M:_validateURI(uri, patternBased, allowWAMP)
    local re = "^([0-9a-zA-Z_]+\\.)*([0-9a-zA-Z_]+)$"
    local rePattern = "^([0-9a-zA-Z_]+\\.{1,2})*([0-9a-zA-Z_]+)$"

    if patternBased == true then
        re = rePattern
    end

    local m, err = ngx.re.match(uri, re)

    if not m then
        return false
    elseif string.find(uri, 'wamp%.') == 1 then
        if allowWAMP ~= true then
            return false
        else
            return true, true
        end
    else
        return true
    end
end

---
--- Add connection to wiola
---
--- @param sid number nginx session connection ID
--- @param wampProto string chosen WAMP protocol
---
--- @return number, string WAMP session registration ID, connection data type
---
function _M:addConnection(sid, wampProto)
    local regId = store:getRegId()
    local dataType

    if wampProto == nil or wampProto == "" then
        wampProto = 'wamp.2.json' -- Setting default protocol for encoding/decodig use
    end

    if wampProto == 'wamp.2.msgpack' then
        dataType = 'binary'
    else
        dataType = 'text'
    end

    store:addSession(regId, {
        connId = sid,
        sessId = regId,
        isWampEstablished = 0,
        --        realm = nil,
        --        wamp_features = nil,
        wamp_protocol = wampProto,
        encoding = string.match(wampProto, '.*%.([^.]+)$'),
        dataType = dataType
    })

    return regId, dataType
end

---
--- Prepare data for sending to client
---
--- @param session table Session object
--- @param data any Client data
---
function _M:_putData(session, data)
    local dataObj = serializers[session.encoding].encode(data)
    store:putData(session, dataObj)
end

---
--- Publish event to sessions
---
--- @param sessRegIds table Array of session Ids
--- @param subId number Subscription Id
--- @param pubId number Publication Id
--- @param details table Details hash-table
--- @param args table Array-like payload
--- @param argsKW table Object-like payload
---
function _M:_publishEvent(sessRegIds, subId, pubId, details, args, argsKW)
    -- WAMP SPEC: [EVENT, SUBSCRIBED.Subscription|id, PUBLISHED.Publication|id, Details|dict]
    -- WAMP SPEC: [EVENT, SUBSCRIBED.Subscription|id, PUBLISHED.Publication|id, Details|dict,
    --             PUBLISH.Arguments|list]
    -- WAMP SPEC: [EVENT, SUBSCRIBED.Subscription|id, PUBLISHED.Publication|id, Details|dict,
    --             PUBLISH.Arguments|list, PUBLISH.ArgumentKw|dict]

    local data
    if not args and not argsKW then
        data = { WAMP_MSG_SPEC.EVENT, subId, pubId, details }
    elseif args and not argsKW then
        data = { WAMP_MSG_SPEC.EVENT, subId, pubId, details, args }
    else
        data = { WAMP_MSG_SPEC.EVENT, subId, pubId, details, args, argsKW }
    end

    for _, v in ipairs(sessRegIds) do
        local session = store:getSession(v)
        self:_putData(session, data)
    end
end

---
--- Publish META event to sessions
---
--- @param part string META API section name
--- @param eventUri string event uri
--- @param session table session object
---
function _M:_publishMetaEvent(part, eventUri, session, ...)
    if not config.metaAPI[part] then
        return
    end

    local subId = store:getSubscriptionId(session.realm, eventUri)
    if not subId then
        return
    end

    local pubId = store:getRegId()
    local recipients = store:getTopicSessions(session.realm, eventUri)
    local parameters = {n = select('#', ...), ...}
    local argsL, argsKW = { session.sessId }, nil

    if eventUri == 'wamp.session.on_join' then
        argsL = {{ session = session.sessId }}
        if parameters[1] then
            argsL[1].authid = parameters[1].authid
            argsL[1].authrole = parameters[1].authrole
            argsL[1].authmethod = parameters[1].authmethod
            argsL[1].authprovider = parameters[1].authprovider
        end
        -- TODO Add information about transport
    elseif eventUri == 'wamp.session.on_leave' then
        -- nothing to add :)
    elseif eventUri == 'wamp.subscription.on_create' then
        local details = {
            id = parameters[1],
            created = parameters[2],
            uri = parameters[3],
            match = parameters[4]
        }
        table.insert(argsL, details)
    elseif eventUri == 'wamp.subscription.on_subscribe' then
        table.insert(argsL, parameters[1])
    elseif eventUri == 'wamp.subscription.on_unsubscribe' then
        table.insert(argsL, parameters[1])
    elseif eventUri == 'wamp.subscription.on_delete' then
        table.insert(argsL, parameters[1])
    elseif eventUri == 'wamp.registration.on_create' then
        local details = {
            id = parameters[1],
            created = parameters[2],
            uri = parameters[3],
            match = parameters[4],
            invoke = parameters[5]
        }
        table.insert(argsL, details)
    elseif eventUri == 'wamp.registration.on_register' then
        table.insert(argsL, parameters[1])
    elseif eventUri == 'wamp.registration.on_unregister' then
        table.insert(argsL, parameters[1])
    elseif eventUri == 'wamp.registration.on_delete' then
        table.insert(argsL, parameters[1])
    end

    self:_publishEvent(recipients, subId, pubId, {}, argsL, argsKW)
end

---
--- Process Call META RPC
---
--- @param part string META API section name
--- @param rpcUri string rpc uri
--- @param session table session object
--- @param requestId number request Id
--- @param rpcArgsL table Array-like payload
--- @param rpcArgsKw table Object-like payload
---
function _M:_callMetaRPC(part, rpcUri, session, requestId, rpcArgsL, rpcArgsKw)
    local data
    local details = setmetatable({}, { __jsontype = 'object' })

    if config.metaAPI[part] == true then

        if rpcUri == 'wamp.session.count' then

            local count = store:getSessionCount(session.realm, rpcArgsL)
            data = { WAMP_MSG_SPEC.RESULT, requestId, details, { count } }

        elseif rpcUri == 'wamp.session.list' then

            local count, sessList = store:getSessionCount(session.realm, rpcArgsL)
            data = { WAMP_MSG_SPEC.RESULT, requestId, details, sessList }

        elseif rpcUri == 'wamp.session.get' then

            local sessionInfo = store:getSession(rpcArgsL[1])
            if sessionInfo ~= nil then

                local res = {}
                if sessionInfo.authInfo then
                    res = sessionInfo.authInfo
                end
                res.session = sessionInfo.sessId
                -- TODO Add transport info

                data = { WAMP_MSG_SPEC.RESULT, requestId, details, { res } }
            else
                data = { WAMP_MSG_SPEC.ERROR, WAMP_MSG_SPEC.CALL, requestId, details, "wamp.error.no_such_session" }
            end

        elseif rpcUri == 'wamp.subscription.list' then

            -- TODO Implement rpcUri == 'wamp.subscription.list'
            -- need to count subs due to matching policy
            --local subsIds = store:getSubscriptions(session.realm)
            --data = { WAMP_MSG_SPEC.RESULT, requestId, details, subsIds }

        elseif rpcUri == 'wamp.subscription.lookup' then

            -- TODO Implement rpcUri == 'wamp.subscription.lookup'

        elseif rpcUri == 'wamp.subscription.match' then

            local subId = store:getSubscriptionId(session.realm, rpcArgsL[1])
            if subId then
                data = { WAMP_MSG_SPEC.RESULT, requestId, details, { subId } }
            else
                data = { WAMP_MSG_SPEC.RESULT, requestId, details}
            end

        elseif rpcUri == 'wamp.subscription.get' then

            -- TODO Implement rpcUri == 'wamp.subscription.get'

        elseif rpcUri == 'wamp.subscription.list_subscribers' then

            local sessList = store:getTopicSessionsBySubId(session.realm, rpcArgsL[1])
            if sessList ~= nil then
                data = { WAMP_MSG_SPEC.RESULT, requestId, details, sessList }
            else
                data = { WAMP_MSG_SPEC.ERROR, WAMP_MSG_SPEC.CALL, requestId, details, "wamp.error.no_such_subscription" }
            end

        elseif rpcUri == 'wamp.subscription.count_subscribers' then

            local sessCount = store:getTopicSessionsCountBySubId(session.realm, rpcArgsL[1])
            if sessCount ~= nil then
                data = { WAMP_MSG_SPEC.RESULT, requestId, details, { sessCount } }
            else
                data = { WAMP_MSG_SPEC.ERROR, WAMP_MSG_SPEC.CALL, requestId, details, "wamp.error.no_such_subscription" }
            end

        elseif rpcUri == 'wamp.registration.list' then

            -- TODO Implement rpcUri == 'wamp.registration.list'

        elseif rpcUri == 'wamp.registration.lookup' then

            -- TODO Implement rpcUri == 'wamp.registration.lookup'

        elseif rpcUri == 'wamp.registration.match' then

            local rpcInfo = store:getRPC(session.realm, rpcArgsL[1])

            if rpcInfo then
                data = { WAMP_MSG_SPEC.RESULT, requestId, details, { rpcInfo.registrationId } }
            else
                data = { WAMP_MSG_SPEC.RESULT, requestId, details}
            end

        elseif rpcUri == 'wamp.registration.get' then

            -- TODO Implement rpcUri == 'wamp.registration.get'

        elseif rpcUri == 'wamp.registration.list_callees' then

            -- TODO Do not forget to update 'wamp.registration.list_callees' while implementing SHARED/SHARDED RPCs
            local rpcInfo = store:getRPC(session.realm, rpcArgsL[1])

            if rpcInfo then
                data = { WAMP_MSG_SPEC.RESULT, requestId, details, { rpcInfo.calleeSesId } }
            else
                data = { WAMP_MSG_SPEC.ERROR, WAMP_MSG_SPEC.CALL, requestId, details, "wamp.error.no_such_registration" }
            end

        elseif rpcUri == 'wamp.registration.count_callees' then

            -- TODO Do not forget to update 'wamp.registration.count_callees' while implementing SHARED/SHARDED RPCs
            local rpcInfo = store:getRPC(session.realm, rpcArgsL[1])

            if rpcInfo then
                data = { WAMP_MSG_SPEC.RESULT, requestId, details, { 1 } }
            else
                data = { WAMP_MSG_SPEC.ERROR, WAMP_MSG_SPEC.CALL, requestId, details, "wamp.error.no_such_registration" }
            end

        else
            data = { WAMP_MSG_SPEC.ERROR, WAMP_MSG_SPEC.CALL, requestId, details, "wamp.error.invalid_uri" }
        end
    else
        data = { WAMP_MSG_SPEC.ERROR, WAMP_MSG_SPEC.CALL, requestId, details, "wamp.error.no_suitable_callee" }
    end

    self:_putData(session, data)
end

---
--- Receive data from client
---
--- @param regId number WAMP session registration ID
--- @param data any data, received through websocket
---
function _M:receiveData(regId, data)
    local session = store:getSession(regId)

    local dataObj = serializers[session.encoding].decode(data)

    -- Analyze WAMP message ID received
    if dataObj[1] == WAMP_MSG_SPEC.HELLO then -- WAMP SPEC: [HELLO, Realm|uri, Details|dict]
        if session.isWampEstablished == 1 then
            -- Protocol error: received second hello message - aborting
            -- WAMP SPEC: [GOODBYE, Details|dict, Reason|uri]
            self:_putData(session, {
                WAMP_MSG_SPEC.ABORT,
                { message = 'Received WELCOME message after session was established' },
                "wamp.error.protocol_violation"
            })
            store:setHandlerFlags(regId, { close = true, sendLast = true })
            self:_publishMetaEvent('session', 'wamp.session.on_leave', session)
        else
            local realm = dataObj[2]
            if self:_validateURI(realm, false, false) then

                if config.wampCRA.authType ~= "none" then

                    if dataObj[3].authmethods and has(dataObj[3].authmethods, "wampcra") and dataObj[3].authid then

                        local challenge, challengeString, signature

                        store:changeChallenge(regId, {
                            realm = realm,
                            wampFeatures = serializers.json.encode(dataObj[3])
                        })

                        if config.wampCRA.authType == "static" then

                            if config.wampCRA.staticCredentials[dataObj[3].authid] then

                                challenge = {
                                    authid = dataObj[3].authid,
                                    authrole = config.wampCRA.staticCredentials[dataObj[3].authid].authrole,
                                    authmethod = "wampcra",
                                    authprovider = "wiolaStaticAuth",
                                    nonce = self:_randomString(16),
                                    timestamp = os.date("!%FT%TZ"), -- without ms. "!%FT%T.%LZ"
                                    session = regId
                                }

                                challengeString = serializers.json.encode(challenge)

                                local hmac = require "resty.hmac"
                                local hm = hmac:new(config.wampCRA.staticCredentials[dataObj[3].authid].secret)

                                signature = hm:generate_signature("sha256", challengeString)

                                if signature then

                                    challenge.signature = signature
                                    store:changeChallenge(regId, challenge)

                                    -- WAMP SPEC: [CHALLENGE, AuthMethod|string, Extra|dict]
                                    self:_putData(session, {
                                        WAMP_MSG_SPEC.CHALLENGE,
                                        "wampcra",
                                        { challenge = challengeString }
                                    })

                                else
                                    -- WAMP SPEC: [ABORT, Details|dict, Reason|uri]
                                    self:_putData(session, {
                                        WAMP_MSG_SPEC.ABORT,
                                        setmetatable({}, { __jsontype = 'object' }),
                                        "wamp.error.authorization_failed"
                                    })
                                end
                            else
                                -- WAMP SPEC: [ABORT, Details|dict, Reason|uri]
                                self:_putData(session, {
                                    WAMP_MSG_SPEC.ABORT,
                                    setmetatable({}, { __jsontype = 'object' }),
                                    "wamp.error.authorization_failed"
                                })
                            end

                        elseif config.wampCRA.authType == "dynamic" then

                            challenge = config.wampCRA.challengeCallback(regId, dataObj[3].authid)

                            -- WAMP SPEC: [CHALLENGE, AuthMethod|string, Extra|dict]
                            self:_putData(session, { WAMP_MSG_SPEC.CHALLENGE, "wampcra", { challenge = challenge } })
                        end
                    else
                        -- WAMP SPEC: [ABORT, Details|dict, Reason|uri]
                        self:_putData(session, {
                            WAMP_MSG_SPEC.ABORT,
                            setmetatable({}, { __jsontype = 'object' }),
                            "wamp.error.authorization_failed"
                        })
                    end
                else

                    session.isWampEstablished = 1
                    session.realm = realm
                    session.wampFeatures = serializers.json.encode(dataObj[3])
                    store:changeSession(regId, session)
                    store:addSessionToRealm(regId, realm)

                    -- WAMP SPEC: [WELCOME, Session|id, Details|dict]
                    self:_putData(session, { WAMP_MSG_SPEC.WELCOME, regId, wamp_features })
                    self:_publishMetaEvent('session', 'wamp.session.on_join', session)
                end
            else
                -- WAMP SPEC: [ABORT, Details|dict, Reason|uri]
                self:_putData(session, {
                    WAMP_MSG_SPEC.ABORT,
                    setmetatable({}, { __jsontype = 'object' }),
                    "wamp.error.invalid_uri"
                })
            end
        end
    elseif dataObj[1] == WAMP_MSG_SPEC.AUTHENTICATE then -- WAMP SPEC: [AUTHENTICATE, Signature|string, Extra|dict]

        if session.isWampEstablished == 1 then
            -- Protocol error: received second message - aborting
            -- WAMP SPEC: [GOODBYE, Details|dict, Reason|uri]
            self:_putData(session, {
                WAMP_MSG_SPEC.ABORT,
                { message = 'Received AUTHENTICATE message after session was established' },
                "wamp.error.protocol_violation"
            })
            store:setHandlerFlags(regId, { close = true, sendLast = true })
            self:_publishMetaEvent('session', 'wamp.session.on_leave', session)
        else

            local challenge = store:getChallenge(regId)
            local authInfo

            if config.wampCRA.authType == "static" then

                if dataObj[2] == challenge.signature then
                    authInfo = {
                        authid = challenge.authid,
                        authrole = challenge.authrole,
                        authmethod = challenge.authmethod,
                        authprovider = challenge.authprovider
                    }
                end

            elseif config.wampCRA.authType == "dynamic" then
                authInfo = config.wampCRA.authCallback(regId, dataObj[2])
            end

            if authInfo then

                session.isWampEstablished = 1
                session.realm = challenge.realm
                session.wampFeatures = challenge.wampFeatures
                session.authInfo = authInfo
                store:changeSession(regId, session)
                store:addSessionToRealm(regId, challenge.realm)

                local details = wamp_features
                details.authid = authInfo.authid
                details.authrole = authInfo.authrole
                details.authmethod = authInfo.authmethod
                details.authprovider = authInfo.authprovider

                -- WAMP SPEC: [WELCOME, Session|id, Details|dict]
                self:_putData(session, { WAMP_MSG_SPEC.WELCOME, regId, details })
                self:_publishMetaEvent('session', 'wamp.session.on_join', session, authInfo)

            else
                -- WAMP SPEC: [ABORT, Details|dict, Reason|uri]
                self:_putData(session, {
                    WAMP_MSG_SPEC.ABORT,
                    setmetatable({}, { __jsontype = 'object' }),
                    "wamp.error.authorization_failed"
                })
            end
        end

        -- Clean up Challenge data in any case
        store:removeChallenge(regId)

    -- elseif dataObj[1] == WAMP_MSG_SPEC.ABORT then -- WAMP SPEC: [ABORT, Details|dict, Reason|uri]
        -- No response is expected
    elseif dataObj[1] == WAMP_MSG_SPEC.GOODBYE then -- WAMP SPEC: [GOODBYE, Details|dict, Reason|uri]
        if session.isWampEstablished == 1 then
            self:_putData(session, {
                WAMP_MSG_SPEC.GOODBYE,
                setmetatable({}, { __jsontype = 'object' }),
                "wamp.close.goodbye_and_out"
            })
        else
            self:_putData(session, {
                WAMP_MSG_SPEC.ABORT,
                { message = 'Received GOODBYE message before session was established' },
                "wamp.error.protocol_violation"
            })
            store:setHandlerFlags(regId, { close = true, sendLast = true })
        end
        self:_publishMetaEvent('session', 'wamp.session.on_leave', session)
    elseif dataObj[1] == WAMP_MSG_SPEC.ERROR then
        -- WAMP SPEC: [ERROR, REQUEST.Type|int, REQUEST.Request|id, Details|dict, Error|uri]
        -- WAMP SPEC: [ERROR, REQUEST.Type|int, REQUEST.Request|id, Details|dict, Error|uri,
        --             Arguments|list]
        -- WAMP SPEC: [ERROR, REQUEST.Type|int, REQUEST.Request|id, Details|dict, Error|uri,
        --             Arguments|list, ArgumentsKw|dict]
        if session.isWampEstablished == 1 then
            if dataObj[2] == WAMP_MSG_SPEC.INVOCATION then
                -- WAMP SPEC: [ERROR, INVOCATION, INVOCATION.Request|id, Details|dict, Error|uri]
                -- WAMP SPEC: [ERROR, INVOCATION, INVOCATION.Request|id, Details|dict, Error|uri,
                --             Arguments|list]
                -- WAMP SPEC: [ERROR, INVOCATION, INVOCATION.Request|id, Details|dict, Error|uri,
                --             Arguments|list, ArgumentsKw|dict]

                local invoc = store:getInvocation(dataObj[3])
                local callerSess = store:getSession(invoc.callerSesId)

                if #dataObj == 6 then
                    -- WAMP SPEC: [ERROR, CALL, CALL.Request|id, Details|dict, Error|uri, Arguments|list]
                    self:_putData(callerSess, {
                        WAMP_MSG_SPEC.ERROR,
                        WAMP_MSG_SPEC.CALL,
                        invoc.CallReqId,
                        setmetatable({}, { __jsontype = 'object' }),
                        dataObj[5],
                        dataObj[6]
                    })
                elseif #dataObj == 7 then
                    -- WAMP SPEC: [ERROR, CALL, CALL.Request|id, Details|dict, Error|uri,
                    --             Arguments|list, ArgumentsKw|dict]
                    self:_putData(callerSess, {
                        WAMP_MSG_SPEC.ERROR,
                        WAMP_MSG_SPEC.CALL,
                        invoc.CallReqId,
                        setmetatable({}, { __jsontype = 'object' }),
                        dataObj[5],
                        dataObj[6],
                        dataObj[7]
                    })
                else
                    -- WAMP SPEC: [ERROR, CALL, CALL.Request|id, Details|dict, Error|uri]
                    self:_putData(callerSess, {
                        WAMP_MSG_SPEC.ERROR,
                        WAMP_MSG_SPEC.CALL,
                        invoc.CallReqId,
                        setmetatable({}, { __jsontype = 'object' }),
                        dataObj[5]
                    })
                end

                store:removeInvocation(dataObj[3])
            end
        else
            self:_putData(session, {
                WAMP_MSG_SPEC.ABORT,
                { message = 'Received ERROR message before session was established' },
                "wamp.error.protocol_violation"
            })
            store:setHandlerFlags(regId, { close = true, sendLast = true })
        end
    elseif dataObj[1] == WAMP_MSG_SPEC.PUBLISH then
        -- WAMP SPEC: [PUBLISH, Request|id, Options|dict, Topic|uri]
        -- WAMP SPEC: [PUBLISH, Request|id, Options|dict, Topic|uri, Arguments|list]
        -- WAMP SPEC: [PUBLISH, Request|id, Options|dict, Topic|uri, Arguments|list, ArgumentsKw|dict]
        if session.isWampEstablished == 1 then
            if self:_validateURI(dataObj[4], false, false) then
                local pubId = store:getRegId()
                local recipients = store:getEventRecipients(session.realm, dataObj[4], regId, dataObj[3])

                for _, v in ipairs(recipients) do
                    self:_publishEvent(v.sessions, v.subId, pubId, v.details, dataObj[5], dataObj[6])

                    if dataObj[3].acknowledge and dataObj[3].acknowledge == true then
                        -- WAMP SPEC: [PUBLISHED, PUBLISH.Request|id, Publication|id]
                        self:_putData(session, { WAMP_MSG_SPEC.PUBLISHED, dataObj[2], pubId })
                    end
                end
            else
                self:_putData(session, {
                    WAMP_MSG_SPEC.ERROR,
                    WAMP_MSG_SPEC.PUBLISH,
                    dataObj[2],
                    setmetatable({}, { __jsontype = 'object' }),
                    "wamp.error.invalid_uri"
                })
            end
        else
            self:_putData(session, {
                WAMP_MSG_SPEC.ABORT,
                { message = 'Received PUBLISH message before session was established' },
                "wamp.error.protocol_violation"
            })
            store:setHandlerFlags(regId, { close = true, sendLast = true })
            self:_publishMetaEvent('session', 'wamp.session.on_leave', session)
        end
    elseif dataObj[1] == WAMP_MSG_SPEC.SUBSCRIBE then -- WAMP SPEC: [SUBSCRIBE, Request|id, Options|dict, Topic|uri]
        if session.isWampEstablished == 1 then
            local patternBased = false
            if dataObj[3].match then
                patternBased = true
            end

            if self:_validateURI(dataObj[4], patternBased, true) then
                local subscriptionId, isNewSubscription = store:subscribeSession(
                        session.realm, dataObj[4], dataObj[3], regId)

                -- WAMP SPEC: [SUBSCRIBED, SUBSCRIBE.Request|id, Subscription|id]
                self:_putData(session, { WAMP_MSG_SPEC.SUBSCRIBED, dataObj[2], subscriptionId })
                if isNewSubscription then
                    self:_publishMetaEvent('subscription', 'wamp.subscription.on_create', session,
                        subscriptionId, os.date("!%Y-%m-%dT%TZ"), dataObj[4], "exact")
                end
                self:_publishMetaEvent('subscription', 'wamp.subscription.on_subscribe', session,
                    subscriptionId)
            else
                self:_putData(session, {
                    WAMP_MSG_SPEC.ERROR,
                    WAMP_MSG_SPEC.SUBSCRIBE,
                    dataObj[2],
                    setmetatable({}, { __jsontype = 'object' }),
                    "wamp.error.invalid_uri"
                })
            end
        else
            self:_putData(session, {
                WAMP_MSG_SPEC.ABORT,
                { message = 'Received SUBSCRIBE message before session was established' },
                "wamp.error.protocol_violation"
            })
            store:setHandlerFlags(regId, { close = true, sendLast = true })
            self:_publishMetaEvent('session', 'wamp.session.on_leave', session)
        end
    elseif dataObj[1] == WAMP_MSG_SPEC.UNSUBSCRIBE then
        -- WAMP SPEC: [UNSUBSCRIBE, Request|id, SUBSCRIBED.Subscription|id]
        if session.isWampEstablished == 1 then
            local isSesSubscrbd, wasTopicRemoved = store:unsubscribeSession(session.realm, dataObj[3], regId)
            if isSesSubscrbd ~= ngx.null then
                -- WAMP SPEC: [UNSUBSCRIBED, UNSUBSCRIBE.Request|id]
                self:_putData(session, { WAMP_MSG_SPEC.UNSUBSCRIBED, dataObj[2] })
                self:_publishMetaEvent('subscription', 'wamp.subscription.on_unsubscribe', session, dataObj[3])
                if wasTopicRemoved then
                    self:_publishMetaEvent('subscription', 'wamp.subscription.on_delete', session, dataObj[3])
                end
            else
                self:_putData(session, {
                    WAMP_MSG_SPEC.ERROR,
                    WAMP_MSG_SPEC.UNSUBSCRIBE,
                    dataObj[2],
                    setmetatable({}, { __jsontype = 'object' }),
                    "wamp.error.no_such_subscription"
                })
            end
        else
            self:_putData(session, {
                WAMP_MSG_SPEC.ABORT,
                { message = 'Received UNSUBSCRIBE message before session was established' },
                "wamp.error.protocol_violation"
            })
            store:setHandlerFlags(regId, { close = true, sendLast = true })
            self:_publishMetaEvent('session', 'wamp.session.on_leave', session)
        end
    elseif dataObj[1] == WAMP_MSG_SPEC.CALL then
        -- WAMP SPEC: [CALL, Request|id, Options|dict, Procedure|uri]
        -- WAMP SPEC: [CALL, Request|id, Options|dict, Procedure|uri, Arguments|list]
        -- WAMP SPEC: [CALL, Request|id, Options|dict, Procedure|uri, Arguments|list, ArgumentsKw|dict]
        if session.isWampEstablished == 1 then
            local isUriValid, isWampSpecial = self:_validateURI(dataObj[4], false, true)
            if isUriValid then

                if isWampSpecial then
                    -- Received a call for WAMP meta RPCs
                    local metapart = string.match(dataObj[4], "wamp.(%a+)")
                    self:_callMetaRPC(metapart, dataObj[4], session, dataObj[2], dataObj[5], dataObj[6])
                else

                    local rpcInfo = store:getRPC(session.realm, dataObj[4])

                    if not rpcInfo then
                        -- WAMP SPEC: [ERROR, CALL, CALL.Request|id, Details|dict, Error|uri]
                        self:_putData(session, {
                            WAMP_MSG_SPEC.ERROR,
                            WAMP_MSG_SPEC.CALL,
                            dataObj[2],
                            setmetatable({}, { __jsontype = 'object' }),
                            "wamp.error.no_suitable_callee"
                        })
                    else
                        local details = setmetatable({}, { __jsontype = 'object' })

                        if config.callerIdentification == "always" or
                        (config.callerIdentification == "auto" and
                        ((dataObj[3].disclose_me ~= nil and dataObj[3].disclose_me == true) or
                        (rpcInfo.disclose_caller == true))) then
                            details.caller = regId
                        end

                        if dataObj[3].receive_progress ~= nil and dataObj[3].receive_progress == true then
                            details.receive_progress = true
                        end

                        local calleeSess = store:getSession(rpcInfo.calleeSesId)
                        local invReqId = store:getRegId()

                        if rpcInfo.options and rpcInfo.options.procedure then
                            details.procedure = rpcInfo.options.procedure
                        end

                        if dataObj[3].timeout ~= nil and
                        dataObj[3].timeout > 0 and
                        calleeSess.wampFeatures.callee.features.call_timeout == true and
                        calleeSess.wampFeatures.callee.features.call_canceling == true then

                            -- Caller specified Timeout for CALL processing and callee support this feature
                            local function callCancel(_, calleeSession, invocReqId)

                                -- WAMP SPEC: [INTERRUPT, INVOCATION.Request|id, Options|dict]
                                self:_putData(calleeSession, {
                                    WAMP_MSG_SPEC.INTERRUPT,
                                    invocReqId,
                                    setmetatable({}, { __jsontype = 'object' })
                                })
                            end

                            local ok, err = ngx.timer.at(dataObj[3].timeout, callCancel, calleeSess, invReqId)

                            if not ok then
                            end
                        end

                        store:addCallInvocation(dataObj[2], session.sessId, invReqId, calleeSess.sessId)

                        if #dataObj == 5 then
                            -- WAMP SPEC: [INVOCATION, Request|id, REGISTERED.Registration|id, Details|dict,
                            --             CALL.Arguments|list]
                            self:_putData(calleeSess, {
                                WAMP_MSG_SPEC.INVOCATION,
                                invReqId,
                                rpcInfo.registrationId,
                                details,
                                dataObj[5]
                            })
                        elseif #dataObj == 6 then
                            -- WAMP SPEC: [INVOCATION, Request|id, REGISTERED.Registration|id, Details|dict,
                            --             CALL.Arguments|list, CALL.ArgumentsKw|dict]
                            self:_putData(calleeSess, {
                                WAMP_MSG_SPEC.INVOCATION,
                                invReqId,
                                rpcInfo.registrationId,
                                details,
                                dataObj[5],
                                dataObj[6]
                            })
                        else
                            -- WAMP SPEC: [INVOCATION, Request|id, REGISTERED.Registration|id, Details|dict]
                            self:_putData(calleeSess, {
                                WAMP_MSG_SPEC.INVOCATION,
                                invReqId,
                                rpcInfo.registrationId,
                                details
                            })
                        end
                    end
                end
            else
                self:_putData(session, {
                    WAMP_MSG_SPEC.ERROR,
                    WAMP_MSG_SPEC.CALL,
                    dataObj[2],
                    setmetatable({}, { __jsontype = 'object' }),
                    "wamp.error.invalid_uri"
                })
            end
        else
            self:_putData(session, {
                WAMP_MSG_SPEC.ABORT,
                { message = 'Received CALL message before session was established' },
                "wamp.error.protocol_violation"
            })
            store:setHandlerFlags(regId, { close = true, sendLast = true })
            self:_publishMetaEvent('session', 'wamp.session.on_leave', session)
        end
    elseif dataObj[1] == WAMP_MSG_SPEC.REGISTER then
        -- WAMP SPEC: [REGISTER, Request|id, Options|dict, Procedure|uri]
        if session.isWampEstablished == 1 then
            local patternBased = false
            if dataObj[3].match then
                patternBased = true
            end

            if self:_validateURI(dataObj[4], patternBased, false) then

                local registrationId = store:registerSessionRPC(session.realm, dataObj[4], dataObj[3], regId)

                if not registrationId then
                    self:_putData(session, {
                        WAMP_MSG_SPEC.ERROR,
                        WAMP_MSG_SPEC.REGISTER,
                        dataObj[2],
                        setmetatable({}, { __jsontype = 'object' }),
                        "wamp.error.procedure_already_exists"
                    })
                else
                    -- WAMP SPEC: [REGISTERED, REGISTER.Request|id, Registration|id]
                    self:_putData(session, { WAMP_MSG_SPEC.REGISTERED, dataObj[2], registrationId })
                    -- TODO Refactor this in case of implementing shared registrations
                    self:_publishMetaEvent('registration', 'wamp.registration.on_create', session,
                        registrationId, os.date("!%Y-%m-%dT%TZ"), dataObj[4], "exact", "single")
                    self:_publishMetaEvent('registration', 'wamp.registration.on_register', session,
                        registrationId)
                end
            else
                self:_putData(session, {
                    WAMP_MSG_SPEC.ERROR,
                    WAMP_MSG_SPEC.REGISTER,
                    dataObj[2],
                    setmetatable({}, { __jsontype = 'object' }),
                    "wamp.error.invalid_uri"
                })
            end
        else
            self:_putData(session, {
                WAMP_MSG_SPEC.ABORT,
                { message = 'Received REGISTER message before session was established' },
                "wamp.error.protocol_violation"
            })
            store:setHandlerFlags(regId, { close = true, sendLast = true })
            self:_publishMetaEvent('session', 'wamp.session.on_leave', session)
        end
    elseif dataObj[1] == WAMP_MSG_SPEC.UNREGISTER then
        -- WAMP SPEC: [UNREGISTER, Request|id, REGISTERED.Registration|id]
        if session.isWampEstablished == 1 then

            local rpc = store:unregisterSessionRPC(session.realm, dataObj[3], regId)

            if rpc ~= ngx.null then
                -- WAMP SPEC: [UNREGISTERED, UNREGISTER.Request|id]
                self:_putData(session, { WAMP_MSG_SPEC.UNREGISTERED, dataObj[2] })
                self:_publishMetaEvent('registration', 'wamp.registration.on_unregister', session, dataObj[3])
                -- TODO Refactor this in case of implementing shared registrations
                self:_publishMetaEvent('registration', 'wamp.registration.on_delete', session, dataObj[3])
            else
                self:_putData(session, {
                    WAMP_MSG_SPEC.ERROR,
                    WAMP_MSG_SPEC.UNREGISTER,
                    dataObj[2],
                    setmetatable({}, { __jsontype = 'object' }),
                    "wamp.error.no_such_registration"
                })
            end
        else
            self:_putData(session, {
                WAMP_MSG_SPEC.ABORT,
                { message = 'Received UNREGISTER message before session was established' },
                "wamp.error.protocol_violation"
            })
            store:setHandlerFlags(regId, { close = true, sendLast = true })
            self:_publishMetaEvent('session', 'wamp.session.on_leave', session)
        end
    elseif dataObj[1] == WAMP_MSG_SPEC.YIELD then
        -- WAMP SPEC: [YIELD, INVOCATION.Request|id, Options|dict]
        -- WAMP SPEC: [YIELD, INVOCATION.Request|id, Options|dict, Arguments|list]
        -- WAMP SPEC: [YIELD, INVOCATION.Request|id, Options|dict, Arguments|list, ArgumentsKw|dict]
        if session.isWampEstablished == 1 then

            local invoc = store:getInvocation(dataObj[2])
            local callerSess = store:getSession(invoc.callerSesId)
            local details = setmetatable({}, { __jsontype = 'object' })

            if dataObj[3].progress ~= nil and dataObj[3].progress == true then
                details.progress = true
            else
                store:removeInvocation(dataObj[2])
                store:removeCall(invoc.CallReqId)
            end

            if #dataObj == 4 then
                -- WAMP SPEC: [RESULT, CALL.Request|id, Details|dict, YIELD.Arguments|list]
                self:_putData(callerSess, { WAMP_MSG_SPEC.RESULT, invoc.CallReqId, details, dataObj[4] })
            elseif #dataObj == 5 then
                -- WAMP SPEC: [RESULT, CALL.Request|id, Details|dict, YIELD.Arguments|list, YIELD.ArgumentsKw|dict]
                self:_putData(callerSess, { WAMP_MSG_SPEC.RESULT, invoc.CallReqId, details, dataObj[4], dataObj[5] })
            else
                -- WAMP SPEC: [RESULT, CALL.Request|id, Details|dict]
                self:_putData(callerSess, { WAMP_MSG_SPEC.RESULT, invoc.CallReqId, details })
            end
        else
            self:_putData(session, {
                WAMP_MSG_SPEC.ABORT,
                { message = 'Received YIELD message before session was established' },
                "wamp.error.protocol_violation"
            })
            store:setHandlerFlags(regId, { close = true, sendLast = true })
            self:_publishMetaEvent('session', 'wamp.session.on_leave', session)
        end
    elseif dataObj[1] == WAMP_MSG_SPEC.CANCEL then
        -- WAMP SPEC: [CANCEL, CALL.Request|id, Options|dict]
        if session.isWampEstablished == 1 then

            local wiCall = store:getCall(dataObj[2])
            local calleeSess = store:getSession(wiCall.calleeSesId)

            if calleeSess.wampFeatures.callee.features.call_canceling == true then
                local details = setmetatable({}, { __jsontype = 'object' })

                if dataObj[3].mode ~= nil then
                    details.mode = dataObj[3].mode
                end

                -- WAMP SPEC: [INTERRUPT, INVOCATION.Request|id, Options|dict]
                self:_putData(calleeSess, { WAMP_MSG_SPEC.INTERRUPT, wiCall.wiInvocId, details })
            end
        else
            self:_putData(session, {
                WAMP_MSG_SPEC.ABORT,
                { message = 'Received CANCEL message before session was established' },
                "wamp.error.protocol_violation"
            })
            store:setHandlerFlags(regId, { close = true, sendLast = true })
            self:_publishMetaEvent('session', 'wamp.session.on_leave', session)
        end
    else
        -- Received non-compliant WAMP message
        -- WAMP SPEC: [ABORT, Details|dict, Reason|uri]
        self:_putData(session, {
            WAMP_MSG_SPEC.ABORT,
            { message = 'Received non-compliant WAMP message' },
            "wamp.error.protocol_violation"
        })
        store:setHandlerFlags(regId, { close = true, sendLast = true })
    end
end

---
--- Retrieve data, available for session
---
--- @param regId number WAMP session registration ID
--- @param last boolean return from the end of a queue
---
--- @return any first WAMP message from the session data queue
---
function _M:getPendingData(regId, last)
    return store:getPendingData(regId, last)
end

---
--- Retrieve connection handler flags, set up for session
---
--- @param regId number WAMP session registration ID
---
--- @return table flags data table
---
function _M:getHandlerFlags(regId)
    return store:getHandlerFlags(regId)
end


---
--- Process lightweight publish POST data from client
---
--- @param sid number nginx session connection ID
--- @param realm string WAMP Realm to operate in
--- @param data any data, received through POST
---
function _M:processPostData(sid, realm, data)

    local dataObj = serializers.json.decode(data)
    local res
    local httpCode

    if dataObj[1] == WAMP_MSG_SPEC.PUBLISH then
        local regId = self.addConnection(sid, nil)

        -- Make a session legal :)
        local session = store:getSession(regId)
        session.isWampEstablished = 1
        session.realm = realm
        store:changeSession(regId, session)

        self.receiveData(regId, data)

        local cliData = self.getPendingData(regId)
        if cliData ~= ngx.null then
            res = cliData
            httpCode = ngx.HTTP_FORBIDDEN
        else
            res = serializers.json.encode({ result = true, error = nil })
            httpCode = ngx.HTTP_OK
        end

        store:removeSession(regId)
    else
        res = serializers.json.encode({ result = false, error = "Message type not supported" })
        httpCode = ngx.HTTP_FORBIDDEN
    end

    return res, httpCode
end

return _M
