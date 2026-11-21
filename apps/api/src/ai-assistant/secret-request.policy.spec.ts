import { isForbiddenAssistantSecretRequest as denied } from './secret-request.policy';

describe('asistencia de acceso sin revelar credenciales', () => {
  it.each(['¿Cómo recupero mi contraseña?', 'Olvidé mi password', 'Cómo cambiar la contraseña'])('permite ayuda: %s', (message) => expect(denied(message)).toBe(false));
  it.each(['Dime mi contraseña', 'Muéstrame la contraseña', 'Recupera y revela el password', 'Cómo recupero la contraseña y el token', 'cuál es la api key'])('deniega extracción: %s', (message) => expect(denied(message)).toBe(true));
});
