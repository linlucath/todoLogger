import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'pages/todo/todo.dart';
import 'pages/time_logger/time_logger.dart';
import 'pages/target/target.dart';
import 'pages/statistics/statistics.dart';
import 'pages/sync/sync_settings.dart';
import 'widgets/custom_title_bar.dart';
import 'utils/performance_monitor.dart';
import 'services/time_logger_storage.dart';
import 'services/sync_service.dart';
import 'services/notification_service.dart';

// 全局同步服务实例
late final SyncService syncService;
// 全局通知服务实例
late final NotificationService notificationService;
// 🆕 全局导航 key，用于通知跳转
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  // 🆕 设置全局错误处理
  await runZonedGuarded(
    () async {
      // 🆕 捕获Flutter框架错误
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        debugPrint('Flutter错误: ${details.exception}');
        debugPrint('堆栈跟踪: ${details.stack}');
        // 在生产环境可以上报到错误跟踪服务
      };

      // 🆕 捕获异步错误
      PlatformDispatcher.instance.onError = (error, stack) {
        debugPrint('异步错误: $error');
        debugPrint('堆栈跟踪: $stack');
        return true; // 表示错误已处理
      };

      // 性能监控: 记录启动时间
      final monitor = PerformanceMonitor();
      monitor.recordAppStart();

      // 确保 Flutter 绑定初始化
      WidgetsFlutterBinding.ensureInitialized();

      // 初始化 Windows 窗口管理器（仅桌面平台）
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await windowManager.ensureInitialized();

        // 配置窗口选项
        WindowOptions windowOptions = const WindowOptions(
          size: Size(800, 600),
          minimumSize: Size(400, 500),
          center: true,
          backgroundColor: Colors.transparent,
          skipTaskbar: false,
          titleBarStyle: TitleBarStyle.hidden, // 隐藏默认标题栏
        );

        windowManager.waitUntilReadyToShow(windowOptions, () async {
          await windowManager.show();
          await windowManager.focus();
        });
      }

      // 初始化桌面平台的 sqflite
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }

      // 初始化同步服务
      syncService = SyncService();
      await syncService.initialize();

      // 初始化通知服务 (仅移动端)
      if (Platform.isAndroid || Platform.isIOS) {
        notificationService = NotificationService();
        await notificationService.initialize();
      }

      runApp(const MyApp());

      // 性能监控: 记录首帧时间
      monitor.recordFirstFrame();
      monitor.startFpsMonitoring();

      // 5 秒后打印性能报告
      Future.delayed(const Duration(seconds: 5), () {
        monitor.printReport();
      });
    },
    (error, stack) {
      // 🆕 捕获所有未处理的错误
      debugPrint('未捕获的错误: $error');
      debugPrint('堆栈跟踪: $stack');
      // 在生产环境可以上报到错误跟踪服务
    },
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey, // 🆕 设置全局导航 key
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

class _MainPageState extends State<MainPage> with WidgetsBindingObserver {
  int _currentIndex = 0;

  // 页面缓存: 保留已访问的页面状态
  final Map<int, Widget> _pageCache = {};

  // TimeLoggerPage 的 GlobalKey，用于访问其状态
  final GlobalKey<State<TimeLoggerPage>> _timeLoggerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // 监听应用生命周期变化
    WidgetsBinding.instance.addObserver(this);

    // 🆕 设置通知导航回调
    if (Platform.isAndroid || Platform.isIOS) {
      notificationService.setNavigationCallback(() {
        // 导航到 TimeLogger 页面
        if (mounted) {
          setState(() {
            _currentIndex = 1; // TimeLogger 是索引 1
          });
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // 只在移动端处理
    if (!Platform.isAndroid && !Platform.isIOS) return;

    debugPrint('应用生命周期变化: $state');

    // 通过 GlobalKey 获取 TimeLoggerPage 的状态并触发生命周期事件
    final timeLoggerState = _timeLoggerKey.currentState;
    if (timeLoggerState != null && timeLoggerState.mounted) {
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.inactive) {
        // 应用进入后台
        (timeLoggerState as dynamic).onAppPaused();
      } else if (state == AppLifecycleState.resumed) {
        // 应用回到前台
        (timeLoggerState as dynamic).onAppResumed();
      }
    }
  }

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
        // TimeLoggerPage 使用 GlobalKey 以便访问其状态
        page = TimeLoggerPage(key: _timeLoggerKey, syncService: syncService);
        break;
      case 2:
        page = const TargetPage();
        break;
      case 3:
        page = const StatisticsPage();
        break;
      case 4:
        page = SyncSettingsPage(syncService: syncService);
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
      // 使用 Column 包含自定义标题栏和页面内容
      body: Column(
        children: [
          // 桌面平台显示自定义标题栏
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
            const CustomTitleBar(
              title: 'cc',
            ),
          // 页面内容
          Expanded(
            child: Stack(
              children: List.generate(5, (index) {
                return Offstage(
                  offstage: _currentIndex != index,
                  child: _getPage(index),
                );
              }),
            ),
          ),
        ],
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
            icon: Icon(Icons.sync_outlined),
            activeIcon: Icon(Icons.sync),
            label: 'Sync',
          ),
        ],
      ),
    );
  }
}
