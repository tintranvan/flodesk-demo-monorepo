package utils

import (
	"context"
	"encoding/json"
	"os"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/eventbridge"
	"github.com/aws/aws-sdk-go-v2/service/eventbridge/types"
)

// EventPublisher interface for publishing events
type EventPublisher interface {
	PublishEvent(eventType string, data interface{}) error
}

// EventBridgePublisher for AWS EventBridge
type EventBridgePublisher struct {
	client  *eventbridge.Client
	busName string
	source  string
}

func NewEventBridgePublisher() (*EventBridgePublisher, error) {
	cfg, err := config.LoadDefaultConfig(context.TODO())
	if err != nil {
		return nil, err
	}

	serviceName := os.Getenv("SERVICE_NAME")
	if serviceName == "" {
		serviceName = "api-svc-a"
	}

	env := os.Getenv("ENVIRONMENT")
	if env == "" {
		env = "dev"
	}

	return &EventBridgePublisher{
		client:  eventbridge.NewFromConfig(cfg),
		busName: env + "-" + serviceName + "-events",
		source:  serviceName,
	}, nil
}

func (e *EventBridgePublisher) PublishEvent(eventType string, data interface{}) error {
	detail, err := json.Marshal(data)
	if err != nil {
		return err
	}

	entry := types.PutEventsRequestEntry{
		Source:      aws.String(e.source),
		DetailType:  aws.String(eventType),
		Detail:      aws.String(string(detail)),
		EventBusName: aws.String(e.busName),
		Time:        aws.Time(time.Now()),
	}

	_, err = e.client.PutEvents(context.TODO(), &eventbridge.PutEventsInput{
		Entries: []types.PutEventsRequestEntry{entry},
	})

	if err != nil {
		Logger.Errorf("Failed to publish event: %v", err)
		return err
	}

	Logger.Infof("Event Published - Type: %s, Bus: %s", eventType, e.busName)
	return nil
}

// MockEventPublisher for local testing
type MockEventPublisher struct{}

func (m *MockEventPublisher) PublishEvent(eventType string, data interface{}) error {
	Logger.Infof("Mock Event Published - Type: %s, Data: %+v", eventType, data)
	return nil
}

// GetEventPublisher returns appropriate publisher based on environment
func GetEventPublisher() EventPublisher {
	env := os.Getenv("ENVIRONMENT")
	if env == "local" || env == "" {
		return &MockEventPublisher{}
	}
	
	publisher, err := NewEventBridgePublisher()
	if err != nil {
		Logger.Errorf("Failed to create EventBridge publisher: %v", err)
		return &MockEventPublisher{}
	}
	return publisher
}

// PublishEvent helper function
func PublishEvent(eventType string, data interface{}) error {
	publisher := GetEventPublisher()
	return publisher.PublishEvent(eventType, data)
}
