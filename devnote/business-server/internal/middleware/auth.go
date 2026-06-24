package middleware

import (
	"net/http"
	"strings"

	"github.com/devnote/business-server/internal/model"
	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

// JWT 常量 —— 与 sync-server 的签发逻辑对齐
//
// P1-3 修复: 统一 claim 结构和验证逻辑。
// sync-server 签发时设置:
//   - iss = "devnote-sync-server"
//   - aud = ["devnote-client", "devnote-business-server"]
// business-server 验证时校验:
//   - iss 必须为 "devnote-sync-server"（防止其他服务签发的 token 被误用）
//   - aud 必须包含 "devnote-business-server"（确认 token 是签发给本服务的）
//   - 签名算法必须为 HS256（与 sync-server 签发算法一致）
const (
	jwtIssuer   = "devnote-sync-server"
	jwtAudience = "devnote-business-server"
)

// JWTAuth 返回一个 Gin 中间件，校验 JWT 并提取用户身份。
//
// P1-3 修复:
// - 原实现使用 jwt.MapClaims 动态读取字段，不校验 iss/aud
// - 现改为类型化 model.Claims，与 sync-server 对齐
// - 增加 iss/aud 校验，防止跨服务 token 重用
// - 限制签名算法为 HS256（原实现接受任何 HMAC 变体）
func JWTAuth(secret string) gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"code":    401,
				"message": "missing authorization header",
			})
			return
		}

		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || !strings.EqualFold(parts[0], "bearer") {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"code":    401,
				"message": "invalid authorization header format",
			})
			return
		}

		tokenString := parts[1]

		// 使用类型化 Claims 解析，校验 iss/aud，限制签名算法为 HS256
		token, err := jwt.ParseWithClaims(tokenString, &model.Claims{}, func(t *jwt.Token) (interface{}, error) {
			// 仅接受 HS256，与 sync-server 签发算法一致
			if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, jwt.ErrSignatureInvalid
			}
			return []byte(secret), nil
		},
			jwt.WithIssuer(jwtIssuer),
			jwt.WithAudience(jwtAudience),
			jwt.WithValidMethods([]string{"HS256"}),
		)

		if err != nil || !token.Valid {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"code":    401,
				"message": "invalid or expired token",
			})
			return
		}

		claims, ok := token.Claims.(*model.Claims)
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"code":    401,
				"message": "invalid token claims",
			})
			return
		}

		// 优先使用标准 Subject 字段（sync-server generateToken 已设置 Subject = user.ID）
		// 回退到自定义 user_id 字段以兼容旧 token
		userID := claims.Subject
		if userID == "" {
			userID = claims.UserID
		}
		if userID == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"code":    401,
				"message": "token missing user identity",
			})
			return
		}

		c.Set("user_id", userID)
		if claims.Username != "" {
			c.Set("username", claims.Username)
		}
		c.Next()
	}
}
