import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import 'auth_helpers.dart';
import 'auth_login_screen.dart';
import 'loo_svg_icon.dart';

/// Onboarding: value → location → sign up; log in is a pushed screen.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _animateToPage(int page) async {
    await _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  void _openLoginFromIntro() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (ctx) => AuthLoginScreen(
          onWantCreateAccount: () => _animateToPage(2),
        ),
      ),
    );
  }

  void _openLoginFromSignUp() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (ctx) => const AuthLoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const BouncingScrollPhysics(),
                children: [
                  _OnboardingValuePage(
                    onLetsGo: () => _animateToPage(1),
                    onLogin: _openLoginFromIntro,
                  ),
                  _OnboardingLocationPage(
                    onGranted: () => _animateToPage(2),
                  ),
                  _OnboardingSignUpPage(
                    onOpenLogin: _openLoginFromSignUp,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 20, top: 8),
              child: SmoothPageIndicator(
                controller: _pageController,
                count: 3,
                effect: const ExpandingDotsEffect(
                  activeDotColor: Color(0xFFFFC107),
                  dotColor: Colors.white24,
                  dotHeight: 8,
                  dotWidth: 8,
                  spacing: 6,
                  expansionFactor: 3.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingValuePage extends StatelessWidget {
  const _OnboardingValuePage({
    required this.onLetsGo,
    required this.onLogin,
  });

  final VoidCallback onLetsGo;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),
          Text(
            'Never Hunt for a Loo Again.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                  fontSize: 28,
                ),
          ),
          const SizedBox(height: 16),
          Text(
            'Find verified construction site toilets, uploaded by drivers like you.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 16,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(flex: 2),
          const Center(child: _ValuePropGraphic()),
          const Spacer(flex: 3),
          SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: onLetsGo,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFFC107),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: const Text("Let's Go"),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: onLogin,
            child: Text(
              'Login',
              style: TextStyle(
                color: Colors.amber.shade400,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
          const Spacer(flex: 1),
        ],
      ),
    );
  }
}

class _ValuePropGraphic extends StatelessWidget {
  const _ValuePropGraphic();

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFFFC107);
    return SizedBox(
      height: 220,
      width: 220,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: amber.withValues(alpha: 0.06),
              boxShadow: [
                BoxShadow(
                  color: amber.withValues(alpha: 0.25),
                  blurRadius: 48,
                  spreadRadius: 8,
                ),
              ],
            ),
          ),
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: amber.withValues(alpha: 0.1),
              boxShadow: [
                BoxShadow(
                  color: amber.withValues(alpha: 0.35),
                  blurRadius: 32,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black,
              border: Border.all(color: amber, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Center(
              child: LooSvgIcon(size: 56, color: amber),
            ),
          ),
        ],
      ),
    );
  }
}

class _RadarPulse extends StatefulWidget {
  @override
  State<_RadarPulse> createState() => _RadarPulseState();
}

class _RadarPulseState extends State<_RadarPulse> {
  int _epoch = 0;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(_epoch),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 2000),
      curve: Curves.easeOut,
      onEnd: () {
        if (mounted) {
          setState(() => _epoch++);
        }
      },
      builder: (context, t, child) {
        return CustomPaint(
          size: const Size(220, 220),
          painter: _RadarPainter(progress: t),
        );
      },
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    const amber = Color(0xFFFFC107);
    final maxR = size.shortestSide * 0.48;

    for (var i = 0; i < 3; i++) {
      final phase = (progress + i * 0.28) % 1.0;
      final r = maxR * phase;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = amber.withValues(alpha: 0.45 * (1 - phase));
      canvas.drawCircle(c, r, paint);
    }

    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [
          amber.withValues(alpha: 0),
          amber.withValues(alpha: 0.15),
          amber.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.2, 1.0],
        transform: GradientRotation(progress * math.pi * 2),
      ).createShader(Rect.fromCircle(center: c, radius: maxR * 0.85));
    canvas.drawCircle(c, maxR * 0.85, sweepPaint);

    canvas.drawCircle(c, 10, Paint()..color = amber);
    canvas.drawCircle(
      c,
      10,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.black,
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _OnboardingLocationPage extends StatefulWidget {
  const _OnboardingLocationPage({required this.onGranted});

  final VoidCallback onGranted;

  @override
  State<_OnboardingLocationPage> createState() =>
      _OnboardingLocationPageState();
}

class _OnboardingLocationPageState extends State<_OnboardingLocationPage> {
  bool _busy = false;

  Future<void> _enableLocation() async {
    setState(() => _busy = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please turn on location services, then try again.'),
            ),
          );
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (!mounted) {
        return;
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        widget.onGranted();
      } else if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Location is blocked. You can enable it later in Settings.',
            ),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: Geolocator.openAppSettings,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No problem — you can enable location from the map anytime.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),
          Text(
            'Find the Closest Loo.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                  fontSize: 28,
                ),
          ),
          const SizedBox(height: 16),
          Text(
            'To show you the nearest toilet, we need your live location.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 16,
              height: 1.4,
            ),
          ),
          const Spacer(flex: 2),
          Center(child: _RadarPulse()),
          const Spacer(flex: 3),
          SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: _busy ? null : _enableLocation,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFFC107),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Text('Enable Location'),
            ),
          ),
          TextButton(
            onPressed: _busy ? null : widget.onGranted,
            child: Text(
              'Skip for now',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(flex: 1),
        ],
      ),
    );
  }
}

class _OnboardingSignUpPage extends StatefulWidget {
  const _OnboardingSignUpPage({required this.onOpenLogin});

  final VoidCallback onOpenLogin;

  @override
  State<_OnboardingSignUpPage> createState() => _OnboardingSignUpPageState();
}

class _OnboardingSignUpPageState extends State<_OnboardingSignUpPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _loading = false;
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white38),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Color(0xFFFFC107)),
      ),
    );
  }

  Future<void> _createAccount() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _errorText = e.message ?? 'Could not create account');
    } catch (e) {
      setState(() => _errorText = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _google() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    final err = await signInWithGoogleForFirebase();
    if (mounted) {
      setState(() {
        _loading = false;
        _errorText = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Column(
                    children: [
                      Text(
                        'Become a loo hunter!',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 26,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Save your favorite spots and help other drivers.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 15,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: _loading ? null : _google,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'G',
                              style: TextStyle(
                                color: Colors.blue.shade700,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                height: 1,
                              ),
                            ),
                          ),
                          label: const Text(
                            'Continue with Google',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Divider(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'or',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Divider(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: Colors.white),
                        decoration: _fieldDecoration('Email'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: _fieldDecoration('Password'),
                      ),
                      if (_errorText != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _errorText!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          onPressed: _loading ? null : _createAccount,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFFC107),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Create account',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      TextButton(
                        onPressed: _loading ? null : widget.onOpenLogin,
                        child: const Text(
                          'Already have an account? Log in',
                          style: TextStyle(
                            color: Color(0xFFFFC107),
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
