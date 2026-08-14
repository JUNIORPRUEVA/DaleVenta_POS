import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../auth/token_storage.dart';
import '../utils/is_flutter_test.dart';
import '../utils/media_url.dart';

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
    final localImage = _tryResolveLocalImage(imageUrl);
    if (localImage != null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        backgroundImage: localImage,
      );
    }

    final url = _resolveAvatarUrl(imageUrl);

    if (url.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        child: child,
      );
    }

    // Las fotos de perfil se reescriben a la ruta pública /uploads (ver
    // media_url.dart) para que carguen en cualquier plataforma sin JWT.
    // Se adjunta el Bearer token igualmente como respaldo por si la URL
    // aún apunta a /media/object (protegida), igual que ProductNetworkImage.
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

  String _resolveAvatarUrl(String? rawUrl) => resolvePublicMediaUrl(rawUrl);

  ImageProvider? _tryResolveLocalImage(String? rawUrl) {
    final value = (rawUrl ?? '').trim();
    if (!value.startsWith('data:image/')) return null;
    final separator = value.indexOf(',');
    if (separator < 0) return null;
    try {
      return MemoryImage(base64Decode(value.substring(separator + 1)));
    } catch (_) {
      return null;
    }
  }
}
