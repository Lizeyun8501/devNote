use devnote_observe::{debug, info, instrument, warn};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;
use std::sync::{LazyLock, Mutex};

use devnote_grpc::DevNoteGrpcClient;
use devnote_websocket::DevNoteWebSocketClient;
use serde::{Deserialize, Serialize};

static RUNTIME: LazyLock<tokio::runtime::Runtime> = LazyLock::new(|| {
    tokio::runtime::Runtime::new().expect("Failed to create tokio runtime")
});

static GRPC_CLIENT: LazyLock<Mutex<Option<DevNoteGrpcClient>>> =
    LazyLock::new(|| Mutex::new(None));

static WS_CLIENT: LazyLock<Mutex<Option<DevNoteWebSocketClient>>> =
    LazyLock::new(|| Mutex::new(None));

#[repr(C)]
pub struct FFIResponse {
    pub code: i32,
    pub message: *mut c_char,
    pub data: *mut c_char,
}

impl FFIResponse {
    pub fn success(data: &str) -> Self {
        Self {
            code: 0,
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
                Err(e) => Self::error(-1, &e.to_string()),
            },
            Err(e) => Self::error(-1, &e.to_string()),
        }
    }
}

#[derive(Deserialize)]
struct DispatchRequest {
    event: String,
    #[allow(dead_code)]
    payload: Option<String>,
}

#[derive(Serialize)]
struct DispatchResponse {
    code: i32,
    message: String,
    data: Option<String>,
}

fn handle_dispatch(event: &str, payload: Option<&str>) -> DispatchResponse {
    match event {
        "NoteEvent.CreateNote" | "NoteEvent.ReadNote" | "NoteEvent.UpdateNote" | "NoteEvent.DeleteNote" | "NoteEvent.ListNotes" => {
            DispatchResponse {
                code: 0,
                message: "ok".to_string(),
                data: Some(payload.unwrap_or("{}").to_string()),
            }
        }
        "FolderEvent.CreateFolder" | "FolderEvent.ReadFolder" | "FolderEvent.UpdateFolder" | "FolderEvent.DeleteFolder" | "FolderEvent.ListFolders" => {
            DispatchResponse {
                code: 0,
                message: "ok".to_string(),
                data: Some(payload.unwrap_or("{}").to_string()),
            }
        }
        "EditorEvent.InsertBlock" | "EditorEvent.UpdateBlock" | "EditorEvent.DeleteBlock" | "EditorEvent.LoadDocument" => {
            DispatchResponse {
                code: 0,
                message: "ok".to_string(),
                data: Some(payload.unwrap_or("{}").to_string()),
            }
        }
        "SearchEvent.SearchNotes" | "SearchEvent.SearchContent" => {
            DispatchResponse {
                code: 0,
                message: "ok".to_string(),
                data: Some("[]".to_string()),
            }
        }
        "SyncEvent.StartSync" | "SyncEvent.GetSyncStatus" | "SyncEvent.ResolveConflict" => {
            DispatchResponse {
                code: 0,
                message: "ok".to_string(),
                data: Some(payload.unwrap_or("{}").to_string()),
            }
        }
        _ => DispatchResponse {
            code: -1,
            message: format!("Unknown event: {}", event),
            data: None,
        },
    }
}

#[no_mangle]
#[instrument]
pub extern "C" fn devnote_init() -> *mut FFIResponse {
    info!("FFI: devnote_init called");
    let response = FFIResponse::success("{}");
    Box::into_raw(Box::new(response))
}

#[no_mangle]
pub unsafe extern "C" fn devnote_destroy(response: *mut FFIResponse) {
    if response.is_null() {
        return;
    }
    let resp = &mut *response;
    if !resp.message.is_null() {
        let _ = CString::from_raw(resp.message);
    }
    if !resp.data.is_null() {
        let _ = CString::from_raw(resp.data);
    }
    let _ = Box::from_raw(response);
}

