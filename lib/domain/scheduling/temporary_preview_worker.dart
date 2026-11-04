import 'dart:isolate';

import 'package:class_set/domain/scheduling/actual_timetable.dart';

/// 在后台检查完整的临时调整预览，避免大课表阻塞界面。
Future<ActualChangePreview> computeTemporaryPreview({
  required TemporaryTimetableState state,
  TemporaryMoveRequest? move,
  TemporarySwapRequest? swap,
  TemporarySubstituteRequest? substitute,
}) => Isolate.run(() {
  if (move != null) return state.previewMove(move);
  if (swap != null) return state.previewSwap(swap);
  if (substitute != null) return state.previewSubstitute(substitute);
  return const ActualChangePreview(changes: [], errors: ['请先选择调整目标']);
});
