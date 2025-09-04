package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
)

func main() {
	// Get configuration
	queueURL := os.Getenv("SQS_QUEUE_URL")
	if queueURL == "" {
		fmt.Println("SQS_QUEUE_URL environment variable is required")
		os.Exit(1)
	}

	intervalStr := os.Getenv("WORKER_INTERVAL")
	if intervalStr == "" {
		intervalStr = "10s"
	}
	interval, _ := time.ParseDuration(intervalStr)

	// Load secrets from JSON if available
	secretsJSON := os.Getenv("SECRETS_JSON")
	if secretsJSON != "" {
		var secrets map[string]string
		if err := json.Unmarshal([]byte(secretsJSON), &secrets); err == nil {
			fmt.Printf("Loaded %d secrets from Secrets Manager\n", len(secrets))
		}
	}

	// Initialize AWS config
	cfg, err := config.LoadDefaultConfig(context.TODO())
	if err != nil {
		fmt.Printf("Failed to load AWS config: %v\n", err)
		os.Exit(1)
	}

	sqsClient := sqs.NewFromConfig(cfg)

	// Start health server
	go startHealthServer()

	fmt.Printf("Worker-C started, checking queue every %v\n", interval)
	fmt.Printf("Queue URL: %s\n", queueURL)

	// Simple polling loop
	for {
		checkQueue(sqsClient, queueURL)
		time.Sleep(interval)
	}
}

func checkQueue(client *sqs.Client, queueURL string) {
	ctx := context.Background()
	
	result, err := client.ReceiveMessage(ctx, &sqs.ReceiveMessageInput{
		QueueUrl:            aws.String(queueURL),
		MaxNumberOfMessages: 10,
		WaitTimeSeconds:     1, // Short polling
	})

	if err != nil {
		fmt.Printf("Error checking queue: %v\n", err)
		return
	}

	if len(result.Messages) == 0 {
		fmt.Printf("[%s] No messages in queue\n", time.Now().Format("15:04:05"))
		return
	}

	fmt.Printf("[%s] Found %d messages:\n", time.Now().Format("15:04:05"), len(result.Messages))
	
	for i, msg := range result.Messages {
		fmt.Printf("  Message %d: %s\n", i+1, *msg.Body)
		
		// Add processing delay for testing auto-scaling
		processingDelay := os.Getenv("PROCESSING_DELAY")
		if processingDelay != "" {
			if delay, err := time.ParseDuration(processingDelay); err == nil {
				fmt.Printf("  Processing with delay: %v\n", delay)
				time.Sleep(delay)
			}
		}
		
		// Delete message after processing
		_, err := client.DeleteMessage(ctx, &sqs.DeleteMessageInput{
			QueueUrl:      aws.String(queueURL),
			ReceiptHandle: msg.ReceiptHandle,
		})
		if err != nil {
			fmt.Printf("  Error deleting message: %v\n", err)
		} else {
			fmt.Printf("  Message %d processed and deleted\n", i+1)
		}
	}
}

func startHealthServer() {
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{
			"status":  "ok",
			"service": "worker-c",
			"time":    time.Now().Format(time.RFC3339),
		})
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	fmt.Printf("Health server starting on port %s\n", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		fmt.Printf("Health server error: %v\n", err)
	}
}
