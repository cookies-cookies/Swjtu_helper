import 'package:flutter/material.dart';
import '../services/jsessionid_service.dart';
import '../services/html_parser_service.dart';
import 'jsessionid_login_page.dart';
import 'student_info_page.dart';
import 'score_center_page.dart';
import 'course_selection_page.dart';
import 'auto_course_grab_page.dart';
import 'etp_test_page.dart';
import 'course_assess_page.dart';
import 'experiment_scores_page.dart';

/// 功能主页
class HomePage extends StatefulWidget {
  final JSessionIdService service;

  const HomePage({super.key, required this.service});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<String> _logs = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _appendLog('欢迎使用教务处系统');
    _drainServiceLogs();
  }

  void _appendLog(String line) {
    setState(() {
      final ts = DateTime.now().toIso8601String().substring(11, 19);
      _logs.add('[$ts] $line');
      if (_logs.length > 500) _logs.removeAt(0);
    });
  }

  void _drainServiceLogs() {
    final lines = widget.service.takeLogs();
    if (lines.isEmpty) return;
    setState(() {
      for (final l in lines) {
        final ts = DateTime.now().toIso8601String().substring(11, 19);
        _logs.add('[$ts] $l');
      }
      while (_logs.length > 500) _logs.removeAt(0);
    });
  }

  /// 检查登录状态
  Future<void> _checkStatus() async {
    setState(() => _isLoading = true);

    final isLoggedIn = await widget.service.isLoggedIn();
    _drainServiceLogs();

    setState(() => _isLoading = false);

    if (mounted) {
      _showMessage(isLoggedIn ? '当前已登录' : '会话已失效');

      if (!isLoggedIn) {
        _showLogoutDialog();
      }
    }
  }

  /// 获取学生信息
  Future<void> _getStudentInfo() async {
    setState(() => _isLoading = true);

    final content = await widget.service.getStudentInfo();
    _drainServiceLogs();

    setState(() => _isLoading = false);

    if (mounted) {
      if (content != null && content.isNotEmpty) {
        _appendLog('StudentInfo 长度: ${content.length}');

        // 解析并显示学生信息
        final studentInfo = HtmlParserService.parseStudentInfo(content);
        if (studentInfo != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => StudentInfoPage(studentInfo: studentInfo),
            ),
          );
        } else {
          _showMessage('解析学生信息失败');
          _appendLog('解析失败，原始内容长度: ${content.length}');
        }
      } else {
        _showMessage('获取失败，会话可能已失效');
      }
    }
  }

  /// 打开成绩中心
  void _openScoreCenter() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ScoreCenterPage(service: widget.service),
      ),
    );
  }

  /// 打开选课查询
  void _openCourseSelection() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CourseSelectionPage(service: widget.service),
      ),
    );
  }

  /// 打开实验教学平台测试
  void _openEtpTest() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => EtpTestPage(service: widget.service),
      ),
    );
  }

  /// 打开自动抢课
  void _openAutoCourseGrab() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AutoCourseGrabPage(service: widget.service),
      ),
    );
  }

  /// 打开课程评价页面
  void _openCourseAssess() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CourseAssessPage(jsessionService: widget.service),
      ),
    );
  }

  /// 打开实验成绩页面
  void _openExperimentScores() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const ExperimentScoresPage()),
    );
  }

  /// 退出登录
  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认退出'),
        content: const Text('确定要退出登录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.service.logout();
      _drainServiceLogs();

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const JSessionIdLoginPage()),
        );
      }
    }
  }

  /// 显示登出对话框（会话失效时）
  void _showLogoutDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('会话已失效'),
        content: const Text('您的 JSESSIONID 已过期，请重新登录。'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _logout();
            },
            child: const Text('重新登录'),
          ),
        ],
      ),
    );
  }

  /// 显示内容对话框
  void _showContentDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              content.length > 5000
                  ? '${content.substring(0, 5000)}\n\n...(内容过长，已截断)...'
                  : content,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 显示消息
  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('教务处功能系统'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: '退出登录',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('加载中...'),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 功能按钮区域
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '功能菜单',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _buildFunctionButton(
                                icon: Icons.info_outline,
                                label: '检查状态',
                                onPressed: _checkStatus,
                                color: Colors.blue,
                              ),
                              _buildFunctionButton(
                                icon: Icons.person,
                                label: '学生信息',
                                onPressed: _getStudentInfo,
                                color: Colors.orange,
                              ),
                              _buildFunctionButton(
                                icon: Icons.assessment,
                                label: '成绩中心',
                                onPressed: _openScoreCenter,
                                color: Colors.purple,
                              ),
                              _buildFunctionButton(
                                icon: Icons.class_,
                                label: '选课查询',
                                onPressed: _openCourseSelection,
                                color: Colors.teal,
                              ),
                              _buildFunctionButton(
                                icon: Icons.flash_on,
                                label: '自动抢课',
                                onPressed: _openAutoCourseGrab,
                                color: Colors.red,
                              ),
                              _buildFunctionButton(
                                icon: Icons.science,
                                label: '实验平台',
                                onPressed: _openEtpTest,
                                color: Colors.deepPurple,
                              ),
                              _buildFunctionButton(
                                icon: Icons.rate_review,
                                label: '自动课程评价',
                                onPressed: _openCourseAssess,
                                color: Colors.pink,
                              ),
                              _buildFunctionButton(
                                icon: Icons.biotech,
                                label: '实验成绩',
                                onPressed: _openExperimentScores,
                                color: Colors.green,
                              ),
                              _buildFunctionButton(
                                icon: Icons.clear_all,
                                label: '清空日志',
                                onPressed: () {
                                  setState(() {
                                    _logs.clear();
                                  });
                                  _appendLog('日志已清空');
                                },
                                color: Colors.purple,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // JSESSIONID 显示
                  Card(
                    elevation: 2,
                    child: ListTile(
                      leading: const Icon(Icons.vpn_key, color: Colors.blue),
                      title: const Text('当前 JSESSIONID'),
                      subtitle: Text(
                        widget.service.jsessionid ?? '未设置',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.visibility),
                        onPressed: () {
                          _showContentDialog(
                            'JSESSIONID',
                            widget.service.jsessionid ?? '未设置',
                          );
                        },
                        tooltip: '查看完整内容',
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 日志区域
                  Expanded(
                    child: Card(
                      elevation: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '操作日志',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                TextButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _logs.clear();
                                    });
                                    _appendLog('日志已清空');
                                  },
                                  icon: const Icon(Icons.clear_all, size: 16),
                                  label: const Text('清空'),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: _logs.isEmpty
                                ? const Center(
                                    child: Text(
                                      '暂无日志',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  )
                                : Container(
                                    color: Colors.grey[100],
                                    child: ListView.builder(
                                      padding: const EdgeInsets.all(8),
                                      itemCount: _logs.length,
                                      itemBuilder: (context, index) {
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 2,
                                          ),
                                          child: Text(
                                            _logs[index],
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildFunctionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  @override
  void dispose() {
    widget.service.dispose();
    super.dispose();
  }
}
