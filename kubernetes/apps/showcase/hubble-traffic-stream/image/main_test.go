package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestPublishOnceEmitsOnlyTheClosedAggregateContract(t *testing.T) {
	t.Helper()
	var received sample
	var authorization string

	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		switch request.URL.Path {
		case "/prometheus":
			if !strings.Contains(request.URL.Query().Get("query"), "hubble_flows_processed_total") {
				t.Error("flow aggregate query was not sent")
			}
			response.Header().Set("Content-Type", "application/json")
			_, _ = response.Write([]byte(`{"status":"success","data":{"resultType":"vector","result":[{"metric":{"kind":"flows"},"value":[1,"146.4444"]},{"metric":{"kind":"drops"},"value":[1,"0.0476"]}]}}`))
		case "/relay":
			authorization = request.Header.Get("Authorization")
			if err := json.NewDecoder(request.Body).Decode(&received); err != nil {
				t.Fatalf("decode relay body: %v", err)
			}
			response.WriteHeader(http.StatusAccepted)
		default:
			http.NotFound(response, request)
		}
	}))
	defer server.Close()

	s := streamer{
		config: config{
			prometheusURL: server.URL + "/prometheus",
			relayURL:      server.URL + "/relay",
			token:         "producer-token",
			interval:      5 * time.Second,
		},
		client: server.Client(),
		now:    func() time.Time { return time.Date(2026, 7, 31, 10, 12, 5, 900, time.UTC) },
	}

	if err := s.publishOnce(context.Background()); err != nil {
		t.Fatalf("publishOnce returned an error: %v", err)
	}
	if authorization != "Bearer producer-token" {
		t.Fatalf("unexpected authorization header %q", authorization)
	}
	want := sample{Timestamp: "2026-07-31T10:12:05Z", FlowsPerSecond: 146.444, DropsPerSecond: 0.048}
	if received != want {
		t.Fatalf("unexpected payload: got %#v, want %#v", received, want)
	}
}

func TestCollectRejectsAnIncompleteAggregate(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) {
		response.Header().Set("Content-Type", "application/json")
		_, _ = response.Write([]byte(`{"status":"success","data":{"resultType":"vector","result":[{"metric":{"kind":"flows"},"value":[1,"146.4"]}]}}`))
	}))
	defer server.Close()

	s := streamer{config: config{prometheusURL: server.URL}, client: server.Client()}
	if _, err := s.collect(context.Background()); err == nil || !strings.Contains(err.Error(), "both flow and drop rates") {
		t.Fatalf("expected an incomplete aggregate error, got %v", err)
	}
}

func TestPublishOnceRejectsRelayFailure(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		if request.URL.Path == "/prometheus" {
			response.Header().Set("Content-Type", "application/json")
			_, _ = response.Write([]byte(`{"status":"success","data":{"resultType":"vector","result":[{"metric":{"kind":"flows"},"value":[1,"1"]},{"metric":{"kind":"drops"},"value":[1,"0"]}]}}`))
			return
		}
		http.Error(response, "rejected", http.StatusUnauthorized)
	}))
	defer server.Close()

	s := streamer{
		config: config{prometheusURL: server.URL + "/prometheus", relayURL: server.URL + "/relay", token: "bad"},
		client: server.Client(),
		now:    time.Now,
	}
	if err := s.publishOnce(context.Background()); err == nil || !strings.Contains(err.Error(), "401 Unauthorized") {
		t.Fatalf("expected a relay rejection, got %v", err)
	}
}

func TestRunExitsAfterConsecutiveFailures(t *testing.T) {
	relayCalls := 0
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		if request.URL.Path == "/prometheus" {
			response.Header().Set("Content-Type", "application/json")
			_, _ = response.Write([]byte(`{"status":"success","data":{"resultType":"vector","result":[{"metric":{"kind":"flows"},"value":[1,"1"]},{"metric":{"kind":"drops"},"value":[1,"0"]}]}}`))
			return
		}
		relayCalls++
		http.Error(response, "unavailable", http.StatusServiceUnavailable)
	}))
	defer server.Close()

	s := streamer{
		config: config{
			prometheusURL: server.URL + "/prometheus",
			relayURL:      server.URL + "/relay",
			token:         "token",
			interval:      time.Millisecond,
		},
		client: server.Client(),
		now:    time.Now,
	}
	err := s.run(context.Background())
	if err == nil || !strings.Contains(err.Error(), "failed 6 consecutive times") {
		t.Fatalf("expected the failure threshold error, got %v", err)
	}
	if relayCalls != maxConsecutiveFailures {
		t.Fatalf("unexpected relay calls: got %d, want %d", relayCalls, maxConsecutiveFailures)
	}
}
