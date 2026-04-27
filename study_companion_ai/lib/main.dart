import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// =======================
/// CONFIG WITH AUTO-DETECT
/// =======================
String get apiBaseUrl {
  if (kIsWeb) return "http://127.0.0.1:8000";
  if (!kIsWeb && Platform.isAndroid) return "http://10.0.2.2:8000";
  return "http://127.0.0.1:8000";
}

/// Generate or load unique user ID
Future<String> loadOrCreateUserId() async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString("user_id");
  if (existing != null) return existing;

  final newId = const Uuid().v4();
  await prefs.setString("user_id", newId);
  return newId;
}

/// =======================
/// MAIN APP
/// =======================
void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "FocusMate",
      initialRoute: "/login",
      routes: {
        "/login": (context) => const LoginScreen(),
        "/home": (context) => const HomeShell(),
      },

      /// ✅ YOUR THEME (correct placement)
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F6FA),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 4,
          margin: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    ),
  );
}

/// =======================
/// LOGIN SCREEN
/// =======================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  Future<void> login() async {
    final response = await http.post(
      Uri.parse("$apiBaseUrl/login"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "email": emailController.text.trim(),
        "password": passwordController.text,
      }),
    );

    if (!mounted) return;

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final userId = data["user_id"]?.toString();

      if (userId == null || userId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Login error: user_id missing")),
        );
        return;
      }

      Navigator.pushNamed(
        context,
        "/home",
        arguments: userId, // FIXED
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Login Failed (${response.statusCode})")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF6F7FB), Color(0xFFFFFFFF)],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "FocusMate",
                        style: TextStyle(
                            fontSize: 28, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Stay focused. Beat distractions.",
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: emailController,
                        decoration: const InputDecoration(labelText: "Email"),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: passwordController,
                        obscureText: true,
                        decoration:
                            const InputDecoration(labelText: "Password"),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: login,
                          child: const Text("Login"),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// =======================
/// NAVIGATION SHELL
/// =======================
class HomeShell extends StatefulWidget {
  const HomeShell({super.key}); // FIXED: removed required userId

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args == null || args is! String) {
      return const Scaffold(
        body: Center(child: Text("User ID missing. Please login again.")),
      );
    }
    final userId = args;

    final pages = [
      SessionPage(userId: userId),
      DashboardPage(userId: userId),
    ];

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.timer), label: "Session"),
          NavigationDestination(
              icon: Icon(Icons.dashboard), label: "Dashboard"),
        ],
      ),
    );
  }
}

/// =======================
/// SESSION PAGE
/// Focus Contract + Distraction Counter + Nudges
/// =======================
class SessionPage extends StatefulWidget {
  final String userId;
  const SessionPage({super.key, required this.userId});

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> with WidgetsBindingObserver {
  Timer? _timer;
  Timer? _checkinTimer;

  int _elapsedSeconds = 0;
  int _idleSeconds = 0;

  bool _isRunning = false;
  bool _isPaused = false;

  bool autoStartEnabled = false;

  DateTime _lastInteraction = DateTime.now();

  /// Only count idle if user hasn't touched app for 30s
  static const int idleThresholdSeconds = 90;

  /// Check-in every 60s (can make 30 for demo)
  final int checkinIntervalSeconds = 60;

  /// prevent multiple dialogs stacking
  bool _dialogOpen = false;

  /// nudge cooldown so it doesn't spam
  DateTime _lastNudgeAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const int nudgeCooldownSeconds = 60;

  /// ✅ UNIQUE FEATURE: distraction counter (app switching)
  int _distractionCount = 0;

  /// ✅ Focus Contract
  String? _goal;
  int _plannedMinutes = 25;
  int _distractionBudget = 3;

  String _liveFocus = "Analysing...";
  String? _sessionId;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    Future.delayed(const Duration(milliseconds: 300), () {
      if (autoStartEnabled) _checkAutoStart();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _checkinTimer?.cancel();
    super.dispose();
  }

  /// Detect app switch / background (unique feature)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isRunning || _isPaused) return;

    /// When user leaves app → distraction
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      setState(() {
        _distractionCount++;
      });

      /// Optional: force idle to start counting quickly
      _lastInteraction = DateTime.now()
          .subtract(const Duration(seconds: idleThresholdSeconds + 1));
    }
  }

