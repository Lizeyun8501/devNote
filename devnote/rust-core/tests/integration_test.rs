// 测试基线 —— 建立 Rust/Go/Flutter 三层测试体系，确保架构变更不引入回归
// 集成测试：覆盖 FFI 生命周期、CRDT HLC 排序、持久化 Schema CRUD

#[cfg(test)]
// 测试约定：测试中使用 `.unwrap()` 是 Rust 惯用写法，由 `#[cfg(test)]` 门控，
// 不会编译进生产二进制。生产代码使用 `?` 运算符传播错误。
mod integration_tests {
    use std::ffi::CStr;
    use serde_json::json;

    // ── FFI 生命周期测试 ──────────────────────────────────────────────────

    #[test]
    fn test_ffi_init_success() {
        let result = devnote_ffi::devnote_init();
        assert!(!result.is_null(), "init returned null");
        let resp = unsafe { &*result };
        assert_eq!(
            resp.code,
            devnote_ffi::FFIErrorCode::Success as i32,
            "init failed: {}",
            unsafe { CStr::from_ptr(resp.message).to_str().unwrap_or("") }
        );
        devnote_ffi::devnote_destroy(result);
    }

    #[test]
    fn test_ffi_create_note() {
        devnote_ffi::devnote_destroy(devnote_ffi::devnote_init());

        // 创建文件夹
        let folder_req = std::ffi::CString::new(
            r#"{"event":"FolderEvent.CreateFolder","payload":"{\"name\":\"TestFolder\"}"}"#,
        ).unwrap();
        let result = dispatch_and_parse(folder_req.as_ptr());
        assert_eq!(result.code, 0, "create folder failed: {}: {}", result.code, result.message);
        let folder_data = get_data(&result);
        let folder_id = folder_data["id"].as_str().expect("missing folder id");

        // 创建笔记
        let payload = json!({
            "event": "NoteEvent.CreateNote",
            "payload": json!({
                "title": "测试笔记",
                "content": "Hello DevNote",
                "folder_id": folder_id
            }).to_string()
        }).to_string();
        let req = std::ffi::CString::new(payload).unwrap();
        let result = dispatch_and_parse(req.as_ptr());

        assert_eq!(result.code, 0, "create note failed: {}: {}", result.code, result.message);
        let data = get_data(&result);
        assert!(!data["id"].as_str().unwrap_or("").is_empty());
        assert_eq!(data["title"], "测试笔记");
    }

    #[test]
    fn test_ffi_list_notes() {
        devnote_ffi::devnote_destroy(devnote_ffi::devnote_init());

        // 创建文件夹
        let folder_req = std::ffi::CString::new(
            r#"{"event":"FolderEvent.CreateFolder","payload":"{\"name\":\"ListTestFolder\"}"}"#,
        ).unwrap();
        let result = dispatch_and_parse(folder_req.as_ptr());
        let folder_id = get_data(&result)["id"].as_str().unwrap();

        // 创建两条笔记
        for i in 1..=2 {
            let payload = json!({
                "event": "NoteEvent.CreateNote",
                "payload": json!({
                    "title": format!("Note{}", i),
                    "content": format!("Content{}", i),
                    "folder_id": folder_id
                }).to_string()
            }).to_string();
            let req = std::ffi::CString::new(payload).unwrap();
            let result = dispatch_and_parse(req.as_ptr());
            assert_eq!(result.code, 0, "create note {} failed: {}: {}", i, result.code, result.message);
        }

        // 列出笔记
        let list_payload = json!({
            "event": "NoteEvent.ListNotes",
            "payload": json!({"folder_id": folder_id}).to_string()
        }).to_string();
        let req = std::ffi::CString::new(list_payload).unwrap();
        let result = dispatch_and_parse(req.as_ptr());

        assert_eq!(result.code, 0, "list notes failed: {}: {}", result.code, result.message);
        let notes = get_data(&result).as_array().expect("data should be array");
        assert_eq!(notes.len(), 2, "expected 2 notes, got {:?}", notes);
    }

