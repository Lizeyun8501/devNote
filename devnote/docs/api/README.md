# DevNote API Documentation

DevNote provides two independent Go servers, each with its own set of RESTful API endpoints. This directory contains OpenAPI 3.0 specifications for both servers.

## Files

| File | Description |
|------|-------------|
| `sync-server-openapi.yaml` | OpenAPI spec for the **sync server** (auth + sync) |
| `business-server-openapi.yaml` | OpenAPI spec for the **business server** (metadata, tags, folders, knowledge graph, validation) |

## Server Overview

### Sync Server (`sync-server/`)

The sync server handles **user authentication** and **note synchronization** between devices.

- **Base URL:** `http://localhost:8080` (or HTTPS on `8443`)
- **Auth:** JWT Bearer token (via `Authorization: Bearer <token>` header)
- **Key endpoints:**
  - **Standard Auth:** `POST /api/v1/auth/{register,login,refresh,logout}`
  - **SRP Auth (zero-knowledge):** `POST /api/v1/auth/srp/{register,init,verify}`
  - **Sync Operations:** `POST /api/v1/sync/{push,pull}`, `GET /api/v1/sync/status`, `POST /api/v1/sync/resolve-conflict`
  - **Health/Metrics:** `GET /health`, `GET /metrics` (Prometheus)

### Business Server (`business-server/`)

The business server handles **note organization**, **knowledge graph**, and **validation**.

- **Base URL:** `http://localhost:8081`
- **Auth:** JWT Bearer token (same token as sync server)
- **Key endpoint groups:**
  - **Metadata:** `GET/POST/PUT/DELETE /api/v1/metadata` (CRUD + search/filter/batch)
  - **Tags:** `GET/POST/PUT/DELETE /api/v1/tags` (hierarchy, merge, split, note associations)
  - **Folders:** `GET/POST/PUT/DELETE /api/v1/folders` (tree, move, copy, path resolution)
  - **Knowledge Graph:** `GET/POST/DELETE /api/v1/knowledge/*` (relations, graph metrics, suggestions, shortest path)
  - **Validation:** `GET/POST/PUT/DELETE /api/v1/validate/*` (rule CRUD, entity validation)

## How to View the API Docs

### Option 1: Swagger UI (Browser)

1. **Online Swagger Editor** (no install required):
   - Visit [https://editor.swagger.io/](https://editor.swagger.io/)
   - Click **File > Import URL** and paste the raw GitHub URL of the spec file, or
   - Copy-paste the YAML content directly into the editor

2. **Run Swagger UI locally with Docker:**
   ```bash
   # Sync Server
   docker run -p 8080:8080 \
     -e SWAGGER_JSON=/spec/sync-server-openapi.yaml \
     -v $(pwd):/spec \
     swaggerapi/swagger-ui

   # Business Server
   docker run -p 8081:8080 \
     -e SWAGGER_JSON=/spec/business-server-openapi.yaml \
     -v $(pwd):/spec \
     swaggerapi/swagger-ui
   ```
   Then open `http://localhost:8080` or `http://localhost:8081` in your browser.

### Option 2: Redoc (Browser)

```bash
# Sync Server
docker run -p 8080:80 \
  -v $(pwd)/sync-server-openapi.yaml:/usr/share/nginx/html/openapi.yaml \
  redocly/redoc

# Business Server
docker run -p 8081:80 \
  -v $(pwd)/business-server-openapi.yaml:/usr/share/nginx/html/openapi.yaml \
  redocly/redoc
```

### Option 3: VS Code Extension

Install the **OpenAPI (Swagger) Editor** extension by 42Crunch in VS Code. Open any `.yaml` file and click the preview button in the top-right corner.

## How to Generate Client Code

### Using OpenAPI Generator (已配置)

项目已集成 openapi-generator，配置文件位于 `openapi-generator-config.yaml`，
生成脚本位于 `scripts/generate_api_client.sh`。

```bash
# 生成所有客户端（sync + business）
./scripts/generate_api_client.sh all

# 仅生成 sync-server 客户端
./scripts/generate_api_client.sh sync

# 仅生成 business-server 客户端
./scripts/generate_api_client.sh business
```

生成的 Dart 客户端位于 `lib/api/generated/`：
- `sync_server/` — 包名 `devnote_sync_api`，包含 SyncApi、AuthApi、SrpAuthApi
- `business_server/` — 包名 `devnote_business_api`，包含 MetadataApi、TagsApi、FoldersApi、KnowledgeApi、ValidationApi

通过 `lib/api/devnote_api_client.dart` 统一封装使用，自动注入 JWT 认证。

依赖：Java 17+（openapi-generator-cli 需要 JVM），通过 `npx @openapitools/openapi-generator-cli` 自动下载。

### Manual Generation (alternative)

Install [openapi-generator](https://openapi-generator.tech/) (requires Java):

```bash
# Generate TypeScript (Axios) client for sync server
openapi-generator-cli generate \
  -i sync-server-openapi.yaml \
  -g typescript-axios \
  -o ../generated/sync-client

# Generate TypeScript (Axios) client for business server
openapi-generator-cli generate \
  -i business-server-openapi.yaml \
  -g typescript-axios \
  -o ../generated/business-client
```

### Generate for other languages

Replace `-g` with the desired generator:

| Generator (`-g`) | Language |
|-----------------|----------|
| `python` | Python |
| `go` | Go (net/http) |
| `kotlin` | Kotlin |
| `swift5` | Swift |
| `dart` | Dart/Flutter |
| `rust` | Rust |
| `java` | Java |

Full list: `openapi-generator-cli list`

### Using Swagger Codegen

```bash
# Java-based Swagger Codegen
java -jar swagger-codegen-cli.jar generate \
  -i sync-server-openapi.yaml \
  -l typescript-angular \
  -o ../generated/sync-client
```

### Using Orval (for TypeScript + React Query)

```bash
npx orval --input sync-server-openapi.yaml --output ../generated/sync-client
```

## Response Format

Both servers use a consistent response format:

- **Success:** `{ "data": <payload> }` (business server wraps all responses in this format)
- **Error:** `{ "code": <int>, "message": <string>, "detail": <string>? }` (business server) or `{ "error": <string> }` (sync server)

## Authentication Flow

1. Register: `POST /api/v1/auth/register` (sync server)
2. Login: `POST /api/v1/auth/login` (sync server) -> returns `token` + `refresh_token`
3. Use the `token` as `Authorization: Bearer <token>` header for all protected endpoints
4. When the token expires (1 hour), use `POST /api/v1/auth/refresh` to get a new one
