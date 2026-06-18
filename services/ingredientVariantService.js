/**
 * ingredientVariantService.js
 * Self-learning ingredient variant system
 * 
 * Extracts food names from recipe titles, learns variant relationships,
 * and expands future ingredient searches with discovered variants.
 * 
 * Example:
 * - User searches: "fish"
 * - Gets recipes: "Grilled Tilapia", "Fish Stew", "Bangus Sisig", "Baked Salmon"
 * - Learns: fish → [tilapia, bangus, salmon]
 * - Next search: Expands "fish" to "tilapia recipe", "bangus recipe", "salmon recipe"
 */

const admin = require("firebase-admin");
const db = admin.firestore();

const VARIANTS_COLLECTION = "ingredient_variants";
const MIN_OCCURRENCES_TO_EXPAND = 2; // Learn variant after 2 occurrences

/**
 * Extract primary ingredient words from recipe title
 * 
 * Examples:
 * "Grilled Tilapia" → "tilapia"
 * "Fish Sinigang" → "fish"
 * "Bangus Sisig" → "bangus"
 * "Chicken Adobo with Rice" → "chicken", "rice"
 */
function extractIngredientsFromTitle(title) {
  if (!title || typeof title !== "string") return [];

  const cleaned = title.toLowerCase().trim();
  
  // Common cooking methods to remove
  const cookingMethods = [
    "grilled?", "baked?", "fried?", "steamed?", "boiled?", "roasted?",
    "sautéed?", "pan-fried?", "deep-fried?", "stewed?", "simmered?",
    "stir-fried?", "salted?", "smoked?", "braised?", "poached?"
  ];
  
  // Common descriptors to remove
  const descriptors = [
    "with", "and", "recipe", "dish", "meal", "salad", "soup", "stew",
    "casserole", "skillet", "pasta", "rice", "noodle", "bowl"
  ];

  let text = cleaned;
  
  // Remove cooking methods
  cookingMethods.forEach(method => {
    const regex = new RegExp(`\\b${method}\\b`, "gi");
    text = text.replace(regex, " ");
  });

  // Split by common separators
  const words = text
    .split(/[\s\-,&]/g)
    .map(w => w.trim())
    .filter(w => w.length > 0);

  // Filter out descriptors and generic words
  const ingredients = words.filter(word => {
    if (word.length < 2) return false;
    if (descriptors.some(d => d === word)) return false;
    if (/^\d+/.test(word)) return false; // Remove numbers
    return true;
  });

  return [...new Set(ingredients)]; // Deduplicate
}

/**
 * Learn variants from recipe search results
 * 
 * When a user searches for "fish" and gets back recipes,
 * we extract the main ingredient from each recipe title
 * and associate it with the original search term.
 */
async function learnVariantsFromRecipes(parentIngredient, recipes) {
  if (!parentIngredient || !Array.isArray(recipes) || recipes.length === 0) {
    return;
  }

  const parentNormalized = normalizeIngredient(parentIngredient);
  const extractedVariants = new Map(); // variant → count

  try {
    // Extract ingredients from all recipe titles
    recipes.forEach(recipe => {
      const recipeTitle = recipe.name || recipe.title || "";
      const ingredients = extractIngredientsFromTitle(recipeTitle);
      
      // Track ingredients found in recipes, filtering out the parent
      ingredients.forEach(ingredient => {
        const normalized = normalizeIngredient(ingredient);
        if (normalized !== parentNormalized && normalized.length > 1) {
          extractedVariants.set(
            normalized,
            (extractedVariants.get(normalized) || 0) + 1
          );
        }
      });
    });

    // Save variants to Firestore
    const variantsRef = db.collection(VARIANTS_COLLECTION).doc(parentNormalized);
    const doc = await variantsRef.get();
    const existing = doc.data() || { variants: {} };

    // Update variants, incrementing occurrence counts
    const updatedVariants = { ...existing.variants };
    extractedVariants.forEach((count, variant) => {
      const currentCount = updatedVariants[variant] || 0;
      updatedVariants[variant] = currentCount + count;
    });

    await variantsRef.set(
      {
        parentFood: parentNormalized,
        variants: updatedVariants,
        variantsList: Object.keys(updatedVariants),
        discoveredVariantsCount: Object.keys(updatedVariants).length,
        totalOccurrences: Object.values(updatedVariants).reduce((a, b) => a + b, 0),
        lastUpdated: new Date().toISOString(),
      },
      { merge: true }
    );

    console.log("INGREDIENT_VARIANT_LEARNED:", {
      parentFood: parentNormalized,
      newVariants: Object.keys(extractedVariants),
      totalVariants: Object.keys(updatedVariants).length,
    });
  } catch (error) {
    console.error("INGREDIENT_VARIANT_LEARNING_ERROR:", {
      parentIngredient,
      error: error.message,
    });
  }
}

/**
 * Normalize ingredient name for consistent lookups
 */
function normalizeIngredient(ingredient) {
  if (!ingredient) return "";
  return ingredient
    .toLowerCase()
    .trim()
    .replace(/s$/, ""); // Remove plural 's' for matching
}

