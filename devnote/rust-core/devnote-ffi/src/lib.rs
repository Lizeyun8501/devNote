use std::ffi::CString;
use std::os::raw::c_char;
use std::ptr;
use serde::Serialize;

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
