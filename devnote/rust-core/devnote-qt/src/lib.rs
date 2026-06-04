//! Rust FFI bindings for the DevNote Qt bridge library.
//!
//! Provides a safe Rust API over the C ABI exported by `libdevnote_qt_bridge`.
//! The library is loaded dynamically at runtime via `libloading`.  When the
//! shared library is not available a `QtNotAvailable` error is returned
//! instead of panicking, allowing smooth fallback to the Flutter canvas.

use devnote_observe::{instrument};
use libloading::{Library, Symbol};
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::ffi::{c_char, c_int, CStr, CString};
use std::path::PathBuf;
use thiserror::Error;

// ---------------------------------------------------------------------------
// Error
// ---------------------------------------------------------------------------

#[derive(Debug, Error)]
pub enum QtBridgeError {
    #[error("Qt shared library not available at any expected path")]
    QtNotAvailable,

    #[error("Qt not initialized")]
    QtNotInitialized,

    #[error("canvas not found")]
    CanvasNotFound,

    #[error("dynamic library error: {0}")]
    LoadError(#[from] libloading::Error),

    #[error("null pointer argument")]
    NullPointer,
}

// ---------------------------------------------------------------------------
// Data types (matching Obsidian Canvas format)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CanvasNode {
    pub id: String,
    #[serde(rename = "type")]
    pub node_type: String,
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub content: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub color: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub file: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CanvasEdge {
    pub id: String,
    #[serde(rename = "fromNode")]
    pub from_node: String,
    #[serde(rename = "toNode")]
    pub to_node: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub color: Option<String>,
    #[serde(rename = "fromSide", skip_serializing_if = "Option::is_none")]
    pub from_side: Option<String>,
    #[serde(rename = "toSide", skip_serializing_if = "Option::is_none")]
    pub to_side: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CanvasData {
    pub nodes: Vec<CanvasNode>,
    pub edges: Vec<CanvasEdge>,
}

/// Callback event type constants.
pub mod event {
    pub const NODE_MOVED: &str = "node_moved";
    pub const NODE_CLICKED: &str = "node_clicked";
    pub const NODE_DOUBLE_CLICKED: &str = "node_double_clicked";
    pub const EDGE_CREATED: &str = "edge_created";
    pub const CANVAS_CLICKED: &str = "canvas_clicked";
}

// ---------------------------------------------------------------------------
// Raw FFI function pointer types
// ---------------------------------------------------------------------------

type FnQtInit = unsafe extern "C" fn(c_int, *mut *mut c_char) -> c_int;
type FnQtDestroy = unsafe extern "C" fn();
type FnCreateCanvas = unsafe extern "C" fn(*mut std::ffi::c_void) -> *mut std::ffi::c_void;
type FnDestroyCanvas = unsafe extern "C" fn(*mut std::ffi::c_void);
type FnAddNode = unsafe extern "C" fn(
    *mut std::ffi::c_void,
    *const c_char,
    *const c_char,
    f64,
    f64,
    f64,
    f64,
);
type FnUpdateNode = unsafe extern "C" fn(*mut std::ffi::c_void, *const c_char, f64, f64, f64, f64);
type FnRemoveNode = unsafe extern "C" fn(*mut std::ffi::c_void, *const c_char);
type FnAddEdge = unsafe extern "C" fn(
    *mut std::ffi::c_void,
    *const c_char,
    *const c_char,
    *const c_char,
    *const c_char,
);
type FnRemoveEdge = unsafe extern "C" fn(*mut std::ffi::c_void, *const c_char);
type FnClearCanvas = unsafe extern "C" fn(*mut std::ffi::c_void);
type FnSetCallback =
    unsafe extern "C" fn(*mut std::ffi::c_void, Option<unsafe extern "C" fn(*const c_char, *const c_char)>);
type FnSetZoom = unsafe extern "C" fn(*mut std::ffi::c_void, f64);
type FnFitAll = unsafe extern "C" fn(*mut std::ffi::c_void);
type FnExportImage = unsafe extern "C" fn(*mut std::ffi::c_void, *const c_char);
type FnLoadJson = unsafe extern "C" fn(*mut std::ffi::c_void, *const c_char);
type FnSaveJson = unsafe extern "C" fn(*mut std::ffi::c_void) -> *mut c_char;
type FnFreeString = unsafe extern "C" fn(*mut c_char);

// ---------------------------------------------------------------------------
// FFI table – holds the dynamically loaded function pointers
// ---------------------------------------------------------------------------

struct FfiTable {
    _lib: &'static Library,

    qt_init: Symbol<'static, FnQtInit>,
    qt_destroy: Symbol<'static, FnQtDestroy>,
    create_canvas: Symbol<'static, FnCreateCanvas>,
    destroy_canvas: Symbol<'static, FnDestroyCanvas>,
    add_node: Symbol<'static, FnAddNode>,
    update_node: Symbol<'static, FnUpdateNode>,
    remove_node: Symbol<'static, FnRemoveNode>,
    add_edge: Symbol<'static, FnAddEdge>,
    remove_edge: Symbol<'static, FnRemoveEdge>,
    clear_canvas: Symbol<'static, FnClearCanvas>,
    set_callback: Symbol<'static, FnSetCallback>,
    set_zoom: Symbol<'static, FnSetZoom>,
    fit_all: Symbol<'static, FnFitAll>,
    export_image: Symbol<'static, FnExportImage>,
    load_json: Symbol<'static, FnLoadJson>,
    save_json: Symbol<'static, FnSaveJson>,
    free_string: Symbol<'static, FnFreeString>,
}

// ---------------------------------------------------------------------------
// Global callback registry
// ---------------------------------------------------------------------------

type RustCallback = Box<dyn Fn(&str, &str) + Send + 'static>;

static CALLBACK_REGISTRY: Mutex<Option<HashMap<usize, RustCallback>>> = Mutex::new(None);

unsafe extern "C" fn c_trampoline(event_type: *const c_char, json_data: *const c_char) {
    if event_type.is_null() || json_data.is_null() {
        return;
    }
    let ev = match CStr::from_ptr(event_type).to_str() {
        Ok(s) => s,
        Err(_) => return,
    };
    let data = match CStr::from_ptr(json_data).to_str() {
        Ok(s) => s,
        Err(_) => return,
    };

    let guard = CALLBACK_REGISTRY.lock();
    if let Some(ref map) = *guard {
        // The C trampoline is global – we iterate all registered callbacks.
        // This works because in practice we only register one callback per
        // process.  For multi-canvas setups, extend the key to be per-canvas.
        for cb in map.values() {
            cb(ev, data);
        }
    }
}

fn register_callback(handle: *mut std::ffi::c_void, cb: RustCallback) {
    let mut guard = CALLBACK_REGISTRY.lock();
    if guard.is_none() {
        *guard = Some(HashMap::new());
    }
    guard.as_mut().unwrap().insert(handle as usize, cb);
}

fn unregister_callback(handle: *mut std::ffi::c_void) {
    let mut guard = CALLBACK_REGISTRY.lock();
    if let Some(ref mut map) = *guard {
        map.remove(&(handle as usize));
    }
}

// ---------------------------------------------------------------------------
// QtBridge – main entry point
// ---------------------------------------------------------------------------

/// High-level bridge to the native Qt shared library.
///
/// # Example
///
/// ```ignore
/// let bridge = QtBridge::new()?;
/// bridge.init()?;
/// let canvas = bridge.create_canvas(std::ptr::null_mut())?;
/// canvas.add_node("n1", "Hello", 100.0, 100.0, 200.0, 120.0)?;
/// ```
pub struct QtBridge {
    ffi: FfiTable,
    initialized: Mutex<bool>,
}

impl QtBridge {
    /// Attempt to load the Qt bridge shared library.
    ///
    /// Searches common paths:
    /// - `./libdevnote_qt_bridge.so` (or `.dylib` / `.dll`)
    /// - The executable's directory
    /// - System library paths via `libloading`
    #[instrument]
    pub fn new() -> Result<Self, QtBridgeError> {
        let lib_path = Self::find_library()?;
        unsafe {
            // Leak the Library so that all Symbol references are 'static.
            // The library is intentionally loaded for the lifetime of the process.
            let lib = Box::leak(Box::new(Library::new(&lib_path)?));

            let ffi = FfiTable {
                qt_init: lib.get(b"devnote_qt_init\0")?,
                qt_destroy: lib.get(b"devnote_qt_destroy\0")?,
                create_canvas: lib.get(b"devnote_qt_create_canvas\0")?,
                destroy_canvas: lib.get(b"devnote_qt_destroy_canvas\0")?,
                add_node: lib.get(b"devnote_qt_canvas_add_node\0")?,
                update_node: lib.get(b"devnote_qt_canvas_update_node\0")?,
                remove_node: lib.get(b"devnote_qt_canvas_remove_node\0")?,
                add_edge: lib.get(b"devnote_qt_canvas_add_edge\0")?,
                remove_edge: lib.get(b"devnote_qt_canvas_remove_edge\0")?,
                clear_canvas: lib.get(b"devnote_qt_canvas_clear\0")?,
                set_callback: lib.get(b"devnote_qt_canvas_set_callback\0")?,
                set_zoom: lib.get(b"devnote_qt_canvas_set_zoom\0")?,
                fit_all: lib.get(b"devnote_qt_canvas_fit_all\0")?,
                export_image: lib.get(b"devnote_qt_canvas_export_image\0")?,
                load_json: lib.get(b"devnote_qt_canvas_load_json\0")?,
                save_json: lib.get(b"devnote_qt_canvas_save_json\0")?,
                free_string: lib.get(b"devnote_qt_free_string\0")?,
                _lib: lib,
            };

            Ok(Self {
                ffi,
                initialized: Mutex::new(false),
            })
        }
    }

    /// Initialize the Qt application. Safe to call multiple times.
    pub fn init(&self) -> Result<(), QtBridgeError> {
        let mut init = self.initialized.lock();
        if *init {
            return Ok(());
        }
        let ret = unsafe { (self.ffi.qt_init)(0, std::ptr::null_mut()) };
        if ret != 0 {
            return Err(QtBridgeError::QtNotInitialized);
        }
        *init = true;
        Ok(())
    }

    /// Destroy the Qt application. After this call the bridge is unusable.
    pub fn destroy(&self) {
        let mut init = self.initialized.lock();
        if *init {
            unsafe { (self.ffi.qt_destroy)() };
            *init = false;
        }
    }

    /// Create a new canvas widget attached to `parent_window_handle`.
    /// Pass `std::ptr::null_mut()` for a top-level window.
    pub fn create_canvas(
        &self,
        parent_window_handle: *mut std::ffi::c_void,
    ) -> Result<QtCanvas<'_>, QtBridgeError> {
        let handle = unsafe { (self.ffi.create_canvas)(parent_window_handle) };
        if handle.is_null() {
            return Err(QtBridgeError::CanvasNotFound);
        }
        Ok(QtCanvas {
            handle,
            ffi: &self.ffi,
        })
    }

    /// Locate the shared library on the filesystem.
    fn find_library() -> Result<PathBuf, QtBridgeError> {
        #[cfg(target_os = "linux")]
        const LIB_NAME: &str = "libdevnote_qt_bridge.so";
        #[cfg(target_os = "macos")]
        const LIB_NAME: &str = "libdevnote_qt_bridge.dylib";
        #[cfg(target_os = "windows")]
        const LIB_NAME: &str = "devnote_qt_bridge.dll";

        // 1. Next to the executable (current dir fallback)
        let candidate = std::env::current_dir()
            .unwrap_or_default()
            .join(LIB_NAME);
        if candidate.exists() {
            return Ok(candidate);
        }

        // 2. EXE directory
        if let Ok(exe) = std::env::current_exe() {
            if let Some(dir) = exe.parent() {
                let p = dir.join(LIB_NAME);
                if p.exists() {
                    return Ok(p);
                }
            }
        }

        // 3. Try system loader (LD_LIBRARY_PATH / PATH / rpath)
        // Just use the name without path – libloading will search.
        Ok(PathBuf::from(LIB_NAME))
    }
}

impl Drop for QtBridge {
    fn drop(&mut self) {
        self.destroy();
    }
}

// ---------------------------------------------------------------------------
// QtCanvas – safe wrapper around a C canvas handle
// ---------------------------------------------------------------------------

/// A handle to a Qt `QGraphicsView` canvas created by the bridge.
///
/// All methods forward to the C ABI.  The canvas is destroyed on drop.
pub struct QtCanvas<'a> {
    handle: *mut std::ffi::c_void,
    ffi: &'a FfiTable,
}

