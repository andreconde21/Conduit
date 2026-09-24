import 'dart:async';

import 'package:conduit/core/theme/app_palette.dart';
import 'package:conduit/features/live_preview/presentation/live_preview_controller.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

typedef WebViewControllerFactory = WebViewController Function();
typedef ExternalUrlOpener = Future<bool> Function(Uri url);

/// A WebView on the forwarded port with a path-only address bar, reload
/// and open-in-browser.
class LivePreviewView extends StatefulWidget {
  const LivePreviewView({
    required this.controller,
    required this.palette,
    required this.brightness,
    required this.onChangePort,
    this.createWebViewController = WebViewController.new,
    this.openExternal = _launchExternal,
    super.key,
  });

  final LivePreviewController controller;
  final AppPalette palette;
  final Brightness brightness;

  /// Asks for a new remote port and restarts the forward.
  final VoidCallback onChangePort;

  /// Injectable for tests; production builds the plugin controller.
  final WebViewControllerFactory createWebViewController;

  /// Opens a URL outside the app; the phone's browser can reach the
  /// loopback forward just like the WebView does.
  final ExternalUrlOpener openExternal;

  static Future<bool> _launchExternal(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);

  @override
  State<LivePreviewView> createState() => _LivePreviewViewState();
}

class _LivePreviewViewState extends State<LivePreviewView> {
  WebViewController? _webView;
  int? _loadedLocalPort;
  final _address = TextEditingController();
  final _addressFocus = FocusNode();
  bool _pageLoading = false;
  String? _pageError;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
    _address.text = widget.controller.path;
    _syncWebView();
  }

  @override
  void didUpdateWidget(covariant LivePreviewView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
      _syncWebView();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _address.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) {
      return;
    }
    if (!_addressFocus.hasFocus && _address.text != widget.controller.path) {
      _address.text = widget.controller.path;
    }
    _syncWebView();
    setState(() {});
  }

  /// Loads the forward's URL once it is ready, and again whenever the
  /// local port changes (a restart binds a new ephemeral port).
  void _syncWebView() {
    final url = widget.controller.url;
    if (url == null) {
      _loadedLocalPort = null;
      return;
    }
    if (_loadedLocalPort == url.port) {
      return;
    }
    _loadedLocalPort = url.port;
    _pageError = null;
    final webView = _webView ??= _createWebView();
    unawaited(webView.loadRequest(url));
  }

  WebViewController _createWebView() {
    final webView = widget.createWebViewController();
    unawaited(webView.setJavaScriptMode(JavaScriptMode.unrestricted));
    unawaited(
      webView.setBackgroundColor(
        widget.palette.canvasFor(widget.brightness),
      ),
    );
    unawaited(
      webView.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final target = Uri.tryParse(request.url);
            if (target == null || _isPreviewOrigin(target)) {
              return NavigationDecision.navigate;
            }
            // Links off the preview go to the phone's browser so the tab
            // stays on the forwarded app.
            unawaited(widget.openExternal(target));
            return NavigationDecision.prevent;
          },
          onPageStarted: (url) {
            _reportUrl(url);
            if (mounted) {
              setState(() {
                _pageLoading = true;
                _pageError = null;
              });
            }
          },
          onPageFinished: (url) {
            _reportUrl(url);
            if (mounted) {
              setState(() => _pageLoading = false);
            }
          },
          onUrlChange: (change) {
            final url = change.url;
            if (url != null) {
              _reportUrl(url);
            }
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) {
              if (mounted) {
                setState(() {
                  _pageLoading = false;
                  _pageError = error.description.isEmpty
                      ? 'The page failed to load.'
                      : error.description;
                });
              }
            }
          },
        ),
      ),
    );
    return webView;
  }

  bool _isPreviewOrigin(Uri target) {
    final localPort = widget.controller.localPort;
    return localPort != null &&
        target.scheme == 'http' &&
        (target.host == '127.0.0.1' || target.host == 'localhost') &&
        target.port == localPort;
  }

  void _reportUrl(String raw) {
    final parsed = Uri.tryParse(raw);
    if (parsed == null || !_isPreviewOrigin(parsed)) {
      return;
    }
    widget.controller.setPath(
      parsed.hasQuery ? '${parsed.path}?${parsed.query}' : parsed.path,
    );
  }

  void _navigateToAddress(String value) {
    final controller = widget.controller;
    controller.setPath(value);
    _address.text = controller.path;
    _addressFocus.unfocus();
    final url = controller.url;
    if (url != null) {
      controller.clearConnectionError();
      unawaited(_webView?.loadRequest(url));
    }
  }

  void _reload() {
    widget.controller.clearConnectionError();
    setState(() => _pageError = null);
    final webView = _webView;
    if (webView != null && widget.controller.url != null) {
      unawaited(webView.reload());
    }
  }

  Future<void> _openInBrowser() async {
    final url = widget.controller.url;
    if (url == null) {
      return;
    }
    final opened = await widget.openExternal(url);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No browser could open the preview.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final palette = widget.palette;
    final brightness = widget.brightness;
    final muted = palette.mutedForegroundFor(brightness);
    final ready = controller.isReady;
    final connectionError = controller.connectionError;
    return Container(
      color: palette.canvasFor(brightness),
      child: Column(
        children: [
          Container(
            height: 44,
            color: palette.canvasFor(brightness),
            padding: const EdgeInsets.only(left: 8),
            child: Row(
              children: [
                Tooltip(
                  message: 'Change port',
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: muted,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    onPressed: widget.onChangePort,
                    icon: const Icon(Icons.lan_outlined, size: 16),
                    label: Text(
                      ':${controller.remotePort ?? '—'}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _address,
                    focusNode: _addressFocus,
                    enabled: ready,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    onSubmitted: _navigateToAddress,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      color: palette.foregroundFor(brightness),
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '/',
                      filled: true,
                      fillColor: palette.panelFor(brightness),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Reload',
                  iconSize: 19,
                  color: muted,
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: ready ? _reload : null,
                ),
                IconButton(
                  tooltip: 'Open in browser',
                  iconSize: 19,
                  color: muted,
                  icon: const Icon(Icons.open_in_browser_rounded),
                  onPressed: ready ? _openInBrowser : null,
                ),
              ],
            ),
          ),
          if (_pageLoading && ready)
            LinearProgressIndicator(
              minHeight: 2,
              color: palette.accent,
              backgroundColor: Colors.transparent,
            ),
          if (connectionError != null && ready)
            MaterialBanner(
              backgroundColor: palette.warning.withValues(alpha: 0.12),
              leading: Icon(Icons.warning_amber_rounded, color: palette.warning),
              content: Text(
                connectionError,
                style: TextStyle(
                  color: palette.foregroundFor(brightness),
                  fontSize: 12.5,
                ),
              ),
              actions: [
                TextButton(onPressed: _reload, child: const Text('Reload')),
                TextButton(
                  onPressed: controller.clearConnectionError,
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          Expanded(child: _body(controller)),
        ],
      ),
    );
  }

  Widget _body(LivePreviewController controller) {
    final palette = widget.palette;
    final brightness = widget.brightness;
    switch (controller.phase) {
      case LivePreviewPhase.idle:
      case LivePreviewPhase.connecting:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: palette.accent,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Forwarding port ${controller.remotePort ?? ''}…',
                style: TextStyle(
                  color: palette.mutedForegroundFor(brightness),
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        );
      case LivePreviewPhase.failed:
        return _Notice(
          icon: Icons.error_outline_rounded,
          title: 'Could not open the preview',
          message: controller.error ?? '',
          palette: palette,
          brightness: brightness,
          actions: [
            TextButton(
              onPressed: widget.onChangePort,
              child: const Text('Change port'),
            ),
            FilledButton(
              onPressed: controller.restart,
              child: const Text('Retry'),
            ),
          ],
        );
      case LivePreviewPhase.closed:
        return _Notice(
          icon: Icons.link_off_rounded,
          title: 'Preview closed',
          message: controller.error ?? '',
          palette: palette,
          brightness: brightness,
          actions: [
            FilledButton(
              onPressed: controller.restart,
              child: const Text('Reconnect'),
            ),
          ],
        );
      case LivePreviewPhase.ready:
        final webView = _webView;
        if (webView == null) {
          return const SizedBox.shrink();
        }
        final pageError = _pageError;
        if (pageError != null) {
          return _Notice(
            icon: Icons.web_asset_off_rounded,
            title: 'The page did not load',
            message: pageError,
            palette: palette,
            brightness: brightness,
            actions: [
              FilledButton(onPressed: _reload, child: const Text('Reload')),
            ],
          );
        }
        return WebViewWidget(controller: webView);
    }
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.message,
    required this.palette,
    required this.brightness,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final String message;
  final AppPalette palette;
  final Brightness brightness;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final muted = palette.mutedForegroundFor(brightness);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: muted),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.foregroundFor(brightness),
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 12.5),
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}
