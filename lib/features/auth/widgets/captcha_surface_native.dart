import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class CaptchaSurface extends StatefulWidget {
  const CaptchaSurface({super.key, required this.url, required this.onMessage});
  final Uri url;
  final ValueChanged<String> onMessage;

  @override
  State<CaptchaSurface> createState() => _CaptchaSurfaceState();
}

class _CaptchaSurfaceState extends State<CaptchaSurface> {
  WebViewController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (WebViewPlatform.instance == null) return;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('CaptchaBridge',
          onMessageReceived: (message) => widget.onMessage(message.message))
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) =>
            !request.isMainFrame || request.url == widget.url.toString()
                ? NavigationDecision.navigate
                : NavigationDecision.prevent,
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && mounted)
            setState(() =>
                _error = 'Verification could not load. Close and try again.');
        },
      ))
      ..loadRequest(widget.url);
  }

  @override
  Widget build(BuildContext context) => _error != null
      ? Center(child: Text(_error!))
      : _controller == null
          ? const Center(
              child: Text(
                  'Human verification is available on Android, iOS, macOS, and web.'))
          : WebViewWidget(controller: _controller!);
}
