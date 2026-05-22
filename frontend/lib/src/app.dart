import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/config.dart';
import 'screens/home_screen.dart';

class SnapFolioApp extends StatelessWidget {
  const SnapFolioApp({super.key});

  @override
  Widget build(BuildContext context) {
    final apiClient = ApiClient(baseUrl: AppConfig.apiBaseUrl);
    const accentBlue = Color(0xFF2563EB);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: accentBlue,
      brightness: Brightness.light,
    ).copyWith(
      primary: accentBlue,
      secondary: accentBlue,
      surface: Colors.white,
    );

    return MaterialApp(
      title: 'SnapFolio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: Colors.white,
        canvasColor: Colors.white,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
        ),
        cardTheme: const CardThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: HomeScreen(apiClient: apiClient),
    );
  }
}
