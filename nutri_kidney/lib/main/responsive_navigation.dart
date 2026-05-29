import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class ResponsiveNavigation {
  static bool isDesktopWeb(BuildContext context) {
    return kIsWeb && MediaQuery.sizeOf(context).width >= 900;
  }

  static Widget wrapBody({
    required BuildContext context,
    required int currentIndex,
    required ValueChanged<int> onDestinationSelected,
    required Widget child,
  }) {
    if (!isDesktopWeb(context)) return child;

    return Row(
      children: [
        _DesktopNavigationRail(
          currentIndex: currentIndex,
          onDestinationSelected: onDestinationSelected,
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _DesktopNavigationRail extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  const _DesktopNavigationRail({
    required this.currentIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 224,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: Color(0xFFE5ECEA)),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: NavigationRail(
            extended: true,
            minExtendedWidth: 212,
            backgroundColor: Colors.white,
            selectedIndex: currentIndex,
            selectedIconTheme: const IconThemeData(color: Color(0xFF00A884)),
            unselectedIconTheme: const IconThemeData(color: Color(0xFF90A4AE)),
            selectedLabelTextStyle: const TextStyle(
              color: Color(0xFF263238),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            unselectedLabelTextStyle: const TextStyle(
              color: Color(0xFF607D8B),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            indicatorColor: const Color(0xFFE8F7F2),
            leading: const Padding(
              padding: EdgeInsets.only(bottom: 18),
              child: Text(
                'Nutri Kidney',
                style: TextStyle(
                  color: Color(0xFF37474F),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            onDestinationSelected: onDestinationSelected,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: Text('Home'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.restaurant_menu),
                label: Text('Food'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.bar_chart),
                label: Text('Analytics'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.favorite_border),
                selectedIcon: Icon(Icons.favorite),
                label: Text('Health'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: Text('Profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
