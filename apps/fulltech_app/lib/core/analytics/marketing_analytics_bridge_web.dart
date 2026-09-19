import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('fullposMetaPixelTrack')
external JSBoolean _fullposMetaPixelTrack(
  JSString pixelId,
  JSString eventName,
  JSObject parameters,
  JSBoolean debugEnabled,
);

bool trackMetaPixelEvent({
  required String pixelId,
  required String eventName,
  required Map<String, String> parameters,
  required bool debugEnabled,
}) {
  try {
    final jsParameters = JSObject();
    for (final entry in parameters.entries) {
      jsParameters.setProperty(entry.key.toJS, entry.value.toJS);
    }
    return _fullposMetaPixelTrack(
      pixelId.toJS,
      eventName.toJS,
      jsParameters,
      debugEnabled.toJS,
    ).toDart;
  } catch (_) {
    return false;
  }
}
