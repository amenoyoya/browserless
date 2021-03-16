/**
 * スクレイピング専用サーバ（Chromeヘッドレスブラウザ実行サーバ）
 * https://www.browserless.io/ もどき
 */
const express = require('express');
const app = express();

const http = require('http').Server(app);
const proxy = require('http-proxy');

const {chromium} = require('playwright');
const qs = require('query-string');
 
/**
 * process.env form .env
 */
require('dotenv').config({path: `${__dirname}/../.env`});


// listen: http://localhost:8099/
const port = 8099;
const server = http.listen(port, () => {
  console.log(`Browserless server\nListening on: http://localhost:${port}/`);
});

/**
 * Playwright CDP Server
 */
(async () => {
  // Playwright ブラウザ操作サーバ起動
  const browserServer = await chromium.launchServer({
    executablePath: process.env.PLAYWRIGHT_EXECUTABLE_PATH || '/usr/bin/google-chrome',
    headless: true,
    logger: {
      isEnabled: (name, severity) => name === 'browser',
      log: (name, severity, message, args) => console.log(`${name} ${message}`),
    }
  });
  console.log('Playwright WebSocket:', browserServer.wsEndpoint());

  // Playwrightブラウザ操作サーバにアクセスを流すプロキシサーバ
  const playwright_socket_proxy = proxy.createProxyServer({
    target: browserServer.wsEndpoint(),
    ws: true, // WebSocket対応
    ignorePath: true, // パスを無視（ws://localhost:port/XXXX => ws://localhost:port/）
  });
  
  // / => ws://playwright.server:port/development-token/
  app.use('/', (req, res) => {
    playwright_socket_proxy.web(req, res);
  });
  
  // Socket通信イベントをリバースプロキシ
  server.on('upgrade', (req, socket, head) => {
    if (process.env.X_TOKEN) {
      // query parameter x-token による認証
      const params = qs.parseUrl(req.url);
      if (params.query['x-token'] !== process.env.X_TOKEN) {
        socket.write('HTTP/1.1 401 Web Socket Protocol Unauthorized\r\n');
        return socket.destroy();
      }
    }
    playwright_socket_proxy.ws(req, socket, head);
  });
})();