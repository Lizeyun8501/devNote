mod handlers;

use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use devnote_observe::{debug, info, instrument, warn};
use parking_lot::Mutex;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;
use std::sync::LazyLock;

use devnote_grpc::DevNoteGrpcClient;
use devnote_websocket::DevNoteWebSocketClient;
use serde::{Deserialize, Serialize};

// ── FFIErrorCode ──────────────────────────────────────────────────────────

#[repr(i32)]
#[derive(Debug, Clone, Copy)]
pub enum FFIErrorCode {
    Success = 0,
    InvalidArgument = 1,
    NotFound = 2,
    NotConnected = 3,
    CryptoError = 4,
    PermissionDenied = 5,
    InternalError = 99,
    RustPanic = -99,
}

// ── Global state ──────────────────────────────────────────────────────────

static RUNTIME: LazyLock<tokio::runtime::Runtime> = LazyLock::new(|| {
    tokio::runtime::Runtime::new().expect("Failed to create tokio runtime")
});

static GRPC_CLIENT: LazyLock<Mutex<Option<DevNoteGrpcClient>>> =
    LazyLock::new(|| Mutex::new(None));

static WS_CLIENT: LazyLock<Mutex<Option<DevNoteWebSocketClient>>> =
    LazyLock::new(|| Mutex::new(None));

// ── FFIResponse ───────────────────────────────────────────────────────────

#[repr(C)]
pub struct FFIResponse {
    pub code: i32,
    pub message: *mut c_char,
    pub data: *mut c_char,
}

impl FFIResponse {
    pub fn success(data: &str) -> Self {
        Self {
            code: FFIErrorCode::Success as i32,
            message: CString::new("ok").unwrap().into_raw(),
            data: CString::new(data).unwrap().into_raw(),
        }
    }

    pub fn error(code: i32, message: &str) -> Self {
        Self {
            code,
            message: CString::new(message).unwrap().into_raw(),
            data: ptr::null_mut(),
        }
    }

    pub fn from_result<T: Serialize>(result: anyhow::Result<T>) -> Self {
        match result {
            Ok(data) => match serde_json::to_string(&data) {
                Ok(json) => Self::success(&json),
                Err(e) => Self::error(FFIErrorCode::InternalError as i32, &e.to_string()),
            },
            Err(e) => Self::error(FFIErrorCode::InternalError as i32, &e.to_string()),
        }
    }
}

// ── Dispatch types ────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct DispatchRequest {
    event: String,
    #[allow(dead_code)]
    payload: Option<String>,
}

#[derive(Serialize)]
pub struct DispatchResponse {
    pub code: i32,
    pub message: String,
    pub data: Option<String>,
}

impl DispatchResponse {
    pub fn success(data: &str) -> Self {
        Self {
            code: FFIErrorCode::Success as i32,
            message: "ok".to_string(),
            data: Some(data.to_string()),
        }
    }

    pub fn error(code: FFIErrorCode, message: &str) -> Self {
        Self {
            code: code as i32,
            message: message.to_string(),
            data: None,
        }
    }
}

fn base64_encode(data: &[u8]) -> String {
    BASE64.encode(data)
}

/// Helper: create a heap-allocated FFIResponse from a catch_unwind error.
fn panic_response() -> *mut FFIResponse {
    Box::into_raw(Box::new(FFIResponse::error(
        FFIErrorCode::RustPanic as i32,
        "Rust panic occurred",
    )))
}

// ── Core FFI Functions ──────────────────────────────────────────────────────

#[no_mangle]
#[instrument]
pub extern "C" fn devnote_init() -> *mut FFIResponse {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        info!("FFI: devnote_init called");
        handlers::register_all_handlers();
        info!("FFI: event handlers registered");
        FFIResponse::success("{}")
    }));
    match result {
        Ok(response) => Box::into_raw(Box::new(response)),
        Err(_) => panic_response(),
    }
}

#[no_mangle]
pub extern "C" fn devnote_destroy(response: *mut FFIResponse) {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if response.is_null() {
            return;
        }
        // SAFETY: response was checked for null above; caller is responsible for
        // passing a valid pointer previously returned by devnote_init or similar.
        let resp = unsafe { &mut *response };
        if !resp.message.is_null() {
            // SAFETY: resp.message was created via CString::into_raw() and ownership
            // is being reclaimed here for deallocation.
            let _ = unsafe { CString::from_raw(resp.message) };
        }
        if !resp.data.is_null() {
            // SAFETY: resp.data was created via CString::into_raw() and ownership
            // is being reclaimed here for deallocation.
            let _ = unsafe { CString::from_raw(resp.data) };
        }
        // SAFETY: response was allocated via Box::into_raw() and we are
        // reclaiming ownership to free it.
        let _ = unsafe { Box::from_raw(response) };
    }));
    if let Err(_) = result {
        warn!("FFI: panic in devnote_destroy");
    }
}

#[no_mangle]
pub extern "C" fn devnote_free_string(s: *mut c_char) {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if !s.is_null() {
            // SAFETY: s was created via CString::into_raw() and ownership is
            // being reclaimed here for deallocation.
            let _ = unsafe { CString::from_raw(s) };
        }
    }));
    if let Err(_) = result {
        warn!("FFI: panic in devnote_free_string");
    }
}

