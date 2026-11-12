import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island/community/user_pod.dart';

import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/exam_api.dart';

final examApiProvider = Provider<ExamApi>((ref) {
  return ExamApi(ref.watch(lkmApiSessionProvider).client);
});

/// Public exam page; null [type] lists both exams and competitions.
final examsProvider = FutureProvider.autoDispose.family<ApiPage<Exam>, String?>(
  (ref, type) {
    final session = ref.watch(lkmApiSessionProvider);
    return session.run(() => ref.watch(examApiProvider).exams(type: type));
  },
);

final examDetailProvider = FutureProvider.autoDispose.family<Exam, String>((
  ref,
  id,
) {
  final session = ref.watch(lkmApiSessionProvider);
  return session.run(() => ref.watch(examApiProvider).exam(id));
});

/// Only competitions have a public leaderboard; other types return empty.
final examLeaderboardProvider = FutureProvider.autoDispose
    .family<ApiPage<ExamRanking>, String>((ref, examId) {
      final session = ref.watch(lkmApiSessionProvider);
      return session.run(() => ref.watch(examApiProvider).leaderboard(examId));
    });

final myCertificatesProvider =
    FutureProvider.autoDispose<List<ExamCertificate>>((ref) async {
      ref.watch(lkmMeProvider);
      final session = ref.watch(lkmApiSessionProvider);
      if (!session.isSignedIn) return const [];
      return session.run(() => ref.watch(examApiProvider).myCertificates());
    });
