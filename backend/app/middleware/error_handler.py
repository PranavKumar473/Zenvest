"""
Global error handling middleware.
Catches unhandled exceptions and returns structured JSON error responses.
"""

import logging
import traceback
from fastapi import Request, status
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

logger = logging.getLogger("error_handler")


class GlobalErrorHandler(BaseHTTPMiddleware):
    """
    Catches all unhandled exceptions and returns structured error responses.
    Prevents stack traces from leaking to clients in production.
    """

    async def dispatch(self, request: Request, call_next):
        try:
            response = await call_next(request)
            return response
        except ValueError as e:
            logger.warning("Validation error: %s", str(e))
            return JSONResponse(
                status_code=status.HTTP_400_BAD_REQUEST,
                content={
                    "error": "validation_error",
                    "message": str(e),
                },
            )
        except PermissionError as e:
            logger.warning("Permission denied: %s", str(e))
            return JSONResponse(
                status_code=status.HTTP_403_FORBIDDEN,
                content={
                    "error": "forbidden",
                    "message": "You do not have permission to perform this action",
                },
            )
        except Exception as e:
            # Log full traceback server-side
            logger.error(
                "Unhandled exception on %s %s: %s\n%s",
                request.method,
                request.url.path,
                str(e),
                traceback.format_exc(),
            )

            # Return sanitized error to client
            return JSONResponse(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                content={
                    "error": "internal_server_error",
                    "message": "An unexpected error occurred. Please try again later.",
                },
            )
