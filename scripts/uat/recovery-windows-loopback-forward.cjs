// Strictly local IPv6 frontend for Windows UAT while another session owns
// IPv4 port 4004. Preserves the app's fixed-port UAT network guard.
const net=require('node:net');
const server=net.createServer(client=>{
  const target=net.connect({host:'127.0.0.1',port:4005});
  client.pipe(target).pipe(client);
  const stop=()=>{client.destroy();target.destroy();};
  client.on('error',stop);target.on('error',stop);
});
server.listen({host:'::1',port:4004,ipv6Only:true},()=>console.log('Windows UAT forwarding [::1]:4004 to 127.0.0.1:4005 (loopback only).'));
process.on('SIGINT',()=>server.close());
process.on('SIGTERM',()=>server.close());
