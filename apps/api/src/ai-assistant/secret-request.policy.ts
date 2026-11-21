/** Permite orientación de recuperación; nunca lectura o extracción de credenciales. */
export function isForbiddenAssistantSecretRequest(message: string): boolean {
  const text = message.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
  if (/api\s*key|apikey|\btoken\b|\bsecret\w*\b|clave.*openai/.test(text)) return true;
  if (!/contrasena|password/.test(text)) return false;
  if (/(?:contrasena|password)\s*(?:es|era|:|=)\s*\S{3,}/.test(text)) return true;
  if (/muestr|revel|extrae|imprim|descifr|\blee\b|cual es|dime.*(?:contrasena|password)|ver (?:mi |la |su )?(?:contrasena|password)/.test(text)) return true;
  return !/recuper|restablec|reset|olvide|olvidado|cambiar|cambio|no recuerdo/.test(text);
}
