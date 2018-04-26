/**
 * Project: wiola
 * User: KSDaemon
 * Date: 21.10.16
 */

const Wampy = require('wampy').Wampy;
const wampyCra = require('wampy-cra');
const w3cws = require('websocket').w3cwebsocket;
let ws, d = Date.now();

console.log('0: Initializing wampy and connecting to server...');

ws = new Wampy('ws://webxp/ws/', {
    debug: false,
    ws: w3cws,
    realm: 'test',
    authid: 'user1',
    authmethods: ['wampcra'],
    onChallenge: (method, info) => {
        console.log('Requested challenge with ', method, info);
        return wampyCra.sign('secret1', info.challenge);
    },
    onConnect: function () {
        console.log('+' + (Date.now() - d) + 'ms: Yahoo! We are online!');
        ws.subscribe('message.received', {
           onSuccess: function () {
               console.log('+' + (Date.now() - d) + 'ms: Successfully subscribed to topic');
               global.setTimeout(function () {
                   ws.publish('message.received', ['New message'], null, { exclude_me: false });
               }, 5000);
           },
           onError: function (err) { console.log('+' + (Date.now() - d) + 'ms: Subscription error:' + err); },
           onEvent: function (res) {
               console.log('+' + (Date.now() - d) + 'ms: Received new message!');
               console.log('+' + (Date.now() - d) + 'ms: Closing connection...');
               ws.disconnect();
           }
        });

    },
    onClose: function () {
        console.log('+' + (Date.now() - d) + 'ms: Connection to WAMP server closed!');
    },
    onError: function () { console.log('Breakdown happened'); },
    onReconnect: function () { console.log('Reconnecting...'); },
    onReconnectSuccess: function () { console.log('Reconnection succeeded...'); }
});