#[no_mangle]
#[instrument]
pub extern "C" fn devnote_ping() -> *mut c_char {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        debug!("FFI: devnote_ping called");
        CString::new("pong").unwrap().into_raw()
    }));
    match result {
        Ok(ptr) => ptr,
        Err(_) => {
            CString::new("panic").unwrap().into_raw()
        }
    }
}

#[no_mangle]
#[instrument]
pub extern "C" fn devnote_dispatch(request: *const c_char) -> *mut c_char {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        info!("FFI: devnote_dispatch called");
        if request.is_null() {
            let error = DispatchResponse::error(FFIErrorCode::InvalidArgument, "Null request");
            let json = serde_json::to_string(&error).unwrap_or_default();
            return CString::new(json).unwrap().into_raw();
        }

        // SAFETY: request was checked for null above, and CStr::from_ptr reads
        // until the null terminator which is guaranteed by the Dart FFI caller
        // using Utf8.toUtf8Pointer().
        let request_cstr = unsafe { CStr::from_ptr(request) };

        let request_str = match request_cstr.to_str() {
            Ok(s) => s,
            Err(_) => {
                let error = DispatchResponse::error(FFIErrorCode::InvalidArgument, "Invalid UTF-8 in request");
                let json = serde_json::to_string(&error).unwrap_or_default();
                return CString::new(json).unwrap().into_raw();
            }
        };

        let dispatch_req: DispatchRequest = match serde_json::from_str(request_str) {
            Ok(req) => req,
            Err(e) => {
                let error = DispatchResponse::error(FFIErrorCode::InvalidArgument, &format!("Failed to parse request: {}", e));
                let json = serde_json::to_string(&error).unwrap_or_default();
                return CString::new(json).unwrap().into_raw();
            }
        };

        let response = handlers::handle_dispatch(&dispatch_req.event, dispatch_req.payload.as_deref());
        debug!("FFI: dispatch event={} result_code={}", &dispatch_req.event, response.code);
        let json = serde_json::to_string(&response).unwrap_or_default();
        CString::new(json).unwrap().into_raw()
    }));
    match result {
        Ok(ptr) => ptr,
        Err(_) => {
            let error = DispatchResponse {
                code: FFIErrorCode::RustPanic as i32,
                message: "Rust panic occurred".to_string(),
                data: None,
            };
            let json = serde_json::to_string(&error).unwrap_or_default();
            CString::new(json).unwrap().into_raw()
        }
    }
}

// ── gRPC FFI Functions ─────────────────────────────────────────────────────

#[no_mangle]
#[instrument]
pub extern "C" fn devnote_grpc_connect(server_addr: *const c_char) -> *mut FFIResponse {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if server_addr.is_null() {
            return FFIResponse::error(FFIErrorCode::InvalidArgument as i32, "Null server address");
        }

        // SAFETY: server_addr was checked for null above, and CStr::from_ptr
        // reads until the null terminator guaranteed by the Dart FFI caller.
        let addr = match unsafe { CStr::from_ptr(server_addr) }.to_str() {
            Ok(s) => s.to_string(),
            Err(_) => {
                return FFIResponse::error(FFIErrorCode::InvalidArgument as i32, "Invalid UTF-8 in server address");
            }
        };

        let result = RUNTIME.block_on(async {
            let client = DevNoteGrpcClient::new(addr);
            match client.connect().await {
                Ok(()) => {
                    let mut guard = GRPC_CLIENT.lock();
                    *guard = Some(client);
                    Ok(())
                }
                Err(e) => Err(e.to_string()),
            }
        });

        match result {
            Ok(()) => FFIResponse::success("{}"),
            Err(e) => FFIResponse::error(FFIErrorCode::NotConnected as i32, &e),
        }
    }));
    match result {
        Ok(response) => Box::into_raw(Box::new(response)),
        Err(_) => panic_response(),
    }
}

#[no_mangle]
#[instrument]
pub extern "C" fn devnote_grpc_disconnect() -> *mut FFIResponse {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        RUNTIME.block_on(async {
            let mut guard = GRPC_CLIENT.lock();
            if let Some(client) = guard.take() {
                client.disconnect().await;
            }
        });

        FFIResponse::success("{}")
    }));
    match result {
        Ok(response) => Box::into_raw(Box::new(response)),
        Err(_) => panic_response(),
    }
}

