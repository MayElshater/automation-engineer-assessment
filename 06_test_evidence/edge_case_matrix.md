| Test | Scenario                   | Expected / Verified Result                                                                                                                                                                  | Status   | Evidence                                                          |
| ---- | -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ----------------------------------------------------------------- |


| T01 | Website lead intake | Website payload is accepted and mapped to the canonical lead structure; contact identifiers are normalized by WF02 | **PASS** | T01a–T01d, `T01_website_normalized.json` |


| T02 | WhatsApp lead intake | Simulated WhatsApp payload is accepted and mapped to the canonical lead structure; contact identifiers are normalized by WF02 | **PASS** | T02a–T02d, `T02_whatsapp_normalized.json` |


| T03 | CSV batch intake | A single uploaded CSV containing 3 rows is parsed into 3 independent canonical leads and each lead is handed independently to WF02 | **PASS** | T03a–T03e, `T03_csv_normalized.json` |


| T04 | Unique lead identity resolution | A new lead with no matching phone, email, or contextual identity candidate is classified as unique and persisted as a canonical lead | **PASS** | T04a–T04d, `T04_unique_identity.json` |


| T05 | Exact duplicate detection by phone | A lead submitted with the same normalized phone number as an existing lead is classified as exact_duplicate with confidence 1.0; the existing canonical lead is matched and the duplicate decision is persisted | **PASS** | T05a–T05d, `T05_database_result.json`, `T05_exact_duplicate_decision.json` |


| T06 | Cross-source likely duplicate detection | Website and WhatsApp submissions with different contact identifiers but matching contextual identity signals are classified as likely_duplicate and routed to manual review instead of being automatically merged | **PASS** | T06a–T06d, `T06_database_result.json`, `T06_likely_duplicate_decision.json` |


| T07 | Incomplete lead manual review | A lead missing both phone and email fails the completeness requirement and is routed to manual_review without continuing through automatic identity resolution | **PASS** | T07a–T07c, `T07_database_result.json`, `T07_manual_review_result.json` |


| T08 | Phone normalization across formats | Equivalent Egyptian phone numbers submitted in international (+20...) and local (01...) formats are normalized to the same canonical phone number, allowing WF02 to detect them as an exact duplicate | **PASS** | T08a–T08d, `T08_normalized_contact_data.json`, `T08_phone_format_duplicate.json` |


| T09 | Enrichment API times out twice then succeeds | WF03 retries the enrichment request with finite retry limits; attempts 1 and 2 time out, attempt 3 succeeds, and enriched company data is persisted | **PASS** | T09a–T09c, `T09_database_result.json` |


| T10  | Idempotent replay | Re-submitting the same source and external ID is detected as an existing operation; the workflow returns `already_processed` and stops before identity resolution or downstream processing, preventing duplicate side effects | **PASS** | T10a–T10e, `T10_idempotent_replay.json` |


| T11  | Deterministic lead scoring | Enriched lead receives deterministic score 55 from the configured scoring dimensions and is classified as `nurture`; rule result is persisted independently of downstream AI classification | **PASS** | T11a–T11d, `T11_rule_scoring_result.json`, `T11_database_result.json` |


| T12  | AI lead classification | Gemini independently returns a valid structured lead assessment (`high_potential`, confidence `0.95`) while the deterministic classification remains `unqualified`. During the AI classification test, this naturally produced a material AI/rule conflict; the reconciliation logic correctly detected the disagreement and routed the lead to `manual_review` without allowing the AI result to overwrite the deterministic score. | **PASS** | T12a–T12d, `T12_validate_ai_response.json`, `T12_database_result.json `|


| **T13** | Malformed AI response | A controlled test fixture injects malformed AI output; response validation detects the malformed/non-object response, preserves deterministic qualification, does not fabricate an AI classification, and safely routes the lead to manual review | **PASS** | T13a–T13d, `T13_dataset_result.json` , `T13c_malformed_validation_ai_response.json` |