impl<'a> QtCanvas<'a> {
    /// Returns the raw C handle.
    pub fn raw_handle(&self) -> *mut std::ffi::c_void {
        self.handle
    }

    // ---- Nodes ----

    pub fn add_node(&self, node_id: &str, content: &str, x: f64, y: f64, w: f64, h: f64) {
        let c_id = CString::new(node_id).unwrap();
        let c_content = CString::new(content).unwrap();
        unsafe {
            (self.ffi.add_node)(self.handle, c_id.as_ptr(), c_content.as_ptr(), x, y, w, h);
        }
    }

    pub fn update_node(&self, node_id: &str, x: f64, y: f64, w: f64, h: f64) {
        let c_id = CString::new(node_id).unwrap();
        unsafe {
            (self.ffi.update_node)(self.handle, c_id.as_ptr(), x, y, w, h);
        }
    }

    pub fn remove_node(&self, node_id: &str) {
        let c_id = CString::new(node_id).unwrap();
        unsafe {
            (self.ffi.remove_node)(self.handle, c_id.as_ptr());
        }
    }

    // ---- Edges ----

    pub fn add_edge(&self, edge_id: &str, source_id: &str, target_id: &str, label: &str) {
        let c_eid = CString::new(edge_id).unwrap();
        let c_src = CString::new(source_id).unwrap();
        let c_dst = CString::new(target_id).unwrap();
        let c_lbl = CString::new(label).unwrap();
        unsafe {
            (self.ffi.add_edge)(
                self.handle,
                c_eid.as_ptr(),
                c_src.as_ptr(),
                c_dst.as_ptr(),
                c_lbl.as_ptr(),
            );
        }
    }

