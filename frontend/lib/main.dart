import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

// ==========================================
// 1. DATA MODEL SCHEMAS
// ==========================================
class Task {
  final int id;
  final String title;
  final String description;
  final String category;
  final int day;
  final bool completed;

  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.day,
    required this.completed,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as int,
      title: json['title'] as String,
      description: json['description'] as String,
      category: json['category'] as String,
      day: json['day'] as int,
      completed: json['completed'] as bool,
    );
  }
}

class Habit {
  final int id;
  final String name;
  final int streak;
  final String? lastCompleted;

  Habit({
    required this.id,
    required this.name,
    required this.streak,
    this.lastCompleted,
  });

  factory Habit.fromJson(Map<String, dynamic> json) {
    return Habit(
      id: json['id'] as int,
      name: json['name'] as String,
      streak: json['streak'] as int,
      lastCompleted: json['last_completed'] as String?,
    );
  }
}

// ==========================================
// 2. HTTP NETWORKING SERVICE LAYER
// ==========================================
class HttpService {
  // Configured default local server endpoint. Settable for emulators (e.g. 10.0.2.2)
  static String baseUrl = "http://localhost:8000";

  static Future<Map<String, dynamic>> generateRoadmap(
      String techStack, String fitnessTargets, int studyHours) async {
    final url = Uri.parse("$baseUrl/api/generate-roadmap");
    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "tech_stack": techStack,
          "fitness_targets": fitnessTargets,
          "study_hours": studyHours,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception("Server Error: ${response.statusCode}");
      }
    } catch (e) {
      throw Exception("Network connection timeout. Verify backend is active.");
    }
  }

  static Future<List<Task>> fetchTasks() async {
    final url = Uri.parse("$baseUrl/api/tasks");
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final List<dynamic> body = jsonDecode(response.body);
        return body.map((dynamic item) => Task.fromJson(item as Map<String, dynamic>)).toList();
      } else {
        throw Exception("Failed to fetch roadmap tasks.");
      }
    } catch (e) {
      throw Exception("Network error connecting to $baseUrl");
    }
  }

  static Future<bool> toggleTaskComplete(int taskId) async {
    final url = Uri.parse("$baseUrl/api/tasks/$taskId/complete");
    try {
      final response = await http.put(url).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['completed'] as bool;
      } else {
        throw Exception("Failed to update task completion.");
      }
    } catch (e) {
      throw Exception("Network connection timed out.");
    }
  }

  static Future<List<Habit>> fetchStreaks() async {
    final url = Uri.parse("$baseUrl/api/streaks");
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final List<dynamic> body = jsonDecode(response.body);
        return body.map((dynamic item) => Habit.fromJson(item as Map<String, dynamic>)).toList();
      } else {
        throw Exception("Failed to load streak habits.");
      }
    } catch (e) {
      throw Exception("Network error connecting to streaks endpoint.");
    }
  }

  static Future<String> chatWithCoordinator(String message) async {
    final url = Uri.parse("$baseUrl/api/chat");
    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"message": message}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['reply'] as String;
      } else {
        throw Exception("Failed to reach AI stylist coordinator.");
      }
    } catch (e) {
      throw Exception("Network error connecting to chat API.");
    }
  }
}

// ==========================================
// 3. CHANGE NOTIFIER ROADMAP PROVIDER
// ==========================================
class RoadmapProvider extends ChangeNotifier {
  List<Task> _tasks = [];
  List<Habit> _habits = [];
  List<String> _milestones = [];
  List<Map<String, String>> _chatMessages = [
    {"sender": "bot", "text": "Welcome to your Summer Arc! Fill in your goals to construct your roadmap, or ask me for advice."}
  ];

  bool _isLoading = false;
  bool _isGenerating = false;
  String _errorMessage = "";
  ThemeMode _themeMode = ThemeMode.dark;

  List<Task> get tasks => _tasks;
  List<Habit> get habits => _habits;
  List<String> get milestones => _milestones;
  List<Map<String, String>> get chatMessages => _chatMessages;
  bool get isLoading => _isLoading;
  bool get isGenerating => _isGenerating;
  String get errorMessage => _errorMessage;
  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  void toggleTheme() {
    _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }

  double get completionRate {
    if (_tasks.isEmpty) return 0.0;
    final completedCount = _tasks.where((t) => t.completed).length;
    return completedCount / _tasks.length;
  }

