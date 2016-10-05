package = "Wiola"
version = "0.5.2-1"

source = {
    url = "git://github.com/KSDaemon/wiola.git",
    tag = "v0.5.2"
}

description = {
    summary = "LUA WAMP router",
    detailed = [[
    WAMP implementation on Lua, using the power of LUA Nginx module,
    Lua-Resty-WebSocket addon, and Redis as cache store.
    This package works both in Nginx enviroment with installed ngx_lua
    and lua-resty-websocket modules and OpenResty platform.
    ]],
    homepage = "https://github.com/KSDaemon/wiola",
    license = "BSD 2-Clause license",
    maintainer = "Konstantin Burkalev <KSDaemon@ya.ru>"
}

dependencies = {
    "lua >= 5.1",
    "luarestyredis",
    "rapidjson >= 0.3",
    "lua-messagepack >= 0.3"
}

build = {
    type = 'builtin',
    modules = {
        ['wiola'] = 'build/wiola.lua',
        ['wiola.handler'] = 'build/handler.lua',
        ['wiola.headers'] = 'build/headers.lua',
        ['wiola.post-handler'] = 'build/post-handler.lua',
    }
}
