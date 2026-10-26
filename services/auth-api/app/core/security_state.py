import hashlib
import json
import os
import socket
import threading
import time
from collections import defaultdict, deque
from datetime import timezone
from urllib.parse import unquote, urlparse


class SecurityStateUnavailable(RuntimeError):
    pass


class _RedisProtocolClient:
    """Small dependency-free Redis client for security-state and rate-limit commands."""

    def __init__(self, url: str):
        parsed = urlparse(url)
        if parsed.scheme not in {"redis", "rediss"}:
            raise ValueError("REDIS_URL must use redis:// or rediss://")
        self.host = parsed.hostname or "redis"
        self.port = parsed.port or 6379
        self.username = unquote(parsed.username) if parsed.username else None
        self.password = unquote(parsed.password) if parsed.password else None
        self.database = int((parsed.path or "/0").lstrip("/") or "0")
        self.use_tls = parsed.scheme == "rediss"
        self.timeout = float(os.getenv("REDIS_SECURITY_TIMEOUT_SECONDS", "1.5"))

    @staticmethod
    def _encode(parts: tuple[object, ...]) -> bytes:
        encoded = [f"*{len(parts)}\r\n".encode()]
        for part in parts:
            value = str(part).encode("utf-8")
            encoded.extend((f"${len(value)}\r\n".encode(), value, b"\r\n"))
        return b"".join(encoded)

    @staticmethod
    def _read(stream):
        marker = stream.read(1)
        if not marker:
            raise OSError("Redis closed the connection")
        line = stream.readline()
        if not line.endswith(b"\r\n"):
            raise OSError("Invalid Redis response")
        value = line[:-2]
        if marker == b"+":
            return value.decode("utf-8")
        if marker == b"-":
            raise OSError(f"Redis error: {value.decode('utf-8', errors='replace')}")
        if marker == b":":
            return int(value)
        if marker == b"$":
            length = int(value)
            if length == -1:
                return None
            payload = stream.read(length)
            if len(payload) != length or stream.read(2) != b"\r\n":
                raise OSError("Invalid Redis bulk response")
            return payload.decode("utf-8")
        raise OSError("Unsupported Redis response")

    def execute(self, *parts: object):
        raw_socket = socket.create_connection((self.host, self.port), self.timeout)
        stream = None
        try:
            raw_socket.settimeout(self.timeout)
            if self.use_tls:
                import ssl

                raw_socket = ssl.create_default_context().wrap_socket(
                    raw_socket, server_hostname=self.host
                )
            stream = raw_socket.makefile("rb")
            if self.password:
                auth = (
                    ("AUTH", self.username, self.password)
                    if self.username
                    else ("AUTH", self.password)
                )
                raw_socket.sendall(self._encode(auth))
                self._read(stream)
            if self.database:
                raw_socket.sendall(self._encode(("SELECT", self.database)))
                self._read(stream)
            raw_socket.sendall(self._encode(parts))
            return self._read(stream)
        finally:
            if stream is not None:
                stream.close()
            raw_socket.close()


class SecurityStateCache:
    def __init__(self):
        redis_url = os.getenv("REDIS_URL", "").strip()
        self.redis = _RedisProtocolClient(redis_url) if redis_url else None
        self._attempts: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    @staticmethod
    def user_key(user_id: int) -> str:
        return f"security:user:{user_id}"

    def set_user(self, user, *, strict: bool = False) -> bool:
        if self.redis is None:
            return True
        suspended_until = user.suspended_until
        if suspended_until is not None and suspended_until.tzinfo is None:
            suspended_until = suspended_until.replace(tzinfo=timezone.utc)
        payload = json.dumps(
            {
                "status": user.status,
                "token_version": int(user.token_version),
                "suspended_until": (
                    suspended_until.isoformat() if suspended_until is not None else None
                ),
            },
            separators=(",", ":"),
        )
        try:
            self.redis.execute("SET", self.user_key(int(user.id)), payload, "EX", 3600)
            return True
        except (OSError, ValueError) as exc:
            if strict:
                raise SecurityStateUnavailable("Security state cache is unavailable") from exc
            return False

    def set_session(
        self,
        session_id: str,
        *,
        active: bool,
        ttl_seconds: int = 2_592_000,
        strict: bool = False,
    ) -> bool:
        if self.redis is None:
            return True
        try:
            self.redis.execute(
                "SET",
                f"security:session:{session_id}",
                "active" if active else "revoked",
                "EX",
                max(60, ttl_seconds),
            )
            return True
        except (OSError, ValueError) as exc:
            if strict:
                raise SecurityStateUnavailable("Security session cache is unavailable") from exc
            return False

    def check_login_rate_limit(self, email: str, ip_address: str) -> None:
        identity = hashlib.sha256(
            f"{email.strip().lower()}|{ip_address}".encode("utf-8")
        ).hexdigest()
        if self.redis is not None:
            key = f"security:login:{identity}"
            try:
                count = int(self.redis.execute("INCR", key))
                if count == 1:
                    self.redis.execute("EXPIRE", key, 60)
            except (OSError, ValueError) as exc:
                raise SecurityStateUnavailable("Login rate limiter is unavailable") from exc
            if count > 10:
                raise PermissionError("Login rate limit exceeded")
            return

        now = time.monotonic()
        with self._lock:
            bucket = self._attempts[identity]
            while bucket and bucket[0] <= now - 60:
                bucket.popleft()
            if len(bucket) >= 10:
                raise PermissionError("Login rate limit exceeded")
            bucket.append(now)

    def clear_login_rate_limit(self, email: str, ip_address: str) -> None:
        identity = hashlib.sha256(
            f"{email.strip().lower()}|{ip_address}".encode("utf-8")
        ).hexdigest()
        if self.redis is not None:
            try:
                self.redis.execute("DEL", f"security:login:{identity}")
            except (OSError, ValueError):
                return
        else:
            with self._lock:
                self._attempts.pop(identity, None)


security_state_cache = SecurityStateCache()
