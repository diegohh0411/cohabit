import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// The app's top navigator, which outlives every page.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Opens a detail page. On desktop it replaces the content beside the
/// sidebar (the shell's own navigator); on phones it covers the whole screen,
/// including the bottom bar.
Future<T?> openPage<T>(BuildContext context, Widget page) => Navigator.of(
  context,
  rootNavigator: !isDesktopPlatform(context),
).push<T>(MaterialPageRoute<T>(builder: (_) => page));
