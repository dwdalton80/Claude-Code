import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _flameController;
  late AnimationController _fadeController;
  late AnimationController _loadingController;
  late AnimationController _iconController;
  late AnimationController _verseController;

  late Animation<double> _flamePulse;
  late Animation<double> _flameGlow;
  late Animation<double> _fadeIn;
  late Animation<double> _loadingProgress;
  late Animation<double> _iconFade;
  late Animation<double> _verseFade;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _flameController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
    _loadingController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..forward();
    _iconController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _verseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

    _flamePulse = Tween<double>(begin: 0.94, end: 1.06).animate(CurvedAnimation(parent: _flameController, curve: Curves.easeInOut));
    _flameGlow = Tween<double>(begin: 0.5, end: 1.0).animate(CurvedAnimation(parent: _flameController, curve: Curves.easeInOut));
    _fadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
    _loadingProgress = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _loadingController, curve: Curves.easeInOut));
    _iconFade = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _iconController, curve: Curves.easeOut));
    _verseFade = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _verseController, curve: Curves.easeOut));

    Future.delayed(const Duration(milliseconds: 600), () { if (mounted) _iconController.forward(); });
    Future.delayed(const Duration(milliseconds: 1100), () { if (mounted) _verseController.forward(); });
  }

  @override
  void dispose() {
    _flameController.dispose();
    _fadeController.dispose();
    _loadingController.dispose();
    _iconController.dispose();
    _verseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      backgroundColor: const Color(0xFF080808),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: const Color(0xFF080808),
        child: SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          children: [
            // Background radial glow behind icon
            AnimatedBuilder(
              animation: _flameController,
              builder: (_, __) => Positioned(
                top: size.height * 0.12,
                left: size.width / 2 - 140,
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFFF4500).withOpacity(_flameGlow.value * 0.25),
                        const Color(0xFFFF6B00).withOpacity(_flameGlow.value * 0.10),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),

            Column(
              children: [
                SizedBox(height: size.height * 0.10),

                // Flame icon with glow
                AnimatedBuilder(
                  animation: _flameController,
                  builder: (_, __) => Transform.scale(
                    scale: _flamePulse.value,
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF5500).withOpacity(_flameGlow.value * 0.5),
                            blurRadius: 50,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: Image.asset('assets/images/app_icon.png'),
                    ),
                  ),
                ),

                SizedBox(height: size.height * 0.04),

                // StudyFire wordmark
                FadeTransition(
                  opacity: _fadeIn,
                  child: RichText(
                    text: const TextSpan(
                      children: [
                        TextSpan(
                          text: 'Study',
                          style: TextStyle(
                            fontSize: 54,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -1.5,
                            height: 1.0,
                          ),
                        ),
                        TextSpan(
                          text: 'Fire',
                          style: TextStyle(
                            fontSize: 54,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFFF6200),
                            letterSpacing: -1.5,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // Tagline
                FadeTransition(
                  opacity: _fadeIn,
                  child: const Text(
                    'Study. Understand. Grow. Compete.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF777777),
                      letterSpacing: 0.3,
                    ),
                  ),
                ),

                SizedBox(height: size.height * 0.055),

                // 4 icons row
                FadeTransition(
                  opacity: _iconFade,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _IconItem(icon: Icons.menu_book_outlined, label: 'STUDY'),
                        _IconItem(icon: Icons.my_location_outlined, label: 'UNDERSTAND'),
                        _IconItem(icon: Icons.trending_up_rounded, label: 'GROW'),
                        _IconItem(icon: Icons.emoji_events_outlined, label: 'COMPETE'),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: size.height * 0.065),

                // Loading bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: AnimatedBuilder(
                    animation: _loadingController,
                    builder: (_, __) => Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: Stack(
                            children: [
                              Container(height: 3, color: const Color(0xFF1E1E1E)),
                              FractionallySizedBox(
                                widthFactor: _loadingProgress.value,
                                child: Container(
                                  height: 3,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFFCC3300), Color(0xFFFF8800)],
                                    ),
                                    borderRadius: BorderRadius.circular(3),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFFF6600).withOpacity(0.9),
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'L O A D I N G . . .',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF444444),
                            letterSpacing: 3.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(),

                // Verse at bottom
                FadeTransition(
                  opacity: _verseFade,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 44),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 3,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6200),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Your word is a lamp to my feet\nand a light to my path.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFFBBBBBB),
                                  height: 1.6,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'PSALM 119:105',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFFFF6200),
                                  letterSpacing: 2.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: size.height * 0.06),
              ],
            ),
          ],
        ),
      )),
    );
  }
}

class _IconItem extends StatelessWidget {
  final IconData icon;
  final String label;
  const _IconItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFFFF6200), size: 30),
        const SizedBox(height: 7),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            color: Color(0xFF666666),
            letterSpacing: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