  Future<void> generateRoadmap(String techStack, String fitnessTargets, int studyHours) async {
    _isGenerating = true;
    _errorMessage = "";
    notifyListeners();

    try {
      final response = await HttpService.generateRoadmap(techStack, fitnessTargets, studyHours);
      
      final List<dynamic> taskList = response['tasks'];
      _tasks = taskList.map((dynamic item) => Task.fromJson(item as Map<String, dynamic>)).toList();
      
      final List<dynamic> milestoneList = response['milestones'] ?? [];
      _milestones = milestoneList.cast<String>();

      // Reload streaks and database states
      await refreshStreaks();
      _errorMessage = "";
    } catch (e) {
      _errorMessage = e.toString().replaceAll("Exception:", "");
    } finally {
      _isGenerating = false;
      notifyListeners();
    }
  }

  Future<void> refreshTasks() async {
    _isLoading = true;
    _errorMessage = "";
    notifyListeners();

    try {
      _tasks = await HttpService.fetchTasks();
    } catch (e) {
      _errorMessage = e.toString().replaceAll("Exception:", "");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshStreaks() async {
    try {
      _habits = await HttpService.fetchStreaks();
    } catch (e) {
      print("Streaks refresh error: $e");
    }
    notifyListeners();
  }

  Future<void> toggleTask(int taskId) async {
    try {
      final newStatus = await HttpService.toggleTaskComplete(taskId);
      
      // Update local item reference state instantly
      final idx = _tasks.indexWhere((t) => t.id == taskId);
      if (idx != -1) {
        final old = _tasks[idx];
        _tasks[idx] = Task(
          id: old.id,
          title: old.title,
          description: old.description,
          category: old.category,
          day: old.day,
          completed: newStatus,
        );
      }
      
      // Fetch updated streaks
      await refreshStreaks();
    } catch (e) {
      _errorMessage = e.toString().replaceAll("Exception:", "");
      notifyListeners();
    }
  }

  Future<void> sendChatMessage(String msg) async {
    if (msg.trim().isEmpty) return;
    
    _chatMessages.add({"sender": "user", "text": msg});
    notifyListeners();

    try {
      final reply = await HttpService.chatWithCoordinator(msg);
      _chatMessages.add({"sender": "bot", "text": reply});
    } catch (e) {
      _chatMessages.add({"sender": "bot", "text": "Sorry, I lost access to the mainframe coordination grid."});
    } finally {
      notifyListeners();
    }
  }

  void clearError() {
    _errorMessage = "";
    notifyListeners();
  }
}

// ==========================================
// 4. MAIN FLUTTER APP APPLICATION
// ==========================================
void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => RoadmapProvider(),
      child: const SummerArcApp(),
    ),
  );
}

class SummerArcApp extends StatelessWidget {
  const SummerArcApp({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<RoadmapProvider>(context);

    return MaterialApp(
      title: 'Summer Arc AI Planner',
      debugShowCheckedModeBanner: false,
      themeMode: provider.themeMode,
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xFFF5F5F9),
        cardColor: Colors.white,
        primaryColor: const Color(0xFF00B4D8),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF00B4D8),
          secondary: Color(0xFF7B2CBF),
          surface: Colors.white,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFFE9ECEF),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: Color(0xFF00B4D8), width: 1.5),
          ),
        ),
      ),
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F14),
        cardColor: const Color(0xFF161622),
        primaryColor: const Color(0xFF00E5FF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF9D4EDD),
          surface: Color(0xFF161622),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF1E1E2F),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: Color(0xFF00E5FF), width: 1.5),
          ),
        ),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const GoalInputScreen(),
    const TimelineDashboardScreen(),
    const ChatScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _screens[_currentIndex]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0C0C10) : Colors.white,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Theme.of(context).brightness == Brightness.dark ? Colors.white24 : Colors.black26,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.rocket_launch),
            label: 'Goal Core',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_customize),
            label: 'Timeline',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.psychology),
            label: 'Orbit AI',
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 5. GOAL INPUT CORE SCREEN
// ==========================================
class GoalInputScreen extends StatefulWidget {
  const GoalInputScreen({super.key});

  @override
  State<GoalInputScreen> createState() => _GoalInputScreenState();
}

class _GoalInputScreenState extends State<GoalInputScreen> {
  final _techController = TextEditingController();
  final _fitnessController = TextEditingController();
  int _studyHours = 4;
  final _formKey = GlobalKey<FormState>();

