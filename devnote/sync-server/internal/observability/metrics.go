package observability

import (
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

// Metrics holds all Prometheus metrics for the sync server.
type Metrics struct {
	// HTTP request counter by method, path, status
	RequestsTotal *prometheus.CounterVec

	// HTTP request duration histogram
	RequestDuration *prometheus.HistogramVec

	// Sync operation counters
	SyncPushTotal    prometheus.Counter
	SyncPullTotal    prometheus.Counter
	SyncConflictTotal prometheus.Counter

	// Active connections gauge
	ActiveConnections prometheus.Gauge

	// Error rate counter
	ErrorsTotal *prometheus.CounterVec
}

// NewMetrics creates and registers all Prometheus metrics.
func NewMetrics() *Metrics {
	return &Metrics{
		RequestsTotal: promauto.NewCounterVec(
			prometheus.CounterOpts{
				Name: "devnote_http_requests_total",
				Help: "Total number of HTTP requests.",
			},
			[]string{"method", "path", "status"},
		),
		RequestDuration: promauto.NewHistogramVec(
			prometheus.HistogramOpts{
				Name:    "devnote_http_request_duration_seconds",
				Help:    "HTTP request duration in seconds.",
				Buckets: prometheus.DefBuckets,
			},
			[]string{"method", "path"},
		),
		SyncPushTotal: promauto.NewCounter(
			prometheus.CounterOpts{
				Name: "devnote_sync_push_total",
				Help: "Total number of sync push operations.",
			},
		),
		SyncPullTotal: promauto.NewCounter(
			prometheus.CounterOpts{
				Name: "devnote_sync_pull_total",
				Help: "Total number of sync pull operations.",
			},
		),
		SyncConflictTotal: promauto.NewCounter(
			prometheus.CounterOpts{
				Name: "devnote_sync_conflict_total",
				Help: "Total number of sync conflict detections.",
			},
		),
		ActiveConnections: promauto.NewGauge(
			prometheus.GaugeOpts{
				Name: "devnote_active_connections",
				Help: "Current number of active connections.",
			},
		),
		ErrorsTotal: promauto.NewCounterVec(
			prometheus.CounterOpts{
				Name: "devnote_errors_total",
				Help: "Total number of errors by type.",
			},
			[]string{"type"},
		),
	}
}