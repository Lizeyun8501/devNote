use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use crate::db;

fn cstr_to_string(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(ptr).to_str().ok().map(|s| s.to_string()) }
}

fn string_to_cchar(s: String) -> *mut c_char {
    CString::new(s).unwrap_or_default().into_raw()
}

#[no_mangle]
pub extern "C" fn devnote_init(db_path: *const c_char) -> i32 {
    let path = match cstr_to_string(db_path) {
        Some(p) => p,
        None => return -1,
    };
    match db::init(&path) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

#[no_mangle]
pub extern "C" fn devnote_create_note(
    title: *const c_char,
    content: *const c_char,
    folder_id: *const c_char,
) -> *mut c_char {
    let title = match cstr_to_string(title) {
        Some(t) => t,
        None => return std::ptr::null_mut(),
    };
    let content = match cstr_to_string(content) {
        Some(c) => c,
        None => return std::ptr::null_mut(),
    };
    let folder_id = cstr_to_string(folder_id);
    let fid = folder_id.as_deref();
    match db::create_note(&title, &content, fid) {
        Ok(note) => {
            let json = serde_json::to_string(&note).unwrap_or_default();
            string_to_cchar(json)
        }
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn devnote_list_notes(folder_id: *const c_char) -> *mut c_char {
    let folder_id = cstr_to_string(folder_id);
    let fid = folder_id.as_deref();
    match db::list_notes(fid) {
        Ok(notes) => {
            let json = serde_json::to_string(&notes).unwrap_or_default();
            string_to_cchar(json)
        }
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn devnote_get_note(id: *const c_char) -> *mut c_char {
    let id = match cstr_to_string(id) {
        Some(i) => i,
        None => return std::ptr::null_mut(),
    };
    match db::get_note(&id) {
        Ok(Some(note)) => {
            let json = serde_json::to_string(&note).unwrap_or_default();
            string_to_cchar(json)
        }
        Ok(None) => std::ptr::null_mut(),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn devnote_update_note(
    id: *const c_char,
    title: *const c_char,
    content: *const c_char,
) -> i32 {
    let id = match cstr_to_string(id) {
        Some(i) => i,
        None => return -1,
    };
    let title = match cstr_to_string(title) {
        Some(t) => t,
        None => return -1,
    };
    let content = match cstr_to_string(content) {
        Some(c) => c,
        None => return -1,
    };
    match db::update_note(&id, &title, &content) {
        Ok(affected) => affected,
        Err(_) => -1,
    }
}

#[no_mangle]
pub extern "C" fn devnote_delete_note(id: *const c_char) -> i32 {
    let id = match cstr_to_string(id) {
        Some(i) => i,
        None => return -1,
    };
    match db::delete_note(&id) {
        Ok(affected) => affected,
        Err(_) => -1,
    }
}

#[no_mangle]
pub extern "C" fn devnote_create_folder(
    name: *const c_char,
    parent_id: *const c_char,
) -> *mut c_char {
    let name = match cstr_to_string(name) {
        Some(n) => n,
        None => return std::ptr::null_mut(),
    };
    let parent_id = cstr_to_string(parent_id);
    let pid = parent_id.as_deref();
    match db::create_folder(&name, pid) {
        Ok(folder) => {
            let json = serde_json::to_string(&folder).unwrap_or_default();
            string_to_cchar(json)
        }
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn devnote_list_folders() -> *mut c_char {
    match db::list_folders() {
        Ok(folders) => {
            let json = serde_json::to_string(&folders).unwrap_or_default();
            string_to_cchar(json)
        }
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn devnote_free_string(s: *mut c_char) {
    if s.is_null() {
        return;
    }
    unsafe {
        let _ = CString::from_raw(s);
    }
}
