"""
AES-256-GCM encryption for real-time transaction sync payloads.
Provides authenticated encryption with associated data (AEAD) for
securing transaction data both in transit and at rest.
"""

import base64
import hashlib
import json
import os
from typing import Optional

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from app.config import get_settings


def _derive_key() -> bytes:
    """Derive a 256-bit key from the configured encryption key using SHA-256."""
    settings = get_settings()
    return hashlib.sha256(settings.ENCRYPTION_KEY.encode("utf-8")).digest()


def encrypt_payload(data: dict) -> dict:
    """
    Encrypt a dict payload using AES-256-GCM.
    Returns: {"iv": base64, "ciphertext": base64, "tag": base64}
    The tag is appended to ciphertext by AESGCM, we separate it for clarity.
    """
    key = _derive_key()
    aesgcm = AESGCM(key)
    nonce = os.urandom(12)  # 96-bit nonce for GCM

    plaintext = json.dumps(data).encode("utf-8")
    # AESGCM.encrypt appends the 16-byte tag to the ciphertext
    ct_with_tag = aesgcm.encrypt(nonce, plaintext, None)

    # Split: ciphertext is everything except last 16 bytes, tag is last 16
    ciphertext = ct_with_tag[:-16]
    tag = ct_with_tag[-16:]

    return {
        "iv": base64.b64encode(nonce).decode("utf-8"),
        "ciphertext": base64.b64encode(ciphertext).decode("utf-8"),
        "tag": base64.b64encode(tag).decode("utf-8"),
    }


def decrypt_payload(encrypted: dict) -> Optional[dict]:
    """
    Decrypt an AES-256-GCM encrypted payload.
    Input: {"iv": base64, "ciphertext": base64, "tag": base64}
    Returns the decrypted dict, or None if decryption fails.
    """
    try:
        key = _derive_key()
        aesgcm = AESGCM(key)

        nonce = base64.b64decode(encrypted["iv"])
        ciphertext = base64.b64decode(encrypted["ciphertext"])
        tag = base64.b64decode(encrypted["tag"])

        # Reassemble ciphertext + tag for AESGCM.decrypt
        ct_with_tag = ciphertext + tag
        plaintext = aesgcm.decrypt(nonce, ct_with_tag, None)

        return json.loads(plaintext.decode("utf-8"))
    except Exception:
        return None


def encrypt_field(value: str) -> str:
    """Encrypt a single string field for at-rest storage."""
    key = _derive_key()
    aesgcm = AESGCM(key)
    nonce = os.urandom(12)
    ct_with_tag = aesgcm.encrypt(nonce, value.encode("utf-8"), None)
    # Store as: base64(nonce + ciphertext_with_tag)
    combined = nonce + ct_with_tag
    return base64.b64encode(combined).decode("utf-8")


def decrypt_field(encrypted_value: str) -> Optional[str]:
    """Decrypt a single encrypted field from at-rest storage."""
    try:
        key = _derive_key()
        aesgcm = AESGCM(key)
        combined = base64.b64decode(encrypted_value)
        nonce = combined[:12]
        ct_with_tag = combined[12:]
        plaintext = aesgcm.decrypt(nonce, ct_with_tag, None)
        return plaintext.decode("utf-8")
    except Exception:
        return None
