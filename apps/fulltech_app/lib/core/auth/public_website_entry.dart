import 'package:flutter/material.dart';
import 'public_website_navigation.dart';

/// Web-only router boundary: load the public website through the server.
class PublicWebsiteEntry extends StatefulWidget {
  const PublicWebsiteEntry({super.key, this.navigate = returnToPublicWebsite});
  final VoidCallback navigate;

  @override
  State<PublicWebsiteEntry> createState() => _PublicWebsiteEntryState();
}

class _PublicWebsiteEntryState extends State<PublicWebsiteEntry> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.navigate();
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Abriendo FullPOS Cloud…')));
}
