use crate::models::{Note, Folder, Tag, Attachment};
use anyhow::Result;
use uuid::Uuid;

pub trait NoteRepository: Send + Sync {
    fn create_note(&mut self, note: Note) -> Result<Note>;
    fn get_note(&self, id: &Uuid) -> Result<Option<Note>>;
    fn update_note(&mut self, note: Note) -> Result<Note>;
    fn delete_note(&mut self, id: &Uuid) -> Result<()>;
    fn list_notes(&self, folder_id: Option<&Uuid>) -> Result<Vec<Note>>;

    fn create_folder(&mut self, folder: Folder) -> Result<Folder>;
    fn get_folder(&self, id: &Uuid) -> Result<Option<Folder>>;
    fn update_folder(&mut self, folder: Folder) -> Result<Folder>;
    fn delete_folder(&mut self, id: &Uuid) -> Result<()>;
    fn list_folders(&self, parent_id: Option<&Uuid>) -> Result<Vec<Folder>>;

    fn create_tag(&mut self, tag: Tag) -> Result<Tag>;
    fn delete_tag(&mut self, id: &Uuid) -> Result<()>;
    fn list_tags(&self) -> Result<Vec<Tag>>;
    fn add_tag_to_note(&mut self, note_id: &Uuid, tag_id: &Uuid) -> Result<()>;
    fn remove_tag_from_note(&mut self, note_id: &Uuid, tag_id: &Uuid) -> Result<()>;

    fn create_attachment(&mut self, attachment: Attachment) -> Result<Attachment>;
    fn delete_attachment(&mut self, id: &Uuid) -> Result<()>;
    fn list_attachments(&self, note_id: &Uuid) -> Result<Vec<Attachment>>;
}
