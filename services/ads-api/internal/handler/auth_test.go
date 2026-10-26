package handler

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"testing"
	"time"
)

func testAccessToken(secret, subject, role string, expires int64) string {
	header := base64.RawURLEncoding.EncodeToString([]byte(`{"alg":"HS256","typ":"JWT"}`))
	payload := base64.RawURLEncoding.EncodeToString([]byte(
		fmt.Sprintf(`{"sub":%q,"role":%q,"roles":[%q],"permissions":["moderation.review"],"token_version":1,"sid":"session-1","jti":"token-1","iat":%d,"typ":"access","iss":"ad-platform-auth","aud":"ad-platform","exp":%d}`, subject, role, role, expires-3600, expires),
	))
	mac := hmac.New(sha256.New, []byte(secret))
	_, _ = mac.Write([]byte(header + "." + payload))
	signature := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	return header + "." + payload + "." + signature
}

func TestParseAccessToken(t *testing.T) {
	now := time.Unix(1_800_000_000, 0).UTC()
	token := testAccessToken("shared-secret", "42", "admin", now.Add(time.Hour).Unix())
	principal, ok := parseAccessToken(token, "shared-secret", now)
	if !ok || principal.UserID != 42 || principal.Role != "admin" {
		t.Fatalf("unexpected principal: %#v ok=%v", principal, ok)
	}
	if _, ok := parseAccessToken(token, "wrong-secret", now); ok {
		t.Fatal("token with invalid signature must be rejected")
	}
	expired := testAccessToken("shared-secret", "42", "admin", now.Add(-time.Second).Unix())
	if _, ok := parseAccessToken(expired, "shared-secret", now); ok {
		t.Fatal("expired token must be rejected")
	}
	moderator := testAccessToken("shared-secret", "42", "moderator", now.Add(time.Hour).Unix())
	moderatorPrincipal, ok := parseAccessToken(moderator, "shared-secret", now)
	if !ok || !moderatorPrincipal.HasPermission("moderation.review") {
		t.Fatal("permission-bearing moderator token must be accepted")
	}
}
