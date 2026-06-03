use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, PartialOrd)]
pub enum Permission {
    Read = 0,
    Write = 1,
    Admin = 2,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResourceACL {
    pub id: String,
    pub resource_id: String,
    pub resource_type: String, // "note", "folder", "workspace"
    pub user_id: String,
    pub permission: Permission,
    pub granted_by: String,
    pub granted_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Workspace {
    pub id: String,
    pub name: String,
    pub owner_id: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceMember {
    pub id: String,
    pub workspace_id: String,
    pub user_id: String,
    pub role: Permission,
    pub joined_at: DateTime<Utc>,
}

pub fn check_permission(
    user_id: &str,
    resource_id: &str,
    required: Permission,
    acls: &[ResourceACL],
) -> bool {
    acls.iter().any(|acl| {
        acl.user_id == user_id
            && acl.resource_id == resource_id
            && acl.permission >= required
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_permission_ordering() {
        assert!(Permission::Admin > Permission::Write);
        assert!(Permission::Write > Permission::Read);
        assert!(Permission::Read < Permission::Admin);
    }

    #[test]
    fn test_check_permission_granted() {
        let acls = vec![ResourceACL {
            id: "1".to_string(),
            resource_id: "note-1".to_string(),
            resource_type: "note".to_string(),
            user_id: "user-1".to_string(),
            permission: Permission::Write,
            granted_by: "admin".to_string(),
            granted_at: Utc::now(),
        }];

        assert!(check_permission("user-1", "note-1", Permission::Read, &acls));
        assert!(check_permission("user-1", "note-1", Permission::Write, &acls));
        assert!(!check_permission("user-1", "note-1", Permission::Admin, &acls));
    }

    #[test]
    fn test_check_permission_denied() {
        let acls = vec![ResourceACL {
            id: "1".to_string(),
            resource_id: "note-1".to_string(),
            resource_type: "note".to_string(),
            user_id: "user-1".to_string(),
            permission: Permission::Read,
            granted_by: "admin".to_string(),
            granted_at: Utc::now(),
        }];

        assert!(!check_permission("user-2", "note-1", Permission::Read, &acls));
        assert!(!check_permission("user-1", "note-2", Permission::Read, &acls));
    }
}
