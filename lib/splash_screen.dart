import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:video_player/video_player.dart';

import 'login_screen.dart';
import 'org_selection_screen.dart';

/// Tela de abertura (splash) que reproduz o video da marca uma unica vez e,
/// ao terminar, encaminha o usuario para a tela correta:
///   - Com sessao salva  -> OrgSelectionScreen
///   - Sem sessao        -> LoginScreen
///
/// A navegacao acontece quando o video termina OU quando um timeout de
/// seguranca expira (evita a app ficar presa caso o video falhe ao carregar).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _maxSplashDuration = Duration(seconds: 8);

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  VideoPlayerController? _controller;
  Timer? _safetyTimer;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
    // Rede de seguranca: se o video nao terminar (ou falhar), segue mesmo assim.
    _safetyTimer = Timer(_maxSplashDuration, _goNext);
  }

  Future<void> _initVideo() async {
    final controller =
        VideoPlayerController.asset('assets/splashscreen.mp4');
    _controller = controller;
    controller.addListener(_onVideoTick);

    try {
      await controller.initialize();
      if (!mounted) return;
      await controller.setVolume(1.0);
      await controller.play();
      setState(() {}); // mostra o primeiro frame
    } catch (e) {
      debugPrint('Erro ao iniciar video da splash: $e');
      _goNext(); // se nao carregou, nao prende o usuario
    }
  }

  void _onVideoTick() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final duration = controller.value.duration;
    final position = controller.value.position;
    final reachedEnd = duration > Duration.zero &&
        position >= duration - const Duration(milliseconds: 120);

    if ((reachedEnd || controller.value.hasError) && !controller.value.isPlaying) {
      _goNext();
    }
  }

  Future<void> _goNext() async {
    if (_navigated || !mounted) return;
    _navigated = true;
    _safetyTimer?.cancel();

    final token = await _storage.read(key: 'session_token');
    final isLoggedIn = token != null && token.isNotEmpty;

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            isLoggedIn ? const OrgSelectionScreen() : const LoginScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _safetyTimer?.cancel();
    _controller?.removeListener(_onVideoTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final isReady = controller != null && controller.value.isInitialized;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: Center(
        child: isReady
            ? SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: controller.value.size.width,
                    height: controller.value.size.height,
                    child: VideoPlayer(controller),
                  ),
                ),
              )
            : const CircularProgressIndicator(color: Colors.blue),
      ),
    );
  }
}
