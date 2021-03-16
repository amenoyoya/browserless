# browserless

⚡ Web browser automation server, like https://browserless.io

## Environment

- Shell: `bash`
- Docker: `19.03.12`
    - docker-compose: `1.26.0`

```bash
# Add execution permission to the CLI tool
$ chmod +x ./x

# Generate docker template
$ ./x init
```

### Structure
```bash
./ # mount to => service://node:/work/
|_ docker/ # Dockerコンテナ設定
|  |_ node/ # node service container
|     |_ Dockerfile # node service container build setting file
|
|_ server/
|  |_ index.js # Browserless server: http://node:8099
|
|_ .env # Dockerコンテナ実行ポート等の環境変数設定
|_ docker-compose.yml # Docker構成設定
|_ package.json # Node.js package settings
|_ x # Docker環境構成・各種操作用スクリプト
```

### Docker containers
- networks:
    - **appnet**: `local`
        - All docker containers in this project will be belonged to this network
- services:
    - **node**: `mcr.microsoft.com/playwright` (Node.js 14.x)
        - Node.js service container
        - routes:
            - HTTP, WebSocket: http://localhost:{NODE_PORT:-8099} => http://node:8099
    - **proxy**: `steveltn/https-portal:1`
        - Nginx proxy server with Let's encrypt SSL certificator container.
        - routes:
            - HTTP: http://localhost => service://proxy:80
            - HTTPS: https://localhost => service://proxy:443

### Launch browserless server
```bash
# Build up docker containers
$ ./x build

# Launch `node` docker container: launch browserless server
$ ./x up -d node

# => Browserless server: http://localhost:{NODE_PORT:-8099}
```

***

## Tips

### 認証機能を付与したい場合
```bash
# .env に X_TOKEN 環境変数追加
$ tee -a ./.env << \EOS
X_TOKEN=8fa9a11f9dda130a5f83cc889915e3e0
EOS

# Restart server
$ ./x restart
```

上記設定で起動した Browserless server に接続したい場合は、`?x-token={X_TOKEN}` クエリを付与して接続する必要がある

```javascript
const {chromium} = require('playwright');

(async () => {
  // Playwright CDP Server 接続: x-token 指定
  const browser = await chromium.connect({
    wsEndpoint: 'http://localhost:8099?x-token=8fa9a11f9dda130a5f83cc889915e3e0'
  });
  // ブラウザ操作
  const page = await browser.newPage();
  await page.goto('https://www.google.com', {waitUntil: 'networkidle'});
  await page.screenshot({
    path: `${__dirname}/google.com.png`,
    fullPage: true,
  });
  browser.close();
})();
```

### 本番サーバで運用したい場合
```bash
# Set stage => production
$ ./x set-stage production

# Set domain => yourserver.com
$ ./x set-domain yourserver.com

# Launch all docker container: launch browserless server with nginx proxy server
$ ./x up -d

# Confirm `proxy` docker container: process of Let's Encrypt
$ ./x logs -f proxy

# => https://yourserver.com ~> http://node:8099
```