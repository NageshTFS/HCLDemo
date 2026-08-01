/**
 * api.js
 *
 * Thin wrapper around fetch() for the /api/employees REST API.
 * All calls are same-origin relative URLs (no host, no CORS handling
 * needed) and carry an HTTP Basic Authorization header built from the
 * credentials stored by auth.js.
 *
 * On any 401 response, stored credentials are cleared and an
 * 'unauthorized' event is dispatched on window so app.js can show the
 * login form again.
 */

const Api = (function () {
  const BASE_URL = '/api/employees';

  function buildHeaders(hasBody) {
    const headers = {};
    const authHeader = Auth.getAuthHeader();
    if (authHeader) {
      headers['Authorization'] = authHeader;
    }
    if (hasBody) {
      headers['Content-Type'] = 'application/json';
    }
    return headers;
  }

  function handleUnauthorized() {
    Auth.clearCredentials();
    window.dispatchEvent(new CustomEvent('unauthorized'));
  }

  async function request(path, options) {
    options = options || {};
    const hasBody = options.body !== undefined;
    const response = await fetch(BASE_URL + path, {
      method: options.method || 'GET',
      headers: buildHeaders(hasBody),
      body: hasBody ? JSON.stringify(options.body) : undefined
    });

    if (response.status === 401) {
      handleUnauthorized();
      throw new Error('Not authorized. Please log in again.');
    }

    if (response.status === 204) {
      return null;
    }

    let payload = null;
    const text = await response.text();
    if (text) {
      try {
        payload = JSON.parse(text);
      } catch (e) {
        payload = text;
      }
    }

    if (!response.ok) {
      const message = (payload && (payload.message || payload.error)) ||
        ('Request failed with status ' + response.status);
      throw new Error(message);
    }

    return payload;
  }

  function getAll() {
    return request('', { method: 'GET' });
  }

  function getById(id) {
    return request('/' + encodeURIComponent(id), { method: 'GET' });
  }

  function create(employee) {
    return request('', { method: 'POST', body: employee });
  }

  function update(id, employee) {
    return request('/' + encodeURIComponent(id), { method: 'PUT', body: employee });
  }

  function remove(id) {
    return request('/' + encodeURIComponent(id), { method: 'DELETE' });
  }

  return {
    getAll: getAll,
    getById: getById,
    create: create,
    update: update,
    remove: remove
  };
})();
