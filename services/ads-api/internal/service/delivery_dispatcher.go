package service

import (
	"ads-api/internal/store"
	"context"
	"log"
	"time"
)

type DeliveryDispatcher struct {
	store    *store.DeliveryStore
	rabbitmq *RabbitMQService
	interval time.Duration
}

func NewDeliveryDispatcher(s *store.DeliveryStore, rabbitmq *RabbitMQService) *DeliveryDispatcher {
	return &DeliveryDispatcher{store: s, rabbitmq: rabbitmq, interval: 500 * time.Millisecond}
}

func (d *DeliveryDispatcher) Run(ctx context.Context) {
	if d.rabbitmq == nil {
		log.Print("Delivery outbox dispatcher disabled: RabbitMQ is unavailable")
		return
	}
	ticker := time.NewTicker(d.interval)
	defer ticker.Stop()
	for {
		d.dispatch(ctx)
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

func (d *DeliveryDispatcher) dispatch(ctx context.Context) {
	events, err := d.store.ListPendingEvents(ctx, 100)
	if err != nil {
		if ctx.Err() == nil {
			log.Printf("Failed to read delivery outbox: %v", err)
		}
		return
	}
	for _, event := range events {
		if err := d.rabbitmq.PublishDeliveryEvent(ctx, event); err != nil {
			if ctx.Err() == nil {
				log.Printf("Failed to publish delivery event %s: %v", event.ID, err)
			}
			return
		}
		if err := d.store.MarkPublished(ctx, event.ID, time.Now().UTC()); err != nil {
			if ctx.Err() == nil {
				log.Printf("Failed to mark delivery event %s as published: %v", event.ID, err)
			}
			return
		}
	}
}
