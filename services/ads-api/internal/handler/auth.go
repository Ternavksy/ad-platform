package handler

import (
	"context"
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
	UserID       int64
	Role         string
	Roles        []string
	Permissions  []string
	TokenVersion int
	SessionID    string
	MFA          bool
}

type jwtHeader struct {
	Algorithm string `json:"alg"`
}

type jwtClaims struct {
	Subject      string   `json:"sub"`
	Role         string   `json:"role"`
	Roles        []string `json:"roles"`
	Permissions  []string `json:"permissions"`
	TokenVersion int      `json:"token_version"`
	SessionID    string   `json:"sid"`
	MFA          bool     `json:"mfa"`
	Issuer       string   `json:"iss"`
	Audience     string   `json:"aud"`
	Type         string   `json:"typ"`
	JTI          string   `json:"jti"`
	IssuedAt     int64    `json:"iat"`
	Expires      int64    `json:"exp"`
}

type SecurityStateReader interface {
	UserSecurityState(ctx context.Context, userID int64) (string, int, error)
}

type SessionStateReader interface {
	SessionIsActive(ctx context.Context, userID int64, sessionID string) (bool, error)
}

func Authenticate(secret string, readers ...SecurityStateReader) gin.HandlerFunc {
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
		if len(readers) > 0 && readers[0] != nil {
			status, version, err := readers[0].UserSecurityState(c.Request.Context(), principal.UserID)
			if err != nil {
				c.AbortWithStatusJSON(http.StatusServiceUnavailable, gin.H{"error": "security state unavailable"})
				return
			}
			if status != "active" || version != principal.TokenVersion {
				c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "session has been revoked"})
				return
			}
			if sessions, ok := readers[0].(SessionStateReader); ok {
				if principal.SessionID == "" {
					c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "session is missing"})
					return
				}
				active, err := sessions.SessionIsActive(
					c.Request.Context(), principal.UserID, principal.SessionID,
				)
				if err != nil {
					c.AbortWithStatusJSON(http.StatusServiceUnavailable, gin.H{"error": "session state unavailable"})
					return
				}
				if !active {
					c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "session has been revoked"})
					return
				}
			}
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
		if !principal.HasRole(role) {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "forbidden"})
			return
		}
		c.Next()
	}
}

func RequirePermission(permission string) gin.HandlerFunc {
	return func(c *gin.Context) {
		principal, ok := CurrentPrincipal(c)
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
			return
		}
		if !principal.HasPermission(permission) {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "forbidden"})
			return
		}
		c.Next()
	}
}

func (p Principal) HasRole(role string) bool {
	if p.Role == role {
		return true
	}
	for _, value := range p.Roles {
		if value == role {
			return true
		}
	}
	return false
}

func (p Principal) HasPermission(permission string) bool {
	for _, value := range p.Permissions {
		if value == permission {
			return true
		}
	}
	return false
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
	if err != nil || userID <= 0 || claims.Type != "access" ||
		claims.Issuer != "ad-platform-auth" || claims.Audience != "ad-platform" {
		return Principal{}, false
	}
	if len(claims.Roles) == 0 && claims.Role != "" {
		claims.Roles = []string{claims.Role}
	}
	if len(claims.Roles) == 0 || claims.TokenVersion <= 0 || claims.SessionID == "" ||
		claims.JTI == "" || claims.IssuedAt <= 0 || claims.IssuedAt > now.Add(time.Minute).Unix() {
		return Principal{}, false
	}
	return Principal{
		UserID: userID, Role: claims.Role, Roles: claims.Roles,
		Permissions: claims.Permissions, TokenVersion: claims.TokenVersion,
		SessionID: claims.SessionID, MFA: claims.MFA,
	}, true
}
