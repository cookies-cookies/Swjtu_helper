import 'package:flutter/material.dart';
import '../models/student_info.dart';

/// 学生信息展示页面
class StudentInfoPage extends StatelessWidget {
  final StudentInfo studentInfo;

  const StudentInfoPage({super.key, required this.studentInfo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('学生信息'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题卡片
            Card(
              elevation: 4,
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      '西南交通大学学生学籍信息表',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[900],
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${studentInfo.name} (${studentInfo.studentId})',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.blue[700],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 基本信息
            _buildSection(context, '基本信息', Icons.person, Colors.blue, [
              _buildInfoRow('学生学号', studentInfo.studentId),
              _buildInfoRow('学生姓名', studentInfo.name),
              _buildInfoRow('护照姓名', studentInfo.passportName),
              _buildInfoRow('学生性别', studentInfo.gender),
              _buildInfoRow('出生年月', studentInfo.birthDate),
              _buildInfoRow(
                '学籍状态',
                studentInfo.status,
                valueColor: Colors.blue,
              ),
              _buildInfoRow('在读状态', studentInfo.enrollmentStatus),
            ]),

            // 学籍信息
            _buildSection(context, '学籍信息', Icons.school, Colors.green, [
              _buildInfoRow('专业学院', studentInfo.college),
              _buildInfoRow('当前年级', studentInfo.grade),
              _buildInfoRow('就读专业', studentInfo.major),
              _buildInfoRow('专业班级', studentInfo.majorClass),
              _buildInfoRow('国标专业', studentInfo.nationalMajor),
              _buildInfoRow('所在校区', studentInfo.campus),
              if (studentInfo.adminCollege.isNotEmpty)
                _buildInfoRow('行政学院', studentInfo.adminCollege),
              if (studentInfo.adminClass.isNotEmpty)
                _buildInfoRow('行政班级', studentInfo.adminClass),
            ]),

            // 个人信息
            _buildSection(context, '个人信息', Icons.badge, Colors.orange, [
              _buildInfoRow('学生籍贯', studentInfo.nativePlace),
              _buildInfoRow('学生民族', studentInfo.ethnicity),
              _buildInfoRow('政治面貌', studentInfo.politicalStatus),
              _buildInfoRow('身份证号', _maskIdCard(studentInfo.idCard)),
              _buildInfoRow('考生号', studentInfo.examNumber),
            ]),

            // 联系方式
            _buildSection(context, '联系方式', Icons.contact_phone, Colors.purple, [
              _buildInfoRow('联系电话', studentInfo.phone),
              _buildInfoRow('家庭住址', studentInfo.homeAddress),
              if (studentInfo.homePhone.isNotEmpty)
                _buildInfoRow('家庭电话', studentInfo.homePhone),
              if (studentInfo.postcode.isNotEmpty)
                _buildInfoRow('邮政编码', studentInfo.postcode),
              if (studentInfo.email.isNotEmpty)
                _buildInfoRow('电子邮件', studentInfo.email),
              if (studentInfo.dormitory.isNotEmpty)
                _buildInfoRow('宿舍号', studentInfo.dormitory),
              if (studentInfo.motherPhone.isNotEmpty)
                _buildInfoRow('母亲电话', studentInfo.motherPhone),
              if (studentInfo.fatherPhone.isNotEmpty)
                _buildInfoRow('父亲电话', studentInfo.fatherPhone),
            ]),

            // 录取信息
            _buildSection(context, '录取信息', Icons.assignment, Colors.teal, [
              _buildInfoRow('生源地', studentInfo.birthplace),
              _buildInfoRow('毕业学校', studentInfo.graduateSchool),
              _buildInfoRow('考生类别', studentInfo.candidateType),
              _buildInfoRow('录取形式', studentInfo.admissionType),
              _buildInfoRow('录取来源', studentInfo.admissionSource),
              _buildInfoRow('高考科类', studentInfo.examSubject),
              if (studentInfo.examScore.isNotEmpty)
                _buildInfoRow('高考成绩', studentInfo.examScore),
              if (studentInfo.enrollmentDate.isNotEmpty)
                _buildInfoRow('入学时间', studentInfo.enrollmentDate),
            ]),

            // 其他信息
            if (studentInfo.trainRoute.isNotEmpty ||
                studentInfo.studentTag.isNotEmpty ||
                studentInfo.remarks.isNotEmpty)
              _buildSection(
                context,
                '其他信息',
                Icons.info_outline,
                Colors.indigo,
                [
                  if (studentInfo.trainRoute.isNotEmpty)
                    _buildInfoRow('乘车区间', studentInfo.trainRoute),
                  if (studentInfo.studentTag.isNotEmpty)
                    _buildInfoRow('学生标记', studentInfo.studentTag),
                  if (studentInfo.remarks.isNotEmpty)
                    _buildInfoRow('备注信息', studentInfo.remarks),
                  if (studentInfo.specialRemarks.isNotEmpty)
                    _buildInfoRow('特殊备注', studentInfo.specialRemarks),
                ],
              ),

            // 学籍异动记录
            if (studentInfo.changeRecords.isNotEmpty)
              _buildChangeRecordsSection(context),
          ],
        ),
      ),
    );
  }

  /// 构建信息区块
  Widget _buildSection(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    List<Widget> children,
  ) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              border: Border(bottom: BorderSide(color: color.withOpacity(0.3))),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  /// 构建信息行
  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? Colors.black54,
                fontWeight: valueColor != null
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建学籍异动记录区块
  Widget _buildChangeRecordsSection(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              border: Border(
                bottom: BorderSide(color: Colors.red.withOpacity(0.3)),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.history, color: Colors.red, size: 24),
                const SizedBox(width: 8),
                Text(
                  '学籍异动记录 (${studentInfo.changeRecords.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 16,
              headingRowColor: MaterialStateProperty.all(Colors.grey[100]),
              columns: const [
                DataColumn(
                  label: Text(
                    '序号',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    '异动日期',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    '批准日期',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    '异动类型',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    '异动原因',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    '异动前学籍',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    '经办人',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
              rows: studentInfo.changeRecords
                  .map(
                    (record) => DataRow(
                      cells: [
                        DataCell(Text(record.index)),
                        DataCell(Text(record.changeDate)),
                        DataCell(Text(record.approvalDate)),
                        DataCell(
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
                              record.changeType,
                              style: TextStyle(
                                color: Colors.orange[900],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        DataCell(Text(record.changeReason)),
                        DataCell(
                          SizedBox(
                            width: 200,
                            child: Text(
                              record.previousStatus,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(Text(record.operator)),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// 脱敏身份证号
  String _maskIdCard(String idCard) {
    if (idCard.isEmpty) return '';
    if (idCard.length < 10) return idCard;
    return idCard.substring(0, 6) +
        '********' +
        idCard.substring(idCard.length - 4);
  }
}
