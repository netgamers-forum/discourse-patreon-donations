import Controller from "@ember/controller";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default Controller.extend({
  isBackfilling: false,
  backfillMessage: null,
  backfillError: null,

  @action
  backfillHistory() {
    this.setProperties({
      isBackfilling: true,
      backfillMessage: null,
      backfillError: null
    });

    ajax("/admin/plugins/patreon-donations/backfill", { type: "POST" })
      .then((result) => {
        this.set("backfillMessage", result.message || "Backfill completed successfully");
      })
      .catch((error) => {
        this.set("backfillError", error.jqXHR?.responseJSON?.error || "Backfill failed");
        popupAjaxError(error);
      })
      .finally(() => {
        this.set("isBackfilling", false);
      });
  }
});
