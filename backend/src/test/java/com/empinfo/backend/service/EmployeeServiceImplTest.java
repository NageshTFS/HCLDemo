package com.empinfo.backend.service;

import com.empinfo.backend.dto.EmployeeRequest;
import com.empinfo.backend.dto.EmployeeResponse;
import com.empinfo.backend.exception.DuplicateEmailException;
import com.empinfo.backend.exception.EmployeeNotFoundException;
import com.empinfo.backend.model.Employee;
import com.empinfo.backend.repository.EmployeeRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class EmployeeServiceImplTest {

    @Mock
    private EmployeeRepository employeeRepository;

    @InjectMocks
    private EmployeeServiceImpl employeeService;

    private Employee employee;
    private EmployeeRequest request;

    @BeforeEach
    void setUp() {
        employee = new Employee();
        employee.setId(1L);
        employee.setFirstName("Ada");
        employee.setLastName("Lovelace");
        employee.setEmail("ada@example.com");
        employee.setPhone("555-1234");
        employee.setDepartment("Engineering");
        employee.setDesignation("Software Engineer");
        employee.setSalary(new BigDecimal("95000.00"));
        employee.setHireDate(LocalDate.of(2020, 1, 15));
        employee.setStatus("ACTIVE");
        employee.setCreatedAt(LocalDateTime.now());
        employee.setUpdatedAt(LocalDateTime.now());

        request = new EmployeeRequest();
        request.setFirstName("Ada");
        request.setLastName("Lovelace");
        request.setEmail("ada@example.com");
        request.setPhone("555-1234");
        request.setDepartment("Engineering");
        request.setDesignation("Software Engineer");
        request.setSalary(new BigDecimal("95000.00"));
        request.setHireDate(LocalDate.of(2020, 1, 15));
        request.setStatus("ACTIVE");
    }

    @Test
    void getAllEmployees_returnsMappedList() {
        when(employeeRepository.findAll()).thenReturn(List.of(employee));

        List<EmployeeResponse> result = employeeService.getAllEmployees();

        assertThat(result).hasSize(1);
        assertThat(result.get(0).getEmail()).isEqualTo("ada@example.com");
    }

    @Test
    void getEmployeeById_found_returnsMapped() {
        when(employeeRepository.findById(1L)).thenReturn(Optional.of(employee));

        EmployeeResponse result = employeeService.getEmployeeById(1L);

        assertThat(result.getId()).isEqualTo(1L);
        assertThat(result.getFirstName()).isEqualTo("Ada");
    }

    @Test
    void getEmployeeById_notFound_throws() {
        when(employeeRepository.findById(99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> employeeService.getEmployeeById(99L))
                .isInstanceOf(EmployeeNotFoundException.class);
    }

    @Test
    void createEmployee_savesAndReturnsMapped() {
        when(employeeRepository.existsByEmail("ada@example.com")).thenReturn(false);
        when(employeeRepository.save(any(Employee.class))).thenReturn(employee);

        EmployeeResponse result = employeeService.createEmployee(request);

        assertThat(result.getEmail()).isEqualTo("ada@example.com");
        ArgumentCaptor<Employee> captor = ArgumentCaptor.forClass(Employee.class);
        verify(employeeRepository).save(captor.capture());
        assertThat(captor.getValue().getFirstName()).isEqualTo("Ada");
    }

    @Test
    void createEmployee_duplicateEmail_throwsDuplicateEmailException() {
        when(employeeRepository.existsByEmail("ada@example.com")).thenReturn(true);

        assertThatThrownBy(() -> employeeService.createEmployee(request))
                .isInstanceOf(DuplicateEmailException.class);

        verify(employeeRepository, never()).save(any(Employee.class));
    }

    @Test
    void updateEmployee_found_updatesAndReturnsMapped() {
        when(employeeRepository.findById(1L)).thenReturn(Optional.of(employee));
        when(employeeRepository.existsByEmailAndIdNot("ada@example.com", 1L)).thenReturn(false);
        when(employeeRepository.save(any(Employee.class))).thenReturn(employee);

        request.setDesignation("Senior Software Engineer");
        EmployeeResponse result = employeeService.updateEmployee(1L, request);

        assertThat(result).isNotNull();
        verify(employeeRepository, times(1)).save(any(Employee.class));
    }

    @Test
    void updateEmployee_notFound_throws() {
        when(employeeRepository.findById(anyLong())).thenReturn(Optional.empty());

        assertThatThrownBy(() -> employeeService.updateEmployee(1L, request))
                .isInstanceOf(EmployeeNotFoundException.class);
    }

    @Test
    void updateEmployee_duplicateEmail_throws() {
        when(employeeRepository.findById(1L)).thenReturn(Optional.of(employee));
        when(employeeRepository.existsByEmailAndIdNot("ada@example.com", 1L)).thenReturn(true);

        assertThatThrownBy(() -> employeeService.updateEmployee(1L, request))
                .isInstanceOf(DuplicateEmailException.class);

        verify(employeeRepository, never()).save(any(Employee.class));
    }

    @Test
    void deleteEmployee_found_deletes() {
        when(employeeRepository.existsById(1L)).thenReturn(true);

        employeeService.deleteEmployee(1L);

        verify(employeeRepository).deleteById(1L);
    }

    @Test
    void deleteEmployee_notFound_throws() {
        when(employeeRepository.existsById(99L)).thenReturn(false);

        assertThatThrownBy(() -> employeeService.deleteEmployee(99L))
                .isInstanceOf(EmployeeNotFoundException.class);

        verify(employeeRepository, never()).deleteById(anyLong());
    }
}
