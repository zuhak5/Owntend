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
  SystemUiOverlayStyle _computeOverlayStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: isDark
          ? scheme.surface
          : const Color(0xFFF7F9FC),
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreStandardUi());
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
    if (!mounted) return;
    SystemChrome.setSystemUIOverlayStyle(_computeOverlayStyle(context));
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _computeOverlayStyle(context),
      child: widget.child,
    );
  }
}

class _FullCanvasSystemUiState extends State<FullCanvasSystemUi>
    with WidgetsBindingObserver {
  SystemUiOverlayStyle _computeOverlayStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyFullCanvasUi());
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
    if (!mounted) return;
    SystemChrome.setSystemUIOverlayStyle(_computeOverlayStyle(context));
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: const [],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _computeOverlayStyle(context),
      child: widget.child,
    );
  }
}