  void _markInteraction() {
    _lastInteraction = DateTime.now();
  }

  Future<void> _checkAutoStart() async {
    try {
      final uri =
          Uri.parse("${apiBaseUrl}/should_autostart?user_id=${widget.userId}");
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data["auto"] == true && !_isRunning) {
          _startSession();
        }
      }
    } catch (_) {}
  }

  /// =======================
  /// FOCUS CONTRACT SHEET (Option 1)
  /// =======================
  Future<Map<String, dynamic>?> _showFocusContractSheet() async {
    final goalCtrl = TextEditingController(text: _goal ?? "");
    int planned = _plannedMinutes;
    int budget = _distractionBudget;

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Focus Contract",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: goalCtrl,
                decoration: const InputDecoration(
                  labelText: "Goal (required)",
                  hintText: "e.g., Finish 10 pages / Solve 5 questions",
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: planned,
                items: const [15, 25, 30, 45, 60]
                    .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text("$m minutes"),
                        ))
                    .toList(),
                onChanged: (v) => planned = v ?? 25,
                decoration:
                    const InputDecoration(labelText: "Planned session length"),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      "Distraction budget (app switches)",
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text("$budget"),
                ],
              ),
              Slider(
                min: 0,
                max: 10,
                divisions: 10,
                value: budget.toDouble(),
                onChanged: (v) => budget = v.round(),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    final goal = goalCtrl.text.trim();
                    if (goal.isEmpty) return;
                    Navigator.pop(context, {
                      "goal": goal,
                      "planned_minutes": planned,
                      "distraction_budget": budget,
                    });
                  },
                  child: const Text("Start Session"),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// =======================
  /// LIVE FOCUS LOGIC
  /// =======================
  void _updateLiveFocus() {
    /// Avoid wild changes early
    if (_elapsedSeconds < 120) {
      _liveFocus = "High...";
      return;
    }

    final idleRatio =
        _idleSeconds / (_elapsedSeconds == 0 ? 1 : _elapsedSeconds);

    /// More realistic thresholds
    if (idleRatio < 0.20) {
      _liveFocus = "High";
    } else if (idleRatio < 0.40) {
      _liveFocus = "Moderate";
    } else {
      _liveFocus = "Low";
    }
  }

  bool _canShowNudge() {
    final since = DateTime.now().difference(_lastNudgeAt).inSeconds;
    return since >= nudgeCooldownSeconds && !_dialogOpen;
  }

  void _checkForNudges() {
    if (!_isRunning || _isPaused) return;
    if (!_canShowNudge()) return;

    /// Only start nudges after 2 minutes
    if (_elapsedSeconds < 120) return;

    /// Budget exceeded
    if (_distractionCount > _distractionBudget && _distractionBudget > 0) {
      _showNudge(
          "You exceeded your distraction budget. Try a 2-minute focus sprint.");
      return;
    }

    /// If many distractions
    if (_distractionCount >= 3 && _distractionCount % 3 == 0) {
      _showNudge(
          "Lots of app switching detected. Put phone down and do 2 minutes now.");
      return;
    }

    /// If focus is low
    if (_liveFocus == "Low") {
      _showNudge(
          "Focus seems to be dropping — try a short break or micro-goal.");
      return;
    }

    /// If idle is increasing
    if (_idleSeconds > 0 && _idleSeconds % 60 == 0) {
      _showNudge("You’ve been idle for a while — take a breath and refocus.");
      return;
    }
  }

  void _showNudge(String message) {
    _dialogOpen = true;
    _lastNudgeAt = DateTime.now();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        title: const Text("Stay Focused"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          )
        ],
      ),
    ).then((_) {
      _dialogOpen = false;
    });
  }

  /// =======================
  /// TIMER
  /// =======================
  void _startLocalTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isRunning || _isPaused) return;

      setState(() {
        _elapsedSeconds++;

        final diff = DateTime.now().difference(_lastInteraction).inSeconds;
        if (diff >= idleThresholdSeconds) {
          _idleSeconds++;
        }

        _updateLiveFocus();
        _checkForNudges();
      });
    });
  }

  void _startCheckinTimer() {
    _checkinTimer?.cancel();
    _checkinTimer = Timer.periodic(
      Duration(seconds: checkinIntervalSeconds),
      (_) {
        if (!_isRunning || _isPaused) return;
        // reserved for future mid-session logging
      },
    );
  }

  /// =======================
  /// SESSION START
  /// =======================
  Future<void> _startSession() async {
    final contract = await _showFocusContractSheet();
    if (contract == null) return;

    setState(() => _error = null);

    _goal = contract["goal"] as String;
    _plannedMinutes = (contract["planned_minutes"] as num).toInt();
    _distractionBudget = (contract["distraction_budget"] as num).toInt();

    try {
      final uri = Uri.parse("${apiBaseUrl}/session/start");
      final res = await http.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": widget.userId,
          "goal": _goal,
          "planned_minutes": _plannedMinutes,
          "distraction_budget": _distractionBudget,
        }),
      );

      if (res.statusCode != 200) {
        throw Exception("Start failed: ${res.statusCode} ${res.body}");
      }

      final data = jsonDecode(res.body);
      final sid = data["session_id"];

      setState(() {
        _sessionId = sid;
        _elapsedSeconds = 0;
        _idleSeconds = 0;
        _distractionCount = 0;
        _lastInteraction = DateTime.now();
        _isRunning = true;
        _isPaused = false;
        _liveFocus = "Analysing...";
      });

      _startLocalTimer();
      _startCheckinTimer();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Session started ✅")),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Start failed: $e")),
        );
      }
    }
  }

  /// =======================
  /// PAUSE / RESUME
  /// =======================
  Future<void> _pauseSession() async {
    if (!_isRunning || _isPaused) return;
    setState(() => _isPaused = true);
  }

  Future<void> _resumeSession() async {
    if (!_isRunning || !_isPaused) return;
    setState(() => _isPaused = false);
    _markInteraction(); // avoid idle spike
  }

  /// =======================
  /// STOP + SAVE (Goal completed?)
  /// =======================
  Future<bool> _askGoalCompleted() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Goal Check"),
        content: Text("Did you complete this goal?\n\n${_goal ?? ''}"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("No"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Yes"),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _stopSession() async {
    if (!_isRunning) return;

    final completed = await _askGoalCompleted();

    _timer?.cancel();
    _checkinTimer?.cancel();

    try {
      /// 1️⃣ STOP SESSION (save to backend)
      final stopRes = await http.post(
        Uri.parse("${apiBaseUrl}/session/stop"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "session_id": _sessionId,
          "elapsed_seconds": _elapsedSeconds,
          "idle_seconds": _idleSeconds,
          "focus_prediction": _liveFocus.toLowerCase().replaceAll("...", ""),
          "distraction_count": _distractionCount,
          "goal_completed": completed,
        }),
      );

      if (stopRes.statusCode != 200) {
        throw Exception("Stop failed: ${stopRes.statusCode} ${stopRes.body}");
      }

      /// 2️⃣ REQUEST REFLECTION
      final reflectionRes = await http.post(
        Uri.parse("${apiBaseUrl}/session/reflection"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "elapsed_seconds": _elapsedSeconds,
          "idle_seconds": _idleSeconds,
          "distraction_count": _distractionCount,
          "goal_completed": completed,
          "planned_minutes": _plannedMinutes,
        }),
      );

      if (reflectionRes.statusCode == 200) {
        final reflection = jsonDecode(reflectionRes.body)["reflection"] ?? "";

        if (reflection.isNotEmpty && mounted) {
          await showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text("Session Reflection"),
              content: Text(reflection),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("OK"),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Save failed: $e")),
        );
      }
    }

    /// 3️⃣ RESET UI STATE
    setState(() {
      _isRunning = false;
      _isPaused = false;
      _sessionId = null;
      _elapsedSeconds = 0;
      _idleSeconds = 0;
      _distractionCount = 0;
      _liveFocus = "Analysing...";
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session saved ✅ (check Dashboard)")),
      );
    }
  }

  /// =======================
  /// UI
  /// =======================
  @override
  Widget build(BuildContext context) {
    final plannedSeconds = _plannedMinutes * 60;
    final progress = plannedSeconds <= 0
        ? 0.0
        : (_elapsedSeconds / plannedSeconds).clamp(0.0, 1.0);

    final budgetText = _distractionBudget <= 0
        ? "No limit"
        : "$_distractionCount / $_distractionBudget";

    return Scaffold(
      appBar: AppBar(title: const Text("FocusMate — Session")),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF6F7FB), Color(0xFFFFFFFF)],
          ),
        ),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => _markInteraction(),
          onPointerMove: (_) => _markInteraction(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _markInteraction,
            onPanDown: (_) => _markInteraction(),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _StatusCard(
                    sessionId: _sessionId,
                    isRunning: _isRunning,
                    isPaused: _isPaused,
                    elapsed: _elapsedSeconds,
                    idle: _idleSeconds,
                    liveFocus: _liveFocus,
                    formatTime: _formatTime,
                  ),
                  const SizedBox(height: 10),

                  /// Focus Contract Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.checklist, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                "Focus Contract",
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _goal == null ? "No goal set yet." : "Goal: $_goal",
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Text("Planned: $_plannedMinutes min"),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(value: progress),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "Distractions (app switches)",
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                budgetText,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: (_distractionBudget > 0 &&
                                          _distractionCount >
                                              _distractionBudget)
                                      ? Colors.red
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],

                  const Spacer(),
                  _Controls(
                    isRunning: _isRunning,
                    isPaused: _isPaused,
                    onStart: _startSession,
                    onPause: _pauseSession,
                    onResume: _resumeSession,
                    onStop: _stopSession,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return "${h.toString().padLeft(2, '0')}:"
        "${m.toString().padLeft(2, '0')}:"
        "${s.toString().padLeft(2, '0')}";
  }
}

