// 高级自定义标题栏示例
// 这个文件展示了如何进一步扩展标题栏功能

import 'package:flutter/material.dart';
import 'dart:io';
import 'package:window_manager/window_manager.dart';

/// 高级自定义标题栏示例
///
/// 包含更多功能：
/// - 动态标题
/// - 搜索栏
/// - 设置按钮
/// - 主题切换
class AdvancedTitleBar extends StatefulWidget {
  final String title;
  final Color? backgroundColor;
  final VoidCallback? onSettings;
  final VoidCallback? onThemeToggle;
  final bool showSearch;

  const AdvancedTitleBar({
    super.key,
    required this.title,
    this.backgroundColor,
    this.onSettings,
    this.onThemeToggle,
    this.showSearch = false,
  });

  @override
  State<AdvancedTitleBar> createState() => _AdvancedTitleBarState();
}

class _AdvancedTitleBarState extends State<AdvancedTitleBar> {
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return const SizedBox.shrink();
    }

    final bgColor = widget.backgroundColor ?? Theme.of(context).primaryColor;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: bgColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 可拖动区域 + 标题/搜索栏
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (details) {
                if (!_isSearching) {
                  windowManager.startDragging();
                }
              },
              onDoubleTap: () async {
                if (!_isSearching) {
                  bool isMaximized = await windowManager.isMaximized();
                  if (isMaximized) {
                    windowManager.unmaximize();
                  } else {
                    windowManager.maximize();
                  }
                }
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 16.0, right: 8.0),
                child: Row(
                  children: [
                    // 应用图标
                    if (!_isSearching) ...[
                      Icon(
                        Icons.check_circle,
                        color: Colors.white.withValues(alpha: 0.9),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                    ],
                    // 标题或搜索栏
                    Expanded(
                      child: _isSearching ? _buildSearchField() : _buildTitle(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 功能按钮
          if (widget.showSearch && !_isSearching)
            _TitleBarIconButton(
              icon: Icons.search,
              onPressed: () => setState(() => _isSearching = true),
              tooltip: '搜索',
            ),
          if (_isSearching)
            _TitleBarIconButton(
              icon: Icons.close,
              onPressed: () {
                setState(() {
                  _isSearching = false;
                  _searchController.clear();
                });
              },
              tooltip: '关闭搜索',
            ),
          if (widget.onThemeToggle != null)
            _TitleBarIconButton(
              icon: Icons.brightness_6,
              onPressed: widget.onThemeToggle!,
              tooltip: '切换主题',
            ),
          if (widget.onSettings != null)
            _TitleBarIconButton(
              icon: Icons.settings,
              onPressed: widget.onSettings!,
              tooltip: '设置',
            ),
          // 分隔线
          Container(
            width: 1,
            height: 20,
            color: Colors.white.withValues(alpha: 0.2),
            margin: const EdgeInsets.symmetric(horizontal: 4),
          ),
          // 窗口控制按钮
          _WindowButton(
            icon: Icons.minimize,
            onPressed: () => windowManager.minimize(),
            tooltip: '最小化',
          ),
          _WindowButton(
            icon: Icons.crop_square,
            onPressed: () async {
              bool isMaximized = await windowManager.isMaximized();
              if (isMaximized) {
                windowManager.unmaximize();
              } else {
                windowManager.maximize();
              }
            },
            tooltip: '最大化/还原',
          ),
          _WindowButton(
            icon: Icons.close,
            onPressed: () => windowManager.close(),
            isClose: true,
            tooltip: '关闭',
          ),
        ],
      ),
    );
  }

  Widget _buildTitle() {
    return Text(
      widget.title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      autofocus: true,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: '搜索...',
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        border: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
      ),
      onSubmitted: (value) {
        // 处理搜索
        debugPrint('搜索: $value');
      },
    );
  }
}

/// 标题栏图标按钮
class _TitleBarIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  const _TitleBarIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  @override
  State<_TitleBarIconButton> createState() => _TitleBarIconButtonState();
}

class _TitleBarIconButtonState extends State<_TitleBarIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip ?? '',
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _isHovered
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.transparent,
            ),
            child: Icon(
              widget.icon,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
}

/// 窗口控制按钮
class _WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool isClose;
  final String? tooltip;

  const _WindowButton({
    required this.icon,
    required this.onPressed,
    this.isClose = false,
    this.tooltip,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip ?? '',
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 46,
            height: 40,
            decoration: BoxDecoration(
              color: _isHovered
                  ? (widget.isClose
                      ? Colors.red
                      : Colors.white.withValues(alpha: 0.1))
                  : Colors.transparent,
            ),
            child: Icon(
              widget.icon,
              color: Colors.white,
              size: 16,
            ),
          ),
        ),
      ),
    );
  }
}
