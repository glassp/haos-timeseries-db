// Preloaded into DbGate (NODE_OPTIONS=--require): it has no setting for the
// listen address and would otherwise be reachable by every add-on, bypassing
// Home Assistant's ingress authentication. nginx proxies ingress to it.
const net = require('net');

const listen = net.Server.prototype.listen;
net.Server.prototype.listen = function (...args) {
  if (typeof args[0] === 'number' || (typeof args[0] === 'string' && /^\d+$/.test(args[0]))) {
    const callback = args.find((arg) => typeof arg === 'function');
    return listen.call(this, { port: Number(args[0]), host: '127.0.0.1' }, callback);
  }
  return listen.apply(this, args);
};
