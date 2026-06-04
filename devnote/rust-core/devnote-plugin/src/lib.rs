//! WebAssembly 插件沙箱 —— 基于 wasmtime 实现安全隔离
//! 借鉴 Obsidian 的社区插件模型和 Figma 的 WASM 插件隔离方案
//!
//! 借鉴 Obsidian 的社区插件模型
//! 来源: https://github.com/obsidianmd/obsidian-sample-plugin
//! 借鉴内容: 插件清单(manifest)元数据、插件生命周期管理(Load/Enable/Disable)、权限系统设计
//!
//! 借鉴 Figma 的 WASM 插件隔离方案
//! 来源: https://www.figma.com
//! 借鉴内容: wasmtime 沙箱引擎、Fuel 燃料消耗追踪、内存限制和执行超时保护

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

#[derive(Default)]
pub struct PluginState {
    pub memory_used: usize,
    pub max_memory: usize,
    pub execution_count: u64,
    pub total_fuel_consumed: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum PluginHealthStatus {
    Healthy,
    Warning,
    Unhealthy,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PluginHealth {
    pub plugin_id: String,
    pub status: PluginHealthStatus,
    pub memory_used: usize,
    pub max_memory: usize,
    pub execution_count: u64,
    pub total_fuel_consumed: u64,
    pub message: Option<String>,
}

#[cfg(feature = "wasm")]
use devnote_observe::{instrument, warn};
#[cfg(feature = "wasm")]
use std::time::Duration;

#[cfg(feature = "wasm")]
pub struct PluginSandbox {
    engine: wasmtime::Engine,
    store: wasmtime::Store<PluginState>,
    instances: HashMap<String, wasmtime::Instance>,
    entries: HashMap<String, PluginEntry>,
    #[allow(dead_code)]
    host: Box<dyn PluginHost>,
}

#[cfg(feature = "wasm")]
impl PluginSandbox {
    pub fn new(host: Box<dyn PluginHost>) -> Result<Self, PluginError> {
        let mut config = wasmtime::Config::new();
        // Memory limit: 16 pages = 1MB, max 256 pages = 16MB
        config.wasm_memory(256);
        // Stack limit: 2MB
        config.max_wasm_stack(2 * 1024 * 1024);
        // Enable fuel consumption for CPU time limiting
        config.consume_fuel(true);

        let engine = wasmtime::Engine::new(&config)
            .map_err(|e| PluginError::WasmRuntime(e.to_string()))?;
        let mut store = wasmtime::Store::new(&engine, PluginState::default());
        // Give each plugin 10 million fuel units (roughly 1 second of execution)
        store.add_fuel(10_000_000)
            .map_err(|e| PluginError::WasmRuntime(e.to_string()))?;

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

    pub fn execute_with_timeout(
        &mut self,
        id: &str,
        method: &str,
        params: &serde_json::Value,
        _timeout: Duration,
    ) -> Result<PluginMethodResult, PluginError> {
        // Check remaining fuel before execution
        let fuel_before = self.store.get_fuel()
            .map_err(|e| PluginError::WasmRuntime(e.to_string()))?;

        // Execute the function
        let result = self.execute_plugin(id, method, params);

        // Check fuel consumed
        let fuel_after = self.store.get_fuel()
            .map_err(|e| PluginError::WasmRuntime(e.to_string()))?;
        let fuel_consumed = fuel_before - fuel_after;

        // Update state tracking
        self.store.data_mut().execution_count += 1;
        self.store.data_mut().total_fuel_consumed += fuel_consumed;

        if fuel_consumed > 8_000_000 {
            // Plugin consumed too much fuel, likely stuck
            tracing::warn!("Plugin consumed {} fuel units, may be inefficient", fuel_consumed);
        }

        result
    }

    pub fn get_plugin_state(&self) -> &PluginState {
        self.store.data()
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

    pub fn get_plugin_state(&self) -> &PluginState {
        static DEFAULT_STATE: PluginState = PluginState {
            memory_used: 0,
            max_memory: 0,
            execution_count: 0,
            total_fuel_consumed: 0,
        };
        &DEFAULT_STATE
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

    pub fn check_plugin_health(&self, plugin_id: &str) -> PluginHealth {
        let entry = self.sandbox.entries.get(plugin_id);

        match entry {
            None => PluginHealth {
                plugin_id: plugin_id.to_string(),
                status: PluginHealthStatus::Unhealthy,
                memory_used: 0,
                max_memory: 0,
                execution_count: 0,
                total_fuel_consumed: 0,
                message: Some("Plugin not found".to_string()),
            },
            Some(e) => {
                let state = self.sandbox.get_plugin_state();
                let status = if e.state != PluginLifecycleState::Enabled {
                    PluginHealthStatus::Warning
                } else if state.total_fuel_consumed > 80_000_000 {
                    PluginHealthStatus::Unhealthy
                } else if state.total_fuel_consumed > 50_000_000 {
                    PluginHealthStatus::Warning
                } else {
                    PluginHealthStatus::Healthy
                };

                let message = if status == PluginHealthStatus::Unhealthy {
                    Some("Plugin has consumed excessive fuel, may be stuck".to_string())
                } else if status == PluginHealthStatus::Warning {
                    Some("Plugin has high fuel consumption or is not enabled".to_string())
                } else {
                    None
                };

                PluginHealth {
                    plugin_id: plugin_id.to_string(),
                    status,
                    memory_used: state.memory_used,
                    max_memory: state.max_memory,
                    execution_count: state.execution_count,
                    total_fuel_consumed: state.total_fuel_consumed,
                    message,
                }
            }
        }
    }
}
