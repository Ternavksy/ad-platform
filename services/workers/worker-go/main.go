package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/rabbitmq/amqp091-go"
)

type AdEventWorker struct {
	conn    *amqp091.Connection
	channel *amqp091.Channel
}

func NewAdEventWorker(rabbitmqURL string) (*AdEventWorker, error) {
	conn, err := amqp091.Dial(rabbitmqURL)
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

	_, err = ch.QueueDeclare(
		"ad_worker_queue",
		true,
		false,
		false,
		false,
		nil,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to declare queue: %w", err)
	}

	err = ch.QueueBind(
		"ad_worker_queue",
		"ad.created",
		"ad_events",
		false,
		nil,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to bind queue for ad.created: %w", err)
	}

	err = ch.QueueBind(
		"ad_worker_queue",
		"ad.updated",
		"ad_events",
		false,
		nil,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to bind queue for ad.updated: %w", err)
	}

	return &AdEventWorker{
		conn:    conn,
		channel: ch,
	}, nil
}

func (w *AdEventWorker) Start() error {
	err := w.channel.Qos(
		1,
		0,
		false,
	)
	if err != nil {
		return fmt.Errorf("failed to set QoS: %w", err)
	}

	msgs, err := w.channel.Consume(
		"ad_worker_queue",
		"",
		false,
		false,
		false,
		false,
		nil,
	)
	if err != nil {
		return fmt.Errorf("failed to register consumer: %w", err)
	}

	log.Println("Starting Go worker...")

	go func() {
		sigChan := make(chan os.Signal, 1)
		signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
		<-sigChan
		log.Println("Worker stopped by user")
		w.Stop()
		os.Exit(0)
	}()

	for d := range msgs {
		w.processMessage(d)
	}

	return nil
}

func (w *AdEventWorker) processMessage(d amqp091.Delivery) {
	log.Printf("Processing message: %s", string(d.Body))

	var data map[string]interface{}
	err := json.Unmarshal(d.Body, &data)
	if err != nil {
		log.Printf("Failed to decode message: %v", err)
		d.Nack(false, false)
		return
	}

	eventType := data["type"].(string)

	switch eventType {
	case "ad_created":
		w.handleAdCreated(data)
	case "ad_updated":
		w.handleAdUpdated(data)
	default:
		log.Printf("Unknown event type: %s", eventType)
	}

	err = d.Ack(false)
	if err != nil {
		log.Printf("Failed to acknowledge message: %v", err)
	}
}

func (w *AdEventWorker) handleAdCreated(data map[string]interface{}) {
	adID := data["ad_id"].(string)
	log.Printf("Go Worker: Processing ad_created event for ad %s", adID)

	time.Sleep(100 * time.Millisecond)

	log.Printf("Go Worker: Completed processing ad_created event for ad %s", adID)
}

func (w *AdEventWorker) handleAdUpdated(data map[string]interface{}) {
	adID := data["ad_id"].(string)
	log.Printf("Go Worker: Processing ad_updated event for ad %s", adID)

	time.Sleep(100 * time.Millisecond)

	log.Printf("Go Worker: Completed processing ad_updated event for ad %s", adID)
}

func (w *AdEventWorker) Stop() {
	if w.channel != nil {
		w.channel.Close()
	}
	if w.conn != nil {
		w.conn.Close()
	}
	log.Println("Go Worker stopped")
}

func main() {
	rabbitmqURL := os.Getenv("RABBITMQ_URL")
	if rabbitmqURL == "" {
		rabbitmqURL = "amqp://guest:guest@rabbitmq:5672/"
	}

	for {
		conn, err := amqp091.Dial("amqp://guest:guest@rabbitmq:5672/")
		if err == nil {
			conn.Close()
			break
		}

		log.Println("Waiting for RabbitMQ...")
		time.Sleep(5 * time.Second)
	}

	worker, err := NewAdEventWorker(rabbitmqURL)
	if err != nil {
		log.Fatalf("Failed to create worker: %v", err)
	}
	defer worker.Stop()

	if err := worker.Start(); err != nil {
		log.Fatalf("Worker failed: %v", err)
	}
}
