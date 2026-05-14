import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Vibrant Social Palette based on provided images
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF8F9FA);
  static const Color primary = Color(0xFFFF2D55); // The vibrant Pink/Magenta
  static const Color secondary = Color(0xFF8E24AA); // The Purple for gradients
  static const Color textMain = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF757575);
  static const Color accent = Color(0xFFFFD700); // Gold for "Official" badges
  static const Color emerald = Color(0xFF10B981); // Green for momentum badges
  
  static Gradient pinkPurpleGradient = const LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: secondary,
        surface: surface,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme).copyWith(
        displaySmall: GoogleFonts.outfit(fontWeight: FontWeight.w900, color: textMain),
        titleLarge: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: textMain),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(color: textMain, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1.5),
        iconTheme: IconThemeData(color: textMain),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: background,
        selectedItemColor: primary,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 10,
      ),
    );
  }

  static BoxDecoration cardDecoration = BoxDecoration(
    color: background,
    borderRadius: BorderRadius.circular(16),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.05),
        blurRadius: 15,
        offset: const Offset(0, 5),
      ),
    ],
  );
}
