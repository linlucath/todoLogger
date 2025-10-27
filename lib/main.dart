import 'package:flutter/material.dart';
import 'pages/todo/todo.dart';
import 'pages/time_logger/time_logger.dart';
import 'pages/target/target.dart';
import 'pages/statistics/statistics.dart';
import 'pages/immersive_work/immersive_work.dart';
import 'utils/performance_monitor.dart';
import 'services/time_logger_storage.dart';

void main() async {
  // 性能监控: 记录启动时间
  final monitor = PerformanceMonitor();
  monitor.recordAppStart();

  // 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 数据迁移: 从 SharedPreferences 迁移到 SQLite
  await TimeLoggerStorage.migrateFromOldStorage();

  runApp(const MyApp());

  // 性能监控: 记录首帧时间
  monitor.recordFirstFrame();
  monitor.startFpsMonitoring();

  // 5 秒后打印性能报告
  Future.delayed(const Duration(seconds: 5), () {
    monitor.printReport();
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Time Logger++',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF6C63FF),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          secondary: const Color(0xFFFF6584),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Color(0xFF6C63FF),
          foregroundColor: Colors.white,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          selectedItemColor: Color(0xFF6C63FF),
          unselectedItemColor: Colors.grey,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle:
              TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          unselectedLabelStyle: TextStyle(fontSize: 12),
        ),
        useMaterial3: true,
      ),
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;

  // 页面缓存: 保留已访问的页面状态
  final Map<int, Widget> _pageCache = {};

  // 获取页面 (懒加载 + 缓存)
  Widget _getPage(int index) {
    // 如果页面已缓存,直接返回
    if (_pageCache.containsKey(index)) {
      return _pageCache[index]!;
    }

    // 创建新页面并缓存
    Widget page;
    switch (index) {
      case 0:
        page = const TodoPage();
        break;
      case 1:
        page = const TimeLoggerPage();
        break;
      case 2:
        page = const TargetPage();
        break;
      case 3:
        page = const StatisticsPage();
        break;
      case 4:
        page = const ImmersiveWorkPage();
        break;
      default:
        page = const TodoPage();
    }

    _pageCache[index] = page;
    return page;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 使用 Offstage 保持页面状态
      body: Stack(
        children: List.generate(5, (index) {
          return Offstage(
            offstage: _currentIndex != index,
            child: _getPage(index),
          );
        }),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.check_circle_outline),
            activeIcon: Icon(Icons.check_circle),
            label: 'TODO',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.timer_outlined),
            activeIcon: Icon(Icons.timer),
            label: 'Timer',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.flag_outlined),
            activeIcon: Icon(Icons.flag),
            label: 'Target',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_outlined),
            activeIcon: Icon(Icons.bar_chart),
            label: 'Stats',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.spa_outlined),
            activeIcon: Icon(Icons.spa),
            label: 'Focus',
          ),
        ],
      ),
    );
  }
}