    #[test]
    fn test_ffi_update_note() {
        devnote_ffi::devnote_destroy(devnote_ffi::devnote_init());

        // 创建文件夹
        let folder_req = std::ffi::CString::new(
            r#"{"event":"FolderEvent.CreateFolder","payload":"{\"name\":\"UpdateTestFolder\"}"}"#,
        ).unwrap();
        let result = dispatch_and_parse(folder_req.as_ptr());
        let folder_id = get_data(&result)["id"].as_str().unwrap();

        // 创建笔记
        let create_payload = json!({
            "event": "NoteEvent.CreateNote",
            "payload": json!({
                "title": "旧标题",
                "content": "旧内容",
                "folder_id": folder_id
            }).to_string()
        }).to_string();
        let req = std::ffi::CString::new(create_payload).unwrap();
        let result = dispatch_and_parse(req.as_ptr());
        let note_id = get_data(&result)["id"].as_str().unwrap();

        // 更新笔记
        let update_payload = json!({
            "event": "NoteEvent.UpdateNote",
            "payload": json!({
                "id": note_id,
                "title": "新标题",
                "content": "新内容"
            }).to_string()
        }).to_string();
        let req = std::ffi::CString::new(update_payload).unwrap();
        let result = dispatch_and_parse(req.as_ptr());

        assert_eq!(result.code, 0, "update note failed: {}: {}", result.code, result.message);
        let data = get_data(&result);
        assert_eq!(data["title"], "新标题");
        // Note 模型没有 content 字段，内容存储在 blocks 中
        assert!(data["blocks"].is_array(), "blocks should be an array");
    }

    #[test]
    fn test_ffi_delete_note() {
        devnote_ffi::devnote_destroy(devnote_ffi::devnote_init());

        // 创建文件夹
        let folder_req = std::ffi::CString::new(
            r#"{"event":"FolderEvent.CreateFolder","payload":"{\"name\":\"DeleteTestFolder\"}"}"#,
        ).unwrap();
        let result = dispatch_and_parse(folder_req.as_ptr());
        let folder_id = get_data(&result)["id"].as_str().unwrap();

        // 创建笔记
        let create_payload = json!({
            "event": "NoteEvent.CreateNote",
            "payload": json!({
                "title": "待删除",
                "content": "bye",
                "folder_id": folder_id
            }).to_string()
        }).to_string();
        let req = std::ffi::CString::new(create_payload).unwrap();
        let result = dispatch_and_parse(req.as_ptr());
        let note_id = get_data(&result)["id"].as_str().unwrap();

        // 删除笔记
        let delete_payload = json!({
            "event": "NoteEvent.DeleteNote",
            "payload": json!({"id": note_id}).to_string()
        }).to_string();
        let req = std::ffi::CString::new(delete_payload).unwrap();
        let result = dispatch_and_parse(req.as_ptr());
        assert_eq!(result.code, 0, "delete note failed: {}: {}", result.code, result.message);
        assert_eq!(get_data(&result).as_bool(), Some(true));

        // 验证已删除
        let get_payload = json!({
            "event": "NoteEvent.GetNote",
            "payload": json!({"id": note_id}).to_string()
        }).to_string();
        let req = std::ffi::CString::new(get_payload).unwrap();
        let result = dispatch_and_parse(req.as_ptr());
        assert_eq!(
            result.code,
            devnote_ffi::FFIErrorCode::NotFound as i64,
            "deleted note should not be found: code={}, msg={}",
            result.code, result.message
        );
    }

