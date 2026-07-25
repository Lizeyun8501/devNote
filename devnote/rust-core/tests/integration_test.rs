// 测试基线 —— 建立 Rust/Go/Flutter 三层测试体系，确保架构变更不引入回归
// 集成测试：覆盖 FRB API 生命周期、CRDT HLC 排序、持久化 Schema CRUD
//
// FRB v2 迁移: 原 C ABI dispatch 测试（devnote_init/devnote_dispatch/devnote_free_string）
// 已替换为直接调用 frb_api.rs 中的 pub fn 函数，与 Dart 端 FRB 绑定调用方式一致。

#[cfg(test)]
// 测试约定：测试中使用 `.unwrap()` 是 Rust 惯用写法，由 `#[cfg(test)]` 门控，
// 不会编译进生产二进制。生产代码使用 `?` 运算符传播错误。
mod integration_tests {
    use std::sync::{Mutex, MutexGuard};
    use std::sync::LazyLock;

    // ── FRB API 生命周期测试 ──────────────────────────────────────────────
    // 直接调用 frb_api.rs 中的 pub fn，替代原 C ABI dispatch 测试

    /// 全局测试互斥锁 —— 串行化所有涉及全局引擎状态的测试
    ///
    /// frb_api.rs 中的 11 个全局引擎（NOTE_REPO、BLOCK_EDITOR 等）是 FRB 架构必需的
    /// 全局单例，Dart 端通过这些单例访问 Rust 功能。测试中每个 init_test_engines()
    /// 调用会覆盖全局状态，若测试并行执行会导致竞态条件（如 test_folder_crud 的
    /// "Folder not found" 失败：一个测试的 init_engines() 在另一个测试的
    /// get_folder/update_folder 之间替换了 NOTE_REPO）。此互斥锁确保涉及全局
    /// 状态的测试串行执行，而 CRDT/持久化测试（使用本地 repo 实例）仍可并行。
    static GLOBAL_TEST_GUARD: LazyLock<Mutex<()>> = LazyLock::new(|| Mutex::new(()));

    /// 初始化引擎并获取全局测试锁 —— 使用临时文件数据库，测试结束后自动清理
    ///
    /// 返回 (TempPath, MutexGuard)，调用者需保留两者直到测试结束：
    /// - TempPath 保证临时数据库文件在测试结束后删除
    /// - MutexGuard 保证全局引擎状态在测试期间不被其他测试覆盖
    fn init_test_engines() -> (tempfile::TempPath, MutexGuard<'static, ()>) {
        let guard = GLOBAL_TEST_GUARD.lock().expect("test guard poisoned");
        let tmp = tempfile::NamedTempFile::new().expect("failed to create temp file");
        let path = tmp.path().to_str().unwrap().to_string();
        devnote_ffi::frb_api::init_engines(path).expect("init_engines failed");
        (tmp.into_temp_path(), guard)
    }

    #[test]
    fn test_init_engines_success() {
        let (_tmp, _guard) = init_test_engines();
        // init_engines 成功后，各引擎应已初始化
        let health = devnote_ffi::frb_api::health_check();
        assert_eq!(health.status, "ok");
        assert!(
            health.engines.get("persistence").copied().unwrap_or(false),
            "persistence engine should be initialized"
        );
    }

    #[test]
    fn test_get_version() {
        let version = devnote_ffi::frb_api::get_version();
        assert_eq!(version.api_version, 1);
        assert!(!version.rust_version.is_empty());
        assert!(!version.features.is_empty());
    }

    #[test]
    fn test_create_note() {
        let (_tmp, _guard) = init_test_engines();

        // 创建文件夹
        let folder = devnote_ffi::frb_api::create_folder("TestFolder".to_string(), None)
            .expect("create folder failed");
        assert!(!folder.id.is_empty());
        assert_eq!(folder.name, "TestFolder");

        // 创建笔记
        let note = devnote_ffi::frb_api::create_note(
            "测试笔记".to_string(),
            "Hello DevNote".to_string(),
            folder.id.clone(),
        ).expect("create note failed");
        assert!(!note.id.is_empty());
        assert_eq!(note.title, "测试笔记");
    }

    #[test]
    fn test_list_notes() {
        let (_tmp, _guard) = init_test_engines();

        // 创建文件夹
        let folder = devnote_ffi::frb_api::create_folder("ListTestFolder".to_string(), None)
            .expect("create folder failed");

        // 创建两条笔记
        for i in 1..=2 {
            devnote_ffi::frb_api::create_note(
                format!("Note{}", i),
                format!("Content{}", i),
                folder.id.clone(),
            ).expect(&format!("create note {} failed", i));
        }

        // 列出笔记
        let notes = devnote_ffi::frb_api::list_notes(folder.id)
            .expect("list notes failed");
        assert_eq!(notes.len(), 2, "expected 2 notes, got {:?}", notes);
    }

    #[test]
    fn test_update_note() {
        let (_tmp, _guard) = init_test_engines();

        // 创建文件夹
        let folder = devnote_ffi::frb_api::create_folder("UpdateTestFolder".to_string(), None)
            .expect("create folder failed");

        // 创建笔记
        let note = devnote_ffi::frb_api::create_note(
            "旧标题".to_string(),
            "旧内容".to_string(),
            folder.id.clone(),
        ).expect("create note failed");

        // 更新笔记
        let updated = devnote_ffi::frb_api::update_note(
            note.id.clone(),
            "新标题".to_string(),
            "新内容".to_string(),
        ).expect("update note failed");
        assert_eq!(updated.title, "新标题");
    }