| **T14** | Enrichment service unavailable after finite retries | WF03 performs finite enrichment retries against the controlled mock service; after repeated `503 Service Unavailable` responses, validation marks enrichment as failed, no enrichment or qualification values are fabricated, and the lead is persisted for manual review | **PASS** | T14a–T14e, `T14c_enrichment_invalid_response.json`, `T14_dataset_result.json` |


| **T15** | AI model returns an empty response | A controlled test fixture returns an empty AI response; WF03 detects the empty response as an AI technical failure, preserves the deterministic score and classification, avoids fabricating an AI assessment, and safely routes and persists the lead for manual review | **PASS** | T15a–T15f, `T15_empty_ai_validation.json`, `T15_dataset_result.json` |


| **T16** | Qualified lead routing and workload-aware sales assignment | A qualified Egypt / AI Automation lead is routed through WF04; eligible reps are ranked by service/country match tier before workload. Rep A is selected over Rep B as the lower-load Tier-1 candidate, while lower-load Tier-2/3 candidates do not outrank exact matches. Assignment is persisted atomically and Rep A workload increments from 2 to 3. | **PASS** | T16a–T16e, `T16_find_eligible_sales_reps.json`, `T16_select_best_sales_rep.json`, `T16_dataset_result.json` |


| **T17** | Overloaded preferred sales rep fallback | A qualified AI Automation / Egypt lead is routed to sales while the otherwise preferred Tier-1 Rep A is at full capacity (10/10). WF04 excludes the overloaded rep, selects the next eligible Tier-1 Rep B ahead of lower-tier candidates, persists the assignment, and atomically increments Rep B workload from 6 to 7. | **PASS** | T17a–T17f, `T17_find_eligible_sales_reps.json`, `T17_select_fallback_rep.json` |


| **T18** | VIP lead manager approval gate | A VIP lead with deterministic score 90 is routed through the WF04 VIP path without automatic sales assignment. WF04 creates a pending manager approval record, preserves `assigned_sales_rep_id` as null, sets priority to `critical`, and persists `next_action` as `await_manager_approval`, ensuring no automated sales action occurs before manager approval. | **PASS** | T18a–T18e, `T18_dataset_result.json` |


| **T19** | No eligible sales rep fallback to manual review | A qualified AI Automation / Egypt lead reaches WF04 while all active sales representatives are at full capacity. No representative is selected, `assigned_sales_rep_id` remains null, and WF04 safely routes the lead to manual review with `next_action = manual_sales_assignment`, preserving the qualified CRM stage and recording the routing failure instead of losing or over-assigning the lead. | **PASS** | T19a–T19e, `T19_routing_failed_result.json`, `T19_manual_review_requested.json` |


| T20 | Nurture / non-sales routing | A valid lead scores 60 and is classified as `nurture`; WF04 routes it through the nurture path without sales assignment, persists `crm_stage=nurture`, `priority=medium`, and `next_action=start_nurture_sequence`, preserving the lead for WF05 follow-up processing | **PASS** | T20a–T20c, T20_database_result.json |


| **T21** | Nurture follow-up sequence initialization | A nurture lead handed off from WF04 initializes exactly one `nurture` follow-up sequence in WF05 with three scheduled steps (+24h, +72h, +7d). Each step is persisted with a deterministic idempotency key, no step is executed prematurely, and a single `followup_sequence_initialized` audit event is recorded with `step_count = 3`. | **PASS** | T21a–T21e, `T21_dataset_result.json`, `T21_followup_sequence_result.json`,`T21_followup_initialized_event.json` |


| **T22** | Follow-up step progression | A scheduled nurture follow-up is made due and detected by the WF05 scheduler. The step is atomically claimed for execution, the follow-up action is prepared and persisted exactly once, and Step 1 transitions to `executed` with `executed_at` populated while Steps 2 and 3 remain scheduled for their original future times. | **PASS** | T22a–T22f, `T22_followup_progression_result.json` |


