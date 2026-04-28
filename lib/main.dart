import 'package:flutter/material.dart';

import 'core/theme/app_colors.dart';
import 'features/splash/presentation/screens/splash_screen.dart';

void main() {
  runApp(const MoneyaApp());
}

class MoneyaApp extends StatelessWidget {
  const MoneyaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MoneyA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.brandPurple,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: AppColors.black, 
        fontFamily: 'Satoshi',
      ),
      home: const SplashScreen(),
    );
  }
}
