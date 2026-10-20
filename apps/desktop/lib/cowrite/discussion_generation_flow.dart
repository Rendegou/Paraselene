// 讨论生成 UI 流程：完整预览与明确确认仍由当前视图负责，运行态属于 Registry。
// 视图消失只会取消尚未确认的票据；已经发送的请求保留进度和取消入口。
import 'package:flutter/material.dart';
import '../workspace/workspace_controller.dart';
import '../l10n/generated/app_localizations.dart';
import 'discussion_thread.dart';

/// 预览后明确发送一次；异步期间不捕获正文新身份，也不清除后续输入。
Future<void> generateDiscussion({
  required WorkspaceController workspace,
  required DiscussionThread thread,
  required String outputLanguage,
  required bool Function() isMounted,
  required Future<bool> Function(Map<String, dynamic>) approve,
}) async {
  final registry = workspace.discussions;
  if (registry == null) return;
  final generations = registry.generations;
  final run = await generations.prepare(
    thread: thread.id,
    draft: thread.draft,
    outputLanguage: outputLanguage,
    buildPreview: () =>
        workspace.prepareGeneration(thread.id, outputLanguage: outputLanguage),
  );
  if (run == null) return;
  try {
    if (!isMounted() || run.cancelRequested) {
      await generations.cancel(run);
      return;
    }
    final approved = await approve(run.preview!);
    if (!approved || !isMounted()) {
      await generations.cancel(run);
      return;
    }
    final sent = await generations.send(run);
    if (sent &&
        registry.work == run.work &&
        registry.chapter == run.chapter &&
        registry.byId(run.thread)?.draft == run.draft) {
      registry.editDraft(run.thread, '');
    }
  } catch (_) {
    generations.recordFailure(run);
    await generations.cancel(run);
  } finally {
    if (registry.work == run.work && registry.chapter == run.chapter) {
      try {
        await registry.refreshOperations();
      } catch (_) {
        generations.recordFailure(run);
      }
    }
  }
}

/// 冻结外发材料的确认对话框；关闭或取消均不发送模型请求。
final class GenerationPreviewDialog extends StatelessWidget {
  const GenerationPreviewDialog({required this.preview, super.key});

  /// 已冻结的完整材料，只展示，不在此重新组装或替换。
  final Map<String, dynamic> preview;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final prepared = preview['prepared'] as Map;
    return AlertDialog(
      title: Text(strings.generationPreview),
      content: SizedBox(
        width: 700,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings.deepseekFeeNotice),
              Text(
                [prepared['model'], prepared['estimated_tokens']].join(' · '),
              ),
              for (final message in prepared['messages'] as List)
                SelectableText(
                  [(message as Map)['role'], message['content'], ''].join('\n'),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(strings.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(strings.generationApprove),
        ),
      ],
    );
  }
}
