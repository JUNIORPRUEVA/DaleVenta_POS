import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/env.dart';
import '../auth/token_storage.dart';
import '../utils/is_flutter_test.dart';

/// A CircleAvatar replacement that loads [imageUrl] via [CachedNetworkImage]
/// and falls back to [child] on error or when the URL is empty.
/// This prevents the unhandled [SocketException] that a plain [CircleAvatar]
/// with [NetworkImage] throws when DNS resolution fails.
class UserAvatar extends StatelessWidget {
  static final TokenStorage _tokenStorage = TokenStorage();

  final String? imageUrl;
  final double radius;
  final Color? backgroundColor;
  final Widget? child;

  const UserAvatar({
    super.key,
    this.imageUrl,
    required this.radius,
    this.backgroundColor,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final url = _resolveAvatarUrl(imageUrl);

    if (url.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        child: child,
      );
    }

    // El endpoint que sirve las fotos de usuario (/media/object) exige
    // autenticación JWT (sistema multi-empresa). Sin el token la petición
    // devuelve 401 y el avatar cae a las iniciales, por eso adjuntamos el
    // Bearer token como cabecera HTTP (mismo patrón que ProductNetworkImage).
    return FutureBuilder<String?>(
      future: isFlutterTest
          ? Future<String?>.value()
          : _tokenStorage.getAccessToken(),
      builder: (context, snapshot) {
        final token = snapshot.data?.trim();
        final headers = token == null || token.isEmpty
            ? null
            : <String, String>{'Authorization': 'Bearer $token'};

        return CachedNetworkImage(
          key: ValueKey('$url:${token?.isNotEmpty ?? false}'),
          imageUrl: url,
          httpHeaders: headers,
          imageBuilder: (context, imageProvider) => CircleAvatar(
            radius: radius,
            backgroundColor: backgroundColor,
            backgroundImage: imageProvider,
          ),
          placeholder: (context, _) => CircleAvatar(
            radius: radius,
            backgroundColor: backgroundColor,
            child: child,
          ),
          errorWidget: (context, _, __) => CircleAvatar(
            radius: radius,
            backgroundColor: backgroundColor,
            child: child,
          ),
        );
      },
    );
  }

  String _resolveAvatarUrl(String? rawUrl) {
    final value = (rawUrl ?? '').trim();
    if (value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }

    final base = Env.apiBaseUrl.trim();
    if (base.isEmpty) return value;

    final normalizedBase = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    final normalizedPath = value.startsWith('/')
        ? value
        : (value.startsWith('uploads/') ? '/$value' : '/uploads/$value');
    return '$normalizedBase$normalizedPath';
  }
}
