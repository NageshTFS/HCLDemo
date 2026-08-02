package com.empinfo.backend.controller;

import com.empinfo.backend.config.SecurityConfig;
import com.empinfo.backend.dto.EmployeeRequest;
import com.empinfo.backend.dto.EmployeeResponse;
import com.empinfo.backend.exception.DuplicateEmailException;
import com.empinfo.backend.exception.EmployeeNotFoundException;
import com.empinfo.backend.service.EmployeeService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.httpBasic;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(EmployeeController.class)
@Import(SecurityConfig.class)
class EmployeeControllerTest {

    private static final String USER = "testuser";
    private static final String PASS = "testpass";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockitoBean
    private EmployeeService employeeService;

    private EmployeeResponse sampleResponse() {
        EmployeeResponse response = new EmployeeResponse();
        response.setId(1L);
        response.setFirstName("Ada");
        response.setLastName("Lovelace");
        response.setEmail("ada@example.com");
        response.setPhone("555-1234");
        response.setDepartment("Engineering");
        response.setDesignation("Software Engineer");
        response.setSalary(new BigDecimal("95000.00"));
        response.setHireDate(LocalDate.of(2020, 1, 15));
        response.setStatus("ACTIVE");
        response.setCreatedAt(LocalDateTime.now());
        response.setUpdatedAt(LocalDateTime.now());
        return response;
    }

    private EmployeeRequest sampleRequest() {
        EmployeeRequest request = new EmployeeRequest();
        request.setFirstName("Ada");
        request.setLastName("Lovelace");
        request.setEmail("ada@example.com");
        request.setPhone("555-1234");
        request.setDepartment("Engineering");
        request.setDesignation("Software Engineer");
        request.setSalary(new BigDecimal("95000.00"));
        request.setHireDate(LocalDate.of(2020, 1, 15));
        request.setStatus("ACTIVE");
        return request;
    }

    @Test
    void getAllEmployees_withoutAuth_returns401() throws Exception {
        mockMvc.perform(get("/api/employees"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void getAllEmployees_withAuth_returns200() throws Exception {
        when(employeeService.getAllEmployees()).thenReturn(List.of(sampleResponse()));

        mockMvc.perform(get("/api/employees").with(httpBasic(USER, PASS)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].email").value("ada@example.com"));
    }

    @Test
    void getEmployeeById_found_returns200() throws Exception {
        when(employeeService.getEmployeeById(1L)).thenReturn(sampleResponse());

        mockMvc.perform(get("/api/employees/1").with(httpBasic(USER, PASS)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(1));
    }

    @Test
    void getEmployeeById_notFound_returns404() throws Exception {
        when(employeeService.getEmployeeById(99L)).thenThrow(new EmployeeNotFoundException(99L));

        mockMvc.perform(get("/api/employees/99").with(httpBasic(USER, PASS)))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.status").value(404));
    }

    @Test
    void createEmployee_valid_returns201() throws Exception {
        when(employeeService.createEmployee(any(EmployeeRequest.class))).thenReturn(sampleResponse());

        mockMvc.perform(post("/api/employees")
                        .with(httpBasic(USER, PASS))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(sampleRequest())))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.email").value("ada@example.com"));
    }

    @Test
    void createEmployee_missingRequiredFields_returns400() throws Exception {
        EmployeeRequest invalid = new EmployeeRequest();
        invalid.setEmail("not-an-email");

        mockMvc.perform(post("/api/employees")
                        .with(httpBasic(USER, PASS))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(invalid)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.status").value(400))
                .andExpect(jsonPath("$.fieldErrors.firstName").exists())
                .andExpect(jsonPath("$.fieldErrors.lastName").exists());
    }

    @Test
    void createEmployee_duplicateEmail_returns409() throws Exception {
        when(employeeService.createEmployee(any(EmployeeRequest.class)))
                .thenThrow(new DuplicateEmailException("ada@example.com"));

        mockMvc.perform(post("/api/employees")
                        .with(httpBasic(USER, PASS))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(sampleRequest())))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.status").value(409));
    }

    @Test
    void updateEmployee_valid_returns200() throws Exception {
        when(employeeService.updateEmployee(eq(1L), any(EmployeeRequest.class))).thenReturn(sampleResponse());

        mockMvc.perform(put("/api/employees/1")
                        .with(httpBasic(USER, PASS))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(sampleRequest())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(1));
    }

    @Test
    void updateEmployee_duplicateEmail_returns409() throws Exception {
        when(employeeService.updateEmployee(eq(1L), any(EmployeeRequest.class)))
                .thenThrow(new DuplicateEmailException("ada@example.com"));

        mockMvc.perform(put("/api/employees/1")
                        .with(httpBasic(USER, PASS))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(sampleRequest())))
                .andExpect(status().isConflict());
    }

    @Test
    void deleteEmployee_found_returns204() throws Exception {
        mockMvc.perform(delete("/api/employees/1").with(httpBasic(USER, PASS)))
                .andExpect(status().isNoContent());

        verify(employeeService).deleteEmployee(1L);
    }

    @Test
    void deleteEmployee_notFound_returns404() throws Exception {
        org.mockito.Mockito.doThrow(new EmployeeNotFoundException(99L))
                .when(employeeService).deleteEmployee(99L);

        mockMvc.perform(delete("/api/employees/99").with(httpBasic(USER, PASS)))
                .andExpect(status().isNotFound());
    }

    // --- Framework-level errors -------------------------------------------------------------
    // These all used to come back as 500: the advice's catch-all @ExceptionHandler(Exception.class)
    // was the only match for Spring MVC's own exceptions, so it overrode their correct 4xx status.

    @Test
    void unmappedApiPath_returns404NotAServerError() throws Exception {
        mockMvc.perform(get("/api/2").with(httpBasic(USER, PASS)))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.status").value(404));
    }

    @Test
    void unsupportedHttpMethod_returns405() throws Exception {
        mockMvc.perform(delete("/api/employees").with(httpBasic(USER, PASS)))
                .andExpect(status().isMethodNotAllowed())
                .andExpect(jsonPath("$.status").value(405));
    }

    @Test
    void nonNumericId_returns400() throws Exception {
        mockMvc.perform(get("/api/employees/abc").with(httpBasic(USER, PASS)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.status").value(400));
    }

    @Test
    void malformedJsonBody_returns400() throws Exception {
        mockMvc.perform(post("/api/employees")
                        .with(httpBasic(USER, PASS))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{bad json"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.status").value(400));
    }

    @Test
    void unsupportedMediaType_returns415() throws Exception {
        mockMvc.perform(post("/api/employees")
                        .with(httpBasic(USER, PASS))
                        .contentType(MediaType.TEXT_PLAIN)
                        .content("not json"))
                .andExpect(status().isUnsupportedMediaType())
                .andExpect(jsonPath("$.status").value(415));
    }

    @Test
    void unexpectedServiceFailure_stillReturns500() throws Exception {
        when(employeeService.getAllEmployees()).thenThrow(new IllegalStateException("boom"));

        mockMvc.perform(get("/api/employees").with(httpBasic(USER, PASS)))
                .andExpect(status().isInternalServerError())
                .andExpect(jsonPath("$.status").value(500))
                .andExpect(jsonPath("$.message").value("An unexpected error occurred"));
    }
}
