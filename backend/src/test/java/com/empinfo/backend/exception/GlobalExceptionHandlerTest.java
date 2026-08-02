package com.empinfo.backend.exception;

import jakarta.validation.ConstraintViolationException;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.ResponseEntity;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.web.ErrorResponseException;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.context.request.ServletWebRequest;
import org.springframework.web.context.request.WebRequest;

import java.util.Collections;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Exercises GlobalExceptionHandler directly. The status-code mapping for the common cases is
 * already covered end-to-end through MockMvc in EmployeeControllerTest; what needs a direct
 * caller is the fallback logic inside handleExceptionInternal, whose branches (5xx, non-standard
 * status, exception carrying no detail) no ordinary request can reach.
 */
class GlobalExceptionHandlerTest {

    private static final String BAD_REQUEST_REASON = "Bad Request";

    private final GlobalExceptionHandler handler = new GlobalExceptionHandler();

    private WebRequest webRequest() {
        return new ServletWebRequest(new MockHttpServletRequest());
    }

    // Distinct name from typedBodyOf below: both take a ResponseEntity, which erases to the
    // same signature, so overloading on the type argument would not compile.
    private ErrorResponse rawBodyOf(ResponseEntity<Object> response) {
        assertThat(response.getBody()).isInstanceOf(ErrorResponse.class);
        return (ErrorResponse) response.getBody();
    }

    private ErrorResponse typedBodyOf(ResponseEntity<ErrorResponse> response, HttpStatus expectedStatus) {
        assertThat(response.getStatusCode()).isEqualTo(expectedStatus);
        ErrorResponse body = response.getBody();
        assertThat(body).isNotNull();
        return body;
    }

    @Test
    void dataIntegrityViolation_returns409() {
        ErrorResponse body = typedBodyOf(
                handler.handleDataIntegrityViolation(new DataIntegrityViolationException("duplicate key")),
                HttpStatus.CONFLICT);

        assertThat(body.getStatus()).isEqualTo(409);
        // The DB's own message is deliberately not echoed back.
        assertThat(body.getMessage())
                .isEqualTo("A record with the same unique value (e.g. email) already exists");
    }

    @Test
    void constraintViolation_returns400() {
        ErrorResponse body = typedBodyOf(
                handler.handleConstraintViolation(new ConstraintViolationException(
                        "salary must be positive", Collections.emptySet())),
                HttpStatus.BAD_REQUEST);

        assertThat(body.getStatus()).isEqualTo(400);
        assertThat(body.getMessage()).contains("salary must be positive");
    }

    @Test
    void genericException_returns500WithOpaqueMessage() {
        ErrorResponse body = typedBodyOf(
                handler.handleGeneric(new IllegalStateException("boom")),
                HttpStatus.INTERNAL_SERVER_ERROR);

        // "boom" must not leak to the client - it goes to the log instead.
        assertThat(body.getMessage()).isEqualTo("An unexpected error occurred");
    }

    @Test
    void frameworkException_keepsItsStatusAndSpringsSafeDetail() {
        HttpRequestMethodNotSupportedException ex = new HttpRequestMethodNotSupportedException("DELETE");

        ResponseEntity<Object> response = handler.handleExceptionInternal(
                ex, null, new HttpHeaders(), HttpStatus.METHOD_NOT_ALLOWED, webRequest());

        ErrorResponse body = rawBodyOf(response);
        assertThat(body.getStatus()).isEqualTo(405);
        assertThat(body.getError()).isEqualTo("Method Not Allowed");
        assertThat(body.getMessage()).contains("DELETE");
    }

    @Test
    void serverErrorFromFramework_doesNotLeakInternals() {
        ResponseEntity<Object> response = handler.handleExceptionInternal(
                new IllegalStateException("connection pool exhausted at com.internal.Pool"),
                null, new HttpHeaders(), HttpStatus.INTERNAL_SERVER_ERROR, webRequest());

        ErrorResponse body = rawBodyOf(response);
        assertThat(body.getStatus()).isEqualTo(500);
        assertThat(body.getMessage()).isEqualTo("An unexpected error occurred");
        assertThat(body.getMessage()).doesNotContain("connection pool");
    }

    @Test
    void exceptionWithNoDetail_fallsBackToReasonPhrase() {
        // ErrorResponseException built from a bare status has a null ProblemDetail detail.
        ResponseEntity<Object> response = handler.handleExceptionInternal(
                new ErrorResponseException(HttpStatus.BAD_REQUEST),
                null, new HttpHeaders(), HttpStatus.BAD_REQUEST, webRequest());

        ErrorResponse body = rawBodyOf(response);
        assertThat(body.getStatus()).isEqualTo(400);
        assertThat(body.getMessage()).isEqualTo(BAD_REQUEST_REASON);
    }

    @Test
    void plainExceptionOn4xx_fallsBackToReasonPhrase() {
        ResponseEntity<Object> response = handler.handleExceptionInternal(
                new IllegalArgumentException("bad input"),
                null, new HttpHeaders(), HttpStatus.BAD_REQUEST, webRequest());

        ErrorResponse body = rawBodyOf(response);
        assertThat(body.getStatus()).isEqualTo(400);
        assertThat(body.getMessage()).isEqualTo(BAD_REQUEST_REASON);
    }

    @Test
    void nonStandardStatusCode_stillProducesABody() {
        // 499 has no HttpStatus constant, so the reason-phrase lookup returns null.
        ResponseEntity<Object> response = handler.handleExceptionInternal(
                new IllegalStateException("nginx client closed request"),
                null, new HttpHeaders(), HttpStatusCode.valueOf(499), webRequest());

        ErrorResponse body = rawBodyOf(response);
        assertThat(body.getStatus()).isEqualTo(499);
        assertThat(body.getError()).isEqualTo("Error");
    }

    @Test
    void preSuppliedErrorResponseBodyIsPassedThrough() {
        // handleMethodArgumentNotValid builds its own body with fieldErrors - that must survive.
        ErrorResponse supplied = new ErrorResponse(400, BAD_REQUEST_REASON, "Validation failed",
                Collections.singletonMap("email", "must not be blank"));

        ResponseEntity<Object> response = handler.handleExceptionInternal(
                new IllegalStateException("ignored"), supplied, new HttpHeaders(),
                HttpStatus.BAD_REQUEST, webRequest());

        ErrorResponse body = rawBodyOf(response);
        assertThat(body).isSameAs(supplied);
        assertThat(body.getFieldErrors()).containsEntry("email", "must not be blank");
    }
}