  // Dialog configuration setting helper
  void _showIpSettingsDialog() {
    final controller = TextEditingController(text: HttpService.baseUrl);
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Host Endpoint Settings'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'API Server URL',
              hintText: 'http://localhost:8000',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                HttpService.baseUrl = controller.text.trim();
                Navigator.pop(context);
              },
              child: const Text('Save'),
            )
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<RoadmapProvider>(context);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SUMMER ARC',
                      style: TextStyle(
                        fontFamily: 'Orbitron',
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Theme.of(context).colorScheme.primary,
                        letterSpacing: 2,
                      ),
                    ),
                    Text(
                      'Construct Your AI Roadmap',
                      style: TextStyle(
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.white54 : Colors.black54,
                        fontSize: 13,
                      ),
                    )
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        provider.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                        color: provider.isDarkMode ? Colors.white60 : Colors.black54,
                      ),
                      onPressed: provider.toggleTheme,
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.settings,
                        color: provider.isDarkMode ? Colors.white60 : Colors.black54,
                      ),
                      onPressed: _showIpSettingsDialog,
                    ),
                  ],
                )
              ],
            ),
            const SizedBox(height: 35),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TARGET TECHNOLOGY STACK',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.5, color: Color(0xFF9D4EDD)),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _techController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Flutter, FastAPI, Rust sandbox coding...',
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'Goal input required' : null,
                    ),
                    const SizedBox(height: 25),
                    const Text(
                      'FITNESS & PHYSIQUE OBJECTIVES',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.5, color: Color(0xFF9D4EDD)),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _fitnessController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Run 5km daily, fat loss conditioning...',
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'Physique targets required' : null,
                    ),
                    const SizedBox(height: 25),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'DAILY DEVOTED STUDY HOURS',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.5, color: Color(0xFF9D4EDD)),
                        ),
                        Text(
                          '$_studyHours Hours',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00E5FF)),
                        )
                      ],
                    ),
                    Slider(
                      value: _studyHours.toDouble(),
                      min: 1,
                      max: 12,
                      divisions: 11,
                      activeColor: const Color(0xFF00E5FF),
                      inactiveColor: Colors.white10,
                      onChanged: (val) {
                        setState(() {
                          _studyHours = val.toInt();
                        });
                      },
                    ),
                    if (provider.errorMessage.isNotEmpty) ...[
                      const SizedBox(height: 15),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.redAccent),
                            const SizedBox(width: 10),
                            Expanded(child: Text(provider.errorMessage, style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
                            IconButton(
                              icon: const Icon(Icons.close, size: 16, color: Colors.white60),
                              onPressed: provider.clearError,
                            )
                          ],
                        ),
                      )
                    ]
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            provider.isGenerating
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF00E5FF),
                    ),
                  )
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF9D4EDD),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 4,
                    ),
                    onPressed: () {
                      if (_formKey.currentState!.validate()) {
                        provider.generateRoadmap(
                          _techController.text,
                          _fitnessController.text,
                          _studyHours,
                        ).then((_) {
                          if (provider.errorMessage.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Summer Arc generated successfully!')),
                            );
                          }
                        });
                      }
                    },
                    child: const Text(
                      'CONSTRUCT ROADMAP',
                      style: TextStyle(
                        fontFamily: 'Orbitron',
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        color: Colors.white,
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 6. TIMELINE DASHBOARD SCREEN
// ==========================================
class TimelineDashboardScreen extends StatelessWidget {
  const TimelineDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<RoadmapProvider>(context);

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'YOUR ROADMAP',
                style: TextStyle(
                  fontFamily: 'Orbitron',
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Color(0xFF00E5FF)),
                onPressed: () {
                  provider.refreshTasks();
                  provider.refreshStreaks();
                },
              ),
            ],
          ),
          const SizedBox(height: 15),
          // Progress metrics card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.black12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Arc Leveling Progress',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    Text(
                      '${(provider.completionRate * 100).toInt()}%',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
                    )
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: provider.completionRate,
                    minHeight: 8,
                    backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.black12,
                    valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                  ),
                ),
                const SizedBox(height: 15),
                Text(
                  'Daily Streak Multipliers',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.white30 : Colors.black38,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: provider.habits.isEmpty
                      ? [Text('Generate roadmap to see streaks', style: TextStyle(fontSize: 12, color: Theme.of(context).brightness == Brightness.dark ? Colors.white38 : Colors.black38))]
                      : provider.habits.map((habit) {
                          return Row(
                            children: [
                              const Icon(Icons.local_fire_department, color: Colors.orange, size: 18),
                              const SizedBox(width: 4),
                              Text(
                                '${habit.name.split(" ").last}: ',
                                style: TextStyle(fontSize: 11, color: Theme.of(context).brightness == Brightness.dark ? Colors.white60 : Colors.black54),
                              ),
                              Text(
                                '${habit.streak}d',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.secondary, fontSize: 12),
                              )
                            ],
                          );
                        }).toList(),
                )
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: provider.isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF9D4EDD)))
                : provider.tasks.isEmpty
                    ? Center(
                        child: Text(
                          'No roadmap tasks initialized.\nUse the Goal Core tab to construct your Arc.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white38 : Colors.black38),
                        ),
                      )
                    : ListView.builder(
                        itemCount: 3, // 3 Days
                        itemBuilder: (context, dayIdx) {
                          final day = dayIdx + 1;
                          final dayTasks = provider.tasks.where((t) => t.day == day).toList();

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12.0),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF9D4EDD).withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: const Color(0xFF9D4EDD), width: 1.5),
                                      ),
                                      child: Text(
                                        'DAY $day',
                                        style: const TextStyle(
                                          fontFamily: 'Orbitron',
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: Color(0xFF9D4EDD),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(child: Divider(color: Theme.of(context).brightness == Brightness.dark ? Colors.white12 : Colors.black12)),
                                  ],
                                ),
                              ),
                              ...dayTasks.map((task) {
                                Color categoryColor = const Color(0xFF00E5FF);
                                if (task.category == 'Fitness') {
                                  categoryColor = const Color(0xFF9D4EDD);
                                } else if (task.category == 'Wellness') {
                                  categoryColor = Colors.tealAccent;
                                }

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: BorderSide(color: task.completed ? (Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.black12) : categoryColor.withOpacity(0.2)),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    leading: Checkbox(
                                      value: task.completed,
                                      activeColor: categoryColor,
                                      onChanged: (_) => provider.toggleTask(task.id),
                                    ),
                                    title: Text(
                                      task.title,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        decoration: task.completed ? TextDecoration.lineThrough : null,
                                        color: task.completed
                                            ? (Theme.of(context).brightness == Brightness.dark ? Colors.white30 : Colors.black38)
                                            : (Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87),
                                      ),
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 6.0),
                                      child: Text(
                                        task.description,
                                        style: TextStyle(fontSize: 12, color: Theme.of(context).brightness == Brightness.dark ? Colors.white60 : Colors.black54),
                                      ),
                                    ),
                                    trailing: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: categoryColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        task.category.toUpperCase(),
                                        style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: categoryColor),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          );
                        },
                      ),
          )
        ],
      ),
    );
  }
}