#[no_mangle]
pub unsafe extern "C" fn devnote_free_string(s: *mut c_char) {
    if !s.is_null() {
        let _ = CString::from_raw(s);
    }
}

#[no_mangle]
#[instrument]
pub unsafe extern "C" fn devnote_ping() -> *mut c_char {
    debug!("FFI: devnote_ping called");
    CString::new("pong").unwrap().into_raw()
}

#[no_mangle]
#[instrument]
pub unsafe extern "C" fn devnote_dispatch(request: *const c_char) -> *mut c_char {
    info!("FFI: devnote_dispatch called");
    if request.is_null() {
        let error = DispatchResponse {
            code: -1,
            message: "Null request".to_string(),
            data: None,
        };
        let json = serde_json::to_string(&error).unwrap_or_default();
        return CString::new(json).unwrap().into_raw();
    }

    let request_cstr = unsafe { CStr::from_ptr(request) };

    let request_str = match request_cstr.to_str() {
        Ok(s) => s,
        Err(_) => {
            let error = DispatchResponse {
                code: -1,
                message: "Invalid UTF-8 in request".to_string(),
                data: None,
            };
            let json = serde_json::to_string(&error).unwrap_or_default();
            return CString::new(json).unwrap().into_raw();
        }
    };

    let dispatch_req: DispatchRequest = match serde_json::from_str(request_str) {
        Ok(req) => req,
        Err(e) => {
            let error = DispatchResponse {
                code: -1,
                message: format!("Failed to parse request: {}", e),
                data: None,
            };
            let json = serde_json::to_string(&error).unwrap_or_default();
            return CString::new(json).unwrap().into_raw();
        }
    };

    let response = handle_dispatch(&dispatch_req.event, dispatch_req.payload.as_deref());
    debug!("FFI: dispatch event={} result_code={}", &dispatch_req.event, response.code);
    let json = serde_json::to_string(&response).unwrap_or_default();
    CString::new(json).unwrap().into_raw()
}

// ── gRPC FFI Functions ─────────────────────────────────────────────────────

#[no_mangle]
#[instrument]
pub unsafe extern "C" fn devnote_grpc_connect(server_addr: *const c_char) -> *mut FFIResponse {
    if server_addr.is_null() {
        return Box::into_raw(Box::new(FFIResponse::error(-1, "Null server address")));
    }

    let addr = match unsafe { CStr::from_ptr(server_addr) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => {
            return Box::into_raw(Box::new(FFIResponse::error(-1, "Invalid UTF-8 in server address")));
        }
    };

    let result = RUNTIME.block_on(async {
        let client = DevNoteGrpcClient::new(addr);
        match client.connect().await {
            Ok(()) => {
                let mut guard = GRPC_CLIENT.lock().unwrap();
                *guard = Some(client);
                Ok(())
            }
            Err(e) => Err(e.to_string()),
        }
    });

    match result {
        Ok(()) => Box::into_raw(Box::new(FFIResponse::success("{}"))),
        Err(e) => Box::into_raw(Box::new(FFIResponse::error(-1, &e))),
    }
}

#[no_mangle]
#[instrument]
pub extern "C" fn devnote_grpc_disconnect() -> *mut FFIResponse {
    RUNTIME.block_on(async {
        let mut guard = GRPC_CLIENT.lock().unwrap();
        if let Some(client) = guard.take() {
            client.disconnect().await;
        }
    });

    Box::into_raw(Box::new(FFIResponse::success("{}")))
}

