use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;

use serde::{Deserialize, Serialize};

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
pub extern "C" fn devnote_init() -> *mut FFIResponse {
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
pub unsafe extern "C" fn devnote_ping() -> *mut c_char {
    CString::new("pong").unwrap().into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn devnote_dispatch(request: *const c_char) -> *mut c_char {
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
    let json = serde_json::to_string(&response).unwrap_or_default();
    CString::new(json).unwrap().into_raw()
}
