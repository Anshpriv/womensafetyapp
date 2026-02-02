import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'home_screen.dart';

class IntroVideoScreen extends StatefulWidget {
  const IntroVideoScreen({super.key});

  @override
  State<IntroVideoScreen> createState() => _IntroVideoScreenState();
}

class _IntroVideoScreenState extends State<IntroVideoScreen> {
  late VideoPlayerController _controller;
  Timer? _navigationTimer;
  late Widget _nextScreen;

  @override
  void initState() {
    super.initState();
    _determineNextScreen();
    _initializeVideo();
  }

  void _determineNextScreen() {
    final auth = context.read<AuthService>();
    
    if (auth.isLoggedIn) {
      _nextScreen = const HomeScreen();
    } else {
      _nextScreen = const LoginScreen();
    }
  }

  void _initializeVideo() async {
    _controller = VideoPlayerController.asset('assets/intro.mp4');
    
    try {
      await _controller.initialize();
      
      if (!mounted) return;
      
      setState(() {});
      
      _controller.setVolume(1.0);
      _controller.setLooping(false);
      
      await _controller.play();
      
      // ✅ Navigate after 30 seconds
      _navigationTimer = Timer(const Duration(seconds: 30), () {
        if (mounted) {
          _navigateToNextScreen();
        }
      });
      
    } catch (e) {
      debugPrint("Video initialization error: $e");
      _navigateToNextScreen();
    }
  }

  void _navigateToNextScreen() {
    if (!mounted) return;
    
    _navigationTimer?.cancel();
    _controller.pause();
    
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 1000),
        pageBuilder: (context, animation, secondaryAnimation) {
          return _nextScreen;
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: _controller.value.isInitialized
            ? SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller.value.size.width,
                    height: _controller.value.size.height,
                    child: VideoPlayer(_controller),
                  ),
                ),
              )
            : const CircularProgressIndicator(
                color: Colors.white,
              ),
      ),
    );
  }
}
