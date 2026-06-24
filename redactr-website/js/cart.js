/**
 * Persists the chosen subscription plan in localStorage so it survives
 * navigation between pricing.html and checkout.html.
 */
const RedactrCart = (function () {
  const STORAGE_KEY = "redactr_selected_plan";

  function setPlan(plan) {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(plan));
  }

  function getPlan() {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : null;
  }

  function clearPlan() {
    localStorage.removeItem(STORAGE_KEY);
  }

  return { setPlan, getPlan, clearPlan };
})();
