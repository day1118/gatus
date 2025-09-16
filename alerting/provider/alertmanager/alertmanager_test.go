package alertmanager

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/TwiN/gatus/v5/alerting/alert"
	"github.com/TwiN/gatus/v5/config/endpoint"
)

func TestAlertProvider_Validate(t *testing.T) {
	tests := []struct {
		name          string
		provider      AlertProvider
		expectedError bool
	}{
		{
			name: "valid configuration",
			provider: AlertProvider{
				DefaultConfig: Config{
					URL: "http://alertmanager:9093",
				},
			},
			expectedError: false,
		},
		{
			name: "missing URL",
			provider: AlertProvider{
				DefaultConfig: Config{},
			},
			expectedError: true,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			err := test.provider.Validate()
			if test.expectedError && err == nil {
				t.Error("expected an error, but got none")
			}
			if !test.expectedError && err != nil {
				t.Errorf("expected no error, but got %v", err)
			}
		})
	}
}

func TestAlertProvider_buildAlert(t *testing.T) {
	provider := AlertProvider{
		DefaultConfig: Config{
			URL:             "http://alertmanager:9093",
			DefaultSeverity: "warning",
			ExtraLabels: map[string]string{
				"environment": "test",
			},
			ExtraAnnotations: map[string]string{
				"runbook": "https://wiki.example.com/runbook",
			},
		},
	}

	ep := &endpoint.Endpoint{
		Name:  "Test API",
		URL:   "https://api.example.com/health",
		Group: "production",
	}

	alert := &alert.Alert{
		Description: stringPtr("API health check failed"),
	}

	result := &endpoint.Result{
		Errors: []string{"connection timeout", "DNS resolution failed"},
	}

	// Test firing alert
	firingAlert := provider.buildAlert(&provider.DefaultConfig, ep, alert, result, false)

	if firingAlert.Labels["alertname"] != "GatusEndpointDown" {
		t.Errorf("expected alertname to be 'GatusEndpointDown', got %s", firingAlert.Labels["alertname"])
	}

	if firingAlert.Labels["instance"] != ep.URL {
		t.Errorf("expected instance to be %s, got %s", ep.URL, firingAlert.Labels["instance"])
	}

	if firingAlert.Labels["endpoint"] != ep.Name {
		t.Errorf("expected endpoint to be %s, got %s", ep.Name, firingAlert.Labels["endpoint"])
	}

	if firingAlert.Labels["group"] != ep.Group {
		t.Errorf("expected group to be %s, got %s", ep.Group, firingAlert.Labels["group"])
	}

	if firingAlert.Labels["severity"] != "warning" {
		t.Errorf("expected severity to be 'warning', got %s", firingAlert.Labels["severity"])
	}

	if firingAlert.Labels["environment"] != "test" {
		t.Errorf("expected environment to be 'test', got %s", firingAlert.Labels["environment"])
	}

	if firingAlert.Annotations["runbook"] != "https://wiki.example.com/runbook" {
		t.Errorf("expected runbook annotation, got %s", firingAlert.Annotations["runbook"])
	}

	if firingAlert.EndsAt != (time.Time{}) {
		t.Error("expected EndsAt to be zero for firing alert")
	}

	// Test resolved alert
	resolvedAlert := provider.buildAlert(&provider.DefaultConfig, ep, alert, result, true)

	if !resolvedAlert.EndsAt.After(time.Now().Add(-time.Minute)) {
		t.Error("expected EndsAt to be set for resolved alert")
	}

	if resolvedAlert.Annotations["summary"] != "Endpoint Test API is now healthy" {
		t.Errorf("unexpected resolved summary: %s", resolvedAlert.Annotations["summary"])
	}
}

func TestAlertProvider_Send(t *testing.T) {
	// Create a mock Alertmanager server
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Errorf("expected POST request, got %s", r.Method)
		}

		if r.URL.Path != "/api/v2/alerts" {
			t.Errorf("expected path /api/v2/alerts, got %s", r.URL.Path)
		}

		if r.Header.Get("Content-Type") != "application/json" {
			t.Errorf("expected Content-Type application/json, got %s", r.Header.Get("Content-Type"))
		}

		// Decode and validate the payload
		var alerts []AlertmanagerAlert
		if err := json.NewDecoder(r.Body).Decode(&alerts); err != nil {
			t.Errorf("failed to decode request body: %v", err)
			http.Error(w, "Bad Request", http.StatusBadRequest)
			return
		}

		if len(alerts) != 1 {
			t.Errorf("expected 1 alert, got %d", len(alerts))
		}

		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	provider := AlertProvider{
		DefaultConfig: Config{
			URL: server.URL,
		},
	}

	ep := &endpoint.Endpoint{
		Name: "Test API",
		URL:  "https://api.example.com/health",
	}

	alert := &alert.Alert{
		Description: stringPtr("Test alert"),
	}

	result := &endpoint.Result{
		Success: false,
		Errors:  []string{"test error"},
	}

	err := provider.Send(ep, alert, result, false)
	if err != nil {
		t.Errorf("unexpected error: %v", err)
	}
}

func TestConfig_Merge(t *testing.T) {
	base := Config{
		URL:             "http://base:9093",
		DefaultSeverity: "critical",
		ExtraLabels: map[string]string{
			"team": "platform",
		},
	}

	override := Config{
		DefaultSeverity: "warning",
		ExtraLabels: map[string]string{
			"environment": "test",
		},
		ExtraAnnotations: map[string]string{
			"runbook": "https://wiki.example.com",
		},
	}

	base.Merge(&override)

	if base.URL != "http://base:9093" {
		t.Errorf("expected URL to remain unchanged, got %s", base.URL)
	}

	if base.DefaultSeverity != "warning" {
		t.Errorf("expected severity to be overridden to 'warning', got %s", base.DefaultSeverity)
	}

	if base.ExtraLabels["team"] != "platform" {
		t.Error("expected original label to be preserved")
	}

	if base.ExtraLabels["environment"] != "test" {
		t.Error("expected override label to be added")
	}

	if base.ExtraAnnotations["runbook"] != "https://wiki.example.com" {
		t.Error("expected override annotation to be added")
	}
}

// Helper function to create string pointers
func stringPtr(s string) *string {
	return &s
}
