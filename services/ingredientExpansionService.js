/**
 * ingredientExpansionService.js
 * 
 * Expands INDIVIDUAL INGREDIENTS into FatSecret food variants.
 * Handles caching to eliminate repeated API calls.
 * 
 * IMPORTANT: This service works with INDIVIDUAL INGREDIENTS ONLY
 * - "chicken" (not "Chicken Adobo")
 * - "rice" (not "Rice with vegetables")
 * - "cabbage" (not "Stir-fried cabbage with seasoning")
 * 
 * Each individual ingredient is searched separately on FatSecret,
 * and nutrition values are summed at the meal level.
 * 
 * EXAMPLE USAGE:
 * 
 * // First call: Searches FatSecret and caches
 * const variants = await expandIngredient("chicken");
 * // Returns: ["Chicken Breast", "Grilled Chicken", "Fried Chicken", "Chicken Tenderloin", ...]
 * 
 * // Pick random variant for meal variety
 * const variant1 = await pickRandomVariant("chicken"); // "Grilled Chicken"
 * const variant2 = await pickRandomVariant("chicken"); // "Fried Chicken" (next time, might be different)
 * 
 * // Second call: Uses cached data instantly
 * const variants2 = await expandIngredient("chicken");
 * // Returns same variants from cache (no API call)
 * 
 * CACHING:
 * - 30-day TTL (refreshes automatically after 30 days)
 * - Stored in Firestore: ingredient_expansions collection
 * - Format: { ingredient: "chicken", variants: [...], cachedAt: "2026-06-18..." }
 */

const { db } = require("../firebase/admin");
const fatSecretBridge = require("./fatSecretBridgeService");

const INGREDIENT_CACHE_COLLECTION = "ingredient_expansions";
const INGREDIENT_CACHE_TTL_MS = 1000 * 60 * 60 * 24 * 30; // 30 days

/**
 * Get cached ingredient expansion or fetch from FatSecret
 */
async function expandIngredient(ingredient) {
  if (!ingredient || typeof ingredient !== "string") return [];

  const normalized = ingredient.toLowerCase().trim();
  const cacheRef = db.collection(INGREDIENT_CACHE_COLLECTION).doc(normalized);

  try {
    const snap = await cacheRef.get();
    if (snap.exists) {
      const cached = snap.data();
      if (isCacheFresh(cached)) {
        return cached.variants || [];
      }
    }
  } catch (error) {
    console.error("INGREDIENT_CACHE_READ_ERROR:", { ingredient, error: error.message });
  }

  // Cache miss or stale - fetch from FatSecret
  const variants = await searchFatSecretForIngredient(normalized);
  
  // Cache the results
  try {
    await cacheRef.set(
      {
        ingredient: normalized,
        variants,
        cachedAt: new Date().toISOString(),
      },
      { merge: true }
    );
  } catch (error) {
    console.error("INGREDIENT_CACHE_WRITE_ERROR:", { ingredient, error: error.message });
  }

  return variants;
}

/**
 * Search FatSecret for individual ingredient and return specific variants
 */
async function searchFatSecretForIngredient(ingredient, limit = 8) {
  try {
    const result = await fatSecretBridge.searchFoods(ingredient, 0);
    const foods = result.foods || [];

    // Extract unique food names from search results
    const variants = [];
    const seen = new Set();

    for (const food of foods.slice(0, limit)) {
      const name = food.food_name || food.name;
      if (!name || seen.has(name.toLowerCase())) continue;
      
      seen.add(name.toLowerCase());
      variants.push(name);
    }

    return variants.length > 0 ? variants : [ingredient];
  } catch (error) {
    console.error("FATSECRET_INGREDIENT_SEARCH_ERROR:", { ingredient, error: error.message });
    // Fallback: return the ingredient itself
    return [ingredient];
  }
}

/**
 * Pick a random variant from cached ingredient expansions
 */
async function pickRandomVariant(ingredient) {
  const variants = await expandIngredient(ingredient);
  if (!Array.isArray(variants) || variants.length === 0) {
    return ingredient;
  }
  const randomIndex = Math.floor(Math.random() * variants.length);
  return variants[randomIndex];
}

/**
 * Pick multiple random variants for the same ingredient across different meal times
 * Useful to ensure variety within a day
 */
async function pickVariantsForDay(ingredient, count = 3) {
  const variants = await expandIngredient(ingredient);
  if (!Array.isArray(variants) || variants.length === 0) {
    return Array(count).fill(ingredient);
  }

  const picked = [];
  const shuffled = [...variants].sort(() => Math.random() - 0.5);
  
  for (let i = 0; i < count; i++) {
    picked.push(shuffled[i % shuffled.length]);
  }
  
  return picked;
}

/**
 * Pre-warm the cache for common meal ingredients
 * Call this on app startup to populate cache
 */
async function prewarmCache(ingredients) {
  const results = [];
  
  for (const ingredient of ingredients) {
    try {
      const variants = await expandIngredient(ingredient);
      results.push({ ingredient, count: variants.length });
    } catch (error) {
      console.error("PREWARM_CACHE_ERROR:", { ingredient, error: error.message });
    }
  }

  return results;
}

function isCacheFresh(cached) {
  if (!cached || !cached.cachedAt) return false;
  const cachedAt = new Date(cached.cachedAt).getTime();
  return Date.now() - cachedAt < INGREDIENT_CACHE_TTL_MS;
}

/**
 * Clear ingredient cache (useful for testing or manual refresh)
 */
async function clearCache(ingredient) {
  try {
    if (ingredient) {
      const normalized = ingredient.toLowerCase().trim();
      await db.collection(INGREDIENT_CACHE_COLLECTION).doc(normalized).delete();
    } else {
      // Clear entire cache
      const snap = await db.collection(INGREDIENT_CACHE_COLLECTION).get();
      const batch = db.batch();
      snap.docs.forEach(doc => batch.delete(doc.ref));
      await batch.commit();
    }
    return true;
  } catch (error) {
    console.error("CACHE_CLEAR_ERROR:", { ingredient, error: error.message });
    return false;
  }
}

module.exports = {
  expandIngredient,
  pickRandomVariant,
  pickVariantsForDay,
  prewarmCache,
  clearCache,
  searchFatSecretForIngredient,
};