    pub fn remove_edge(&self, edge_id: &str) {
        let c_id = CString::new(edge_id).unwrap();
        unsafe {
            (self.ffi.remove_edge)(self.handle, c_id.as_ptr());
        }
    }

    // ---- Canvas-level ----

    pub fn clear(&self) {
        unsafe {
            (self.ffi.clear_canvas)(self.handle);
        }
    }

    pub fn set_zoom(&self, zoom: f64) {
        unsafe {
            (self.ffi.set_zoom)(self.handle, zoom);
        }
    }

    pub fn fit_all(&self) {
        unsafe {
            (self.ffi.fit_all)(self.handle);
        }
    }

    pub fn export_image(&self, path: &str) {
        let c_path = CString::new(path).unwrap();
        unsafe {
            (self.ffi.export_image)(self.handle, c_path.as_ptr());
        }
    }

    // ---- JSON ----

    /// Load canvas data from an Obsidian Canvas JSON string.
    pub fn load_json(&self, json: &str) {
        let c_json = CString::new(json).unwrap();
        unsafe {
            (self.ffi.load_json)(self.handle, c_json.as_ptr());
        }
    }

    /// Save the current canvas state as an Obsidian Canvas JSON string.
    pub fn save_json(&self) -> Result<String, QtBridgeError> {
        unsafe {
            let ptr = (self.ffi.save_json)(self.handle);
            if ptr.is_null() {
                return Err(QtBridgeError::NullPointer);
            }
            let s = CStr::from_ptr(ptr).to_string_lossy().into_owned();
            (self.ffi.free_string)(ptr);
            Ok(s)
        }
    }

    // ---- Callback ----

    /// Register a callback for Qt canvas events.
    ///
    /// The closure receives `(event_type, json_data)` pairs.  See the
    /// `event` module for well-known event type strings.
    /// Pass `None` to unregister.
    pub fn set_callback<F>(&self, callback: Option<F>)
    where
        F: Fn(&str, &str) + Send + 'static,
    {
        if let Some(cb) = callback {
            register_callback(self.handle, Box::new(cb));
            unsafe {
                (self.ffi.set_callback)(self.handle, Some(c_trampoline));
            }
        } else {
            unregister_callback(self.handle);
            unsafe {
                (self.ffi.set_callback)(self.handle, None);
            }
        }
    }
}

impl<'a> Drop for QtCanvas<'a> {
    fn drop(&mut self) {
        unregister_callback(self.handle);
        unsafe {
            (self.ffi.set_callback)(self.handle, None);
            (self.ffi.destroy_canvas)(self.handle);
        }
    }
}