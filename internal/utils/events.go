package utils

import (
	"os"
)

// EventPublisher interface for publishing events
type EventPublisher interface {
	PublishEvent(eventType string, data interface{}) error
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
	
	// TODO: Return real EventBridge publisher for AWS environments
	return &MockEventPublisher{}
}

// PublishEvent helper function
func PublishEvent(eventType string, data interface{}) error {
	publisher := GetEventPublisher()
	return publisher.PublishEvent(eventType, data)
}
