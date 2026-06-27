FROM golang:1.25-alpine AS builder

RUN apk add --no-cache gcc musl-dev

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=1 GOOS=linux go build -o /business-server ./cmd/server

FROM alpine:3.19

RUN apk add --no-cache ca-certificates tzdata

# S9: 创建非 root 用户运行服务，减少容器逃逸攻击面
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

COPY --from=builder /business-server /app/business-server

RUN mkdir -p /app/data && chown -R appuser:appgroup /app

USER appuser

EXPOSE 8081

CMD ["/app/business-server"]