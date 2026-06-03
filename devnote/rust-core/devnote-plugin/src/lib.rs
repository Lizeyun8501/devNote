use devnote_observe::{instrument, warn};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PluginManifest {
    pub id: String,
    pub name: String,
    pub version: String,
    pub description: String,
    pub author: String,
    pub permissions: Vec<PluginPermission>,
    pub api_version: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum PluginPermission {
    ReadNotes,
    WriteNotes,
    AccessNetwork,
    AccessFileSystem,
    AccessUI,
    AccessCanvas,
    AccessDatabase,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PluginMethodResult {
    pub success: bool,
    pub data: Option<serde_json::Value>,
    pub error: Option<String>,
}

pub trait PluginAPI: Send + Sync {
    fn read_note(&self, id: &str) -> Result<Option<serde_json::Value>, anyhow::Error>;
    fn write_note(&self, id: &str, content: &serde_json::Value) -> Result<(), anyhow::Error>;
    fn search_notes(&self, query: &str) -> Result<Vec<serde_json::Value>, anyhow::Error>;
    fn show_notification(&self, message: &str) -> Result<(), anyhow::Error>;
}

pub trait PluginHost: Send + Sync {
    fn get_api(&self) -> &dyn PluginAPI;
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PluginLifecycleState {
    Loaded,
    Enabled,
    Disabled,
}

#[derive(Debug, Clone)]
pub struct PluginEntry {
    pub manifest: PluginManifest,
    pub state: PluginLifecycleState,
    pub granted_permissions: Vec<PluginPermission>,
}

#[derive(Debug, thiserror::Error)]
pub enum PluginError {
    #[error("plugin not found: {0}")]
    NotFound(String),
    #[error("permission denied: {0:?}")]
    PermissionDenied(PluginPermission),
    #[error("plugin already loaded: {0}")]
    AlreadyLoaded(String),
    #[error("plugin execution failed: {0}")]
    ExecutionFailed(String),
    #[error("invalid manifest: {0}")]
    InvalidManifest(String),
    #[error("wasm runtime error: {0}")]
    WasmRuntime(String),
}

#[cfg(feature = "wasm")]
pub struct PluginSandbox {
    engine: wasmtime::Engine,
    store: wasmtime::Store<()>,
    instances: HashMap<String, wasmtime::Instance>,
    entries: HashMap<String, PluginEntry>,
    #[allow(dead_code)]
    host: Box<dyn PluginHost>,
}

#[cfg(feature = "wasm")]
impl PluginSandbox {
    pub fn new(host: Box<dyn PluginHost>) -> Result<Self, PluginError> {
        let engine = wasmtime::Engine::default();
        let store = wasmtime::Store::new(&engine, ());
        Ok(Self {
            engine,
            store,
            instances: HashMap::new(),
            entries: HashMap::new(),
            host,
        })
    }

    #[instrument]
    pub fn load_plugin(
        &mut self,
        wasm_bytes: &[u8],
        manifest: PluginManifest,
    ) -> Result<(), PluginError> {
        if self.entries.contains_key(&manifest.id) {
            return Err(PluginError::AlreadyLoaded(manifest.id.clone()));
        }

        let module = wasmtime::Module::new(&self.engine, wasm_bytes)
            .map_err(|e| PluginError::WasmRuntime(e.to_string()))?;

        let instance = wasmtime::Linker::new(&self.engine)
            .instantiate(&mut self.store, &module)
            .map_err(|e| PluginError::WasmRuntime(e.to_string()))?;

        let entry = PluginEntry {
            manifest,
            state: PluginLifecycleState::Loaded,
            granted_permissions: Vec::new(),
        };

        self.instances.insert(entry.manifest.id.clone(), instance);
        self.entries.insert(entry.manifest.id.clone(), entry);

        Ok(())
    }

    #[instrument]
    pub fn unload_plugin(&mut self, id: &str) -> Result<(), PluginError> {
        if !self.entries.contains_key(id) {
            return Err(PluginError::NotFound(id.to_string()));
        }
        self.instances.remove(id);
        self.entries.remove(id);
        Ok(())
    }

    #[instrument]
    pub fn execute_plugin(
        &mut self,
        id: &str,
        method: &str,
        params: &serde_json::Value,
    ) -> Result<PluginMethodResult, PluginError> {
        let entry = self
            .entries
            .get(id)
            .ok_or_else(|| PluginError::NotFound(id.to_string()))?;

        if entry.state != PluginLifecycleState::Enabled {
            return Err(PluginError::ExecutionFailed(format!(
                "plugin {} is not enabled",
                id
            )));
        }

        let instance = self
            .instances
            .get(id)
            .ok_or_else(|| PluginError::NotFound(id.to_string()))?;

        let func = instance
            .get_typed_func::<(), i32>(&mut self.store, method)
            .map_err(|e| PluginError::ExecutionFailed(e.to_string()))?;

        func.call(&mut self.store, ())
            .map_err(|e| PluginError::ExecutionFailed(e.to_string()))?;

        Ok(PluginMethodResult {
            success: true,
            data: Some(params.clone()),
            error: None,
        })
    }

    pub fn check_permission(
        &self,
        id: &str,
        permission: PluginPermission,
    ) -> Result<bool, PluginError> {
        let entry = self
            .entries
            .get(id)
            .ok_or_else(|| PluginError::NotFound(id.to_string()))?;
        Ok(entry.granted_permissions.contains(&permission))
    }
}

#[cfg(not(feature = "wasm"))]
pub struct PluginSandbox {
    entries: HashMap<String, PluginEntry>,
    host: Box<dyn PluginHost>,
}

#[cfg(not(feature = "wasm"))]
impl PluginSandbox {
    pub fn new(host: Box<dyn PluginHost>) -> Result<Self, PluginError> {
        Ok(Self {
            entries: HashMap::new(),
            host,
        })
    }

    pub fn load_plugin(
        &mut self,
        _wasm_bytes: &[u8],
        manifest: PluginManifest,
    ) -> Result<(), PluginError> {
        if self.entries.contains_key(&manifest.id) {
            return Err(PluginError::AlreadyLoaded(manifest.id.clone()));
        }

        let entry = PluginEntry {
            manifest,
            state: PluginLifecycleState::Loaded,
            granted_permissions: Vec::new(),
        };

        self.entries.insert(entry.manifest.id.clone(), entry);
        Ok(())
    }

    pub fn unload_plugin(&mut self, id: &str) -> Result<(), PluginError> {
        if !self.entries.contains_key(id) {
            return Err(PluginError::NotFound(id.to_string()));
        }
        self.entries.remove(id);
        Ok(())
    }

    pub fn execute_plugin(
        &mut self,
        id: &str,
        method: &str,
        params: &serde_json::Value,
    ) -> Result<PluginMethodResult, PluginError> {
        let entry = self
            .entries
            .get(id)
            .ok_or_else(|| PluginError::NotFound(id.to_string()))?;

        if entry.state != PluginLifecycleState::Enabled {
            return Err(PluginError::ExecutionFailed(format!(
                "plugin {} is not enabled",
                id
            )));
        }

        let api = self.host.get_api();
        let _ = (method, params, api);

        Ok(PluginMethodResult {
            success: true,
            data: Some(params.clone()),
            error: None,
        })
    }

    pub fn check_permission(
        &self,
        id: &str,
        permission: PluginPermission,
    ) -> Result<bool, PluginError> {
        let entry = self
            .entries
            .get(id)
            .ok_or_else(|| PluginError::NotFound(id.to_string()))?;
        Ok(entry.granted_permissions.contains(&permission))
    }
}

pub struct PluginManager {
    sandbox: PluginSandbox,
    lazy_loaded: HashMap<String, Vec<u8>>,
}

impl PluginManager {
    pub fn new(host: Box<dyn PluginHost>) -> Result<Self, PluginError> {
        let sandbox = PluginSandbox::new(host)?;
        Ok(Self {
            sandbox,
            lazy_loaded: HashMap::new(),
        })
    }

    pub fn load_plugin(
        &mut self,
        wasm_bytes: &[u8],
        manifest: PluginManifest,
    ) -> Result<(), PluginError> {
        self.sandbox.load_plugin(wasm_bytes, manifest)
    }

    pub fn unload_plugin(&mut self, id: &str) -> Result<(), PluginError> {
        self.sandbox.unload_plugin(id)
    }

    pub fn enable_plugin(&mut self, id: &str) -> Result<(), PluginError> {
        let entry = self
            .sandbox
            .entries
            .get_mut(id)
            .ok_or_else(|| PluginError::NotFound(id.to_string()))?;
        entry.state = PluginLifecycleState::Enabled;
        Ok(())
    }

    pub fn disable_plugin(&mut self, id: &str) -> Result<(), PluginError> {
        let entry = self
            .sandbox
            .entries
            .get_mut(id)
            .ok_or_else(|| PluginError::NotFound(id.to_string()))?;
        entry.state = PluginLifecycleState::Disabled;
        Ok(())
    }

    pub fn execute_plugin(
        &mut self,
        id: &str,
        method: &str,
        params: &serde_json::Value,
    ) -> Result<PluginMethodResult, PluginError> {
        self.sandbox.execute_plugin(id, method, params)
    }

    pub fn grant_permission(
        &mut self,
        id: &str,
        permission: PluginPermission,
    ) -> Result<(), PluginError> {
        let entry = self
            .sandbox
            .entries
            .get_mut(id)
            .ok_or_else(|| PluginError::NotFound(id.to_string()))?;
        if !entry.granted_permissions.contains(&permission) {
            entry.granted_permissions.push(permission);
        }
        Ok(())
    }

    pub fn revoke_permission(
        &mut self,
        id: &str,
        permission: PluginPermission,
    ) -> Result<(), PluginError> {
        let entry = self
            .sandbox
            .entries
            .get_mut(id)
            .ok_or_else(|| PluginError::NotFound(id.to_string()))?;
        entry.granted_permissions.retain(|p| p != &permission);
        Ok(())
    }

    pub fn check_permission(
        &self,
        id: &str,
        permission: PluginPermission,
    ) -> Result<bool, PluginError> {
        self.sandbox.check_permission(id, permission)
    }

    pub fn get_plugin(&self, id: &str) -> Option<&PluginEntry> {
        self.sandbox.entries.get(id)
    }

    pub fn list_plugins(&self) -> Vec<&PluginEntry> {
        self.sandbox.entries.values().collect()
    }

    pub fn register_lazy(&mut self, id: String, wasm_bytes: Vec<u8>) {
        self.lazy_loaded.insert(id, wasm_bytes);
    }

    pub fn load_lazy(&mut self, id: &str, manifest: PluginManifest) -> Result<(), PluginError> {
        if let Some(bytes) = self.lazy_loaded.remove(id) {
            self.load_plugin(&bytes, manifest)?;
        }
        Ok(())
    }

    pub fn get_plugin_version(&self, id: &str) -> Option<&str> {
        self.sandbox
            .entries
            .get(id)
            .map(|e| e.manifest.version.as_str())
    }
}
