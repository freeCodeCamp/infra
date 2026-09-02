package r2alias

import (
	"errors"
	"fmt"
	"sync"

	"github.com/prometheus/client_golang/prometheus"
)

const (
	metricNamespace = "caddy"
	metricSubsystem = "r2alias"
)

const (
	opHead  = "head"
	opGet   = "get"
	opAlias = "alias"
)

const (
	resultOK       = "ok"
	resultNotFound = "not_found"
	resultTooLarge = "too_large"
	resultError    = "error"
	resultHit      = "hit"
	resultMiss     = "miss"
)

var moduleMetrics = struct {
	once       sync.Once
	operations *prometheus.CounterVec
	lookups    *prometheus.CounterVec
	inFlight   prometheus.Gauge
}{}

func initMetrics(registry prometheus.Registerer) error {
	moduleMetrics.once.Do(func() {
		moduleMetrics.operations = prometheus.NewCounterVec(prometheus.CounterOpts{
			Namespace: metricNamespace,
			Subsystem: metricSubsystem,
			Name:      "r2_operations_total",
			Help:      "R2 round trips by operation and outcome.",
		}, []string{"operation", "result"})

		moduleMetrics.lookups = prometheus.NewCounterVec(prometheus.CounterOpts{
			Namespace: metricNamespace,
			Subsystem: metricSubsystem,
			Name:      "alias_lookups_total",
			Help:      "Alias resolutions by cache outcome.",
		}, []string{"result"})

		moduleMetrics.inFlight = prometheus.NewGauge(prometheus.GaugeOpts{
			Namespace: metricNamespace,
			Subsystem: metricSubsystem,
			Name:      "buffered_bytes",
			Help:      "Object bytes currently held in memory for in-flight responses.",
		})
	})

	if registry == nil {
		return nil
	}
	for _, c := range []prometheus.Collector{
		moduleMetrics.operations, moduleMetrics.lookups, moduleMetrics.inFlight,
	} {
		if err := registry.Register(c); err != nil {
			var already prometheus.AlreadyRegisteredError
			if !errors.As(err, &already) {
				return fmt.Errorf("register %T: %w", c, err)
			}
		}
	}
	return nil
}

func recordOperation(operation, result string) {
	if moduleMetrics.operations == nil {
		return
	}
	moduleMetrics.operations.WithLabelValues(operation, result).Inc()
}

func recordLookup(result string) {
	if moduleMetrics.lookups == nil {
		return
	}
	moduleMetrics.lookups.WithLabelValues(result).Inc()
}

func addBufferedBytes(delta float64) {
	if moduleMetrics.inFlight == nil {
		return
	}
	moduleMetrics.inFlight.Add(delta)
}
