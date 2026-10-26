"""add user administration, roles, sessions and audit

Revision ID: k1f2a3b4c5d6
Revises: j0e1f2a3b4c5
"""

from alembic import op
import sqlalchemy as sa


revision = "k1f2a3b4c5d6"
down_revision = "j0e1f2a3b4c5"
branch_labels = None
depends_on = None


ROLE_NAMES = ["user", "moderator", "support", "finance_admin", "admin", "superadmin"]
PERMISSION_NAMES = [
    "users.read",
    "users.block",
    "users.roles.manage",
    "users.sessions.revoke",
    "billing.read",
    "billing.adjust",
    "moderation.review",
    "fraud.review",
    "audit.read",
    "admins.invite",
]


def upgrade() -> None:
    op.add_column("users", sa.Column("status", sa.String(16), nullable=False, server_default="active"))
    op.add_column("users", sa.Column("email_verified_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("users", sa.Column("last_login_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("users", sa.Column("failed_login_attempts", sa.Integer(), nullable=False, server_default="0"))
    op.add_column("users", sa.Column("locked_until", sa.DateTime(timezone=True), nullable=True))
    op.add_column("users", sa.Column("suspended_until", sa.DateTime(timezone=True), nullable=True))
    op.add_column("users", sa.Column("blocked_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("users", sa.Column("blocked_by", sa.BigInteger(), nullable=True))
    op.add_column("users", sa.Column("block_reason", sa.String(500), nullable=False, server_default=""))
    op.add_column("users", sa.Column("token_version", sa.Integer(), nullable=False, server_default="1"))
    op.add_column("users", sa.Column("password_reset_required", sa.Boolean(), nullable=False, server_default=sa.false()))
    op.add_column("users", sa.Column("mfa_secret_encrypted", sa.Text(), nullable=True))
    op.add_column("users", sa.Column("mfa_confirmed_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("users", sa.Column("mfa_recovery_codes", sa.Text(), nullable=True))
    op.add_column("users", sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()))
    op.add_column("users", sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()))
    op.add_column("users", sa.Column("row_version", sa.Integer(), nullable=False, server_default="1"))
    op.create_index("ix_users_status", "users", ["status"])
    op.create_foreign_key("fk_users_blocked_by", "users", "users", ["blocked_by"], ["id"], ondelete="SET NULL")

    op.create_table(
        "roles",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("name", sa.String(32), nullable=False),
        sa.Column("description", sa.String(255), nullable=False, server_default=""),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("name"),
    )
    op.create_index("ix_roles_name", "roles", ["name"], unique=True)
    op.create_table(
        "permissions",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("name", sa.String(64), nullable=False),
        sa.Column("description", sa.String(255), nullable=False, server_default=""),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("name"),
    )
    op.create_index("ix_permissions_name", "permissions", ["name"], unique=True)
    op.create_table(
        "user_roles",
        sa.Column("user_id", sa.BigInteger(), nullable=False),
        sa.Column("role_id", sa.BigInteger(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.ForeignKeyConstraint(["role_id"], ["roles.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("user_id", "role_id"),
    )
    op.create_table(
        "role_permissions",
        sa.Column("role_id", sa.BigInteger(), nullable=False),
        sa.Column("permission_id", sa.BigInteger(), nullable=False),
        sa.ForeignKeyConstraint(["permission_id"], ["permissions.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["role_id"], ["roles.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("role_id", "permission_id"),
    )

    role_table = sa.table("roles", sa.column("id", sa.BigInteger()), sa.column("name", sa.String()), sa.column("description", sa.String()))
    permission_table = sa.table("permissions", sa.column("id", sa.BigInteger()), sa.column("name", sa.String()), sa.column("description", sa.String()))
    op.bulk_insert(role_table, [{"id": index + 1, "name": name, "description": name.replace("_", " ").title()} for index, name in enumerate(ROLE_NAMES)])
    op.bulk_insert(permission_table, [{"id": index + 1, "name": name, "description": name} for index, name in enumerate(PERMISSION_NAMES)])

    permission_ids = {name: index + 1 for index, name in enumerate(PERMISSION_NAMES)}
    role_ids = {name: index + 1 for index, name in enumerate(ROLE_NAMES)}
    grants = {
        "moderator": ["moderation.review"],
        "support": ["users.read", "users.sessions.revoke"],
        "finance_admin": ["users.read", "billing.read", "billing.adjust"],
        "admin": PERMISSION_NAMES[:-1],
        "superadmin": PERMISSION_NAMES,
    }
    role_permission_table = sa.table("role_permissions", sa.column("role_id", sa.BigInteger()), sa.column("permission_id", sa.BigInteger()))
    op.bulk_insert(
        role_permission_table,
        [
            {"role_id": role_ids[role], "permission_id": permission_ids[permission]}
            for role, permissions in grants.items()
            for permission in permissions
        ],
    )
    op.execute(
        "INSERT INTO user_roles (user_id, role_id, created_at) "
        "SELECT u.id, r.id, CURRENT_TIMESTAMP FROM users u "
        "JOIN roles r ON r.name = CASE WHEN u.role = 'admin' THEN 'admin' ELSE 'user' END"
    )

    op.create_table(
        "user_sessions",
        sa.Column("id", sa.String(36), nullable=False),
        sa.Column("user_id", sa.BigInteger(), nullable=False),
        sa.Column("refresh_token_hash", sa.String(64), nullable=False),
        sa.Column("access_jti", sa.String(36), nullable=False),
        sa.Column("user_agent_hash", sa.String(64), nullable=False, server_default=""),
        sa.Column("ip_hash", sa.String(64), nullable=False, server_default=""),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_used_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("replaced_by", sa.String(36), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("refresh_token_hash"),
    )
    op.create_index("ix_user_sessions_user_id", "user_sessions", ["user_id"])
    op.create_index("ix_user_sessions_refresh_token_hash", "user_sessions", ["refresh_token_hash"], unique=True)
    op.create_index("ix_user_sessions_expires_at", "user_sessions", ["expires_at"])

    op.create_table(
        "admin_invitations",
        sa.Column("id", sa.String(36), nullable=False),
        sa.Column("email", sa.String(255), nullable=False),
        sa.Column("role_name", sa.String(32), nullable=False),
        sa.Column("token_hash", sa.String(64), nullable=False),
        sa.Column("created_by", sa.BigInteger(), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("accepted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["created_by"], ["users.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("token_hash"),
    )
    op.create_index("ix_admin_invitations_email", "admin_invitations", ["email"])
    op.create_index("ix_admin_invitations_token_hash", "admin_invitations", ["token_hash"], unique=True)
    op.create_index("ix_admin_invitations_expires_at", "admin_invitations", ["expires_at"])

    op.create_table(
        "admin_audit_log",
        sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("actor_user_id", sa.BigInteger(), nullable=False),
        sa.Column("actor_roles", sa.JSON(), nullable=False),
        sa.Column("action", sa.String(64), nullable=False),
        sa.Column("target_type", sa.String(32), nullable=False),
        sa.Column("target_id", sa.String(64), nullable=False),
        sa.Column("before_state", sa.JSON(), nullable=True),
        sa.Column("after_state", sa.JSON(), nullable=True),
        sa.Column("reason", sa.String(500), nullable=False, server_default=""),
        sa.Column("request_id", sa.String(64), nullable=False),
        sa.Column("ip_hash", sa.String(64), nullable=False, server_default=""),
        sa.Column("user_agent_hash", sa.String(64), nullable=False, server_default=""),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.ForeignKeyConstraint(["actor_user_id"], ["users.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("request_id", "action", "target_type", "target_id", name="uq_admin_audit_request_action_target"),
    )
    op.create_index("ix_admin_audit_actor", "admin_audit_log", ["actor_user_id"])
    op.create_index("ix_admin_audit_action", "admin_audit_log", ["action"])
    op.create_index("ix_admin_audit_target", "admin_audit_log", ["target_id"])
    op.create_index("ix_admin_audit_request", "admin_audit_log", ["request_id"])
    op.create_index("ix_admin_audit_created", "admin_audit_log", ["created_at"])


def downgrade() -> None:
    op.drop_table("admin_audit_log")
    op.drop_table("admin_invitations")
    op.drop_table("user_sessions")
    op.drop_table("role_permissions")
    op.drop_table("user_roles")
    op.drop_index("ix_permissions_name", table_name="permissions")
    op.drop_table("permissions")
    op.drop_index("ix_roles_name", table_name="roles")
    op.drop_table("roles")
    op.drop_constraint("fk_users_blocked_by", "users", type_="foreignkey")
    op.drop_index("ix_users_status", table_name="users")
    for column in [
        "row_version", "updated_at", "created_at", "mfa_recovery_codes",
        "mfa_confirmed_at", "mfa_secret_encrypted", "password_reset_required",
        "token_version", "block_reason", "blocked_by", "blocked_at",
        "suspended_until", "locked_until", "failed_login_attempts",
        "last_login_at", "email_verified_at", "status",
    ]:
        op.drop_column("users", column)
