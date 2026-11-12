import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/activation_models.dart';

/// Un paso concreto dentro de un camino de la guía.
@immutable
class ActivationGuideStep {
  const ActivationGuideStep(this.text, {this.hint, this.emphasis = false});

  final String text;

  /// Aclaración corta bajo el paso (para qué sirve el dato, dónde está).
  final String? hint;

  /// Paso crítico: se dibuja resaltado para que no se pase por alto.
  final bool emphasis;
}

/// Una forma de completar la tarea. La guía muestra un selector de caminos
/// cuando el mismo resultado se consigue desde dos pantallas distintas.
@immutable
class ActivationGuidePath {
  const ActivationGuidePath({
    required this.label,
    required this.steps,
    this.destination,
  });

  /// Etiqueta corta del selector (una o dos palabras).
  final String label;
  final List<ActivationGuideStep> steps;

  /// Pantalla donde se ejecuta este camino. Si es `null` se usa la de la tarea.
  final String? destination;
}

/// Etiqueta del botón de apertura, con el nombre real de la pantalla.
String? activationOpenLabelFor(String? destination) {
  switch (destination) {
    case 'catalog':
      return 'Abrir Inventario';
    case 'company':
      return 'Abrir Empresa';
    case 'ecf':
      return 'Abrir facturación electrónica';
    case 'pos':
      return 'Abrir Facturación';
    default:
      return null;
  }
}

/// Dato que el formulario pide, con su explicación en lenguaje llano.
@immutable
class ActivationGuideField {
  const ActivationGuideField({
    required this.name,
    required this.help,
    this.required = false,
  });

  final String name;
  final String help;
  final bool required;
}

/// Contenido completo de la guía lateral.
@immutable
class ActivationGuide {
  const ActivationGuide({
    required this.eyebrow,
    required this.title,
    required this.summary,
    required this.paths,
    this.fields = const <ActivationGuideField>[],
    this.footer,
    this.notice,
  });

  final String eyebrow;
  final String title;
  final String summary;
  final List<ActivationGuidePath> paths;
  final List<ActivationGuideField> fields;
  final String? footer;

  /// Aviso imprescindible que se muestra arriba, antes de los pasos.
  final String? notice;
}

