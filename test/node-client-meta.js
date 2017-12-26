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
            onEvent: function (arrayPayload, objectPayload) {
                console.log('Received wamp.session.on_join message!');
                console.log(arrayPayload);
                console.log(objectPayload);
            }
        }).subscribe('wamp.session.on_leave', {
            onEvent: function (arrayPayload, objectPayload) {
                console.log('Received wamp.session.on_leave message!');
                console.log(arrayPayload);
                console.log(objectPayload);
            }
        }).subscribe('wamp.subscription.on_create', {
            onEvent: function (arrayPayload, objectPayload) {
                console.log('Received wamp.subscription.on_create message!');
                console.log(arrayPayload);
                console.log(objectPayload);
            }
        }).subscribe('wamp.subscription.on_subscribe', {
            onEvent: function (arrayPayload, objectPayload) {
                console.log('Received wamp.subscription.on_subscribe message!');
                console.log(arrayPayload);
                console.log(objectPayload);
            }
        }).subscribe('wamp.subscription.on_unsubscribe', {
            onEvent: function (arrayPayload, objectPayload) {
                console.log('Received wamp.subscription.on_unsubscribe message!');
                console.log(arrayPayload);
                console.log(objectPayload);
            }
        }).subscribe('wamp.subscription.on_delete', {
            onEvent: function (arrayPayload, objectPayload) {
                console.log('Received wamp.subscription.on_delete message!');
                console.log(arrayPayload);
                console.log(objectPayload);
            }
        }).subscribe('wamp.registration.on_create', {
            onEvent: function (arrayPayload, objectPayload) {
                console.log('Received wamp.registration.on_create message!');
                console.log(arrayPayload);
                console.log(objectPayload);
            }
        }).subscribe('wamp.registration.on_register', {
            onEvent: function (arrayPayload, objectPayload) {
                console.log('Received wamp.registration.on_register message!');
                console.log(arrayPayload);
                console.log(objectPayload);
            }
        }).subscribe('wamp.registration.on_unregister', {
            onEvent: function (arrayPayload, objectPayload) {
                console.log('Received wamp.registration.on_unregister message!');
                console.log(arrayPayload);
                console.log(objectPayload);
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
            onEvent: function (arrayPayload, objectPayload) {
                console.log('Received wamp.registration.on_delete message!');
                console.log(arrayPayload);
                console.log(objectPayload);
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
