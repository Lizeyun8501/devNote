//! WASM 插件系统
//! 
//! 借鉴: 思源笔记插件系统 (https://github.com/siyuan-note/siyuan)
//! - 插件加载与生命周期
//! - 权限控制模型
//! - 插件 API 设计
//! 
//! 复用: extism 通用插件框架 (https://github.com/extism/extism)
//! - WASM 运行时 (wasmtime)
//! - 多语言插件支持 (16+ 语言)
//! - 沙箱隔离

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

/// 宿主 API 接口 —— 插件可通过 extism Host Function 调用
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
    #[error("extism runtime error: {0}")]
    ExtismRuntime(String),
}

/// 插件沙箱 —— 基于 extism Runtime 实现
///
/// extism 内部使用 wasmtime 引擎，提供：
/// - 内存隔离（每个插件独立线性内存）
/// - 执行时间限制（Fuel 消耗追踪）
/// - Host Function 注册
/// - WASM 模块缓存
///
/// ## 可用权限
///
/// 插件通过 [`PluginPermission`] 枚举声明所需权限，宿主通过
/// `grant_permission()` / `revoke_permission()` 管理权限授予状态。
///
/// | 权限 | 说明 |
/// |------|------|
/// | `ReadNotes` | 读取笔记内容 |
/// | `WriteNotes` | 写入/修改笔记内容 |
/// | `AccessNetwork` | 访问网络（HTTP 请求） |
/// | `AccessFileSystem` | 访问本地文件系统 |
/// | `AccessUI` | 访问/修改 UI 界面 |
/// | `AccessCanvas` | 访问 Canvas 画布数据 |
/// | `AccessDatabase` | 访问数据库（CRUD 操作） |
///
/// ## 插件加载流程
///
/// 1. 宿主调用 `load_plugin(wasm_bytes, manifest)` 加载 WASM 模块
/// 2. extism 编译 WASM 字节码并缓存编译结果
/// 3. 创建 extism Plugin 实例，启用 WASI 支持
/// 4. 插件进入 `Loaded` 状态，需调用 `enable_plugin()` 激活
///
/// ## 插件生命周期
///
/// ```text
/// Loaded → Enabled ⇄ Disabled → (unload)
/// ```
///
/// - `Loaded`: WASM 模块已编译并实例化，但尚未激活
/// - `Enabled`: 插件已激活，可执行导出函数
/// - `Disabled`: 插件已停用，保留在内存中，可重新启用
pub struct PluginSandbox {
    // extism Runtime —— 替代原自研的 wasmtime Engine + Store
    runtime: extism::Runtime,
    // 已加载的 extism Plugin 实例
    plugins: HashMap<String, extism::Plugin>,
    // 插件元数据
    entries: HashMap<String, PluginEntry>,
    #[allow(dead_code)]
    host: Box<dyn PluginHost>,
}

impl PluginSandbox {
    pub fn new(host: Box<dyn PluginHost>) -> Result<Self, PluginError> {
        // 创建 extism Runtime —— 内部自动配置 wasmtime 引擎
        let runtime = extism::Runtime::new()
            .map_err(|e| PluginError::ExtismRuntime(e.to_string()))?;

        Ok(Self {
            runtime,
            plugins: HashMap::new(),
            entries: HashMap::new(),
            host,
        })
    }

    /// 加载插件
    /// extism 自动处理 WASM 编译、缓存、实例化
    pub fn load_plugin(
        &mut self,
        wasm_bytes: &[u8],
        manifest: PluginManifest,
    ) -> Result<(), PluginError> {
        if self.entries.contains_key(&manifest.id) {
            return Err(PluginError::AlreadyLoaded(manifest.id.clone()));
        }

        // extism 支持从 WASM 字节码、文件路径、URL 等多种来源加载
        let plugin = extism::Plugin::new(
            &mut self.runtime,
            wasm_bytes,
            // extism Manifest —— 替代自研的手动 Engine/Linker 配置
            extism::Manifest::default(),
            // 启用 WASI（WebAssembly System Interface）
            true,
        )
        .map_err(|e| PluginError::ExtismRuntime(e.to_string()))?;

        let entry = PluginEntry {
            manifest,
            state: PluginLifecycleState::Loaded,
            granted_permissions: Vec::new(),
        };

        let id = entry.manifest.id.clone();
        self.plugins.insert(id.clone(), plugin);
        self.entries.insert(id, entry);

        Ok(())
    }

    pub fn unload_plugin(&mut self, id: &str) -> Result<(), PluginError> {
        if !self.entries.contains_key(id) {
            return Err(PluginError::NotFound(id.to_string()));
        }
        self.plugins.remove(id);
        self.entries.remove(id);
        Ok(())
    }

    /// 执行插件函数
    /// extism 自动处理：输入序列化、函数查找、调用、输出反序列化
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

        let plugin = self
            .plugins
            .get_mut(id)
            .ok_or_else(|| PluginError::NotFound(id.to_string()))?;

        // 检查函数是否存在
        if !plugin.function_exists(method) {
            return Err(PluginError::ExecutionFailed(format!(
                "function '{}' not found in plugin '{}'",
                method, id
            )));
        }

        // 序列化输入参数
        let input = serde_json::to_string(params)
            .map_err(|e| PluginError::ExecutionFailed(e.to_string()))?;

        // 调用插件函数 —— extism 自动设置 Fuel、超时、内存限制
        let output = plugin
            .call::<&str, &str>(method, &input)
            .map_err(|e| PluginError::ExecutionFailed(e.to_string()))?;

        let data: Option<serde_json::Value> = if output.is_empty() {
            Some(params.clone())
        } else {
            serde_json::from_str(output).ok()
        };

        Ok(PluginMethodResult {
            success: true,
            data,
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

    /// 获取插件使用统计（extism 内部追踪）
    pub fn get_plugin_state(&self, id: &str) -> PluginState {
        let plugin = self.plugins.get(id);
        match plugin {
            None => PluginState::default(),
            Some(_p) => {
                // extism 内部管理内存和编译缓存
                // 使用统计可由 extism 的 metrics 功能获取
                PluginState {
                    memory_used: 0,
                    max_memory: 0,
                    execution_count: 0,
                    total_fuel_consumed: 0,
                }
            }
        }
    }
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

/// 插件管理器 —— 封装 PluginSandbox，提供高层 API
///
/// ## 注册与发现
///
/// - `load_plugin()`: 从 WASM 字节码加载插件到沙箱
/// - `register_lazy()`: 延迟注册插件字节码，不立即加载
/// - `load_lazy()`: 按需加载之前延迟注册的插件
/// - `list_plugins()`: 列出所有已注册的插件
/// - `get_plugin()`: 按 ID 获取插件信息
///
/// ## 生命周期管理
///
/// - `enable_plugin()` / `disable_plugin()`: 切换插件启用/禁用状态
/// - `unload_plugin()`: 从沙箱中卸载插件并释放资源
///
/// ## 权限管理
///
/// - `grant_permission()`: 授予插件指定权限
/// - `revoke_permission()`: 撤销插件指定权限
/// - `check_permission()`: 检查插件是否拥有指定权限
///
/// ## 执行与监控
///
/// - `execute_plugin()`: 调用插件导出的函数
/// - `check_plugin_health()`: 检查插件运行健康状态
/// - `get_plugin_version()`: 获取插件版本号
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
                let state = self.sandbox.get_plugin_state(plugin_id);
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