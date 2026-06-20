use once_cell::sync::OnceCell;
use std::io;
use tracing_subscriber::fmt::format::FmtSpan;
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;
use tracing_subscriber::EnvFilter;
use tracing_subscriber::Layer;

// ── Re-exports ────────────────────────────────────────────────────────
pub use tracing::{self, debug, error, info, trace, warn};
pub use tracing::instrument;

// ── Log config ────────────────────────────────────────────────────────

#[derive(Clone, Debug)]
pub enum LogFormat {
    Pretty,
    Json,
}

#[derive(Clone, Debug)]
pub enum LogLevel {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
}

impl LogLevel {
    fn as_str(&self) -> &'static str {
        match self {
            LogLevel::Trace => "trace",
            LogLevel::Debug => "debug",
            LogLevel::Info => "info",
            LogLevel::Warn => "warn",
            LogLevel::Error => "error",
        }
    }
}

#[derive(Clone, Debug)]
pub struct LogConfig {
    pub level: LogLevel,
    pub format: LogFormat,
    pub file_enabled: bool,
    pub file_dir: String,
    pub otlp_endpoint: Option<String>,
}

impl Default for LogConfig {
    fn default() -> Self {
        LogConfig {
            level: LogLevel::Info,
            format: LogFormat::Pretty,
            file_enabled: true,
            file_dir: "logs".to_string(),
            otlp_endpoint: None,
        }
    }
}

// ── Metrics globals ───────────────────────────────────────────────────

static METRICS_HANDLE: OnceCell<metrics_exporter_prometheus::PrometheusHandle> = OnceCell::new();

fn metrics_recorder() -> &'static metrics_exporter_prometheus::PrometheusRecorder {
    static RECORDER: OnceCell<Box<metrics_exporter_prometheus::PrometheusRecorder>> = OnceCell::new();
    RECORDER
        .get_or_init(|| Box::new(metrics_exporter_prometheus::PrometheusBuilder::new().build_recorder()))
        .as_ref()
}

pub fn get_metrics_handle() -> &'static metrics_exporter_prometheus::PrometheusHandle {
    METRICS_HANDLE.get_or_init(|| metrics_recorder().handle())
}

/// Increment a counter metric by 1.
///
/// 注意：当前 metrics 后端尚不支持带标签的计数器。当传入非空 labels 时，
/// 会通过 tracing::debug! 记录一条日志说明标签被忽略，避免静默丢弃。
pub fn increment_counter(name: &'static str, labels: &[(&str, &str)]) {
    if !labels.is_empty() {
        tracing::debug!(
            name,
            ?labels,
            "counter labels not yet supported by metrics backend"
        );
    }
    metrics::counter!(name).increment(1);
}

/// Record a histogram value.
///
/// 注意：当前 metrics 后端尚不支持带标签的直方图。当传入非空 labels 时，
/// 会通过 tracing::debug! 记录一条日志说明标签被忽略，避免静默丢弃。
pub fn record_histogram(name: &'static str, value: f64, labels: &[(&str, &str)]) {
    if !labels.is_empty() {
        tracing::debug!(
            name,
            ?labels,
            "histogram labels not yet supported by metrics backend"
        );
    }
    metrics::histogram!(name).record(value);
}

// ── Init ──────────────────────────────────────────────────────────────

/// Initialise the tracing subscriber. Call once at startup.
pub fn init_logging(config: LogConfig) {
    let env_filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new(config.level.as_str()));

    let console_layer = match config.format {
        LogFormat::Pretty => {
            tracing_subscriber::fmt::layer()
                .pretty()
                .with_span_events(FmtSpan::CLOSE)
                .with_writer(io::stdout)
                .boxed()
        }
        LogFormat::Json => {
            tracing_subscriber::fmt::layer()
                .json()
                .with_span_events(FmtSpan::CLOSE)
                .with_writer(io::stdout)
                .boxed()
        }
    };

    let mut layers: Vec<Box<dyn tracing_subscriber::layer::Layer<_> + Send + Sync>> =
        vec![console_layer];

    // Optional file layer.
    if config.file_enabled {
        let file_appender = tracing_appender::rolling::daily(&config.file_dir, "devnote.log");
        let file_layer = tracing_subscriber::fmt::layer()
            .with_ansi(false)
            .with_writer(file_appender)
            .boxed();
        layers.push(file_layer);
    }

    // Optional OTLP exporter.
    #[cfg(feature = "otlp")]
    if let Some(ref endpoint) = config.otlp_endpoint {
        let tracer = opentelemetry_sdk::trace::TracerProvider::builder()
            .with_batch_exporter(
                opentelemetry_otlp::new_exporter()
                    .tonic()
                    .with_endpoint(endpoint.clone())
                    .build_span_exporter()
                    .expect("failed to build OTLP span exporter"),
                opentelemetry_sdk::runtime::Tokio,
            )
            .build()
            .tracer("devnote");

        let otel_layer = tracing_opentelemetry::layer().with_tracer(tracer).boxed();
        layers.push(otel_layer);
    }

    tracing_subscriber::registry()
        .with(env_filter)
        .with(layers)
        .init();

    // Touch the metrics recorder so it is initialised early.
    metrics_recorder();
}