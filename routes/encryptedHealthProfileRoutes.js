const express = require("express");
const { admin, db, auth } = require("../firebase/admin");
const {
  encryptHealthProfile,
  decryptHealthProfile,
} = require("../utils/encryption");

const router = express.Router();

async function authenticateFirebaseUser(req, res, next) {
  try {
    const authorization = req.headers.authorization || "";
    const match = authorization.match(/^Bearer (.+)$/);

    if (!match) {
      return res.status(401).json({
        success: false,
        error: "Missing Firebase ID token.",
      });
    }

    req.auth = await auth.verifyIdToken(match[1]);
    return next();
  } catch (error) {
    return res.status(401).json({
      success: false,
      error: "Invalid Firebase ID token.",
    });
  }
}

function getAuthenticatedUid(req) {
  return req.auth && req.auth.uid;
}

router.post("/profile", authenticateFirebaseUser, async (req, res) => {
  try {
    const uid = getAuthenticatedUid(req);
    const now = admin.firestore.FieldValue.serverTimestamp();
    const docRef = db.collection("users").doc(uid).collection("healthProfile").doc("main");
    const existingDoc = await docRef.get();
    const profileToSave = {
      ...req.body,
      uid,
      updatedAt: now,
    };

    if (!existingDoc.exists) {
      profileToSave.createdAt = now;
    }

    const encryptedProfile = encryptHealthProfile(profileToSave);

    await docRef.set(encryptedProfile, { merge: true });

    return res.status(200).json({
      success: true,
      path: `users/${uid}/healthProfile/main`,
    });
  } catch (error) {
    console.error("Encrypted health profile save failed:", error.message);
    return res.status(500).json({
      success: false,
      error: "Failed to save health profile.",
    });
  }
});

router.put("/profile", authenticateFirebaseUser, async (req, res) => {
  try {
    const uid = getAuthenticatedUid(req);
    const docRef = db.collection("users").doc(uid).collection("healthProfile").doc("main");
    const encryptedProfile = encryptHealthProfile({
      ...req.body,
      uid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await docRef.set(encryptedProfile, { merge: true });

    return res.status(200).json({
      success: true,
      path: `users/${uid}/healthProfile/main`,
    });
  } catch (error) {
    console.error("Encrypted health profile update failed:", error.message);
    return res.status(500).json({
      success: false,
      error: "Failed to update health profile.",
    });
  }
});

router.get("/profile", authenticateFirebaseUser, async (req, res) => {
  try {
    const uid = getAuthenticatedUid(req);
    const docRef = db.collection("users").doc(uid).collection("healthProfile").doc("main");
    const snapshot = await docRef.get();

    if (!snapshot.exists) {
      return res.status(404).json({
        success: false,
        error: "Health profile not found.",
      });
    }

    const decryptedProfile = decryptHealthProfile(snapshot.data());

    return res.status(200).json({
      success: true,
      profile: decryptedProfile,
      path: `users/${uid}/healthProfile/main`,
    });
  } catch (error) {
    console.error("Encrypted health profile read failed:", error.message);
    return res.status(500).json({
      success: false,
      error: "Failed to read health profile.",
    });
  }
});

module.exports = router;
