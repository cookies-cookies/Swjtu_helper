import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_windows/webview_windows.dart';

/// WebView 登录页面 - 提供手动复制 JSESSIONID 的指引
class WebViewLoginPage extends StatefulWidget {
  final String url;
  final Function(String jsessionid)? onJSessionIdObtained;

  const WebViewLoginPage({
    super.key,
    required this.url,
    this.onJSessionIdObtained,
  });

  @override
  State<WebViewLoginPage> createState() => _WebViewLoginPageState();
}

class _WebViewLoginPageState extends State<WebViewLoginPage> {
  final _controller = WebviewController();
  bool _isLoading = true;
  String _currentUrl = '';
  final TextEditingController _jsessionidController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  @override
  void dispose() {
    _jsessionidController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _initWebView() async {
    try {
      await _controller.initialize();

      await _controller.setUserAgent(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      );

      _controller.url.listen((url) {
        setState(() {
          _currentUrl = url;
          _isLoading = false;
        });

        // 检测登录成功
        if (url.contains('UserFramework') ||
            url.contains('UserLoadingAction')) {
          _showManualExtractGuide();
        }
      });

      await _controller.loadUrl(widget.url);
    } catch (e) {
      print('WebView 初始化错误: $e');
    }
  }

  /// 显示手动提取 JSESSIONID 的详细指引
  void _showManualExtractGuide() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue[700]),
            const SizedBox(width: 12),
            const Text('登录成功！'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '请按照以下步骤手动获取 JSESSIONID：',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),
              _buildStepCard(
                '方法 1：使用 Edge 浏览器',
                [
                  '1. 打开 Edge 浏览器',
                  '2. 访问 https://jwc.swjtu.edu.cn',
                  '3. 登录您的账号',
                  '4. 按 F12 打开开发者工具',
                  '5. 切换到 "应用程序" 或 "Application" 标签',
                  '6. 左侧展开 "Cookie"',
                  '7. 点击 jwc.swjtu.edu.cn',
                  '8. 找到 JSESSIONID，复制其值',
                ],
                Icons.web,
                Colors.blue,
              ),
              const SizedBox(height: 12),
              _buildStepCard(
                '方法 2：从此窗口复制',
                [
                  '1. 按 Ctrl+Shift+I 打开此 WebView 的开发者工具',
                  '2. 在 Console 中输入: document.cookie',
                  '3. 如果看不到 JSESSIONID（HttpOnly 保护）',
                  '4. 使用方法 1 从浏览器获取',
                ],
                Icons.code,
                Colors.green,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[300]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '注意：JSESSIONID 带有 HttpOnly 标志，'
                        'JavaScript 无法直接读取，必须手动获取。',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _showManualInputDialog();
            },
            icon: const Icon(Icons.edit),
            label: const Text('手动输入'),
          ),
        ],
      ),
    );
  }

  Widget _buildStepCard(
    String title,
    List<String> steps,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...steps.map(
            (step) => Padding(
              padding: const EdgeInsets.only(left: 28, top: 4),
              child: Text(
                step,
                style: const TextStyle(fontSize: 12, height: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 显示手动输入对话框
  void _showManualInputDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('输入 JSESSIONID'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _jsessionidController,
              decoration: const InputDecoration(
                labelText: 'JSESSIONID',
                border: OutlineInputBorder(),
                hintText: '粘贴从浏览器复制的值',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        _jsessionidController.text = data!.text!.trim();
                      }
                    },
                    icon: const Icon(Icons.paste),
                    label: const Text('粘贴'),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final jsessionId = _jsessionidController.text.trim();
              if (jsessionId.isNotEmpty) {
                if (widget.onJSessionIdObtained != null) {
                  widget.onJSessionIdObtained!(jsessionId);
                }
                Navigator.of(context).pop(); // 关闭输入对话框
                Navigator.of(context).pop(jsessionId); // 返回到登录页
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录教务系统'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showManualExtractGuide,
            tooltip: '如何获取 JSESSIONID',
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _showManualInputDialog,
            tooltip: '手动输入 JSESSIONID',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoading)
            const LinearProgressIndicator()
          else
            Container(height: 4, color: Colors.green),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.grey[100],
            child: Row(
              children: [
                const Icon(Icons.link, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _currentUrl.isEmpty ? '正在加载...' : _currentUrl,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: Webview(_controller)),
        ],
      ),
    );
  }
}