#[no_mangle]
#[instrument]
pub extern "C" fn devnote_grpc_dispatch(
    method: *const c_char,
    payload: *const c_char,
) -> *mut FFIResponse {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if method.is_null() {
            return FFIResponse::error(FFIErrorCode::InvalidArgument as i32, "Null method");
        }

        // SAFETY: method was checked for null above, and CStr::from_ptr reads
        // until the null terminator guaranteed by the Dart FFI caller.
        let method_str = match unsafe { CStr::from_ptr(method) }.to_str() {
            Ok(s) => s,
            Err(_) => return FFIResponse::error(FFIErrorCode::InvalidArgument as i32, "Invalid UTF-8 in method"),
        };

        let payload_bytes = if payload.is_null() {
            vec![]
        } else {
            // SAFETY: payload was checked for null above, and CStr::from_ptr
            // reads until the null terminator guaranteed by the Dart FFI caller.
            match unsafe { CStr::from_ptr(payload) }.to_str() {
                Ok(s) => s.as_bytes().to_vec(),
                Err(_) => return FFIResponse::error(FFIErrorCode::InvalidArgument as i32, "Invalid UTF-8 in payload"),
            }
        };

        let request_id = uuid::Uuid::new_v4().to_string();

        let result = RUNTIME.block_on(async {
            let guard = GRPC_CLIENT.lock();
            if let Some(ref client) = *guard {
                match client.dispatch(method_str, payload_bytes, &request_id).await {
                    Ok(response) => Ok(response),
                    Err(e) => Err(e.to_string()),
                }
            } else {
                Err("gRPC client not connected".to_string())
            }
        });

        match result {
            Ok(response) => {
                let json = serde_json::json!({
                    "success": response.success,
                    "payload": if response.payload.is_empty() {
                        serde_json::Value::Null
                    } else {
                        serde_json::Value::String(base64_encode(&response.payload))
                    },
                    "error": response.error,
                    "request_id": response.request_id,
                });
                FFIResponse::success(&json.to_string())
            }
            Err(e) => FFIResponse::error(FFIErrorCode::NotConnected as i32, &e),
        }
    }));
    match result {
        Ok(response) => Box::into_raw(Box::new(response)),
        Err(_) => panic_response(),
    }
}

// ── WebSocket FFI Functions ────────────────────────────────────────────────

#[no_mangle]
#[instrument]
pub extern "C" fn devnote_ws_connect(url: *const c_char) -> *mut FFIResponse {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if url.is_null() {
            return FFIResponse::error(FFIErrorCode::InvalidArgument as i32, "Null URL");
        }

        // SAFETY: url was checked for null above, and CStr::from_ptr reads
        // until the null terminator guaranteed by the Dart FFI caller.
        let url_str = match unsafe { CStr::from_ptr(url) }.to_str() {
            Ok(s) => s.to_string(),
            Err(_) => {
                return FFIResponse::error(FFIErrorCode::InvalidArgument as i32, "Invalid UTF-8 in URL");
            }
        };

        let result = RUNTIME.block_on(async {
            let client = DevNoteWebSocketClient::new(url_str);
            match client.connect().await {
                Ok(()) => {
                    let mut guard = WS_CLIENT.lock();
                    *guard = Some(client);
                    Ok(())
                }
                Err(e) => Err(e.to_string()),
            }
        });

        match result {
            Ok(()) => FFIResponse::success("{}"),
            Err(e) => FFIResponse::error(FFIErrorCode::NotConnected as i32, &e),
        }
    }));
    match result {
        Ok(response) => Box::into_raw(Box::new(response)),
        Err(_) => panic_response(),
    }
}

#[no_mangle]
#[instrument]
pub extern "C" fn devnote_ws_disconnect() -> *mut FFIResponse {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let result = RUNTIME.block_on(async {
            let mut guard = WS_CLIENT.lock();
            if let Some(client) = guard.take() {
                match client.disconnect().await {
                    Ok(()) => Ok(()),
                    Err(e) => Err(e.to_string()),
                }
            } else {
                Ok(())
            }
        });

        match result {
            Ok(()) => FFIResponse::success("{}"),
            Err(e) => FFIResponse::error(FFIErrorCode::InternalError as i32, &e),
        }
    }));
    match result {
        Ok(response) => Box::into_raw(Box::new(response)),
        Err(_) => panic_response(),
    }
}

#[no_mangle]
#[instrument]
pub extern "C" fn devnote_ws_send(message: *const c_char) -> *mut FFIResponse {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if message.is_null() {
            return FFIResponse::error(FFIErrorCode::InvalidArgument as i32, "Null message");
        }

        // SAFETY: message was checked for null above, and CStr::from_ptr reads
        // until the null terminator guaranteed by the Dart FFI caller.
        let msg_str = match unsafe { CStr::from_ptr(message) }.to_str() {
            Ok(s) => s,
            Err(_) => return FFIResponse::error(FFIErrorCode::InvalidArgument as i32, "Invalid UTF-8 in message"),
        };

        let result = RUNTIME.block_on(async {
            let guard = WS_CLIENT.lock();
            if let Some(ref client) = *guard {
                match client.send_text(msg_str).await {
                    Ok(()) => Ok(()),
                    Err(e) => Err(e.to_string()),
                }
            } else {
                Err("WebSocket client not connected".to_string())
            }
        });

        match result {
            Ok(()) => FFIResponse::success("{}"),
            Err(e) => FFIResponse::error(FFIErrorCode::NotConnected as i32, &e),
        }
    }));
    match result {
        Ok(response) => Box::into_raw(Box::new(response)),
        Err(_) => panic_response(),
    }
}
