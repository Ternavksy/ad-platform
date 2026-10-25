package service

import (
	"ads-api/internal/model"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/rabbitmq/amqp091-go"
)

type RabbitMQService struct {
	mu      sync.Mutex
	url     string
	conn    *amqp091.Connection
	channel *amqp091.Channel
}

func NewRabbitMQService(url string) (*RabbitMQService, error) {
	r := &RabbitMQService{url: url}
	r.mu.Lock()
	err := r.connectLocked()
	r.mu.Unlock()
	if err != nil {
		return nil, err
	}
	return r, nil
}

func (r *RabbitMQService) connectLocked() error {
	conn, err := amqp091.Dial(r.url)
	if err != nil {
		return fmt.Errorf("failed to connect to RabbitMQ: %w", err)
	}
	ch, err := conn.Channel()
	if err != nil {
		_ = conn.Close()
		return fmt.Errorf("failed to open channel: %w", err)
	}
	if err := ch.ExchangeDeclare("ad_events", "topic", true, false, false, false, nil); err != nil {
		_ = ch.Close()
		_ = conn.Close()
		return fmt.Errorf("failed to declare exchange: %w", err)
	}
	if err := ch.Confirm(false); err != nil {
		_ = ch.Close()
		_ = conn.Close()
		return fmt.Errorf("failed to enable publisher confirms: %w", err)
	}
	r.conn = conn
	r.channel = ch
	return nil
}

func (r *RabbitMQService) resetLocked() {
	if r.channel != nil {
		_ = r.channel.Close()
	}
	if r.conn != nil {
		_ = r.conn.Close()
	}
	r.channel = nil
	r.conn = nil
}

func (r *RabbitMQService) publish(ctx context.Context, routingKey string, event any) error {
	body, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("failed to marshal event: %w", err)
	}

	r.mu.Lock()
	defer r.mu.Unlock()
	var lastErr error
	for attempt := 0; attempt < 2; attempt++ {
		if r.channel == nil || r.conn == nil || r.conn.IsClosed() || r.channel.IsClosed() {
			r.resetLocked()
			if err := r.connectLocked(); err != nil {
				lastErr = err
				continue
			}
		}
		confirmation, err := r.channel.PublishWithDeferredConfirmWithContext(
			ctx, "ad_events", routingKey, false, false,
			amqp091.Publishing{
				ContentType:  "application/json",
				DeliveryMode: amqp091.Persistent,
				Body:         body,
			},
		)
		if err == nil {
			var confirmed bool
			confirmed, err = confirmation.WaitContext(ctx)
			if err == nil && confirmed {
				return nil
			}
			if err == nil {
				err = fmt.Errorf("RabbitMQ negatively acknowledged the message")
			}
		}
		lastErr = err
		r.resetLocked()
	}
	return fmt.Errorf("failed to publish message: %w", lastErr)
}

func (r *RabbitMQService) PublishAdCreated(ctx context.Context, adID string, campaignID int64) error {
	event := map[string]interface{}{
		"type":        "ad_created",
		"ad_id":       adID,
		"campaign_id": campaignID,
		"created":     time.Now().UTC().Format(time.RFC3339),
	}
	if err := r.publish(ctx, "ad.created", event); err != nil {
		return err
	}
	log.Printf("Published ad_created event for ad %s", adID)
	return nil
}

func (r *RabbitMQService) PublishAdUpdated(ctx context.Context, adID string, campaignID int64) error {
	event := map[string]interface{}{
		"type":        "ad_updated",
		"ad_id":       adID,
		"campaign_id": campaignID,
		"updated":     time.Now().UTC().Format(time.RFC3339),
	}
	if err := r.publish(ctx, "ad.updated", event); err != nil {
		return err
	}
	log.Printf("Published ad_updated event for ad %s", adID)
	return nil
}

func (r *RabbitMQService) PublishDeliveryEvent(ctx context.Context, event model.DeliveryEvent) error {
	routingKey := map[string]string{
		"ad_impression": "ad.impression",
		"ad_click":      "ad.click",
		"ad_conversion": "ad.conversion",
	}[event.EventType]
	if routingKey == "" {
		return fmt.Errorf("unsupported delivery event type %q", event.EventType)
	}
	return r.publish(ctx, routingKey, event)
}

func (r *RabbitMQService) Close() error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.resetLocked()
	return nil
}