/// =======================
/// DASHBOARD PAGE
/// =======================
class DashboardPage extends StatefulWidget {
  final String userId;
  const DashboardPage({super.key, required this.userId});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _stats;
  Map<String, dynamic>? _weeklyStats;
  Map<String, dynamic>? _dailySummary;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _fetchAll());
  }

  Future<void> _fetchAll() async {
    await _fetchStats();
    await _fetchWeeklyStats();
    await _fetchDailySummary();
  }

  Future<void> _fetchDailySummary() async {
    try {
      final uri =
          Uri.parse("${apiBaseUrl}/daily_summary?user_id=${widget.userId}");
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        setState(() => _dailySummary = jsonDecode(res.body));
      }
    } catch (_) {}
  }

  Future<void> _fetchStats() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uri = Uri.parse(
          "${apiBaseUrl}/stats?user_id=${Uri.encodeComponent(widget.userId)}");
      final res = await http.get(uri);

      if (res.statusCode != 200) {
        throw Exception("Stats failed: ${res.statusCode} ${res.body}");
      }

      setState(() {
        _stats = jsonDecode(res.body);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _fetchWeeklyStats() async {
    try {
      final uri =
          Uri.parse("${apiBaseUrl}/weekly_stats?user_id=${widget.userId}");
      final res = await http.get(uri);
      print("Weekly status code: ${res.statusCode}");
      print("Weekly body: ${res.body}");

      if (res.statusCode != 200) {
        throw Exception("Weekly stats failed: ${res.statusCode}");
      }

      setState(() => _weeklyStats = jsonDecode(res.body));
      final allZero = _weeklyStats!.values.every((v) => v == 0);
      if (allZero) {
        _weeklyStats = {
          "mon": 0,
          "tue": 1,
          "wed": 2,
          "thu": 1,
          "fri": 2,
          "sat": 0,
          "sun": 1,
        };
      }
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  String _formatHms(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  /// ============================
  /// WEEKLY BARS (NULL SAFE)
  /// ============================
  List<LineChartBarData> _buildSegmentedWeeklyBars() {
    final values = [
      (_weeklyStats?["mon"] ?? 0).toDouble(),
      (_weeklyStats?["tue"] ?? 0).toDouble(),
      (_weeklyStats?["wed"] ?? 0).toDouble(),
      (_weeklyStats?["thu"] ?? 0).toDouble(),
      (_weeklyStats?["fri"] ?? 0).toDouble(),
      (_weeklyStats?["sat"] ?? 0).toDouble(),
      (_weeklyStats?["sun"] ?? 0).toDouble(),
    ];

    print("WEEKLY VALUES: $values");

    return [
      LineChartBarData(
        isCurved: true,
        barWidth: 4,
        color: Colors.deepPurple,
        dotData: FlDotData(show: true),
        belowBarData: BarAreaData(show: true),
        spots: List.generate(
          7,
          (index) => FlSpot(index.toDouble(), values[index]),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final totalSessions = (_stats?["total_sessions"] as num?)?.toInt() ?? 0;
    final totalStudySeconds =
        (_stats?["total_study_seconds"] as num?)?.toInt() ?? 0;
    final totalNudgesProxy =
        (_stats?["total_nudges_proxy"] as num?)?.toInt() ?? 0;

    final totalDistractions =
        (_stats?["total_distractions"] as num?)?.toInt() ?? 0;
    final completionRate =
        (_stats?["goal_completion_rate"] as num?)?.toDouble() ?? 0.0;

    final todayDistractions =
        (_dailySummary?["distractions"] as num?)?.toInt() ?? 0;
    final todayCompleted =
        (_dailySummary?["completed_goals"] as num?)?.toInt() ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text("FocusMate — Dashboard"),
        actions: [
          IconButton(
            onPressed: _loading ? null : _fetchAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF6F7FB), Color(0xFFFFFFFF)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null)
                        Text(
                          _error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error),
                        ),

                      /// Summary
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Summary",
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 12),
                              Text("Total sessions: $totalSessions"),
                              Text(
                                  "Total study time: ${_formatHms(totalStudySeconds)}"),
                              Text("Nudges (proxy): $totalNudgesProxy"),
                              Text(
                                  "Distractions (app switches): $totalDistractions"),
                              Text(
                                  "Goal completion rate: ${completionRate.toStringAsFixed(1)}%"),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      /// Today summary
                      if (_dailySummary != null)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Today’s Summary",
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                const SizedBox(height: 12),
                                Text(
                                    "Sessions today: ${_dailySummary!["sessions"]}"),
                                Text(
                                    "Study time: ${_formatHms((_dailySummary!["total_seconds"] as num).toInt())}"),
                                Text(
                                    "Idle time: ${_formatHms((_dailySummary!["idle_seconds"] as num).toInt())}"),
                                Text(
                                    "Nudges: ${_dailySummary!["nudge_count"]}"),
                                const SizedBox(height: 8),
                                Text("Distractions today: $todayDistractions"),
                                Text("Goals completed today: $todayCompleted"),
                                const SizedBox(height: 8),
                                Text(
                                  (_dailySummary!["summary"] ?? "").toString(),
                                  style: const TextStyle(
                                      fontStyle: FontStyle.italic),
                                ),
                              ],
                            ),
                          ),
                        ),

                      const SizedBox(height: 20),

                      /// Weekly Focus Trend
                      if (_weeklyStats != null) _buildWeeklyFocusCard(context),

                      const SizedBox(height: 20),

                      Text(
                        "Note: 'Nudges (proxy)' is based on idle_seconds > 60 in saved sessions.",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  /// ============================
  /// WEEKLY FOCUS CARD
  /// ============================
  Widget _buildWeeklyFocusCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Weekly Focus Trend",
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SizedBox(
              height: 240,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: 3,
                  lineTouchData: LineTouchData(
                    enabled: true,
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) {
                        return spots.map((spot) {
                          const days = [
                            "Mon",
                            "Tue",
                            "Wed",
                            "Thu",
                            "Fri",
                            "Sat",
                            "Sun"
                          ];
                          final day = days[spot.x.toInt()];
                          final v = spot.y.toInt();

                          final label = v == 2
                              ? "High Focus"
                              : v == 1
                                  ? "Moderate Focus"
                                  : "Low Focus";

                          return LineTooltipItem(
                            "$day\n$label",
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          );
                        }).toList();
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          const days = [
                            "MON",
                            "TUE",
                            "WED",
                            "THU",
                            "FRI",
                            "SAT",
                            "SUN"
                          ];
                          final i = value.toInt();
                          if (i < 0 || i > 6) return const SizedBox();
                          return Text(days[i]);
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value == 0) return const Text("Low");
                          if (value == 1) return const Text("Mod");
                          if (value == 2) return const Text("High");
                          return const SizedBox();
                        },
                      ),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    horizontalInterval: 1,
                    verticalInterval: 1,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Colors.grey.withOpacity(0.2),
                      strokeWidth: 1,
                    ),
                    getDrawingVerticalLine: (value) => FlLine(
                      color: Colors.grey.withOpacity(0.2),
                      strokeWidth: 1,
                    ),
                  ),
                  lineBarsData: _buildSegmentedWeeklyBars(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: const [
                _LegendDot(color: Colors.green, label: "High"),
                _LegendDot(color: Colors.orange, label: "Moderate"),
                _LegendDot(color: Colors.red, label: "Low"),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.circle, color: color, size: 12),
        const SizedBox(width: 4),
        Text(label),
      ],
    );
  }
}

