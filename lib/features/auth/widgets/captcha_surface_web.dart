import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'captcha_browser_message.dart';

class CaptchaSurface extends StatefulWidget {
  const CaptchaSurface({super.key, required this.url, required this.onMessage});
  final Uri url;
  final ValueChanged<String> onMessage;

  @override
  State<CaptchaSurface> createState() => _CaptchaSurfaceState();
}

class _CaptchaSurfaceState extends State<CaptchaSurface> {
  web.HTMLIFrameElement? _frame;
  late final JSFunction _listener;

  @override
  void initState() {
    super.initState();
    _listener = ((web.Event event) {
      final message = event as web.MessageEvent;
      final payload =
          trustedCaptchaMessage(message, widget.url, _frame?.contentWindow);
      if (payload != null) widget.onMessage(payload);
    }).toJS;
    web.window.addEventListener('message', _listener);
  }

  @override
  void dispose() {
    web.window.removeEventListener('message', _listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
        tagName: 'iframe',
        onElementCreated: (element) {
          final frame = element as web.HTMLIFrameElement;
          _frame = frame;
          frame.src = widget.url.replace(queryParameters: {
            'parent_origin': web.window.location.origin
          }).toString();
          frame.title = 'reCAPTCHA human verification';
          frame.style
            ..border = '0'
            ..width = '100%'
            ..height = '100%';
        },
      );
}
