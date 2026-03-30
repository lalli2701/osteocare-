import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'dashboard_page.dart';
import '../../../features/survey/presentation/survey_page.dart';
import '../../../features/chatbot/presentation/assistant_fab.dart';
import 'tasks_page.dart';
import 'profile_page.dart';

class DashboardWrapper extends ConsumerStatefulWidget {
  const DashboardWrapper({super.key});

  static const routePath = '/dashboard';

  @override
  ConsumerState<DashboardWrapper> createState() => _DashboardWrapperState();
}

class _DashboardWrapperState extends ConsumerState<DashboardWrapper> {
  int _selectedIndex = 0;
  late Locale _currentLocale;
  bool _localeInitialized = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newLocale = context.locale;
    if (!_localeInitialized) {
      _currentLocale = newLocale;
      _localeInitialized = true;
      return;
    }
    if (newLocale != _currentLocale) {
      _currentLocale = newLocale;
      setState(() {});
    }
  }

  List<Widget> get _pages {
    // Recreate pages on every build to ensure they use current locale
    // IMPORTANT: Remove 'const' so new instances are created each time
    // Using 'const' causes Flutter to reuse same instance from pool,
    // preventing didChangeDependencies() from triggering properly
    return [
      DashboardPage(),
      SurveyPage(),
      TasksPage(),
      ProfilePage(),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Force rebuild when locale changes
    context.locale;

    final isSurveyMode = _selectedIndex == 1;

    Widget? contextualFab;
    if (_selectedIndex == 0) {
      contextualFab = const AssistantFab(
        contextHint: 'Ask how to reduce your risk',
      );
    } else if (_selectedIndex == 3) {
      contextualFab = const AssistantFab(
        contextHint: 'Explain my results and next steps',
      );
    }

    return Scaffold(
      body: _pages[_selectedIndex],
      floatingActionButton: isSurveyMode ? null : contextualFab,
      bottomNavigationBar: isSurveyMode
          ? null
          : BottomNavigationBar(
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.dashboard),
            label: 'dashboard'.tr(),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.assignment),
            label: 'survey'.tr(),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.task_alt),
            label: 'Daily Plan',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person),
            label: 'profile'.tr(),
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}