| **T23** | Lead response stops active follow-up sequence | After nurture Step 1 has executed, a `customer_replied` event is recorded before Step 2. When Step 2 becomes due, WF05 detects the response before outbound execution, sets `stop_required = true` with `stop_reason = customer_replied`, cancels both remaining scheduled follow-ups, and performs no additional follow-up execution. | **PASS** | T23a–T23e, `T23_followup_stop_result.json`, `T23_followup_stopped_event.json` |


| **T24** | Follow-up execution failure and lease-based recovery | A due nurture follow-up is atomically claimed and intentionally interrupted before persistence, leaving both the follow-up and its idempotency key in `processing`. After the processing lease expires, WF05 safely recovers and reclaims the same work, completes the follow-up, marks the idempotency key `completed`, preserves the remaining scheduled sequence, and records exactly one `followup_executed` event with no duplicate side effects. | **PASS** | T24a–T24h, `T24_followup_retry_result.json` |


| **T25** | Successful booking | A valid `booked` event is accepted by WF06, atomically claimed through booking-event idempotency, persisted as a single scheduled booking, moves the lead to `meeting_booked` with `next_action = attend_meeting`, cancels the two remaining scheduled follow-ups while preserving executed history, records booking/audit events, handles the absence of an assigned sales rep deterministically, and completes the idempotency key with the booking UUID as its response reference. | **PASS** | T25a–T25i, `T25_dataset_result.json`, `T25_successful_booking_result.json` |


| **T26** | Booking entity conflict / unavailable state | A new `booked` webhook event is received for an `external_booking_id` that already belongs to a different lead. WF06 detects the ownership conflict, rejects the mutation with HTTP `409`, preserves the original booking unchanged, leaves the incoming lead state untouched, performs no follow-up cancellation or sales-rep notification, marks the booking-event idempotency key as `failed` with `booking_state_conflict`, and records a `booking_processing_failed` audit event. | **PASS** | T26a–T26g,  `T26_booking_conflict_info.json`|


| **T27** | Booking reschedule and cancellation lifecycle | An existing scheduled booking receives a `rescheduled` event followed by a `cancelled` event. WF06 updates the same booking row in place, changes the meeting time and status to `rescheduled`, then transitions the same booking to `cancelled`, without creating duplicate booking records. Both mutations complete successfully and return deterministic processed responses. | **PASS** |T27A_booking_rescheduale(T27a–T27d)-T27B_booking_cancel(T27a-T27d) `T27A_booking_reschedule_database.json`, `T27B_booking_cancel_database.json` |


| **T28** | Conversion state persisted correctly | A valid `converted` booking event is received for an existing booking. WF06 updates the same booking to `completed`, preserves the lead's historical qualification result, transitions the CRM funnel stage to canonical `won`, sets `next_action = handoff_to_delivery` and `processing_status = completed`, preserves already-finalized follow-up history, records a `lead_converted` audit event, and completes booking-event idempotency without duplicate side effects. | **PASS** |T28a–T28f, `T28_conversion_audit_events.json`|


| **T29** | **Transient CRM failure → recovery succeeds** | A `crm_sync` operation fails with transient `http_429` and is placed in the DLQ as `pending`. WF07 atomically claims the item, classifies the failure as `transient`, confirms the original idempotency key is not already completed, allows a safe retry, executes recovery attempt `1`, persists the DLQ as `resolved`, and records `recovery_attempt_succeeded` in the audit trail. This proves bounded, state-aware recovery of transient failures without blind replay. | **PASS** | T29a–T29e, `T29_transient_failure_recovery.json` |


| **T30** | **Transient failure reaches retry limit → terminal DLQ failure** | A `crm_sync` recovery item with transient `http_503` already at `attempt_count = 3` is processed by WF07. The failure is still classified as transient, but because the maximum recovery attempts are exhausted, WF07 does **not** execute another recovery operation, marks the DLQ item `failed`, preserves `attempt_count = 3`, sets `reprocessed_at`, and records `dlq_retry_exhausted`. This proves bounded retries and prevents infinite recovery loops. | **PASS** | T30a–T30c, `T30_test_fixture.json` |


