import json
import os
import urllib.error
import urllib.request
from dataclasses import dataclass

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer


bearer = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class AnalyticsPrincipal:
    user_id: int
    permissions: list[str]
    token: str

    def has(self, permission: str) -> bool:
        return permission in self.permissions


def get_current_principal(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
) -> AnalyticsPrincipal:
    if credentials is None:
        raise HTTPException(status_code=401, detail="Authentication required")
    request = urllib.request.Request(
        os.getenv("AUTH_API_URL", "http://auth-api:8000") + "/auth/me",
        headers={"Authorization": f"Bearer {credentials.credentials}"},
    )
    try:
        with urllib.request.urlopen(request, timeout=3) as response:
            payload = json.loads(response.read())
    except urllib.error.HTTPError as exc:
        raise HTTPException(status_code=exc.code, detail="Session is not valid")
    except (OSError, ValueError):
        raise HTTPException(status_code=503, detail="Authentication service unavailable")
    return AnalyticsPrincipal(
        user_id=int(payload["id"]),
        permissions=list(payload.get("permissions", [])),
        token=credentials.credentials,
    )


def assert_resource_access(kind: str, resource_id: int, principal: AnalyticsPrincipal) -> None:
    request = urllib.request.Request(
        f"{os.getenv('ADS_API_URL', 'http://ads-api:8080')}/{kind}/{resource_id}",
        headers={"Authorization": f"Bearer {principal.token}"},
    )
    try:
        with urllib.request.urlopen(request, timeout=3) as response:
            if response.status != 200:
                raise HTTPException(status_code=403, detail="Forbidden")
    except urllib.error.HTTPError as exc:
        if exc.code in {401, 403, 404}:
            raise HTTPException(status_code=403, detail="Forbidden")
        raise HTTPException(status_code=503, detail="Resource authorization unavailable")
    except OSError:
        raise HTTPException(status_code=503, detail="Resource authorization unavailable")
