/**
 * app.js
 *
 * UI wiring for the Employee Management POC: view switching (login /
 * list / add-edit form), table rendering, client-side validation that
 * mirrors the backend (first_name, last_name, email required; email
 * format), and CRUD actions against the API.
 */

(function () {
  const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

  // Views
  const loginView = document.getElementById('loginView');
  const listView = document.getElementById('listView');
  const formView = document.getElementById('formView');
  const logoutBtn = document.getElementById('logoutBtn');

  // Login form
  const loginForm = document.getElementById('loginForm');
  const loginError = document.getElementById('loginError');

  // List view
  const showAddFormBtn = document.getElementById('showAddFormBtn');
  const refreshBtn = document.getElementById('refreshBtn');
  const listError = document.getElementById('listError');
  const listLoading = document.getElementById('listLoading');
  const employeeTableBody = document.getElementById('employeeTableBody');
  const emptyMessage = document.getElementById('emptyMessage');

  // Employee form
  const employeeForm = document.getElementById('employeeForm');
  const formTitle = document.getElementById('formTitle');
  const formError = document.getElementById('formError');
  const cancelFormBtn = document.getElementById('cancelFormBtn');
  const employeeIdInput = document.getElementById('employeeId');
  const firstNameInput = document.getElementById('firstName');
  const lastNameInput = document.getElementById('lastName');
  const emailInput = document.getElementById('email');
  const phoneInput = document.getElementById('phone');
  const departmentInput = document.getElementById('department');
  const designationInput = document.getElementById('designation');
  const salaryInput = document.getElementById('salary');
  const hireDateInput = document.getElementById('hireDate');
  const statusInput = document.getElementById('status');

  function showView(view) {
    [loginView, listView, formView].forEach(function (v) {
      v.classList.add('hidden');
    });
    view.classList.remove('hidden');
    logoutBtn.classList.toggle('hidden', view === loginView);
  }

  function showLogin(message) {
    showView(loginView);
    if (message) {
      loginError.textContent = message;
      loginError.classList.remove('hidden');
    } else {
      loginError.textContent = '';
      loginError.classList.add('hidden');
    }
  }

  function showList() {
    showView(listView);
    loadEmployees();
  }

  function clearFieldErrors() {
    document.querySelectorAll('.field-error').forEach(function (el) {
      el.textContent = '';
    });
    document.querySelectorAll('.input-error').forEach(function (el) {
      el.classList.remove('input-error');
    });
    formError.classList.add('hidden');
    formError.textContent = '';
  }

  function setFieldError(input, errorEl, message) {
    input.classList.add('input-error');
    errorEl.textContent = message;
  }

  function showAddForm() {
    clearFieldErrors();
    employeeForm.reset();
    employeeIdInput.value = '';
    formTitle.textContent = 'Add Employee';
    statusInput.value = 'ACTIVE';
    showView(formView);
  }

  function showEditForm(employee) {
    clearFieldErrors();
    employeeForm.reset();
    employeeIdInput.value = employee.id;
    firstNameInput.value = employee.firstName || '';
    lastNameInput.value = employee.lastName || '';
    emailInput.value = employee.email || '';
    phoneInput.value = employee.phone || '';
    departmentInput.value = employee.department || '';
    designationInput.value = employee.designation || '';
    salaryInput.value = (employee.salary !== undefined && employee.salary !== null) ? employee.salary : '';
    hireDateInput.value = employee.hireDate || '';
    statusInput.value = employee.status || 'ACTIVE';
    formTitle.textContent = 'Edit Employee';
    showView(formView);
  }

  /**
   * Client-side validation mirroring the backend: first_name, last_name
   * and email are required, and email must look like a valid address.
   */
  function validateEmployeeForm() {
    clearFieldErrors();
    let valid = true;

    if (!firstNameInput.value.trim()) {
      setFieldError(firstNameInput, document.getElementById('firstNameError'), 'First name is required.');
      valid = false;
    }

    if (!lastNameInput.value.trim()) {
      setFieldError(lastNameInput, document.getElementById('lastNameError'), 'Last name is required.');
      valid = false;
    }

    const emailValue = emailInput.value.trim();
    if (!emailValue) {
      setFieldError(emailInput, document.getElementById('emailError'), 'Email is required.');
      valid = false;
    } else if (!EMAIL_PATTERN.test(emailValue)) {
      setFieldError(emailInput, document.getElementById('emailError'), 'Enter a valid email address.');
      valid = false;
    }

    return valid;
  }

  function buildEmployeePayload() {
    return {
      firstName: firstNameInput.value.trim(),
      lastName: lastNameInput.value.trim(),
      email: emailInput.value.trim(),
      phone: phoneInput.value.trim(),
      department: departmentInput.value.trim(),
      designation: designationInput.value.trim(),
      salary: salaryInput.value === '' ? null : Number(salaryInput.value),
      hireDate: hireDateInput.value || null,
      status: statusInput.value
    };
  }

  function escapeHtml(value) {
    const div = document.createElement('div');
    div.textContent = value === undefined || value === null ? '' : String(value);
    return div.innerHTML;
  }

  function formatSalary(salary) {
    if (salary === undefined || salary === null || salary === '') {
      return '';
    }
    const num = Number(salary);
    return isNaN(num) ? String(salary) : num.toFixed(2);
  }

  function renderEmployees(employees) {
    employeeTableBody.innerHTML = '';

    if (!employees || employees.length === 0) {
      emptyMessage.classList.remove('hidden');
      return;
    }
    emptyMessage.classList.add('hidden');

    employees.forEach(function (employee) {
      const tr = document.createElement('tr');
      tr.innerHTML =
        '<td>' + escapeHtml(employee.id) + '</td>' +
        '<td>' + escapeHtml(employee.firstName) + '</td>' +
        '<td>' + escapeHtml(employee.lastName) + '</td>' +
        '<td>' + escapeHtml(employee.email) + '</td>' +
        '<td>' + escapeHtml(employee.phone) + '</td>' +
        '<td>' + escapeHtml(employee.department) + '</td>' +
        '<td>' + escapeHtml(employee.designation) + '</td>' +
        '<td>' + escapeHtml(formatSalary(employee.salary)) + '</td>' +
        '<td>' + escapeHtml(employee.hireDate) + '</td>' +
        '<td>' + escapeHtml(employee.status) + '</td>' +
        '<td></td>';

      const actionsCell = tr.lastElementChild;

      const editBtn = document.createElement('button');
      editBtn.type = 'button';
      editBtn.className = 'btn btn-secondary btn-small';
      editBtn.textContent = 'Edit';
      editBtn.addEventListener('click', function () {
        showEditForm(employee);
      });

      const deleteBtn = document.createElement('button');
      deleteBtn.type = 'button';
      deleteBtn.className = 'btn btn-danger btn-small';
      deleteBtn.textContent = 'Delete';
      deleteBtn.addEventListener('click', function () {
        handleDelete(employee);
      });

      actionsCell.appendChild(editBtn);
      actionsCell.appendChild(deleteBtn);

      employeeTableBody.appendChild(tr);
    });
  }

  async function loadEmployees() {
    listError.classList.add('hidden');
    listLoading.classList.remove('hidden');
    try {
      const employees = await Api.getAll();
      renderEmployees(employees);
    } catch (err) {
      listError.textContent = err.message || 'Failed to load employees.';
      listError.classList.remove('hidden');
    } finally {
      listLoading.classList.add('hidden');
    }
  }

  async function handleDelete(employee) {
    const label = (employee.firstName || '') + ' ' + (employee.lastName || '');
    if (!window.confirm('Delete employee "' + label.trim() + '"?')) {
      return;
    }
    try {
      await Api.remove(employee.id);
      loadEmployees();
    } catch (err) {
      listError.textContent = err.message || 'Failed to delete employee.';
      listError.classList.remove('hidden');
    }
  }

  async function handleEmployeeFormSubmit(evt) {
    evt.preventDefault();
    if (!validateEmployeeForm()) {
      return;
    }

    const payload = buildEmployeePayload();
    const id = employeeIdInput.value;

    try {
      if (id) {
        await Api.update(id, payload);
      } else {
        await Api.create(payload);
      }
      showList();
    } catch (err) {
      formError.textContent = err.message || 'Failed to save employee.';
      formError.classList.remove('hidden');
    }
  }

  async function handleLoginSubmit(evt) {
    evt.preventDefault();
    loginError.classList.add('hidden');

    const username = document.getElementById('username').value.trim();
    const password = document.getElementById('password').value;

    if (!username || !password) {
      loginError.textContent = 'Username and password are required.';
      loginError.classList.remove('hidden');
      return;
    }

    Auth.setCredentials(username, password);

    try {
      // Verify the credentials work before treating the user as logged in.
      await Api.getAll().then(function (employees) {
        loginForm.reset();
        showView(listView);
        renderEmployees(employees);
      });
    } catch (err) {
      Auth.clearCredentials();
      loginError.textContent = 'Invalid username or password.';
      loginError.classList.remove('hidden');
    }
  }

  function handleLogout() {
    Auth.clearCredentials();
    showLogin();
  }

  function handleUnauthorizedEvent() {
    showLogin('Your session has expired. Please log in again.');
  }

  // Wire up events
  loginForm.addEventListener('submit', handleLoginSubmit);
  logoutBtn.addEventListener('click', handleLogout);
  showAddFormBtn.addEventListener('click', showAddForm);
  refreshBtn.addEventListener('click', loadEmployees);
  cancelFormBtn.addEventListener('click', showList);
  employeeForm.addEventListener('submit', handleEmployeeFormSubmit);
  window.addEventListener('unauthorized', handleUnauthorizedEvent);

  // Initial view
  if (Auth.isLoggedIn()) {
    showList();
  } else {
    showLogin();
  }
})();
