package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/aws/aws-sdk-go-v2/service/sqs/types"
)

type Message struct {
	ID      string    `json:"id"`
	Content string    `json:"content"`
	Time    time.Time `json:"time"`
}

func main() {
	log.Println("Starting Worker-D...")

	// Load AWS config
	cfg, err := config.LoadDefaultConfig(context.TODO())
	if err != nil {
		log.Fatalf("Failed to load AWS config: %v", err)
	}

	// Create SQS client
	sqsClient := sqs.NewFromConfig(cfg)

	// Get queue URL from environment
	queueURL := os.Getenv("SQS_QUEUE_URL")
	if queueURL == "" {
		queueURL = os.Getenv("QUEUE_URL") // fallback
		if queueURL == "" {
			log.Fatal("SQS_QUEUE_URL or QUEUE_URL environment variable is required")
		}
	}

	log.Printf("Listening to queue: %s", queueURL)

	// Create context for graceful shutdown
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Handle shutdown signals
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		<-sigChan
		log.Println("Shutdown signal received, stopping worker...")
		cancel()
	}()

	// Start message processing loop
	for {
		select {
		case <-ctx.Done():
			log.Println("Worker-D stopped gracefully")
			return
		default:
			processMessages(ctx, sqsClient, queueURL)
		}
	}
}

func processMessages(ctx context.Context, client *sqs.Client, queueURL string) {
	// Receive messages from SQS
	result, err := client.ReceiveMessage(ctx, &sqs.ReceiveMessageInput{
		QueueUrl:            aws.String(queueURL),
		MaxNumberOfMessages: 10,
		WaitTimeSeconds:     20, // Long polling
		VisibilityTimeout:   30,
	})

	if err != nil {
		log.Printf("Error receiving messages: %v", err)
		time.Sleep(5 * time.Second)
		return
	}

	if len(result.Messages) == 0 {
		log.Println("No messages received, continuing to poll...")
		return
	}

	log.Printf("Received %d messages", len(result.Messages))

	// Process each message
	for _, msg := range result.Messages {
		if err := processMessage(ctx, client, queueURL, msg); err != nil {
			log.Printf("Error processing message %s: %v", *msg.MessageId, err)
		}
	}
}

func processMessage(ctx context.Context, client *sqs.Client, queueURL string, msg types.Message) error {
	log.Printf("Processing message: %s", *msg.MessageId)

	// Parse EventBridge event
	var eventData map[string]interface{}
	if err := json.Unmarshal([]byte(*msg.Body), &eventData); err != nil {
		log.Printf("Failed to parse message body: %v", err)
	} else {
		// Log EventBridge event details
		if detailType, ok := eventData["detail-type"].(string); ok {
			log.Printf("EventBridge Event: %s from %s", detailType, eventData["source"])
			if detail, ok := eventData["detail"].(map[string]interface{}); ok {
				log.Printf("Event Detail: %+v", detail)
				
				// Extract request data if exists
				if requestData, ok := detail["requestData"].(map[string]interface{}); ok {
					log.Printf("Request Data: %+v", requestData)
				}
			}
		} else {
			log.Printf("Direct Message: %+v", eventData)
		}
	}

	// Simulate processing work (configurable delay)
	processingTime := 2 * time.Second
	if delayEnv := os.Getenv("PROCESSING_DELAY"); delayEnv != "" {
		if delay, err := time.ParseDuration(delayEnv); err == nil {
			processingTime = delay
		}
	}

	log.Printf("Processing for %v...", processingTime)
	
	select {
	case <-time.After(processingTime):
		// Processing completed
	case <-ctx.Done():
		return fmt.Errorf("processing cancelled")
	}

	// Delete message from queue after successful processing
	_, err := client.DeleteMessage(ctx, &sqs.DeleteMessageInput{
		QueueUrl:      aws.String(queueURL),
		ReceiptHandle: msg.ReceiptHandle,
	})

	if err != nil {
		return fmt.Errorf("failed to delete message: %w", err)
	}

	log.Printf("Successfully processed and deleted message: %s", *msg.MessageId)
	return nil
}
