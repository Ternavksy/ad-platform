package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"time"

	"github.com/jmoiron/sqlx"
	"github.com/redis/go-redis/v9"
)

type AuthorizationStore struct {
	db    *sqlx.DB
	redis *redis.Client
}

type cachedSecurityState struct {
	Status         string     `json:"status"`
	TokenVersion   int        `json:"token_version"`
	SuspendedUntil *time.Time `json:"suspended_until,omitempty"`
}

func NewAuthorizationStore(db *sqlx.DB, redisURL string) (*AuthorizationStore, error) {
	options, err := redis.ParseURL(redisURL)
	if err != nil {
		return nil, fmt.Errorf("parse Redis security-state URL: %w", err)
	}
	client := redis.NewClient(options)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if err := client.Ping(ctx).Err(); err != nil {
		_ = client.Close()
		return nil, fmt.Errorf("connect to Redis security-state cache: %w", err)
	}
	return &AuthorizationStore{db: db, redis: client}, nil
}

func securityStateKey(userID int64) string {
	return fmt.Sprintf("security:user:%d", userID)
}

func sessionStateKey(sessionID string) string {
	return "security:session:" + sessionID
}

func (s *AuthorizationStore) Close() error {
	return s.redis.Close()
}

func (s *AuthorizationStore) cacheState(ctx context.Context, userID int64, state cachedSecurityState) error {
	payload, err := json.Marshal(state)
	if err != nil {
		return err
	}
	return s.redis.Set(ctx, securityStateKey(userID), payload, time.Hour).Err()
}

func (s *AuthorizationStore) UserSecurityState(ctx context.Context, userID int64) (string, int, error) {
	value, err := s.redis.Get(ctx, securityStateKey(userID)).Result()
	if err == nil {
		var cached cachedSecurityState
		if json.Unmarshal([]byte(value), &cached) != nil || cached.Status == "" || cached.TokenVersion <= 0 {
			return "", 0, fmt.Errorf("invalid cached security state for user %d", userID)
		}
		if cached.Status != "suspended" || cached.SuspendedUntil == nil || cached.SuspendedUntil.After(time.Now().UTC()) {
			return cached.Status, cached.TokenVersion, nil
		}
		err = redis.Nil
	}
	if err != redis.Nil {
		return "", 0, fmt.Errorf("read Redis security state: %w", err)
	}

	var state struct {
		Status         string       `db:"status"`
		TokenVersion   int          `db:"token_version"`
		SuspendedUntil sql.NullTime `db:"suspended_until"`
	}
	if err := s.db.GetContext(ctx, &state, `
		SELECT status, token_version, suspended_until
		FROM users WHERE id = ?
	`, userID); err != nil {
		return "", 0, err
	}
	if state.Status == "suspended" && state.SuspendedUntil.Valid && !state.SuspendedUntil.Time.After(time.Now().UTC()) {
		if _, err := s.db.ExecContext(ctx, `
			UPDATE users SET status = 'active', suspended_until = NULL
			WHERE id = ? AND status = 'suspended' AND suspended_until <= ?
		`, userID, time.Now().UTC()); err != nil {
			return "", 0, err
		}
		state.Status = "active"
	}
	cached := cachedSecurityState{Status: state.Status, TokenVersion: state.TokenVersion}
	if state.SuspendedUntil.Valid {
		value := state.SuspendedUntil.Time.UTC()
		cached.SuspendedUntil = &value
	}
	if err := s.cacheState(ctx, userID, cached); err != nil {
		return "", 0, fmt.Errorf("populate Redis security state: %w", err)
	}
	return state.Status, state.TokenVersion, nil
}

func (s *AuthorizationStore) SessionIsActive(
	ctx context.Context,
	userID int64,
	sessionID string,
) (bool, error) {
	value, err := s.redis.Get(ctx, sessionStateKey(sessionID)).Result()
	if err == nil {
		if value != "active" && value != "revoked" {
			return false, fmt.Errorf("invalid cached session state")
		}
		return value == "active", nil
	}
	if err != redis.Nil {
		return false, fmt.Errorf("read Redis session state: %w", err)
	}
	var session struct {
		RevokedAt sql.NullTime `db:"revoked_at"`
		ExpiresAt time.Time    `db:"expires_at"`
	}
	if err := s.db.GetContext(ctx, &session, `
		SELECT revoked_at, expires_at
		FROM user_sessions WHERE id = ? AND user_id = ?
	`, sessionID, userID); err != nil {
		if err == sql.ErrNoRows {
			return false, nil
		}
		return false, err
	}
	active := !session.RevokedAt.Valid && session.ExpiresAt.After(time.Now().UTC())
	ttl := time.Until(session.ExpiresAt)
	if ttl < time.Minute {
		ttl = time.Minute
	}
	if err := s.redis.Set(
		ctx,
		sessionStateKey(sessionID),
		map[bool]string{true: "active", false: "revoked"}[active],
		ttl,
	).Err(); err != nil {
		return false, fmt.Errorf("populate Redis session state: %w", err)
	}
	return active, nil
}

func (s *AuthorizationStore) ApplyUserBlocked(
	ctx context.Context,
	userID int64,
	tokenVersion int,
) error {
	if _, err := s.db.ExecContext(ctx, `
		UPDATE campaigns SET status = 'paused'
		WHERE user_id = ? AND status = 'active'
	`, userID); err != nil {
		return fmt.Errorf("pause blocked user's campaigns: %w", err)
	}
	if err := s.cacheState(ctx, userID, cachedSecurityState{
		Status: "blocked", TokenVersion: tokenVersion,
	}); err != nil {
		return fmt.Errorf("cache blocked user security state: %w", err)
	}
	return nil
}
