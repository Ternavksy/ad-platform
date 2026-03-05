package store

import (
	"context"
	"fmt"
	"time"

	"github.com/tarantool/go-tarantool/v2"
)

type TarantoolStore struct {
	conn *tarantool.Connection
}

func NewTarantoolStore(dsn string) (*TarantoolStore, error) {
	ctx := context.Background()
	dialer := tarantool.NetDialer{
		Address:  dsn,
		User:     "guest",
		Password: "",
	}
	opts := tarantool.Opts{
		Timeout: 5 * time.Second,
	}

	conn, err := tarantool.Connect(ctx, dialer, opts)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to Tarantool: %w", err)
	}

	return &TarantoolStore{conn: conn}, nil
}

func (s *TarantoolStore) Close() error {
	return s.conn.Close()
}

func (s *TarantoolStore) SetCampaign(ctx context.Context, campaignID int64, data []byte) error {
	req := tarantool.NewReplaceRequest("campaigns").
		Tuple([]interface{}{campaignID, data})

	_, err := s.conn.Do(req).Get()
	return err
}

func (s *TarantoolStore) GetCampaign(ctx context.Context, campaignID int64) ([]byte, error) {
	req := tarantool.NewSelectRequest("campaigns").
		Index("primary").
		Limit(1).
		Iterator(tarantool.IterEq).
		Key([]interface{}{campaignID})

	resp, err := s.conn.Do(req).Get()
	if err != nil {
		return nil, err
	}

	if len(resp) == 0 {
		return nil, nil
	}
	row := resp[0].([]interface{})

	data, ok := row[1].([]byte)
	if !ok {
		return nil, fmt.Errorf("invalid data format")
	}

	return data, nil
}

func (s *TarantoolStore) DeleteCampaign(ctx context.Context, campaignID int64) error {
	req := tarantool.NewDeleteRequest("campaigns").
		Index("primary").
		Key([]interface{}{campaignID})

	_, err := s.conn.Do(req).Get()
	return err
}

func (s *TarantoolStore) SetAd(ctx context.Context, adID int64, data []byte) error {
	req := tarantool.NewReplaceRequest("ads").
		Tuple([]interface{}{adID, data})
	_, err := s.conn.Do(req).Get()
	return err
}

func (s *TarantoolStore) GetAd(ctx context.Context, adID int64) ([]byte, error) {
	req := tarantool.NewSelectRequest("ads").
		Index("primary").
		Offset(0).
		Limit(1).
		Iterator(tarantool.IterEq).
		Key([]interface{}{adID})

	resp, err := s.conn.Do(req).Get()
	if err != nil {
		return nil, err
	}

	if len(resp) == 0 {
		return nil, nil
	}

	return resp[0].([]interface{})[1].([]byte), nil
}

func (s *TarantoolStore) DeleteAd(ctx context.Context, adID int64) error {
	req := tarantool.NewDeleteRequest("ads").
		Index("primary").
		Key([]interface{}{adID})

	_, err := s.conn.Do(req).Get()
	return err
}

func (s *TarantoolStore) SetCreative(ctx context.Context, creativeID int64, data []byte) error {
	req := tarantool.NewReplaceRequest("creatives").
		Tuple([]interface{}{creativeID, data})

	_, err := s.conn.Do(req).Get()
	return err
}

func (s *TarantoolStore) GetCreative(ctx context.Context, creativeID int64) ([]byte, error) {
	req := tarantool.NewSelectRequest("creatives").
		Index("primary").
		Offset(0).
		Limit(1).
		Iterator(tarantool.IterEq).
		Key([]interface{}{creativeID})

	resp, err := s.conn.Do(req).Get()
	if err != nil {
		return nil, err
	}

	if len(resp) == 0 {
		return nil, nil
	}

	return resp[0].([]interface{})[1].([]byte), nil
}

func (s *TarantoolStore) DeleteCreative(ctx context.Context, creativeID int64) error {
	req := tarantool.NewDeleteRequest("creatives").
		Index("primary").
		Key([]interface{}{creativeID})

	_, err := s.conn.Do(req).Get()
	return err
}

func (s *TarantoolStore) SetSession(ctx context.Context, sessionID string, data []byte, ttl time.Duration) error {
	expireAt := time.Now().Add(ttl).Unix()

	req := tarantool.NewReplaceRequest("sessions").
		Tuple([]interface{}{sessionID, data, expireAt})

	_, err := s.conn.Do(req).Get()
	return err
}

func (s *TarantoolStore) GetSession(ctx context.Context, sessionID string) ([]byte, error) {
	req := tarantool.NewSelectRequest("sessions").
		Index("primary").
		Offset(0).
		Limit(1).
		Iterator(tarantool.IterEq).
		Key([]interface{}{sessionID})

	resp, err := s.conn.Do(req).Get()
	if err != nil {
		return nil, err
	}

	if len(resp) == 0 {
		return nil, nil
	}

	return resp[0].([]interface{})[1].([]byte), nil
}

func (s *TarantoolStore) DeleteSession(ctx context.Context, sessionID string) error {
	req := tarantool.NewDeleteRequest("sessions").
		Index("primary").
		Key([]interface{}{sessionID})

	_, err := s.conn.Do(req).Get()
	return err
}

func (s *TarantoolStore) IncrementRateLimit(ctx context.Context, key string, window time.Duration) (int64, error) {
	expireAt := time.Now().Add(window).Unix()

	req := tarantool.NewCallRequest("increment_rate_limit").
		Args([]interface{}{key, expireAt})

	resp, err := s.conn.Do(req).Get()
	if err != nil {
		return 0, err
	}

	if len(resp) > 0 {
		if count, ok := resp[0].(int64); ok {
			return count, nil
		}
	}

	return 0, nil
}

func (s *TarantoolStore) TrackUserActivity(ctx context.Context, userID int64, action string) error {
	timestamp := time.Now().Unix()

	req := tarantool.NewInsertRequest("user_activity").
		Tuple([]interface{}{userID, action, timestamp})

	_, err := s.conn.Do(req).Get()
	return err
}

func (s *TarantoolStore) GetUserActivity(ctx context.Context, userID int64, limit int) ([]map[string]interface{}, error) {
	req := tarantool.NewSelectRequest("user_activity").
		Index("user_id").
		Offset(0).
		Limit(uint32(limit)).
		Iterator(tarantool.IterEq).
		Key([]interface{}{userID})

	resp, err := s.conn.Do(req).Get()
	if err != nil {
		return nil, err
	}

	var activities []map[string]interface{}
	for _, row := range resp {
		if rowData, ok := row.([]interface{}); ok && len(rowData) >= 3 {
			activity := map[string]interface{}{
				"user_id":   rowData[0],
				"action":    rowData[1],
				"timestamp": rowData[2],
			}
			activities = append(activities, activity)
		}
	}

	return activities, nil
}
