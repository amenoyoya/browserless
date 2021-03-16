#!/bin/bash

cd $(dirname $0)

export USER_ID="${USER_ID:-$UID}"
export STAGE=local
export DOMAINS=$(cat config | tr '\n' ',' | sed 's/,$//')

case "$1" in
"init")
    mkdir -p ./docker/node/
    mkdir -p ./server/
    tee ./docker/node/Dockerfile << \EOS
FROM mcr.microsoft.com/playwright

# Docker実行ユーザIDを build-arg から取得
ARG USER_ID

RUN if [ "$USER_ID" = "" ] || [ "$USER_ID" = "0" ]; then USER_ID=1026; fi && \
    : '日本語対応' && \
    apt-get update && \
    apt-get -y install locales fonts-ipafont fonts-ipaexfont && \
    echo "ja_JP UTF-8" > /etc/locale.gen && locale-gen && \
    : 'install Google Chrome: /usr/bin/google-chrome' && \
    apt-get install -y wget curl git vim && \
    wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && \
    apt-get install -y ./google-chrome-stable_current_amd64.deb && \
    : 'Add user (User ID: $USER_ID)' && \
    if [ "$(getent passwd $USER_ID)" != "" ]; then usermod -u $((USER_ID + 100)) "$(getent passwd $USER_ID | cut -f 1 -d ':')"; fi && \
    useradd -u $USER_ID -m -s /bin/bash worker && \
    apt-get install -y sudo && \
    echo "worker ALL=NOPASSWD: ALL" >> '/etc/sudoers' && \
    : 'Fix permission' && \
    mkdir -p /usr/local/share/.config/ && \
    chown -R worker /usr/local/share/.config/ && \
    : 'cleanup apt-get caches' && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 作業ディレクトリ: ./ => service://node:/work/
WORKDIR /work/

# 作業ユーザ: Docker実行ユーザ
## => コンテナ側のコマンド実行で作成されるファイルパーミッションをDocker実行ユーザ所有に
USER worker

# Startup script: install node_modules && npm run start
CMD ["/bin/bash", "-c", "yarn && yarn start"]
EOS
    tee ./.env << \EOS
NODE_PORT=8099
EOS
    tee ./.gitignore << \EOS
node_modules/
.env
EOS
    tee ./config << \EOS
browserless.localhost -> http://node:8099
EOS
    tee ./docker-compose.yml << \EOS
# ver 3.6 >= required: enable '-w' option for 'docker-compose exec'
version: "3.8"

networks:
  # プロジェクト内仮想ネットワーク
  ## 同一ネットワーク内の各コンテナはサービス名で双方向通信可能
  appnet:
    driver: bridge
    # ネットワークIP範囲を指定する場合
    # ipam:
    #   driver: default
    #   config:
    #     # 仮想ネットワークのネットワーク範囲を指定
    #     ## 172.68.0.0/16 の場合、172.68.0.1 ～ 172.68.255.254 のIPアドレスを割り振れる
    #     ## ただし 172.68.0.1 はゲートウェイに使われる
    #     - subnet: 172.68.0.0/16

services:
  # node service container: mcr.microsoft.com/playwright (node:14)
  node:
    build:
      context: ./docker/node/
      args:
        # use current working user id
        USER_ID: $USER_ID
    logging:
      driver: json-file
    networks:
      - appnet
    ports:
      # http://localhost:{NODE_PORT} => http://node:8099
      - "${NODE_PORT:-8099}:8099"
    # enable terminal
    tty: true
    volumes:
      # ./ => docker:/work/
      - ./:/work/
    environment:
      TZ: Asia/Tokyo
      # playwright インストール時にブラウザダウンロードをスキップ
      PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD: 1

  # proxy service container: https proxy server (nginx) 
  proxy:
    image: steveltn/https-portal:1
    logging:
      driver: json-file
    # 所属ネットワーク
    network_mode: host
    ports:
      - '80:80'
      - '443:443'
    volumes:
      - /var/run/docker.sock/:/tmp/docker.sock/:ro
    environment:
      STAGE: "${STAGE:-local}" # 本番環境の場合は production を指定（実際の Let's Encrypt に SSL 申請を行う）
      DOMAINS: "$DOMAINS" # 'domain -> http://port-forward, ...'
      WEBSOCKET: "true" # WebSocket接続を許可
EOS
    tee ./package.json << \EOS
{
  "dependencies": {
    "dotenv": "^8.2.0",
    "express": "^4.17.1",
    "http-proxy": "^1.18.1",
    "playwright": "^1.8.0",
    "query-string": "^6.14.1"
  },
  "scripts": {
    "start": "node server/index.js"
  }
}
EOS
    tee ./server/index.js << \EOS
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
EOS
    ;;
"set-stage")
    sed -i "s/^export STAGE=.*/export STAGE=${2:-local}/" ./x
    ;;
"set-domain")
    tee ./config << EOS
${2:-browserless.localhost} -> http://node:8099
EOS
    ;;
"node")
    if [ "$w" != "" ]; then
        docker-compose exec -w "/work/$w" node ${@:2:($#-1)}
    else
        docker-compose exec node ${@:2:($#-1)}
    fi
    ;;
*)
    docker-compose $*
    ;;
esac