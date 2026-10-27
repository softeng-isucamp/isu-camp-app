import 'dart:js_interop';
import 'package:web/web.dart' as web;

String? trustedCaptchaMessage(
    web.MessageEvent message, Uri apiUrl, web.Window? frameWindow) {
  if (message.origin != apiUrl.origin || frameWindow == null) return null;
  // Dart equality can inspect properties of a cross-origin WindowProxy.
  // JavaScript strict equality checks its identity without reading properties.
  if (!message.source.strictEquals(frameWindow).toDart ||
      !message.data.isA<JSString>()) return null;
  return (message.data as JSString).toDart;
}
