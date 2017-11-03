--
-- Project: wiola
-- User: Konstantin Burkalev
-- Date: 08.11.16
--

local _M = {}

--
-- Cleans up wiola session data in redis store
--
-- store - Store instance on which to operate
-- regId - WAMP session registration ID
--
function _M.cleanupSession(store, regId)
    ngx.log(ngx.DEBUG, "Cleaning up session: ", regId)
    store:removeSession(regId)
    ngx.log(ngx.DEBUG, "Session data successfully removed!")
end

return _M
