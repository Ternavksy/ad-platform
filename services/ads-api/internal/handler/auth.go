package handler

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

const principalKey = "auth_principal"

type Principal struct {
	UserID int64
	Role   string
}

type jwtHeader struct {
	Algorithm string `json:"alg"`
}

type jwtClaims struct {
	Subject string `json:"sub"`
	Role    string `json:"role"`
	Expires int64  `json:"exp"`
}

func Authenticate(secret string) gin.HandlerFunc {
	return func(c *gin.Context) {
		value := strings.TrimSpace(c.GetHeader("Authorization"))
		parts := strings.SplitN(value, " ", 2)
		if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
			return
		}
		principal, ok := parseAccessToken(parts[1], secret, time.Now().UTC())
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid access token"})
			return
		}
		c.Set(principalKey, principal)
		c.Next()
	}
}

func RequireRole(role string) gin.HandlerFunc {
	return func(c *gin.Context) {
		principal, ok := CurrentPrincipal(c)
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
			return
		}
		if principal.Role != role {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "forbidden"})
			return
		}
		c.Next()
	}
}

func CurrentPrincipal(c *gin.Context) (Principal, bool) {
	value, exists := c.Get(principalKey)
	principal, ok := value.(Principal)
	return principal, exists && ok
}

func parseAccessToken(value, secret string, now time.Time) (Principal, bool) {
	parts := strings.Split(value, ".")
	if len(parts) != 3 || secret == "" {
		return Principal{}, false
	}
	headerBytes, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return Principal{}, false
	}
	var header jwtHeader
	if json.Unmarshal(headerBytes, &header) != nil || header.Algorithm != "HS256" {
		return Principal{}, false
	}
	providedSignature, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		return Principal{}, false
	}
	mac := hmac.New(sha256.New, []byte(secret))
	_, _ = mac.Write([]byte(parts[0] + "." + parts[1]))
	if !hmac.Equal(providedSignature, mac.Sum(nil)) {
		return Principal{}, false
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return Principal{}, false
	}
	var claims jwtClaims
	if json.Unmarshal(payload, &claims) != nil || claims.Expires <= now.Unix() {
		return Principal{}, false
	}
	userID, err := strconv.ParseInt(claims.Subject, 10, 64)
	if err != nil || userID <= 0 || (claims.Role != "user" && claims.Role != "admin") {
		return Principal{}, false
	}
	return Principal{UserID: userID, Role: claims.Role}, true
}
