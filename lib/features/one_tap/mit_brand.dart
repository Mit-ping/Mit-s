import 'package:flutter/material.dart';
import 'package:hiddify/features/one_tap/mit_connection_controls.dart';

abstract class MitBrand {
  static const name = 'Mit’s VPN';
  static const icon = 'assets/images/mit_vpn_icon.png';
  static const sourceUrl = 'https://github.com/Mit-ping/Mit-s';
}

ThemeData mitTheme({ThemeData? base}) => (base ?? ThemeData.dark(useMaterial3: true)).copyWith(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: mitBackground,
  colorScheme: ColorScheme.fromSeed(seedColor: mitGreen, brightness: Brightness.dark, surface: mitBackground),
  appBarTheme: const AppBarTheme(backgroundColor: mitBackground, foregroundColor: Colors.white, centerTitle: false),
);

class MitLogo extends StatelessWidget {
  const MitLogo({super.key, this.size = 112});
  final double size;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * .22),
    child: Image.asset(MitBrand.icon, width: size, height: size, fit: BoxFit.contain, semanticLabel: MitBrand.name),
  );
}

class MitPage extends StatelessWidget {
  const MitPage({super.key, required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Theme(
    data: mitTheme(),
    child: Scaffold(appBar: AppBar(title: Text(title)), body: SafeArea(child: child)),
  );
}
