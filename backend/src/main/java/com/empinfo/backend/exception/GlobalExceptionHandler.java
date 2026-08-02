package com.empinfo.backend.exception;

import jakarta.validation.ConstraintViolationException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.ResponseEntity;
import org.springframework.lang.Nullable;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.context.request.WebRequest;
import org.springframework.web.servlet.mvc.method.annotation.ResponseEntityExceptionHandler;

import java.util.HashMap;
import java.util.Map;

/**
 * Extends {@link ResponseEntityExceptionHandler} on purpose. Spring MVC raises its own exceptions
 * for request-level problems - unmapped path (NoResourceFoundException), wrong HTTP method
 * (HttpRequestMethodNotSupportedException), unparseable body (HttpMessageNotReadableException),
 * bad path-variable type (MethodArgumentTypeMismatchException), and so on - each of which already
 * carries the correct 4xx status. Without this base class, the catch-all
 * {@code @ExceptionHandler(Exception.class)} below is the only match for all of them and flattens
 * every one into a 500 (e.g. GET /api/2 returned 500 instead of 404). The inherited handlers are
 * more specific than {@code Exception}, so Spring now picks them first and the catch-all is left
 * with genuinely unexpected failures only.
 */
@RestControllerAdvice
public class GlobalExceptionHandler extends ResponseEntityExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    // Deliberately opaque: server-side failures must not describe themselves to the caller.
    private static final String GENERIC_ERROR_MESSAGE = "An unexpected error occurred";

    @ExceptionHandler(EmployeeNotFoundException.class)
    public ResponseEntity<ErrorResponse> handleNotFound(EmployeeNotFoundException ex) {
        ErrorResponse body = new ErrorResponse(
                HttpStatus.NOT_FOUND.value(),
                HttpStatus.NOT_FOUND.getReasonPhrase(),
                ex.getMessage());
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(body);
    }

    @ExceptionHandler(DuplicateEmailException.class)
    public ResponseEntity<ErrorResponse> handleDuplicateEmail(DuplicateEmailException ex) {
        ErrorResponse body = new ErrorResponse(
                HttpStatus.CONFLICT.value(),
                HttpStatus.CONFLICT.getReasonPhrase(),
                ex.getMessage());
        return ResponseEntity.status(HttpStatus.CONFLICT).body(body);
    }

    // Backstop for the unique constraint at the DB level (e.g. race condition
    // between the app-layer uniqueness check and the insert/update).
    @ExceptionHandler(DataIntegrityViolationException.class)
    public ResponseEntity<ErrorResponse> handleDataIntegrityViolation(DataIntegrityViolationException ex) {
        ErrorResponse body = new ErrorResponse(
                HttpStatus.CONFLICT.value(),
                HttpStatus.CONFLICT.getReasonPhrase(),
                "A record with the same unique value (e.g. email) already exists");
        return ResponseEntity.status(HttpStatus.CONFLICT).body(body);
    }

    @ExceptionHandler(ConstraintViolationException.class)
    public ResponseEntity<ErrorResponse> handleConstraintViolation(ConstraintViolationException ex) {
        ErrorResponse body = new ErrorResponse(
                HttpStatus.BAD_REQUEST.value(),
                HttpStatus.BAD_REQUEST.getReasonPhrase(),
                ex.getMessage());
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(body);
    }

    /**
     * Overrides the inherited handler rather than declaring a second one for the same exception:
     * two {@code @ExceptionHandler} methods mapped to MethodArgumentNotValidException in one advice
     * is an ambiguous mapping and fails the context at startup.
     */
    @Override
    protected ResponseEntity<Object> handleMethodArgumentNotValid(MethodArgumentNotValidException ex,
                                                                  HttpHeaders headers,
                                                                  HttpStatusCode status,
                                                                  WebRequest request) {
        Map<String, String> fieldErrors = new HashMap<>();
        for (FieldError fieldError : ex.getBindingResult().getFieldErrors()) {
            fieldErrors.put(fieldError.getField(), fieldError.getDefaultMessage());
        }
        ErrorResponse body = new ErrorResponse(
                HttpStatus.BAD_REQUEST.value(),
                HttpStatus.BAD_REQUEST.getReasonPhrase(),
                "Validation failed for one or more fields",
                fieldErrors);
        return handleExceptionInternal(ex, body, headers, HttpStatus.BAD_REQUEST, request);
    }

    /**
     * Single funnel for every exception the base class handles, so framework errors come back in
     * the same JSON shape as the application's own errors instead of Spring's default ProblemDetail.
     */
    @Override
    protected ResponseEntity<Object> handleExceptionInternal(Exception ex,
                                                             @Nullable Object body,
                                                             HttpHeaders headers,
                                                             HttpStatusCode statusCode,
                                                             WebRequest request) {
        Object responseBody = (body instanceof ErrorResponse) ? body : toErrorResponse(ex, statusCode);
        return super.handleExceptionInternal(ex, responseBody, headers, statusCode, request);
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handleGeneric(Exception ex) {
        // Logged because the client-facing message is deliberately opaque - without this, a real
        // 500 leaves nothing at all to diagnose from.
        log.error("Unhandled exception", ex);
        ErrorResponse body = new ErrorResponse(
                HttpStatus.INTERNAL_SERVER_ERROR.value(),
                HttpStatus.INTERNAL_SERVER_ERROR.getReasonPhrase(),
                GENERIC_ERROR_MESSAGE);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(body);
    }

    private ErrorResponse toErrorResponse(Exception ex, HttpStatusCode statusCode) {
        HttpStatus resolved = HttpStatus.resolve(statusCode.value());
        String reason = (resolved != null) ? resolved.getReasonPhrase() : "Error";

        String message;
        if (statusCode.is5xxServerError()) {
            // Never surface framework internals on a server error.
            log.error("Unhandled exception", ex);
            message = GENERIC_ERROR_MESSAGE;
        } else if (ex instanceof org.springframework.web.ErrorResponse errorResponse) {
            // Spring's own short, safe description ("Method 'DELETE' is not supported.") rather
            // than ex.getMessage(), which can carry parser/stack detail.
            String detail = errorResponse.getBody().getDetail();
            message = (detail != null) ? detail : reason;
        } else {
            message = reason;
        }
        return new ErrorResponse(statusCode.value(), reason, message);
    }
}
