import 'package:universal_io/io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../utils/navigation.dart';
import '../services/auth_service.dart';
import '../utils/constants.dart';

class CustomTitleBar extends StatefulWidget {
  const CustomTitleBar({super.key});

  @override
  State<CustomTitleBar> createState() => _CustomTitleBarState();
}

class _CustomTitleBarState extends State<CustomTitleBar> with WindowListener {
  bool _isMaximized = false;
  bool _isHoveringClose = false;
  bool _isHoveringMaximize = false;
  bool _isHoveringMinimize = false;
  bool _isPressedClose = false;
  bool _isPressedMaximize = false;
  bool _isPressedMinimize = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _updateMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowEvent(String event) {
    if (event == 'maximize' || event == 'unmaximize' || event == 'resize') {
      _updateMaximized();
    }
  }

  Future<void> _updateMaximized() async {
    final maximized = await windowManager.isMaximized();
    if (mounted && _isMaximized != maximized) {
      setState(() => _isMaximized = maximized);
    }
  }

  void _startDragging() => windowManager.startDragging();

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    return GestureDetector(
      onPanStart: (_) => _startDragging(),
      onDoubleTap: () async {
        if (_isMaximized)
          await windowManager.unmaximize();
        else
          await windowManager.maximize();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 40,
        color: primaryColor,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Image.asset(
                'assets/app_icon.png',
                width: 24,
                height: 24,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.chat, color: Colors.white, size: 24),
              ),
            ),
            const Text(Constants.appName,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
            const Spacer(),
            Row(
              children: [
                _buildWindowButton(
                  icon: Icons.remove,
                  onPressed: () => windowManager.minimize(),
                  isHovering: _isHoveringMinimize,
                  isPressed: _isPressedMinimize,
                  onHoverChanged: (v) =>
                      setState(() => _isHoveringMinimize = v),
                  onPressedChanged: (v) =>
                      setState(() => _isPressedMinimize = v),
                ),
                _buildWindowButton(
                  icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
                  onPressed: () async {
                    if (_isMaximized)
                      await windowManager.unmaximize();
                    else
                      await windowManager.maximize();
                  },
                  isHovering: _isHoveringMaximize,
                  isPressed: _isPressedMaximize,
                  onHoverChanged: (v) =>
                      setState(() => _isHoveringMaximize = v),
                  onPressedChanged: (v) =>
                      setState(() => _isPressedMaximize = v),
                ),
                _buildWindowButton(
                  icon: Icons.close,
                  onPressed: () => windowManager.close(),
                  isHovering: _isHoveringClose,
                  isPressed: _isPressedClose,
                  onHoverChanged: (v) => setState(() => _isHoveringClose = v),
                  onPressedChanged: (v) => setState(() => _isPressedClose = v),
                  isClose: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWindowButton({
    required IconData icon,
    required VoidCallback onPressed,
    required bool isHovering,
    required bool isPressed,
    required Function(bool) onHoverChanged,
    required Function(bool) onPressedChanged,
    bool isClose = false,
  }) {
    Color getColor() => isPressed
        ? (isClose ? Colors.white : Colors.black)
        : isHovering
            ? (isClose ? Colors.white : Colors.black)
            : (isClose ? Colors.red : Colors.white);
    Color getBg() => isPressed
        ? (isClose ? Colors.red.shade800 : Colors.white.withOpacity(0.4))
        : isHovering
            ? (isClose ? Colors.red.shade600 : Colors.white.withOpacity(0.25))
            : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: GestureDetector(
        onTapDown: (_) => onPressedChanged(true),
        onTapUp: (_) {
          onPressedChanged(false);
          onPressed();
        },
        onTapCancel: () => onPressedChanged(false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
              color: getBg(), borderRadius: BorderRadius.circular(4)),
          child: Center(child: Icon(icon, color: getColor(), size: 18)),
        ),
      ),
    );
  }
}
