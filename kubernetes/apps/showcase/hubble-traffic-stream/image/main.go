package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"math"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"
)

const aggregateQuery = `label_replace(sum(rate(hubble_flows_processed_total[5m])), "kind", "flows", "", "") or label_replace(sum(rate(hubble_drop_total[5m])), "kind", "drops", "", "")`
const maxConsecutiveFailures = 6

type config struct {
	prometheusURL string
	relayURL      string
	token         string
	interval      time.Duration
}

type sample struct {
	Timestamp      string  `json:"timestamp"`
	FlowsPerSecond float64 `json:"flowsPerSecond"`
	DropsPerSecond float64 `json:"dropsPerSecond"`
}

type prometheusResponse struct {
	Status string `json:"status"`
	Data   struct {
		ResultType string `json:"resultType"`
		Result     []struct {
			Metric map[string]string  `json:"metric"`
			Value  [2]json.RawMessage `json:"value"`
		} `json:"result"`
	} `json:"data"`
}

type streamer struct {
	config config
	client *http.Client
	now    func() time.Time
}

func loadConfig() (config, error) {
	interval := 5 * time.Second
	if raw := os.Getenv("INTERVAL"); raw != "" {
		parsed, err := time.ParseDuration(raw)
		if err != nil || parsed < 3*time.Second {
			return config{}, errors.New("INTERVAL must be a duration of at least 3s")
		}
		interval = parsed
	}

	cfg := config{
		prometheusURL: os.Getenv("PROMETHEUS_URL"),
		relayURL:      os.Getenv("RELAY_URL"),
		token:         os.Getenv("PRODUCER_TOKEN"),
		interval:      interval,
	}
	if cfg.prometheusURL == "" || cfg.relayURL == "" || cfg.token == "" {
		return config{}, errors.New("PROMETHEUS_URL, RELAY_URL, and PRODUCER_TOKEN are required")
	}
	for name, raw := range map[string]string{"PROMETHEUS_URL": cfg.prometheusURL, "RELAY_URL": cfg.relayURL} {
		parsed, err := url.Parse(raw)
		if err != nil || parsed.Scheme == "" || parsed.Host == "" {
			return config{}, fmt.Errorf("%s must be an absolute URL", name)
		}
	}
	return cfg, nil
}

func main() {
	cfg, err := loadConfig()
	if err != nil {
		log.Fatal(err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	s := streamer{
		config: cfg,
		client: &http.Client{Timeout: 4 * time.Second},
		now:    time.Now,
	}
	if err := s.run(ctx); err != nil && !errors.Is(err, context.Canceled) {
		log.Fatal(err)
	}
}

func (s streamer) run(ctx context.Context) error {
	ticker := time.NewTicker(s.config.interval)
	defer ticker.Stop()
	failures := 0

	for {
		if err := s.publishOnce(ctx); err != nil && !errors.Is(err, context.Canceled) {
			failures++
			log.Printf("publish failed: %v", err)
			if failures >= maxConsecutiveFailures {
				return fmt.Errorf("publisher failed %d consecutive times", failures)
			}
		} else {
			failures = 0
		}

		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
		}
	}
}

func (s streamer) publishOnce(ctx context.Context) error {
	rates, err := s.collect(ctx)
	if err != nil {
		return fmt.Errorf("collect aggregate rates: %w", err)
	}

	payload := sample{
		Timestamp:      s.now().UTC().Truncate(time.Second).Format(time.RFC3339),
		FlowsPerSecond: round(rates["flows"]),
		DropsPerSecond: round(rates["drops"]),
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("encode payload: %w", err)
	}

	request, err := http.NewRequestWithContext(ctx, http.MethodPost, s.config.relayURL, strings.NewReader(string(body)))
	if err != nil {
		return fmt.Errorf("build relay request: %w", err)
	}
	request.Header.Set("Authorization", "Bearer "+s.config.token)
	request.Header.Set("Content-Type", "application/json")

	response, err := s.client.Do(request)
	if err != nil {
		return fmt.Errorf("send relay request: %w", err)
	}
	defer response.Body.Close()
	responseBody, _ := io.ReadAll(io.LimitReader(response.Body, 4096))
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fmt.Errorf("relay returned %s: %s", response.Status, strings.TrimSpace(string(responseBody)))
	}
	log.Printf("published aggregate rates at %s", payload.Timestamp)
	return nil
}

func (s streamer) collect(ctx context.Context) (map[string]float64, error) {
	endpoint, err := url.Parse(s.config.prometheusURL)
	if err != nil {
		return nil, err
	}
	query := endpoint.Query()
	query.Set("query", aggregateQuery)
	endpoint.RawQuery = query.Encode()

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint.String(), nil)
	if err != nil {
		return nil, err
	}
	response, err := s.client.Do(request)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("Prometheus returned %s", response.Status)
	}

	var document prometheusResponse
	decoder := json.NewDecoder(io.LimitReader(response.Body, 64*1024))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&document); err != nil {
		return nil, fmt.Errorf("decode Prometheus response: %w", err)
	}
	if document.Status != "success" || document.Data.ResultType != "vector" {
		return nil, errors.New("Prometheus response was not a successful instant vector")
	}

	rates := make(map[string]float64, 2)
	for _, result := range document.Data.Result {
		kind := result.Metric["kind"]
		if kind != "flows" && kind != "drops" {
			return nil, fmt.Errorf("unexpected aggregate kind %q", kind)
		}
		var raw string
		if err := json.Unmarshal(result.Value[1], &raw); err != nil {
			return nil, fmt.Errorf("decode %s rate: %w", kind, err)
		}
		rate, err := strconv.ParseFloat(raw, 64)
		if err != nil || math.IsNaN(rate) || math.IsInf(rate, 0) || rate < 0 {
			return nil, fmt.Errorf("invalid %s rate", kind)
		}
		if _, exists := rates[kind]; exists {
			return nil, fmt.Errorf("duplicate %s rate", kind)
		}
		rates[kind] = rate
	}
	if len(rates) != 2 {
		return nil, errors.New("Prometheus did not return both flow and drop rates")
	}
	return rates, nil
}

func round(value float64) float64 {
	return math.Round(value*1000) / 1000
}
