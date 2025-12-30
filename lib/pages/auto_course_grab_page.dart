import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;

import '../services/jsessionid_service.dart';

class AutoCourseGrabPage extends StatefulWidget {
  final JSessionIdService service;

  const AutoCourseGrabPage({super.key, required this.service});

  @override
  State<AutoCourseGrabPage> createState() => _AutoCourseGrabPageState();
}

class _AutoCourseGrabPageState extends State<AutoCourseGrabPage> {
  int _selectedIndex = 0;

  // Tab 0: 查询
  final TextEditingController _queryController = TextEditingController();
  String _querySelectAction = 'QueryName'; // QueryName / CourseCode / TeachID
  int _queryMode = 0; // 0=CourseStudentAction当前学期, 1=CourseAction下学期
  bool _querying = false;
  List<_CourseRow> _queryRows = [];
  String? _queryError;

  // Tab 1: 自动抢课
  final TextEditingController _batchController = TextEditingController();
  bool _running = false;
  Timer? _timer;
  final List<_GrabTask> _tasks = [];

  static const int _maxParallelRequests = 6;
  static const Duration _perRequestTimeout = Duration(seconds: 90);

  @override
  void dispose() {
    _timer?.cancel();
    _queryController.dispose();
    _batchController.dispose();
    super.dispose();
  }

