"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.recordStudyActivity = recordStudyActivity;
exports.replenishGraceDays = replenishGraceDays;
const admin = __importStar(require("firebase-admin"));
const db = () => admin.firestore();
/**
 * Records a study activity for the user and updates streak.
 * Designed to be called from session-end Cloud Function trigger.
 */
async function recordStudyActivity(uid) {
    const ref = db().collection("users").doc(uid);
    return db().runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists)
            throw new Error(`User ${uid} not found`);
        const data = snap.data();
        const profile = data.profile;
        const now = new Date();
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const lastActiveTstamp = profile.lastActiveDate;
        const lastActive = lastActiveTstamp?.toDate() ?? null;
        const lastActiveDay = lastActive
            ? new Date(lastActive.getFullYear(), lastActive.getMonth(), lastActive.getDate())
            : null;
        // Already recorded today
        if (lastActiveDay && lastActiveDay.getTime() === today.getTime()) {
            return {
                newStreak: profile.streak ?? 0,
                wasExtended: false,
                usedGraceDay: false,
                streakBroken: false,
                isNewRecord: false,
                milestoneReached: null,
            };
        }
        let streak = profile.streak ?? 0;
        let longestStreak = profile.longestStreak ?? 0;
        let hasGraceDay = profile.hasGraceDayAvailable ?? true;
        let usedGraceDay = false;
        let streakBroken = false;
        const yesterday = new Date(today);
        yesterday.setDate(today.getDate() - 1);
        const twoDaysAgo = new Date(today);
        twoDaysAgo.setDate(today.getDate() - 2);
        if (!lastActiveDay) {
            streak = 1;
        }
        else if (lastActiveDay.getTime() === yesterday.getTime()) {
            streak++;
        }
        else if (lastActiveDay.getTime() === twoDaysAgo.getTime() && hasGraceDay) {
            streak++;
            hasGraceDay = false;
            usedGraceDay = true;
        }
        else {
            streakBroken = true;
            streak = 1;
        }
        if (streak > longestStreak)
            longestStreak = streak;
        const milestones = [3, 7, 14, 30, 60, 100, 365];
        const milestoneReached = milestones.includes(streak) ? streak : null;
        tx.update(ref, {
            "profile.streak": streak,
            "profile.longestStreak": longestStreak,
            "profile.lastActiveDate": admin.firestore.Timestamp.fromDate(today),
            "profile.hasGraceDayAvailable": hasGraceDay,
            "profile.totalStudyDays": admin.firestore.FieldValue.increment(1),
        });
        return {
            newStreak: streak,
            wasExtended: !streakBroken,
            usedGraceDay,
            streakBroken,
            isNewRecord: streak === longestStreak && streak > 1,
            milestoneReached,
        };
    });
}
/**
 * Called weekly (Monday) to replenish the grace day token.
 */
async function replenishGraceDays() {
    const snapshot = await db().collection("users").get();
    const batch = db().batch();
    for (const doc of snapshot.docs) {
        batch.update(doc.ref, { "profile.hasGraceDayAvailable": true });
    }
    await batch.commit();
}
//# sourceMappingURL=streak_manager.js.map