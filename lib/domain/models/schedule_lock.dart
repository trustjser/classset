/// 课表锁定的对象类型。
enum ScheduleLockScope { schoolClass, teacher }

/// 保护一个班级或教师的全部已排课节。
class ScheduleLock {
  const ScheduleLock({
    required this.termId,
    required this.scope,
    required this.targetId,
  });

  final String termId;
  final ScheduleLockScope scope;
  final String targetId;
}
