const express = require("express");
const router = express.Router();
const { admin, db } = require("../firebase/admin");

//////////////////// STEP 1 - Just collect data ////////////////////
router.post("/step1", async (req, res) => {
  console.log("Step 1 received:", req.body);
  
  try {
    res.json({
      success: true,
      message: "Step 1 data received (waiting for final submission)",
    });
  } catch (error) {
    console.error("Step 1 Error:", error.message);
    res.status(400).json({
      success: false,
      error: error.message
    });
  }
});

//////////////////// STEP 2 - Just collect data ////////////////////
router.post("/step2", async (req, res) => {
  console.log("Step 2 received:", req.body);
  
  try {
    res.json({
      success: true,
      message: "Step 2 data received (waiting for final submission)",
      data: req.body,
    });
  } catch (error) {
    console.error("Step 2 Error:", error.message);
    res.status(400).json({
      success: false,
      error: error.message
    });
  }
});


//////////////// STEP 3 - Just collect data ///////////////////////////
router.post("/step3", async (req, res) => {
  console.log("Step 3 received:", req.body);

  try {
    res.json({
      success: true,
      message: "Step 3 data received (waiting for final submission)",
      data: req.body
    });
  } catch (error) {
    console.error("Step 3 Error:", error.message);
    res.status(400).json({
      success: false,
      error: error.message
    });
  }
});

//////////////////// STEP 4 - Just collect data //////////////////////

router.post("/step4", async (req, res) => {
  console.log("Step 4 received:", req.body);

  try {
    res.json({
      success: true,
      message: "Step 4 data received (waiting for final submission)",
      data: req.body
    });
  } catch (error) {
    console.error("Step 4 Error:", error.message);
    res.status(400).json({
      success: false,
      error: error.message
    });
  }
});

////////////// FINAL SUBMIT - Saves All Data to Firestore //////////////

router.post("/submit-all", async (req, res) => {
  console.log("Final submission received - saving to database");

  const { userId, step1, step2, step3, step4 } = req.body;

  try {
    // 1. Save User data
    await db.collection("users").doc(userId).set({
      uid: userId,
      childFullName: step1?.name,
      dateOfBirth: step1?.dob,
      gender: step1?.gender,
      preferredMeasurementSystem: step3?.preferredMeasurement,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 2. Create MedicalProfile and get its ID
    const medicalProfileDoc = await db.collection("medicalProfile").add({
      userId: userId,
      kidneyDiseaseType: step1?.kidneyType,
      ckdStage: step1?.ckdStage,
      dateOfDiagnosis: step1?.diagnosisDate,
      onDialysis: step2?.isOnDialysis,
      treatmentFrequency: step2?.treatmentFrequency,
      fluidRestriction: step3?.fluidRestriction,
      physicalActivityLevel: step3?.physicalActivityLevel,
      allergies: step2?.allergies,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    
    const medicalProfileId = medicalProfileDoc.id;
    console.log("Medical Profile created:", medicalProfileId);

    // 3. Create AnthropometricData
    const anthropometricDoc = await db.collection("anthropometrics").add({
      userId: userId,
      medicalProfileId: medicalProfileId,
      height: step1?.height,
      weight: step1?.weight,
      dryWeight: step1?.dryWeight,
      MUAC: step1?.muac,
      date: admin.firestore.FieldValue.serverTimestamp(),
    });
    
    console.log("Anthropometric data created:", anthropometricDoc.id);

    // 4. Create LabResults
    // Build lab result payload safely (avoid undefined values)
    const labResultPayload = {
      userId: userId,
      medicalProfileId: medicalProfileId,
      testName: "Blood Test",
      date: step4?.resultDate ?? null,
      creatinine: parseFloat(step4?.creatinine) || null,
      potassium: parseFloat(step4?.potassium) || null,
      phosphorus: parseFloat(step4?.phosphorus) || null,
      sodium: parseFloat(step4?.sodium) || null,
      calcium: parseFloat(step4?.calcium) || null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    const labResultDoc = await db.collection("labResults").add(labResultPayload);
    
    console.log("Lab Result created:", labResultDoc.id);

    // 5. Update user document with references
    await db.collection("users").doc(userId).update({
      medicalProfileId: medicalProfileId,
    });

    console.log("FINAL SUBMIT: All collections created for user:", userId);

    res.status(200).json({
      success: true,
      message: "All data saved successfully to database",
      userId: userId,
      medicalProfileId: medicalProfileId,
    });
  } catch (error) {
    console.error("FINAL SUBMIT ERROR:", error.message);
    res.status(400).json({
      success: false,
      error: error.message
    });
  }
});

module.exports = router;