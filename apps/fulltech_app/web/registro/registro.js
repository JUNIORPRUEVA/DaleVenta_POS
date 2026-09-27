(function () {
  'use strict';

  var form = document.getElementById('registerForm');
  var alertBox = document.getElementById('formAlert');
  var submitButton = document.getElementById('submitButton');
  var togglePassword = document.getElementById('togglePassword');
  var passwordInput = document.getElementById('password');
  var fields = {
    firstName: document.getElementById('firstName'),
    commercialName: document.getElementById('commercialName'),
    phone: document.getElementById('phone'),
    email: document.getElementById('email'),
    password: passwordInput,
    terms: document.getElementById('terms')
  };
  var errors = {
    firstName: document.getElementById('firstNameError'),
    commercialName: document.getElementById('commercialNameError'),
    phone: document.getElementById('phoneError'),
    email: document.getElementById('emailError'),
    password: document.getElementById('passwordError'),
    terms: document.getElementById('termsError')
  };

  captureAttribution();

  togglePassword.addEventListener('click', function () {
    var visible = passwordInput.type === 'text';
    passwordInput.type = visible ? 'password' : 'text';
    togglePassword.textContent = visible ? 'Mostrar' : 'Ocultar';
    togglePassword.setAttribute('aria-label', visible ? 'Mostrar clave' : 'Ocultar clave');
  });

  form.addEventListener('submit', function (event) {
    event.preventDefault();
    clearStatus();

    var payload = buildPayload();
    var validation = validate(payload);
    if (!validation.valid) {
      showValidation(validation.errors);
      focusFirstInvalid(validation.errors);
      return;
    }

    setSubmitting(true);
    registerBusiness(payload)
      .then(function (data) {
        return hydrateSession(data);
      })
      .then(function (sessionReady) {
        if (sessionReady) {
          showStatus('Cuenta creada. Abriendo FullPOS Cloud...', false);
          window.setTimeout(function () {
            window.location.assign('/');
          }, 650);
          return;
        }

        showStatus('Cuenta creada. Inicia sesión para entrar a tu panel.', false);
        submitButton.textContent = 'Ir a iniciar sesión';
        submitButton.disabled = false;
        submitButton.onclick = function () {
          window.location.assign('/login');
        };
      })
      .catch(function (error) {
        var mapped = mapRegisterError(error);
        if (mapped.field && errors[mapped.field]) {
          setFieldError(mapped.field, mapped.message);
          fields[mapped.field].focus();
        }
        showStatus(mapped.message, true);
        setSubmitting(false);
      });
  });

  function buildPayload() {
    var firstName = cleanText(fields.firstName.value);
    var commercialName = cleanText(fields.commercialName.value);
    var phone = cleanText(fields.phone.value);
    var email = cleanText(fields.email.value).toLowerCase();
    var password = fields.password.value || '';

    return {
      firstName: firstName,
      lastName: '',
      email: email,
      phone: phone,
      password: password,
      confirmPassword: password,
      commercialName: commercialName,
      legalName: commercialName,
      businessPhone: phone,
      businessEmail: email,
      country: 'República Dominicana',
      businessType: 'Comercio',
      currency: 'DOP',
      timezone: 'America/Santo_Domingo',
      locale: 'es-DO'
    };
  }

  function validate(payload) {
    var result = { valid: true, errors: {} };
    var emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    var digits = payload.phone.replace(/\D/g, '');

    if (!payload.firstName) {
      result.errors.firstName = 'Escribe tu nombre.';
    }
    if (!payload.commercialName) {
      result.errors.commercialName = 'Escribe el nombre del negocio.';
    }
    if (digits.length < 10) {
      result.errors.phone = 'Escribe un WhatsApp válido.';
    }
    if (!emailPattern.test(payload.email)) {
      result.errors.email = 'Escribe un correo válido.';
    }
    if (payload.password.length < 8) {
      result.errors.password = 'La clave debe tener al menos 8 caracteres.';
    }
    if (!fields.terms.checked) {
      result.errors.terms = 'Debes aceptar los términos para continuar.';
    }

    result.valid = Object.keys(result.errors).length === 0;
    return result;
  }

  function registerBusiness(payload) {
    return fetch('/api/auth/register-business', {
      method: 'POST',
      credentials: 'same-origin',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(payload)
    }).then(function (response) {
      return response.text().then(function (text) {
        var data = parseJson(text);
        if (!response.ok) {
          var message = extractMessage(data) || 'No pudimos crear la cuenta. Revisa los datos e intenta de nuevo.';
          var error = new Error(message);
          error.status = response.status;
          throw error;
        }
        return data || {};
      });
    });
  }

  function hydrateSession(data) {
    var accessToken = cleanText(data.accessToken || data.token || '');
    var refreshToken = cleanText(data.refreshToken || '');
    if (!accessToken) {
      return Promise.resolve(false);
    }

    return fetch('/api/users/me', {
      method: 'GET',
      credentials: 'same-origin',
      headers: {
        Accept: 'application/json',
        Authorization: 'Bearer ' + accessToken
      }
    })
      .then(function (response) {
        if (!response.ok) return data.user || null;
        return response.json().catch(function () {
          return data.user || null;
        });
      })
      .catch(function () {
        return data.user || null;
      })
      .then(function (user) {
        var normalizedUser = normalizeUser(user, accessToken);
        saveFlutterString('accessToken', accessToken);
        if (refreshToken) {
          saveFlutterString('refreshToken', refreshToken);
        }
        if (normalizedUser) {
          saveFlutterString('authUserSnapshot', JSON.stringify(normalizedUser));
        }
        return true;
      })
      .catch(function () {
        return false;
      });
  }

  function normalizeUser(user, accessToken) {
    if (!user || typeof user !== 'object') {
      return null;
    }
    var copy = {};
    Object.keys(user).forEach(function (key) {
      copy[key] = user[key];
    });

    if (!copy.companyId) {
      var identity = parseJwt(accessToken);
      if (identity && identity.companyId) {
        copy.companyId = identity.companyId;
      }
    }

    return copy;
  }

  function saveFlutterString(key, value) {
    window.localStorage.setItem('flutter.' + key, JSON.stringify(String(value)));
  }

  function parseJwt(token) {
    var parts = String(token || '').split('.');
    if (parts.length < 2) return null;
    try {
      var base64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
      var padded = base64 + '==='.slice((base64.length + 3) % 4);
      return JSON.parse(window.atob(padded));
    } catch (_) {
      return null;
    }
  }

  function mapRegisterError(error) {
    var message = cleanText(error && error.message);
    var lower = message.toLowerCase();
    if ((error && error.status === 409) || lower.indexOf('ya existe') !== -1 || (lower.indexOf('correo') !== -1 && lower.indexOf('existe') !== -1)) {
      return { field: 'email', message: 'Ya existe una cuenta con este correo.' };
    }
    if (lower.indexOf('password') !== -1 || lower.indexOf('clave') !== -1 || lower.indexOf('contraseña') !== -1) {
      return { field: 'password', message: 'Revisa la clave. Debe tener al menos 8 caracteres.' };
    }
    if (lower.indexOf('phone') !== -1 || lower.indexOf('tel') !== -1 || lower.indexOf('whatsapp') !== -1) {
      return { field: 'phone', message: 'Revisa el WhatsApp e intenta de nuevo.' };
    }
    if (lower.indexOf('email') !== -1 || lower.indexOf('correo') !== -1) {
      return { field: 'email', message: 'Revisa el correo e intenta de nuevo.' };
    }
    return { field: null, message: message || 'No pudimos crear la cuenta. Intenta de nuevo en unos minutos.' };
  }

  function captureAttribution() {
    var allowed = ['utm_source', 'utm_medium', 'utm_campaign', 'utm_content', 'utm_term', 'fbclid', 'gclid', 'ref'];
    var params = new URLSearchParams(window.location.search);
    var data = {};

    allowed.forEach(function (key) {
      var value = sanitizeAttribution(params.get(key));
      if (value) data[key] = value;
    });

    if (Object.keys(data).length > 0) {
      data.path = window.location.pathname;
      data.capturedAt = new Date().toISOString();
      window.sessionStorage.setItem('fullpos_registro_attribution', JSON.stringify(data));
    }
  }

  function sanitizeAttribution(value) {
    return cleanText(value || '')
      .replace(/[^\w .:-]/g, '')
      .slice(0, 120);
  }

  function showValidation(validationErrors) {
    Object.keys(validationErrors).forEach(function (field) {
      setFieldError(field, validationErrors[field]);
    });
  }

  function focusFirstInvalid(validationErrors) {
    var first = Object.keys(validationErrors)[0];
    if (first && fields[first]) {
      fields[first].focus();
    }
  }

  function setFieldError(field, message) {
    if (errors[field]) {
      errors[field].textContent = message;
    }
    if (fields[field] && fields[field].setAttribute) {
      fields[field].setAttribute('aria-invalid', 'true');
    }
  }

  function clearStatus() {
    alertBox.hidden = true;
    alertBox.className = 'alert';
    alertBox.textContent = '';
    Object.keys(errors).forEach(function (field) {
      errors[field].textContent = '';
      if (fields[field] && fields[field].removeAttribute) {
        fields[field].removeAttribute('aria-invalid');
      }
    });
  }

  function showStatus(message, isError) {
    alertBox.textContent = message;
    alertBox.hidden = false;
    alertBox.className = isError ? 'alert error' : 'alert';
  }

  function setSubmitting(isSubmitting) {
    submitButton.disabled = isSubmitting;
    submitButton.textContent = isSubmitting ? 'Creando cuenta...' : 'Crear cuenta';
  }

  function parseJson(text) {
    if (!text) return null;
    try {
      return JSON.parse(text);
    } catch (_) {
      return null;
    }
  }

  function extractMessage(data) {
    if (!data) return '';
    if (Array.isArray(data.message)) return data.message.join(' ');
    return cleanText(data.message || data.error || '');
  }

  function cleanText(value) {
    return String(value || '').replace(/\s+/g, ' ').trim();
  }
})();