// ==========================================
// 7. ORBIT AI STYLIZED CHAT SCREEN
// ==========================================
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgController = TextEditingController();
  final _scrollController = ScrollController();

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<RoadmapProvider>(context);

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ORBIT COORDINATOR',
                style: TextStyle(
                  fontFamily: 'Orbitron',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: Color(0xFF00E5FF),
                ),
              ),
              Text(
                'Gamified AI Roadmap Stylist',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.black12),
              ),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: provider.chatMessages.length,
                itemBuilder: (context, index) {
                  final msg = provider.chatMessages[index];
                  final isBot = msg['sender'] == 'bot';

                  return Align(
                    alignment: isBot ? Alignment.centerLeft : Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isBot ? (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E1E2F) : Colors.grey[200]) : Theme.of(context).colorScheme.secondary.withOpacity(0.15),
                        border: Border.all(
                          color: isBot ? Theme.of(context).colorScheme.primary.withOpacity(0.3) : Theme.of(context).colorScheme.secondary.withOpacity(0.4),
                          width: 1,
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(12),
                          topRight: const Radius.circular(12),
                          bottomLeft: isBot ? Radius.zero : const Radius.circular(12),
                          bottomRight: isBot ? const Radius.circular(12) : Radius.zero,
                        ),
                      ),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isBot ? '[ORBIT]' : '[YOU]',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: isBot ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.secondary,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            msg['text'] ?? '',
                            style: const TextStyle(fontSize: 13, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _msgController,
                  decoration: const InputDecoration(
                    hintText: 'Adjust daily schedules or query style guidance...',
                  ),
                  onSubmitted: (_) {
                    final text = _msgController.text;
                    _msgController.clear();
                    provider.sendChatMessage(text).then((_) => _scrollToBottom());
                  },
                ),
              ),
              const SizedBox(width: 10),
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: () {
                    final text = _msgController.text;
                    _msgController.clear();
                    provider.sendChatMessage(text).then((_) => _scrollToBottom());
                  },
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}
