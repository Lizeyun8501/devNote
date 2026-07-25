FROM golang:1.25-alpine AS builder

RUN apk add --no-cache build-base git

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

# 使用静态链接构建以减少运行时依赖（CGO_DISABLED）
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o /sync-server ./cmd/server

FROM alpine:3.19

RUN apk add --no-cache ca-certificates tzdata

# S9: 创建非 root 用户运行服务，减少容器逃逸攻击面
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

COPY --from=builder /sync-server /app/sync-server

RUN mkdir -p /app/data && chown -R appuser:appgroup /app

USER appuser

EXPOSE 8080

CMD ["/app/sync-server"]