/**
 * Get all known variants for an ingredient
 */
async function getVariantsForIngredient(ingredient) {
  const normalized = normalizeIngredient(ingredient);
  
  try {
    const doc = await db.collection(VARIANTS_COLLECTION).doc(normalized).get();
    
    if (!doc.exists) {
      return { ingredient: normalized, variants: [], found: false };
    }

    const data = doc.data();
    // Only return variants with minimum occurrences
    const activatedVariants = Object.entries(data.variants || {})
      .filter(([_, count]) => count >= MIN_OCCURRENCES_TO_EXPAND)
      .map(([variant, _]) => variant);

    return {
      ingredient: normalized,
      variants: activatedVariants,
      found: true,
      totalVariants: data.variantsList?.length || 0,
      discoveryHistory: data.variants || {},
    };
  } catch (error) {
    console.error("GET_VARIANTS_ERROR:", {
      ingredient,
      error: error.message,
    });
    return { ingredient: normalized, variants: [], error: true };
  }
}

/**
 * Generate expanded search queries from an ingredient
 * 
 * Instead of just searching "fish recipe",
 * search for ["fish recipe", "tilapia recipe", "bangus recipe", "salmon recipe"]
 */
async function expandIngredientSearches(ingredient, searchTemplates = []) {
  const variants = await getVariantsForIngredient(ingredient);
  const ingredients = [ingredient, ...variants.variants];

  // Default templates if none provided
  const templates = searchTemplates.length > 0 ? searchTemplates : [
    "{ingredient} recipe",
    "{ingredient} healthy",
    "{ingredient} low sodium",
  ];

  // Generate all combinations
  const queries = [];
  ingredients.forEach(ing => {
    templates.forEach(template => {
      const query = template.replace("{ingredient}", ing);
      queries.push(query);
    });
  });

  return {
    baseIngredient: ingredient,
    expandedIngredients: ingredients,
    variantCount: variants.variants.length,
    queries,
  };
}

/**
 * Find similar recipes based on shared ingredients
 * Used for recipe replacement suggestions
 * 
 * When user clicks "Grilled Tilapia", find other recipes with tilapia/fish
 */
async function findSimilarRecipes(selectedRecipe, allRecipes, maxSuggestions = 5) {
  if (!selectedRecipe || !Array.isArray(allRecipes)) {
    return [];
  }

  try {
    // Extract ingredients from selected recipe title
    const selectedIngredients = new Set(
      extractIngredientsFromTitle(selectedRecipe.name || selectedRecipe.title || "")
    );

    if (selectedIngredients.size === 0) {
      return [];
    }

    // Score all other recipes by shared ingredients
    const scored = allRecipes
      .filter(recipe => 
        (recipe.recipeId || recipe.foodId) !== (selectedRecipe.recipeId || selectedRecipe.foodId)
      )
      .map(recipe => {
        const recipeIngredients = new Set(
          extractIngredientsFromTitle(recipe.name || recipe.title || "")
        );
        
        // Calculate similarity
        const shared = new Set([...selectedIngredients].filter(x => recipeIngredients.has(x)));
        const similarity = shared.size / Math.max(selectedIngredients.size, recipeIngredients.size);
        
        return {
          recipe,
          similarity,
          sharedIngredients: Array.from(shared),
        };
      })
      .filter(item => item.similarity > 0) // Only recipes with shared ingredients
      .sort((a, b) => b.similarity - a.similarity)
      .slice(0, maxSuggestions);

    return scored.map(item => ({
      ...item.recipe,
      similarityScore: Math.round(item.similarity * 100),
      sharedIngredients: item.sharedIngredients,
    }));
  } catch (error) {
    console.error("FIND_SIMILAR_RECIPES_ERROR:", {
      selectedRecipe: selectedRecipe?.name,
      error: error.message,
    });
    return [];
  }
}

/**
 * Extract and normalize food name for variant tracking
 * 
 * "Grilled Tilapia" → "tilapia"
 * "Fish Sinigang" → "fish"
 */
function extractPrimaryFoodName(recipeName) {
  const ingredients = extractIngredientsFromTitle(recipeName);
  return ingredients.length > 0 ? ingredients[0] : null;
}

/**
 * Get variant expansion with metadata
 */
async function getVariantExpansionData(ingredient) {
  const variants = await getVariantsForIngredient(ingredient);
  
  return {
    baseIngredient: ingredient,
    expanded: {
      ingredients: [ingredient, ...variants.variants],
      count: variants.variants.length + 1,
    },
    discovery: {
      variantCount: variants.discoveryHistory ? Object.keys(variants.discoveryHistory).length : 0,
      totalOccurrences: variants.discoveryHistory ? 
        Object.values(variants.discoveryHistory).reduce((a, b) => a + b, 0) : 0,
    },
  };
}

module.exports = {
  learnVariantsFromRecipes,
  getVariantsForIngredient,
  expandIngredientSearches,
  findSimilarRecipes,
  extractIngredientsFromTitle,
  extractPrimaryFoodName,
  normalizeIngredient,
  getVariantExpansionData,
};