| **T31** | **Targeted manual recovery of a failed DLQ item** | A specific `failed` DLQ record is explicitly selected by an operator using `manual_dlq_id`. WF07 re-enters only the targeted item into the standard recovery path without resetting its attempt history, applies the same failure-classification and idempotency safeguards, safely executes recovery attempt `2`, and persists the item as `resolved`. This proves targeted manual reprocessing is supported without bypassing replay protection or historical retry state. | **PASS** | T31a–T31b , `T31_manual_dlq_recovery_result.json` |


| **T32** | **Partial-success recovery prevents duplicate side effects** | A `crm_sync` operation is recorded in the DLQ as a transient `timeout` even though the original CRM side effect had already completed successfully. During targeted manual recovery, WF07 loads the original operation state using the same idempotency key, detects `status = completed` with an existing response reference, sets the recovery decision to `already_completed` with `safe_to_execute = false`, skips replaying the CRM operation, and resolves the DLQ item without incrementing the recovery attempt. This proves WF07 safely handles partial-success failures and prevents duplicate external side effects during recovery. | **PASS** | T32a–T32d, `T32_partial_success_idempotent_recovery.json` |


| **T33** | **SLA within threshold** | A qualified lead assigned to a sales representative has an SLA age below the 30-minute threshold. WF08 identifies the lead as SLA-eligible, evaluates it as `within_threshold`, performs no escalation or lead mutation, preserves `next_action = sales_follow_up` and `priority = high`, and records no `sla_breached` event. | **PASS** | `T33a_wf08_within_threshold_execution.png`, `T33b_evaluate_sla_within_threshold.png`, `T33c_within_threshold_no_mutation.png`, `T33_precheck_within_threshold.json`, `T33_sla_within_threshold_result.json` |


| **T34** | **SLA breach / escalation** | A qualified lead assigned to a sales representative exceeds the 30-minute SLA threshold. WF08 identifies the lead as `breached`, escalates `priority` from `high` to `critical`, changes `next_action` from `sales_follow_up` to `sla_escalation`, preserves qualification state and sales ownership, and records one `sla_breached` audit event. A subsequent monitoring run preserves the escalated state and does not create a duplicate breach event. | **PASS** | `T34a_wf08_sla_breach_execution.png`, `T34b_evaluate_sla_breached.png`, `T34c_persist_sla_breach.png`, `T34d_monitoring_snapshot_escalated.png`, `T34e_idempotent_breach_rerun.png`, `T34_before_sla_breach.json`, `T34_after_sla_escalation.json` |


| **T35** | **Monitoring / audit event correctness** | WF08 produces an operational monitoring snapshot whose persisted metrics match independent database verification across leads, DLQ state, duplicates, SLA breaches, bookings, wins, and follow-ups. The `sla_breached` audit record preserves the workflow, execution, SLA threshold, elapsed time, previous and new actions, and sales ownership required to explain the escalation. | **PASS** | `T35a_monitoring_audit_execution.png`, `T35_monitoring_snapshot.json`, `T35_db_metrics_verification.json`, `T35_audit_correctness.json` |


| **T36** | **End-to-end happy path from CSV lead to conversion** | A new CSV lead is normalized, validated, resolved as unique, enriched, deterministically qualified, AI-classified, routed to an eligible sales representative, and handed to the qualified follow-up flow. WF05 initializes and executes the first follow-up step. A subsequent booking event creates one booking and cancels the remaining scheduled follow-ups, then a conversion event completes the same booking, preserves the historical `qualified` result, transitions the CRM stage to `won`, sets `next_action = handoff_to_delivery`, and completes processing. WF08 subsequently reflects the updated booked and won counts in the operational monitoring snapshot. | **PASS** | `T36_booking_completed.png`, `T36_csv_intake_and_routing.json`, `T36d_booking_completed.png`, `T36e_conversion_won.json`, `T36_audit_trail.json`, `T36_wf08_final_monitoring.json` |