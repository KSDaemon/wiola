wiola
=====

WAMP (WebSocket Application Messaging Protocol) implementation on Lua, using the power of LUA Nginx module,
Lua WebSocket addon, and Redis as cache store.

Table of Contents
=================

* [Description](#description)
* [Usage example](#usage-example)
* [Installation](#installation)
* [Dependencies](#dependencies)
* [Methods](#methods)
    * [setupRedis](#setupredishost-port-db)
    * [addConnection](#addconnectionsid-wampproto)
    * [removeConnection](#removeconnectionregid)
    * [receiveData](#receivedataregid-data)
    * [getPendingData](#getpendingdataregid)
    * [processPostData](#processpostdatasid-realm-data)
* [Copyright and License](#copyright-and-license)
* [See Also](#see-also)

Description
===========

Wiola implements [WAMP](http://wamp.ws) v2 router specification on top of OpenResty web app server,
 which is actually nginx plus a bunch of 3rd party modules, such as lua-nginx-module, lua-resty-websocket,
 lua-resty-redis, lua-resty-libcjson and so on.

wiola supports next WAMP roles and features:

* broker: advanced profile with features:
    * subscriber blackwhite listing
    * publisher exclusion
    * publisher identification
* dealer: advanced profile with features:
    * callee blackwhite listing
    * caller exclusion
    * caller identification
    * progressive call results

Wiola supports JSON and msgpack serializers.

From v0.3.1 Wiola also supports lightweight POST event publishing. See processPostData method and post-handler.lua for details.

[Back to TOC](#table-of-contents)

Usage example
=============

For example usage, please see [handler.lua](src/wiola/handler.lua) file.

[Back to TOC](#table-of-contents)

Installation
============

To use wiola you need:

* Nginx or OpenResty
* [luajit](http://luajit.org/)
* [lua-nginx-module](https://github.com/chaoslawful/lua-nginx-module)
* [lua-resty-websocket](https://github.com/agentzh/lua-resty-websocket)
* [lua-resty-redis](https://github.com/agentzh/lua-resty-redis)
* [Redis server](http://redis.io)
* [lua-rapidjson](https://github.com/xpol/lua-rapidjson)
* [lua-MessagePack](http://fperrad.github.io/lua-MessagePack/) (optional)

Instead of compiling lua-* modules into nginx, you can simply use [OpenResty](http://openresty.org) server.

In any case, for your convenience, you can install Wiola through [luarocks](http://luarocks.org/modules/ksdaemon/wiola)
by `luarocks install wiola`.

Next thing is configuring nginx host. See example below.

```nginx
# set search paths for pure Lua external libraries (';;' is the default path):
# add paths for wiola and msgpack libs
lua_package_path '/usr/local/lualib/wiola/?.lua;/usr/local/lualib/lua-MessagePack/?.lua;;';

# Configure a vhost
server {
   # example location for websocket WAMP connection
   location /ws/ {
      lua_socket_log_errors off;
      lua_check_client_abort on;

      # This is needed to set additional websocket protocol headers
      header_filter_by_lua_file $document_root/lua/wiola/headers.lua;
      # Set a handler for connection
      content_by_lua_file $document_root/lua/wiola/handler.lua;
   }

   # example location for a lightweight POST event publishing
   location /wslight/ {
      lua_socket_log_errors off;
      lua_check_client_abort on;

      content_by_lua_file $document_root/lua/wiola/post-handler.lua;
   }

}
```

Actually, you do not need to do anything else. Just take any WAMP client and make a connection.

[Back to TOC](#table-of-contents)

Methods
========

setupRedis(host, port, db)
------------------------------------------

Configure and initialize connection to Redis server.

Parameters:

 * **host** - Redis server host or Redis unix socket path
 * **port** - Redis server port (in case of use network connection). Omit for socket connection.
 * **db** - Redis database index to select

Returns:

 * **Connection flag** (integer)
 * **Error description** (string) in case of error, nil on success

[Back to TOC](#table-of-contents)

addConnection(sid, wampProto)
------------------------------------------

Adds new connection instance to wiola control.

Parameters:

 * **sid** - nginx session id
 * **wampProto** - chosen WAMP subprotocol. It is set in header filter. So just pass here ngx.header["Sec-WebSocket-Protocol"]. It's done just in order not to use shared variables.

Returns:

 * **WAMP session ID** (integer)
 * **Connection data type** (string: 'text' or 'binary')

[Back to TOC](#table-of-contents)

removeConnection(regId)
------------------------------------------

Removes connection from viola control. Cleans all cached data. Do not neglect this method on connection termination.

Parameters:

 * **regId** - WAMP session ID

Returns: nothing

[Back to TOC](#table-of-contents)

receiveData(regId, data)
------------------------------------------

This method should be called, when new data is received from web socket. This method analyze all incoming messages, set states and prepare response data for clients.

Parameters:

 * **regId** - WAMP session ID
 * **data** - received data

Returns: nothing

[Back to TOC](#table-of-contents)

getPendingData(regId)
------------------------------------------

Checks the store for new data for client.

Parameters:

 * **regId** - WAMP session ID

Returns:

 * **client data** (type depends on session data type) or **null**
 * **error description** in case of error

 This method is actualy a proxy for redis:lpop() method.

[Back to TOC](#table-of-contents)

processPostData(sid, realm, data)
------------------------------------------

Process lightweight POST data from client containing a publish message. This method is intended for fast publishing
an event, for example, in case when WAMP client is a browser application, which makes some changes on backend server,
so backend is a right place to notify other WAMP subscribers, but making a full WAMP connection is not optimal.

Parameters:

 * **sid** - nginx session connection ID
 * **realm** - WAMP Realm to operate in
 * **data** - data, received through POST (JSON-encoded WAMP publish event)

Returns:

 * **response data** (JSON encoded WAMP response message in case of error, or { result = true })
 * **httpCode** HTTP status code (HTTP_OK/200 in case of success, HTTP_FORBIDDEN/403 in case of error)

[Back to TOC](#table-of-contents)

Copyright and License
=====================

Wiola library is licensed under the BSD 2-Clause license.

Copyright (c) 2014, Konstantin Burkalev
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

[Back to TOC](#table-of-contents)

See Also
========

* [WAMP specification](http://wamp.ws)
* [Wampy.js](https://github.com/KSDaemon/wampy.js). WAMP Javascript client-side implementation.
* [OpenResty](http://openresty.org)
* [lua-nginx-module](https://github.com/chaoslawful/lua-nginx-module)
* [lua-resty-websocket](https://github.com/agentzh/lua-resty-websocket)
* [lua-resty-libcjson](https://github.com/bungle/lua-resty-libcjson)
* [lua-rapidjson](https://github.com/xpol/lua-rapidjson)
* [lua-resty-redis](https://github.com/agentzh/lua-resty-redis)
* [Redis key-value store](http://redis.io)
* [lua-MessagePack](http://fperrad.github.io/lua-MessagePack/)

[Back to TOC](#table-of-contents)
