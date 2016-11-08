--
-- Project: wiola
-- User: Konstantin Burkalev
-- Date: 08.11.16
--

local _M = {}

--
-- Cleans up wiola session data in redis store
--
-- redis - Redis instance on which to operate
-- regId - WAMP session registration ID
--
function _M.cleanupSession(redis, regId)

    ngx.log(ngx.DEBUG, "Cleaning up session: ", regId)

    local session = redis:array_to_hash(redis:hgetall("wiSes" .. regId))
    session.realm = session.realm or ""

    local subscriptions = redis:array_to_hash(redis:hgetall("wiRealm" .. session.realm .. "Subs"))

    for k, v in pairs(subscriptions) do
        redis:srem("wiRealm" .. session.realm .. "Sub" .. k .. "Sessions", regId)
        if redis:scard("wiRealm" .. session.realm .. "Sub" .. k .. "Sessions") == 0 then
            redis:del("wiRealm" .. session.realm .. "Sub" .. k .. "Sessions")
            redis:hdel("wiRealm" .. session.realm .. "Subs",k)
            redis:hdel("wiRealm" .. session.realm .. "RevSubs",v)
        end
    end

    local rpcs = redis:array_to_hash(redis:hgetall("wiSes" .. regId .. "RPCs"))

    for k, v in pairs(rpcs) do
        redis:srem("wiRealm" .. session.realm .. "RPCs",k)
        redis:del("wiRPC" .. k)
    end

    redis:del("wiSes" .. regId .. "RPCs")
    redis:del("wiSes" .. regId .. "RevRPCs")
    redis:del("wiSes" .. regId .. "Challenge")

    redis:srem("wiRealm" .. session.realm .. "Sessions", regId)
    if redis:scard("wiRealm" .. session.realm .. "Sessions") == 0 then
        redis:srem("wiolaRealms",session.realm)
    end

    redis:del("wiSes" .. regId .. "Data")
    redis:del("wiSes" .. regId)
    redis:srem("wiolaIds",regId)

    ngx.log(ngx.DEBUG, "Session data successfully removed!")
end

return _M