    #[test]
    fn test_ffi_full_lifecycle() {
        devnote_ffi::devnote_destroy(devnote_ffi::devnote_init());

        // 1. Create folder
        let folder_req = std::ffi::CString::new(
            r#"{"event":"FolderEvent.CreateFolder","payload":"{\"name\":\"FullLifecycle\"}"}"#,
        ).unwrap();
        let result = dispatch_and_parse(folder_req.as_ptr());
        let folder_id = get_data(&result)["id"].as_str().unwrap();

        // 2. Create note
        let create_payload = json!({
            "event": "NoteEvent.CreateNote",
            "payload": json!({
                "title": "Lifecycle",
                "content": "Test",
                "folder_id": folder_id
            }).to_string()
        }).to_string();
        let req = std::ffi::CString::new(create_payload).unwrap();
        let result = dispatch_and_parse(req.as_ptr());
        assert_eq!(result.code, 0);
        let note_id = get_data(&result)["id"].as_str().unwrap().to_string();

        // 3. Get note
        let get_payload = json!({
            "event": "NoteEvent.GetNote",
            "payload": json!({"id": note_id}).to_string()
        }).to_string();
        let req = std::ffi::CString::new(get_payload).unwrap();
        let result = dispatch_and_parse(req.as_ptr());
        assert_eq!(result.code, 0);
        assert_eq!(get_data(&result)["title"], "Lifecycle");

        // 4. Update note
        let update_payload = json!({
            "event": "NoteEvent.UpdateNote",
            "payload": json!({
                "id": note_id,
                "title": "Updated",
                "content": "Updated content"
            }).to_string()
        }).to_string();
        let req = std::ffi::CString::new(update_payload).unwrap();
        let result = dispatch_and_parse(req.as_ptr());
        assert_eq!(result.code, 0);
        assert_eq!(get_data(&result)["title"], "Updated");

        // 5. List notes
        let list_payload = json!({
            "event": "NoteEvent.ListNotes",
            "payload": json!({"folder_id": folder_id}).to_string()
        }).to_string();
        let req = std::ffi::CString::new(list_payload).unwrap();
        let result = dispatch_and_parse(req.as_ptr());
        assert_eq!(result.code, 0);
        assert_eq!(get_data(&result).as_array().unwrap().len(), 1);

        // 6. Delete note
        let delete_payload = json!({
            "event": "NoteEvent.DeleteNote",
            "payload": json!({"id": note_id}).to_string()
        }).to_string();
        let req = std::ffi::CString::new(delete_payload).unwrap();
        let result = dispatch_and_parse(req.as_ptr());
        assert_eq!(result.code, 0);
        assert_eq!(get_data(&result).as_bool(), Some(true));
    }

