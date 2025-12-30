import 'package:flutter/material.dart';
import 'dart:io';
import '../models/course_selection.dart';
import '../services/jsessionid_service.dart';
import '../services/html_parser_service.dart';
import '../services/course_table_parser_service.dart';
import 'class_schedule_page.dart';

/// 选课查询页面
class CourseSelectionPage extends StatefulWidget {
  final JSessionIdService service;

  const CourseSelectionPage({super.key, required this.service});

  @override
  State<CourseSelectionPage> createState() => _CourseSelectionPageState();
}

/// 小型导航项类（用于左侧菜单）
class _NavItem {
  final IconData icon;
  final String title;
  final String description;

  _NavItem({
    required this.icon,
    required this.title,
    required this.description,
  });
}

class _CourseSelectionPageState extends State<CourseSelectionPage> {
  bool _isLoading = false;
  CourseSelection? _courseSelection;
  String? _errorMsg;
  String _viewMode = 'list'; // 'list' 或 'week'
  int _selectedIndex = 0;
  final TextEditingController _classKeyController = TextEditingController();
  bool _querying = false;
  CourseTable? _scheduleTable; // 保存解析后的课表
  String? _queryError;
  String? _requestUrl; // 保存构造的请求URL

  @override
  void dispose() {
    _classKeyController.dispose();
    super.dispose();
  }

  // 切换菜单项时清空课表缓存
  void _onNavItemChanged(int index) {
    setState(() {
      _selectedIndex = index;
      _scheduleTable = null;
      _queryError = null;
      _requestUrl = null;
      _querying = false;
    });
  }

  final List<_NavItem> _navItems = [
    _NavItem(icon: Icons.list, title: '本学期选课', description: '查看本学期课程列表'),
    _NavItem(
      icon: Icons.calendar_today,
      title: '本学期课表',
      description: '查询班级本学期课表',
    ),
    _NavItem(
      icon: Icons.calendar_month,
      title: '下学期课表',
      description: '查询班级下学期课表',
    ),
    _NavItem(icon: Icons.history, title: '历史选课记录', description: '查看往期选课记录'),
    _NavItem(icon: Icons.list_alt, title: '选课日志查询', description: '查看选课操作日志'),
  ];

  @override
  void initState() {
    super.initState();
    _loadCourseSelection();
  }

  Future<void> _loadCourseSelection() async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      final html = await widget.service.getCourseSelection();
      if (html == null) {
        setState(() {
          _errorMsg = '获取选课信息失败，请检查网络或重新登录';
          _isLoading = false;
        });
        return;
      }

      // 保存HTML以便分析
      try {
        final file = File('debug_course_selection_detailed.html');
        await file.writeAsString(html);
        print('[DEBUG] 选课页面HTML已保存到: ${file.absolute.path}');
      } catch (e) {
        print('[WARN] 保存HTML失败: $e');
      }