/// Guía paso a paso de una tarea del onboarding.
///
/// Cada tarea puede tener su propio recorrido; si no lo tiene, se construye una
/// guía genérica con el título y la descripción reales de la tarea, de modo que
/// «Ver cómo» siempre explica algo útil en cualquier proceso del onboarding.
ActivationGuide activationGuideFor(String taskKey, ActivationTask? task) {
  switch (taskKey) {
    case 'products':
      return const ActivationGuide(
        eyebrow: 'Guía',
        title: 'Crea tu primer producto',
        summary: 'Dos caminos con el mismo formulario. Elige el que prefieras.',
        paths: [
          ActivationGuidePath(
            label: 'Rápido',
            // Este camino se ejecuta en la pantalla de Facturación; el camino
            // de Inventario usa el destino propio de la tarea (`catalog`).
            destination: 'pos',
            steps: [
              ActivationGuideStep(
                'Pulsa «Nuevo producto».',
                hint: 'En Facturación, arriba del catálogo.',
              ),
              ActivationGuideStep(
                'Escribe el nombre.',
                hint: 'Es como lo vas a buscar al vender.',
              ),
              ActivationGuideStep(
                'Pon el precio y el costo.',
                hint: 'Precio: lo que cobras. Costo: lo que te cuesta.',
              ),
              ActivationGuideStep(
                'Indica el stock disponible.',
                hint: 'Cuántas unidades tienes hoy.',
              ),
              ActivationGuideStep(
                'Elige la categoría.',
                hint:
                    'Si es la primera, escríbela y pulsa «Crear». Si ya existe, toca un chip de la lista.',
              ),
              ActivationGuideStep(
                'Añade una imagen.',
                hint: 'Opcional, pero ayuda a reconocerlo.',
              ),
              ActivationGuideStep('Pulsa «Crear producto».'),
            ],
          ),
          ActivationGuidePath(
            label: 'Inventario',
            steps: [
              ActivationGuideStep(
                'Abre el menú lateral.',
                hint: 'El botón de tres líneas, arriba a la izquierda.',
              ),
              ActivationGuideStep('Entra en «Inventario» → «Productos».'),
              ActivationGuideStep(
                'Pulsa «Nuevo producto».',
                hint: 'Es el mismo formulario del camino Rápido.',
              ),
              ActivationGuideStep('Completa nombre, precio, costo y stock.'),
              ActivationGuideStep(
                'Elige la categoría.',
                hint:
                    'Campo «Categoría»: escribe una nueva y pulsa «Crear», o elige una de la lista.',
              ),
              ActivationGuideStep(
                'Añade una imagen si quieres.',
                hint: 'Aquí es opcional.',
              ),
              ActivationGuideStep('Pulsa «Crear producto».'),
            ],
          ),
        ],
        fields: [
          ActivationGuideField(
            name: 'Nombre',
            help: 'Cómo lo buscas y cómo sale en la factura',
            required: true,
          ),
          ActivationGuideField(
            name: 'Precio',
            help: 'Lo que cobras al cliente',
            required: true,
          ),
          ActivationGuideField(
            name: 'Costo',
            help: 'Lo que te cuesta a ti',
            required: true,
          ),
          ActivationGuideField(
            name: 'Categoría',
            help: 'Escríbela y pulsa «Crear», o elige una existente',
            required: true,
          ),
          ActivationGuideField(
            name: 'Stock disponible',
            help: 'Unidades que tienes hoy',
            required: true,
          ),
          ActivationGuideField(
            name: 'Imagen',
            help: 'Opcional, para reconocerlo en el catálogo',
          ),
          ActivationGuideField(
            name: 'Código',
            help: 'Código de barra o referencia interna',
          ),
        ],
        footer: 'La categoría es obligatoria: créala si es tu primer producto.',
      );
    case 'business':
      return const ActivationGuide(
        eyebrow: 'Guía',
        title: 'Completa los datos de tu empresa',
        summary:
            'Tus datos, tu logo y las funciones que necesitas para operar.',
        paths: [
          ActivationGuidePath(
            label: 'Paso a paso',
            steps: [
              ActivationGuideStep(
                'Abre «Empresa» desde el menú lateral.',
                hint: 'Está dentro de Configuración.',
              ),
              ActivationGuideStep(
                'Completa la información del negocio.',
                hint:
                    'Nombre comercial, RNC, teléfono y dirección: es lo que sale impreso en tus comprobantes.',
              ),
              ActivationGuideStep(
                'Sube tu logo.',
                hint:
                    'Pulsa «Subir logo»: aparecerá en tus facturas, tickets y recibos.',
                emphasis: true,
              ),
              ActivationGuideStep(
                'Activa las funciones que usa tu negocio.',
                hint:
                    'Impuestos, inventario, unidades de medida, almacenes o listas de precios. Cada interruptor explica lo que hace.',
              ),
              ActivationGuideStep(
                'Pulsa «Guardar empresa».',
                hint: 'Abajo a la derecha de la pantalla.',
              ),
            ],
          ),
        ],
        fields: [
          ActivationGuideField(
            name: 'Nombre comercial',
            help: 'Cómo apareces en la factura y el ticket',
            required: true,
          ),
          ActivationGuideField(
            name: 'RNC',
            help: 'Tu identificación fiscal, si la tienes',
          ),
          ActivationGuideField(
            name: 'Teléfono y dirección',
            help: 'Los datos de contacto del comprobante',
          ),
          ActivationGuideField(
            name: 'Logo',
            help: 'Va impreso en tus documentos',
          ),
          ActivationGuideField(
            name: 'Funciones',
            help: 'Impuestos, inventario, almacenes, listas de precios…',
          ),
        ],
        footer:
            'Lo que guardes aquí es lo que verá tu cliente en cada documento.',
      );
    case 'taxes':
      return const ActivationGuide(
        eyebrow: 'Guía',
        title: 'Configura los impuestos',
        summary: 'Decide si cobras ITBIS y cómo lo aplicas.',
        paths: [
          ActivationGuidePath(
            label: 'Paso a paso',
            steps: [
              ActivationGuideStep(
                'Abre el menú lateral y entra en «Empresa».',
                hint: 'Está dentro de Configuración.',
              ),
              ActivationGuideStep(
                'Activa «Utilizar impuestos».',
                hint:
                    'Está en el panel «Impuestos y e-CF», bajando por la página.',
              ),
              ActivationGuideStep(
                'Elige cómo tratas el ITBIS.',
                hint:
                    '«Precio incluye impuesto» o «Precio + impuesto», según trabajes.',
              ),
              ActivationGuideStep(
                'Pulsa «Guardar empresa».',
                hint: 'Abajo a la derecha de la pantalla.',
              ),
            ],
          ),
        ],
        footer:
            'La tasa predeterminada es el 18 %. Las ventas anteriores no cambian.',
      );
    case 'tickets':
      return const ActivationGuide(
        eyebrow: 'Guía',
        title: 'Pon tu logo en los tickets',
        summary: 'El logo aparece en tickets y comprobantes.',
        paths: [
          ActivationGuidePath(
            label: 'Paso a paso',
            steps: [
              ActivationGuideStep(
                'Abre el menú lateral y entra en «Empresa».',
                hint: 'Está dentro de Configuración.',
              ),
              ActivationGuideStep(
                'En «Logo», pulsa «Subir logo».',
                hint: 'Elige una imagen cuadrada con fondo claro.',
              ),
              ActivationGuideStep(
                'Pulsa «Guardar empresa».',
                hint: 'Abajo a la derecha de la pantalla.',
              ),
            ],
          ),
        ],
        footer: 'Si más adelante quieres otro, el botón cambia a «Cambiar».',
      );
    case 'ecf':
      return const ActivationGuide(
        eyebrow: 'Guía',
        title: 'Activa tu facturación electrónica',
        summary: 'Empieza en Empresa. Después todo el proceso, paso a paso.',
        notice:
            'Primero se activa el módulo en Empresa. Hasta entonces, el menú no muestra «Facturación electrónica».',
        paths: [
          ActivationGuidePath(
            label: 'Paso a paso',
            // El proceso empieza en Empresa, no en el módulo.
            destination: 'company',
            steps: [
              ActivationGuideStep(
                'Entra a Empresa › Configuración y activa el módulo de facturación electrónica.',
                hint:
                    'En el panel «Impuestos y e-CF». Después pulsa «Guardar empresa».',
                emphasis: true,
              ),
              ActivationGuideStep(
                'Ve al menú lateral (drawer) y entra a «Facturación electrónica».',
                hint: 'Aparece cuando el módulo está activo.',
              ),
              ActivationGuideStep(
                'Llena los datos que se te solicitan.',
                hint:
                    'Datos fiscales, certificado digital y credenciales de la DGII.',
              ),
              ActivationGuideStep(
                'Entra al asistente y síguelo hasta el final.',
                hint:
                    'Hace la postulación por ti y te avisa si necesita que intervengas.',
              ),
              ActivationGuideStep(
                'Registra los comprobantes y las autorizaciones, y empieza a facturar.',
                hint: 'Autoriza tus NCF para emitir facturas electrónicas.',
              ),
            ],
          ),
        ],
        footer:
            'Es opcional: puedes seguir vendiendo con tickets mientras se aprueba.',
      );
    case 'firstSale':
      return const ActivationGuide(
        eyebrow: 'Guía',
        title: 'Haz tu primera venta',
        summary:
            'Primero abre la caja. Después cobra y entrega el comprobante.',
        notice:
            'Sin la caja abierta el sistema no deja cobrar. Ábrela antes de empezar.',
        paths: [
          ActivationGuidePath(
            label: 'Efectivo',
            steps: [
              ActivationGuideStep(
                'Comprueba que la caja esté abierta.',
                hint:
                    'Mira el botón «Turno» en el encabezado, arriba a la derecha. Si dice «Cerrado», pulsa ahí y elige la primera opción de la lista: «Abrir turno».',
                emphasis: true,
              ),
              ActivationGuideStep(
                'Busca el producto.',
                hint: 'Por nombre, código o categoría.',
              ),
              ActivationGuideStep(
                'Tócalo para agregarlo al carrito.',
                hint: 'Puedes cambiar cantidad y precio.',
              ),
              ActivationGuideStep(
                'Revisa el total.',
                hint: 'Está en el panel derecho.',
              ),
              ActivationGuideStep(
                'Pulsa «Cobrar» y elige Efectivo.',
                hint: 'Escribe con cuánto paga el cliente.',
              ),
              ActivationGuideStep(
                'Confirma la venta.',
                hint: 'Verás el cambio y el comprobante.',
              ),
            ],
          ),
          ActivationGuidePath(
            label: 'Otros medios',
            steps: [
              ActivationGuideStep(
                'Comprueba que la caja esté abierta.',
                hint:
                    'En el botón «Turno» del encabezado: si dice «Cerrado», ábrela con la primera opción, «Abrir turno».',
                emphasis: true,
              ),
              ActivationGuideStep(
                'Agrega los productos al carrito.',
                hint: 'Igual que en el camino Efectivo.',
              ),
              ActivationGuideStep(
                'En «Cobrar», elige el medio de pago.',
                hint: 'Transferencia, tarjeta, crédito o mixto.',
              ),
              ActivationGuideStep(
                'Confirma la venta.',
                hint: 'Si es crédito, queda como cuenta por cobrar.',
              ),
            ],
          ),
        ],
        footer: 'La tarea se completa cuando la venta queda registrada.',
      );
    default:
      final title = task?.title.trim();
      final description = task?.description.trim();
      final action = (task?.actionLabel ?? '').trim();
      return ActivationGuide(
        eyebrow: 'Guía',
        title: (title != null && title.isNotEmpty)
            ? title
            : 'Cómo completar este paso',
        summary: (description != null && description.isNotEmpty)
            ? description
            : 'Se completa desde la pantalla que abre el botón principal.',
        paths: [
          ActivationGuidePath(
            label: 'Paso a paso',
            steps: [
              ActivationGuideStep(
                (action.isNotEmpty)
                    ? 'Pulsa «$action».'
                    : 'Pulsa el botón principal de la tarea.',
                hint: 'Abre la pantalla donde se completa el paso.',
              ),
              const ActivationGuideStep(
                'Completa los datos que te pida.',
                hint: 'Solo se guarda lo que tú confirmes.',
              ),
              const ActivationGuideStep('Confirma y guarda.'),
            ],
          ),
        ],
        footer: 'Este paso se marca solo cuando los datos existen de verdad.',
      );
  }
}

