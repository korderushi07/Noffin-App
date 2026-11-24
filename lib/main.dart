import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tiffin/auth_screen.dart';
import 'package:tiffin/billing_screen.dart';
import 'package:tiffin/calendar_screen.dart';
import 'package:tiffin/data/repository.dart';
import 'package:tiffin/settings_screen.dart';
import 'package:tiffin/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables from .env asset or dart-define
  await dotenv.load(fileName: '.env').catchError((_) {});

  const dartDefineUrl = String.fromEnvironment('SUPABASE_URL');
  const dartDefinePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  const dartDefineAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  final supabaseUrl = dotenv.env['SUPABASE_URL']?.isNotEmpty == true
      ? dotenv.env['SUPABASE_URL']!
      : (dartDefineUrl.isNotEmpty
            ? dartDefineUrl
            : 'https://placeholder.supabase.co');

  final supabaseApiKey =
      dotenv.env['SUPABASE_PUBLISHABLE_KEY']?.isNotEmpty == true
      ? dotenv.env['SUPABASE_PUBLISHABLE_KEY']!
      : (dotenv.env['SUPABASE_ANON_KEY']?.isNotEmpty == true
            ? dotenv.env['SUPABASE_ANON_KEY']!
            : (dartDefinePublishableKey.isNotEmpty
                  ? dartDefinePublishableKey
                  : (dartDefineAnonKey.isNotEmpty
                        ? dartDefineAnonKey
                        : 'placeholder-anon-key')));

  final supabaseUri = Uri.tryParse(supabaseUrl);
  final hasValidConfiguration =
      supabaseUri != null &&
      supabaseUri.isAbsolute &&
      supabaseUri.scheme == 'https' &&
      supabaseApiKey.isNotEmpty &&
      !supabaseUrl.contains('placeholder') &&
      !supabaseUrl.contains('your-project') &&
      !supabaseApiKey.contains('placeholder') &&
      !supabaseApiKey.contains('your-anon-key');

  if (!hasValidConfiguration) {
    runApp(const TiffinApp(supabaseConfigured: false));
    return;
  }

  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseApiKey);

  runApp(const TiffinApp());
}

class TiffinApp extends StatelessWidget {
  final bool supabaseConfigured;

  const TiffinApp({super.key, this.supabaseConfigured = true});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Noffin',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: supabaseConfigured ? const AuthGate() : const SupabaseSetupScreen(),
    );
  }
}

class SupabaseSetupScreen extends StatelessWidget {
  const SupabaseSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.cloud_off_outlined,
                    size: 44,
                    color: AppColors.text,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Connect your Supabase project',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'The app is still using the sample credentials. Add your '
                    'project URL and publishable key to the root .env file, '
                    'then restart the app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: AppColors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.separator),
                    ),
                    child: const SelectableText(
                      'SUPABASE_URL=https://<project-ref>.supabase.co\n'
                      'SUPABASE_PUBLISHABLE_KEY=<publishable-key>',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.6,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Before signing in, run supabase/schema.sql in your '
                    'project’s SQL Editor. Never use a secret/service-role key in '
                    'the app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  TiffinState? _signedInState;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null && !session.user.isAnonymous) {
          if (_signedInState?.userId != session.user.id) {
            _signedInState = TiffinState(
              repository: TiffinRepository(Supabase.instance.client),
              userId: session.user.id,
            );
          }
          return HomeShell(
            key: ValueKey(session.user.id),
            state: _signedInState!,
          );
        }
        return const AuthScreen();
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  final TiffinState state;

  const HomeShell({super.key, required this.state});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      CalendarScreen(state: widget.state),
      BillingScreen(state: widget.state),
      SettingsScreen(state: widget.state),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Billing',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
