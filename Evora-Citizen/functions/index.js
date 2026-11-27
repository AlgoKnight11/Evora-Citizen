const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

/**
 * Normalizes any department string into a standard FCM topic slug.
 */
function normalizeDeptSlug(department) {
  if (!department) return "general";
  const d = department.toLowerCase();
  if (
    d.includes("solid_waste") ||
    d.includes("waste") ||
    d.includes("garbage") ||
    d.includes("sanitation") ||
    d.includes("clean")
  ) {
    return "solid_waste";
  } else if (
    d.includes("road") ||
    d.includes("traffic") ||
    d.includes("street") ||
    d.includes("pothole")
  ) {
    return "roads";
  } else if (
    d.includes("water") ||
    d.includes("drain") ||
    d.includes("sewer") ||
    d.includes("leak")
  ) {
    return "water_supply";
  } else if (
    d.includes("elect") ||
    d.includes("light") ||
    d.includes("power")
  ) {
    return "electricity";
  }
  return "general";
}

/**
 * Cloud Firestore Trigger:
 * Fires whenever a new field task is created in `/tenants/{tenantId}/tasks/{taskId}`.
 * This automatically dispatches a high-priority FCM push notification to all field workers
 * subscribed to the matching municipal department topic (and/or direct worker FCM token).
 *
 * Even if the worker's phone is locked, asleep, or the app is killed/terminated,
 * Android's Google Play Services receives this FCM payload and displays the heads-up
 * notification with sound, vibration, and full complaint analysis!
 */
exports.onTaskCreated = functions.firestore
  .document("tenants/{tenantId}/tasks/{taskId}")
  .onCreate(async (snap, context) => {
    const task = snap.data();
    const { tenantId, taskId } = context.params;

    if (!task) {
      console.warn(`[onTaskCreated] Empty task payload for ${taskId}`);
      return null;
    }

    console.log(
      `[onTaskCreated] Processing new task ${taskId} for tenant ${tenantId}, dept: ${task.departmentId}`
    );

    const cleanTenant = (tenantId || "tenant_dehradun_01")
      .replace(/[^a-zA-Z0-9_]/g, "_")
      .toLowerCase();

    const deptSlug = normalizeDeptSlug(task.departmentId);
    const departmentTopic = `${cleanTenant}_${deptSlug}`;

    const priorityVal = (task.priority || "p3").toUpperCase();
    const priorityIcon =
      priorityVal === "P1"
        ? "🚨 [CRITICAL P1]"
        : priorityVal === "P2"
        ? "⚠️ [URGENT P2]"
        : priorityVal === "P4"
        ? "ℹ️ [LOW P4]"
        : "📋 [NORMAL P3]";

    const title = `${priorityIcon} ${task.title || "New Municipal Grievance"}`;

    const locationSummary =
      task.location?.addressSummary ||
      task.location?.wardId ||
      task.wardId ||
      "Doon Municipal Area";
    const landmark = task.location?.landmark
      ? ` (Near ${task.location.landmark})`
      : "";
    const instructions = (task.instructions || "Field inspection and resolution required.")
      .trim();
    const shortInstructions =
      instructions.length > 90
        ? `${instructions.substring(0, 90)}...`
        : instructions;

    const body = `📍 ${locationSummary}${landmark}\n⚡ Severity: ${priorityVal}\n🔍 Citizen Report: "${shortInstructions}"`;

    // High-priority FCM payload with Android notification channel and wake-lock hints
    const fcmPayload = {
      notification: {
        title: title,
        body: body,
      },
      data: {
        taskId: taskId,
        tenantId: tenantId,
        civicFlowCaseId: task.civicFlowCaseId || "",
        priority: task.priority || "p3",
        departmentId: task.departmentId || "",
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      android: {
        priority: "high",
        ttl: 86400 * 1000, // 24 hours
        notification: {
          channelId: "evora_worker_dispatches_v2",
          priority: "max",
          defaultSound: true,
          defaultVibrateTimings: true,
          notificationPriority: "PRIORITY_MAX",
          visibility: "PUBLIC",
          icon: "ic_launcher",
          tag: taskId,
          ticker: "New Municipal Dispatch Alert",
        },
      },
    };

    const sendPromises = [];

    // 1. Send to department topic (e.g. tenant_dehradun_01_solid_waste)
    const topicMessage = {
      ...fcmPayload,
      topic: departmentTopic,
    };
    sendPromises.push(
      admin
        .messaging()
        .send(topicMessage)
        .then((response) => {
          console.log(
            `[onTaskCreated] Successfully sent push to topic ${departmentTopic}: ${response}`
          );
          return response;
        })
        .catch((err) => {
          console.error(
            `[onTaskCreated] Error sending push to topic ${departmentTopic}:`,
            err
          );
          return null;
        })
    );

    // 2. If a specific worker is assigned, also send directly to their device token
    if (task.workerUid) {
      const workerDocPromise = admin
        .firestore()
        .collection("tenants")
        .doc(tenantId)
        .collection("workers")
        .doc(task.workerUid)
        .get()
        .then(async (docSnap) => {
          if (docSnap.exists) {
            const workerData = docSnap.data();
            const fcmToken = workerData?.fcmToken;
            if (fcmToken) {
              const directMessage = {
                ...fcmPayload,
                token: fcmToken,
              };
              return admin
                .messaging()
                .send(directMessage)
                .then((resp) => {
                  console.log(
                    `[onTaskCreated] Sent direct push to worker ${task.workerUid}: ${resp}`
                  );
                });
            }
          }
          return null;
        })
        .catch((err) => {
          console.error(
            `[onTaskCreated] Error sending direct push to worker ${task.workerUid}:`,
            err
          );
        });

      sendPromises.push(workerDocPromise);
    }

    await Promise.all(sendPromises);
    return null;
  });

/**
 * Health check HTTP function
 */
exports.ping = functions.https.onRequest((req, res) => {
  res.status(200).send({
    status: "ok",
    service: "evora-push-dispatcher",
    timestamp: new Date().toISOString(),
  });
});