    #[test]
    fn test_ffi_unknown_event() {
        devnote_ffi::devnote_destroy(devnote_ffi::devnote_init());

        let req = std::ffi::CString::new(r#"{"event":"UnknownEvent.Foo","payload":"{}"}"#).unwrap();
        let result = dispatch_and_parse(req.as_ptr());
        assert_eq!(
            result.code,
            devnote_ffi::FFIErrorCode::NotFound as i64,
            "unknown event should return NotFound"
        );
    }

    #[test]
    fn test_ffi_null_request() {
        devnote_ffi::devnote_destroy(devnote_ffi::devnote_init());

        let ptr = devnote_ffi::devnote_dispatch(std::ptr::null());
        let result = parse_response(ptr);
        assert_eq!(
            result.code,
            devnote_ffi::FFIErrorCode::InvalidArgument as i64,
            "null request should return InvalidArgument"
        );
    }

    // ── 辅助函数 ──────────────────────────────────────────────────────────

    /// 调用 devnote_dispatch 并解析返回的 JSON（含内层 data 解析），自动释放字符串
    fn dispatch_and_parse(request: *const std::os::raw::c_char) -> DispatchResult {
        let ptr = devnote_ffi::devnote_dispatch(request);
        parse_response(ptr)
    }

    /// 解析后的调度响应
    struct DispatchResult {
        code: i64,
        message: String,
        /// 内层 data 已从 JSON 字符串解析为 Value（None 表示无数据/null）
        data: Option<serde_json::Value>,
    }

    fn parse_response(ptr: *mut std::os::raw::c_char) -> DispatchResult {
        assert!(!ptr.is_null(), "dispatch returned null pointer");
        let json_str = unsafe { CStr::from_ptr(ptr) }
            .to_str()
            .expect("invalid UTF-8 in dispatch response");
        let outer: serde_json::Value =
            serde_json::from_str(json_str).expect("failed to parse dispatch JSON");
        devnote_ffi::devnote_free_string(ptr);

        let code = outer["code"].as_i64().unwrap_or(-1);
        let message = outer["message"].as_str().unwrap_or("").to_string();

        // DispatchResponse 的 data 字段是 Option<String>，
        // 内层数据是 JSON 字符串，需要二次解析
        let data = if let Some(inner_str) = outer["data"].as_str() {
            match serde_json::from_str::<serde_json::Value>(inner_str) {
                Ok(v) => Some(v),
                Err(_) => {
                    // 如果内层不是有效 JSON（例如 "true"），保留原始字符串
                    Some(serde_json::Value::String(inner_str.to_string()))
                }
            }
        } else {
            None
        };

        DispatchResult { code, message, data }
    }

    /// 从 DispatchResult 中获取 data 字段，若不存在则 panic
    fn get_data(result: &DispatchResult) -> &serde_json::Value {
        result.data.as_ref().unwrap_or_else(|| {
            panic!(
                "expected data but got code={}, message={}",
                result.code, result.message
            )
        })
    }

    // ── CRDT HLC 排序测试 ──────────────────────────────────────────────────

    #[test]
    fn test_crdt_hlc_ordering() {
        use devnote_crdt::HLC;

        let mut hlc1 = HLC::new("node-a".into());
        let mut hlc2 = HLC::new("node-b".into());

        // hlc1 先发生
        hlc1.increment();
        // hlc2 接收 hlc1，应发生在 hlc1 之后
        hlc2.receive(&hlc1);

        assert!(
            hlc2 > hlc1,
            "hlc2 (node-b 接收 node-a) 应排在 hlc1 之后"
        );
    }

    #[test]
    fn test_crdt_hlc_causality() {
        use devnote_crdt::HLC;

        let mut hlc_a = HLC::new("node-a".into());
        hlc_a.increment();
        let mut hlc_b = HLC::new("node-b".into());
        hlc_b.receive(&hlc_a); // hlc_b 发生在 hlc_a 之后

        assert!(hlc_b > hlc_a, "hlc_b 应在因果关系上大于 hlc_a");
    }

    #[test]
    fn test_crdt_vector_clock_merge() {
        use devnote_crdt::VectorClock;

        let mut vc1 = VectorClock::new();
        vc1.increment("device-a");
        let mut vc2 = VectorClock::new();
        vc2.increment("device-b");
        vc1.merge(&vc2);

        assert!(vc1.get("device-a").is_some(), "vc1 should have device-a");
        assert!(vc1.get("device-b").is_some(), "vc1 should have device-b after merge");
    }

    #[test]
    fn test_crdt_document_operations() {
        use devnote_crdt::CRDTDocument;

        let mut doc = CRDTDocument::new("doc-1".to_string(), "device-a".to_string());

        // Insert
        doc.insert_block("block-1".to_string(), 0, "Hello".to_string());
        assert_eq!(doc.active_blocks().len(), 1);

        // Replace
        doc.replace_block("block-1".to_string(), "Hello".to_string(), "World".to_string());
        let blocks = doc.active_blocks();
        assert_eq!(blocks[0].content, "World");

        // Delete (tombstone)
        doc.delete_block("block-1".to_string());
        assert_eq!(doc.active_blocks().len(), 0);
        assert!(doc.blocks.iter().any(|b| b.id == "block-1" && b.tombstone));
    }

    #[test]
    fn test_crdt_merge_documents() {
        use devnote_crdt::CRDTDocument;

        let mut doc1 = CRDTDocument::new("doc-merge".to_string(), "device-a".to_string());
        doc1.insert_block("block-a".to_string(), 0, "Hello from A".to_string());

        let mut doc2 = CRDTDocument::new("doc-merge".to_string(), "device-b".to_string());
        let op = doc2.insert_block("block-b".to_string(), 0, "Hello from B".to_string());

        let result = doc1.merge(vec![op]);
        assert!(result.is_ok(), "merge should succeed");
        assert_eq!(doc1.active_blocks().len(), 2);
    }

    // ── 持久化 Schema 和 CRUD 测试 ────────────────────────────────────────

    #[test]
    fn test_persistence_schema_creation() {
        use devnote_persistence::SqliteNoteRepository;

        let repo = SqliteNoteRepository::in_memory()
            .expect("failed to create in-memory repo");

        // 创建文件夹
        let folder = repo
            .create_folder("TestFolder", None::<&uuid::Uuid>)
            .expect("create folder failed");
        assert!(!folder.id.is_nil());
        assert_eq!(folder.name, "TestFolder");

        // 创建笔记
        let note = repo
            .create_note("TestNote", "Hello World", &folder.id)
            .expect("create note failed");
        assert!(!note.id.is_nil());
        assert_eq!(note.title, "TestNote");
        assert_eq!(note.folder_id, folder.id);
    }

    #[test]
    fn test_persistence_crud() {
        use devnote_persistence::SqliteNoteRepository;

        let repo = SqliteNoteRepository::in_memory().expect("failed to create repo");

        // Create
        let folder = repo
            .create_folder("CRUDTest", None::<&uuid::Uuid>)
            .expect("create folder");
        let note = repo
            .create_note("CRUD Note", "Content", &folder.id)
            .expect("create note");

        // Read
        let fetched = repo
            .get_note(&note.id)
            .expect("get note")
            .expect("note should exist");
        assert_eq!(fetched.title, "CRUD Note");

        // Update
        let updated = repo
            .update_note(&note.id, "Updated CRUD", "New Content")
            .expect("update note");
        assert_eq!(updated.title, "Updated CRUD");
        assert!(updated.updated_at >= fetched.updated_at, "updated_at should advance");

        // Delete
        repo.delete_note(&note.id).expect("delete note");
        let after_delete = repo.get_note(&note.id).expect("get note");
        assert!(after_delete.is_none(), "note should be deleted");

        // List
        let notes = repo
            .list_notes(&folder.id)
            .expect("list notes");
        assert!(notes.is_empty(), "folder should be empty after delete");
    }

    #[test]
    fn test_persistence_feature_flags() {
        use devnote_persistence::{FeatureFlag, SqliteNoteRepository};

        let repo = SqliteNoteRepository::in_memory().expect("failed to create repo");

        let flag = FeatureFlag {
            key: "dark_mode".to_string(),
            enabled: true,
            description: "Enable dark mode".to_string(),
            updated_at: chrono::Utc::now().timestamp(),
        };

        repo.set_feature_flag(flag).expect("set feature flag");

        let fetched = repo
            .get_feature_flag("dark_mode")
            .expect("get feature flag")
            .expect("feature flag should exist");
        assert!(fetched.enabled);
        assert_eq!(fetched.description, "Enable dark mode");

        let all_flags = repo.list_feature_flags().expect("list flags");
        assert_eq!(all_flags.len(), 1);

        repo.delete_feature_flag("dark_mode").expect("delete flag");
        let after_delete = repo.get_feature_flag("dark_mode").expect("get flag");
        assert!(after_delete.is_none());
    }

    #[test]
    fn test_persistence_tag_operations() {
        use devnote_persistence::SqliteNoteRepository;

        let repo = SqliteNoteRepository::in_memory().expect("failed to create repo");

        let tag = repo.create_tag("rust").expect("create tag");
        assert_eq!(tag.name, "rust");

        let tag2 = repo.create_tag("golang").expect("create tag");

        let folder = repo
            .create_folder("TagTest", None::<&uuid::Uuid>)
            .expect("create folder");
        let note = repo
            .create_note("Tagged Note", "Content", &folder.id)
            .expect("create note");

        repo.add_tag_to_note(&note.id, &tag.id)
            .expect("add tag to note");
        repo.add_tag_to_note(&note.id, &tag2.id)
            .expect("add second tag");

        let fetched = repo
            .get_note(&note.id)
            .expect("get note")
            .expect("note should exist");
        assert_eq!(fetched.tags.len(), 2);
        assert!(fetched.tags.contains(&tag.id));
        assert!(fetched.tags.contains(&tag2.id));
    }
}