#[no_mangle]
#[instrument]
pub unsafe extern "C" fn devnote_grpc_dispatch(
    method: *const c_char,
    payload: *const c_char,
) -> *mut FFIResponse {
    if method.is_null() {
        return Box::into_raw(Box::new(FFIResponse::error(-1, "Null method")));
    }

    let method_str = match unsafe { CStr::from_ptr(method) }.to_str() {
        Ok(s) => s,
        Err(_) => return Box::into_raw(Box::new(FFIResponse::error(-1, "Invalid UTF-8 in method"))),
    };

    let payload_bytes = if payload.is_null() {
        vec![]
    } else {
        match unsafe { CStr::from_ptr(payload) }.to_str() {
            Ok(s) => s.as_bytes().to_vec(),
            Err(_) => return Box::into_raw(Box::new(FFIResponse::error(-1, "Invalid UTF-8 in payload"))),
        }
    };

    let request_id = uuid::Uuid::new_v4().to_string();

    let result = RUNTIME.block_on(async {
        let guard = GRPC_CLIENT.lock().unwrap();
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
            Box::into_raw(Box::new(FFIResponse::success(&json.to_string())))
        }
        Err(e) => Box::into_raw(Box::new(FFIResponse::error(-1, &e))),
    }
}

// ── WebSocket FFI Functions ────────────────────────────────────────────────

#[no_mangle]
#[instrument]
pub unsafe extern "C" fn devnote_ws_connect(url: *const c_char) -> *mut FFIResponse {
    if url.is_null() {
        return Box::into_raw(Box::new(FFIResponse::error(-1, "Null URL")));
    }

    let url_str = match unsafe { CStr::from_ptr(url) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => {
            return Box::into_raw(Box::new(FFIResponse::error(-1, "Invalid UTF-8 in URL")));
        }
    };

    let result = RUNTIME.block_on(async {
        let client = DevNoteWebSocketClient::new(url_str);
        match client.connect().await {
            Ok(()) => {
                let mut guard = WS_CLIENT.lock().unwrap();
                *guard = Some(client);
                Ok(())
            }
            Err(e) => Err(e.to_string()),
        }
    });

    match result {
        Ok(()) => Box::into_raw(Box::new(FFIResponse::success("{}"))),
        Err(e) => Box::into_raw(Box::new(FFIResponse::error(-1, &e))),
    }
}

#[no_mangle]
#[instrument]
pub extern "C" fn devnote_ws_disconnect() -> *mut FFIResponse {
    let result = RUNTIME.block_on(async {
        let mut guard = WS_CLIENT.lock().unwrap();
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
        Ok(()) => Box::into_raw(Box::new(FFIResponse::success("{}"))),
        Err(e) => Box::into_raw(Box::new(FFIResponse::error(-1, &e))),
    }
}

#[no_mangle]
#[instrument]
pub unsafe extern "C" fn devnote_ws_send(message: *const c_char) -> *mut FFIResponse {
    if message.is_null() {
        return Box::into_raw(Box::new(FFIResponse::error(-1, "Null message")));
    }

    let msg_str = match unsafe { CStr::from_ptr(message) }.to_str() {
        Ok(s) => s,
        Err(_) => return Box::into_raw(Box::new(FFIResponse::error(-1, "Invalid UTF-8 in message"))),
    };

    let result = RUNTIME.block_on(async {
        let guard = WS_CLIENT.lock().unwrap();
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
        Ok(()) => Box::into_raw(Box::new(FFIResponse::success("{}"))),
        Err(e) => Box::into_raw(Box::new(FFIResponse::error(-1, &e))),
    }
}

fn base64_encode(data: &[u8]) -> String {
    const CHARS: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut result = String::new();
    for chunk in data.chunks(3) {
        let b0 = chunk[0] as u32;
        let b1 = if chunk.len() > 1 { chunk[1] as u32 } else { 0 };
        let b2 = if chunk.len() > 2 { chunk[2] as u32 } else { 0 };
        let triple = (b0 << 16) | (b1 << 8) | b2;
        result.push(CHARS[((triple >> 18) & 0x3F) as usize] as char);
        result.push(CHARS[((triple >> 12) & 0x3F) as usize] as char);
        if chunk.len() > 1 {
            result.push(CHARS[((triple >> 6) & 0x3F) as usize] as char);
        } else {
            result.push('=');
        }
        if chunk.len() > 2 {
            result.push(CHARS[(triple & 0x3F) as usize] as char);
        } else {
            result.push('=');
        }
    }
    result
}
