package com.empinfo.backend.exception;

public class DuplicateEmailException extends RuntimeException {

    public DuplicateEmailException(String email) {
        super("An employee with email '" + email + "' already exists");
    }
}
