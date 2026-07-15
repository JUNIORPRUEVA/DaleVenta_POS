/// Función helper para obtener iniciales de un nombre
String getInitials(String name) {
  final initials = name
      .split(' ')
      .map((e) => e.isNotEmpty ? e[0].toUpperCase() : '')
      .join('')
      .replaceAll(' ', '');

  if (initials.isEmpty) return 'U';
  if (initials.length >= 2) return initials.substring(0, 2);
  return initials.padRight(2, initials[0]);
}
