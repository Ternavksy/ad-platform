package service

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"github.com/rabbitmq/amqp091-go"
)

type RabbitMQService struct {
	conn    *amqp091.Connection
	channel *amqp091.Channel
}

func NewRabbitMQService(url string) (*RabbitMQService, error) {
	conn, err := amqp091.Dial(url)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to RabbitMQ: %w", err)
	}

	ch, err := conn.Channel()
	if err != nil {
		return nil, fmt.Errorf("failed to open channel: %w", err)
	}

	err = ch.ExchangeDeclare(
		"ad_events",
		"topic",
		true,
		false,
		false,
		false,
		nil,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to declare exchange: %w", err)
	}

	return &RabbitMQService{
		conn:    conn,
		channel: ch,
	}, nil
}

func (r *RabbitMQService) PublishAdCreated(ctx context.Context, adID string) error {
	event := map[string]interface{}{
		"type":    "ad_created",
		"ad_id":   adID,
		"created": time.Now().Format(time.RFC3339),
	}

	body, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("failed to marshal event: %w", err)
	}

	err = r.channel.PublishWithContext(ctx,
		"ad_events",
		"ad.created",
		false,
		false,
		amqp091.Publishing{
			ContentType: "application/json",
			Body:        body,
		})
	if err != nil {
		return fmt.Errorf("failed to publish message: %w", err)
	}

	log.Printf("Published ad_created event for ad %s", adID)
	return nil
}

func (r *RabbitMQService) PublishAdUpdated(ctx context.Context, adID string) error {
	event := map[string]interface{}{
		"type":    "ad_updated",
		"ad_id":   adID,
		"updated": time.Now().Format(time.RFC3339),
	}

	body, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("failed to marshal event: %w", err)
	}

	err = r.channel.PublishWithContext(ctx,
		"ad_events",
		"ad.updated",
		false,
		false,
		amqp091.Publishing{
			ContentType: "application/json",
			Body:        body,
		})
	if err != nil {
		return fmt.Errorf("failed to publish message: %w", err)
	}

	log.Printf("Published ad_updated event for ad %s", adID)
	return nil
}

func (r *RabbitMQService) Close() error {
	if err := r.channel.Close(); err != nil {
		return fmt.Errorf("failed to close channel: %w", err)
	}
	if err := r.conn.Close(); err != nil {
		return fmt.Errorf("failed to close connection: %w", err)
	}
	return nil
}
