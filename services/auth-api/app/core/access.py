from sqlalchemy.orm import Session

from app.models.admin import Permission, Role
from app.models.user import User


ROLE_PERMISSIONS = {
    "user": set(),
    "moderator": {"moderation.review"},
    "support": {"users.read", "users.sessions.revoke"},
    "finance_admin": {"users.read", "billing.read", "billing.adjust"},
    "admin": {
        "users.read", "users.block", "users.roles.manage",
        "users.sessions.revoke", "billing.read", "billing.adjust",
        "moderation.review", "fraud.review", "audit.read",
    },
    "superadmin": {
        "users.read", "users.block", "users.roles.manage",
        "users.sessions.revoke", "billing.read", "billing.adjust",
        "moderation.review", "fraud.review", "audit.read", "admins.invite",
    },
}
ADMIN_ROLES = {"moderator", "support", "finance_admin", "admin", "superadmin"}


def ensure_access_catalog(db: Session) -> dict[str, Role]:
    permissions = {item.name: item for item in db.query(Permission).all()}
    for name in sorted({permission for values in ROLE_PERMISSIONS.values() for permission in values}):
        if name not in permissions:
            permissions[name] = Permission(name=name, description=name)
            db.add(permissions[name])
    db.flush()
    roles = {item.name: item for item in db.query(Role).all()}
    for name, granted in ROLE_PERMISSIONS.items():
        role = roles.get(name)
        if role is None:
            role = Role(name=name, description=name.replace("_", " ").title())
            db.add(role)
            roles[name] = role
        role.permissions = [permissions[value] for value in sorted(granted)]
    db.flush()
    return roles


def assign_roles(db: Session, user: User, role_names: list[str]) -> None:
    catalog = ensure_access_catalog(db)
    normalized = sorted(set(role_names))
    if not normalized or any(name not in catalog for name in normalized):
        raise ValueError("Unknown role")
    user.roles = [catalog[name] for name in normalized]
    user.role = "superadmin" if "superadmin" in normalized else (
        "admin" if any(name in ADMIN_ROLES for name in normalized) else normalized[0]
    )


def user_roles(user: User) -> list[str]:
    values = sorted({role.name for role in user.roles})
    return values or [user.role or "user"]


def user_permissions(user: User) -> list[str]:
    values = {permission.name for role in user.roles for permission in role.permissions}
    if not values:
        for role in user_roles(user):
            values.update(ROLE_PERMISSIONS.get(role, set()))
    return sorted(values)
