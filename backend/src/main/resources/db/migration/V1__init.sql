CREATE TABLE employees (
    id            BIGSERIAL PRIMARY KEY,
    first_name    VARCHAR(100)   NOT NULL,
    last_name     VARCHAR(100)   NOT NULL,
    email         VARCHAR(255)   NOT NULL,
    phone         VARCHAR(30),
    department    VARCHAR(100),
    designation   VARCHAR(100),
    salary        NUMERIC(12, 2),
    hire_date     DATE,
    status        VARCHAR(30),
    created_at    TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_employees_email UNIQUE (email)
);

CREATE INDEX idx_employees_email ON employees (email);