/// Columna de ayuda que se abre pegada al borde izquierdo de la pantalla.
///
/// Sin fondo oscuro y sin desenfoque: la aplicación sigue visible e interactiva
/// detrás, porque los pasos se ejecutan mientras se leen. El contenido va
/// pegado a los extremos para aprovechar todo el ancho de la columna.
class ActivationGuideColumn extends StatefulWidget {
  const ActivationGuideColumn({
    super.key,
    required this.taskKey,
    required this.onClose,
    this.task,
    this.onOpenDestination,
    this.fallbackDestination,
  });

  final String taskKey;
  final ActivationTask? task;
  final VoidCallback onClose;

  /// Abre la pantalla real indicada. Si es `null` el botón no se muestra.
  final ValueChanged<String>? onOpenDestination;

  /// Destino de la tarea, usado cuando el camino no declara uno propio.
  final String? fallbackDestination;

  /// Al menos el 22 % del ancho, con un mínimo legible de 300 px y un máximo de
  /// 372 px para no comerse la pantalla en monitores grandes.
  static double widthFor(double screenWidth) =>
      (screenWidth * 0.22).clamp(300.0, 372.0);

  @override
  State<ActivationGuideColumn> createState() => _ActivationGuideColumnState();
}

class _ActivationGuideColumnState extends State<ActivationGuideColumn> {
  int _pathIndex = 0;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isMobile = size.width < 900;
    final width = isMobile
        ? size.width
        : ActivationGuideColumn.widthFor(size.width);
    final guide = activationGuideFor(widget.taskKey, widget.task);
    final index = _pathIndex.clamp(0, guide.paths.length - 1);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: width,
          height: double.infinity,
          child: Material(
            color: Colors.white,
            elevation: 12,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(
                  right: BorderSide(color: AppColors.secondaryBorder),
                ),
              ),
              child: _GuideBody(
                guide: guide,
                pathIndex: index,
                onSelectPath: (value) => setState(() => _pathIndex = value),
                onClose: widget.onClose,
                onOpenDestination: widget.onOpenDestination,
                fallbackDestination: widget.fallbackDestination,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GuideBody extends StatelessWidget {
  const _GuideBody({
    required this.guide,
    required this.pathIndex,
    required this.onSelectPath,
    required this.onClose,
    required this.onOpenDestination,
    required this.fallbackDestination,
  });

  final ActivationGuide guide;
  final int pathIndex;
  final ValueChanged<int> onSelectPath;
  final VoidCallback onClose;
  final ValueChanged<String>? onOpenDestination;
  final String? fallbackDestination;

  @override
  Widget build(BuildContext context) {
    final path = guide.paths[pathIndex];
    final target = path.destination ?? fallbackDestination;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Fondo opaco: el cuerpo hace scroll y no debe verse por debajo de la
        // cabecera.
        ColoredBox(
          color: Colors.white,
          child: _GuideHeader(guide: guide, onClose: onClose),
        ),
        const Divider(height: 1, color: AppColors.secondaryBorder),
        Expanded(
          // 16 px frente a los 20 px anteriores: el texto pega más al borde y
          // se aprovecha el ancho de la columna.
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            children: [
              if (guide.notice != null) ...[
                _NoticeBanner(text: guide.notice!),
                const SizedBox(height: 14),
              ],
              if (guide.paths.length > 1) ...[
                _PathSelector(
                  paths: guide.paths,
                  index: pathIndex,
                  onSelect: onSelectPath,
                ),
                const SizedBox(height: 16),
              ],
              for (var i = 0; i < path.steps.length; i++)
                _StepRow(index: i + 1, step: path.steps[i]),
              if (guide.fields.isNotEmpty) ...[
                const SizedBox(height: 6),
                const Divider(height: 1, color: AppColors.secondaryBorder),
                const SizedBox(height: 14),
                const _SectionTitle('Datos que te pide'),
                const SizedBox(height: 10),
                for (final field in guide.fields) _FieldRow(field: field),
              ],
              if (guide.footer != null) ...[
                const SizedBox(height: 16),
                _FooterNote(text: guide.footer!),
              ],
            ],
          ),
        ),
        // El botón de apertura vive FUERA del scroll: siempre visible, sin
        // tener que bajar hasta el final de la guía.
        if (onOpenDestination != null && target != null) ...[
          const Divider(height: 1, color: AppColors.secondaryBorder),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: SizedBox(
              height: 42,
              child: FilledButton.icon(
                onPressed: () => onOpenDestination!(target),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text(
                  activationOpenLabelFor(target) ?? 'Abrir la pantalla',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _GuideHeader extends StatelessWidget {
  const _GuideHeader({required this.guide, required this.onClose});

  final ActivationGuide guide;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Laterales al mínimo: el contenido ocupa todo el ancho útil.
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  guide.eyebrow.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: AppColors.textSecondary.withValues(alpha: 0.75),
                  ),
                ),
              ),
              _CloseButton(onTap: onClose),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            guide.title,
            style: const TextStyle(
              fontSize: 18,
              height: 1.2,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            guide.summary,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Cerrar la guía',
      // El foco inicial vive aquí (arriba) para que la lista abra siempre por el
      // principio y para que Escape llegue al atajo de teclado.
      child: Focus(
        autofocus: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: const SizedBox(
            width: 28,
            height: 28,
            child: Icon(
              Icons.close_rounded,
              size: 17,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Selector de camino: dos pastillas dentro de un carril gris. Sustituye a los
/// dos bloques apilados, que repetían información y ocupaban el doble.
class _PathSelector extends StatelessWidget {
  const _PathSelector({
    required this.paths,
    required this.index,
    required this.onSelect,
  });

  final List<ActivationGuidePath> paths;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          for (var i = 0; i < paths.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(i),
                child: Semantics(
                  button: true,
                  selected: i == index,
                  label: paths[i].label,
                  // La acción va en el nodo accesible para que el selector
                  // responda tanto al puntero como a lectores de pantalla.
                  onTap: () => onSelect(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOut,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == index ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                      boxShadow: i == index
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.07),
                                blurRadius: 3,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      paths[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: i == index
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.index, required this.step});

  final int index;
  final ActivationGuideStep step;

  @override
  Widget build(BuildContext context) {
    final critical = step.emphasis;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: critical
                ? const Color(0xFFF59E0B).withValues(alpha: 0.16)
                : AppColors.primary.withValues(alpha: 0.09),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$index',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: critical ? const Color(0xFFB45309) : AppColors.primary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.text,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  color: critical
                      ? const Color(0xFF7C2D12)
                      : AppColors.textPrimary,
                ),
              ),
              if (step.hint != null) ...[
                const SizedBox(height: 2),
                Text(
                  step.hint!,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: critical
                        ? const Color(0xFF92400E)
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );

    if (!critical) {
      return Padding(padding: const EdgeInsets.only(bottom: 14), child: row);
    }
    // Paso imprescindible: fondo cálido y borde para que no se pase por alto.
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFFDBA74)),
      ),
      child: row,
    );
  }
}

/// Aviso imprescindible de la guía (borde y fondo cálidos).
class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFFDBA74)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.priority_high_rounded,
            size: 15,
            color: Color(0xFFB45309),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w700,
                color: Color(0xFF7C2D12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila de dato: nombre en negrita, obligatoriedad al lado y la ayuda debajo.
/// Sin caja ni iconos: una viñeta y dos líneas, nada más.
class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.field});

  final ActivationGuideField field;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: field.required
                    ? AppColors.primary
                    : AppColors.textSecondary.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
                children: [
                  TextSpan(
                    text: field.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (field.required)
                    const TextSpan(
                      text: ' · obligatorio',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  TextSpan(text: '\n${field.help}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterNote extends StatelessWidget {
  const _FooterNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 13,
          color: AppColors.textSecondary.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
