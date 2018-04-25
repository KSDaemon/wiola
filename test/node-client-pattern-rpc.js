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
    //debug: true,
    autoReconnect: false,
    ws: w3cws,
    realm: 'test',
    onConnect() {
        console.log('+' + (Date.now() - d) + 'ms: Yahoo! We are online!');

        ws.register('a1.b2..d4.e5', (e) => {
                console.log('Received "a1.b2..d4.e5" RPC invocation: ', e);
            }, { match: 'wildcard' });

        ws.register('a1.b2.c3..e5', (e) => {
                console.log('Received "a1.b2.c3..e5" RPC invocation: ', e);
            }, { match: 'wildcard' });

        ws.register('a1.b2..d4.e5..g7', (e) => {
                console.log('Received "a1.b2..d4.e5..g7" RPC invocation: ', e);
            }, { match: 'wildcard' });

        ws.register('a1.b2..d4..f6.g7', (e) => {
                console.log('Received "a1.b2..d4..f6.g7" RPC invocation: ', e);
            }, { match: 'wildcard' });

        ws.register('a1.b2..d4.e5..g7.h8', (e) => {
                console.log('Received "a1.b2..d4.e5..g7.h8" RPC invocation: ', e);
            }, { match: 'wildcard' });

        global.setTimeout(() => {
            ws.call('a1.b2.c3.d4.e5', ['Payload'], {
                onSuccess: (e) => {
                    console.log('Results for "a1.b2.c3.d4.e5" call: ', e);
                },
                onError: (e) => {
                    console.log('Error in "a1.b2.c3.d4.e5" call: ', e);
                }
            } , { exclude_me: false });
            ws.call('a1.b2.c88.d4.e5.f6.g7', ['Payload'], {
                onSuccess: (e) => {
                    console.log('Results for "a1.b2.c88.d4.e5.f6.g7" call', e);
                },
                onError: (e) => {
                    console.log('Error in "a1.b2.c88.d4.e5.f6.g7" call: ', e);
                }
            }, { exclude_me: false });
        }, 5000);

    },
    onClose() {
        console.log('+' + (Date.now() - d) + 'ms: Connection to WAMP server closed!');
    },
    onError(err) { console.log('Breakdown happened! ', err); },
    onReconnect() { console.log('Reconnecting...'); },
    onReconnectSuccess() { console.log('Reconnection succeeded...'); }
});
