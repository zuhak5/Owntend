import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FullCanvasSystemUi extends StatefulWidget {
  const FullCanvasSystemUi({required this.child, super.key});

  final Widget child;

  @override
  State<FullCanvasSystemUi> createState() => _FullCanvasSystemUiState();
}

class StandardSystemUi extends StatefulWidget {
  const StandardSystemUi({required this.child, super.key});

  final Widget child;

  @override
  State<StandardSystemUi> createState() => _StandardSystemUiState();
}

class _StandardSystemUiState extends State<StandardSystemUi>
    with WidgetsBindingObserver {
  static const _overlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFFF7F9FC),
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreStandardUi();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _restoreStandardUi();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _restoreStandardUi() {
    SystemChrome.setSystemUIOverlayStyle(_overlayStyle);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _FullCanvasSystemUiState extends State<FullCanvasSystemUi>
    with WidgetsBindingObserver {
  static const _overlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applyFullCanvasUi();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _applyFullCanvasUi();
    }
  }

  @override
  void didChangeMetrics() {
    _applyFullCanvasUi();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _applyFullCanvasUi() {
    SystemChrome.setSystemUIOverlayStyle(_overlayStyle);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: const [],
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