    #[test]
    fn test_delete_note() {
        let (_tmp, _guard) = init_test_engines();

        // 创建文件夹
        let folder = devnote_ffi::frb_api::create_folder("DeleteTestFolder".to_string(), None)
            .expect("create folder failed");

        // 创建笔记
        let note = devnote_ffi::frb_api::create_note(
            "待删除".to_string(),
            "bye".to_string(),
            folder.id.clone(),
        ).expect("create note failed");

        // 删除笔记
        devnote_ffi::frb_api::delete_note(note.id.clone())
            .expect("delete note failed");

        // 验证已删除
        let result = devnote_ffi::frb_api::get_note(note.id)
            .expect("get_note should not error");
        assert!(result.is_none(), "deleted note should not be found");
    }

    #[test]
    fn test_full_lifecycle() {
        let (_tmp, _guard) = init_test_engines();

        // 1. Create folder
        let folder = devnote_ffi::frb_api::create_folder("FullLifecycle".to_string(), None)
            .expect("create folder failed");

        // 2. Create note
        let note = devnote_ffi::frb_api::create_note(
            "Lifecycle".to_string(),
            "Test".to_string(),
            folder.id.clone(),
        ).expect("create note failed");

        // 3. Get note
        let fetched = devnote_ffi::frb_api::get_note(note.id.clone())
            .expect("get_note failed")
            .expect("note should exist");
        assert_eq!(fetched.title, "Lifecycle");

        // 4. Update note
        let updated = devnote_ffi::frb_api::update_note(
            note.id.clone(),
            "Updated".to_string(),
            "Updated content".to_string(),
        ).expect("update note failed");
        assert_eq!(updated.title, "Updated");

        // 5. List notes
        let notes = devnote_ffi::frb_api::list_notes(folder.id.clone())
            .expect("list notes failed");
        assert_eq!(notes.len(), 1);

        // 6. Delete note
        devnote_ffi::frb_api::delete_note(note.id.clone())
            .expect("delete note failed");
        let notes = devnote_ffi::frb_api::list_notes(folder.id)
            .expect("list notes after delete failed");
        assert!(notes.is_empty(), "folder should be empty after delete");
    }

    #[test]
    fn test_folder_crud() {
        let (_tmp, _guard) = init_test_engines();

        // Create
        let folder = devnote_ffi::frb_api::create_folder("FolderCRUD".to_string(), None)
            .expect("create folder failed");

        // Read
        let fetched = devnote_ffi::frb_api::get_folder(folder.id.clone())
            .expect("get_folder failed")
            .expect("folder should exist");
        assert_eq!(fetched.name, "FolderCRUD");

        // Update
        let updated = devnote_ffi::frb_api::update_folder(
            folder.id.clone(),
            "UpdatedFolder".to_string(),
            None,
            None,
        ).expect("update folder failed");
        assert_eq!(updated.name, "UpdatedFolder");

        // Delete
        devnote_ffi::frb_api::delete_folder(folder.id)
            .expect("delete folder failed");
    }

    #[test]
    fn test_tag_crud() {
        let (_tmp, _guard) = init_test_engines();

        // Create
        let tag = devnote_ffi::frb_api::create_tag("rust".to_string())
            .expect("create tag failed");
        assert_eq!(tag.name, "rust");

        // List
        let tags = devnote_ffi::frb_api::list_tags()
            .expect("list tags failed");
        assert_eq!(tags.len(), 1);

        // Delete
        devnote_ffi::frb_api::delete_tag(tag.id)
            .expect("delete tag failed");
        let tags = devnote_ffi::frb_api::list_tags()
            .expect("list tags after delete failed");
        assert!(tags.is_empty());
    }

    #[test]
    fn test_health_check() {
        let (_tmp, _guard) = init_test_engines();
        let result = devnote_ffi::frb_api::health_check();
        assert_eq!(result.status, "ok");
        // persistence 引擎应已初始化
        assert!(
            result.engines.get("persistence").copied().unwrap_or(false),
            "persistence engine should be healthy"
        );
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
        doc.insert_block("block-1".to_string(), 0, "Hello".to_string()).unwrap();
        assert_eq!(doc.active_blocks().len(), 1);

        // Replace
        doc.replace_block("block-1".to_string(), "Hello".to_string(), "World".to_string()).unwrap();
        let blocks = doc.active_blocks();
        assert_eq!(blocks[0].content, "World");

        // Delete (tombstone)
        doc.delete_block("block-1".to_string()).unwrap();
        assert_eq!(doc.active_blocks().len(), 0);
        assert!(doc.blocks.iter().any(|b| b.id == "block-1" && b.tombstone));
    }

    #[test]
    fn test_crdt_merge_documents() {
        use devnote_crdt::CRDTDocument;

        let mut doc1 = CRDTDocument::new("doc-merge".to_string(), "device-a".to_string());
        doc1.insert_block("block-a".to_string(), 0, "Hello from A".to_string()).unwrap();

        let mut doc2 = CRDTDocument::new("doc-merge".to_string(), "device-b".to_string());
        let op = doc2.insert_block("block-b".to_string(), 0, "Hello from B".to_string()).unwrap();

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
