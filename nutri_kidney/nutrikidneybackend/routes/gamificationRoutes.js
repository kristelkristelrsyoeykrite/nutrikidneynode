const express = require("express");
const { admin, db } = require("../firebase/admin");
const {
  getGamificationSummary,
  getLeaderboard,
} = require("../services/gamificationService");

const router = express.Router();

router.post("/summary", async (req, res) => {
  try {
    const { userId, profileUserId, date } = req.body;
    if (!userId) {
      return res.status(400).json({ success: false, error: "userId is required" });
    }

    const today = date || new Date().toISOString().slice(0, 10);
    const gamification = await getGamificationSummary({
      db,
      userId: profileUserId || userId,
      date: today,
    });
    return res.status(200).json({ success: true, gamification });
  } catch (error) {
    console.error("GAMIFICATION_SUMMARY ERROR:", error.message);
    return res.status(500).json({
      success: false,
      error: error.message || "Failed to load gamification summary",
    });
  }
});

router.post("/leaderboard", async (req, res) => {
  try {
    const leaderboard = await getLeaderboard({
      admin,
      db,
      limit: Number(req.body.limit) || 10,
    });
    return res.status(200).json({
      success: true,
      title: "Weekly Logging Leaderboard",
      leaderboard,
    });
  } catch (error) {
    console.error("GAMIFICATION_LEADERBOARD ERROR:", error.message);
    return res.status(500).json({
      success: false,
      error: error.message || "Failed to load leaderboard",
    });
  }
});

router.post("/leaderboard-visibility", async (req, res) => {
  try {
    const { userId, showOnLeaderboard } = req.body;
    if (!userId || typeof showOnLeaderboard !== "boolean") {
      return res.status(400).json({
        success: false,
        error: "userId and showOnLeaderboard are required",
      });
    }

    await db
      .collection("users")
      .doc(userId)
      .collection("gamification")
      .doc("status")
      .set(
        {
          leaderboardOptIn: showOnLeaderboard,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

    return res.status(200).json({
      success: true,
      showOnLeaderboard,
    });
  } catch (error) {
    console.error("GAMIFICATION_VISIBILITY ERROR:", error.message);
    return res.status(500).json({
      success: false,
      error: error.message || "Failed to update leaderboard visibility",
    });
  }
});

module.exports = router;
