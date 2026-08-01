/**
 * auth.js
 *
 * Manages HTTP Basic auth credentials for the Employee Management app.
 * Credentials are kept in sessionStorage (cleared when the browser tab
 * closes) and never sent anywhere except as an Authorization header on
 * calls to /api/employees.
 */

const Auth = (function () {
  const STORAGE_KEY = 'empapp.basicAuthCredentials';

  function setCredentials(username, password) {
    const value = JSON.stringify({ username: username, password: password });
    sessionStorage.setItem(STORAGE_KEY, value);
  }

  function getCredentials() {
    const raw = sessionStorage.getItem(STORAGE_KEY);
    if (!raw) {
      return null;
    }
    try {
      return JSON.parse(raw);
    } catch (e) {
      return null;
    }
  }

  function clearCredentials() {
    sessionStorage.removeItem(STORAGE_KEY);
  }

  function isLoggedIn() {
    return getCredentials() !== null;
  }

  /**
   * Returns the value to use for the Authorization header
   * (e.g. "Basic dXNlcjpwYXNz"), or null if no credentials are stored.
   */
  function getAuthHeader() {
    const creds = getCredentials();
    if (!creds) {
      return null;
    }
    const token = btoa(unescape(encodeURIComponent(creds.username + ':' + creds.password)));
    return 'Basic ' + token;
  }

  return {
    setCredentials: setCredentials,
    getCredentials: getCredentials,
    clearCredentials: clearCredentials,
    isLoggedIn: isLoggedIn,
    getAuthHeader: getAuthHeader
  };
})();
