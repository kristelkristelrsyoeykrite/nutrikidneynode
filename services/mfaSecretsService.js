/**
 * MFA Secrets Management Service
 * Stores MFA secrets in a protected collection with encryption
 * This prevents exposure of MFA secrets even if user profile data is exposed
 */

const { admin, db } = require('../firebase/admin');
const crypto = require('crypto');

/**
 * MFA_SECRETS collection stores encrypted MFA secrets separately
 * This collection should have strict Firestore rules:
 * - Only authenticated users can read their own secrets
 * - Only the backend can write
 * - Secrets are stored encrypted
 */
const MFA_SECRETS_COLLECTION = 'mfa_secrets';

/**
 * Encrypt a secret using the application encryption key
 * @param {string} secret - Plain text secret
 * @returns {string} Encrypted secret
 */
function encryptSecret(secret) {
  const encryptionKey = process.env.ENCRYPTION_KEY;
  if (!encryptionKey) {
    throw new Error('ENCRYPTION_KEY not configured');
  }

  try {
    const iv = crypto.randomBytes(16);
    const cipher = crypto.createCipheriv(
      'aes-256-cbc',
      Buffer.from(encryptionKey, 'hex'),
      iv,
    );

    let encrypted = cipher.update(secret, 'utf8', 'hex');
    encrypted += cipher.final('hex');

    // Return IV + encrypted data
    return `${iv.toString('hex')}:${encrypted}`;
  } catch (error) {
    console.error('Failed to encrypt secret:', error.message);
    throw new Error('Encryption failed');
  }
}

/**
 * Decrypt a secret using the application encryption key
 * @param {string} encryptedData - Encrypted data (IV:ciphertext)
 * @returns {string} Decrypted secret
 */
function decryptSecret(encryptedData) {
  const encryptionKey = process.env.ENCRYPTION_KEY;
  if (!encryptionKey) {
    throw new Error('ENCRYPTION_KEY not configured');
  }

  try {
    const [ivHex, encryptedHex] = encryptedData.split(':');
    const iv = Buffer.from(ivHex, 'hex');
    const decipher = crypto.createDecipheriv(
      'aes-256-cbc',
      Buffer.from(encryptionKey, 'hex'),
      iv,
    );

    let decrypted = decipher.update(encryptedHex, 'hex', 'utf8');
    decrypted += decipher.final('utf8');

    return decrypted;
  } catch (error) {
    console.error('Failed to decrypt secret:', error.message);
    throw new Error('Decryption failed');
  }
}

/**
 * Save MFA secret in protected collection
 * @param {string} uid - User ID
 * @param {string} secret - MFA secret (will be encrypted)
 * @param {string} type - Type of secret (e.g., 'authenticator_temp', 'authenticator')
 * @returns {Promise<void>}
 */
async function saveMfaSecret(uid, secret, type = 'authenticator') {
  if (!uid || !secret) {
    throw new Error('User ID and secret are required');
  }

  try {
    const encryptedSecret = encryptSecret(secret);

    await db.collection(MFA_SECRETS_COLLECTION).doc(uid).set(
      {
        type,
        secretHash: crypto.createHash('sha256').update(secret).digest('hex'),
        // Do NOT store the secret itself unencrypted
        // Store encrypted secret
        secret: encryptedSecret,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  } catch (error) {
    console.error('Failed to save MFA secret:', error.message);
    throw error;
  }
}

/**
 * Get MFA secret from protected collection
 * @param {string} uid - User ID
 * @returns {Promise<string|null>} Decrypted MFA secret or null if not found
 */
async function getMfaSecret(uid) {
  if (!uid) {
    throw new Error('User ID is required');
  }

  try {
    const doc = await db.collection(MFA_SECRETS_COLLECTION).doc(uid).get();

    if (!doc.exists) {
      return null;
    }

    const data = doc.data();
    if (!data.secret) {
      return null;
    }

    // Decrypt the secret before returning
    const decryptedSecret = decryptSecret(data.secret);
    return decryptedSecret;
  } catch (error) {
    console.error('Failed to get MFA secret:', error.message);
    throw error;
  }
}

/**
 * Save temporary MFA secret during setup
 * @param {string} uid - User ID
 * @param {string} secret - Temporary MFA secret
 * @returns {Promise<void>}
 */
async function saveTempMfaSecret(uid, secret) {
  return saveMfaSecret(uid, secret, 'authenticator_temp');
}

/**
 * Get temporary MFA secret
 * @param {string} uid - User ID
 * @returns {Promise<string|null>}
 */
async function getTempMfaSecret(uid) {
  if (!uid) {
    throw new Error('User ID is required');
  }

  try {
    const doc = await db.collection(MFA_SECRETS_COLLECTION).doc(uid).get();

    if (!doc.exists) {
      return null;
    }

    const data = doc.data();

    // Only return if it's a temporary secret
    if (data.type !== 'authenticator_temp') {
      return null;
    }

    if (!data.secret) {
      return null;
    }

    const decryptedSecret = decryptSecret(data.secret);
    return decryptedSecret;
  } catch (error) {
    console.error('Failed to get temp MFA secret:', error.message);
    throw error;
  }
}

/**
 * Promote temporary MFA secret to permanent
 * @param {string} uid - User ID
 * @returns {Promise<void>}
 */
async function promoteTempMfaSecret(uid) {
  if (!uid) {
    throw new Error('User ID is required');
  }

  try {
    const tempSecret = await getTempMfaSecret(uid);
    if (!tempSecret) {
      throw new Error('No temporary MFA secret found');
    }

    // Save as permanent
    await saveMfaSecret(uid, tempSecret, 'authenticator');

    // Clear temp flag
    await db.collection(MFA_SECRETS_COLLECTION).doc(uid).update({
      type: 'authenticator',
      promotedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (error) {
    console.error('Failed to promote MFA secret:', error.message);
    throw error;
  }
}

/**
 * Delete MFA secret
 * @param {string} uid - User ID
 * @returns {Promise<void>}
 */
async function deleteMfaSecret(uid) {
  if (!uid) {
    throw new Error('User ID is required');
  }

  try {
    await db.collection(MFA_SECRETS_COLLECTION).doc(uid).delete();
  } catch (error) {
    console.error('Failed to delete MFA secret:', error.message);
    throw error;
  }
}

/**
 * Verify that the user has a temporary MFA secret setup
 * @param {string} uid - User ID
 * @returns {Promise<boolean>}
 */
async function hasTempMfaSecret(uid) {
  const secret = await getTempMfaSecret(uid);
  return !!secret;
}

/**
 * Verify that the user has a permanent MFA secret setup
 * @param {string} uid - User ID
 * @returns {Promise<boolean>}
 */
async function hasPermanentMfaSecret(uid) {
  if (!uid) return false;

  try {
    const doc = await db.collection(MFA_SECRETS_COLLECTION).doc(uid).get();

    if (!doc.exists) {
      return false;
    }

    const data = doc.data();
    return data.type === 'authenticator' && !!data.secret;
  } catch (error) {
    console.error('Failed to check MFA secret:', error.message);
    return false;
  }
}

module.exports = {
  saveMfaSecret,
  getMfaSecret,
  saveTempMfaSecret,
  getTempMfaSecret,
  promoteTempMfaSecret,
  deleteMfaSecret,
  hasTempMfaSecret,
  hasPermanentMfaSecret,
  encryptSecret,
  decryptSecret,
  MFA_SECRETS_COLLECTION,
};
