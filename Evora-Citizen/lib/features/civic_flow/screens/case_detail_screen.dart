import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/evora_colors.dart';
import '../models/civic_flow_model.dart';
import '../services/civic_flow_service.dart';

class CaseDetailScreen extends ConsumerStatefulWidget {
  final String caseId;

  const CaseDetailScreen({super.key, required this.caseId});

  @override
  ConsumerState<CaseDetailScreen> createState() => _CaseDetailScreenState();
}

class _CaseDetailScreenState extends ConsumerState<CaseDetailScreen> {
  final _infoResponseController = TextEditingController();
  final _feedbackController = TextEditingController();
  bool _isActionLoading = false;

  @override
  void dispose() {
    _infoResponseController.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _confirmWithdraw(CivicFlowCase c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw Grievance?'),
        content: Text(
          'Are you sure you want to withdraw grievance ${c.caseNumber}?\n\n'
          'If the issue is already resolved before municipal worker action, withdrawing will permanently remove this grievance from your account, cancel all active municipal dispatches, and delete all associated media files.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: EvoraColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Withdraw Grievance'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isActionLoading = true);
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);

      final success = await ref.read(civicFlowProvider.notifier).withdrawCase(c.id);

      if (mounted) {
        setState(() => _isActionLoading = false);
        if (success) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Grievance successfully withdrawn and removed.'),
              backgroundColor: EvoraColors.primary,
            ),
          );
          navigator.pop();
        } else {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Failed to withdraw grievance. Please try again.'),
              backgroundColor: EvoraColors.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(civicFlowProvider);
    final caseIndex = state.citizenCases.indexWhere((c) => c.id == widget.caseId);

    if (caseIndex == -1) {
      if (state.isLoading) {
        return Scaffold(
          appBar: AppBar(title: const Text('Grievance Details')),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Grievance Details')),
        body: const Center(child: Text('Case record not found.')),
      );
    }

    final c = state.citizenCases[caseIndex];
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

    return Scaffold(
      appBar: AppBar(
        title: Text(c.caseNumber),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: EvoraColors.error),
            tooltip: 'Withdraw Grievance',
            onPressed: _isActionLoading ? null : () => _confirmWithdraw(c),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: EvoraColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: EvoraColors.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          c.caseNumber,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: EvoraColors.primary),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: EvoraColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            CivicFlowStatus.getLabel(c.status),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: EvoraColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${c.category} — ${c.subcategory}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      c.description,
                      style: const TextStyle(fontSize: 14, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 16, color: EvoraColors.outline),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            c.landmark != null ? '${c.locality} (${c.landmark})' : c.locality,
                            style: const TextStyle(fontSize: 12, color: EvoraColors.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                    if (c.assignedDepartment != null || c.requiredDepartments.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: EvoraColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: EvoraColors.primary.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.account_balance_outlined, size: 16, color: EvoraColors.primary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Lead: ${c.assignedDepartment ?? c.requiredDepartments.first}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: EvoraColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (c.requiredDepartments.length > 1) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: c.requiredDepartments
                                    .where((d) => d != c.assignedDepartment)
                                    .map((dept) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: EvoraColors.secondary.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(100),
                                    ),
                                    child: Text(
                                      '+ $dept',
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: EvoraColors.primary,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                            if (c.departmentReasons.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              ...c.departmentReasons.entries.map((e) => Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      '• ${e.key}: ${e.value}',
                                      style: const TextStyle(fontSize: 11, color: EvoraColors.onSurfaceVariant),
                                    ),
                                  )),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (c.priority == 'high' || c.priority == 'urgent')
                                ? Colors.orange.withValues(alpha: 0.15)
                                : EvoraColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            'Priority: ${c.priority.toUpperCase()}',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: (c.priority == 'high' || c.priority == 'urgent')
                                  ? Colors.orange.shade800
                                  : EvoraColors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (c.aiConfidence != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: EvoraColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              'AI Triage ${(c.aiConfidence! * 100).round()}%',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: EvoraColors.primary,
                              ),
                            ),
                          ),
                        if (c.piiRedactedCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.teal.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              '${c.piiRedactedCount} PII Redacted',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.teal.shade700,
                              ),
                            ),
                          ),
                        if (c.supportersCount > 1)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              '${c.supportersCount} Citizens Supporting',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (c.assignedOfficer != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.person_pin_outlined, size: 16, color: EvoraColors.outline),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Officer: ${c.assignedOfficer}',
                              style: const TextStyle(fontSize: 12, color: EvoraColors.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Attached Photo if exists
              if (c.imageUrl != null) ...[
                const SizedBox(height: 20),
                const Text('Ground Evidence Photo', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    c.imageUrl!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ],

              // Interactive Action: Needs Information Response
              if (c.status == CivicFlowStatus.needsInfo) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.orange),
                          SizedBox(width: 8),
                          Text(
                            'Action Required: Clarification Needed',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.orange),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        c.officerNotes ?? 'The assigned officer has requested additional details regarding the exact landmark.',
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _infoResponseController,
                        decoration: const InputDecoration(
                          hintText: 'Enter your response...',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: _isActionLoading
                            ? null
                            : () async {
                                final text = _infoResponseController.text.trim();
                                if (text.isEmpty) return;
                                setState(() => _isActionLoading = true);
                                final ok = await ref
                                    .read(civicFlowProvider.notifier)
                                    .respondToNeedsInfo(c.id, text);
                                if (!mounted) return;
                                setState(() => _isActionLoading = false);
                                if (ok) {
                                  _infoResponseController.clear();
                                  FocusManager.instance.primaryFocus?.unfocus();
                                }
                              },
                        child: _isActionLoading
                            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Submit Response to Officer'),
                      ),
                    ],
                  ),
                ),
              ],

              // Interactive Action: Verify Resolution (Pending Review)
              if (c.status == CivicFlowStatus.resolvedPending) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: EvoraColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: EvoraColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Officer Marked Work Completed',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: EvoraColors.primary),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Please verify if the issue was satisfactorily resolved on the ground.',
                        style: TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text('Confirm Resolved'),
                              onPressed: () async {
                                await ref.read(civicFlowProvider.notifier).verifyResolution(c.id, isSatisfied: true);
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton(
                            child: const Text('Reopen Case'),
                            onPressed: () async {
                              await ref.read(civicFlowProvider.notifier).verifyResolution(c.id, isSatisfied: false, feedback: 'Issue persists on site.');
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Official 10-Stage Status Stepper Timeline
              const Text(
                'Official Action Timeline',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 12),

              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: c.timeline.length,
                itemBuilder: (context, index) {
                  final event = c.timeline[index];
                  final isLast = index == c.timeline.length - 1;

                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Timeline track indicator
                        Column(
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: isLast ? EvoraColors.primary : EvoraColors.secondary,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check, size: 14, color: Colors.white),
                            ),
                            if (!isLast)
                              Expanded(
                                child: Container(
                                  width: 2,
                                  color: EvoraColors.outlineVariant.withValues(alpha: 0.6),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 14),
                        // Timeline Details
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      event.title,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        color: isLast ? EvoraColors.primary : EvoraColors.onSurface,
                                      ),
                                    ),
                                    Text(
                                      event.actor,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: EvoraColors.outline,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  dateFormat.format(event.timestamp),
                                  style: const TextStyle(fontSize: 11, color: EvoraColors.outline),
                                ),
                                if (event.description.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    event.description,
                                    style: const TextStyle(fontSize: 13, height: 1.3),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              // Withdraw Grievance Action Card
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: EvoraColors.error.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: EvoraColors.error.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info_outline, size: 20, color: EvoraColors.error),
                        SizedBox(width: 8),
                        Text(
                          'Issue Resolved Early?',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: EvoraColors.error),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'If this civic issue was resolved before municipal action or was filed by mistake, you may withdraw this grievance. This permanently removes it from your account, cleans up stored media, and cancels active dispatches.',
                      style: TextStyle(fontSize: 13, height: 1.3),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: _isActionLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: EvoraColors.error),
                              )
                            : const Icon(Icons.delete_outline, size: 18, color: EvoraColors.error),
                        label: Text(
                          _isActionLoading ? 'Withdrawing...' : 'Withdraw Grievance',
                          style: const TextStyle(color: EvoraColors.error, fontWeight: FontWeight.w700),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: EvoraColors.error),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _isActionLoading ? null : () => _confirmWithdraw(c),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
