import 'package:flutter/material.dart';
import '../services/course_assess_service.dart';
import '../services/jsessionid_service.dart';
import '../services/assess_parser_service.dart';

/// 课程评价页面
class CourseAssessPage extends StatefulWidget {
  final JSessionIdService jsessionService;

  const CourseAssessPage({super.key, required this.jsessionService});

  @override
  State<CourseAssessPage> createState() => _CourseAssessPageState();
}

class _CourseAssessPageState extends State<CourseAssessPage> {
  final CourseAssessService _assessService = CourseAssessService();
  final List<String> _logs = [];
  List<Map<String, String>> _courses = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _assessService.setJSessionId(widget.jsessionService.jsessionid!);

    // 设置百度统计Cookie（这些Cookie在浏览器中自动设置，我们手动添加）
    final now = (DateTime.now().millisecondsSinceEpoch / 1000).floor();
    _assessService.setExtraCookies({
      'Hm_lvt_87cf2c3472ff749fe7d2282b7106e8f1': '$now',
      'Hm_lpvt_87cf2c3472ff749fe7d2282b7106e8f1': '$now',
      'HMACCOUNT': '322FEB6B5A01DF04', // 固定值
    });

    _addLog('课程评价页面已加载');
  }

  void _addLog(String log) {
    setState(() {
      final ts = DateTime.now().toIso8601String().substring(11, 19);
      _logs.add('[$ts] $log');
      if (_logs.length > 200) _logs.removeAt(0);
    });
  }

  void _drainServiceLogs() {
    final logs = _assessService.takeLogs();
    for (final log in logs) {
      _addLog(log);
    }
  }

  /// 获取待评价课程列表
  Future<void> _fetchAssessmentList() async {
    setState(() {
      _isLoading = true;
      _courses = [];
    });
    _addLog('开始获取待评价课程列表...');

    final html = await _assessService.getAssessmentList();
    _drainServiceLogs();

    if (html != null) {
      _addLog('✅ 成功获取课程列表');
      _addLog('HTML 已保存到 debug_assess_list.html');

      // 解析课程列表
      final courses = AssessParserService.parseCourseList(html);
      if (courses != null && courses.isNotEmpty) {
        setState(() {
          _courses = courses;
        });
        _addLog('解析到 ${courses.length} 门课程');

        // 统计待评价数量
        final pendingCount = courses
            .where((c) => c['assessStatus'] == '待评价')
            .length;
        final completedCount = courses.length - pendingCount;
        _addLog('待评价: $pendingCount 门，已完成: $completedCount 门');

        _showMessage('成功获取 ${courses.length} 门课程');
      } else {
        _addLog('❌ 未解析到课程数据');
        _showMessage('未找到课程数据');
      }
    } else {
      _addLog('❌ 获取失败');
      _showMessage('获取失败，请检查日志');
    }

    setState(() => _isLoading = false);
  }

  /// 评价单门课程
  Future<void> _assessCourse(Map<String, String> course) async {
    final courseName = course['courseName']!;
    final sid = course['sid']!;
    final lid = course['lid']!;
    final templateFlag = int.tryParse(course['templateFlag'] ?? '0') ?? 0;

    if (sid.isEmpty || lid.isEmpty) {
      _addLog('[ERROR] 课程参数不完整');
      _showMessage('课程参数错误');
      return;
    }

    // 确保Cookie设置正确（每次提交前重新设置）
    final now = (DateTime.now().millisecondsSinceEpoch / 1000).floor();
    _assessService.setExtraCookies({
      'Hm_lvt_87cf2c3472ff749fe7d2282b7106e8f1': '$now',
      'Hm_lpvt_87cf2c3472ff749fe7d2282b7106e8f1': '$now',
      'HMACCOUNT': '322FEB6B5A01DF04',
    });

    // 确认对话框
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认评价'),
        content: Text('确定要自动评价《$courseName》吗？\n\n将自动填写满分评价。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    _addLog('开始评价: $courseName');

    final success = await _assessService.autoAssessCourse(
      sid: sid,
      lid: lid,
      templateFlag: templateFlag,
      testMode: false, // 🔴 测试模式:只输出数据,不实际提交
    );

    _drainServiceLogs();

    if (success) {
      _addLog('✅ 评价成功: $courseName');
      _showMessage('评价成功！');

      // 刷新列表
      await Future.delayed(const Duration(milliseconds: 500));
      await _fetchAssessmentList();
    } else {
      _addLog('❌ 评价失败: $courseName');
      _showMessage('评价失败，请查看日志');
    }

    setState(() => _isLoading = false);
  }

  /// 一键评价全部待评价课程（并行处理）
  Future<void> _assessAllPending() async {
    final pendingCourses = _courses
        .where((c) => c['assessStatus'] == '待评价')
        .toList();

    if (pendingCourses.isEmpty) {
      _showMessage('没有待评价的课程');
      return;
    }

    // 确认对话框
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认批量评价'),
        content: Text(
          '确定要自动评价全部 ${pendingCourses.length} 门课程吗？\n\n'
          '所有课程将同时开始处理（每个等待65秒后提交）。',
        ),
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

    if (confirm != true) return;

    setState(() => _isLoading = true);
    _addLog('🚀 开始并行评价 ${pendingCourses.length} 门课程（同时处理）');

    // 并行执行所有评价任务
    final results = await Future.wait(
      pendingCourses.map((course) async {
        final courseName = course['courseName']!;
        final sid = course['sid']!;
        final lid = course['lid']!;
        final templateFlag = int.tryParse(course['templateFlag'] ?? '0') ?? 0;

        _addLog('开始: $courseName');

        final success = await _assessService.autoAssessCourse(
          sid: sid,
          lid: lid,
          templateFlag: templateFlag,
          testMode: false,
        );

        _drainServiceLogs();

        if (success) {
          _addLog('✅ 成功: $courseName');
        } else {
          _addLog('❌ 失败: $courseName');
        }

        return success;
      }),
    );

    final successCount = results.where((r) => r).length;
    final failCount = results.where((r) => !r).length;

    _addLog('批量评价完成: 成功 $successCount 门，失败 $failCount 门');
    _showMessage('完成！成功 $successCount 门，失败 $failCount 门');

    // 刷新列表
    await Future.delayed(const Duration(milliseconds: 500));
    await _fetchAssessmentList();

    setState(() => _isLoading = false);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  void dispose() {
    _assessService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('自动课程评价'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 功能按钮
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '评价功能',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _isLoading ? null : _fetchAssessmentList,
                          icon: const Icon(Icons.list, size: 18),
                          label: const Text('获取待评价课程'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        if (_courses.any((c) => c['assessStatus'] == '待评价'))
                          ElevatedButton.icon(
                            onPressed: _isLoading ? null : _assessAllPending,
                            icon: const Icon(Icons.auto_awesome, size: 18),
                            label: const Text('一键评价全部'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() => _logs.clear());
                            _addLog('日志已清空');
                          },
                          icon: const Icon(Icons.clear_all, size: 18),
                          label: const Text('清空日志'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 课程列表显示
            if (_courses.isNotEmpty)
              Expanded(
                child: Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(4),
                            topRight: Radius.circular(4),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.school, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              '课程列表（共 ${_courses.length} 门）',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(6),
                          itemCount: _courses.length,
                          itemBuilder: (context, index) {
                            final course = _courses[index];
                            final isPending = course['assessStatus'] == '待评价';

                            return Card(
                              margin: const EdgeInsets.only(bottom: 6),
                              color: isPending
                                  ? Colors.orange[50]
                                  : Colors.green[50],
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isPending
                                                ? Colors.orange
                                                : Colors.green,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            course['assessStatus']!,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            course['courseName']!,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    _buildCourseInfo(
                                      '选课编号',
                                      course['courseId']!,
                                    ),
                                    _buildCourseInfo(
                                      '教学班号',
                                      course['classNumber']!,
                                    ),
                                    if (isPending)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: ElevatedButton.icon(
                                          onPressed: _isLoading
                                              ? null
                                              : () => _assessCourse(course),
                                          icon: const Icon(
                                            Icons.edit,
                                            size: 16,
                                          ),
                                          label: const Text('填写评价'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.orange,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            minimumSize: Size.zero,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // 日志区域
            if (_courses.isEmpty)
              Expanded(
                child: Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(4),
                            topRight: Radius.circular(4),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.terminal, size: 18),
                            const SizedBox(width: 8),
                            const Text(
                              '操作日志',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            if (_isLoading)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _logs.isEmpty
                            ? const Center(child: Text('暂无日志'))
                            : ListView.builder(
                                padding: const EdgeInsets.all(8),
                                itemCount: _logs.length,
                                itemBuilder: (context, index) {
                                  final log = _logs[index];
                                  return SelectableText(
                                    log,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                      color: log.contains('[ERROR]')
                                          ? Colors.red
                                          : log.contains('✅')
                                          ? Colors.green
                                          : log.contains('[WARN]')
                                          ? Colors.orange
                                          : null,
                                    ),
                                  );
                                },
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

  Widget _buildCourseInfo(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 65,
            child: Text(
              '$label:',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
