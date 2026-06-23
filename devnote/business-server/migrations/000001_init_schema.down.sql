-- 回滚 business-server 初始 schema

DROP INDEX IF EXISTS idx_business_rule_user_id;
DROP INDEX IF EXISTS idx_validation_rule_user_id;
DROP INDEX IF EXISTS idx_knowledge_relation_user_id;
DROP INDEX IF EXISTS idx_knowledge_target;
DROP INDEX IF EXISTS idx_knowledge_source;
DROP INDEX IF EXISTS idx_tag_relation_note;
DROP INDEX IF EXISTS idx_tag_relation_tag;
DROP INDEX IF EXISTS idx_tag_meta_user_id;
DROP INDEX IF EXISTS idx_tag_meta_parent;
DROP INDEX IF EXISTS idx_folder_meta_user_id;
DROP INDEX IF EXISTS idx_folder_meta_parent;
DROP INDEX IF EXISTS idx_note_meta_user_id;
DROP INDEX IF EXISTS idx_note_meta_author;
DROP INDEX IF EXISTS idx_note_meta_title;

DROP TABLE IF EXISTS business_rule;
DROP TABLE IF EXISTS validation_rule;
DROP TABLE IF EXISTS knowledge_relation;
DROP TABLE IF EXISTS tag_relation;
DROP TABLE IF EXISTS tag_meta;
DROP TABLE IF EXISTS folder_meta;
DROP TABLE IF EXISTS note_meta;