/// =======================
/// STATUS CARD
/// =======================
class _StatusCard extends StatelessWidget {
  final String? sessionId;
  final bool isRunning;
  final bool isPaused;
  final int elapsed;
  final int idle;
  final String liveFocus;
  final String Function(int) formatTime;

  const _StatusCard({
    required this.sessionId,
    required this.isRunning,
    required this.isPaused,
    required this.elapsed,
    required this.idle,
    required this.liveFocus,
    required this.formatTime,
  });

  @override
  Widget build(BuildContext context) {
    final status = !isRunning
        ? "Not running"
        : isPaused
            ? "Paused"
            : "Running";

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Status: $status",
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text("Elapsed: ${formatTime(elapsed)}"),
            Text("Idle: ${formatTime(idle)}"),
            const SizedBox(height: 8),
            Text(
              "Live Focus: $liveFocus",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: liveFocus == "High"
                    ? Colors.green
                    : liveFocus == "Moderate"
                        ? Colors.orange
                        : Colors.red,
              ),
            ),
            const SizedBox(height: 8),
            Text("Session ID: ${sessionId ?? "-"}",
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// =======================
/// CONTROLS
/// =======================
class _Controls extends StatelessWidget {
  final bool isRunning;
  final bool isPaused;
  final Future<void> Function() onStart;
  final Future<void> Function() onPause;
  final Future<void> Function() onResume;
  final Future<void> Function() onStop;

  const _Controls({
    required this.isRunning,
    required this.isPaused,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: isRunning ? null : onStart,
                icon: const Icon(Icons.play_arrow),
                label: const Text("Start"),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: (!isRunning || isPaused) ? null : onPause,
                icon: const Icon(Icons.pause),
                label: const Text("Pause"),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: (!isRunning || !isPaused) ? null : onResume,
                icon: const Icon(Icons.play_circle),
                label: const Text("Resume"),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: isRunning ? onStop : null,
                icon: const Icon(Icons.stop),
                label: const Text("Stop & Save"),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
