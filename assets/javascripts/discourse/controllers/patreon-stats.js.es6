import Controller from "@ember/controller";
import { computed } from "@ember/object";

export default Controller.extend({
  hasStats: computed("model.stats", function() {
    return !!this.get("model.stats");
  }),

  patronCount: computed("model.stats.patron_count", function() {
    return this.get("model.stats.patron_count") || 0;
  }),

  monthlyEstimate: computed("model.stats.monthly_estimate", function() {
    const amount = this.get("model.stats.monthly_estimate") || 0;
    return amount.toFixed(2);
  }),

  lastMonthTotal: computed("model.stats.last_month_total", function() {
    const amount = this.get("model.stats.last_month_total") || 0;
    return amount.toFixed(2);
  }),

  updatedAt: computed("model.stats.updated_at", function() {
    const timestamp = this.get("model.stats.updated_at");
    return timestamp ? new Date(timestamp).toLocaleString() : "";
  }),

  hasMonthlyHistory: computed("model.monthly_history", function() {
    const history = this.get("model.monthly_history");
    return history && history.length > 0;
  }),

  monthlyHistory: computed("model.monthly_history", function() {
    const history = this.get("model.monthly_history") || [];
    return history.map(item => ({
      ...item,
      monthName: this.getMonthName(item.month),
      formattedAmount: item.total_amount.toFixed(2)
    }));
  }),

  getMonthName(monthNumber) {
    const months = [
      "January", "February", "March", "April", "May", "June",
      "July", "August", "September", "October", "November", "December"
    ];
    return months[monthNumber - 1] || "";
  }
});
