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
|_ .env # Dockerコンテナ実行ポート等の環境変数設定
|_ docker-compose.yml # Docker構成設定
|_ x # Docker環境構成・各種操作用スクリプト
```

### Docker containers
- networks:
    - **appnet**: `local`
        - All docker containers in this project will be belonged to this network
- services:
    - **node**: `mcr.microsoft.com/playwright` (Node.js 14.x)
        - Node.js service container
        - http://localhost:{NODE_PORT:-8099} => http://node:8099

### Launch docker containers
```bash
# Build up docker containers
$ ./x build

# Launch docker containers
$ ./x up -d
```