  void _onNavChanged(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _runQuery() async {
    final keyword = _queryController.text.trim();
    if (keyword.isEmpty) {
      setState(() => _queryError = '请输入课程码/课程名关键字');
      return;
    }

    setState(() {
      _querying = true;
      _queryError = null;
      _queryRows = [];
    });

    try {
      final html = _queryMode == 0
          ? await widget.service.postCourseStudentSysScheduleQuery(
              keyword,
              jumpPage: 1,
              courseType: 'all',
              selectAction: _querySelectAction,
            )
          : await widget.service.getCourseActionQueryNextTerm(
              keyword,
              selectAction: _querySelectAction,
            );
      if (!mounted) return;

      setState(() {
        _querying = false;
        if (html == null || html.isEmpty) {
          _queryError = '查询失败或返回空内容（请检查登录状态/JSESSIONID）';
        } else {
          _queryRows = _queryMode == 0
              ? _parseCourseRows(html)
              : _parseCourseActionRows(html);
          if (_queryRows.isEmpty) {
            if (html.contains('没有找到可选课程') || html.contains('未查询到相关数据')) {
              _queryError = '没有找到可选课程（请检查关键字/查询方式）';
            } else {
              _queryError = '未解析到课程列表（可能当前页结构变化）';
            }
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _querying = false;
        _queryError = '查询失败: $e';
      });
    }
  }

  void _buildTasksFromInput() {
    final lines = _batchController.text
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    setState(() {
      for (final k in lines) {
        final exists = _tasks.any((t) => t.keyword == k);
        if (!exists) {
          _tasks.add(
            _GrabTask(
              keyword: k,
              status: _TaskStatus.pending,
              message: null,
              lastUpdate: null,
              lastRequest: null,
            ),
          );
        }
      }
    });
  }

  void _start() {
    // 合并文本输入与“搜索页添加”的清单
    _buildTasksFromInput();
    if (_tasks.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先输入要抢的课程关键字（每行一个）')));
      return;
    }

    setState(() {
      _running = true;
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      if (!_running) return;
      await _tick();
    });

    // 立即跑一轮
    _tick();
  }

  void _stop() {
    setState(() => _running = false);
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (!_running) return;

    final pending = _tasks
        .where((t) => t.status != _TaskStatus.success)
        .toList();
    if (pending.isEmpty) {
      _stop();
      return;
    }

    final sem = _AsyncSemaphore(_maxParallelRequests);
    await Future.wait(
      pending.map(
        (t) => sem.withPermit(() async {
          if (!_running) return;
          await _processTask(t);
        }),
      ),
    );

    // 如果都成功了，自动停止
    final allDone =
        _tasks.isNotEmpty &&
        _tasks.every((t) => t.status == _TaskStatus.success);
    if (allDone) {
      _stop();
    }
  }

  String _maskedCookie() {
    final js = widget.service.jsessionid;
    if (js == null || js.isEmpty) return 'JSESSIONID=<empty>';
    final head = js.length <= 8 ? js : js.substring(0, 8);
    return 'JSESSIONID=$head...';
  }

  String _buildQueryRequestDebug({
    required String keyword,
    required String selectAction,
    int jumpPage = 1,
    String courseType = 'all',
  }) {
    final form = <String, String>{
      'setAction': 'studentCourseSysSchedule',
      'viewType': '',
      'jumpPage': jumpPage.toString(),
      'selectAction': selectAction,
      'key1': keyword,
      'courseType': courseType,
      'key4': '',
      'btn': '执行查询',
    };
    final body = form.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
    return [
      'POST http://jwc.swjtu.edu.cn/vatuu/CourseStudentAction',
      'Headers: Content-Type=application/x-www-form-urlencoded; Origin=http://jwc.swjtu.edu.cn; Referer=http://jwc.swjtu.edu.cn/vatuu/CourseStudentAction?setAction=studentCourseSysSchedule; Cookie(${_maskedCookie()})',
      'Body: $body',
    ].join('\n');
  }

  String _buildApplyRequestDebug({
    required String teachIdChoose,
    required String isBook,
    required String referer,
  }) {
    final tt = DateTime.now().millisecondsSinceEpoch;
    final url =
        'http://jwc.swjtu.edu.cn/vatuu/CourseStudentAction?setAction=addStudentCourseApply&teachId=${Uri.encodeQueryComponent(teachIdChoose)}&isBook=${Uri.encodeQueryComponent(isBook)}&tt=$tt';
    return [
      'GET $url',
      'Headers: Accept=*/*; Referer=$referer; Cookie(${_maskedCookie()})',
    ].join('\n');
  }

  Future<void> _processTask(_GrabTask task) async {
    if (!_running) return;

    try {
      // 如果已经有 teachIdChoose（从搜索页“添加”得到），直接提交选课申请，不需要反复查询。
      final directTeachIdChoose = task.teachIdChoose?.trim();
      if (directTeachIdChoose != null && directTeachIdChoose.isNotEmpty) {
        final referer =
            'http://jwc.swjtu.edu.cn/vatuu/CourseStudentAction?setAction=${task.refererSetAction ?? 'studentCourseSysSchedule'}';
        final req = _buildApplyRequestDebug(
          teachIdChoose: directTeachIdChoose,
          isBook: task.isBook ?? '1',
          referer: referer,
        );

        if (mounted) {
          setState(() {
            task.status = _TaskStatus.running;
            task.lastUpdate = DateTime.now();
            task.lastRequest = req;
            task.message = '直接提交选课申请...';
          });
        }

        final res = await widget.service
            .addStudentCourseApply(
              teachId: directTeachIdChoose,
              isBook: task.isBook ?? '1',
              referer: referer,
            )
            .timeout(_perRequestTimeout);

        if (res == null || res.isEmpty) {
          if (mounted) {
            setState(() {
              task.status = _TaskStatus.failed;
              task.lastUpdate = DateTime.now();
              task.message = '提交失败/空响应';
            });
          }
          return;
        }

        final ok =
            res.contains('成功') && !res.contains('失败') && !res.contains('您还未登陆');
        if (mounted) {
          setState(() {
            task.lastUpdate = DateTime.now();
            task.status = ok ? _TaskStatus.success : _TaskStatus.pending;
            task.message = ok ? '提交成功（命中“成功”关键字）' : '已提交但未判定成功（会自动重试）';
          });
        }
        return;
      }

      final selectAction = _inferSelectAction(task.keyword);
      final queryReq = _buildQueryRequestDebug(
        keyword: task.keyword,
        selectAction: selectAction,
      );

      if (mounted) {
        setState(() {
          task.status = _TaskStatus.running;
          task.lastUpdate = DateTime.now();
          task.lastRequest = queryReq;
          task.message = '查询中...';
        });
      }

      final q = await widget.service
          .postCourseStudentSysScheduleQuery(
            task.keyword,
            jumpPage: 1,
            courseType: 'all',
            selectAction: selectAction,
          )
          .timeout(_perRequestTimeout);

      if (q == null || q.isEmpty) {
        if (mounted) {
          setState(() {
            task.status = _TaskStatus.failed;
            task.lastUpdate = DateTime.now();
            task.message = '查询失败/空响应';
          });
        }
        return;
      }

      // 从查询结果里提取 teachIdChoose（隐藏值），并尽量补齐课程代码等信息
      final matchedRow = _findCourseRow(q, task.keyword);
      final teachIdChoose =
          matchedRow?.teachIdChoose ?? _extractTeachIdChoose(q, task.keyword);
      if (teachIdChoose == null) {
        if (mounted) {
          setState(() {
            task.status = _TaskStatus.pending;
            task.lastUpdate = DateTime.now();
            task.message = '未找到 teachIdChoose（仅查询成功）';
          });
        }
        return;
      }

      if (matchedRow != null) {
        if (mounted) {
          setState(() {
            task.courseCode = matchedRow.courseCode;
            task.courseName = matchedRow.courseName;
            task.teachId = matchedRow.teachId;
            task.teachClassId = matchedRow.teachClassId;
            task.teacherName = matchedRow.teacherName;
            task.timePlace = matchedRow.timePlace;
            task.teachIdChoose = matchedRow.teachIdChoose;
            task.refererSetAction = 'studentCourseSysSchedule';
          });
        }
      } else {
        task.teachIdChoose = teachIdChoose;
        task.refererSetAction = 'studentCourseSysSchedule';
      }

      final referer =
          'http://jwc.swjtu.edu.cn/vatuu/CourseStudentAction?setAction=${task.refererSetAction ?? 'studentCourseSysSchedule'}';
      final applyReq = _buildApplyRequestDebug(
        teachIdChoose: teachIdChoose,
        isBook: task.isBook ?? '1',
        referer: referer,
      );

      if (mounted) {
        setState(() {
          task.lastRequest = applyReq;
          task.message = '已解析 teachId，尝试提交选课申请...';
        });
      }

      final res = await widget.service
          .addStudentCourseApply(
            teachId: teachIdChoose,
            isBook: task.isBook ?? '1',
            referer: referer,
          )
          .timeout(_perRequestTimeout);

      if (res == null || res.isEmpty) {
        if (mounted) {
          setState(() {
            task.status = _TaskStatus.failed;
            task.lastUpdate = DateTime.now();
            task.message = '提交失败/空响应';
          });
        }
        return;
      }

      final ok =
          res.contains('成功') && !res.contains('失败') && !res.contains('您还未登陆');
      if (mounted) {
        setState(() {
          task.lastUpdate = DateTime.now();
          task.status = ok ? _TaskStatus.success : _TaskStatus.pending;
          task.message = ok ? '提交成功（命中“成功”关键字）' : '已提交但未判定成功（会自动重试）';
        });
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          task.status = _TaskStatus.pending;
          task.lastUpdate = DateTime.now();
          task.message = '请求超时（服务器可能很卡，自动重试）';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          task.status = _TaskStatus.failed;
          task.lastUpdate = DateTime.now();
          task.message = '异常: $e';
        });
      }
    }
  }

  String? _extractTeachIdChoose(String pageHtml, String keyword) {
    try {
      final doc = html.parse(pageHtml);
      final rows = doc.querySelectorAll('#table3 tr');
      if (rows.isEmpty) return null;

      // 关键字可能是：选课编号(A1298)、课程代码(JYZX000115)、课程名(职业生涯规划)
      final q = keyword.trim();

      for (final row in rows.skip(1)) {
        final idSpan = row.querySelector('span[id^="teachIdChoose"]');
        if (idSpan == null) continue;

        final chooseId = idSpan.text.trim();
        if (chooseId.isEmpty) continue;

        final teachId =
            row.querySelector('span[id^="teachId"]')?.text.trim() ?? '';
        final courseCode =
            row.querySelector('span[id^="courseCode"]')?.text.trim() ?? '';
        final courseName =
            row.querySelector('span[id^="courseName"]')?.text.trim() ?? '';

        if (teachId == q || courseCode == q || courseName.contains(q)) {
          return chooseId;
        }
      }

      // 如果没有精确匹配，就退化：取第一条（用户的查询通常已过滤）
      final first = rows.skip(1).first;
      return first.querySelector('span[id^="teachIdChoose"]')?.text.trim();
    } catch (_) {
      return null;
    }
  }

  String _inferSelectAction(String keyword) {
    final k = keyword.trim();
    if (RegExp(r'^[A-Za-z]\d{3,}$').hasMatch(k)) {
      return 'TeachID';
    }
    if (RegExp(r'^[A-Za-z]{2,}\d{3,}$').hasMatch(k)) {
      return 'CourseCode';
    }
    return 'QueryName';
  }

  _CourseRow? _findCourseRow(String pageHtml, String keyword) {
    final rows = _parseCourseRows(pageHtml);
    if (rows.isEmpty) return null;

    final q = keyword.trim();
    for (final r in rows) {
      if (r.teachId == q || r.courseCode == q || r.courseName.contains(q)) {
        return r;
      }
    }
    return rows.first;
  }

  void _addToGrabList(_CourseRow r) {
    final exists = _tasks.any((t) => t.teachIdChoose == r.teachIdChoose);
    if (exists) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已在清单中：${r.courseCode}')));
      setState(() => _selectedIndex = 1);
      return;
    }

    setState(() {
      _tasks.add(
        _GrabTask(
          keyword: r.courseCode.isNotEmpty ? r.courseCode : r.courseName,
          courseCode: r.courseCode,
          courseName: r.courseName,
          teachId: r.teachId,
          teachIdChoose: r.teachIdChoose,
          teachClassId: r.teachClassId,
          teacherName: r.teacherName,
          timePlace: r.timePlace,
          refererSetAction: 'studentCourseSysSchedule',
          isBook: '1',
          status: _TaskStatus.pending,
          message: null,
          lastUpdate: null,
          lastRequest: null,
        ),
      );
      _selectedIndex = 1;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已添加到自动抢课：${r.courseCode}')));
  }

  List<_CourseRow> _parseCourseRows(String pageHtml) {
    try {
      final doc = html.parse(pageHtml);
      final rows = doc.querySelectorAll('#table3 tr');
      if (rows.length <= 1) return [];

      final result = <_CourseRow>[];
      for (final row in rows.skip(1)) {
        final teachIdChoose = row
            .querySelector('span[id^="teachIdChoose"]')
            ?.text
            .trim();
        final teachId = row.querySelector('span[id^="teachId"]')?.text.trim();
        final courseCode = row
            .querySelector('span[id^="courseCode"]')
            ?.text
            .trim();
        final courseName = row
            .querySelector('span[id^="courseName"]')
            ?.text
            .trim();
        final teachClassId = row
            .querySelector('span[id^="teachClassId"]')
            ?.text
            .trim();
        final teacherName = row
            .querySelector('span[id^="teacherName"]')
            ?.text
            .trim();
        final timePlace = row.querySelectorAll('td').length >= 11
            ? row.querySelectorAll('td')[10].text.trim()
            : null;
        final statusText = row.querySelectorAll('td').isNotEmpty
            ? row.querySelectorAll('td').last.text.trim()
            : null;

        if ((teachIdChoose ?? '').isEmpty) continue;
        result.add(
          _CourseRow(
            teachIdChoose: teachIdChoose!,
            teachId: teachId ?? '',
            courseCode: courseCode ?? '',
            courseName: courseName ?? '',
            teachClassId: teachClassId ?? '',
            teacherName: teacherName ?? '',
            timePlace: timePlace,
            statusText: statusText,
          ),
        );
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  List<_CourseRow> _parseCourseActionRows(String pageHtml) {
    try {
      final doc = html.parse(pageHtml);
      final rows = doc.querySelectorAll('table tr');
      if (rows.length <= 1) return [];

      final result = <_CourseRow>[];
      for (final row in rows.skip(1)) {
        final tds = row.querySelectorAll('td');
        if (tds.length < 13) continue;

        // 提取课程代码（第3列的链接）
        final courseCodeLink = tds[2].querySelector('a');
        final courseCode = courseCodeLink?.text.trim() ?? '';

        // 提取课程名称（第4列的链接）
        final courseNameLink = tds[3].querySelector('a');
        final courseName = courseNameLink?.text.trim() ?? '';

        // 提取选课编号（teachId，第2列）
        final teachClassId = tds[1].querySelector('a')?.text.trim() ?? '';

        // 提取教师（第9列）
        final teacherName = tds[8].querySelector('a')?.text.trim() ?? '';

        // 提取时间地点（第11列）
        final timePlace = tds[10].text.trim();

        // 提取 key1 参数作为 teachIdChoose（从"名单"链接里提取）
        final listLink = tds[tds.length - 1].querySelector(
          'a[href*="courseStudentList"]',
        );
        String? teachIdChoose;
        if (listLink != null) {
          final href = listLink.attributes['href'] ?? '';
          final key1Match = RegExp(r'key1=([A-F0-9]+)').firstMatch(href);
          if (key1Match != null) {
            teachIdChoose = key1Match.group(1);
          }
        }

        if (teachIdChoose == null || teachIdChoose.isEmpty) continue;

        result.add(
          _CourseRow(
            teachIdChoose: teachIdChoose,
            teachId: teachClassId,
            courseCode: courseCode,
            courseName: courseName,
            teachClassId: teachClassId,
            teacherName: teacherName,
            timePlace: timePlace.isEmpty ? null : timePlace,
            statusText: null,
          ),
        );
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('自动抢课')),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _onNavChanged,
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.search),
                label: Text('课程码搜索'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.play_circle_outline),
                label: Text('自动抢课'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _selectedIndex == 0 ? _buildQueryPane() : _buildGrabPane(),
          ),
        ],
      ),
    );
  }

  Widget _buildQueryPane() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '课程码/名称搜索',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('学期：'),
              const SizedBox(width: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('当前学期')),
                  ButtonSegment(value: 1, label: Text('下学期')),
                ],
                selected: {_queryMode},
                onSelectionChanged: _querying
                    ? null
                    : (v) {
                        setState(() => _queryMode = v.first);
                      },
              ),
              const SizedBox(width: 16),
              const Text('查询方式：'),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _querySelectAction,
                items: const [
                  DropdownMenuItem(value: 'QueryName', child: Text('按课程名称')),
                  DropdownMenuItem(value: 'CourseCode', child: Text('按课程代码')),
                  DropdownMenuItem(value: 'TeachID', child: Text('按选课编号')),
                ],
                onChanged: _querying
                    ? null
                    : (v) {
                        if (v == null) return;
                        setState(() => _querySelectAction = v);
                      },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _queryController,
                  decoration: const InputDecoration(
                    labelText: '关键字（课程码/课程名）',
                    hintText: '例如：职业生涯规划',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _runQuery(),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _querying ? null : _runQuery,
                icon: _querying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(_querying ? '查询中...' : '查询'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_queryError != null)
            Text(_queryError!, style: const TextStyle(color: Colors.red)),
          if (_queryRows.isNotEmpty) ...[
            Text('解析到 ${_queryRows.length} 条结果（包含课程代码）'),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: _queryRows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final r = _queryRows[index];
                  return ListTile(
                    title: Text('${r.courseCode}  ${r.courseName}'),
                    subtitle: Text(
                      '选课编号: ${r.teachId}  教学班号: ${r.teachClassId}\n'
                      '教师: ${r.teacherName}${r.timePlace == null || r.timePlace!.isEmpty ? '' : '\n${r.timePlace}'}',
                    ),
                    trailing: ElevatedButton(
                      onPressed: () async {
                        _addToGrabList(r);
                      },
                      child: const Text('添加'),
                    ),
                  );
                },
              ),
            ),
          ] else
            const Expanded(child: Center(child: Text('输入关键字后点击查询'))),
        ],
      ),
    );
  }

  Widget _buildGrabPane() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '自动抢课',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '可在“课程码搜索”页点【添加】累加到清单；也可手动输入每行一个关键字。',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _batchController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '要抢的课程关键字（每行一个）',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (!_running) {
                _buildTasksFromInput();
              }
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _running ? null : _start,
                icon: const Icon(Icons.play_arrow),
                label: const Text('开始'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _running ? _stop : null,
                icon: const Icon(Icons.stop),
                label: const Text('停止'),
              ),
              const SizedBox(width: 12),
              Text(_running ? '状态：运行中' : '状态：未运行'),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _tasks.isEmpty
                ? const Center(child: Text('暂无任务'))
                : ListView.separated(
                    itemCount: _tasks.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final t = _tasks[index];
                      return ListTile(
                        leading: _statusIcon(t.status),
                        title: Text(
                          (t.courseCode != null && t.courseCode!.isNotEmpty)
                              ? '${t.courseCode}  ${t.courseName ?? ''}'.trim()
                              : t.keyword,
                        ),
                        subtitle: Text(_formatSubtitle(t)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statusIcon(_TaskStatus s) {
    switch (s) {
      case _TaskStatus.success:
        return const Icon(Icons.check_circle, color: Colors.green);
      case _TaskStatus.running:
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case _TaskStatus.failed:
        return const Icon(Icons.error, color: Colors.red);
      case _TaskStatus.pending:
        return const Icon(Icons.hourglass_empty, color: Colors.grey);
    }
  }

  String _formatSubtitle(_GrabTask t) {
    final ts = t.lastUpdate == null
        ? '未开始'
        : t.lastUpdate!.toIso8601String().substring(11, 19);
    final parts = <String>[];
    if (t.teachId != null && t.teachId!.isNotEmpty) {
      parts.add('选课编号:${t.teachId}');
    }
    if (t.teachClassId != null && t.teachClassId!.isNotEmpty) {
      parts.add('班号:${t.teachClassId}');
    }
    if (t.teacherName != null && t.teacherName!.isNotEmpty) {
      parts.add('教师:${t.teacherName}');
    }
    final meta = parts.isEmpty ? '' : '（${parts.join('  ')}）';
    final req = (t.lastRequest ?? '').trim();
    if (req.isEmpty) {
      return '[$ts] ${t.message ?? ''}$meta';
    }
    return '[$ts] ${t.message ?? ''}$meta\n$req';
  }
}

class _AsyncSemaphore {
  int _available;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  _AsyncSemaphore(this._available);

  Future<T> withPermit<T>(Future<T> Function() action) async {
    await _acquire();
    try {
      return await action();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_available > 0) {
      _available--;
      return Future.value();
    }
    final c = Completer<void>();
    _waiters.add(c);
    return c.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    } else {
      _available++;
    }
  }
}

enum _TaskStatus { pending, running, success, failed }

class _GrabTask {
  final String keyword;
  String? courseCode;
  String? courseName;
  String? teachId;
  String? teachIdChoose;
  String? teachClassId;
  String? teacherName;
  String? timePlace;
  String? refererSetAction;
  String? isBook;
  String? lastRequest;
  _TaskStatus status;
  String? message;
  DateTime? lastUpdate;

  _GrabTask({
    required this.keyword,
    this.courseCode,
    this.courseName,
    this.teachId,
    this.teachIdChoose,
    this.teachClassId,
    this.teacherName,
    this.timePlace,
    this.refererSetAction,
    this.isBook,
    this.lastRequest,
    this.status = _TaskStatus.pending,
    this.message,
    this.lastUpdate,
  });
}

class _CourseRow {
  final String teachIdChoose;
  final String teachId;
  final String courseCode;
  final String courseName;
  final String teachClassId;
  final String teacherName;
  final String? timePlace;
  final String? statusText;

  _CourseRow({
    required this.teachIdChoose,
    required this.teachId,
    required this.courseCode,
    required this.courseName,
    required this.teachClassId,
    required this.teacherName,
    required this.timePlace,
    required this.statusText,
  });
}
