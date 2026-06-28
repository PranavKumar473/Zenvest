"""
AES-256 encryption utilities for sensitive financial data at rest.
Uses Fernet (AES-128-CBC via cryptography library) for field-level encryption.
"""

import base64
import hashlib
from cryptography.fernet import Fernet
from app.config import get_settings


def _get_fernet() -> Fernet:
    """Create a Fernet instance from the configured encryption key."""
    settings = get_settings()
    # Derive a 32-byte key using SHA-256, then base64-encode for Fernet
    key_bytes = hashlib.sha256(settings.ENCRYPTION_KEY.encode()).digest()
    fernet_key = base64.urlsafe_b64encode(key_bytes)
    return Fernet(fernet_key)


def encrypt_value(plaintext: str) -> str:
    """
    Encrypt a string value.
    Returns base64-encoded ciphertext suitable for database storage.
    """
    fernet = _get_fernet()
    encrypted = fernet.encrypt(plaintext.encode("utf-8"))
    return encrypted.decode("utf-8")


def decrypt_value(ciphertext: str) -> str:
    """
    Decrypt a previously encrypted value.
    Returns the original plaintext string.
    Raises cryptography.fernet.InvalidToken if the key is wrong or data is corrupted.
    """
    fernet = _get_fernet()
    decrypted = fernet.decrypt(ciphertext.encode("utf-8"))
    return decrypted.decode("utf-8")
