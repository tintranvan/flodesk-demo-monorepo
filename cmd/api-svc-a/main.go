package main

import (
	"encoding/json"
	"net/http"
	"os"

	"flodesk-monorepo/internal/utils"
)

func main() {
	logLevel := os.Getenv("LOG_LEVEL")
	if logLevel == "" {
		logLevel = "info"
	}
	utils.InitLogger(logLevel)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	http.HandleFunc("/api-svc-a/health", healthHandler)
	http.HandleFunc("/api-svc-a/process", processHandler)
	http.HandleFunc("/api-svc-a/complete", completeHandler)

	utils.Logger.Infof("Starting API-SVC-A on :%s", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		utils.Logger.Fatal(err)
	}
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"ok","service":"api-svc-a"}`))
}

func processHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	utils.Logger.Info("Processing request...")
	
	// Parse request body
	var requestData map[string]interface{}
	json.NewDecoder(r.Body).Decode(&requestData)
	
	// Publish event with request data
	eventData := map[string]interface{}{
		"taskId":      "task-123",
		"service":     "api-svc-a",
		"timestamp":   "2024-01-01T00:00:00Z",
		"requestData": requestData,
	}
	
	if err := utils.PublishEvent("task.created", eventData); err != nil {
		utils.Logger.Errorf("Failed to publish event: %v", err)
	}

	response := map[string]interface{}{
		"message": "Task processed successfully",
		"service": "api-svc-a",
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func completeHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	utils.Logger.Info("Completing process...")
	
	// Parse request body
	var requestData map[string]interface{}
	json.NewDecoder(r.Body).Decode(&requestData)
	
	// Publish process.completed event with request data
	eventData := map[string]interface{}{
		"processId":   "proc-456",
		"service":     "api-svc-a",
		"status":      "completed",
		"timestamp":   "2024-01-01T00:00:00Z",
		"requestData": requestData,
	}
	
	if err := utils.PublishEvent("process.completed", eventData); err != nil {
		utils.Logger.Errorf("Failed to publish event: %v", err)
	}

	response := map[string]interface{}{
		"message": "Process completed successfully",
		"service": "api-svc-a",
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}
