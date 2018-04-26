/**
 * Project: wiola
 * User: KSDaemon
 * Date: 21.10.16
 */

const Wampy = require('wampy').Wampy;
const w3cws = require('websocket').w3cwebsocket;
let ws, d = Date.now();

console.log('0: Initializing wampy and connecting to server...');

ws = new Wampy('ws://webxp/ws/', {
    ws: w3cws,
    realm: 'test',
    onConnect: function () {
        console.log('+' + (Date.now() - d) + 'ms: Yahoo! We are online!');
        ws.subscribe('wamp.session.on_join', {
            onEvent: function (res) {
                console.log('Received wamp.session.on_join message!');
                console.log(res);
                ws.call('wamp.session.count', null, function (result) {
                    console.log('Received RPC wamp.session.count result!');
                    console.log(result);
                });
            }
        }).subscribe('wamp.session.on_leave', {
            onEvent: function (res) {
                console.log('Received wamp.session.on_leave message!');
                console.log(res);
                ws.call('wamp.session.count', null, function (result) {
                    console.log('Received RPC wamp.session.count result!');
                    console.log(result);
                });
            }
        }).subscribe('wamp.subscription.on_create', {
            onEvent: function (res) {
                console.log('Received wamp.subscription.on_create message!');
                console.log(res);
            }
        }).subscribe('wamp.subscription.on_subscribe', {
            onEvent: function (res) {
                console.log('Received wamp.subscription.on_subscribe message!');
                console.log(res);
                ws.call('wamp.subscription.list_subscribers', res.argsList[1], function (result) {
                    console.log('Received RPC wamp.subscription.list_subscribers result!');
                    console.log(result);
                });
                ws.call('wamp.subscription.count_subscribers', res.argsList[1], function (result) {
                    console.log('Received RPC wamp.subscription.count_subscribers result!');
                    console.log(result);
                });
            }
        }).subscribe('wamp.subscription.on_unsubscribe', {
            onEvent: function (res) {
                console.log('Received wamp.subscription.on_unsubscribe message!');
                console.log(res);
                ws.call('wamp.subscription.list_subscribers', res.argsList[1], function (result) {
                    console.log('Received RPC wamp.subscription.list_subscribers result!');
                    console.log(result);
                });
                ws.call('wamp.subscription.count_subscribers', res.argsList[1], function (result) {
                    console.log('Received RPC wamp.subscription.count_subscribers result!');
                    console.log(result);
                });
            }
        }).subscribe('wamp.subscription.on_delete', {
            onEvent: function (res) {
                console.log('Received wamp.subscription.on_delete message!');
                console.log(res);
            }
        }).subscribe('wamp.registration.on_create', {
            onEvent: function (res) {
                console.log('Received wamp.registration.on_create message!');
                console.log(res);
            }
        }).subscribe('wamp.registration.on_register', {
            onEvent: function (res) {
                console.log('Received wamp.registration.on_register message!');
                console.log(res);
                ws.call('wamp.registration.list_callees', res.argsList[1], function (result) {
                    console.log('Received RPC wamp.registration.list_callees result!');
                    console.log(result);
                });
                ws.call('wamp.registration.count_callees', res.argsList[1], function (result) {
                    console.log('Received RPC wamp.registration.count_callees result!');
                    console.log(result);
                });
            }
        }).subscribe('wamp.registration.on_unregister', {
            onEvent: function (res) {
                console.log('Received wamp.registration.on_unregister message!');
                console.log(res);
            }
        }).subscribe('wamp.registration.on_delete', {
            onSuccess: function () {
                global.setTimeout(function () {
                    ws.call('wamp.session.count', null, function (result) {
                        console.log('Received RPC wamp.session.count result!');
                        console.log(result);
                    });
                    ws.call('wamp.session.list', null, function (result) {
                        console.log('Received RPC wamp.session.list result!');
                        console.log(result);

                        ws.call('wamp.session.get', result.argsList[0], function (result) {
                            console.log('Received RPC wamp.session.get result!');
                            console.log(result);
                        });
                    });
                }, 5000);
            },
            onEvent: function (res) {
                console.log('Received wamp.registration.on_delete message!');
                console.log(res);
            }
        });

    },
    onClose: function () {
        console.log('+' + (Date.now() - d) + 'ms: Connection to WAMP server closed!');
    },
    onError: function (err) { console.log('Breakdown happened! ', err); },
    onReconnect: function () { console.log('Reconnecting...'); },
    onReconnectSuccess: function () { console.log('Reconnection succeeded...'); }
});
