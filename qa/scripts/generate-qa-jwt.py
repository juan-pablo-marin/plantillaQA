#!/usr/bin/env python3
"""
Genera un JWT HS256 compatible con victims_backend (JWTMiddleware):
  - user_id: entero (obligatorio)
  - email, role: opcionales
  - exp: expiración

Uso (mismo JWT_SECRET que en .env.qa / backend):
  export JWT_SECRET='tu-secreto'
  python3 qa/scripts/generate-qa-jwt.py

  TEST_USER_ID=42 python3 qa/scripts/generate-qa-jwt.py
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import time


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode().rstrip("=")


def main() -> None:
    secret = os.environ.get("JWT_SECRET", "").encode()
    if not secret:
        raise SystemExit("Define JWT_SECRET (mismo valor que el contenedor backend).")

    uid = int(os.environ.get("TEST_USER_ID", "1"))
    email = os.environ.get("TEST_JWT_EMAIL", "qa@victimasrav.local")
    role = os.environ.get("TEST_JWT_ROLE", "funcionario")
    ttl = int(os.environ.get("TEST_JWT_TTL_SECONDS", "86400"))

    header = {"alg": "HS256", "typ": "JWT"}
    payload = {
        "user_id": uid,
        "email": email,
        "role": role,
        "exp": int(time.time()) + ttl,
    }

    h = b64url(json.dumps(header, separators=(",", ":")).encode())
    p = b64url(json.dumps(payload, separators=(",", ":")).encode())
    signing = f"{h}.{p}".encode()
    sig = b64url(hmac.new(secret, signing, hashlib.sha256).digest())
    print(f"{h}.{p}.{sig}")


if __name__ == "__main__":
    main()
