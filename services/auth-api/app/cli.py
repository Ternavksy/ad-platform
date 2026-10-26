import argparse
import getpass
import sys
import uuid

from app.core.access import assign_roles, user_roles
from app.core.security import hash_password, utcnow
from app.db.session import transaction
from app.models.admin import AdminAuditLog
from app.models.balance import Balance
from app.models.transaction import Transaction as _Transaction  # register User.transactions mapper
from app.models.user import User


def create_admin(email: str) -> int:
    normalized = email.strip().lower()
    password = getpass.getpass("Administrator password: ")
    confirmation = getpass.getpass("Repeat password: ")
    if password != confirmation:
        print("Passwords do not match", file=sys.stderr)
        return 2
    if len(password) < 12:
        print("Administrator password must contain at least 12 characters", file=sys.stderr)
        return 2
    with transaction() as db:
        if db.query(User).filter(User.email == normalized).first():
            print("User already exists", file=sys.stderr)
            return 1
        user = User(
            email=normalized,
            password_hash=hash_password(password),
            role="superadmin",
            email_verified_at=utcnow(),
        )
        db.add(user)
        db.flush()
        assign_roles(db, user, ["superadmin"])
        db.add(Balance(user_id=user.id, amount=0))
        db.add(
            AdminAuditLog(
                actor_user_id=user.id,
                actor_roles=user_roles(user),
                action="superadmin.bootstrapped",
                target_type="user",
                target_id=str(user.id),
                before_state=None,
                after_state={"id": user.id, "email": user.email, "roles": ["superadmin"]},
                reason="initial secure bootstrap",
                request_id=str(uuid.uuid4()),
                ip_hash="",
                user_agent_hash="",
                created_at=utcnow(),
            )
        )
    print(f"Created superadmin {normalized}. MFA setup is required on first login.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Ad Platform administration CLI")
    commands = parser.add_subparsers(dest="command", required=True)
    create = commands.add_parser("create-admin", help="Create the initial superadmin")
    create.add_argument("--email", required=True)
    args = parser.parse_args()
    if args.command == "create-admin":
        return create_admin(args.email)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
