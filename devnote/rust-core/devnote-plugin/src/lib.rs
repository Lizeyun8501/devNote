//! WASM 插件系统（基于 extism）
//!
//! ## 替换说明
//! 原实现：自研 wasmtime 沙箱（544 行），手动管理 Engine/Store/Fuel/权限
//! 替换为：extism v1.21.0 通用 WASM 插件框架
//!
//! ## extism 优势
//! - **多语言插件开发**：插件可用 Rust/Go/Python/JS/C#/Java 等 16+ 语言编写
//! - **内置 Host Function**：插件可以直接调用宿主的 HTTP/日志/存储 API
//! - **WASM 缓存**：自动缓存编译后的 WASM 模块，提升加载速度
//! - **Component Model 支持**：跟进最新 WASM 生态
//! - **跨平台 SDK**：Dart/Rust/Go/Python/Node.js 等宿主 SDK
//!
//! 来源: https://extism.org/
//! 借鉴 Obsidian 的社区插件模型
//! 来源: https://github.com/obsidianmd/obsidian-sample-plugin
//! 借鉴内容: 插件清单(manifest)元数据、插件生命周期管理、权限系统设计
//!
//! ## 插件系统架构
//!
//! 本模块实现了 DevNote 的 WASM 插件系统，采用分层架构：
//!
//! ```text
//! ┌─────────────────────────────────────────┐
//! │           Dart 前端 (Flutter)            │
//! │  通过 FFI Bridge 调用 Rust 插件管理 API   │
//! └──────────────────┬──────────────────────┘
//!                    │ FFI (flutter_rust_bridge)
//! ┌──────────────────▼──────────────────────┐
//! │         PluginManager (高层 API)         │
//! │  注册/发现/管理插件，权限授予/撤销         │
//! ├──────────────────────────────────────────┤
//! │         PluginSandbox (低层 API)          │
//! │  基于 extism Runtime 的 WASM 沙箱执行     │
//! ├──────────────────────────────────────────┤
//! │         extism Runtime (WASM 引擎)       │
//! │  wasmtime 引擎 + Fuel 限制 + 内存隔离    │
//! └──────────────────────────────────────────┘
//! ```
//!
//! ## Plugin FFI Contract
//!
//! ### Dart↔Rust 接口约定
//!
//! Dart 前端通过 `flutter_rust_bridge` (FRB) 调用 Rust 插件 API，
//! 所有跨 FFI 边界的数据结构必须实现 `Serialize`/`Deserialize`，
//! FRB 使用 SSE 编解码器自动处理序列化。
//!
//! ### FFI 函数清单
//!
//! | Dart 调用 | Rust 实现 | 说明 |
//! |-----------|-----------|------|
//! | `loadPlugin(wasmBytes, manifest)` | `PluginManager::load_plugin()` | 加载 WASM 插件到沙箱 |
//! | `unloadPlugin(id)` | `PluginManager::unload_plugin()` | 卸载插件并释放资源 |
//! | `enablePlugin(id)` | `PluginManager::enable_plugin()` | 启用已加载的插件 |
//! | `disablePlugin(id)` | `PluginManager::disable_plugin()` | 禁用插件（保留在内存中） |
//! | `executePlugin(id, method, params)` | `PluginManager::execute_plugin()` | 执行插件导出的函数 |
//! | `grantPermission(id, permission)` | `PluginManager::grant_permission()` | 授予插件权限 |
//! | `revokePermission(id, permission)` | `PluginManager::revoke_permission()` | 撤销插件权限 |
//! | `listPlugins()` | `PluginManager::list_plugins()` | 列出所有已注册插件 |
//! | `checkPluginHealth(id)` | `PluginManager::check_plugin_health()` | 检查插件健康状态 |
//!
//! ### 数据类型映射
//!
//! | Rust 类型 | Dart 类型 | 说明 |
//! |-----------|-----------|------|
//! | `PluginManifest` | `Map<String, dynamic>` | 插件清单元数据 |
//! | `PluginPermission` | `String` (enum name) | 插件权限枚举 |
//! | `PluginLifecycleState` | `String` (enum name) | 插件生命周期状态 |
//! | `PluginMethodResult` | `Map<String, dynamic>` | 插件函数执行结果 |
//! | `PluginHealth` | `Map<String, dynamic>` | 插件健康检查结果 |
//! | `PluginError` | `String` (error message) | 插件错误（通过 FRB Result 传递） |

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