      final courseSelection = HtmlParserService.parseCourseSelection(html);
      if (courseSelection == null || courseSelection.courses.isEmpty) {
        setState(() {
          _errorMsg = '解析选课数据失败或本学期暂无选课';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _courseSelection = courseSelection;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMsg = '获取选课信息失败: $e';
        _isLoading = false;
      });
    }
  }

  /// 构建课表查询页面（本学期或下学期）
  Widget _buildScheduleQueryPage({required bool isNextSemester}) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _navItems[_selectedIndex].title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _navItems[_selectedIndex].description,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _classKeyController,
                  decoration: const InputDecoration(
                    labelText: '班级关键字',
                    hintText: '例如：电子2024-01班',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _querying
                    ? null
                    : () =>
                          _queryAndShowSchedule(isNextSemester: isNextSemester),
                icon: _querying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(_querying ? '查询中...' : '查询课表'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_requestUrl != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.link, color: Colors.blue[700], size: 18),
                      const SizedBox(width: 8),
                      Text(
                        '请求URL：',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[800],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _requestUrl!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue[900],
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_queryError != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _queryError!,
                      style: TextStyle(color: Colors.red[700]),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_scheduleTable != null) ...[
            const Divider(),
            const SizedBox(height: 12),
            Text(
              '课表信息（${_scheduleTable!.slots.length} 门课程）',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ClassSchedulePage(table: _scheduleTable!, embedded: true),
            ),
          ] else if (!_querying)
            const Expanded(
              child: Center(
                child: Text(
                  '输入班级关键字后点击查询',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 查询并显示班级课表（合并功能）
  /// [isNextSemester] 为 true 时查询下学期
  Future<void> _queryAndShowSchedule({bool isNextSemester = false}) async {
    final key = _classKeyController.text.trim();
    if (key.isEmpty) {
      setState(() => _queryError = '请输入班级关键字');
      return;
    }

    setState(() {
      _querying = true;
      _scheduleTable = null;
      _queryError = null;
      _requestUrl = null;
    });

    try {
      // 步骤1：查询课程列表
      // 优先尝试用目标学期查询,如果失败则回退到本学期
      String? queryHtml = await widget.service.fetchCourseQueryForClass(
        key,
        isNextSemester: isNextSemester,
      );

      Map<String, String>? result;

      if (queryHtml != null) {
        // 尝试用目标学期的HTML解析
        result = await widget.service.fetchPrintCourseTableFromQueryHtml(
          queryHtml,
          key,
          isNextSemester: false, // 不修改termId,直接使用查询结果中的
        );
      }

      // 如果目标学期查询失败,回退到本学期查询
      if (result == null && isNextSemester) {
        queryHtml = await widget.service.fetchCourseQueryForClass(
          key,
          isNextSemester: false, // 用本学期查询
        );

        if (queryHtml != null) {
          result = await widget.service.fetchPrintCourseTableFromQueryHtml(
            queryHtml,
            key,
            isNextSemester: true, // 修改termId到下学期
          );
        }
      }

      if (queryHtml == null) {
        setState(() {
          _queryError = '查询失败或返回空内容（请检查会话/JSESSIONID）';
          _querying = false;
        });
        return;
      }

      if (result == null) {
        setState(() {
          _queryError = '错误：未找到班级 $key 的课表链接';
          _querying = false;
        });
        return;
      }

      final scheduleHtml = result['html'];
      final requestUrl = result['url'];

      // 步骤3：解析课表
      final table = CourseTableParser.parse(scheduleHtml ?? '');

      setState(() {
        _querying = false;
        _requestUrl = requestUrl;
        // if (table.slots.isEmpty) {
        //   _queryError = '解析后未找到课程信息（可能该学期暂无课程）';
        //   _scheduleTable = null; // 清空旧数据
        // } else {
        _scheduleTable = table;
        // }
      });
    } catch (e) {
      setState(() {
        _queryError = '查询异常: $e';
        _querying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本学期选课'),
        centerTitle: true,
        actions: [
          // 视图切换按钮
          IconButton(
            icon: Icon(
              _viewMode == 'list' ? Icons.calendar_view_week : Icons.list,
            ),
            onPressed: () {
              setState(() {
                _viewMode = _viewMode == 'list' ? 'week' : 'list';
              });
            },
            tooltip: _viewMode == 'list' ? '按周显示' : '列表显示',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _courseSelection = null);
              _loadCourseSelection();
            },
            tooltip: '刷新',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在加载选课信息...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_errorMsg != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              _errorMsg!,
              style: TextStyle(color: Colors.red[700]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _courseSelection = null);
                _loadCourseSelection();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_courseSelection == null) {
      return const Center(child: Text('暂无选课数据'));
    }

    // 主体内容（列表或按周视图）
    final mainContent = _viewMode == 'list'
        ? _buildListView()
        : _buildWeekView();

    // 左侧导航栏，参考成绩中心样式
    final sidebar = Container(
      width: 240,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(right: BorderSide(color: Colors.grey[300]!, width: 1)),
      ),
      child: ListView.builder(
        itemCount: _navItems.length,
        itemBuilder: (context, index) {
          final item = _navItems[index];
          final isSelected = _selectedIndex == index;
          return InkWell(
            onTap: () {
              _onNavItemChanged(index);
              // 如果切换到本学期选课，恢复视图模式
              if (index == 0) {
                setState(() => _viewMode = 'list');
              }
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? Colors.blue[50] : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? Colors.blue[300]! : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    item.icon,
                    color: isSelected ? Colors.blue[700] : Colors.grey[600],
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? Colors.blue[800]
                                : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.description,
                          style: TextStyle(
                            fontSize: 11,
                            color: isSelected
                                ? Colors.blue[600]
                                : Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    // 右侧内容：如果左侧选择第0项，显示主内容，否则显示各自功能页面
    Widget rightContent;
    if (_selectedIndex == 0) {
      rightContent = mainContent;
    } else if (_selectedIndex == 1) {
      // 本学期课表
      rightContent = _buildScheduleQueryPage(isNextSemester: false);
    } else if (_selectedIndex == 2) {
      // 下学期课表
      rightContent = _buildScheduleQueryPage(isNextSemester: true);
    } else {
      rightContent = Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _navItems[_selectedIndex].icon,
                size: 48,
                color: Colors.grey[600],
              ),
              const SizedBox(height: 12),
              Text(
                _navItems[_selectedIndex].title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _navItems[_selectedIndex].description,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sidebar,
        Expanded(child: rightContent),
      ],
    );
  }

  /// 列表视图
  Widget _buildListView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶部统计
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.purple[700]!, Colors.purple[500]!],
            ),
            border: Border(
              bottom: BorderSide(color: Colors.purple[100]!, width: 2),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                icon: Icons.book,
                label: '课程数量',
                value: '${_courseSelection!.courses.length}',
              ),
              _buildStatItem(
                icon: Icons.star,
                label: '总学分',
                value: _courseSelection!.totalCredits.toStringAsFixed(1),
              ),
            ],
          ),
        ),
        // 课程列表
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _courseSelection!.courses.length,
            itemBuilder: (context, index) {
              final course = _courseSelection!.courses[index];
              return _buildCourseCard(course, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildCourseCard(SelectedCourse course, int index) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.purple[400]!, Colors.purple[600]!],
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.courseName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        course.courseCode,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green[100],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${course.credit}学分',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow(Icons.person, '教师', course.teacher),
            const SizedBox(height: 6),
            _buildInfoRow(Icons.business, '学院', course.college),
            const SizedBox(height: 6),
            _buildInfoRow(Icons.class_, '班号', course.classNumber),
            if (course.schedule.isNotEmpty) ...[
              const SizedBox(height: 6),
              _buildInfoRow(Icons.schedule, '时间地点', course.schedule),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                _buildChip(
                  course.nature,
                  course.isRequired ? Colors.red[100]! : Colors.blue[100]!,
                  course.isRequired ? Colors.red[700]! : Colors.blue[700]!,
                ),
                const SizedBox(width: 8),
                _buildChip(
                  '选课号: ${course.selectCode}',
                  Colors.grey[200]!,
                  Colors.grey[700]!,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(fontSize: 13, color: Colors.grey[700]),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ),
      ],
    );
  }

  Widget _buildChip(String text, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: textColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// 按周显示视图
  Widget _buildWeekView() {
    // 解析课程的时间信息，按星期组织
    final weekSchedule = _parseWeekSchedule();

    return Column(
      children: [
        // 顶部统计条
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.teal[700]!, Colors.teal[500]!],
            ),
            border: Border(
              bottom: BorderSide(color: Colors.teal[100]!, width: 2),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildWeekStatItem(
                Icons.calendar_today,
                '本周课程',
                '${_courseSelection!.courses.length}',
              ),
              _buildWeekStatItem(Icons.timer, '总学时', _calculateTotalHours()),
              _buildWeekStatItem(
                Icons.star,
                '总学分',
                _courseSelection!.totalCredits.toStringAsFixed(1),
              ),
            ],
          ),
        ),
        // 课程表
        Expanded(
          child: weekSchedule.isEmpty
              ? const Center(child: Text('暂无课程时间信息'))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    for (var day in ['周一', '周二', '周三', '周四', '周五', '周六', '周日'])
                      if (weekSchedule.containsKey(day) &&
                          weekSchedule[day]!.isNotEmpty)
                        _buildDaySection(day, weekSchedule[day]!),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildWeekStatItem(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDaySection(String day, List<SelectedCourse> courses) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.teal[50],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today, size: 18, color: Colors.teal[700]),
                const SizedBox(width: 8),
                Text(
                  day,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal[800],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${courses.length}门课程',
                  style: TextStyle(fontSize: 12, color: Colors.teal[600]),
                ),
              ],
            ),
          ),
          ...courses.map((course) => _buildWeekCourseItem(course)),
        ],
      ),
    );
  }

  Widget _buildWeekCourseItem(SelectedCourse course) {
    // 解析时间信息
    final timeInfo = _parseScheduleInfo(course.schedule);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[200]!, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 节次标签
              if (timeInfo['section'] != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    timeInfo['section']!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange[900],
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.courseName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      course.courseCode,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${course.credit}学分',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[800],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 周次和教室信息
          Row(
            children: [
              if (timeInfo['weeks'] != null) ...[
                Icon(Icons.calendar_month, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  timeInfo['weeks']!,
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
                const SizedBox(width: 16),
              ],
              if (timeInfo['room'] != null) ...[
                Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    timeInfo['room']!,
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.person, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 6),
              Text(
                course.teacher,
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: course.isRequired ? Colors.red[50] : Colors.blue[50],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  course.nature,
                  style: TextStyle(
                    fontSize: 10,
                    color: course.isRequired
                        ? Colors.red[700]
                        : Colors.blue[700],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 解析时间地点信息
  Map<String, String?> _parseScheduleInfo(String schedule) {
    final result = <String, String?>{
      'weeks': null,
      'section': null,
      'room': null,
    };

    // 提取周次
    final weeksMatch = RegExp(r'(\d+[-~]\d+周|\d+周)').firstMatch(schedule);
    if (weeksMatch != null) {
      result['weeks'] = weeksMatch.group(1);
    }

    // 提取节次
    final sectionMatch = RegExp(r'(\d+[-~]\d+节|\d+节)').firstMatch(schedule);
    if (sectionMatch != null) {
      result['section'] = sectionMatch.group(1);
    }

    // 提取教室
    String room = schedule
        .replaceAll(RegExp(r'\d+[-~]?\d*周'), '')
        .replaceAll(RegExp(r'星期[一二三四五六日天]'), '')
        .replaceAll(RegExp(r'周[一二三四五六日天]'), '')
        .replaceAll(RegExp(r'\d+[-~]?\d*节'), '')
        .trim();

    if (room.isNotEmpty) {
      result['room'] = room;
    }

    return result;
  }

  /// 解析周课程表
  Map<String, List<SelectedCourse>> _parseWeekSchedule() {
    final Map<String, List<SelectedCourse>> schedule = {};

    for (var course in _courseSelection!.courses) {
      if (course.schedule.isEmpty) continue;

      // 尝试从时间地点字符串中提取星期信息
      final scheduleText = course.schedule;
      String? day;

      if (scheduleText.contains('周一') || scheduleText.contains('星期一')) {
        day = '周一';
      } else if (scheduleText.contains('周二') || scheduleText.contains('星期二')) {
        day = '周二';
      } else if (scheduleText.contains('周三') || scheduleText.contains('星期三')) {
        day = '周三';
      } else if (scheduleText.contains('周四') || scheduleText.contains('星期四')) {
        day = '周四';
      } else if (scheduleText.contains('周五') || scheduleText.contains('星期五')) {
        day = '周五';
      } else if (scheduleText.contains('周六') || scheduleText.contains('星期六')) {
        day = '周六';
      } else if (scheduleText.contains('周日') ||
          scheduleText.contains('星期日') ||
          scheduleText.contains('星期天')) {
        day = '周日';
      }

      if (day != null) {
        if (!schedule.containsKey(day)) {
          schedule[day] = [];
        }
        schedule[day]!.add(course);
      }
    }

    // 对每一天的课程按节次排序
    for (var day in schedule.keys) {
      schedule[day]!.sort((a, b) {
        final timeA = _extractStartSection(a.schedule);
        final timeB = _extractStartSection(b.schedule);
        return timeA.compareTo(timeB);
      });
    }

    return schedule;
  }

  /// 提取开始节次（用于排序）
  /// 例如："1-17周 星期四 3-5节" -> 3
  /// "1-17周 星期三 9-10节" -> 9
  int _extractStartSection(String schedule) {
    // 匹配 "数字-数字节" 或 "数字节" 模式
    final match = RegExp(r'(\d+)[-\~]?\d*节').firstMatch(schedule);
    if (match != null && match.groupCount >= 1) {
      return int.tryParse(match.group(1)!) ?? 999;
    }
    return 999; // 无法解析的放最后
  }

  /// 计算总学时（粗略估算）
  String _calculateTotalHours() {
    int totalHours = 0;
    for (var course in _courseSelection!.courses) {
      // 粗略估算：1学分约等于16学时
      totalHours += (course.credit * 16).round();
    }
    return '$totalHours';
  }
}
