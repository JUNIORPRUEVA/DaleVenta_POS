import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/design_system/typography/app_typography.dart';
import '../../../clientes/cliente_model.dart';

/// Búsqueda anclada al campo: conserva el repositorio y la selección del editor.
class SalesClientSelector extends StatefulWidget {
  const SalesClientSelector({
    super.key,
    required this.name,
    required this.phone,
    required this.hasClient,
    required this.search,
    required this.onSelected,
    required this.onClear,
    required this.onCreate,
  });
  final String name;
  final String phone;
  final bool hasClient;
  final Future<List<ClienteModel>> Function(String) search;
  final ValueChanged<ClienteModel> onSelected;
  final VoidCallback onClear;
  final VoidCallback onCreate;
  static const createIconAsset = 'assets/image/cliente-crear.png';

  @override
  State<SalesClientSelector> createState() => _SalesClientSelectorState();
}

class _SalesClientSelectorState extends State<SalesClientSelector> {
  final _menu = MenuController();
  final _search = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  int _request = 0;
  bool _loading = false;
  String? _error;
  List<ClienteModel> _clients = const [];

  @override
  void initState() {
    super.initState();
    _restoreSelection();
    _focus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant SalesClientSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name ||
        oldWidget.hasClient != widget.hasClient) {
      if (!_menu.isOpen) _restoreSelection();
    }
  }

  void _restoreSelection() {
    _search.text = widget.hasClient ? widget.name : '';
  }

  void _onFocusChanged() {
    if (_focus.hasFocus && !_menu.isOpen && widget.hasClient) {
      _search.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _search.text.length,
      );
    }
    if (mounted) setState(() {});
  }

  void _open() {
    if (_menu.isOpen) return;
    _search.clear();
    _menu.open();
  }

  Future<void> _load(String query) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final clients = await widget.search(query.trim());
      if (!mounted || request != _request || !_menu.isOpen) return;
      setState(() {
        _clients = clients;
        _loading = false;
      });
    } catch (error, stack) {
      if (!mounted || request != _request || !_menu.isOpen) return;
      developer.log(
        'Error de búsqueda de clientes (${error.runtimeType})',
        name: 'SalesClientSelector',
        stackTrace: stack,
      );
      setState(() {
        _loading = false;
        _error = 'No se pudieron cargar los clientes.';
      });
    }
  }

  void _schedule(String query) {
    _debounce?.cancel();
    ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    _debounce = Timer(const Duration(milliseconds: 220), () => _load(query));
  }

  @override
  void dispose() {
    ++_request;
    _debounce?.cancel();
    _focus.removeListener(_onFocusChanged);
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => MenuAnchor(
      controller: _menu,
      childFocusNode: _focus,
      consumeOutsideTap: true,
      onOpen: () {
        unawaited(_load(_search.text));
      },
      onClose: () {
        _debounce?.cancel();
        ++_request;
        _focus.unfocus();
        _restoreSelection();
      },
      style: const MenuStyle(
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(side: BorderSide(color: AppColors.border)),
        ),
        backgroundColor: WidgetStatePropertyAll(AppColors.surface),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
      ),
      menuChildren: [
        SizedBox(
          width: constraints.maxWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      TextButton(
                        onPressed: () => _load(_search.text),
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              else if (_clients.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No se encontraron clientes'),
                )
              else
                SizedBox(
                  height: (_clients.length * 56.0).clamp(
                    0.0,
                    (MediaQuery.sizeOf(context).height * 0.35).clamp(
                      120.0,
                      280.0,
                    ),
                  ),
                  child: ListView.builder(
                    primary: false,
                    padding: EdgeInsets.zero,
                    itemCount: _clients.length,
                    itemBuilder: (context, index) {
                      final client = _clients[index];
                      return ListTile(
                        shape: const RoundedRectangleBorder(),
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        title: Text(
                          client.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: client.telefono.isEmpty
                            ? null
                            : Text(client.telefono, maxLines: 1),
                        onTap: () {
                          _menu.close();
                          widget.onSelected(client);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
      builder: (context, controller, _) => Container(
        height: 32,
        decoration: BoxDecoration(
          border: Border.all(
            color: _focus.hasFocus ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Tooltip(
                message: widget.hasClient
                    ? '${widget.name}${widget.phone.isEmpty ? '' : ' · ${widget.phone}'}'
                    : 'Buscar por nombre o teléfono',
                child: TextField(
                  controller: _search,
                  focusNode: _focus,
                  onTap: _open,
                  onChanged: (query) {
                    if (!_menu.isOpen) _menu.open();
                    _schedule(query);
                  },
                  onSubmitted: (_) {
                    _debounce?.cancel();
                    unawaited(_load(_search.text));
                  },
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(height: 1.2),
                  strutStyle: const StrutStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    height: 1.2,
                    forceStrutHeight: true,
                  ),
                  textAlignVertical: TextAlignVertical.center,
                  decoration: InputDecoration(
                    hintText: 'Seleccionar cliente',
                    hintStyle: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(height: 1.2, color: AppColors.textMuted),
                    isDense: true,
                    isCollapsed: true,
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    hoverColor: Colors.transparent,
                  ),
                ),
              ),
            ),
            if (widget.hasClient)
              SizedBox.square(
                dimension: 26,
                child: IconButton(
                  tooltip: 'Quitar cliente',
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  onPressed: () {
                    controller.close();
                    _focus.unfocus();
                    widget.onClear();
                  },
                  icon: const Icon(Icons.close_rounded),
                  style: IconButton.styleFrom(
                    shape: const RoundedRectangleBorder(),
                  ),
                ),
              ),
            SizedBox.square(
              dimension: 24,
              child: IconButton(
                tooltip: 'Mostrar clientes',
                padding: EdgeInsets.zero,
                iconSize: 16,
                onPressed: () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    _focus.requestFocus();
                    _open();
                  }
                },
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                style: IconButton.styleFrom(
                  shape: const RoundedRectangleBorder(),
                ),
              ),
            ),
            Container(
              width: 32,
              height: 30,
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: AppColors.border)),
              ),
              child: IconButton(
                tooltip: 'Crear cliente',
                padding: EdgeInsets.zero,
                onPressed: () {
                  controller.close();
                  _focus.unfocus();
                  widget.onCreate();
                },
                icon: const ImageIcon(
                  AssetImage(SalesClientSelector.createIconAsset),
                  size: 20,
                ),
                style: IconButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  shape: const RoundedRectangleBorder(),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
